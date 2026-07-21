#!/usr/bin/env bash
set -u
set -o pipefail

PROJECT_ROOT=$(cd "$(dirname "$0")/.." && pwd)
FAILURES=0
TEST_ROOT=""

cleanup() {
  if [ -n "$TEST_ROOT" ] && [ -d "$TEST_ROOT" ]; then
    rm -rf "$TEST_ROOT"
  fi
}
trap cleanup EXIT

fail() {
  echo "FAIL: $1"
  FAILURES=$((FAILURES + 1))
}

pass() {
  echo "PASS: $1"
}

assert_eq() {
  EXPECTED=$1
  ACTUAL=$2
  MESSAGE=$3
  if [ "$EXPECTED" = "$ACTUAL" ]; then
    pass "$MESSAGE"
  else
    fail "$MESSAGE (expected $EXPECTED, got $ACTUAL)"
  fi
}

assert_file() {
  if [ -f "$1" ]; then
    pass "$1 exists"
  else
    fail "$1 does not exist"
  fi
}

assert_not_file() {
  if [ ! -e "$1" ]; then
    pass "$1 was removed"
  else
    fail "$1 still exists"
  fi
}

prepare_fixture() {
  cleanup
  TEST_ROOT=$(mktemp -d)
  TEST_REPO="$TEST_ROOT/repo"
  FAKE_BIN="$TEST_ROOT/bin"
  mkdir -p "$TEST_REPO/scripts" "$FAKE_BIN"
  cp "$PROJECT_ROOT/scripts/sync-skills.sh" "$TEST_REPO/scripts/"
  echo 'https://example.test/source.git:main:managed' > "$TEST_REPO/upstreams.txt"

  cat > "$FAKE_BIN/git" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  rev-parse)
    echo "$TEST_REPO"
    ;;
  clone)
    if [ "$FAKE_CLONE_MODE" = "clone-failure" ]; then
      exit 1
    fi
    for ARG in "$@"; do
      CLONE_DIR=$ARG
    done
    mkdir -p "$CLONE_DIR"
    if [ "$FAKE_CLONE_MODE" = "success" ]; then
      mkdir -p "$CLONE_DIR/skills"
      touch "$CLONE_DIR/skills/current.txt"
    fi
    ;;
  sparse-checkout|checkout)
    ;;
  *)
    echo "Unexpected fake git command: $*" >&2
    exit 99
    ;;
esac
EOF
  chmod +x "$FAKE_BIN/git" "$TEST_REPO/scripts/sync-skills.sh"
}

run_sync() {
  (
    cd "$TEST_REPO" || exit 99
    PATH="$FAKE_BIN:$PATH" \
      TEST_REPO="$TEST_REPO" \
      FAKE_CLONE_MODE="$1" \
      scripts/sync-skills.sh >/dev/null
  )
  SYNC_STATUS=$?
}

test_changed_sync_returns_zero_and_deletes_stale_files() {
  prepare_fixture
  mkdir -p "$TEST_REPO/skills/managed"
  touch "$TEST_REPO/skills/managed/stale.txt"
  run_sync success
  assert_eq 0 "$SYNC_STATUS" "changed sync returns zero"
  assert_file "$TEST_REPO/skills/managed/current.txt"
  assert_not_file "$TEST_REPO/skills/managed/stale.txt"
}

test_unchanged_sync_returns_one() {
  prepare_fixture
  mkdir -p "$TEST_REPO/skills/managed"
  touch "$TEST_REPO/skills/managed/current.txt"
  run_sync success
  assert_eq 1 "$SYNC_STATUS" "unchanged sync returns one"
}

test_clone_failure_returns_two() {
  prepare_fixture
  run_sync clone-failure
  assert_eq 2 "$SYNC_STATUS" "clone failure returns two"
}

test_missing_skills_directory_returns_two() {
  prepare_fixture
  run_sync no-skills
  assert_eq 2 "$SYNC_STATUS" "missing skills directory returns two"
}

test_changed_sync_returns_zero_and_deletes_stale_files
test_unchanged_sync_returns_one
test_clone_failure_returns_two
test_missing_skills_directory_returns_two
cleanup
TEST_ROOT=""

if [ "$FAILURES" -ne 0 ]; then
  echo "$FAILURES test assertion(s) failed"
  exit 1
fi

echo "All sync workflow tests passed"
