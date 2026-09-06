# Confirm before an autopilot merge

Confirm before an autopilot merge is the per-turn `-saikit:autopilot` contract:
the hook arms the full ceremony, writes `autopilot=1`, and injects a paragraph
that prepares the PR and then stops to ask. A typo or a later prompt without
the exact sentinel does not inherit the flag.

## Sub-features

- `autopilot-sentinel` arms lane `full` and `autopilot=1` only for the exact sentinel.
- `autopilot-no-inherit` leaves the flag absent for plain `-saikit`, a typo, and a follow-up without the sentinel.
- `autopilot-paragraph` injects the confirmation paragraph and does not promise unattended merge or revert.
- `autopilot-persist` keeps `autopilot=1` after a mid-turn tool rewrite from a current fixture.

## How to get to it (user POV)

- In a prompt, write `-saikit:autopilot` (exact suffix). The turn runs the full ceremony and the contract asks before publishing.
- A typo such as `-saikit:autopiloto` still arms full, but without the autopilot flag or paragraph.
- A later message in the same session without the sentinel disarms; the next turn does not inherit autopilot.

## Driving it with control-summonaikit

Preconditions:

- `control-summonaikit doctor` reports isolation ready and `tests/fixtures/escenarios` intact.
- The drive consumes current golden fixtures (01, 02, and a pytest tool step). It does not rewrite hook or baseline.

- Case `autopilot-sentinel`: action Drive a prompt derived from fixture 02 with the exact sentinel; command `control-summonaikit drive autopilot-contract`; observable `-saikit:autopilot`, `lane=full`, and `autopilot=1`.
- Case `autopilot-no-inherit`: action Drive fixture 02, a typo suffix, and a follow-up without the sentinel; command `control-summonaikit drive autopilot-contract`; observable no `autopilot=1` on those paths, and the follow-up disarms.
- Case `autopilot-paragraph`: action Read the contract from the exact-sentinel drive; command `control-summonaikit drive autopilot-contract`; observable `Autopilot lane`, `STOP AND ASK`, and no unattended merge/revert promise.
- Case `autopilot-persist`: action After the exact sentinel, replay the pytest tool fixture; command `control-summonaikit drive autopilot-contract`; observable `autopilot=1` still in state.

- **Proof.** Keep the attempt under `artifacts/<run>/autopilot-contract/<attempt>/`.
  Header plus exit 0 is not enough: state must show `autopilot=1` only for the
  exact sentinel, and the paragraph must ask before publishing.

## Gotchas

- The sentinel is per-turn and exact (`-saikit:autopilot` with the same word boundary as `:fast`). A substring or typo is not inheritance.
- This drive observes the current hook. If the source is wrong, open a product defect; do not patch hook or golden to make the card green.
- Fixture 02 (`-saikit` without suffix) is the control that full-without-flag stays byte-shaped: the `autopilot=` line is absent.
