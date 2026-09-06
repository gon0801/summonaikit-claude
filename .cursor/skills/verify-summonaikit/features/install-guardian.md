# Install the guardian

Install the guardian lets an operator publish or refresh the turn-gate hook into
an agent profile safely: classify the destination, refuse unknowns, and either
install or report without writing.

## Sub-features

- `install-dry-run` reports what would happen without writing.
- `install-isolated` installs the repo hook into a disposable HOME.
- `install-ownership` leaves the `# SAIKIT-CLAUDE-OWNED` marker on a successful install.
- `install-refuse-live` never targets the operator's live `~/.claude` from this skill.

## How to get to it (user POV)

- Run `bash tools/install-hook.sh --dry-run` to see the classification.
- Run `bash tools/install-hook.sh` (or `--host claude`) after a merge to deploy
  (operator-only; not part of automated verification).
- Run `bash tools/install-hook.sh --dest <path> --source … --manifest …` for a
  targeted path (tests and this skill use a disposable path).

## Driving it with control-summonaikit

Preconditions:

- `control-summonaikit doctor` reports `doctor: PASS`.
- No second instance is active (`.run/env` already consumed by launch).

- Case `install-ownership`: action Confirm ownership after launch; command `control-summonaikit doctor`; observable `ownership marker present` and `DEST matches repo source`.
- Case `install-dry-run`: action Drive dry-run classification; command `control-summonaikit drive-install-dry-run`; observable exit `0` with dry-run / `YA AL DIA` line and `HOME=` equal to `VERIFY_HOME`.

- **Isolated install (already done by launch).** Confirm the launch log.
  Inspect `.cursor/skills/verify-summonaikit/artifacts/launch-*.txt`. It must
  show `INSTALADO` (or equivalent success) and `DEST` under the disposable HOME.
- **Proof.** Keep both `launch-*.txt` and `install-dry-run-*.txt`. Confirm
  `VERIFY_DEST` still exists and matches the source sha (doctor).

## Gotchas

- Running the installer without an isolated `HOME` can publish skills/recipes
  into the live `~/.claude`. Always go through `control-summonaikit`.
- `--check` without isolation reads live host copies; it is not a verification
  drive for this skill.
- `--dry-run` success alone is not proof of install. Launch (or an explicit
  isolated `--dest` install) is the write path.
- A destination classified `DESCONOCIDO` must remain untouched; do not force
  overwrite to "make the drive green".
