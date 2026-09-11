# 20.28 — evidencia (cierre review)

Identidad: `run-identity.txt` (plataforma, SHA final, hook cksum, gitleaks).

Pares rojo/verde a archivo completo (sin pipe). Merge e integration: validados en la ronda previa + gate; no se re-miden.

| Superficie | Rojo | Verde |
|---|---|---|
| lock / `test_saikit_merge` | `merge-rojo-sin-canon.log` | `merge-post-verde.log` |
| fuga / `test_feature_map_integration` | `integration-rojo-sin-snapshot.log` | `integration-post-verde.log` |
| secrets / `test_feature_map_secrets_capture` | `secrets-rojo-rc3-as-pass.log` — MUT en aceptacion real (`veredicto_check_secrets`) → PASS falso sin summary | `secrets-post-verde.log` — drive via veredicto; costura PATH → SKIP |
| verify-app / `test_feature_map_verify_app` | `verify_app-rojo-cksum-star.log` — `cksum: saikit-planted-dir-20.28: Is a directory` (sin `__pycache__` ambiental) | `verify_app-post-verde.log` — plantado sin punto; mutante cksum* rojo por el plantado |

Fuera de alcance: `evento-rail-residuales.md`.
`hooks/` intacto.
