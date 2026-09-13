# 20.25 — primera pasada de mantenimiento del feature map (2026-09-13)

- checkout SHA: `ede1337` (== origin/master, árbol limpio al lanzar)
- hook: commit `16aea80`, contenido sha256 `37e55640…` (pin vigente)
- run: `20260913T085504Z-28670` (HOME aislado, hook preparation diferida)
- lint: `feature-map: OK` (cubre el catálogo completo)
- `list-features`: 17/17 features (ver `list-features-full.txt`)
- log de corridas: `drives-primera-pasada.log` (+ re-drive check-secrets tras el fix)

## Matriz feature → fuente → modo → attempt/result → prerrequisito

| feature | fuente | modo | attempt/result | prerrequisito |
|---|---|---|---|---|
| install-guardian | ficha + driver install-guardian.sh | sandbox | FAIL (hook-prepare exit 5; causa R34) | hook instalable en DEST |
| gate-turn | ficha + driver gate-turn.sh | sandbox | FAIL (hook-prepare exit 5; causa R34) | hook instalable en DEST |
| audit-ledger | ficha + driver | sandbox | PASS | ninguna viva |
| check-deploy-log | ficha + driver | sandbox | PASS | ninguna viva |
| saikit-merge | ficha + driver (doubles) | simulated | PASS (13 casos) | ninguna viva |
| saikit-postmerge | ficha + driver (doubles) | simulated | PASS (9 casos; incluye postmerge-hint-pendiente y postmerge-no-color) | ninguna viva |
| setup-autopilot | ficha + driver | sandbox | PASS (10 casos; incluye setup-lock / lock-held) | ninguna viva |
| ci-minimo | ficha + driver | sandbox | PASS | ninguna viva |
| autopilot-contract | ficha + driver | sandbox | FAIL (hook-prepare exit 5; causa R34) | hook instalable en DEST |
| install-hosts | ficha + driver | sandbox | FAIL (hook-prepare exit 5; causa R34) | hook instalable en DEST |
| routing-recipes | ficha + driver | sandbox | PASS | ninguna viva |
| check-secrets | ficha + driver | sandbox | unknown/3 (sin gitleaks; fallback declarado, no acredita motor fuerte) | detector fuerte para PASS |
| capture-payloads | ficha + driver | sandbox | PASS | ninguna viva |
| decision-blast | ficha + driver | sandbox | PASS | ninguna viva |
| verify-app | ficha + driver | sandbox | PASS | ninguna viva |
| stage-override | ficha + driver | sandbox | FAIL (hook-prepare exit 5; causa R34) | hook instalable en DEST |
| merge-happy-path | driver evaluador (19.16; nunca mergea) | live | unknown/bloqueado (sin autorización viva, sin destino, gh ausente) | alcance 20.8 + destino |

## Pendientes conocidos del bloque 1 (fuente, ficha, driver, mutante)

Ya corregidos y mergeados — no re-hechos; figuran con su evidencia:

- hints ejecutables de postmerge → 20.28 (PR #298); casos postmerge-hint-* conducidos hoy: PASS
- setup liberar-lock → 20.28 (PR #298); casos setup-lock* conducidos hoy: PASS
- neutralización de `CLICOLOR_FORCE` → 18.25 + caso postmerge-no-color conducido hoy: PASS
- retirada `--dry-run` de zcode/grok → 20.24 (PR #267); casos hosts-quitar-*-dry en
  install-hosts: NO conducidos hoy (hook-prepare exit 5) — evidencia 20.24 no reutilizable
  (distinto checkout SHA); quedan FAIL-con-causa en esta pasada, no PASS

## Gap del harness hallado y corregido en la pasada (G1)

`"${extra[@]}"` con arreglo vacío bajo `set -u` muere en bash ≤4.3
(macOS sistema): `cmd_doctor` pelado + `run_tool` de check-secrets (línea 202,
alcanzable sin gitleaks usable y sin fallback forzable). Fix: idiom portable
`${extra[@]+"${extra[@]}"}` en ambos sitios + mutante `doctor_array_sin_guardia`
+ regresión en `tests/test_feature_map_doctor.sh` (2 casos nuevos, verdes aquí;
mutante rojo medido en bash 3.2, SKIP declarado en bash ≥4.4).
Re-conducción: `doctor` pelado RC=0; check-secrets re-drive unknown/3 honesto.
Evidencia: `/tmp/bloque6-doctor-test.log` (16/17 casos; el restante es R34).

## Gap reportado aparte (R34, sin fix en la pasada)

El hook no parsea con bash 3.2 del sistema (apóstrofes de la prosa dentro del
`$(cat <<'HARNESS_CONTEXT')`; bash ≥4 OK; pre-existente hasta HEAD~60; CI Linux
verde). En esta Mac: instalador rehúsa (exit 5), 5 features con instancia en
FAIL, `doctor` instancia en FAIL. Fix (reescribir el heredoc o el guard del
instalador) toca `hooks/`+`tools/`: fuera del alcance skill/map/harness,
requiere decisión de producto. No oculto; sin fila abierta.

## Veredicto global: `changed`

La pasada se completó (17/17 conducidas una vez en su modo declarado, sin
superficie paralela), halló y corrigió un gap del harness con regresión,
mutante y re-conducción. Los 5 FAIL son de entorno con causa única declarada
(R34); los 2 unknown, declarados con razón. Ningún FAIL ni unknown convertido
en PASS. Evidencia 20.x no reutilizada (ninguna coincide en checkout SHA).
