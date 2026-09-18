---
name: verify
description: >-
  Drive summonaikit-claude, the Claude Code turn-gate hook plus its operator
  CLI tools under tools/, in a disposable HOME and capture evidence: install
  and host registration, armed and unarmed gate turns, ledger and deploy-log
  audits, merge tooling, recipes and routing. Use before claiming a change to
  hooks/, tools/, agents/, recetas/, skills/ or hosts/ works, or whenever a
  playbook asks for the driver skill. Never touches the live ~/.claude,
  ~/.grok, ~/.dsh or ~/.codex profiles.
---

# verify

This repo has no server and no UI. The user surface is the gate hook
`hooks/summonaikit-harness.sh` as a host runs it, plus the bash tools in
`tools/`. Everything is driven through one controller that isolates `HOME`.

The controller and the feature map already exist and are the maintained
source: `.cursor/skills/verify-summonaikit/`. The pre-commit candado
`feature-map catalog/descriptors/cards` keeps that map in sync with the
code. This skill routes to it and does not keep a second map. For per-feature
limits and the maintenance runbook, read
`.cursor/skills/verify-summonaikit/SKILL.md`.

Set the controller path once per shell:

```bash
CTRL=.cursor/skills/verify-summonaikit/scripts/control-summonaikit
```

## Launch

```bash
"$CTRL" launch
```

Ready when stdout prints `launched run_id=<id>` and `DEST=<tmp>/summonaikit-harness.sh`.
Launch creates a disposable `HOME` and git area and records them in
`.cursor/skills/verify-summonaikit/.run/state.json`. It installs nothing yet.
A drive that needs the hook installs it into the disposable `HOME` first.

One active run per checkout. A second `launch` fails with
`run activo — run cleanup first`. Parallel lanes each need their own worktree,
which carries its own `.run/`.

## Doctor

```bash
"$CTRL" doctor              # every feature
"$CTRL" doctor <feature-id> # one feature
```

Read-only. Run it first whenever something looks off. For a hook feature,
`PASS` means the disposable `DEST` carries `# SAIKIT-CLAUDE-OWNED`, passes
`bash -n`, matches repo source byte for byte and is not the live
`~/.claude/hooks/` copy. `MISSING` before the first hook drive is expected.
Resolve any `FAIL` before driving. Never repair it by installing into the real
home.

## Drive

```bash
"$CTRL" list-features       # id, card, mode, scope; no launch needed
"$CTRL" drive <feature-id>  # every required case of that feature
```

Pick the feature from `list-features`, then read its card in
`.cursor/skills/verify-summonaikit/features/<id>.md` before driving. A card
that lists several entry points needs all of them. One convenient path is not
proof of the feature.

Common picks for a change under review:

| You changed | Drive |
|---|---|
| `hooks/summonaikit-harness.sh` | `gate-turn`, then `install-guardian` |
| `tools/install-hook.sh` or a host adapter | `install-guardian`, `install-hosts` |
| `tools/model-routing.sh` or `recetas/` | `routing-recipes` |
| Ledger tooling for `Plans.md` | `audit-ledger` |
| Deploy-log tooling | `check-deploy-log` |
| The merge or postmerge tools | `saikit-merge`, `saikit-postmerge` |

Ad-hoc runs go through `"$CTRL" cli -- <catalog entry> <args>`, for example
`"$CTRL" cli -- tools/install-hook.sh --dry-run`. It rejects `bash`, `/bin/sh`
and any path outside the catalog.

Hard rule. Never run `tools/install-hook.sh` without `--dry-run`, or
`--check`, against the operator profile from this skill. Live hosts are the
operator's call.

The Spanish product Drive in `verify/` is a separate seal. Run `pytest verify/`
and paste its output into `verify/Evidence.txt` when the change touches what
`verify/LEEME.md` maps. A controller `PASS` does not renew that seal.

## Evidence

Each drive attempt writes to
`.cursor/skills/verify-summonaikit/artifacts/<run_id>/<feature_id>/<attempt_id>/`:
`steps.jsonl`, `summary.json` and redacted logs. Exit code is the verdict.
`PASS` exits 0, `FAIL` exits 1 and `unknown` exits 3. Report `unknown` as
`unknown`, never as a pass.

Proof standards:

- Drive the real operator path: the installer, the hook through
  `tools/golden-harness.sh` scenarios, the ledger and deploy-log tools. Unit
  helpers and mutated hooks are not proof.
- Quote the exit code and the log, not a summary claim.
- For the gate, prove both the unarmed turn (no state written) and the armed
  turn (contract injected and state written).
- A dry-run is proven by its log. Its name is not evidence that nothing else ran.

## Cleanup

```bash
"$CTRL" cleanup
```

Removes only the temps this run owns, proven by the marker and token in
`state.json`. It never kills processes by name, never touches live profiles
and never deletes `artifacts/`. Run it after every failed attempt too, or the
next `launch` refuses. A second cleanup with no active run is a no-op.

If `.cursor/skills/verify-summonaikit/.run/env` exists, it is a legacy file.
Do not source it and do not delete the `HOME` it names. Delete only the `env`
file and launch again.

## Helpers

`control-summonaikit` is the only helper. It is executable and every
invocation is shown above. Subcommands: `launch`, `doctor [id]`,
`list-features`, `drive <id>`, `cli -- <entry> <args>`, `cleanup`.

## Known limits

- `merge-happy-path` stays `blocked`. It needs a live remote per attempt and
  is never credited by simulation.
- Muse Code is not a host yet. Phase 23 in `Plans.md` tracks it, and
  `docs/task-23.1-captura-muse.md` holds the measured contract. Do not drive
  Muse from this skill until `--host muse` exists.
