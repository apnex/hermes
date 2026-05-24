# manifests — deployment geometry

Reference for how this repo's manifests fit together. If you're just installing
Hermes, the top-level `README.md` is enough — read this when you're editing
templates, debugging a rollout, or trying to understand why a particular file
exists.

This doc is **GitOps-mechanism-agnostic**. Everything below works identically
whether you run `kubectl apply -k manifests/` by hand or let Argo CD do it for
you. Argo is an optional automation around the apply step, not a prerequisite
for any of the patterns described here.

## File layout

```
manifests/
├── kustomization.yaml          ← bundles resources + generates ConfigMap
├── pvc.yaml                    ← /opt/data persistence
├── service.yaml                ← ClusterIP on :8642 (API) + :9119 (dashboard)
├── serviceaccount.yaml         ← hermes-admin SA + cluster-admin binding
├── deployment.yaml             ← pod spec + seed-config initContainer
├── config.yaml.tpl             ← hermes-core config (model, providers, voice)
└── honcho.json.tpl             ← Honcho plugin config (memory tuning)
```

Two template files, one ConfigMap, one initContainer that renders both at pod
start. The rest is plumbing.

## The render chain

```
       ┌─────────────────────────────────────────────────────────┐
       │  Git: manifests/*.tpl + *.yaml                          │
       │  (source of truth for everything except credentials)    │
       └─────────────────────────────────────────────────────────┘
                          │
                          │  kubectl apply -k manifests/
                          │  (run by you, or by Argo CD on git push)
                          ▼
       ┌─────────────────────────────────────────────────────────┐
       │  Cluster (ns: hermes)                                   │
       │                                                         │
       │  ConfigMap  hermes-config-<hash>                        │
       │    data:                                                │
       │      config.yaml.tpl     (verbatim from Git)            │
       │      honcho.json.tpl     (verbatim from Git)            │
       │                                                         │
       │  Secret  hermes-secrets    ← created out-of-band by     │
       │    LITELLM_BASE_URL          ./set-secret. NOT in Git.  │
       │    LITELLM_MODEL                                        │
       │    LITELLM_API_KEY                                      │
       │    API_SERVER_KEY                                       │
       │    HERMES_PEER_NAME       (optional)                    │
       │    DISCORD_BOT_TOKEN      (optional)                    │
       │    DISCORD_ALLOWED_USERS  (optional)                    │
       │                                                         │
       │  Deployment hermes                                      │
       │    initContainer "seed-config":                         │
       │      reads /seed/*.tpl from ConfigMap                   │
       │      reads env from hermes-secrets                      │
       │      sed @VAR@ substitution                             │
       │      writes /opt/data/config.yaml                       │
       │      writes /opt/data/honcho.json                       │
       │    container "hermes":                                  │
       │      reads /opt/data/config.yaml  (hermes-core)         │
       │      reads /opt/data/honcho.json  (Honcho plugin)       │
       └─────────────────────────────────────────────────────────┘
```

## Four design decisions worth understanding

### 1. Two templates, one ConfigMap

`kustomization.yaml` lists both templates under a single `configMapGenerator`:

```yaml
configMapGenerator:
  - name: hermes-config
    files:
      - config.yaml.tpl
      - honcho.json.tpl
```

Kustomize hashes the combined content into the ConfigMap name
(`hermes-config-kkc5fb85gd` today). The Deployment references the ConfigMap
by its generated name, so **any edit to either template changes the hash,
which changes the volume reference, which triggers a rolling pod restart.**

You never need `kubectl rollout restart` after a template edit — the rollout
is implicit in the apply.

### 2. Templates, not finished files

Both `.tpl` files contain `@VAR@` placeholders. The `seed-config` initContainer
substitutes them at pod start using env vars sourced from the `hermes-secrets`
Secret. This keeps Git clean of:

- LLM endpoint URLs (operator-specific)
- API keys (obviously)
- Per-install identity like `HERMES_PEER_NAME`

A fresh clone of this repo has nothing operator-specific in it.

### 3. Rendered files live on the PVC

The init container writes to `/opt/data/`, which is the persistent volume.
This has three consequences worth knowing:

1. **The plugin reads a normal file.** No env-var indirection, no special
   client code — `plugins/memory/honcho/client.py` just opens
   `/opt/data/honcho.json`.
2. **Pod restart re-renders from template.** In-pod edits to either rendered
   file are wiped on the next restart. The `honcho.json.tpl` `_comment` field
   carries this warning into the rendered file itself.
3. **The PVC stays the source of truth for runtime state.** Sessions, memory
   caches, skills, and now config all live on the same persistent volume.

