# Capture synthetic payloads

Capture synthetic payloads registers a fictional host config, feeds a
synthetic hook payload, checks cwd and private permissions, then removes the
registration while leaving foreign config intact. Raw captures stay in the
case temp. Retained evidence must not contain the synthetic secret.

## Sub-features

- `capture-lifecycle` installs on a disposable repo, saves a synthetic payload, asserts private perms and cwd filter, then removes the owned registration without touching foreign settings.
- `capture-redaction` scans retained evidence for the synthetic secret and requires zero matches.

## How to get to it (user POV)

- Run `bash tools/capture-payloads.sh --instalar <disposable-repo>` on a throwaway project, never on a live profile.
- Feed stdin to the same script (hook mode) to store a payload under `capturas/` or `$SAIKIT_CAPTURE_DIR`.
- Run `--quitar <repo>` to remove only what this tool created.

## Driving it with control-summonaikit

Preconditions:

- `control-summonaikit launch` created an isolated HOME. Destinations are under the run temp, never `~/.claude`, `~/.grok`, `~/.dsh`, or `~/.codex`.
- Only synthetic payloads are fed. Real captures are not loaded to test redaction.

- Case `capture-lifecycle`: action Install, feed a synthetic payload, check cwd/permissions, then remove; command `control-summonaikit drive capture-payloads`; observable owned settings/marker, payload saved privately, other-cwd writes nothing, owned files removed, foreign settings checksum unchanged.
- Case `capture-redaction`: action Scan the attempt artifacts after the synthetic feed; command `control-summonaikit drive capture-payloads`; observable zero matches of the synthetic secret in retained evidence.

## Gotchas

- `--quitar` without the ownership marker refuses to delete a user settings file even if it mentions the capturer.
- `--only-cwd` compares physical paths (`pwd -P`). A different working directory must not write.
- Raw payload content stays in the private temp. Do not copy it into published artifacts.
