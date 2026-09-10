# 20.14 — Autopilot completo en Grok (vínculo 20.13)

Medición viva. Destino: `gon0801/saikit-descartable`. Host: Grok 1.0.24.
Sello vía consumo vinculado (20.13); merge solo con `tools/saikit-merge.sh`.

## Identidad

| Campo | Valor |
|---|---|
| Fecha | 2026-09-09 (PDT) / 2026-09-10Z |
| Checkout kit | `e0f7a2518e6983025d0c19a501a01138c8a730d8` (`HEAD` == `origin/master`) |
| Hook fuente / lab / vivo grok | sha256 `37e55640003afaff6d4a54cf6495afc73bec5799b86323fb7a317889fec78680` (4345 líneas; 4/4 al día) |
| Grok | `1.0.24 (68e414c661e3) [stable]` |
| Deps | 20.8 auth §8 vigente; 20.13 `cc:完了` (deploy REAL) |
| Lab | HOME aislado `/tmp/saikit-2014-IFPGIT` (copia de perfil; hook de la copia). Perfil vivo `~/.grok` no escrito (trusted_folders vivo vacío; key de medición `3731768740` ausente en vivo). |
| gh bajo HOME aislado | keyring no resuelve; wrapper PATH reentra `HOME=/Users/dn` para `gh`/`git` (sin exportar tokens). Declarado residual. |

## Cadena observada (correlacionada)

| Paso | Evidencia | Resultado |
|---|---|---|
| PR | `pr-create.txt`, PR **#8** | OPEN → MERGED |
| CI | Actions `34435315920` / `34435336141` | verde antes del merge |
| Sello hijo | `states/child-seal_boot.env` sesión `01a0898c-…` | `lane=seal_boot` + `veredicto_sha256=fa339156…` |
| Consumo padre | `states/parent-linked.env.observed` sesión `01a08985-…` | `linked_seal_session=01a0898c-…` + mismo hash + `agents_seen=reviewer` |
| Veredicto | `b4cbe346….json` | sha HEAD `b4cbe346…`, PR 8, blast `bash tests/run.sh` |
| LISTO | `out/merge-listo.txt` | `LISTO: … bash tools/saikit-merge.sh --confirmado` |
| sí → merge | `out/merge-confirmado.txt` | `MERGE-OK: 6e095023…` vía tool; **no** `gh pr merge` a pelo |
| postmerge | `out/postmerge.txt` | `VERDE` sobre merge commit; nada que deshacer |
| Sesión ajena | `states/foreign-no-consume.env` | spawn del hijo **sin** SubagentStart previo → sin `veredicto_sha256` / sin `linked_seal_session` |

Head feature: `b4cbe34693a8ff40a6988b12afe91ddbb330bc09` (app 1.1.1 + tools kit).
Merge squash: `6e095023434c1245f5057252c83e878624cd752f`.

## Qué NO se hizo

- No se usó merge manual ni `gh pr merge` directo.
- No se atribuyó sello por mtime / ruta / `task_hash`.
- No se cerró nada como `unknown`: el run1 murió por error de red de la API Grok (`out/run1-api-fail.stderr.txt`); el run2 completó el sello vinculado y el gate.

## Residuales declarados

1. **Wrapper gh/git**: bajo HOME aislado el keyring no autentica; el lab usa wrappers que reentran al HOME del operador solo para esas tools (prohibido `GH_TOKEN=`).
2. **LISTO/`--confirmado` fuera del proceso Grok**: tras el sello vivo, Grok quedó colgado; LISTO y merge los corrió el operador de la medición con el mismo `SAIKIT_ESTADO_ROOT` del lab (estado padre ya consumido). El contrato «sí explícito → solo `saikit-merge.sh --confirmado`» se cumplió; no hubo atajo `gh pr merge`.
3. **Estado padre borrado post-merge**: el dir `01a08985-…` ya no estaba en disco al cerrar (TTL/cleanup); el snapshot `parent-linked.env.observed` documenta lo leído antes. El hijo `seal_boot` y el foreign sí quedaron en disco.
4. **Run1 API fail**: ~454k tokens, sin sello; no cuenta como PASS parcial.

## Veredicto de la fila

**Cadena positiva observada** (PR/CI/sello vinculado/LISTO/sí/merge/postmerge + negativo de sesión ajena). Listo para cierre del lead.
