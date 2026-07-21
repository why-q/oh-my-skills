#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# update.sh
# All-in-one: pull, sync skills, commit, push, and trigger Action.
#
# Usage:
#   ./scripts/update.sh          # sync + commit + push
#   ./scripts/update.sh --ci     # also trigger GitHub Action
# ============================================================

REPO_ROOT="$(git rev-parse --show-toplevel)"
SYNC_SCRIPT="$REPO_ROOT/scripts/sync-skills.sh"
REMOTE="origin"
BRANCH=$(git branch --show-current)

echo "=== oh-my-skills Update ==="
echo ""

# ── Step 0: Pull latest from remote ─────────────────────────
echo "[0/5] Pulling latest from $REMOTE/$BRANCH..."
if git pull --rebase "$REMOTE" "$BRANCH"; then
  echo "Up to date with remote"
else
  echo "Error: Pull failed — resolve conflicts manually, then re-run"
  exit 1
fi

# ── Step 1: Sync skills from upstreams ──────────────────────
echo ""
echo "[1/5] Syncing skills from upstreams..."
if [ ! -f "$SYNC_SCRIPT" ]; then
  echo "Error: $SYNC_SCRIPT not found"
  exit 1
fi

chmod +x "$SYNC_SCRIPT"

SYNC_STATUS=0
"$SYNC_SCRIPT" || SYNC_STATUS=$?

case "$SYNC_STATUS" in
  0)
    ;;
  1)
    echo ""
    echo "No upstream changes detected"
    ;;
  *)
    echo ""
    echo "Error: Skills sync failed with status $SYNC_STATUS"
    exit "$SYNC_STATUS"
    ;;
esac

# ── Step 2: Check for changes ───────────────────────────────
echo ""
echo "[2/5] Checking for changes..."

# Stage only relevant paths
git add upstreams.txt 'skills/*'

# Check if anything is staged
if git diff --cached --quiet; then
  echo "Nothing to commit — jumping to Action trigger"
  # Skip steps 3 and 4, go straight to step 5
else
  # ── Step 3: Commit ────────────────────────────────────────
  echo ""
  echo "[3/5] Committing changes..."

  # Detect what changed to build a meaningful commit message
  UPSTREAMS_CHANGED=false
  SKILLS_CHANGED=false

  if git diff --cached --name-only -- upstreams.txt | grep -q .; then
    UPSTREAMS_CHANGED=true
  fi
  if git diff --cached --name-only -- skills/ | grep -q .; then
    SKILLS_CHANGED=true
  fi

  # Determine commit message
  if [ "$UPSTREAMS_CHANGED" = true ] && [ "$SKILLS_CHANGED" = true ]; then
    COMMIT_MSG="feat(upstream): add/update upstream sources and sync skills"
  elif [ "$UPSTREAMS_CHANGED" = true ]; then
    COMMIT_MSG="feat(upstream): update upstream sources config"
  elif [ "$SKILLS_CHANGED" = true ]; then
    COMMIT_MSG="chore(skills): sync skills from upstreams"
  else
    COMMIT_MSG="chore(skills): update skills repository"
  fi

  git commit -m "$COMMIT_MSG"
  echo "Committed: $COMMIT_MSG"

  # ── Step 4: Push ──────────────────────────────────────────
  echo ""
  echo "[4/5] Pushing to $REMOTE/$BRANCH..."
  git push "$REMOTE" "$BRANCH"
  echo "Pushed to $REMOTE/$BRANCH"
fi

# ── Step 5: Optionally trigger GitHub Action ────────────────
TRIGGER_CI=false
for arg in "$@"; do
  if [ "$arg" = "--ci" ]; then
    TRIGGER_CI=true
  fi
done

echo ""
if [ "$TRIGGER_CI" = true ]; then
  echo "[5/5] Triggering GitHub Action..."
  REPO_URL=$(git remote get-url "$REMOTE")
  REPO_PATH=$(echo "$REPO_URL" | sed -E 's|.*github.com[:/]||; s|\.git$||')

  if [ -n "$REPO_PATH" ]; then
    TOKEN="${PAT_TOKEN:-}"
    if [ -z "$TOKEN" ]; then
      echo "No PAT_TOKEN env var set — skipping Action trigger"
      echo "Set it with: export PAT_TOKEN=your_token_here"
    else
      echo "[DEBUG] Github Action API - https://api.github.com/repos/$REPO_PATH/actions/workflows/sync-skills.yml/dispatches"
      HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST \
        -H "Authorization: token $TOKEN" \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/$REPO_PATH/actions/workflows/sync-skills.yml/dispatches" \
        -d '{"ref":"'"$BRANCH"'"}')
      echo "[DEBUG] HTTP status: $HTTP_STATUS"
      if [ "$HTTP_STATUS" -eq 204 ]; then
        echo "GitHub Action triggered successfully"
      else
        echo "Failed to trigger Action (HTTP $HTTP_STATUS) — you can trigger manually from the Actions tab"
      fi
    fi
  else
    echo "Could not determine repo path — trigger manually from the Actions tab"
  fi
else
  echo "[5/5] Skipping Action trigger (use --ci to trigger)"
fi

echo ""
echo "=== Done ==="
