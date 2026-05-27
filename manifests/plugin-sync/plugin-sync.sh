#!/bin/sh
# plugin-sync.sh — GitOps plugin loader for Hermes plugin repositories.
#
# Reads a wanted-plugins manifest, clones a plugin source repo, and
# writes the filtered plugin subset to a target directory under
# /opt/data/plugins/ — where Hermes's memory plugin loader
# auto-discovers them via $HERMES_HOME/plugins/<name>/.
#
# Agent-agnostic in shape: mirrors skill-sync.sh exactly. Hermes is the
# first consumer; the loader has no Hermes-specific code paths beyond
# the chown uid (10000:10000) that matches the hermes container user.
#
# Inputs (env):
#   PLUGINS_REPO       git URL of the source repo (default: apnex/hermes-plugins)
#   PLUGINS_REF        git ref to pull (default: v1.0.1 — pinned for prod)
#   PLUGINS_MANIFEST   path to wanted-plugins.yaml (required)
#   PLUGINS_TARGET     output directory (default: /opt/data/plugins)
#   PLUGINS_OWNER      chown target to this uid:gid (default: 10000:10000)
#
# Manifest format (wanted-plugins.yaml):
#   plugins:
#     - <plugin-name>     # resolved as a top-level directory in the source repo
#
# Behaviour:
#   - Idempotent: target dir is rewritten atomically each run.
#   - Best-effort: missing plugins are logged, never fatal,
#     unless every requested item fails to resolve.
#   - Designed to run as an initContainer (one-shot) OR as a sidecar
#     loop (re-run on interval).

set -eu

# --- defaults ---------------------------------------------------------
PLUGINS_REPO="${PLUGINS_REPO:-https://github.com/apnex/hermes-plugins.git}"
PLUGINS_REF="${PLUGINS_REF:-v1.0.1}"
PLUGINS_MANIFEST="${PLUGINS_MANIFEST:?PLUGINS_MANIFEST is required}"
PLUGINS_TARGET="${PLUGINS_TARGET:-/opt/data/plugins}"
PLUGINS_OWNER="${PLUGINS_OWNER:-10000:10000}"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

log() { printf '[plugin-sync] %s\n' "$*"; }

# --- 1. clone source repo --------------------------------------------
log "cloning $PLUGINS_REPO@$PLUGINS_REF"
git clone --depth 1 --branch "$PLUGINS_REF" \
    "$PLUGINS_REPO" "$WORKDIR/repo" 2>&1 | sed 's/^/[plugin-sync]   /'

REPO="$WORKDIR/repo"

# --- 2. parse wanted-plugins manifest --------------------------------
# Manifest is small YAML — extract plugin names with awk to avoid pulling
# a yaml parser into the image. Lines we care about:
#   plugins:
#     - foo
#     - bar

if [ ! -f "$PLUGINS_MANIFEST" ]; then
  log "ERROR: manifest not found at $PLUGINS_MANIFEST"
  exit 1
fi

log "reading manifest $PLUGINS_MANIFEST"

# Extract list items under a given top-level key.
extract_list() {
  key="$1"
  awk -v key="$key" '
    $0 ~ "^"key":" { in_list=1; next }
    in_list && /^[a-zA-Z_]/ { in_list=0 }
    in_list && /^  *-/ {
      sub(/^  *-[ \t]*/, "")
      sub(/[ \t]*$/, "")
      sub(/[ \t]*#.*$/, "")
      if (length($0) > 0) print
    }
  ' "$PLUGINS_MANIFEST"
}

PLUGINS="$(extract_list plugins || true)"

log "requested plugins: $(echo $PLUGINS | tr '\n' ' ')"

WANTED="$(printf '%s\n' "$PLUGINS" | sed '/^$/d' | sort -u)"

if [ -z "$WANTED" ]; then
  log "no plugins requested after resolution — nothing to do"
  exit 0
fi

log "final plugin set: $(echo $WANTED | tr '\n' ' ')"

# --- 3. write to target ----------------------------------------------
# Idempotent: rewrite the target dir each run via atomic swap.

STAGING="$WORKDIR/staging"
mkdir -p "$STAGING"

ok=0
miss=0
for plugin in $WANTED; do
  src="$REPO/$plugin"
  if [ ! -d "$src" ]; then
    log "WARN: plugin '$plugin' not found at $plugin/ in repo — skipping"
    miss=$((miss + 1))
    continue
  fi
  cp -a "$src" "$STAGING/$plugin"
  log "  + $plugin"
  ok=$((ok + 1))
done

if [ "$ok" -eq 0 ]; then
  log "ERROR: zero plugins resolved successfully ($miss missed)"
  exit 1
fi

# Atomic-ish swap: write to a tmp dir adjacent to target, then mv.
TMPTARGET="$(dirname "$PLUGINS_TARGET")/.$(basename "$PLUGINS_TARGET").new"
rm -rf "$TMPTARGET"
mkdir -p "$(dirname "$PLUGINS_TARGET")"
mv "$STAGING" "$TMPTARGET"

# Ownership for the consumer (Hermes runs as uid 10000).
chown -R "$PLUGINS_OWNER" "$TMPTARGET"
chmod -R u+rwX,go+rX,go-w "$TMPTARGET"

# Swap into place.
if [ -e "$PLUGINS_TARGET" ]; then
  OLD="$(dirname "$PLUGINS_TARGET")/.$(basename "$PLUGINS_TARGET").old"
  rm -rf "$OLD"
  mv "$PLUGINS_TARGET" "$OLD"
fi
mv "$TMPTARGET" "$PLUGINS_TARGET"
rm -rf "$(dirname "$PLUGINS_TARGET")/.$(basename "$PLUGINS_TARGET").old" 2>/dev/null || true

log "wrote $ok plugins to $PLUGINS_TARGET ($miss missed)"
log "done."
