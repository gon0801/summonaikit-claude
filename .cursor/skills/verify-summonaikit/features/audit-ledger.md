# Audit the task ledger

Audit the task ledger tells the operator whether any `Plans.md` rows still
marked `cc:TODO` already have their work merged on `origin/master`.

## Sub-features

- `ledger-ok` exits 0 with `AUDITORIA DEL LEDGER: OK` on a consistent fixture.
- `ledger-stale` names the open row when merged work is still `cc:TODO`.

## How to get to it (user POV)

- From the repo root, run `bash tools/audita-ledger.sh`.
- Read the stdout block starting with `AUDITORIA DEL LEDGER`.

## Driving it with control-summonaikit

Preconditions:

- `control-summonaikit doctor audit-ledger` reports `doctor: PASS`; this
  fixture audit does not require hook preparation.
- The driver builds a disposable git repo; it does not judge the operator
  checkout's live `Plans.md`.

- Case `ledger-ok`: action Audit a consistent fixture; command `control-summonaikit drive-audit-ledger`; observable `AUDITORIA DEL LEDGER: OK` and exit 0.
- Case `ledger-stale`: action Audit a stale TODO row; command `control-summonaikit drive audit-ledger`; observable `LEDGER DESACTUALIZADO` naming `fila 16.3`.

- **Proof.** Keep the attempt. A header alone is not enough: the OK line or
  the stale reason (row id) must appear in the assertion `observed` field.

## Gotchas

- This tool is intentionally **not** a CI job: during a PR the new commits are
  already on the branch while the row may still say `cc:TODO`.
- Do not edit `Plans.md` from a verification run; closing rows is the lead's job.
- A green audit does not prove the hook works — only that the ledger is consistent.
- The auditor exits 0 even when it reports stale rows; the verdict is the text.
