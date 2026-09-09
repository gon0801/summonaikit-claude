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
- `merge-lock-contencion`, `merge-lock-propio`, `merge-lock-worktrees` and
  `merge-lock-recuperacion` drive the integration lock
  (`<git-common-dir>/saikit-merge.lock`, 20.5): a second `--confirmado` while
  another holds the lock exits 3 reporting the owner and the
  `--liberar-lock` hint without merging; the owner releases only its own lock
  on exit (an alien lock survives a rejected run); the lock is shared by every
  worktree of the clone; and `--liberar-lock` is the only explicit recovery —
  it prints the lock content, removes it, and is a green no-op without lock.
  Anchored by the product cases `c_lock_dos_procesos`, `c_lock_exclusion`,
  `c_lock_libera_propio`, `c_lock_dos_worktrees`, `c_lock_caida`,
  `c_lock_reintento_revalida` and `c_lock_entre_clones`
  (tests/test_saikit_merge.sh).

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
- Case `merge-lock-contencion`: action Hold the lock with a confirming run (`SAIKIT_MERGE_SOSTENER_SEG` test seam) and confirm from a second process; command `control-summonaikit drive saikit-merge`; observable exit 3 with `LOCK de integracion ocupado`, the `--liberar-lock` hint, and no `gh pr merge` from the rejected run.
- Case `merge-lock-propio`: action Let the owner finish while a rejected contender exits 3; command `control-summonaikit drive saikit-merge`; observable the alien lock still present after the rejected run and gone once the owner exits.
- Case `merge-lock-worktrees`: action Confirm from a second worktree of the same clone while the owner holds the lock; command `control-summonaikit drive saikit-merge`; observable exit 3 naming the SAME lock path of the main worktree and no merge call.
- Case `merge-lock-recuperacion`: action Plant a leftover lock (dead owner) and run `--liberar-lock`, then again with no lock; command `control-summonaikit drive saikit-merge`; observable first run prints the lock fields and removes it (exit 0), second run is a green `nada que liberar`.

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
  to `merge-happy-path`, which stays blocked without a new authorization
  (inventariado; no observado).
- 18.26: a child-session seal does not credit the parent. In the measured
  Grok path the merge stays manual; this simulated drive does not close that
  live gap.
- The lock is per `git-common-dir`: it serializes every worktree of one clone
  but promises nothing between independent clones or machines (there the
  leader keeps integrating serially). Exit 3 (alien lock) is a different
  channel from exit 1 (`NO-MERGE`); a `LISTO:`/dry-run run never takes it.
- The lock never frees itself: a killed owner (kill -9, no trap) leaves it
  behind on purpose, and only `--liberar-lock` removes it. Everything the
  gate decides runs AFTER acquiring the lock, so a retry revalidates head,
  CI and seal from scratch.
