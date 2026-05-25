#!/bin/sh
# skill-sync.sh — GitOps skill loader for SKILL.md-tree repositories.
#
# Reads a wanted-bundles manifest, resolves bundle → skill lists from a
# remote git repo (mission-kit-format: skills/<name>/SKILL.md trees +
# bundles/<role>.yaml composition files), and writes the filtered set
# to a target directory.
#
# Agent-agnostic: any harness that reads SKILL.md trees from a directory
# can consume the output. Hermes is the first consumer; the loader has
# no Hermes-specific code paths.
#
# Inputs (env):
#   SKILL_SYNC_REPO          git URL of the source repo (default: apnex/mission-kit)
#   SKILL_SYNC_REF           git ref to pull (default: main)
#   SKILL_SYNC_MANIFEST      path to wanted-bundles.yaml (required)
#   SKILL_SYNC_TARGET        output directory (default: /opt/data/extra-skills)
#   SKILL_SYNC_OWNER         chown target to this uid:gid (default: 10000:10000)
#
# Manifest format (wanted-bundles.yaml):
#   bundles:
#     - <bundle-name>        # resolved via bundles/<name>.yaml in source repo
#   extra_skills:
#     - <skill-name>         # always pulled, bypasses bundle resolution
#
# Behaviour:
#   - Idempotent: target dir is wiped and rewritten each run.
#   - Best-effort: missing bundles/skills are logged, never fatal,
#     unless every requested item fails to resolve.
#   - Designed to run as an initContainer (one-shot) OR as a sidecar
#     loop (re-run on interval).

set -eu

# --- defaults ---------------------------------------------------------
SKILL_SYNC_REPO="${SKILL_SYNC_REPO:-https://github.com/apnex/mission-kit.git}"
SKILL_SYNC_REF="${SKILL_SYNC_REF:-main}"
SKILL_SYNC_MANIFEST="${SKILL_SYNC_MANIFEST:?SKILL_SYNC_MANIFEST is required}"
SKILL_SYNC_TARGET="${SKILL_SYNC_TARGET:-/opt/data/extra-skills}"
SKILL_SYNC_OWNER="${SKILL_SYNC_OWNER:-10000:10000}"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

log() { printf '[skill-sync] %s\n' "$*"; }

# --- 1. clone source repo --------------------------------------------
log "cloning $SKILL_SYNC_REPO@$SKILL_SYNC_REF"
git clone --depth 1 --branch "$SKILL_SYNC_REF" \
    "$SKILL_SYNC_REPO" "$WORKDIR/repo" 2>&1 | sed 's/^/[skill-sync]   /'

REPO="$WORKDIR/repo"

# --- 2. parse wanted-bundles manifest --------------------------------
# Manifest is small YAML — extract bundle names and extra skills with
# awk to avoid pulling a yaml parser into the image. Lines we care about:
#   bundles:
#     - foo
#     - bar
#   extra_skills:
#     - baz

if [ ! -f "$SKILL_SYNC_MANIFEST" ]; then
  log "ERROR: manifest not found at $SKILL_SYNC_MANIFEST"
  exit 1
fi

log "reading manifest $SKILL_SYNC_MANIFEST"

# Extract list items under a given top-level key.
extract_list() {
  key="$1"
  awk -v key="$key" '
    $0 ~ "^"key":" { in_list=1; next }
    in_list && /^[a-zA-Z_]/ { in_list=0 }
    in_list && /^  *-/ {
      sub(/^  *-[ \t]*/, "")
      sub(/[ \t]*$/, "")
      if (length($0) > 0) print
    }
  ' "$SKILL_SYNC_MANIFEST"
}

BUNDLES="$(extract_list bundles || true)"
EXTRAS="$(extract_list extra_skills || true)"

log "requested bundles: $(echo $BUNDLES | tr '\n' ' ')"
log "requested extras:  $(echo $EXTRAS | tr '\n' ' ')"

# --- 3. resolve bundles → skill names --------------------------------
# Each bundle is bundles/<name>.yaml with a "skills:" list. Extract
# items the same way as the manifest parser.

RESOLVED=""
for bundle in $BUNDLES; do
  bundle_file="$REPO/bundles/$bundle.yaml"
  if [ ! -f "$bundle_file" ]; then
    log "WARN: bundle '$bundle' not found at bundles/$bundle.yaml — skipping"
    continue
  fi
  skills_in_bundle="$(awk '
    /^skills:/ { in_list=1; next }
    in_list && /^[a-zA-Z_]/ { in_list=0 }
    in_list && /^  *-/ {
      sub(/^  *-[ \t]*/, "")
      sub(/[ \t]*$/, "")
      sub(/[ \t]*#.*$/, "")
      if (length($0) > 0) print
    }
  ' "$bundle_file")"
  log "bundle '$bundle' → $(echo $skills_in_bundle | tr '\n' ' ')"
  RESOLVED="$RESOLVED $skills_in_bundle"
done

# Combine bundle-resolved skills + extras, deduplicate.
WANTED="$(printf '%s\n%s\n' "$RESOLVED" "$EXTRAS" | tr ' ' '\n' \
          | sed '/^$/d' | sort -u)"

if [ -z "$WANTED" ]; then
  log "no skills requested after resolution — nothing to do"
  exit 0
fi

log "final skill set: $(echo $WANTED | tr '\n' ' ')"

# --- 4. write to target ----------------------------------------------
# Idempotent: rewrite the target dir each run. The local /opt/data/skills/
# is left untouched — this loader only owns SKILL_SYNC_TARGET.

STAGING="$WORKDIR/staging"
mkdir -p "$STAGING"

ok=0
miss=0
for skill in $WANTED; do
  src="$REPO/skills/$skill"
  if [ ! -d "$src" ] || [ ! -f "$src/SKILL.md" ]; then
    log "WARN: skill '$skill' not found at skills/$skill/SKILL.md — skipping"
    miss=$((miss + 1))
    continue
  fi
  cp -a "$src" "$STAGING/$skill"
  log "  + $skill"
  ok=$((ok + 1))
done

if [ "$ok" -eq 0 ]; then
  log "ERROR: zero skills resolved successfully ($miss missed)"
  exit 1
fi

# Atomic-ish swap: write to a tmp dir adjacent to target, then mv.
TMPTARGET="$(dirname "$SKILL_SYNC_TARGET")/.$(basename "$SKILL_SYNC_TARGET").new"
rm -rf "$TMPTARGET"
mkdir -p "$(dirname "$SKILL_SYNC_TARGET")"
mv "$STAGING" "$TMPTARGET"

# Ownership for the consumer (Hermes runs as uid 10000).
chown -R "$SKILL_SYNC_OWNER" "$TMPTARGET"
chmod -R u+rwX,go+rX,go-w "$TMPTARGET"

# Swap into place.
if [ -e "$SKILL_SYNC_TARGET" ]; then
  OLD="$(dirname "$SKILL_SYNC_TARGET")/.$(basename "$SKILL_SYNC_TARGET").old"
  rm -rf "$OLD"
  mv "$SKILL_SYNC_TARGET" "$OLD"
fi
mv "$TMPTARGET" "$SKILL_SYNC_TARGET"
rm -rf "$(dirname "$SKILL_SYNC_TARGET")/.$(basename "$SKILL_SYNC_TARGET").old" 2>/dev/null || true

log "wrote $ok skills to $SKILL_SYNC_TARGET ($miss missed)"
log "done."
