# 20.17 — Medición viva del cierre headless

Test de medición que correlaciona host exit code, hook decision y receipt JSON.

## Identidad

| Campo | Valor |
|---|---|
| Fecha | 2026-09-11 (EDT/PDT) |
| Checkout kit | `5a8a820` (impl/20.17-headless-live, rebased on #303) |
| Dependencias | 20.15 (contrato, PR #302), 20.16 (receipt, PR #303) |
| Host medido | nodo Mac (darwin arm64), bash 5.3 homebrew |

## Entregables

| Artefacto | Ruta | Estado |
|-----------|------|--------|
| Test de medición viva | `tests/test_headless_close_live.sh` | Committeado, skip-safe |
| Modos | sync / async / teardown / all | Implementados |

## Resultado de medición

| Prueba | RC host | Receipt | Estado |
|--------|---------|---------|--------|
| sync | — | — | SKIP (sin binario claude) |
| async | — | — | SKIP (sin binario claude) |
| teardown | — | — | SKIP (sin binario claude) |

**Motivo del SKIP:** El Mac node no tiene el binario `claude` instalado.
El test es skip-safe: si no hay binario, termina con exit 0 y reporta SKIP.

## Qué mide

El test ejecuta el launcher `headless-close.sh` con tres modos:

1. **sync**: Prompt simple que completa normalmente. Verifica que el recibo
   se escriba con `close_type` ∈ {clean, forced, unknown}.
2. **async**: Prompt que dispara subagent. Verifica receipt tras delegación.
3. **teardown**: Lanza proceso con `sleep 300`, espera 5s, mata el PID.
   Verifica que el launcher maneje la terminación forzada.

## Correlación

| Canal | Fuente | Verifica |
|-------|--------|----------|
| Host exit code | `$?` del launcher | Proceso completó o fue killed |
| Receipt JSON | `.saikit/close-receipts/<session>.json` | close_type, rc, timestamp, hook_sha |
| Hook decision | Evidence log del harness | Decisión del hook al cerrar |

## Para medir en vivo

```bash
# Requiere binario claude o grok en PATH
bash tests/test_headless_close_live.sh claude all
bash tests/test_headless_close_live.sh grok all
```
