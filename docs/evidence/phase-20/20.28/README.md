# 20.28 — evidencia review round (macOS)

Identidad de corrida: `run-identity.txt` (plataforma, HEAD de trabajo, hook cksum, gitleaks).

Pares rojo/verde (archivo completo, sin pipe). El rojo se midió **revirtiendo el fix en el árbol** y restaurando después; el verde es el árbol de esta entrega.

| Superficie | Rojo (revertido) | Verde (fix) |
|---|---|---|
| lock / `test_saikit_merge` | `merge-rojo-sin-canon.log` — `lock_dos_worktrees` ROJO; archivo FAIL | `merge-post-verde.log` — OK; mutante sin canon rojo bajo costura symlink |
| fuga / `test_feature_map_integration` | `integration-rojo-sin-snapshot.log` — FAIL con `SAIKIT_MUT_LEAK_SIN_SNAPSHOT=1` en la guarda | `integration-post-verde.log` — OK; listado + mutante |
| secrets / `test_feature_map_secrets_capture` | `secrets-rojo-rc3-as-pass.log` — FAIL: aceptacion conto rc=3 como PASS | `secrets-post-verde.log` — OK; costura PATH → SKIP; camino con gitleaks PASS |
| verify-app / `test_feature_map_verify_app` | `verify_app-rojo-cksum-star.log` — FAIL: `cksum: __pycache__: Is a directory` | `verify_app-post-verde.log` — OK; prune caches + mutantes |

Fuera de alcance (sin cambio): `evento-rail-residuales.md`.
`hooks/` no se tocó (cksum estable en `run-identity.txt`).
