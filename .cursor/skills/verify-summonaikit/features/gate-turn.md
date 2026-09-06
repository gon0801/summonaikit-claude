# Gate an AI turn

Gate an AI turn is the product core: when a prompt includes the sentinel
`-saikit`, the hook arms and injects the harness contract; without it, the hook
must not create session state or block the turn.

## Sub-features

- `gate-unarmed` leaves no state for a prompt without `-saikit`.
- `gate-armed` injects the harness contract on a prompt with `-saikit`.
- `gate-stop-unarmed` allows Stop with exit 0 and no gate pressure when never armed.
- `gate-via-golden` drives real captured payloads through `tools/golden-harness.sh`.

## How to get to it (user POV)

- In Claude Code, send a normal prompt (no sentinel): the gate stays down.
- Send a prompt containing `-saikit`: the harness arms for that session.
- End a turn; the Stop hook judges the receipt when the session was armed.

## Driving it with control-summonaikit

Preconditions:

- `control-summonaikit doctor` reports `doctor: PASS`.
- Fixture directories exist under `tests/fixtures/escenarios/`.

- Case `gate-unarmed`: action Drive unarmed golden scenario; command `control-summonaikit drive-gate-scenario 01-sin-armar`; observable exit `0`, `=== escenario 01-sin-armar`, and `(sin estado)` / no harness-state after prompt.
- Case `gate-armed`: action Drive armed golden scenario; command `control-summonaikit drive-gate-scenario 02-armado-contrato`; observable exit `0`, contract / `SUMMONAIKIT HARNESS`, and state under `hooks/state/`.

- **Proof.** Keep both `artifacts/gate-01-sin-armar-*.txt` and
  `artifacts/gate-02-armado-contrato-*.txt`. The unarmed log must not show a
  `harness-state.env`; the armed log must.

## Gotchas

- Always pass `--hook` to the disposable `VERIFY_DEST` (the helper does this).
  Default golden-harness `--print` otherwise targets the live profile hook.
- Scenario names are directory names under `tests/fixtures/escenarios/`; typos
  fail closed with `unknown scenario`.
- Full-suite `golden-harness.sh --check` is a CI/regression tool, not a single
  feature drive — use one scenario at a time here.
- The sentinel is exactly `-saikit` with word boundaries; substrings inside
  other tokens must not arm (covered by other fixtures; do not invent prompts).
