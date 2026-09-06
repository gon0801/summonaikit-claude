# Record a decision and a blast

Record a decision and a blast writes a decision-trail row and a blast-radius
JSON on a private fixture by invoking the real tools. A bad row or an invalid
level/command is rejected and left untouched. A pasted token is redacted.
Agents do not write these artifacts automatically.

## Sub-features

- `decision-valid` appends a complete row and `--check` exits 0.
- `decision-reject` reports a malformed row (exit 2) and does not repair the file.
- `blast-valid` writes `blast-<task>.json` with hecho/comando/salida/nivel.
- `blast-reject` rejects a level outside 1-5 and a level ≥ 4 without a command.
- `redact` replaces a synthetic token with `[REDACTED]` in both artifacts.
- `output-location` leaves both files under the fixture, never the checkout.

## How to get to it (user POV)

- From a git repo, run `bash tools/saikit-decision.sh --append --task <id> …` to add one trail row.
- Run `bash tools/saikit-blast.sh --write --task <id> --hecho … --nivel <1-5>` to write the blast JSON.
- Default paths are `.saikit/decisiones/<task>.tsv` and `.saikit/findings/blast-<task>.json`.

## Driving it with control-summonaikit

Preconditions:

- `control-summonaikit doctor` reports `doctor: PASS`.
- The driver builds a disposable git repo; it does not write the operator checkout.

- Case `decision-valid`: action Append a complete trail row on the fixture; command `control-summonaikit drive decision-blast`; observable the tsv under `.saikit/decisiones/` with the contract header and `--check` exit 0.
- Case `decision-reject`: action Append onto a three-field row; command `control-summonaikit drive decision-blast`; observable exit 2 naming `TSV malformado` / `linea 2` and a byte-identical file.
- Case `blast-valid`: action Write a level-4 blast with a command; command `control-summonaikit drive decision-blast`; observable `blast-fm1913b.json` with `"hecho"`, `"comando"`, `"salida"`, and `"nivel":4`.
- Case `blast-reject`: action Write nivel 6, then nivel 4 without a command; command `control-summonaikit drive decision-blast`; observable exit 2, no new file for the bad level, and the prior blast left intact.
- Case `redact`: action Paste a synthetic token into trail fields and blast salida; command `control-summonaikit drive decision-blast`; observable `[REDACTED]` and no leftover token in either artifact.
- Case `output-location`: action Invoke both tools from the fixture cwd without `--dir`; command `control-summonaikit drive decision-blast`; observable files under the fixture `.saikit/` paths and absent from the checkout.

- **Proof.** Keep the attempt. A tool exit 0 alone is not enough: the file
  path, the rejection reason, and the redaction marker must appear in
  `observed`.

## Gotchas

- Agents do not write these artifacts automatically. This drive invokes the
  tools; a green card does not mean a later agent run will append a trail or
  blast on its own.
- This drive does not replay the race or lock battery of the unit tests.
- Default output follows `git rev-parse --show-toplevel` of the fixture, not
  the working checkout. Never point `--dir` at a live profile.
