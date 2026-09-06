# Live merge happy path (preconditions)

Live merge happy path (preconditions) inventories the operator's live merge
measurement. Without a new authorization and a concrete disposable destination
it returns `unknown`/`BLOCKED` and makes no GitHub call. Preparing the manual
procedure does not authorize running it. Live measurement stays Optional.
Status: inventariado; no observado. Phase 18 closeout (18.10) keeps that
honesty: green⇒merge was never seen live.

## Sub-features

- `live-blocked-no-auth` reports `unknown`/`BLOCKED` and records that no
  external `gh`/`curl`/`ssh` call ran.
- `live-current-reasons` names the current gaps (authorization/destination,
  fake or missing `gh`) instead of a stale historical block.
- `live-manual-procedure` writes the disposable-repo / topic+marker / host /
  cost-quota / SHA-PR / redacted-capture checklist and does not execute it.
- `live-no-sim-credit` refuses to treat a simulated `saikit-merge` PASS as a
  live merge. `live_merge` stays `unknown`.
- `live-no-seal-transfer` keeps a child-session seal off the parent: no copy
  by newer mtime or by the presence of `verified:` (limit 18.26).

## How to get to it (user POV)

- Run `control-summonaikit doctor merge-happy-path` to see current blockers.
- Run `control-summonaikit drive merge-happy-path` to evaluate preconditions
  only. It never merges, never talks to live GitHub, and never writes the
  operator's live profiles.
- A future live measurement needs a new, concrete operator authorization for
  a disposable repo. Phase 18 authorizations do not carry over.

## Driving it with control-summonaikit

Preconditions:

- `control-summonaikit launch` created an isolated HOME (the drive needs a run).
- No `SAIKIT_LIVE_AUTH` + `SAIKIT_LIVE_DEST` pair authorizes a live merge.
  Even when both are set, this driver still does not merge.
- A script named `gh` on `PATH` is not live access. Official `gh --version`
  is local only; this drive does not call `gh pr` / `gh api`.

- Case `live-blocked-no-auth`: action Evaluate live merge without a valid authorization or concrete destination; command `control-summonaikit drive merge-happy-path`; observable `unknown`/`BLOCKED` and `no-external-call`.
- Case `live-current-reasons`: action Name the current missing live dependencies; command `control-summonaikit drive merge-happy-path`; observable reasons that mention authorization/destination and `gh` (absent or fake).
- Case `live-manual-procedure`: action Print the Optional measurement checklist; command `control-summonaikit drive merge-happy-path`; observable topic+marker, host, cost/quota, SHA/PR, redacted capture, and `no-autoriza-ejecutar`.
- Case `live-no-sim-credit`: action Compare against the simulated merge feature; command `control-summonaikit drive merge-happy-path`; observable `simulated` is not live and `live_merge` stays `unknown` (`live-merge-not-run`).
- Case `live-no-seal-transfer`: action Plant a child seal with newer mtime and a parent log that already has `verified:`; command `control-summonaikit drive merge-happy-path`; observable parent state untouched and no mtime/`verified` transfer.

- **Proof.** Keep the attempt under `artifacts/<run>/merge-happy-path/<attempt>/`.
  Summary `mode` must be `live` and `result` must be `unknown`. A simulated
  `MERGE-OK:` from `saikit-merge` is not this feature.

## Gotchas

- Simulation never fills the live-merge assertion. Do not treat
  `drive saikit-merge` as `merge-happy-path`.
- Do not transfer a child reviewer seal, log, or `veredicto_sha256` onto the
  parent because the child file is newer or the parent already shows
  `verified:` (18.26). There is no bypass. In the measured Grok path the
  merge stays manual.
- 18.27 fixed the headless Stop hatch (wake form + DELEGATED needs in-flight
  work) and still does not guarantee a receipt on every headless exit. Merge
  stay fail-closed without the receipt; ceremony closeout is best-effort.
- 18.10 closed the phase docs/guide with those limits: inventariado; no
  observado. A skill PASS here is not a live merge.
- Do not run this against live `~/.claude`, `~/.grok`, `~/.dsh`, or
  `~/.codex`. Do not merge. Preparing the procedure is not permission.
