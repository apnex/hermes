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
# System tooling for "trusted dev on the NUC" capability:
#   - kubectl             cluster-admin via auto-mounted ServiceAccount token
#   - openssh-client      (already in upstream) for the `nuc` host shell wrapper
#   - /usr/local/bin/nuc  wrapper: `nuc <cmd>` SSHes back to the host as root
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
 && curl -fsSL -o /usr/local/bin/kubectl \
      "https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
 && chmod +x /usr/local/bin/kubectl \
 && rm -rf /var/lib/apt/lists/*

# Wrapper: `nuc <command>` SSHes back to the host as root, reading the bot's
# private key from /etc/hermes-host-ssh/id_ed25519 (Secret-mounted, mode 0400).
# Host key checking disabled — single-user LAN, acceptable trade-off.
RUN cat > /usr/local/bin/nuc <<'EOF' \
 && chmod +x /usr/local/bin/nuc
#!/bin/bash
exec ssh \
  -i "${HERMES_HOST_SSH_KEY_PATH:-/etc/hermes-host-ssh/id_ed25519}" \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -o LogLevel=ERROR \
  "${HERMES_HOST_SSH_TARGET:-root@192.168.1.250}" "$@"
EOF

USER hermes
RUN uv pip install --python /opt/hermes/.venv/bin/python --no-cache \
      sounddevice \
      numpy \
      faster-whisper \
      discord.py \
      PyNaCl \
      edge-tts \
      davey

USER root
