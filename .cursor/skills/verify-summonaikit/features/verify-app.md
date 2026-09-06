# Generate the Spanish app map

Generate the Spanish app map writes `verify/` once on a disposable fixture
via `skills/saikit-verificar-app/verificar.sh`. A second generate rejects and
leaves prior files intact. `estado` reports a current seal versus observed
drift. A skill PASS is not the product `verify/` PASS and does not refresh
the checkout seal.

## Sub-features

- `verify-generate` writes the expected map files in a new fixture and seals the real SHA.
- `verify-reject-existing` refuses to regenerate over an existing map and leaves those files unchanged.
- `verify-estado` reports `al_dia` for the current seal and `desactualizado` after observed drift.
- `verify-drive-cmd` publishes a Drive command that includes `verify/` and matches `TEST_RUNNER_RE` from the hook source.
- `verify-no-product-pass` records that this drive does not credit or refresh the checkout `verify/` seal.

## How to get to it (user POV)

- Run `bash skills/saikit-verificar-app/verificar.sh generar <repo>` on a repo that has no `verify/LEEME.md`.
- Run the same command again: it refuses and does not rewrite.
- Run `bash skills/saikit-verificar-app/verificar.sh estado <repo>` to see `al_dia` or `desactualizado`.

## Driving it with control-summonaikit

Preconditions:

- `control-summonaikit launch` created an isolated HOME.
- Generation runs only in a disposable fixture. The checkout `verify/` is not rewritten.
- A green skill drive is not a product `verify/` PASS.

- Case `verify-generate`: action Generate the map on a new fixture; command `control-summonaikit drive verify-app`; observable `verify/LEEME.md` and the other map files with a seal that carries the fixture SHA.
- Case `verify-reject-existing`: action Generate again over that fixture; command `control-summonaikit drive verify-app`; observable a non-zero reject and unchanged prior files.
- Case `verify-estado`: action Read estado, then change measured content and commit; command `control-summonaikit drive verify-app`; observable `al_dia` then `desactualizado`.
- Case `verify-drive-cmd`: action Read `COMANDO_DRIVE` from the fixture `Drive.md`; command `control-summonaikit drive verify-app`; observable the command includes `verify/` and matches `TEST_RUNNER_RE` from the hook source.
- Case `verify-no-product-pass`: action Finish the drive without touching checkout `verify/`; command `control-summonaikit drive verify-app`; observable the checkout seal bytes unchanged and a recorded limit that skill PASS is not product verify PASS.

## Gotchas

- The generator runs once. An existing `verify/LEEME.md` is a reject, not a refresh.
- `estado` without a readable `generado:` seal is `unknown`, never `al_dia`.
- Do not refresh the checkout `verify/` seal here. 19.17 runs `pytest verify/`
  isolated and records that result; a skill PASS is not the product seal.
- Passing this feature does not mean the product Spanish map is current.
