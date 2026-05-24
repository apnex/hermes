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

# Honcho self-hosted in-cluster — AUTH_USE_AUTH=false on the server,
# so no API key needed. recallMode=hybrid gives auto context injection
# AND the honcho_* tools (profile/search/context/reasoning/conclude).
honcho:
  baseUrl: http://honcho.honcho.svc.cluster.local:8000
  workspace: default
  apiKey: ""
  recallMode: hybrid
  saveMessages: true
  writeFrequency: async
  contextCadence: 1
  dialecticCadence: 2
  dialecticReasoningLevel: low
  dialecticDynamic: true
  sessionStrategy: per-session
