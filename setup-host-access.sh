#!/bin/bash
## setup-host-access — provision the bot's SSH key into /root/.ssh/authorized_keys
##                     on the NUC, then print the export command to feed it into
##                     ./set-secret.
##
## Run as root on the NUC. Idempotent: if a hermes-bot key is already present,
## reuses it instead of generating a new one.
##
## After this script: export HERMES_HOST_SSH_KEY="$(cat ...)" && ./set-secret
##                    kubectl -n hermes rollout restart deploy/hermes
set -e

if [[ $EUID -ne 0 ]]; then
	echo "Error: must run as root (need write access to /root/.ssh/)" >&2
	exit 1
fi

KEY_DIR="${KEY_DIR:-/root/.config/hermes-bot}"
KEY_PATH="${KEY_DIR}/id_ed25519"
KEY_COMMENT="hermes-bot-$(hostname)"
AUTH_KEYS="/root/.ssh/authorized_keys"

mkdir -p "${KEY_DIR}"
chmod 0700 "${KEY_DIR}"

## 1. Generate keypair if not already present
if [[ ! -f "${KEY_PATH}" ]]; then
	echo "generating new ed25519 keypair at ${KEY_PATH}"
	ssh-keygen -t ed25519 -C "${KEY_COMMENT}" -f "${KEY_PATH}" -N "" >/dev/null
else
	echo "reusing existing keypair at ${KEY_PATH}"
fi
PUBKEY="$(cat "${KEY_PATH}.pub")"

## 2. Ensure /root/.ssh/authorized_keys exists with correct perms
mkdir -p /root/.ssh
chmod 0700 /root/.ssh
touch "${AUTH_KEYS}"
chmod 0600 "${AUTH_KEYS}"

## 3. Append pubkey if not already there (idempotent on the *comment*,
##    so re-running after a key rotation still works cleanly)
if grep -q " ${KEY_COMMENT}$" "${AUTH_KEYS}" 2>/dev/null; then
	## Replace any existing line with the same comment (handles key rotation)
	grep -v " ${KEY_COMMENT}$" "${AUTH_KEYS}" > "${AUTH_KEYS}.tmp" || true
	echo "${PUBKEY}" >> "${AUTH_KEYS}.tmp"
	mv "${AUTH_KEYS}.tmp" "${AUTH_KEYS}"
	chmod 0600 "${AUTH_KEYS}"
	echo "replaced existing ${KEY_COMMENT} entry in ${AUTH_KEYS}"
else
	echo "${PUBKEY}" >> "${AUTH_KEYS}"
	echo "appended pubkey to ${AUTH_KEYS}"
fi

## 4. Sanity-check the local SSH connection works
echo
echo "verifying ssh root@localhost with the new key..."
if ssh -i "${KEY_PATH}" \
	-o StrictHostKeyChecking=no \
	-o UserKnownHostsFile=/dev/null \
	-o LogLevel=ERROR \
	-o ConnectTimeout=5 \
	root@localhost 'echo "ssh: ok ($(hostname))"' 2>&1; then
	echo "✓ ssh connectivity confirmed"
else
	echo "⚠ ssh test failed — check sshd config (PermitRootLogin) and host firewall" >&2
fi

## 5. Print next-step commands for the operator
cat <<EOF

────────────────────────────────────────────────────────────
Next steps:

  export HERMES_HOST_SSH_KEY="\$(cat ${KEY_PATH})"
  ./set-secret
  kubectl -n hermes rollout restart deploy/hermes

Then from inside the pod (or via the bot): \`nuc whoami\` should print "root".
────────────────────────────────────────────────────────────
EOF
