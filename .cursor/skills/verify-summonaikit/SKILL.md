---
name: verify-summonaikit
description: >-
  Drive summonaikit-claude (the Claude Code turn-gate hook and its operator
  CLI tools) in an isolated HOME: launch, doctor, exercise install/gate/ledger/
  deploy-log features, capture evidence, and clean up. Use when verifying
  user-facing behavior of this repo without touching live ~/.claude profiles.
---

# verify-summonaikit

Primary surface: **CLI** (bash tools under `tools/` plus the gate hook
`hooks/summonaikit-harness.sh`). There is no web UI. Claude Code hosts the
hook in production; this skill never drives the operator's live profile.

Secondary surfaces (out of scope for default drives): dsh/cordis plugin,
zcode/codex/grok host installers, the Spanish `verify/` map from
`saikit-verificar-app`.

## Launch

No long-lived server. Launch means: create a disposable `HOME`, install the
repo hook into it, and record the instance under `.cursor/skills/verify-summonaikit/.run/`.

```bash
CTRL=.cursor/skills/verify-summonaikit/scripts/control-summonaikit
chmod +x "$CTRL"   # once
"$CTRL" launch
```

Ready when stdout shows `launched run_id=...` and `DEST=.../summonaikit-harness.sh`,
and the launch log under `artifacts/launch-*.txt` contains `INSTALADO` (or an
equivalent success line). The helper sets `HOME`/`USERPROFILE` to the disposable
dir for every later command.

Teardown:

```bash
"$CTRL" cleanup
```

## Doctor

Run first whenever anything looks off:

```bash
"$CTRL" doctor
```

Require `doctor: PASS`. That means: an active instance exists, `DEST` carries
`# SAIKIT-CLAUDE-OWNED`, `bash -n` is clean, `DEST` matches the repo source
byte-for-byte, and `DEST` is **not** the live `~/.claude/hooks/` copy.

Refuse to drive if doctor fails. Never "fix" by installing into the real home.

## Drive

Harness: `control-summonaikit` (bash). Prefer its `drive-*` commands and the
feature map under `features/`. Stable handles are CLI flags, stdout markers
(`AUDITORIA DEL LEDGER`, `[deploy-log] OK`, `=== escenario …`, ownership
marker), and fixture scenario directory names — not coordinates.

```bash
"$CTRL" doctor
"$CTRL" drive-install-dry-run
"$CTRL" drive-gate-scenario 01-sin-armar
"$CTRL" drive-gate-scenario 02-armado-contrato
"$CTRL" drive-audit-ledger
"$CTRL" drive-deploy-log
```

Ad-hoc under the isolated home:

```bash
"$CTRL" cli -- tools/install-hook.sh --dry-run
```

**Hard rule:** never run `tools/install-hook.sh` (without `--dry-run`) or
`--check` against the operator profile from this skill. Writes go only through
`launch` / isolated `HOME`. `--check` without isolation reads live hosts; leave
that to the operator.

## Evidence

Proof artifacts live in `.cursor/skills/verify-summonaikit/artifacts/` and
**survive** cleanup.

Proof standards:

- Exercise the real operator path (installer, golden-harness scenarios, ledger
  and deploy-log tools) — not internal unit helpers or mutated hooks.
- Capture the command outcome (exit code + stdout/stderr log), not only a
  summary claim.
- For the gate: prove both an unarmed prompt (`01-sin-armar` → no state) and an
  armed prompt (`02-armado-contrato` → contract injected + state files).
- For dry-run install: confirm exit 0 and a recognizable status line; do not
  treat the name "dry-run" as proof that nothing else ran — the log is the proof.
- Mocks are not used; fixtures under `tests/fixtures/escenarios/` are real
  captured payloads.

Name artifacts with the run id from launch (`*-${VERIFY_RUN_ID}.txt`).

## Cleanup

```bash
"$CTRL" cleanup
```

Removes only the disposable `VERIFY_HOME` recorded in `.run/env` (must be under
`/tmp` or `$TMPDIR`). Does **not** kill processes by name, does **not** touch
live profiles, and does **not** delete `artifacts/`.

If a drive fails mid-run, still run cleanup so the next launch is not blocked.

## Helpers

Executable helper (invocation above):

`.cursor/skills/verify-summonaikit/scripts/control-summonaikit`

| Command | Purpose |
|---|---|
| `launch` | Isolated HOME + install hook |
| `doctor` | Read-only instance health |
| `cleanup` | Tear down instance; keep evidence |
| `cli -- …` | Run a command with `HOME=VERIFY_HOME` |
| `drive-install-dry-run` | Installer dry-run proof |
| `drive-gate-scenario [name]` | One golden-harness scenario |
| `drive-audit-ledger` | Ledger audit proof |
| `drive-deploy-log` | Deploy-log check proof |

## Feature map

Read `features/README.md` before driving. Cover every entry point listed for
the feature under test; one convenient path is incomplete when the map lists
others.
