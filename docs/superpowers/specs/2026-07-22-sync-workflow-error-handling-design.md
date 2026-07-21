# Sync Workflow Error Handling Design

## Goal

Make automated and manual synchronization distinguish a clean no-change run from an upstream or script failure, and correct the documented update command.

## Exit-Code Contract

`scripts/sync-skills.sh` will use these exit codes:

- `0`: synchronization completed and changed the local skills tree.
- `1`: synchronization completed successfully with no changes.
- `2`: synchronization could not complete for one or more configured upstreams.

The script may continue checking later upstreams after an upstream-specific failure so all failures are reported, but it must return `2` at the end. A missing upstream `skills/` directory is an invalid synchronization source and therefore also counts as a failure.

## Consumers

The GitHub Actions workflow will capture the sync exit code explicitly. It will continue to change detection only for exit code `0`, end successfully without a commit for exit code `1`, and fail the job for exit code `2` or any unexpected code.

`scripts/update-skills.sh` will apply the same interpretation. It will continue to staging and commit only after exit code `0`, skip the commit path after exit code `1`, and stop before staging or pushing after a real failure.

## Documentation

README examples will reference the existing `scripts/update-skills.sh` script rather than the nonexistent `scripts/update.sh` path.

## Verification

Repository tests will exercise the documented exit-code cases using isolated temporary Git repositories and local upstream fixtures. Static checks will validate shell syntax and confirm the workflow consumes the three-state result without masking failures.
