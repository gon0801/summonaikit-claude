# Gate an AI turn

Gate an AI turn is the product core: when a prompt includes the sentinel
`-saikit`, the hook arms and injects the harness contract; without it, the hook
must not create session state or block the turn.

## Sub-features

- `gate-unarmed` leaves no state for a prompt without `-saikit`.
- `gate-armed` injects the harness contract on a prompt with `-saikit`.
- `gate-stop-no-receipt` lets an armed Stop without a receipt close (fixture 07,
  exit 0): since Bloque A the Stop no longer demands a receipt or a ceremony per
  turn — delivery requires the roles through the PR receipt at approve/merge time.
- `gate-via-golden` drives real captured payloads through `tools/golden-harness.sh`.
- `gate-grok-bg-doc-roto` was retired by Bloque A: with no ceremony blocks left,
  the "broken document falls back to the normal gate" distinction is no longer
  observable at drive level. The DELEGATED hatch stays in the hook as a fast
  wait path; its parsing is pinned by the G4 product cases.
- `gate-advzona-teardown-seguro` and `gate-advzona-unknown-limpia` drive the
  adversarial-zone teardown in a hook copy: a symlinked ancestor (`.saikit`,
  `scratch`, `scratch/adversary` or the session dir) makes the cleanup OMIT
  itself with a diagnostic (fail-open, the turn is not blocked) and an outside
  sentinel survives; the honest-unknown terminal exit (both text channels
  blind) removes the session state AND its zone without touching foreign
  scratch content. Anchored by `advzona_teardown_no_atraviesa_enlaces_de_ancestros`
  and `advzona_unknown_honesto_limpia_la_zona` plus their per-ancestor and
  `zona_unknown_sin_limpieza` mutations (tests/test_adversary_lock.sh).

## How to get to it (user POV)

- In Claude Code, send a normal prompt (no sentinel): the gate stays down.
- Send a prompt containing `-saikit`: the harness arms for that session.
- End a turn; the Stop hook judges the receipt when the session was armed.

## Driving it with control-summonaikit

Preconditions:

- `control-summonaikit launch` created the isolated run. A scoped
  `doctor gate-turn` may report the deferred hook as `MISSING`; the drive
  prepares it from repo source before running the fixtures.
- Fixture directories exist under `tests/fixtures/escenarios/`.

- Case `gate-unarmed`: action Drive unarmed golden scenario; command `control-summonaikit drive-gate-scenario 01-sin-armar`; observable hook sha, steps `01 02 03`, `(sin estado)`, and no harness contract.
- Case `gate-armed`: action Drive armed golden scenario; command `control-summonaikit drive-gate-scenario 02-armado-contrato`; observable hook sha, `SUMMONAIKIT HARNESS REQUIRED`, `harness-state.env`, and `task_hash`.
- Case `gate-stop-no-receipt`: action Drive armed Stop without receipt; command `control-summonaikit drive-gate-scenario 07-evidencia-incompleta`; observable clean close (exit 0) on fixture 07, not on 01/02.
- Case `gate-advzona-teardown-seguro`: action Arm an adversary session in a hook copy, replace `.saikit` with a symlink to an outside dir holding a sentinel, then send a disarm prompt; command `control-summonaikit drive gate-turn`; observable exit 0 with `limpieza de zona OMITIDA` / `es symlink` on stderr and the sentinel intact.
- Case `gate-advzona-unknown-limpia`: action Arm and dispatch an adversary session, create the zone plus foreign scratch content, then Stop with no message and no transcript; command `control-summonaikit drive gate-turn`; observable exit 0, session state gone, own zone gone, foreign zone and loose scratch file intact.

- **Proof.** Keep the attempt under `artifacts/<run>/gate-turn/<attempt>/`.
  The unarmed log must show `(sin estado)` and no contract; the armed log must
  show contract JSON plus `harness-state.env`. Stop without receipt is a
  separate case — do not treat 01/02 as that close.

## Gotchas

- Always pass `--hook` to the disposable `VERIFY_DEST` (the helper does this).
  Default golden-harness `--print` otherwise targets the live profile hook.
- Scenario names are directory names under `tests/fixtures/escenarios/`; typos
  fail closed with `unknown scenario`.
- Full-suite `golden-harness.sh --check` is a CI/regression tool, not a single
  feature drive — use one scenario at a time here.
- The sentinel is exactly `-saikit` with word boundaries; substrings inside
  other tokens must not arm (covered by other fixtures; do not invent prompts).
- 18.27: Grok headless (`-p`) can exit without a receipt. Since Bloque A the
  Stop no longer demands one per turn, so that exit is a normal close; merge
  still stays fail-closed without the delivery receipt on the PR. The wake
  form and the DELEGATED in-flight-work parsing stay in the hook as a fast
  wait path (pinned by the G4 product cases), but a broken document now
  falls through to the same clean close instead of blocking.
- Zone teardown is fail-open BY DESIGN: if the cleanup cannot prove the zone
  is under the canonical root (symlinked ancestor), it omits itself with a
  diagnostic instead of blocking the turn — nothing foreign is deleted, and
  the zone is left in place for the operator.
