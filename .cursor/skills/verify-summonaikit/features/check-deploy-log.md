# Check the deploy log

Check the deploy log validates `docs/deploy-log.md`: ordered entries, required
fields, and one record per PR/change after a merge deploy.

## Sub-features

- `deploy-log-ok` exits 0 with an `[deploy-log] OK` line when the log is valid.
- `deploy-log-order` exits non-zero and names `orden` when dates increase downward.
- `deploy-log-dup` exits non-zero and names the duplicated PR.
- `deploy-log-hora-evidente` accepts a deploy hour backed by an installer `.bak` name (recoverable).
- `deploy-log-hora-no-recuperada` accepts the honest `hora no recuperada` bullet (unknown, not rejected).
- `deploy-log-hora-sin-evidencia` rejects a deploy hour with no deploy evidence, naming `evidencia`.

## How to get to it (user POV)

- After deploying hooks post-merge, append a row to `docs/deploy-log.md`.
- Run `bash tools/check-deploy-log.sh` to validate the log.

## Driving it with control-summonaikit

Preconditions:

- `control-summonaikit doctor check-deploy-log` reports `doctor: PASS`; this
  fixture audit does not require hook preparation.
- The driver writes disposable fixtures; it does not rewrite the checkout log.

- Case `deploy-log-ok`: action Validate a well-formed fixture; command `control-summonaikit drive-deploy-log`; observable exit `0` and `[deploy-log] OK`.
- Case `deploy-log-order`: action Reject inverted dates; command `control-summonaikit drive check-deploy-log`; observable exit non-zero and reason `orden`.
- Case `deploy-log-dup`: action Reject a repeated PR; command `control-summonaikit drive check-deploy-log`; observable exit non-zero naming `#203`.
- Case `deploy-log-hora-evidente`: action Validate a post-HORA_CONTROL entry whose Deploy bullet cites a `.bak` backup; command `control-summonaikit drive check-deploy-log`; observable exit `0` (hour is deploy-sourced).
- Case `deploy-log-hora-no-recuperada`: action Validate a post-HORA_CONTROL entry whose Deploy bullet says `hora no recuperada`; command `control-summonaikit drive check-deploy-log`; observable exit `0` (honest unknown).
- Case `deploy-log-hora-sin-evidencia`: action Reject a post-HORA_CONTROL entry whose Deploy bullet carries an hour with no `.bak` and no live-measured marker; command `control-summonaikit drive check-deploy-log`; observable exit `1` naming `evidencia`.

- **Proof.** Keep the attempt. A header or exit 0 on the real log is not
  enough: each case records the concrete reason from its fixture.

## Gotchas

- Deploy itself (`tools/install-hook.sh` to live hosts) is operator-only and
  outside this skill's write path.
- A valid deploy log does not prove the live hosts are up to date; pair with
  the operator's `install-hook.sh --check` when that is the question.
- History can be RECTIFIED, not rewritten silently, with a split rule: only
  MERGE data (merge hash and `mergedAt`) is corrected in place against
  GitHub (`mergedAt`/`mergeCommit`). A deploy hour is corrected ONLY against
  deploy evidence — installer backup names; with no evidence it is recorded
  as `hora no recuperada` (not recovered) and NEVER derived from `mergedAt`,
  which accredits the merge, not the deploy. Rectifications live under a
  dated banner section that names the affected PRs, describes the error, and
  states that the deploy itself was NOT repeated (see the
  `Rectificación histórica` banner in `docs/deploy-log.md`, 2026-09-07). The
  checker validates order, fields and one-record-per-PR. Since the checker's
  own cordon `HORA_CONTROL` (declared in its header, 2026-09-08), it also
  REQUIRES an explicit deploy source for every hour in the Deploy SECTION
  (all `- **Deploy...` bullets plus their continuation lines) of entries
  dated on or after that cordon: an installer backup name (`.bak` as a glued
  filename — a negated `.bak` in foreign prose does not count) or the
  explicit marker `hora medida en vivo`, both INSIDE that section. Hours
  equal to the merge hour are judged by evidence type, never by timestamp
  inequality; the judged region before the cordon keeps its ~10 legitimately
  live-measured hours without a marker and is not touched.
- Do not invent deploy-log entries to make the drive pass.
