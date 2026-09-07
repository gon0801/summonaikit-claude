# Install the guardian

Install the guardian lets an operator publish or refresh the turn-gate hook into
an agent profile safely: classify the destination, refuse unknowns, and either
install or report without writing.

## Sub-features

- `install-dry-run` reports what would happen without writing.
- `install-ownership` leaves the `# SAIKIT-CLAUDE-OWNED` marker on a successful install.
- `install-noop` reprints `YA AL DIA` when the destination already matches the source.
- `install-foreign` leaves a neighbor file that is not the destination untouched.
- `install-restore` restores a known vendor fixture over the destination.

## How to get to it (user POV)

- Run `bash tools/install-hook.sh --dry-run` to see the classification.
- Run `bash tools/install-hook.sh` (or `--host claude`) after a merge to deploy
  (operator-only; not part of automated verification).
- Run `bash tools/install-hook.sh --dest <path> --source … --manifest …` for a
  targeted path (tests and this skill use a disposable path).

## Driving it with control-summonaikit

Preconditions:

- `control-summonaikit launch` created the isolated run. Hook preparation is
  part of this drive and its result is recorded in the attempt.
- No second instance is active (`.run/env` already consumed by launch).

- Case `install-dry-run`: action Drive dry-run without writes; command `control-summonaikit drive-install-dry-run`; observable exit `0`, `procedencia: rama=`, and dest absent or unchanged.
- Case `install-ownership`: action Confirm ownership after launch; command `control-summonaikit drive install-guardian`; observable `SAIKIT-CLAUDE-OWNED` and DEST sha matches source.
- Case `install-noop`: action Reinstall over matching dest; command `control-summonaikit drive install-guardian`; observable `YA AL DIA` and dest bytes unchanged.
- Case `install-foreign`: action Install beside a neighbor file; command `control-summonaikit drive install-guardian`; observable neighbor checksum intact.
- Case `install-restore`: action Restore known vendor fixture; command `control-summonaikit drive install-guardian`; observable dest bytes match the vendor backup.

- **Isolated install.** Inspect `hook-prepare.log` inside the attempt. It must
  be redacted, show a successful installer execution, and correspond to `DEST`
  under the disposable HOME.
- **Proof.** Keep both `launch-*.txt` and the drive attempt under
  `artifacts/<run>/install-guardian/<attempt>/`. Confirm `VERIFY_DEST` still
  exists and matches the source sha (doctor).

## Gotchas

- Running the installer without an isolated `HOME` can publish skills/recipes
  into the live `~/.claude`. Always go through `control-summonaikit`.
- `--check` without isolation reads live host copies; it is not a verification
  drive for this skill.
- `--dry-run` success alone is not proof of install. Launch (or an explicit
  isolated `--dest` install) is the write path.
- A destination classified `DESCONOCIDO` must remain untouched; do not force
  overwrite to "make the drive green".
