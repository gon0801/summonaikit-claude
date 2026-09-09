# Offer a minimum CI workflow

Offer a minimum CI workflow asks whether to write a pinned GitHub Actions
file when the repo has no workflows. Accepting writes real test and verify
commands; rejecting leaves disk unchanged and warns that merge needs checks.
An existing workflow is left intact. Local generation is not a live Actions run.

## Sub-features

- `ci-interactive` accepts the offer on a real PTY and writes the workflow.
- `ci-reject` declines on a real PTY, writes nothing, and warns that merge needs checks.
- `ci-flags` applies `--ci-minimo si` without a TTY and asserts YAML, pins, and run lines.
- `ci-defaults` without a TTY writes nothing and prints the no-CI warning.
- `ci-preserve-foreign` leaves an existing foreign workflow intact and does not add ours.
- `ci-idempotent` does not rewrite the YAML on a second accept.
- `ci-runners` emits the admitted test commands (bash/npm/yarn/pnpm/pytest).
- `ci-unsupported` exits 2 and writes nothing when no runner is present.
- `ci-run-fixture` runs the generated test and verify commands locally; that is not live Actions.
- `ci-pins-ilegible` drives `tools/bump-ci-pins.sh --check` against a fixture
  source (no network): a pin missing OWNER, SHA or TAG makes the check die with
  exit 2 naming the broken pin and the missing field — never «todos los pins al
  dia». Anchored by the product regression
  `pins_pin_incompleto_falla_cerrado_por_campo` (tests/test_ci_minimo.sh) and
  its mutation `pin_ilegible_se_descarta`.
- `ci-pins-proponer` drives `tools/bump-ci-pins.sh --proponer` resolved through
  the `SAIKIT_BUMP_CI_PINS_API` test hook (no network): the output is a
  reviewable unified diff that is NOT applied — the generator checksum is
  unchanged and no floating `@tag` is adopted (the pin stays `owner@sha40`).
  Anchored by the product case `pins_proponer_api_simulada_revisable`
  (tests/test_ci_minimo.sh).

## How to get to it (user POV)

- From a git repo with no workflows, run `bash tools/saikit-ci-minimo.sh --ofrecer` and answer si or no.
- Pass `--ci-minimo si` or `--ci-minimo no` to skip the prompt.
- If any workflow already exists, the tool reports that and does not overwrite it.

## Driving it with control-summonaikit

Preconditions:

- `control-summonaikit doctor` reports isolation ready.
- Interactive accept/reject need a real PTY; if none is available they stay `unknown` (never a fake PTY).
- Generation and local command runs live in a disposable fixture. They do not start GitHub Actions.

- Case `ci-interactive`: action Accept the offer over a real PTY; command `control-summonaikit drive ci-minimo`; observable the offer prompt and `.github/workflows/saikit-ci-minimo.yml` written.
- Case `ci-reject`: action Decline the offer over a real PTY; command `control-summonaikit drive ci-minimo`; observable no workflow file and the no-CI / sin checks warning.
- Case `ci-flags`: action Pass `--ci-minimo si` with stdin not a TTY; command `control-summonaikit drive ci-minimo`; observable parseable YAML, uses @sha40, no secrets, and real test plus verify run lines.
- Case `ci-defaults`: action Run with no flag and no TTY; command `control-summonaikit drive ci-minimo`; observable no write and the no-CI warning.
- Case `ci-preserve-foreign`: action Accept on a repo that already has a workflow; command `control-summonaikit drive ci-minimo`; observable the foreign file checksum unchanged and our YAML absent.
- Case `ci-idempotent`: action Accept twice; command `control-summonaikit drive ci-minimo`; observable the second run keeps the same YAML hash.
- Case `ci-runners`: action Generate for each admitted runner; command `control-summonaikit drive ci-minimo`; observable `bash tests/run.sh`, `npm test`, `yarn test`, `pnpm test`, and `python -m pytest`.
- Case `ci-unsupported`: action Accept on a repo with no runner; command `control-summonaikit drive ci-minimo`; observable exit 2 and no YAML.
- Case `ci-run-fixture`: action Execute the generated `run:` lines in the fixture (skip install/network); command `control-summonaikit drive ci-minimo`; observable test and verify commands ran locally, not live Actions.
- Case `ci-pins-ilegible`: action Delete one `PIN_SETUP_NODE_<campo>` line from a copy of the generator and run `--check` with a fixture source that knows the healthy pins; command `control-summonaikit drive ci-minimo`; observable exit 2 with `PIN_SETUP_NODE` plus the missing field (OWNER, SHA and TAG each), and no «todos los pins al dia».
- Case `ci-pins-proponer`: action Run `--proponer actions/setup-node v4.5.0` with the `SAIKIT_BUMP_CI_PINS_API` hook resolving the tag to a sha40; command `control-summonaikit drive ci-minimo`; observable a unified diff marked «NO aplicada», the generator checksum unchanged, and no `uses: ...@vN` floating tag.

## Gotchas

- A pipe or redirected stdin is not a PTY. The tool then assumes no and does not write.
- Missing PTY is `unknown` for accept/reject only; flags, defaults, runners, and fixture runs stay observable.
- Pins are historical; this drive does not refresh them. A green local run does not mean Actions ran.
- `bump-ci-pins.sh --check` is read-only and fail-closed: exit 0 («al dia») is
  only valid when EVERY pin could be read and compared. An incomplete pin
  (missing OWNER/SHA/TAG) is illegible and dies with exit 2 naming pin and
  field; exit 1 is a readable-but-stale pin and exit 2 also covers no network
  or unknown tag. `--proponer` never writes: it prints a reviewable diff
  (covered by the `ci-pins-proponer` case, not just this gotcha).
- Any existing `*.yml`/`*.yaml` under `.github/workflows` is PRESENTE: the tool is a no-op and must not overwrite.
