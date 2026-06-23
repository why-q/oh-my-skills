#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# sync-skills.sh
# Reads upstreams from upstreams.txt and synchronizes the
# skills/ subdirectory from each upstream repo into the
# local skills/ directory.
#
# Usage: ./scripts/sync-skills.sh
# ============================================================

REPO_ROOT="$(git rev-parse --show-toplevel)"
UPSTREAMS_FILE="$REPO_ROOT/upstreams.txt"
SKILLS_DIR="$REPO_ROOT/skills"
TMP_DIR=$(mktemp -d)
CHANGES=0

# ── Validate ────────────────────────────────────────────────
if [ ! -f "$UPSTREAMS_FILE" ]; then
  echo "❌ Error: $UPSTREAMS_FILE not found"
  exit 1
fi

# Count valid (non-blank, non-comment) entries
ENTRY_COUNT=$(grep -v '^\s*$' "$UPSTREAMS_FILE" | grep -v '^\s*#' | wc -l | xargs)
if [ "$ENTRY_COUNT" -eq 0 ]; then
  echo "⚠️  No upstreams defined in $UPSTREAMS_FILE"
  exit 1
fi

echo "=== Skills Sync Started ==="
echo "    Upstreams file: $UPSTREAMS_FILE"
echo "    Entries found:  $ENTRY_COUNT"
echo ""

# Read upstreams.txt line by line (compatible with Bash 3.2+)
while IFS= read -r LINE || [ -n "$LINE" ]; do
  # Skip blank lines and comments
  LINE=$(echo "$LINE" | xargs)
  if [ -z "$LINE" ] || [[ "$LINE" == \#* ]]; then
    continue
  fi

  # Parse URL:BRANCH:LOCAL_PREFIX (split from right to avoid breaking URLs with ':')
  LOCAL_PREFIX=$(echo "$LINE" | rev | cut -d':' -f1 | rev)
  REMAINING=$(echo "$LINE" | rev | cut -d':' -f2- | rev)
  UPSTREAM_BRANCH=$(echo "$REMAINING" | rev | cut -d':' -f1 | rev)
  UPSTREAM_URL=$(echo "$REMAINING" | rev | cut -d':' -f2- | rev)

  # Handle GitHub URL shorthand (owner/repo → full URL)
  if [[ "$UPSTREAM_URL" != http* ]]; then
    UPSTREAM_URL="https://github.com/${UPSTREAM_URL}.git"
  fi

  REPO_NAME=$(basename -s .git "$UPSTREAM_URL")
  CLONE_DIR="$TMP_DIR/$REPO_NAME"

  echo "--- Syncing: $UPSTREAM_URL (branch: $UPSTREAM_BRANCH) → skills/${LOCAL_PREFIX:-(root)} ---"

  # Clone with sparse checkout (only the skills/ directory)
  if ! git clone --depth 1 --branch "$UPSTREAM_BRANCH" \
    --filter=blob:none \
    --no-checkout \
    "$UPSTREAM_URL" "$CLONE_DIR" 2>/dev/null; then
    echo "  ❌ Failed to clone $UPSTREAM_URL — skipping"
    continue
  fi

  cd "$CLONE_DIR"
  git sparse-checkout init --cone 2>/dev/null
  git sparse-checkout set skills 2>/dev/null
  git checkout 2>/dev/null

  # Verify the skills/ dir exists in upstream
  if [ ! -d "skills" ]; then
    echo "  ⚠️  No 'skills/' directory found in $REPO_NAME — skipping"
    cd - > /dev/null
    continue
  fi

  # Determine target directory
  if [ -n "$LOCAL_PREFIX" ]; then
    TARGET_DIR="$SKILLS_DIR/$LOCAL_PREFIX"
  else
    TARGET_DIR="$SKILLS_DIR"
  fi

  # Compare: skip if nothing changed
  if [ -d "$TARGET_DIR" ]; then
    DIFF_OUTPUT=$(diff -rq "skills/" "$TARGET_DIR/" 2>/dev/null || true)
    if [ -z "$DIFF_OUTPUT" ]; then
      echo "  ✅ Already up to date — no changes"
      cd - > /dev/null
      continue
    fi
  fi

  # Rsync: copy contents, remove stale files, preserve structure
  mkdir -p "$TARGET_DIR"
  rsync -a --delete "skills/" "$TARGET_DIR/"
  echo "  🔄 Updated: skills/ → $TARGET_DIR/"
  CHANGES=1

  cd - > /dev/null

done < <(grep -v '^\s*$' "$UPSTREAMS_FILE" | grep -v '^\s*#')

# Cleanup
rm -rf "$TMP_DIR"

echo ""
if [ "$CHANGES" -eq 1 ]; then
  echo "=== ✅ Changes detected — ready to commit ==="
  exit 0
else
  echo "=== ✅ All skills are up to date ==="
  exit 1
fi
