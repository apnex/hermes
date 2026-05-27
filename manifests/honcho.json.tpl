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
  "contextTokens": 3000,

  "dialecticCadence": 10,
  "dialecticDepth": 3,
  "dialecticReasoningLevel": "medium",

  "_comment_tier1": "honcho-tuned v1.0.0 — Tier 1 distillation block. Controls the <distillations> XML block injected at the top of <memory-context>. Keys use camelCase (read by HonchoClientConfig.from_global_config in honcho-tuned/client.py).",
  "distillation": {
    "enabled": true,
    "maxPerLevelUser": 10,
    "maxPerLevelAi": 10,
    "maxContradictions": 5,
    "maxDeductive": 5
  },

  "_comment_tier3a": "honcho-tuned v1.0.0 — Tier 3a configurable dialectic prompts. Templates support {query} and {peer} substitution. reasoning_levels keyed by minimal|low|medium|high|max — falls back to 'default', then raw query. The reasoning_levels key uses snake_case to match session.py:_apply_dialectic_template.",
  "dialecticPrompts": {
    "default": "What does the user believe about this topic?",
    "reasoning_levels": {
      "minimal": "Give the single most relevant fact about {peer}.",
      "low": "Briefly answer: {query}",
      "medium": "Answer {query} citing 2-3 supporting observations.",
      "high": "Reason through {query} across observations, flag contradictions.",
      "max": "Audit-level: enumerate every relevant observation and synthesize."
    }
  },

  "_defaults_rationale": {
    "contextCadence_10": "Refresh base context every 10 turns. Halves token churn vs SDK default of 5. Profile is stable enough that mid-session refresh isn't critical.",
    "contextTokens_3000": "Hard cap on auto-injected memory block. Raised from 800 to 3000 (12KB) in v1.0.1 to fit user+ai cards (~3.5KB) + distillation blocks (~7KB) + headroom; the previous 800-token budget dropped distillations and representation entirely, leaving only peer cards.  Synthesized representation still gets trimmed first under pressure — the priority order is (1) representation/ai_representation, (2) summary, (3) inductive sub-tails, (4) deductive sub-tails.  Contradictions and peer_cards are never trimmed.",
    "dialecticCadence_10": "Fire dialectic .chat() reasoning every 10 turns. Extra LLM round-trip; this cadence balances quality vs cost.",
    "dialecticDepth_3": "audit + synthesis + reconciliation. Reconciliation pass de-dupes and resolves contradictions in derived conclusions; the surface for filtering meta-chatter ('user discussed X') vs real preferences ('user prefers X').",
    "dialecticReasoningLevel_medium": "Auto-escalates to high via reasoning_heuristic when needed. Bump to high only if depth=3 reconciliation fails to suppress meta-chatter dupes.",
    "pinPeerName_true": "Forces peerName to win over gateway-supplied runtime user_id (e.g. Discord numeric ID). Without this, multi-gateway use fragments the profile across distinct peer records.",
    "sessionStrategy_per-session": "Each Hermes invocation isolated. Gateway sessions (Discord/Telegram) override this to per-chat automatically."
  }
}
