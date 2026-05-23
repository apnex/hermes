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
 && rm -rf /var/lib/apt/lists/*

USER hermes
RUN uv pip install --python /opt/hermes/.venv/bin/python --no-cache \
      sounddevice \
      numpy \
      faster-whisper \
      discord.py

USER root