If you ever need to debug "is the file the pod sees actually what I committed
to Git?", compare:

```sh
# What's in the ConfigMap (= what Kustomize sent to the cluster):
kubectl -n hermes get cm -o name | grep hermes-config | head -1 | \
  xargs -I{} kubectl -n hermes get {} -o jsonpath='{.data.honcho\.json\.tpl}'

# What's actually rendered on the pod:
kubectl -n hermes exec deploy/hermes -- cat /opt/data/honcho.json
```

Differences should only be the `@VAR@` substitutions.

### 4. Split ownership between the two templates

`config.yaml.tpl` is **hermes-core's** territory — model selection, named
providers, auxiliary task assignments, memory char limits, voice. Maintained
against the Hermes agent's own config schema.

`honcho.json.tpl` is the **Honcho plugin's** territory — cadences, depths,
recall mode, peer pinning, write frequency. Maintained against the Honcho
client SDK's config schema. The plugin reads this file directly via
`HonchoClientConfig.from_global_config()`.

The line between them isn't arbitrary: each file matches a different upstream
schema, owned by a different codebase. `config.yaml.tpl` does keep a tiny
`honcho:` block with `base_url` only — that's the transport bootstrap the
plugin needs before it has a chance to read its own file. Tuning lives in
`honcho.json.tpl` exclusively.

See `docs/memory.md` for the Honcho-specific tuning rationale.

## The edit loop

### Editing a template

1. `$EDITOR manifests/honcho.json.tpl`  (or `config.yaml.tpl`)
2. Apply the change:
   - **(a) Direct:** `kubectl apply -k manifests/`
   - **(b) Argo CD:** `git commit && git push` (Argo reconciles within ~3 min,
     or run `argocd app sync hermes` to force).
3. Pod rolls automatically (Kustomize hash change → new volume reference).
4. Verify on the pod: `kubectl -n hermes exec deploy/hermes -- cat /opt/data/honcho.json`

### Rotating a Secret value

1. Update the env var on the host (`export LITELLM_API_KEY=...`).
2. `./set-secret` — overwrites the `hermes-secrets` Secret in place.
3. `kubectl -n hermes rollout restart deploy/hermes` — Secret changes do NOT
   trigger a rollout on their own (no hash on Secrets), so this is explicit.
4. New pod's seed-config initContainer reads the new value and re-renders.

### Adding a new placeholder

Three places must agree:

1. Add `@NEW_VAR@` to the appropriate template.
2. Add a `sed -e "s|@NEW_VAR@|${NEW_VAR}|g"` line to `deployment.yaml`'s
   `seed-config` command block.
3. Add a `env:` entry on the `seed-config` initContainer with `secretKeyRef`
   sourced from `hermes-secrets` (use `optional: true` if the deployment
   should still boot when the key is missing).
4. Update `./set-secret` to accept the new env var and include it in the Secret.

## What this geometry does NOT cover

- **The Honcho server.** Lives in `apnex/honcho` with its own kustomize tree,
  ConfigMap (server env), and operational docs. The contract between this
  repo and that one is a single URL — `baseUrl` in `honcho.json.tpl`. See
  `docs/memory.md` for where that seam is drawn.
- **The Hermes container image.** Built separately. To change *how* the
  plugin parses `honcho.json` you rebuild the image and bump the tag in
  `deployment.yaml`. To change *values* in `honcho.json` you just edit the
  template — no image rebuild.
- **Secrets in Git.** Deliberate. `hermes-secrets` is created by `./set-secret`
  against the live cluster. If you nuke the namespace, you re-run `./set-secret`
  before the pod will boot cleanly.
- **The LoadBalancer / VIP.** `service.yaml` ships ClusterIP only. LAN/WAN
  exposure is an overlay (e.g. `apnex/labops/vip-hermes/`) — don't fork this
  repo to expose it, overlay it.

## Verifying the chain end-to-end

After any change, three checks confirm the loop closed:

```sh
# 1. Kustomize produced the expected resources locally
kubectl kustomize manifests/ | head -40

# 2. Cluster has the new ConfigMap hash
kubectl -n hermes get cm | grep hermes-config

# 3. Pod is running the latest ReplicaSet (= rolled successfully)
kubectl -n hermes get pods -l app=hermes -o wide
kubectl -n hermes describe deploy hermes | grep -E 'Image|hermes-config'
```

If Argo is in play, also:

```sh
kubectl -n argocd get app hermes -o jsonpath='{.status.sync.status} / {.status.health.status} @ {.status.sync.revision}{"\n"}'
```

Should print `Synced / Healthy @ <commit-sha>`.
