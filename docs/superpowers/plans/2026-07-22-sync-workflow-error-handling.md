# Sync Workflow Error Handling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make local and automated skill synchronization report upstream failures instead of treating them as a successful no-change run, while correcting the documented update command.

**Architecture:** Keep the existing three-state sync interface and formalize it as exit codes `0` (changed), `1` (unchanged), and `2` (failed). A shell regression harness supplies a fake `git` executable so sync behavior can be tested deterministically without network access; the two consumers then branch explicitly on that contract.

**Tech Stack:** Bash 3.2-compatible shell scripts, GitHub Actions YAML, Git, rsync

---

## File Structure

- Create `tests/test-sync-workflow.sh`: isolated regression harness for sync exit codes, deletion behavior, and consumer handling.
- Modify `scripts/sync-skills.sh`: accumulate upstream failures and return exit code `2` after processing all entries.
- Modify `scripts/update-skills.sh`: stop on exit code `2` and continue only for the documented success codes.
- Modify `.github/workflows/sync-skills.yml`: capture the sync result without masking errors and gate change detection on a changed result.
- Modify `README.md`: use the real update script filename and document sync outcomes.

### Task 1: Lock Down the Sync Exit-Code Contract

**Files:**
- Create: `tests/test-sync-workflow.sh`
- Modify: `scripts/sync-skills.sh:16-118`

- [ ] **Step 1: Write failing sync regression tests**

Create a Bash test harness that copies `sync-skills.sh` into a temporary repository, places a fake `git` command first on `PATH`, and tests these observable cases:

```bash
run_sync() {
  set +e
  (
    cd "$TEST_REPO"
    PATH="$FAKE_BIN:$PATH" FAKE_CLONE_MODE="$1" scripts/sync-skills.sh
  )
  SYNC_STATUS=$?
  set -e
}

test_changed_sync_returns_zero_and_deletes_stale_files() {
  prepare_fixture success
  mkdir -p "$TEST_REPO/skills/managed"
  touch "$TEST_REPO/skills/managed/stale.txt"
  run_sync success
  assert_eq 0 "$SYNC_STATUS" "changed sync status"
  assert_file "$TEST_REPO/skills/managed/current.txt"
  assert_not_file "$TEST_REPO/skills/managed/stale.txt"
}

test_unchanged_sync_returns_one() {
  prepare_fixture success
  mkdir -p "$TEST_REPO/skills/managed"
  touch "$TEST_REPO/skills/managed/current.txt"
  run_sync success
  assert_eq 1 "$SYNC_STATUS" "unchanged sync status"
}

test_clone_failure_returns_two() {
  prepare_fixture clone-failure
  run_sync clone-failure
  assert_eq 2 "$SYNC_STATUS" "clone failure status"
}

test_missing_skills_directory_returns_two() {
  prepare_fixture no-skills
  run_sync no-skills
  assert_eq 2 "$SYNC_STATUS" "missing skills status"
}
```

The fake `git` must return the fixture root for `rev-parse`, create the requested clone directory and `skills/current.txt` for a successful `clone`, fail `clone` in `clone-failure` mode, and accept `sparse-checkout` and `checkout` commands.

- [ ] **Step 2: Run the regression tests and verify the error cases fail**

Run:

```bash
bash tests/test-sync-workflow.sh
```

Expected: the changed and unchanged cases pass; clone-failure and missing-skills cases report expected status `2` but receive status `1`.

- [ ] **Step 3: Implement failure accumulation in the sync script**

Initialize a failure flag alongside `CHANGES`:

```bash
CHANGES=0
FAILURES=0
```

Set `FAILURES=1` before continuing after either a failed clone or a missing upstream `skills/` directory. Replace the final status block with this precedence:

```bash
if [ "$FAILURES" -eq 1 ]; then
  echo "=== Sync incomplete: one or more upstreams failed ==="
  exit 2
elif [ "$CHANGES" -eq 1 ]; then
  echo "=== Changes detected - ready to commit ==="
  exit 0
else
  echo "=== All skills are up to date ==="
  exit 1
fi
```

- [ ] **Step 4: Run the sync regression tests and verify all cases pass**

Run:

```bash
bash tests/test-sync-workflow.sh
```

Expected: `PASS` for changed, unchanged, clone failure, and missing-skills cases; exit code `0` from the test harness.

- [ ] **Step 5: Commit the sync contract and tests**

```bash
git add tests/test-sync-workflow.sh scripts/sync-skills.sh
git commit -m "fix(sync): report upstream failures"
```

