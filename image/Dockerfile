# syntax=docker/dockerfile:1.4
# Hermes agent + local voice (sounddevice capture + faster-whisper STT).
#
# Adds the optional audio stack the upstream image does not ship:
#   - libportaudio2       PortAudio C runtime (sounddevice depends on it)
#   - libasound2-plugins  ALSA plugin pack (Pulse plugin for ALSA-via-Pulse paths)
#   - alsa-utils          arecord/aplay/amixer — for in-pod debugging only
#   - sounddevice, numpy  mic capture + audio buffer manipulation
#   - faster-whisper      local STT engine; model auto-downloads to ~/.cache on first use
#                         ($HOME=/opt/data for the hermes user, so the model lands on the PVC)
#   - discord.py          Hermes Discord gateway adapter (optional — only used when
#                         DISCORD_BOT_TOKEN is set in the Secret)
#   - PyNaCl              RTP voice encryption (required for voice channel join)
#   - edge-tts            Microsoft Edge TTS — bot's voice output
#   - davey               DAVE E2EE library — discord.py >= 2.5 requires it
#                         for voice channel support (without it: "voice will NOT be supported")
#
# System tooling for "trusted dev on the host" capability:
#   - kubectl                   cluster-admin via auto-mounted ServiceAccount token
#   - openssh-client            (already in upstream) for the ssh-target wrapper
#   - /usr/local/bin/ssh-target wrapper: `ssh-target <cmd>` SSHes back to the
#                               host, normalising non-root logins to sudo
#
# Note: upstream strips `pip` from the venv to keep it lean — use `uv` (which is
# pre-installed at /usr/local/bin/uv) for any additional Python packages.
FROM docker.io/nousresearch/hermes-agent:v2026.5.16

USER root

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      libportaudio2 \
      libasound2-plugins \
      alsa-utils \
      curl \
      ca-certificates \
      gh \
 && curl -fsSL -o /usr/local/bin/kubectl \
      "https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
 && chmod +x /usr/local/bin/kubectl \
 && rm -rf /var/lib/apt/lists/*

# Wire git's HTTPS credential helper to gh, system-wide. With $GH_TOKEN set
# in the pod env (sourced from hermes-secrets), `git push` to github.com
# Just Works without a per-pod `gh auth login`. The helper lives in
# /etc/gitconfig so it survives the hermes user's $HOME being mounted
# from the PVC.
#
# Also sets a system-wide author identity so commits from any hermes pod
# attribute to a recognisable bot identity (the GH_TOKEN already maps the
# push to the owning GitHub account; this gives `git log` audit clarity
# for "which commits came from a hermes pod").
RUN git config --system credential.https://github.com.helper '' \
 && git config --system --add credential.https://github.com.helper '!gh auth git-credential' \
 && git config --system credential.https://gist.github.com.helper '' \
 && git config --system --add credential.https://gist.github.com.helper '!gh auth git-credential' \
 && git config --system user.name 'hermes' \
 && git config --system user.email 'kate@apnex.local'

# Wrapper: `ssh-target <command>` SSHes to the configured host as the
# configured user, reading the bot's private key from the Secret-mounted
# path. SSH_TARGET_{USER,HOST,KEY} are supplied by the platform shim
# (on GCE: terraform + OS Login). Sensible-but-broken defaults exist only
# so a misconfigured pod fails loudly. Host key checking disabled —
# single-user LAN trade-off.
RUN cat > /usr/local/bin/ssh-target <<'EOF' \
 && chmod +x /usr/local/bin/ssh-target
#!/bin/bash
# Host resolution chain: explicit SSH_TARGET_HOST overrides; otherwise
# fall back to POD_HOST_IP (injected via Downward API: status.hostIP) —
# the single-node pattern where the pod SSHes to its own host. Final
# fallback is an unresolvable name so misconfiguration fails loudly.
HOST="${SSH_TARGET_HOST:-${POD_HOST_IP:-unset.invalid}}"
USER="${SSH_TARGET_USER:-root}"
# Privilege normalisation: OS Login lands us as a non-root SA user
# (sa_<unique_id>); a vanilla host lands us as root. Prefix sudo for any
# non-root user so callers run privileged identically on every platform —
# the platform delta (who we land as) never leaks to the caller.
PFX=""
[ "$USER" = root ] || PFX="sudo"
exec ssh \
  -i "${SSH_TARGET_KEY_PATH:-/etc/ssh-target/id_ed25519}" \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -o LogLevel=ERROR \
  "${USER}@${HOST}" $PFX "$@"
EOF

USER hermes
RUN uv pip install --python /opt/hermes/.venv/bin/python --no-cache \
      sounddevice \
      numpy \
      faster-whisper \
      discord.py \
      PyNaCl \
      edge-tts \
      honcho-ai \
      davey

USER root
