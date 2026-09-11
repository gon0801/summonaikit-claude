# 20.16 — Supervisión del cierre headless

Implementación de la superficie de observación definida en 20.15.

## Identidad

| Campo | Valor |
|---|---|
| Fecha | 2026-09-11 (EDT/PDT) |
| Checkout kit | `3ce973d` (spike/20.15-headless-close, HEAD == origin/master post-#301) |
| Hook fuente | sha256 `37e55640…` (4345 líneas; 4/4 al día) |
| Dependencias | 20.8 (`cc:完了`), 20.15 (`cc:完了`, PR #302) |
| Host medido | nodo Mac (darwin arm64), bash 5.3 homebrew |

## Entregables

| Artefacto | Ruta | Estado |
|-----------|------|--------|
| Launcher | `tools/headless-close.sh` | Integrado con recibo (9/9 tests) |
| Recibo | `tools/headless-close-receipt.sh` | JSON con jq (10/10 tests) |
| Tests launcher | `tests/test_headless_close.sh` | 9 PASS / 0 FAIL |
| Tests recibo | `tests/test_headless_close_receipt.sh` | 10 PASS / 0 FAIL |
| Contrato | `docs/spec/headless-close-contract.md` | De 20.15 |

## Qué observa la superficie

El launcher (`headless-close.sh`) envuelve `claude -p` y al terminar:
1. Captura el RC del proceso hijo.
2. Lee el estado del harness (`.saikit/*/harness-state.env`).
3. Escribe un recibo JSON en `.saikit/close-receipts/<session>.json` con:
   - `session_key`, `timestamp`, `checkout_sha`, `hook_sha`
   - `close_type`: `clean` (Stop disparó) | `forced` (launcher limpió) | `unknown`
   - `rc`, `task_hash`, `agents_seen`, `cycle`
4. Limpia estado + zona adversary.

## Mutantes discriminados

| Mutante | Qué atrapa | Test |
|---------|-----------|------|
| `close_type` inválido → no escribir | Validación de tipo | `close_type inválido → exit 2` |
| RC no numérico → no escribir | Validación numérica | `RC no numérico → exit 2` |
| Sin `jq` → fallback seguro | JSON con chars especiales | `clean receipt: JSON válido` (jq path) |
| Sin recibo → limpieza forzada | Detección de estado | `cleanup sin recibo: estado borrado` |
| Con recibo → limpieza normal | Detección de recibo | `cleanup con recibo: estado borrado` |
| Zona adversary → se limpia | Limpieza de zona | `adversary zone: limpiada` |
| RC propagado | Exit code del hijo | `RC propagation: exit 42 propagado` |
| Sin `.saikit/` → no-op | Aislamiento | `sin .saikit/: no-op` |
| Launcher escribe recibo | Integración | `launcher escribe recibo de cierre` |
| Recibo con campos completos | Completitud | `campos requeridos: todos presentes` |

## Cómo abre 20.17

20.17 mide la cadena host/hook/supervisor/estado en vivo:
- Delegación sync: el launcher corre, el host completa, el recibo se escribe.
- Delegación async: el launcher corre, el host delega, el subagente completa,
  el recibo se escribe con `close_type=forced` si el Stop no disparó.
- Teardown: el launcher detecta la ausencia de Stop y limpia.
- La correlación es por `session_key` en el recibo vs el estado del host.
