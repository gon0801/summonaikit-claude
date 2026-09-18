# Feature map

The maintained map lives at
`.cursor/skills/verify-summonaikit/features/README.md`, with one card per
feature and a JSON descriptor next to each card. The pre-commit candado
`feature-map catalog/descriptors/cards` fails when the code, the catalog and
the cards disagree. That is why this directory holds no cards of its own. A
second copy would drift without a candado.

Enumerate the live inventory without launching:

```bash
.cursor/skills/verify-summonaikit/scripts/control-summonaikit list-features
```

Then open `.cursor/skills/verify-summonaikit/features/<id>.md` for the recipe.
Each card names its sub-features, how the operator reaches it, how the
controller drives it and its gotchas.
