# Check the deploy log

Check the deploy log validates `docs/deploy-log.md`: ordered entries, required
fields, and one record per PR/change after a merge deploy.

## Sub-features

- `deploy-log-ok` exits 0 with an `[deploy-log] OK` line when the log is valid.
- `deploy-log-order` exits non-zero and names `orden` when dates increase downward.
- `deploy-log-dup` exits non-zero and names the duplicated PR.

## How to get to it (user POV)

- After deploying hooks post-merge, append a row to `docs/deploy-log.md`.
- Run `bash tools/check-deploy-log.sh` to validate the log.

## Driving it with control-summonaikit

Preconditions:

- `control-summonaikit doctor` reports `doctor: PASS`.
- The driver writes disposable fixtures; it does not rewrite the checkout log.

- Case `deploy-log-ok`: action Validate a well-formed fixture; command `control-summonaikit drive-deploy-log`; observable exit `0` and `[deploy-log] OK`.
- Case `deploy-log-order`: action Reject inverted dates; command `control-summonaikit drive check-deploy-log`; observable exit non-zero and reason `orden`.
- Case `deploy-log-dup`: action Reject a repeated PR; command `control-summonaikit drive check-deploy-log`; observable exit non-zero naming `#203`.

- **Proof.** Keep the attempt. A header or exit 0 on the real log is not
  enough: each case records the concrete reason from its fixture.

## Gotchas

- Deploy itself (`tools/install-hook.sh` to live hosts) is operator-only and
  outside this skill's write path.
- A valid deploy log does not prove the live hosts are up to date; pair with
  the operator's `install-hook.sh --check` when that is the question.
- Do not invent deploy-log entries to make the drive pass.
