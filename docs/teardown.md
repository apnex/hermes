# hermes teardown

Symmetric to install. Removes everything this repo deploys, with explicit
choices for data preservation vs. full wipe.

## What gets removed

| Resource                  | Created by                       | Removed by         |
|---------------------------|----------------------------------|--------------------|
| Deployment (`hermes`)     | `kubectl apply -k manifests/`    | step 1             |
| Service (ClusterIP)       | `kubectl apply -k manifests/`    | step 1             |
| ServiceAccount + Binding  | `kubectl apply -k manifests/`    | step 1             |
| PVC (`hermes-data`)       | `kubectl apply -k manifests/`    | step 1 (object) + step 3 (data) |
| ConfigMap (`hermes-config`) | Kustomize configMapGenerator   | step 1             |
| `hermes-secrets` Secret   | `./set-secret`                   | step 2             |
| LoadBalancer Service (`vip-hermes`) | separate Argo app (`labops/vip-hermes/`) | step 4 |
| `hermes` namespace        | `kubectl create namespace hermes` or `CreateNamespace=true` | step 5 |
| ArgoCD Application (if used) | install step 3 (b)            | step 0 (do this **first**) |

## Teardown — choose your path

### Path A: With ArgoCD

```sh
# 0. Delete the Application FIRST — Argo prunes the workloads it manages.
#    With automated.prune: true this also removes Deployment, Service,
#    ConfigMap, ServiceAccount, PVC (object only — see step 3 for data).
kubectl -n argocd delete application hermes

# 0b. If the VIP is deployed as a separate Argo app (per the apnex/labops
#     registry pattern), delete it too — OR keep it for a future redeploy.
kubectl -n argocd delete application vip-hermes   # optional

# Wait for the prune to settle.
kubectl -n hermes get all     # should be empty (or just terminating pods)
```

Then continue from step 2 below to clean up the Secret + PVC + namespace.

### Path B: Direct (no GitOps)

```sh
# 1. Delete everything Kustomize created
kubectl delete -k manifests/
```

## Common cleanup (both paths)

```sh
# 2. Delete the out-of-band hermes-secrets Secret
#    (not in Git, not managed by Argo/Kustomize)
kubectl -n hermes delete secret hermes-secrets --ignore-not-found

# 3. Delete the PVC — DESTROYS skills, sessions, MEMORY.md, USER.md,
#    audio cache, and any in-pod state. Skip to preserve across redeploys.
kubectl -n hermes delete pvc hermes-data --ignore-not-found

# 4. Delete the namespace (also removes any stray resources)
kubectl delete namespace hermes

# 5. If your StorageClass is `local-path`, the underlying data directory on
#    the host node remains by default (k3s convention). Purge it manually
#    if you want a truly clean slate:
sudo rm -rf /opt/local-path-provisioner/*pvc-*hermes*

# 6. If you used MetalLB and want the VIP back in the pool immediately,
#    no action needed — deleting the Service released the IP automatically.
```

## Optional cleanup — host-access feature

If you enabled the `nuc <cmd>` host-access wrapper (see README "Optional:
host + cluster access"), reverse it manually:

```sh
# On the NUC host as root: remove the SSH key the bot used.
KEY_FP=$(ssh-keygen -lf /root/.config/hermes-bot/id_ed25519.pub | awk '{print $2}')
sed -i.bak "/${KEY_FP}/d" /root/.ssh/authorized_keys
rm -rf /root/.config/hermes-bot
```

## Optional cleanup — Discord gateway

If you wired the Discord bot:

```sh
# 1. Revoke the bot token (so a stale Secret can't reconnect):
#    Discord Developer Portal → your app → Bot → Reset Token
#    (or delete the application entirely if no longer needed)

# 2. The token is gone from the cluster automatically once the
#    hermes-secrets Secret is deleted in step 2 above.

# 3. If desired, remove the bot from your Discord server:
#    Server Settings → Members → kick the bot
```

## Verification

```sh
kubectl get ns hermes                       # → NotFound
kubectl get pv | grep hermes                # → empty (after step 3)
kubectl -n argocd get app hermes            # → NotFound (after step 0)
kubectl -n argocd get app vip-hermes        # → NotFound (after step 0b)
```

## Reinstall after teardown

Follow `README.md` install steps from scratch. If you skipped step 3 (PVC
deletion), the new deployment will attach to the existing PVC and recover
prior skills, sessions, MEMORY.md, and USER.md on first start.

## Caveats

- **In-flight agent work is lost.** Any active session, background process,
  or scheduled cron job dies when the pod terminates. Drain user-facing
  channels (e.g. announce in Discord) before tearing down a live deployment.
- **Honcho memory survives.** Honcho lives in a separate namespace
  (`honcho`) with its own PVC. Hermes teardown does not touch it — a
  reinstall will reconnect to existing observations and conclusions.
- **Argo App deletion is async.** If pods are stuck terminating, check for
  finalizers: `kubectl -n hermes get pods -o jsonpath='{.items[*].metadata.finalizers}'`.
- **LiteLLM proxy unaffected.** Your LLM endpoint (Cloud Run / wherever)
  is external to the cluster — teardown only removes the client, not the
  backend.
