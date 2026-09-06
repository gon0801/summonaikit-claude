# summonaikit-claude verification map

This directory is the maintained source for verifying the operator-facing
behavior of summonaikit-claude. Read the index before driving, then use the
matching feature file as the recipe.

## Baseline preconditions

- Run every write through `control-summonaikit launch` so `HOME` is a disposable
  directory under `/tmp` (or `$TMPDIR`).
- Put `control-summonaikit` on your invocation path:
  `.cursor/skills/verify-summonaikit/scripts/control-summonaikit`.
- Run `control-summonaikit doctor` and require `doctor: PASS`.
- Never drive the live `~/.claude`, `~/.grok`, `~/.dsh`, or `~/.codex` profiles.
- Prefer repo source via the launched `VERIFY_DEST`; do not assume the live
  installed hook matches the checkout.

## Driving conventions

- Start every recipe from a freshly launched instance unless the feature says
  otherwise.
- Treat every command as literal. Keep flags and scenario names unchanged.
- Run tools through `control-summonaikit` so `HOME` stays isolated.
- Restore nothing in the live profile; cleanup only removes `VERIFY_HOME`.
- Keep proof artifacts under `.cursor/skills/verify-summonaikit/artifacts/`.

## Proof and skip reporting

- Capture exit code and the full command log, not only the final status line.
- Gate proof includes both unarmed (no state) and armed (contract + state) paths
  when the feature lists both.
- Record the feature ID and scenario/entry point with every artifact.
- Report an unreachable path with the attempted command and unmet precondition.
- Do not report a skipped entry point as verified through a different path.

## Feature entry contract

Each feature file starts with an H1 title and one paragraph describing the
user-visible behavior. It then uses exactly four H2 sections in this order:

1. `Sub-features`
2. `How to get to it (user POV)`
3. `Driving it with control-summonaikit`
4. `Gotchas`

## Features

- [Install the guardian](./install-guardian.md) covers dry-run classification and
  isolated install of the gate hook.
- [Gate an AI turn](./gate-turn.md) covers unarmed vs armed Claude prompt/stop
  scenarios via golden-harness.
- [Audit the task ledger](./audit-ledger.md) covers `tools/audita-ledger.sh`.
- [Check the deploy log](./check-deploy-log.md) covers `tools/check-deploy-log.sh`.
- [Merge a sealed PR (simulated)](./saikit-merge.md) covers `tools/saikit-merge.sh`
  with local Git/origin and a strict fake `gh`.
- [Post-merge health warning](./saikit-postmerge.md) covers `tools/saikit-postmerge.sh` in simulated mode.
- [Confirm before an autopilot merge](./autopilot-contract.md) covers the per-turn `-saikit:autopilot` sentinel, state flag, and confirmation paragraph.
