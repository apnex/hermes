model:
  provider: "custom"
  base_url: "@LITELLM_BASE_URL@"
  default: "@LITELLM_MODEL@"
  api_key: "@LITELLM_API_KEY@"

# Named providers — define once; reference by name from auxiliary tasks.
# Key MUST match model.provider above (currently "custom") so the resolver
# finds it. Renaming this key without updating model.provider triggers
# "No inference provider configured" at first model call.
providers:
  custom:
    base_url: "@LITELLM_BASE_URL@"
    api_key: "@LITELLM_API_KEY@"

auxiliary:
  vision:           { provider: custom, model: "smart-fast" }
  web_extract:      { provider: custom, model: "smart-fast" }
  compression:      { provider: custom, model: "smart-fast" }
  session_search:   { provider: custom, model: "smart-fast" }
  skills_hub:       { provider: custom, model: "smart-fast" }
  approval:         { provider: custom, model: "smart-fast" }
  mcp:              { provider: custom, model: "smart-fast" }
  title_generation: { provider: custom, model: "smart-fast" }
  triage_specifier: { provider: custom, model: "smart-fast" }
  curator:          { provider: custom, model: "smart-fast" }

# Voice (CLI /voice command) — defaults shown explicitly for operator visibility.
# These match Hermes's built-in defaults; override if you want a different
# whisper variant or TTS voice.
stt:
  enabled: true
  provider: local            # local faster-whisper; no API key, no network
  local:
    model: base              # tiny | base | small | medium | large-v3
tts:
  provider: edge             # Microsoft Edge TTS — free, HTTPS, no key

# Memory — local notes + user profile, plus Honcho as the AI-native backend.
# Bumped from defaults (1375/2200) — single power-user, multi-session use case.
memory:
  memory_enabled: true
  user_profile_enabled: true
  memory_char_limit: 3000
  user_char_limit: 2000
  provider: honcho

# Skills — local /opt/data/skills/ is always scanned first. The
# external_dirs entry below adds a read-only root populated by the
# skill-sync initContainer (see manifests/skill-sync/), which clones
# a SKILL.md-tree repo (default apnex/mission-kit) and resolves
# wanted bundles into a concrete skill subset.
skills:
  external_dirs:
    - /opt/data/extra-skills

# Honcho — only the transport-level bootstrap lives here. All plugin
# tuning (recallMode, cadences, depth, reasoning level, peer pinning,
# write frequency) lives in /opt/data/honcho.json, rendered from
# manifests/honcho.json.tpl by the seed-config initContainer. The plugin
# reads honcho.json directly; this block exists only so an unconfigured
# install can still find the server URL before the wizard runs.
honcho:
  base_url: http://honcho.honcho.svc.cluster.local:8000
