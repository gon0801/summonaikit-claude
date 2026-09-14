# 21.5 — Preflight canónico del recibo (evidencia)

Fase nueva del hook (`SUMMONAIKIT_HOOK_PHASE=preflight` → `preflight_check()`):
ejecuta literalmente `stop_gate` en un subshell con las rutas de escritura
redirigidas a un scratch temporal. Mismo parser, mismas reglas — ninguna
regex ni gramática paralela (lo ata `caso_g9_sin_gramatica_paralela`).

Archivos:

- `rojo-preflight-no-existe.log` — ROJO TDD: el corpus G9 contra el hook sin
  preflight (exit 1; `preflight=SIN-REPORTE` en los 8 casos de corpus).
- `verde-corpus-g9.log` — VERDE: 12/12 casos G9 (exit 0).
- `golden-check-pre.log` — `golden-harness.sh --check` tras el cambio:
  57 escenarios sin deriva de comportamiento (exit 0).
- `golden-record.log` — salida del `--record` (re-grabado de identidad).
- `mutantes-g9-local.log` — corrida local de los 3 mutantes nuevos (`preflight_sin_stop`, `preflight_consume_ciclo`, `preflight_falla_callada`): 3/3 atrapados por el caso declarado (EXIT=0; replica la lógica del runner).
- `check-syntax.log` — gate de sintaxis con brew bash 5.3 sobre hook + tests nuevos y tocados (el bash 3.2 del sistema no parsea el hook ni en master: preexistente, fuera de alcance).
- `run-identity.txt` — identidad de la corrida.
- `evento-rail-decision.md` — decisión sobre los residuales del raíl de
  EVENTO de 20.28 (excluidos de 21.5, declarados).

Baterías completas (a archivo completo, sin pipes): ver reporte del PR.

Nota de re-corridas (2026-09-14Z): el corpus se revalidó contra el árbol final
(`SAIKIT_HOOK_VIVO=$PWD/hooks/summonaikit-harness.sh`: 12/12 OK) — un intento
sin esa variable ejercitó el hook desplegado en `~/.claude/hooks` (sin
preflight) y dio rojo espurio por instrumento, no por el cambio; diagnosticado
por `caso_g9_sin_gramatica_paralela` (`preflight_check no existe en el hook
bajo prueba`). Los logs rojo/verde del árbol final se conservan tal cual.
