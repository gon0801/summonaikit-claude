# Task 7.2 — Veredictos del contrato de SALIDA de Grok Build 1.0.3

Fecha: 2026-08-14. Medición headless (`grok -p`) sobre repo descartable,
siguiendo `docs/task-7.2-plan.md` §C. 7 rondas (una por modo) + 4 variantes
oráculo para validar el canal de `additionalContext` (hallazgo 5 del
cross-review del plan: no se declara `ignored` sin validar el oráculo).
Sin payloads, sin prompts, sin rutas de perfil completas; las citas de log son
líneas redactadas. Los debug logs quedan en el repo descartable y **no se
commitean** (contienen credenciales de sesión — higiene declarada).

## Tabla de veredictos

| Modo | Forma emitida | Veredicto | Señal |
|---|---|---|---|
| `empty` | (control, sin salida) | — | 1 `end_turn` + 1 `shutdown`, exit 0 |
| `block0` | `{"decision":"block","reason":…}` top-level, exit 0 | **ACEPTADA** | log: `stop hook completed … block=true`; exactamente 2 `end_turn`; el texto del turno **cita el reason** (el modeló lo recibió) |
| `exit2` | stdout vacío + stderr, exit 2 | **IGNORADA** | log: `stop hook failed; ignoring (fail-open) … exit code 1` — el wrapper PowerShell devuelve 1 (no 2) y Grok es fail-open ante exit ≠ 0 en Stop |
| `budget` | `{"continue":false,"stopReason":…}`, exit 0 | **ACEPTADA** | log: `prevent_continuation=true` (control: `false`) |
| `context` | `hookSpecificOutput.additionalContext` en `user_prompt_submit` | **IGNORADA** | `.ok` existe; nonce ausente de todos los archivos de sesión; oráculo con instrucción obligatoria: el modelo NO la recibió |
| `extra` | `context` + clave extra `saikitProbe` | **ACEPTADA** (esquema NO estricto) | `hook completed` idéntico al modo sin clave extra; sin rechazo |
| `notice` | `{"systemMessage":…}` en `stop` | **IGNORADA** (en headless) | parsea sin rechazo pero no tiene superficie visible; TUI no medido (límite 7 del plan) |
| `shutdown` | decisión sobre el Stop de cierre | **IGNORADA SIN MUTAR ESTADO** (DoD 2 ✓) | en la ronda block0 el Stop `shutdown` logeó `block=true` (la decisión se emitió) y el proceso salió 0, sin segundo ciclo ni error |

Variantes oráculo de `additionalContext` (todas con instrucción observable
obligatoria; el modelo nunca la recibió):

| Variante | Forma | Resultado |
|---|---|---|
| A | `hookSpecificOutput`, valor `user_prompt_submit` snake, en UPS | ignorada |
| B | `hookSpecificOutput`, en Stop `end_turn` | ignorada (`additional_context=false` en el log pese a emitirla) |
| C | top-level, en UPS | ignorada |
| D | top-level, en Stop `end_turn` | ignorada (`additional_context=false`) |

Dato de protocolo (handshake ACP, log de initialize): Grok declara
`blockingEvents: [pre_tool_use, stop, subagent_stop]`, `decisions: [deny,
block]`, `stopSignals: [continue, stopReason, additionalContext]` — el
bloqueo en `stop` es ciudadano de primera clase; `additionalContext` figura
como señal de Stop pero en 1.0.3 no se aplica en ninguna de las 4 formas
medidas.

El tope de una emisión por ronda del probe funcionó: ninguna ronda tuvo 3+
`end_turn`.

## Decisión de formas de salida para Grok (§D del plan)

**`TARGET=grok` con forma propia: el bloqueo emite `decision:block` (JSON,
exit 0) y NUNCA exit 2; el budget usa `continue:false`+`stopReason` (aceptada
tal cual); el armado NO puede usar `additionalContext` — 7.3 debe re-planificar
el canal de armado.** El gate NO es decorativo: el bloqueo mueve el Stop de
turno de forma fiable. Candidato de armado ya medido: el `reason` del
`decision:block` sí llega al modelo (lo citó en el turno block0).

Filas de §D aplicadas: "block0 accepted y exit2 ignored" (forma propia sin
exit 2) + "context ignored y Stop sí mueve" (re-planificar el armado) +
"extra = accepted" (esquema no estricto) + "notice = ignored" (review-notice
fail-open, no bloquea 7.3–7.6).

## Desviaciones y lecciones del protocolo

1. **§E4 del plan tenía un bug el restore "quirúrgico"**: `grep -v
   'saikit-captura-grok' trusted_folders.toml` quita sólo la línea de encabezado
   y deja huérfanos `trusted`/`decided_at`, que se adosan a la sección anterior
   (TOML con claves duplicadas). Se detectó por cksum (el plan lo exige) y se
   restauró desde el backup tras verificar por diff que no hubo cambio
   concurrente. cksum final == cksum previo a §A3. La línea del plan quedó
   corregida.
2. Las 4 variantes oráculo no estaban en §C: son la materialización del
   hallazgo 5 del cross-review del plan (validar el oráculo antes de declarar
   `ignored`), declaradas acá.
3. `grok -p` headless ≠ TUI (límite 7): los veredictos de `notice` y de las
   formas ignoradas aplican a headless; si la TUI difiere, se declara aparte.

## Limpieza (§E4, ejecutada)

Probe quitado (`--quitar --host grok`, rc 0), hooks oráculo borrados, trust
restaurado byte a byte (cksum verificado), `grok inspect` ⇒ `Project trusted:
no`. Cksums de `~/.grok/hooks/*`, `config.toml`, `agents/*` idénticos a los de
antes de la medición. La evidencia (`probe-ran/`, debug logs, salidas de turno)
queda en el repo descartable, sin commitear.
