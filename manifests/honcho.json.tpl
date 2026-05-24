{
  "_comment": "Hermes <-> Honcho plugin config. Owned by the Honcho plugin (NOT hermes-core). Rendered from this template by the seed-config initContainer on every pod start. Edit this file in Git and redeploy to change tuning; in-pod edits to /opt/data/honcho.json will be overwritten on next restart.",

  "baseUrl": "http://honcho.honcho.svc.cluster.local:8000",
  "enabled": true,

  "workspace": "hermes",
  "peerName": "@HERMES_PEER_NAME@",
  "pinPeerName": true,
  "aiPeer": "hermes",

  "recallMode": "hybrid",
  "writeFrequency": "async",
  "saveMessages": true,

  "sessionStrategy": "per-session",

  "contextCadence": 10,
  "contextTokens": 800,

  "dialecticCadence": 10,
  "dialecticDepth": 3,
  "dialecticReasoningLevel": "medium",

  "_defaults_rationale": {
    "contextCadence_10": "Refresh base context every 10 turns. Halves token churn vs SDK default of 5. Profile is stable enough that mid-session refresh isn't critical.",
    "contextTokens_800": "Hard cap on auto-injected memory block. Forces Honcho to send synthesized representation, not raw observation log. Default 2000 produces 4KB+ firehoses on active peers.",
    "dialecticCadence_10": "Fire dialectic .chat() reasoning every 10 turns. Extra LLM round-trip; this cadence balances quality vs cost.",
    "dialecticDepth_3": "audit + synthesis + reconciliation. Reconciliation pass de-dupes and resolves contradictions in derived conclusions; the surface for filtering meta-chatter ('user discussed X') vs real preferences ('user prefers X').",
    "dialecticReasoningLevel_medium": "Auto-escalates to high via reasoning_heuristic when needed. Bump to high only if depth=3 reconciliation fails to suppress meta-chatter dupes.",
    "pinPeerName_true": "Forces peerName to win over gateway-supplied runtime user_id (e.g. Discord numeric ID). Without this, multi-gateway use fragments the profile across distinct peer records.",
    "sessionStrategy_per-session": "Each Hermes invocation isolated. Gateway sessions (Discord/Telegram) override this to per-chat automatically."
  }
}
