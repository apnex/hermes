# hermes

GitOps-deployed [Hermes agent](https://github.com/NousResearch/hermes-agent) for
Kubernetes. Generic, reusable; **no operator-specific values are committed.**

## What this deploys

- `Deployment` running `nousresearch/hermes-agent` in service mode (`hermes gateway run`).
- `PersistentVolumeClaim` for `/opt/data` (Hermes's skills, sessions, memory).
- `ConfigMap` holding a `config.yaml` *template* (substituted at first boot by an init container).
- `ClusterIP` `Service` exposing `:8642` (OpenAI-compatible API) + `:9119` (web dashboard).

All operator-supplied values (LiteLLM base URL, model name, API key, API server key) live
in a Kubernetes `Secret` (`hermes-secrets`) created out-of-band by `./set-secret` — they
are never committed.

## Prerequisites

- A Kubernetes cluster with `kubectl` access.
- An OpenAI-compatible LLM endpoint (e.g. a LiteLLM router) — base URL (must include the OpenAI-style `/v1` path), model ID, API key.
- A GitOps tool (point Argo CD at `manifests/`).

## Deploy

1. **Create the Secret.** Export four env vars and run `./set-secret`:

   ```sh
   export LITELLM_BASE_URL="https://your-litellm-router/v1"
   export LITELLM_MODEL="your-default-model-id"
   export LITELLM_API_KEY="your-router-api-key"
   export API_SERVER_KEY="$(openssl rand -hex 32)"   # bearer token for :8642
   ./set-secret
   ```

   Creates the `hermes` namespace if absent, then applies the `hermes-secrets` Secret.

2. **Point your GitOps tool at `manifests/`.** Argo CD example:

   ```yaml
   apiVersion: argoproj.io/v1alpha1
   kind: Application
   metadata: { name: hermes, namespace: argocd }
   spec:
     project: default
     source:
       repoURL: https://github.com/apnex/hermes
       targetRevision: main
       path: manifests
     destination: { server: https://kubernetes.default.svc, namespace: hermes }
     syncPolicy:
       automated: { selfHeal: true, prune: true }
       syncOptions: [CreateNamespace=true]
   ```

3. **Verify.**

   `kubectl -n hermes get pods` should show `hermes-…` Running. Then, since the Service
   is `ClusterIP`, port-forward to reach the API from your shell:

   ```sh
   kubectl -n hermes port-forward svc/hermes 8642:8642 &
   curl -H "Authorization: Bearer ${API_SERVER_KEY}" http://localhost:8642/v1/models
   ```

   That should return the models your LiteLLM router exposes.

## Exposure

The repo ships a `ClusterIP` Service — portable, works on any cluster. To expose Hermes
externally, add your own `Ingress`, `NodePort`, `kubectl port-forward`, or LoadBalancer
overlay on top — don't fork, overlay.

## Configuration after first boot

The init container **regenerates `/opt/data/config.yaml` from the ConfigMap template
and the operator Secret on every pod start**, so the supported way to change any of the
templated fields (`provider`, `base_url`, model name, API key) is: update `hermes-secrets`
(re-run `./set-secret` with new env vars) and bounce the pod. Hermes still owns other
state on the PVC at runtime (skills, sessions, memories); changes to those persist
across restarts as usual. To tweak fields Hermes manages itself, `kubectl exec` into
the pod and use `hermes config set …` (those values live outside the regenerated
template).
