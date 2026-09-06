# Merge a sealed PR (simulated)

Merge a sealed PR (simulated) drives `tools/saikit-merge.sh` against a
disposable Git repo and a strict fake `gh` that only answers the forms the
tool uses and records argv. The mode is always `simulated`: no live GitHub.

## Sub-features

- `merge-listo` reports `LISTO:` and does not call `gh pr merge`.
- `merge-confirmado` revalidates head, CI and the sealed verdict, then merges
  with `--match-head-commit` and without `--admin` or `--delete-branch`.
- `merge-ci-rojo`, `merge-base-movida`, `merge-sello-ajeno` and
  `merge-head-cambiado` reject and never call merge.
- `revert-ok` merges an exact inverse of the fixture tip that carries the
  trailer; `revert-sin-trailer` and `revert-no-punta` refuse anything else.

## How to get to it (user POV)

- From a task branch with a sealed verdict, run `bash tools/saikit-merge.sh`.
  When every check is green it prints `LISTO:` and stops.
- The operator authorizes the merge with `bash tools/saikit-merge.sh --confirmado`.
  That run repeats the whole gate (SHA, CI, seal). If anything moved, it
  prints `NO-MERGE:` and does not merge.
- `bash tools/saikit-merge.sh --revert-de <merge_commit>` only reverts the
  tip of the configured base when that commit has a `Saikit-Merge:` trailer.

## Driving it with control-summonaikit

Preconditions:

- `control-summonaikit launch` created an isolated HOME (the drive needs a run).
- `control-summonaikit doctor saikit-merge` reports simulated `gh` ready; a
  missing live `gh` does not block this feature.
- The driver builds a disposable work repo and local bare origin. It never
  merges the operator checkout or talks to real GitHub.

- Case `merge-listo`: action Run the gate without confirmation; command `control-summonaikit drive saikit-merge`; observable `LISTO:` and no `gh pr merge`.
- Case `merge-confirmado`: action Confirm after a green gate; command `control-summonaikit drive saikit-merge`; observable `MERGE-OK:`, `--match-head-commit <head>`, `gh run list`, seal bytes unchanged, and argv without `--admin` or `--delete-branch`.
- Case `merge-ci-rojo`: action Confirm with a failed CI fixture; command `control-summonaikit drive saikit-merge`; observable `NO-MERGE: CI rojo` and no merge call.
- Case `merge-base-movida`: action Confirm after the base advanced; command `control-summonaikit drive saikit-merge`; observable `NO-MERGE: base avanzada` and no merge call.
- Case `merge-sello-ajeno`: action Confirm with a verdict for another SHA; command `control-summonaikit drive saikit-merge`; observable `NO-MERGE: veredicto de otro sha` and no merge call.
- Case `merge-head-cambiado`: action Confirm after commits landed past the seal; command `control-summonaikit drive saikit-merge`; observable `NO-MERGE: commits despues del veredicto` and no merge call.
- Case `revert-ok`: action Confirm `--revert-de` of the fixture tip with trailer; command `control-summonaikit drive saikit-merge`; observable `MERGE-OK:` and `--match-head-commit` of the revert head.
- Case `revert-sin-trailer`: action Confirm `--revert-de` of a tip without trailer; command `control-summonaikit drive saikit-merge`; observable `NO-MERGE: sin trailer` and no merge call.
- Case `revert-no-punta`: action Confirm `--revert-de` of a commit that is no longer the tip; command `control-summonaikit drive saikit-merge`; observable `NO-MERGE: no es la punta` and no merge call.

- **Proof.** Keep the attempt under `artifacts/<run>/saikit-merge/<attempt>/`.
  Summary `mode` must be `simulated`. A `LISTO:` line alone is not proof: the
  fake `gh` log must show no `pr merge` on rejects, and the confirmado argv
  must pin the correct head.

## Gotchas

- This drive never uses `--admin` or `--delete-branch`. The fake `gh` rejects
  unexpected forms and records argv.
- `--confirmado` confirms intent, not yesterday's conditions. A moved base,
  red CI, foreign seal or new head after the seal must not merge.
- `--revert-de` does not authorize other branches: only the current tip of
  the configured base, and only with the `Saikit-Merge:` trailer.
- A live `gh` in PATH is not evidence of this feature. Mode `live` belongs
  to `merge-happy-path`, which stays blocked without a new authorization.
