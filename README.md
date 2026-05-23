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

## Updating

- **Secret values change** (rotate keys, switch model): re-run `./set-secret`, then
  `kubectl -n hermes rollout restart deploy/hermes`.
- **Template / manifest change**: re-run `kubectl apply -k manifests/` (direct) or push
  the commit (Argo CD). Kustomize's content-hash on the ConfigMap auto-rolls the pod.

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
