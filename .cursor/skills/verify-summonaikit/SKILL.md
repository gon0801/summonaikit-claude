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

Secondary surfaces now driven in isolation: host install/registration
(`install-hosts`) and model routing / recipe manifest (`routing-recipes`).
Still out of scope for default drives: the Spanish `verify/` map from
`saikit-verificar-app`, and any live model turn.

## Launch

No long-lived server. Launch means: create a disposable `HOME`, install the
repo hook into it, and record validated state in
`.cursor/skills/verify-summonaikit/.run/state.json` (never a sourced env file).

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
"$CTRL" list-features
"$CTRL" doctor
"$CTRL" drive install-guardian
"$CTRL" drive install-hosts
"$CTRL" drive routing-recipes
"$CTRL" drive-install-dry-run
"$CTRL" drive-gate-scenario 01-sin-armar
"$CTRL" drive-gate-scenario 02-armado-contrato
"$CTRL" drive-audit-ledger
"$CTRL" drive-deploy-log
```

`list-features` prints `id`, `card`, `mode` and declared `scope` for every catalog
entry (including pending) and does **not** launch. `drive <id>` runs every
required case of that feature and writes evidence v1 under
`artifacts/<run_id>/<feature_id>/<attempt_id>/`. The four `drive-*` aliases
do the same wrap; `drive-gate-scenario` declares **partial** scope (one
scenario, not all of `gate-turn`).

Ad-hoc under the isolated home, **only catalog public entries** (not an
arbitrary shell or command — a deliberate restriction vs the old CLI):

```bash
"$CTRL" cli -- tools/install-hook.sh --dry-run
```

`cli --` rejects `bash`, `/bin/sh`, and any path that is not a catalog
surface. Setup/merge/postmerge are refused on the working checkout; they
need a disposable repo owned by the run.

**Hard rule:** never run `tools/install-hook.sh` (without `--dry-run`) or
`--check` against the operator profile from this skill. Writes go only through
`launch` / isolated `HOME`. `--check` without isolation reads live hosts; leave
that to the operator.

**Legacy `.run/env`:** if that file exists, do not source it and do not
`rm -rf` its purported `VERIFY_HOME`. Delete only the `env` file and
**re-lanzar** (`"$CTRL" launch`). New runs use `state.json` only.

## Evidence

Proof artifacts live in `.cursor/skills/verify-summonaikit/artifacts/` and
**survive** cleanup. Each drive attempt uses an exclusive directory
`artifacts/<run_id>/<feature_id>/<attempt_id>/` with `steps.jsonl`,
`summary.json` and redacted logs. Retry and cleanup keep prior attempt
dirs. `PASS` exits 0, `FAIL` exits 1, `unknown` exits 3.

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

Removes only temps **owned by this run** (marker + token in `state.json`).
A textual `/tmp` prefix is not enough. Does **not** kill processes by name,
does **not** touch live profiles, and does **not** delete `artifacts/`.
Repeating cleanup is a no-op.

If `state.json` is truncated/invalid, `VERIFY_HOME` is already gone, or ownership
cannot be proven, cleanup **soft-clears** only `state.json` / `.active` (HOME
untouched) and prints a re-lanzar instruction — so launch is never deadlocked
behind an impossible cleanup.

If a drive fails mid-run, still run cleanup so the next launch is not blocked.
A leftover `.run/env` is rejected (re-lanzar); cleanup will not delete its
purported HOME.

## Helpers

Executable helper (invocation above):

`.cursor/skills/verify-summonaikit/scripts/control-summonaikit`

| Command | Purpose |
|---|---|
| `launch` | Isolated HOME + install hook |
| `doctor` | Read-only instance health |
| `cleanup` | Tear down instance; keep evidence |
| `cli -- …` | Run a **catalog public** entry with isolated env (not an arbitrary shell) |
| `list-features` | Enumerate id/card/mode/scope without launch |
| `drive <id>` | Run all required cases for that feature (evidence v1) |
| `drive-install-dry-run` | Installer dry-run proof |
| `drive-gate-scenario [name]` | One golden-harness scenario (partial scope) |
| `drive-audit-ledger` | Ledger audit proof |
| `drive-deploy-log` | Deploy-log check proof |

## Feature map

Read `features/README.md` before driving. Cover every entry point listed for
the feature under test; one convenient path is incomplete when the map lists
others.
