# Route models and lock the recipe book

Route models and lock the recipe book resolves already-supported roles through
`tools/model-routing.sh` and checks the recipe manifest with
`tools/gen-recetas-manifest.sh`. Empty host rows stay empty. Optional 16.7
(`--task <receta>`) is not implemented and is not credited.

## Sub-features

- `routing-roles` resolves implementer/reviewer on measured hosts and keeps zcode/kimi/dsh empty.
- `routing-unknown` rejects an unknown role with exit 2 and no stdout.
- `recipes-manifest-ok` accepts a sandbox manifest that matches its recipes.
- `recipes-manifest-altered` rejects a stale or altered manifest with exit 1.
- `recipes-consume` shows a consumer reading the published/sandbox recetario by name and hash.
- `routing-no-16.7` proves `--task` is an unknown argument (Optional 16.7 stays unimplemented).
- `routing-no-live` states that routing/manifest checks are not a live model turn and do not load the dsh adapter.

## How to get to it (user POV)

- Run `bash tools/model-routing.sh --host claude --role implementer --field model`.
- Run `bash tools/gen-recetas-manifest.sh --check` (or `--dir` on a disposable copy).
- Do not pass `--task`; that optional mapping was never shipped.

## Driving it with control-summonaikit

Preconditions:

- `control-summonaikit launch` created an isolated HOME.
- Recipe writes use a disposable directory, never the checkout `recetas/`.
- This drive does not implement Optional 16.7.

- Case `routing-roles`: action Resolve supported roles on measured and empty hosts; command `control-summonaikit drive routing-recipes`; observable `claude-sonnet-5` for claude/implementer, `grok-4.6` for grok/reviewer, and empty stdout for zcode/kimi/dsh.
- Case `routing-unknown`: action Pass an invented role; command `control-summonaikit drive routing-recipes`; observable exit 2 and empty stdout.
- Case `recipes-manifest-ok`: action Generate and `--check` a valid sandbox recetario; command `control-summonaikit drive routing-recipes`; observable `--check` exit 0.
- Case `recipes-manifest-altered`: action Change a recipe after generating the manifest; command `control-summonaikit drive routing-recipes`; observable `--check` exit 1 (stale/altered).
- Case `recipes-consume`: action Read the sandbox or published MANIFEST; command `control-summonaikit drive routing-recipes`; observable a named recipe (bug) and its hash line.
- Case `routing-no-16.7`: action Invoke `model-routing.sh --task`; command `control-summonaikit drive routing-recipes`; observable unknown-argument / not implemented (no task-to-tier mapping).
- Case `routing-no-live`: action Finish the routing/manifest drive; command `control-summonaikit drive routing-recipes`; observable a recorded limit that this is not a live model turn and did not load the dsh adapter.

## Gotchas

- A host row that was never measured must stay empty (exit 0, no default model).
- `--check` against the checkout is not this drive; the drive uses `--dir` on a disposable copy so it cannot dirty Git.
- Optional 16.7 (`--task <receta>` ⇒ tier) is out of scope. A green routing drive does not ship it.
- Resolving a model id is not a live turn. Publishing the dsh plugin is not proof the host loaded it.
