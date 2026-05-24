# Long-term memory (Honcho)

This Hermes deployment uses [Honcho](https://github.com/plastic-labs/honcho)
as its memory backend. Honcho is an AI-native memory server that derives
durable conclusions about peers (users, agents) from raw conversation
transcripts, then makes them queryable via a small set of APIs.

This doc covers the **client side** — how Hermes is configured to talk to
Honcho, what each tuning knob does, and the guardrails that keep memory
useful instead of noisy.

For the **server side** (postgres, redis, deriver, image builds, auth,
backup/restore, runbook), see [apnex/honcho](https://github.com/apnex/honcho).
The contract between this repo and that one is a single URL —
`baseUrl` in `honcho.json.tpl` — plus the assumption that whatever
answers there speaks the Honcho REST API.

## The two files

| File | Owned by | Purpose |
|------|----------|---------|
| `manifests/config.yaml.tpl` (`honcho:` block) | hermes-core | Transport bootstrap. Only `base_url` is consulted. |
| `manifests/honcho.json.tpl` | Honcho plugin | All tuning — cadences, depth, recall mode, peer identity, write frequency. |

The split exists because the two files match two different upstream schemas
maintained by two different codebases. Tuning lives in `honcho.json.tpl`
exclusively; the `honcho:` block in `config.yaml.tpl` is a legacy shim
preserved only because the plugin needs *some* way to find the server URL
before it can read its own config file.

For the rollout mechanics — how an edit to either file reaches the running
pod — see [`../manifests/README.md`](../manifests/README.md).

## Tuning knobs

Every field in `honcho.json.tpl` is documented inline via the
`_defaults_rationale` block in the file itself. Promoted here for searchability:

### Identity

| Knob | Default | Why |
|------|---------|-----|
| `workspace` | `hermes` | Top-level Honcho tenant. One Hermes deployment = one workspace. |
| `peerName` | `@HERMES_PEER_NAME@` (Secret) | Stable identity for the human peer. Rendered from `hermes-secrets`. |
| `aiPeer` | `hermes` | Stable identity for the agent peer. Lets Honcho distinguish user-said-X from agent-said-X. |
| `pinPeerName` | `true` | Forces `peerName` to win over gateway-supplied runtime user IDs (e.g. Discord's 18-digit numeric ID). Without this, the same human ends up as multiple peer records across gateways, fragmenting the profile. |

### Recall

| Knob | Default | Why |
|------|---------|-----|
| `recallMode` | `hybrid` | Use both auto-injected context AND on-demand tool calls. `inject`-only is too coarse; `tools`-only loses the safety net. |
| `contextCadence` | `10` | Refresh the auto-injected context block every 10 turns. Halves token churn vs. the SDK default of 5. The peer profile is stable enough that mid-session refresh isn't usually critical. |
| `contextTokens` | `800` | Hard cap on the auto-injected memory block. Forces Honcho to send a *synthesized* representation rather than a raw observation log. Default 2000 produces 4KB+ firehoses on active peers, most of which is noise. |

### Derivation (the dialectic layer)

| Knob | Default | Why |
|------|---------|-----|
| `dialecticCadence` | `10` | Fire dialectic reasoning every 10 turns. This is an extra LLM round-trip per fire; this cadence balances quality against cost. |
| `dialecticDepth` | `3` | audit + synthesis + reconciliation. Depth 3 adds a reconciliation pass that de-dupes and resolves contradictions in derived conclusions — this is the surface that filters meta-chatter (`"user discussed X"`) from real preferences (`"user prefers X"`). Depths 1–2 skip reconciliation. |
| `dialecticReasoningLevel` | `medium` | Auto-escalates to `high` via Honcho's `reasoning_heuristic` when needed. Bump the default to `high` only if depth=3 reconciliation visibly fails to suppress meta-chatter dupes across sessions. |

### Write path

| Knob | Default | Why |
|------|---------|-----|
| `writeFrequency` | `async` | Don't block the agent loop on Honcho writes. The deriver consumes the queue out-of-band. |
| `saveMessages` | `true` | Send full conversation transcripts to Honcho. Required for derivation to have something to derive *from*. |
| `sessionStrategy` | `per-session` | Each Hermes invocation gets an isolated Honcho session. Gateway sessions (Discord, Telegram) override this to `per-chat` automatically. |

## The "observations are not commitments" guardrail

Honcho's `dialectic` layer derives conclusions from the conversation transcript.
That includes observations like:

- `"user discussed the seed-config initContainer in session 2026-05-24"`
- `"user mentioned wanting to write a guardrail skill"`
- `"user asked about the GitOps geometry"`

These are **factual observations of what happened**, not directives. But they
can be injected into a future session's context block and read by the agent
as if they were a TODO list. That produces the failure mode where the agent
opens a new session by enumerating "open items" that were never actually
commitments — just things that came up in conversation.

The mitigation is layered:

1. **`contextTokens: 800`** caps the volume of raw observation that can leak
   through. Forces synthesis.
2. **`dialecticDepth: 3`** adds reconciliation, which is supposed to collapse
   `"user discussed X"` into `"user is interested in X"` or drop it entirely
   if it doesn't recur. This is the most important knob for noise control.
3. **Agent-side discipline** (you, reading this): when Honcho-derived context
   surfaces a topic, treat it as background ("this is something we've talked
   about") not as a commitment ("this is something we promised to do"). The
   user's *current message* is the authoritative source of intent for any
   given turn. Honcho's role is to keep you from re-asking the user things
   they've already told you, not to set your agenda.

If the agent starts opening sessions by enumerating "items we left open"
that the user didn't actually flag as open, the first lever is to verify
`dialecticDepth` is still 3 (drift check via the [edit loop](../manifests/README.md#editing-a-template)),
then check whether the reconciliation pass is producing dupes.

## When Honcho is unavailable

If the Honcho server is down or unreachable:

- **The agent still runs.** The plugin fails open — Hermes operates with its
  static memory (`config.yaml.tpl` `memory.memory_char_limit` /
  `user_char_limit`) and whatever's in the current session context.
- **Writes are dropped, not queued indefinitely.** Reconnect by restoring
  the server; missed writes are not retroactively replayed. Honcho rebuilds
  representations from the next batch of observations.
- **Recall tool calls return errors that the agent surfaces.** This is
  intentional — silent recall failure is worse than a visible error, because
  the agent would otherwise act on stale or absent memory thinking it had
  fresh data.

To diagnose:

```sh
# Server reachable from the pod?
kubectl -n hermes exec deploy/hermes -- \
  curl -s http://honcho.honcho.svc.cluster.local:8000/health

# Plugin config matches what's on disk?
kubectl -n hermes exec deploy/hermes -- cat /opt/data/honcho.json

# Deriver caught up?
kubectl -n honcho logs deploy/honcho-deriver --tail=30
```

Server-side troubleshooting beyond reachability lives in
[apnex/honcho/docs/runbook.md](https://github.com/apnex/honcho/blob/main/docs/runbook.md).

## What this doc does NOT cover

- **Postgres / redis / deriver operations.** Server-side. See the honcho repo.
- **Honcho image builds, version upgrades, auth posture (JWT mode).** Server-side.
- **The Honcho REST API surface itself.** Upstream docs at
  [plastic-labs/honcho](https://github.com/plastic-labs/honcho) are canonical.
- **Hermes-core memory** (`memory.memory_char_limit`, `memory.user_char_limit`
  in `config.yaml.tpl`). That's a separate, static-file memory layer that
  operates independently of Honcho. Honcho is *additive* — it doesn't replace
  Hermes's built-in memory, it augments it.
