# Audit the task ledger

Audit the task ledger tells the operator whether any `Plans.md` rows still
marked `cc:TODO` already have their work merged on `origin/master`.

## Sub-features

- `ledger-run` executes `tools/audita-ledger.sh` and prints a header.
- `ledger-ok` exits 0 when no stale TODO rows are found.
- `ledger-report` surfaces stale rows when present (exit non-zero).

## How to get to it (user POV)

- From the repo root, run `bash tools/audita-ledger.sh`.
- Read the stdout block starting with `AUDITORIA DEL LEDGER`.

## Driving it with control-summonaikit

Preconditions:

- `control-summonaikit doctor` reports `doctor: PASS`.
- Network/git refs: the tool judges against local `origin/master` (no fetch
  required for a read; stale remotes are an operator concern).

- Case `ledger-run`: action Run ledger audit; command `control-summonaikit drive-audit-ledger`; observable `AUDITORIA DEL LEDGER` header and recorded exit (0 when clean).

- **Proof.** Keep the artifact. If exit is non-zero, paste the listed stale
  rows into the verification report rather than forcing a green drive.

## Gotchas

- This tool is intentionally **not** a CI job: during a PR the new commits are
  already on the branch while the row may still say `cc:TODO`.
- Do not edit `Plans.md` from a verification run; closing rows is the lead's job.
- A green audit does not prove the hook works — only that the ledger is consistent.
