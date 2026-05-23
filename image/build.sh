#!/bin/bash
## build.sh — build the hermes-with-voice image and import into k3s containerd.
##
## Use for single-node k3s only. For multi-node, push to a registry instead
## (replace the `k3s ctr images import` line with `podman push`).
##
## Usage:  ./build.sh            # default tag
##         TAG=foo/bar ./build.sh
##
## Requires: docker, k3s (with `k3s ctr`). Run as root or via sudo for the
## containerd import step.
set -euo pipefail

TAG="${TAG:-localhost/hermes-agent:v2026.5.16-voice}"

cd "$(dirname "$0")"

echo "==> building ${TAG}"
docker build -t "${TAG}" .

echo "==> importing into k3s containerd (k8s.io namespace)"
docker save "${TAG}" | k3s ctr -n k8s.io images import -

echo "==> verifying"
k3s ctr -n k8s.io images ls | grep "hermes-agent" | head -5

echo
echo "✓ ready: ${TAG}"
echo "  Use in manifests with imagePullPolicy: IfNotPresent"
