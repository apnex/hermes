model:
  provider: "custom"
  base_url: "@LITELLM_BASE_URL@"
  default: "@LITELLM_MODEL@"
  api_key: "@LITELLM_API_KEY@"

# Named providers — define once; reference by name from auxiliary tasks.
providers:
  litellm:
    base_url: "@LITELLM_BASE_URL@"
    api_key: "@LITELLM_API_KEY@"

auxiliary:
  vision:           { provider: litellm, model: "smart-fast" }
  web_extract:      { provider: litellm, model: "smart-fast" }
  compression:      { provider: litellm, model: "smart-fast" }
  session_search:   { provider: litellm, model: "smart-fast" }
  skills_hub:       { provider: litellm, model: "smart-fast" }
  approval:         { provider: litellm, model: "smart-fast" }
  mcp:              { provider: litellm, model: "smart-fast" }
  title_generation: { provider: litellm, model: "smart-fast" }
  triage_specifier: { provider: litellm, model: "smart-fast" }
  curator:          { provider: litellm, model: "smart-fast" }

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
