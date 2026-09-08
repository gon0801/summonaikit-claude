# Prepare the autopilot of a repo

Prepare the autopilot of a repo asks five Spanish questions (or accepts the
same answers as flags) and writes `.saikit/autopilot.json` under a per-repo
lock. A missing CI offer is a separate prompt, never question 6/5.

## Sub-features

- `setup-interactive` asks the five questions on a real PTY, in order, and maps each answer into JSON.
- `setup-invalid` rejects a bad answer without a partial config or leftover lock.
- `setup-timeout` kills its own process group and leaves no write and no orphan lock.
- `setup-flags` applies distinctive flag values without a TTY.
- `setup-defaults` writes the safe defaults when stdin is not a terminal.
- `setup-pipe-not-pty` treats a pipe as non-interactive (piped text is not a PTY).
- `setup-lock` reports a stale lock and refuses to write.
- `setup-lock-held` reports a LIVE held lock (exit 3), prints the recovery hint in executable form `bash tools/saikit-setup-autopilot.sh --liberar-lock`, and executes the EXTRACTED hint command against a COPY of the fixture: the command is pulled from the observed hint line, must match the full-line form exactly (a hint carrying an unknown extra flag fails the assertion — it is a substring, not the command), and the copy run resolves the hint's relative tool path to the real tool (exit 0, the copy's lock is released, the original stays held).
- `setup-with-ci` skips the CI offer when workflows already exist.
- `setup-without-ci` warns that the autopilot will not merge, without calling that warning 6/5.

## How to get to it (user POV)

- From a git repo, run `bash tools/saikit-setup-autopilot.sh` and answer the five prompts.
- Pass `--merge`, `--despliega`, `--salud-url`, `--sin-verify-app`, and `--telegram` to skip the prompts.
- If another setup still holds the lock, run `--liberar-lock` only when you mean to release it.

## Driving it with control-summonaikit

Preconditions:

- `control-summonaikit doctor` reports isolation ready.
- Interactive cases need a real PTY; if none is available they stay `unknown` (never a fake PTY).
- Lock and config live in a disposable repo, never in a live profile.

- Case `setup-interactive`: action Drive five setup questions over a real PTY; command `control-summonaikit drive setup-autopilot`; observable five prompts 1/5–5/5 in order and answers mapped into `.saikit/autopilot.json`.
- Case `setup-invalid`: action Send an invalid first answer on a PTY; command `control-summonaikit drive setup-autopilot`; observable no config file and no leftover lock.
- Case `setup-timeout`: action Start the assistant and let the PTY helper time out; command `control-summonaikit drive setup-autopilot`; observable timeout kill/reap, no write, no orphan lock.
- Case `setup-flags`: action Pass distinctive flags with stdin not a TTY; command `control-summonaikit drive setup-autopilot`; observable JSON fields match the flags, not the defaults.
- Case `setup-defaults`: action Run with no answers and no TTY; command `control-summonaikit drive setup-autopilot`; observable `merge=false` and `merge_despliega=unknown`.
- Case `setup-pipe-not-pty`: action Pipe answers into the assistant; command `control-summonaikit drive setup-autopilot`; observable defaults (pipe is not a PTY).
- Case `setup-lock`: action Run against a stale lock; command `control-summonaikit drive setup-autopilot`; observable exit 3 and no config write.
- Case `setup-lock-held`: action Hold the lock with the tool's own SOSTENER test hook, run a second setup, then execute the hint from a COPY of the fixture repo; command `control-summonaikit drive setup-autopilot`; observable exit `3`, stderr carries the exact hint line `bash tools/saikit-setup-autopilot.sh --liberar-lock`, and the copy's lock is released while the original stays held (the run uses the extracted argv, never a handwritten one).
- Case `setup-with-ci`: action Run flags on a repo that already has workflows; command `control-summonaikit drive setup-autopilot`; observable `ya hay workflows` / no offer.
- Case `setup-without-ci`: action Run flags on a repo with no workflows; command `control-summonaikit drive setup-autopilot`; observable the no-CI warning is not labeled 6/5.

## Gotchas

- A pipe or redirected stdin is not a PTY. The assistant then takes defaults and ignores the piped lines.
- Missing PTY is `unknown` for interactive cases only; flags and defaults stay observable.
- The CI offer is not a sixth setup question and does not enter the JSON.
- The lock lives in `git-common-dir`; do not point this drive at a live profile.
- Recorded actions must carry the REAL argv (20fix H3): the tool has no
  `--lock-held` flag, and the holder prep and the second run are registered
  separately (`--pr 11` with `SAIKIT_SETUP_SOSTENER_SEG=8`, then the real
  `--pr 12` invocation). If the holder never takes the lock, the second run
  DID NOT happen: it is reported as absent with the true reason, never as an
  action with an invented argv or empty output.
