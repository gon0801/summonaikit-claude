# Post-merge health warning

Post-merge health warning looks at the merge commit's CI run and optional
health URL, then tells the operator if something broke. On red it prints a
ready-to-copy revert command. It never runs that revert.

## Sub-features

- `postmerge-green` exits 0 with `VERDE` when CI succeeded and no revert is offered.
- `postmerge-red` exits 1 with `ROJO` and `PARA REVERTIR`, leaving HEAD and the worktree unchanged.
- `postmerge-pending` and `postmerge-no-run` exit 3 with `UNKNOWN` and name the gap.
- `postmerge-redacted` keeps synthetic secrets out of the warning and telegram text.
- `postmerge-transport` rejects unexpected gh, curl, and telegram calls.

## How to get to it (user POV)

- After a confirmed merge, run `bash tools/saikit-postmerge.sh --merge-commit <sha>`.
- Read the `VERDE` / `ROJO` / `UNKNOWN` line. Copy the revert block only if you decide to undo.

## Driving it with control-summonaikit

Preconditions:

- `control-summonaikit doctor` reports `doctor: PASS`.
- The driver builds a disposable Git repo with a local bare origin. gh, curl,
  and telegram-send are strict doubles; unexpected forms fail.
- Mode is `simulated`. Live GitHub, curl, and telegram are never used.

- Case `postmerge-green`: action Observe native green; command `control-summonaikit drive saikit-postmerge`; observable exit `0`, `VERDE`, and no `PARA REVERTIR`.
- Case `postmerge-red`: action Observe native red without revert; command `control-summonaikit drive saikit-postmerge`; observable exit `1`, `ROJO`, `--revert-de <sha>`, and intact HEAD/worktree.
- Case `postmerge-pending`: action Observe native unknown for in-progress CI; command `control-summonaikit drive saikit-postmerge`; observable exit `3`, `UNKNOWN`, and `pendiente`.
- Case `postmerge-no-run`: action Observe native unknown when CI has no run; command `control-summonaikit drive saikit-postmerge`; observable exit `3`, `UNKNOWN`, and `sin run`.
- Case `postmerge-redacted`: action Observe a redacted warning; command `control-summonaikit drive saikit-postmerge`; observable `[REDACTED]` and no raw synthetic secret.
- Case `postmerge-transport`: action Probe unexpected transports; command `control-summonaikit drive saikit-postmerge`; observable unexpected gh/curl/telegram fail and only expected calls are logged.

- **Proof.** Keep the attempt. Native tool_exit 0/1/3 is the contract of the
  tool, not the drive result. A printed revert command is not execution: HEAD
  and the worktree must stay identical.

## Gotchas

- This drive never runs `git revert`, `gh pr merge`, or a live telegram send.
- `UNKNOWN` (exit 3) is a successful observation of native pending/no-run, not
  a missing drive.
- A real `gh` or `curl` on PATH is not used; inherited transports fail closed.
- Redaction is judged on the tool output before evidence is stored.
