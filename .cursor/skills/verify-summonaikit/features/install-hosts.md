# Install hosts and register them

Install hosts and register them publishes the four hook copies (claude, grok,
dsh, codex) into isolated destinations. zcode reuses the Claude copy; kimi
publishes agent profiles and does not invent another hook file. Registration
is judged by diagnostic text and structure, never by exit 0 alone.

## Sub-features

- `hosts-four-copies` installs the four hook copies and proves zcode/kimi did not invent another.
- `hosts-zcode-reuses` appends zcode registration against the Claude dest and leaves that dest untouched.
- `hosts-kimi-profiles` publishes kimi profiles without model/effort and without a hook copy.
- `hosts-identity` checks ownership marker, dest hash vs source, and known Git provenance.
- `hosts-noop` reprints `YA AL DIA` when a host dest already matches the source.
- `hosts-retirada` removes a host publish while leaving a neighbor intact.
- `hosts-quitar-zcode-dry` reports and classifies the zcode retirement without executing it: every piece (user-config 5.4 entries, agent profiles) stays present after the dry-run.
- `hosts-quitar-grok-dry` reports and classifies the grok retirement (JSON, hook, agents) without executing it: all pieces stay present after the dry-run.
- `hosts-foreign` leaves a neighbor file that is not the destination untouched.
- `hosts-registration` judges registration by diagnostic text and phase structure, not exit 0.
- `hosts-os-unavailable` records the Windows or POSIX branch that this OS cannot observe, without invalidating the other hosts.
- `hosts-symlink` refuses to follow a recipe/dest symlink (or reports unknown if the host cannot create real links).
- `hosts-no-live` states that an isolated install is not a live model turn and does not load the dsh adapter.

## How to get to it (user POV)

- Run `bash tools/install-hook.sh --host grok|dsh|codex` (or the default Claude dest) after a merge.
- Run `bash tools/install-hook.sh --host zcode` to register against the Claude copy; ` --host kimi` to publish profiles only.
- Run `bash tools/check-hook-registration.sh` with the host-specific settings/config flags. Read the text; ignore the exit code.

## Driving it with control-summonaikit

Preconditions:

- `control-summonaikit launch` created an isolated HOME (never a live profile).
- `control-summonaikit doctor` reports isolation ready.
- jq is required for grok/zcode writes; a missing jq is an explicit host-unavailable reason, not a FAIL of the other hosts.

- Case `hosts-four-copies`: action Install claude/grok/dsh/codex hook copies in the sandbox; command `control-summonaikit drive install-hosts`; observable four dest hashes match source and zcode/kimi have no extra hook file.
- Case `hosts-zcode-reuses`: action Register zcode against the Claude dest; command `control-summonaikit drive install-hosts`; observable four phases in the zcode user-config and Claude dest bytes unchanged.
- Case `hosts-kimi-profiles`: action Publish kimi profiles; command `control-summonaikit drive install-hosts`; observable role files with the kit mark, no `model:`/`effort:`, dest unchanged.
- Case `hosts-identity`: action Inspect installed copies and installer log; command `control-summonaikit drive install-hosts`; observable `SAIKIT-CLAUDE-OWNED`, dest sha equals source, and `procedencia: rama=`.
- Case `hosts-noop`: action Reinstall a matching host dest; command `control-summonaikit drive install-hosts`; observable `YA AL DIA` and dest bytes unchanged.
- Case `hosts-retirada`: action Remove a grok publish beside a neighbor; command `control-summonaikit drive install-hosts`; observable quit/backup text and neighbor checksum intact.
- Case `hosts-quitar-zcode-dry`: action Dry-run the zcode retirement after a zcode install; command `control-summonaikit drive install-hosts`; observable `dry-run: --quitar-zcode no ejecuta la retirada`, per-piece classification, and config entries plus agent profiles still present.
- Case `hosts-quitar-grok-dry`: action Dry-run the grok retirement after a grok install; command `control-summonaikit drive install-hosts`; observable `dry-run: --quitar-grok no ejecuta la retirada`, JSON/hook/agents classified, and all pieces still present.
- Case `hosts-foreign`: action Install beside a neighbor file; command `control-summonaikit drive install-hosts`; observable neighbor checksum intact.
- Case `hosts-registration`: action Run the registration checker on isolated host files; command `control-summonaikit drive install-hosts`; observable diagnostic text naming phases or REGISTRO, recorded as structure, not as exit 0.
- Case `hosts-os-unavailable`: action Observe the Windows or POSIX wrap branch this OS cannot run; command `control-summonaikit drive install-hosts`; observable `unknown` for the missing OS branch and the other host copies still present.
- Case `hosts-symlink`: action Point a recipe dest at a real symlink; command `control-summonaikit drive install-hosts`; observable the external target stays intact and the installer reports an enlace, or `unknown` if the host cannot create real symlinks.
- Case `hosts-no-live`: action Finish the isolated install drive; command `control-summonaikit drive install-hosts`; observable a recorded limit that this is not a live model turn and did not load the dsh adapter.

## Gotchas

- `--check` without an isolated HOME reads live host copies. This drive never does that.
- zcode and kimi are not `--check --host` values: zcode reuses Claude; kimi does not declare a hook copy.
- Registration always exits 0 (fail-open). A silent exit is not proof. Read the diagnostic.
- A missing Windows `.ps1` or a missing POSIX wrap is an OS-unavailable observation. It does not fail the other hosts.
- Installing a host copy is not a live turn and does not prove dsh loaded the adapter.
