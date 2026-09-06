# Check committed secrets

Check committed secrets scans staged or named files for leaked credentials.
The strong detector (pinned gitleaks) is the verdict when present. Without it
the grep fallback still catches obvious traps, warns that it is not the
verdict, and never prints the secret value.

## Sub-features

- `secrets-strong` runs a clean file and a synthetic trap through the strong detector, or records `unknown` when that detector is missing.
- `secrets-fallback` forces the grep engine, asserts its warning and declared limit, and does not credit a strong-detector PASS.
- `secrets-redaction` proves the synthetic secret is absent from the tool report and from retained evidence.

## How to get to it (user POV)

- Run `bash tools/check-secrets.sh <file>...` (pre-commit does this on staged text).
- Install gitleaks 8.30.1 (or set `SAIKIT_GITLEAKS`) for the same verdict as the CI `secrets` job.
- Without gitleaks, read the warning: a local PASS is not the CI verdict.

## Driving it with control-summonaikit

Preconditions:

- `control-summonaikit launch` created an isolated HOME.
- Traps live in the run temp, never in the checkout. Real GitHub/Telegram tokens stay out of the environment.
- Missing gitleaks makes strong-detector assertions `unknown`; the fallback warning is still required when that engine can be forced.

- Case `secrets-strong`: action Scan a clean fixture and a synthetic trap; command `control-summonaikit drive check-secrets`; observable clean exit 0 and trap exit 1 with the strong detector, or `unknown` naming the missing detector.
- Case `secrets-fallback`: action Hide gitleaks and scan the comment-keyword fixture; command `control-summonaikit drive check-secrets`; observable the `AVISO — sin gitleaks` warning and the declared limit that this PASS is not the verdict.
- Case `secrets-redaction`: action Inspect the trap report and the attempt artifacts; command `control-summonaikit drive check-secrets`; observable no synthetic secret value in stdout/URL/fields and zero matches in retained evidence.

## Gotchas

- A fallback PASS is not the CI `secrets` job. Do not treat it as a strong-detector result.
- The report prints `file:line` only. Seeing the trap value in output is a FAIL.
- Do not load real captures or live tokens to exercise redaction.