### Task 2: Make Both Consumers Respect Sync Failures

**Files:**
- Modify: `tests/test-sync-workflow.sh`
- Modify: `scripts/update-skills.sh:40-46`
- Modify: `.github/workflows/sync-skills.yml:28-46`

- [ ] **Step 1: Add failing consumer regression checks**

Extend the harness with an update-script test using a fixture-local sync stub that exits `2` and a fake `git` command that records invocations:

```bash
test_update_stops_before_staging_after_sync_failure() {
  prepare_update_fixture 2
  run_update
  assert_eq 2 "$UPDATE_STATUS" "update failure status"
  assert_not_contains "add" "$GIT_CALL_LOG"
  assert_not_contains "push" "$GIT_CALL_LOG"
}
```

Add static workflow assertions that require an identified sync step, explicit changed output, and no `|| echo "NO_CHANGES=true"` masking expression:

```bash
assert_contains "id: sync" ".github/workflows/sync-skills.yml"
assert_contains 'changed=true' ".github/workflows/sync-skills.yml"
assert_not_contains 'scripts/sync-skills.sh || echo' ".github/workflows/sync-skills.yml"
```

- [ ] **Step 2: Run the tests and verify both consumer checks fail**

Run:

```bash
bash tests/test-sync-workflow.sh
```

Expected: failure because `update-skills.sh` proceeds to `git add`, and because the workflow still masks every nonzero sync result.

- [ ] **Step 3: Handle the three statuses in the local update script**

Replace the unconditional continuation with an explicit case statement:

```bash
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
```

- [ ] **Step 4: Capture and expose the three statuses in GitHub Actions**

Give the sync step `id: sync`, temporarily disable immediate shell exit while capturing the command status, and branch explicitly:

```yaml
- name: Run sync script
  id: sync
  run: |
    chmod +x scripts/sync-skills.sh
    set +e
    scripts/sync-skills.sh
    status=$?
    set -e
    case "$status" in
      0) echo "changed=true" >> "$GITHUB_OUTPUT" ;;
      1) echo "changed=false" >> "$GITHUB_OUTPUT" ;;
      *) echo "Skills sync failed with status $status"; exit "$status" ;;
    esac
```

Gate change detection with `if: steps.sync.outputs.changed == 'true'`. Keep commit and push gated by the change-check step's `has_changes` output.

- [ ] **Step 5: Run the consumer regression tests**

Run:

```bash
bash tests/test-sync-workflow.sh
```

Expected: all sync and consumer cases pass with exit code `0`.

- [ ] **Step 6: Commit the consumer fixes**

```bash
git add tests/test-sync-workflow.sh scripts/update-skills.sh .github/workflows/sync-skills.yml
git commit -m "fix(workflow): preserve sync failures"
```

### Task 3: Correct Documentation and Run Full Verification

**Files:**
- Modify: `README.md:11-18`
- Modify: `tests/test-sync-workflow.sh`

- [ ] **Step 1: Add a failing documentation regression check**

Add assertions to the test harness:

```bash
assert_contains './scripts/update-skills.sh' "README.md"
assert_not_contains './scripts/update.sh' "README.md"
```

- [ ] **Step 2: Run the test and verify it fails on the obsolete path**

Run:

```bash
bash tests/test-sync-workflow.sh
```

Expected: failure reporting that `README.md` still contains `./scripts/update.sh`.

- [ ] **Step 3: Correct and clarify README usage**

Change both update examples to:

```bash
./scripts/update-skills.sh          # sync + commit + push
./scripts/update-skills.sh --ci     # also trigger GitHub Action
```

Add a concise note after manual sync explaining that status `1` means no changes and status `2` means at least one configured upstream failed.

- [ ] **Step 4: Run all repository verification**

Run:

```bash
bash tests/test-sync-workflow.sh
bash -n scripts/sync-skills.sh
bash -n scripts/update-skills.sh
git diff --check
```

Expected: the regression harness exits `0`, both syntax checks exit `0`, and `git diff --check` produces no output.

- [ ] **Step 5: Review the final diff against the approved design**

Run:

```bash
git diff -- README.md scripts/sync-skills.sh scripts/update-skills.sh .github/workflows/sync-skills.yml tests/test-sync-workflow.sh
git status --short
```

Expected: only the planned implementation files are changed, and the diff implements all four design sections: exit codes, local consumer, Actions consumer, and documentation.

- [ ] **Step 6: Commit the documentation and final test assertions**

```bash
git add README.md tests/test-sync-workflow.sh
git commit -m "docs: correct skill update command"
```
