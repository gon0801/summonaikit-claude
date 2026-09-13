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
The Spanish `verify/` map is a complementary Drive: run `pytest verify/`
isolated and record that result. A skill PASS is not the product `verify/`
seal. Live merge (`merge-happy-path`) stays inventariado; no observado.

## Launch

No long-lived server. Launch means: create a disposable `HOME` and Git area,
then record validated state in
`.cursor/skills/verify-summonaikit/.run/state.json` (never a sourced env file).
Hook installation is deferred until a drive that needs it; fixture-only ledger
and deploy-log audits do not depend on the hook or installer.

```bash
CTRL=.cursor/skills/verify-summonaikit/scripts/control-summonaikit
chmod +x "$CTRL"   # once
"$CTRL" launch
```

Ready when stdout shows `launched run_id=...` and
`DEST=.../summonaikit-harness.sh`. The launch log records that hook preparation
is deferred. A hook-dependent drive writes a redacted `hook-prepare.log` inside
its attempt and must install successfully before it runs. The helper sets
`HOME`/`USERPROFILE` to the disposable dir for every later command. `launch`
also binds STATE and ARTIFACTS to that run; changing either path or the recorded
repo makes later commands fail.

Teardown:

```bash
"$CTRL" cleanup
```

## Doctor

After launch, inspect all requirements or one feature:

```bash
"$CTRL" doctor
"$CTRL" doctor audit-ledger
```

The all-feature report can be `unknown/MISSING` before the first hook-dependent
drive. Fixture-only features remain ready without preparing the hook.

For a feature with an instance requirement, `doctor: PASS` means `DEST` carries
`# SAIKIT-CLAUDE-OWNED`, `bash -n` is clean, `DEST` matches repo source
byte-for-byte, and `DEST` is **not** the live `~/.claude/hooks/` copy. For a
fixture-only feature, PASS covers only that feature's declared requirements.

Resolve `doctor: FAIL` before driving. `MISSING` for the deferred isolated hook
is prepared by a dependent drive. Never "fix" by installing into the real
home. Doctor does not scan the operator profile.

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
entry (active or blocked; leftover pending is a lint FAIL) and does **not**
launch. `drive <id>` runs every
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
need a disposable repo owned by the run. Output paths for installer, CI,
decision/blast, recipes, golden recording, capture and staging must also stay
under the assigned run; golden `--record` requires an explicit safe baseline.

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
- Gate fixtures under `tests/fixtures/escenarios/` are captured payloads.
- Simulated features (`saikit-merge`, `saikit-postmerge`) use in-driver
  doubles, not live remotes.

Name artifacts with the run id from launch (`*-${VERIFY_RUN_ID}.txt`).

## Cleanup

```bash
"$CTRL" cleanup
```

Removes only temps **owned by this run** (marker + token in `state.json`).
A textual `/tmp` prefix is not enough. Does **not** kill processes by name,
does **not** touch live profiles, and does **not** delete `artifacts/`.
Repeating cleanup is a no-op.

If an assigned `state.json` is truncated/invalid, `VERIFY_HOME` is already gone,
or ownership cannot be proven, cleanup **soft-clears** only its assigned state
metadata (HOME untouched), prints a re-lanzar instruction, and exits 1 because
the violation was observed. Unassigned STATE is rejected without deleting it.
A later cleanup with no active run is a no-op with exit 0.

If a drive fails mid-run, still run cleanup so the next launch is not blocked.
A leftover `.run/env` is rejected (re-lanzar); cleanup will not delete its
purported HOME.

## Helpers

Executable helper (invocation above):

`.cursor/skills/verify-summonaikit/scripts/control-summonaikit`

| Command | Purpose |
|---|---|
| `launch` | Isolated HOME/Git state; hook preparation deferred |
| `doctor` | Read-only per-feature requirement report |
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
others. Per-feature limits live on the cards. Reconciled 2026-09-13 (20.23):
the Phase 18 limits that Phase 20 measured are overcome — seal channel
(20.12), linked consume (20.13) and the full Grok flow (20.14); headless
design, surface and live measurement (20.15–20.17); the complete green path
in Claude (20.10); the `PreToolUse` deny (20.9); all three `cuidar-pr` modes
(20.11). What stays: `merge-happy-path` remains `blocked` (live scope per
attempt, never simulated credit); dsh scenario2 remains `unknown`
(20.18/20.19 open with a written decision, never PASS).

## Maintenance runbook (20.23): source → reconcile → drive → triage

One full pass per phase close, or when the catalog trigger fires. Vocabulary:
`PASS`/`FAIL`/`unknown` per feature and attempt; `clean`/`changed`/`blocked`
only for the whole pass verdict — never per feature.

1. **Source.** `Plans.md` statuses and `docs/evidence/phase-20/` are
   authoritative; `features/catalog.json` plus `list-features` and the lint
   define the full inventory. No promise without a measurement.
2. **Reconcile.** Every card maps to a source entry; every doc claim maps to
   a measured run. A deferred case stays named, never implicitly PASS.
3. **Drive.** Each feature once in its declared `execution_mode`, using the
   existing surfaces only (`list-features`, `launch`, `doctor`, `drive`,
   `cleanup`) — no parallel surface. Evidence v1 survives cleanup; the matrix
   (feature → source → mode → attempt/result → prerequisite) is tied to the
   checkout SHA and the hook SHA. Prior `20.x` evidence is reused only when
   checkout SHA, hook SHA and required cases all match.
4. **Triage.** Classify every deviation as doc drift, harness gap, or product
   regression. Doc drift is fixed in the pass. Harness gaps are fixed in the
   pass with regression plus discriminant mutant, then re-driven. Product
   regressions are reported apart, never silently fixed here.
5. **Edit scope of a pass.** Skill, map and harness only. A `changed` verdict
   ships as ONE pull request with regression, mutant and re-drive; a product
   gap ships as a separate report. Live driving requires the 20.8 scope alive;
   without it, live stays blocked, not passed.
