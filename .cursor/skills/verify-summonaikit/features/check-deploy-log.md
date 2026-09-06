# Check the deploy log

Check the deploy log validates `docs/deploy-log.md`: ordered entries, required
fields, and one record per PR/change after a merge deploy.

## Sub-features

- `deploy-log-run` executes `tools/check-deploy-log.sh`.
- `deploy-log-ok` exits 0 with an `[deploy-log] OK` line when the log is valid.
- `deploy-log-fail` exits non-zero when order, format, or duplicates break the norm.

## How to get to it (user POV)

- After deploying hooks post-merge, append a row to `docs/deploy-log.md`.
- Run `bash tools/check-deploy-log.sh` to validate the log.

## Driving it with control-summonaikit

Preconditions:

- `control-summonaikit doctor` reports `doctor: PASS`.
- `docs/deploy-log.md` exists in the checkout.

- Case `deploy-log-run`: action Validate deploy log; command `control-summonaikit drive-deploy-log`; observable exit `0` and `[deploy-log] OK` in the artifact.

- **Proof.** Keep the artifact. On failure, record the tool's complaint lines
  (order / norma / duplicate PR) instead of rewriting the log mid-drive.

## Gotchas

- Deploy itself (`tools/install-hook.sh` to live hosts) is operator-only and
  outside this skill's write path.
- A valid deploy log does not prove the live hosts are up to date; pair with
  the operator's `install-hook.sh --check` when that is the question.
- Do not invent deploy-log entries to make the drive pass.
