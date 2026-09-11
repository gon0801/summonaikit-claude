# 20.15 — diseño de cierre headless (redo post #307)

Fecha: 2026-09-11. Rama `impl/20.15-17-headless-redo` sobre
`origin/revert/block3-20.15-17` (PR #307 queda revert-only).

## Cómo el launcher conoce su sesión

Claude `-p --output-format json` expone `session_id` top-level (medido 20.10
`docs/evidence/phase-20/20.10/runs/turn1.json`). Grok: misma forma
`-p --single --output-format json`; el mock de 20.16 cubre argv; medición viva
Grok queda pendiente si el binario no está.

## STATE_PATH

Exacto al hook. Vacío → `UNKNOWN`. Sin glob. Sin `sin-session`.

## Teardown sin Stop

El supervisor observa leftover en su ruta. Recibo de 6 etiquetas ⇒ forced
clean exit 0. Sin recibo ⇒ exit 1. No se cita 18.27 como evidencia de este redo.

## Medición viva 20s `claude -p`

Corrida 2026-09-11 en Davids-MBP: `tools/headless-close.sh --timeout 20` con
binario `/Users/dn/.local/bin/claude` (vía SAIKIT_CLAUDE_BIN). JSON con
`session_id=92312d88-4ef1-4336-8162-759c3bea1702` top-level. close_type=clean
(sin leftover de hook en el sandbox). rc=0. No hubo COMPANION_APP_UNAVAILABLE.
No se tocó Terminal.app. No se relanzó.

## Fuera de alcance

No se toca Claude Terminal.app. No se mergea. Plans.md 20.15–17 siguen
`cc:TODO` hasta que David mergea.
