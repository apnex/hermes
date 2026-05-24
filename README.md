# hermes

GitOps-friendly deployment of the [Hermes agent](https://github.com/NousResearch/hermes-agent)
for any Kubernetes cluster. Generic, reusable — no operator-specific values committed.

Exposes Hermes's **OpenAI-compatible API** on `:8642` (bearer-token guarded) and **web
dashboard** on `:9119`.

**Requirements:** Kubernetes (with `kubectl` access) + an OpenAI-compatible LLM endpoint
(e.g. a LiteLLM router).

## Install

### 1. Clone

```sh
git clone https://github.com/apnex/hermes && cd hermes
```

### 2. Set the Secret

Edit the four values to match your LLM endpoint, then run `./set-secret`:

```sh
export LITELLM_BASE_URL="https://your-llm-router/v1"   # OpenAI-compatible endpoint (with /v1)
export LITELLM_MODEL="your-default-model"              # main model alias
export LITELLM_API_KEY="your-llm-api-key"              # provider key
export API_SERVER_KEY="$(openssl rand -hex 32)"        # random bearer token for :8642

./set-secret
```

Creates the `hermes` namespace and applies the `hermes-secrets` Secret.

### 3. Deploy

**Pick one.**

**(a) Direct — no GitOps:**

```sh
kubectl apply -k manifests/
```

Re-run after any edits.

**(b) With Argo CD:**

```sh
kubectl apply -f - <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: hermes
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/apnex/hermes
    targetRevision: main
    path: manifests
  destination:
    server: https://kubernetes.default.svc
    namespace: hermes
  syncPolicy:
    automated: { selfHeal: true, prune: true }
    syncOptions: [CreateNamespace=true]
EOF
```

### 4. Verify

```sh
kubectl -n hermes port-forward svc/hermes 8642:8642 &
curl -H "Authorization: Bearer $API_SERVER_KEY" http://localhost:8642/v1/models
```

Should list your router's models.

## Interact with the agent

`./hermes-tui` opens an interactive Hermes session inside the deployed pod (shares the
agent's skills, sessions, memory):

```sh
./hermes-tui                       # open the TUI
./hermes-tui chat -q "say hi"      # one-shot subcommand passthrough
```

## Optional: Discord gateway

Wire a Hermes bot that responds to your Discord DMs (voice-note transcription
included). One extra env var to `./set-secret` — that's it.

### 1. Create a Discord bot

1. Open **https://discord.com/developers/applications** → **New Application** → name it.
2. Sidebar → **Bot** → **Reset Token** → copy the token (you only see it once).
3. Same page → **Privileged Gateway Intents** → toggle ✅ **MESSAGE CONTENT INTENT** → **Save**.
4. Sidebar → **OAuth2** → **URL Generator**:
   - Scopes: ✅ `bot`, ✅ `applications.commands`
   - Bot permissions: ✅ View Channels, ✅ Send Messages, ✅ Read Message History,
     ✅ Add Reactions, ✅ Create Public Threads
5. Open the generated URL in a browser → invite the bot to a server you control
   (a personal playground server is fine).

### 2. Find your own Discord user ID

The bot ignores DMs from any user not on its allowlist (security default — no
unauthenticated access). To allow yourself:

1. Discord client → **User Settings** → **Advanced** → toggle **Developer Mode** ON.
2. Right-click your own avatar → **Copy User ID** (an 18-digit number).

For multiple users, comma-separate (e.g. `111111111111111111,222222222222222222`).

### 3. Inject the token and allowlist

```sh
export DISCORD_BOT_TOKEN='your-bot-token-from-step-1'
export DISCORD_ALLOWED_USERS='your-discord-user-id-from-step-2'
./set-secret                                       # idempotent; adds the new keys
kubectl -n hermes rollout restart deploy/hermes    # pick up the new env bindings
```

Both env vars are read from the Secret via `optional: true` `secretKeyRef`, so
Discord stays dormant when either is missing — fully opt-in.

### 4. Verify

```sh
kubectl -n hermes logs -l app=hermes --tail=30 | grep -i discord
```

Look for `Discord connected as @YourBot` (or similar). DM the bot from your
Discord client — it should reply.

## Optional: host + cluster access

Turn the bot into a trusted root user on the NUC plus a `cluster-admin` operator
inside Kubernetes. Three independent capabilities:

| Capability | Plumbed via |
|---|---|
| Read/edit anything under `/root` at native fs speed | `hostPath` mount of `/root` |
| Run any host command as root (`npm`, `cargo`, `docker`, `systemctl`, `apt`, …) | `nuc <cmd>` wrapper → SSH to `root@NUC` |
| Manage K8s resources (kubectl + Argo apps) | In-cluster ServiceAccount `hermes-admin` with `cluster-admin` ClusterRoleBinding |

### Cluster access (always on)

Already in the manifests. The `hermes-admin` ServiceAccount is created with the
deployment and bound to `cluster-admin`. Pod processes use the auto-mounted
token at `/var/run/secrets/kubernetes.io/serviceaccount/token`; `kubectl` in the
pod picks it up via in-cluster config detection — no kubeconfig needed.

Verify: `kubectl exec -n hermes deploy/hermes -- kubectl get pods -A` should
list every pod in the cluster.

### Host access (opt-in)

The `/root` bind-mount is in the manifests but the SSH key is gated by a
separate optional Secret. Run the helper once on the NUC as root:

```sh
./setup-host-access.sh
```

It generates an ed25519 keypair, appends the pubkey to `/root/.ssh/authorized_keys`,
verifies SSH works locally, and prints the two-step finish:

```sh
export HERMES_HOST_SSH_KEY="$(cat /root/.config/hermes-bot/id_ed25519)"
./set-secret
kubectl -n hermes rollout restart deploy/hermes
```

After the pod rolls, the bot can run `nuc <command>` to execute anything on the
host as root.

### Trust posture caveats

The single-user setup above is deliberately permissive. Worth knowing:

1. **`/root` mount means the bot can see `.bash_history`, `.claude.json`, every
   git repo's `.git/`, and the `hermes`/`labops` repos themselves.** If you'd
   rather narrow this, replace the `hostPath` `path: /root` with a specific
   subdirectory like `/root/projects` and consolidate work there.
2. **The bot can edit `/root/.ssh/authorized_keys`**. Mostly fine, but a
   confused bot could lock you out or add other keys. Watch git diffs if you
   ever commit the file by accident.
3. **`cluster-admin` lets the bot delete the cluster.** `kubectl delete ns hermes`,
   `kubectl delete nodes obpc` — both technically possible. Hermes's command-approval
   flow gates `rm` and `kubectl delete` but not silent edits. Narrow the
   ClusterRoleBinding if this is a concern.

To narrow K8s perms later: replace `roleRef.name: cluster-admin` in
`manifests/serviceaccount.yaml` with a custom `ClusterRole` you author.

## Updating

- **Secret values change** (rotate keys, switch model): re-run `./set-secret`, then
  `kubectl -n hermes rollout restart deploy/hermes`.
- **Template / manifest change**:
  - **(a) Direct:** `kubectl apply -k manifests/`
  - **(b) With Argo CD:** `git commit && git push` (Argo reconciles on its own,
    or `argocd app sync hermes` to force)

  Kustomize's content-hash on the ConfigMap auto-rolls the pod after either path.

For the geometry — how templates, the ConfigMap, the seed-config initContainer,
and the PVC fit together — see [`manifests/README.md`](manifests/README.md).

## Long-term memory

This deployment ships with [Honcho](https://github.com/plastic-labs/honcho)
as the memory backend. Tuning lives in `manifests/honcho.json.tpl` (cadences,
depth, recall mode, peer identity); the server itself is deployed separately
from [apnex/honcho](https://github.com/apnex/honcho).

See [`docs/memory.md`](docs/memory.md) for the tuning rationale, the
"observations are not commitments" guardrail, and what to check when memory
recall misbehaves.

## Uninstall / Reset

> **Warning:** Deleting the PVC wipes Hermes's persistent state — sessions, memory,
> skills. No undo. Back up `/opt/data` first if you want any of it.

**(a) Direct — no GitOps:**

```sh
kubectl delete -k manifests/
kubectl delete namespace hermes   # also clears the out-of-band Secret
```

**(b) With Argo CD:**

```sh
kubectl -n argocd delete application hermes --wait=true   # cascades children
kubectl delete namespace hermes
```

If you deploy via an ApplicationSet / app-of-apps, remove the `hermes` entry from that
registry first — otherwise it will be recreated within seconds. If a sync races the
namespace-terminating window and gets stuck retrying (`unable to create new content in
namespace hermes because it is being terminated`), force a fresh sync once the
namespace is gone:

```sh
kubectl -n argocd patch application hermes --type=merge \
  -p '{"operation":{"sync":{"revision":"HEAD","prune":true}}}'
```

To reinstall: repeat the install steps above — `./set-secret` recreates the namespace
and Secret in one go, and the GitOps controller (or `kubectl apply -k manifests/`)
brings the rest back.

## Notes

- **Auxiliary model alias.** The template uses `model: "smart-fast"` via your router for
  Hermes's ten auxiliary tasks (title generation, vision, compression, …). Change it in
  `manifests/config.yaml.tpl` if your router uses different aliases (e.g.
  `gpt-4o-mini`, `claude-haiku-4.5`, `gemini-2.5-flash`).
- **`temperature` requirement.** Hermes sends `temperature` on auxiliary calls, so the
  chosen aux alias must accept it (i.e. a non-reasoning model).
- **External exposure.** The Service is `ClusterIP`. Add your own Ingress / NodePort /
  port-forward / LoadBalancer overlay for LAN/WAN access — don't fork, overlay.

## What this deploys

`Deployment` (single replica, stateful) + `PVC` (`/opt/data` — Hermes's skills,
sessions, memory) + `ConfigMap` (`config.yaml` rendered from a template on every pod
start; hashed by Kustomize for auto-rollout on edits) + `ClusterIP` `Service`. All
operator-supplied values live in the out-of-band `hermes-secrets` Secret (4 keys: base
URL, model, API key, API server bearer token).
