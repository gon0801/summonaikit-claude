# 21.1 — Canal nativo de delegación en Codex (spike)

Fila `[Recommended]` `[lane:release]` `[tdd:skip:medición]` `[needs-spike]`.
Pregunta: ¿qué emiten `collaboration.spawn_agent` y la finalización del
agente para los roles del recetario, y hay señal estable para acreditar rol?

## Identidad de ESTA evidencia

| Campo | Valor |
|---|---|
| Fecha | 2026-09-13 |
| CLI observado | `codex-cli 0.154.0` (`codex exec --dangerously-bypass-hook-trust -s read-only --json`) |
| Lab | repo sintético aislado con `alfa.txt` (`hola lab`) y `beta.txt` (`segundo archivo`); CODEX_HOME temporal con auth copiada, `multi_agent=true`, roles implementer/reviewer, hook shim grabador puro |
| Prompt | "Spawnea DOS subagentes EN PARALELO: implementer lee alfa.txt, reviewer lee beta.txt; resume en una línea cada uno" (sin modificar archivos) |
| Resultado funcional | EXIT=0; el resumen final citó ambos contenidos exactos |
| Captura | 10 payloads PostToolUse/Stop/SessionStart/UserPromptSubmit en `fixture-00…09` (redactados: blob `message` opaco → `[REDACTED:…]`, rutas del lab → `[LAB]`, valores >300c truncados con marca) |
| Incidente | el nodo cayó a mitad del spike con 10 payloads ya en disco; al volver, el proceso había terminado solo (EXIT=0) y el conteo final siguió en 10: la secuencia está completa (despacho×2, internos×3, wait×2, Stop×1, más SessionStart y UserPromptSubmit). Nada se re-corrió ni se inventó |

Claves de correlación observadas (IDs de sesión de laboratorio, descartable):

| Símbolo | Valor | Alcance |
|---|---|---|
| S (session_id = thread_id) | `01a09b09-15c5-79d1-aefa-413b8e98621a` | TODOS los payloads |
| T0 (turno padre) | `01a09b09-1630-7152-a842-e7ccb61a3249` | despachos, waits, Stop |
| A1 (implementer) | agent_id `01a09b09-32af-7042-8163-ab4cfcfa85e5`, turno `…-32cd-…` | 2 internos Bash |
| A2 (reviewer) | agent_id `01a09b09-4084-72f3-bc5d-6050fa672a00`, turno `…-40a2-…` | 1 interno Bash |

## Matriz campo → significado

`solicitado` = despacho del spawn · `running` = internos del subagente ·
`completed/failed` = finalización (wait/Stop)

| Campo | Dónde aparece | Significado para el gate |
|---|---|---|
| `tool_name=collaborationspawn_agent` (sin punto) | despacho solicitado | SÍ distingue el acto de delegar |
| `tool_input.agent_type` (`implementer`/`reviewer`) | despacho + internos | rol DECLARADO en el despacho; en internos coincide con quien ejecuta |
| `tool_input.task_name` (`leer_alfa`/`leer_beta`) | SOLO despacho | nombre de tarea, no identidad; la respuesta lo devuelve como ruta (`/root/leer_alfa`) |
| `tool_use_id` (`call_…`) | despacho | id del acto de despacho; NO reaparece en ningún interno |
| `agent_id` (primer nivel) | SOLO internos | existe, estable por agente (A1×2, A2×1) — pero el despacho NO lo trae |
| `turn_id` propio (T1/T2) | SOLO internos | distingue agentes entre sí, pero nada lo liga al despacho |
| `tool_name=collaborationwait_agent` + `timeout_ms` | finalización | SÍ marca espera; pero SIN `agent_id`, SIN `agent_type`, SIN estado: `response={"message":"Wait completed.","timed_out":false}` no dice QUÉ agente ni si completó o falló; con 2 agentes concurrentes hay 2 waits indistinguibles |
| `Stop` | cierre | SIN identidad: no dice quién terminó ni con qué estado |
| `session_id` | todos | estable (S), pero es la sesión PADRE: no discrimina agentes |

## Veredicto: LIMITACIÓN demostrada (no hay señal autoritativa) — **SUPERSEDED** por la RE-CORRIDA 2026-09-13 (ver "Veredicto revisado"); se preserva como hecho histórico

Tres huecos, cada uno suficiente para negar la señal:

1. **Despacho ↔ interno sin clave estable.** El despacho no trae `agent_id`
   y los internos no traen `task_name` ni el `tool_use_id` del despacho. La
   única correlación posible es `agent_type` + orden temporal — ambigua en
   cuanto dos agentes concurrentes comparten tipo (el caso del recetario:
   N implementers en paralelo serían indistinguibles).
2. **Finalización sin identidad ni estado.** Los `wait` y el `Stop` no
   identifican agente y no distinguen `completed/failed` (solo
   `timed_out:false`). Un gate no puede saber qué terminó ni cómo.
3. **`task_name`/prosa no acreditan rol** (lo que la fila ya prohibía usar:
   la respuesta del despacho es una ruta de tarea, no una identidad).

Por tanto **21.2 NO se activa**: no hay evento nativo al cual adaptar el
gate. `VERIFIED BY SUBAGENT` conserva su contrato zcode, sin ampliarse.

## Qué quedó `unknown` (con razón)

- `unknown`: si versiones futuras del CLI agregan `agent_id` al despacho o
  identidad/estado al wait/Stop (observado solo en 0.154.0).
- `unknown`: el contenido del blob `message` opaco (redactado sin abrir;
  irrelevante para el gate: es el prompt delegado, no una credencial de rol).
- No se tocó el perfil real del operador (solo LEÍDO) ni los hooks
  desplegados; los procesos `codex` viejos de la Mac (probe ajeno de 10 días)
  no se usaron ni se mataron.

---

# RE-CORRIDA 2026-09-13 (hallazgo del reviewer: hooks `SubagentStart`/`SubagentStop` no cubiertos)

El reviewer rechazó el veredicto anterior: el spike solo capturó 4 eventos y
no configuró `SubagentStart`/`SubagentStop`, que EXISTEN en codex-cli 0.154.0
(verificado en el binario instalado:
`SubagentStartHookSpecificOutputWire`, campos `session_id turn_id agent_type
transcript_path hook_event_name model permission_mode` para el Start y
`agent_transcript_path last_assistant_message` para el Stop; claves de config
`subagent_start`/`subagent_stop`). La re-corrida usa la misma metodología con
el shim ampliado (matcher `.*` en los seis eventos).

## Corrida A — 2 agentes concurrentes (implementer + reviewer), EXIT=0

Lab nuevo `/tmp/sx21b` (CODEX_HOME temporal con auth copiada,
`multi_agent=true`, roles implementer/reviewer, shim grabador puro en los 6
eventos). Mismo prompt que la corrida original. Resultado funcional: EXIT=0,
el resumen final citó ambos contenidos exactos. 15 payloads en
`fixture-10…24` (redactados igual: blob `message` opaco → `[REDACTED:…]`,
rutas del lab → `[LAB]`, valores >300c truncados con marca).

Claves de correlación (IDs de laboratorio, descartables):

| Símbolo | Valor | Alcance |
|---|---|---|
| S (session_id) | `01a09be2-d0f9-7542-ad5b-e3ddbbb68133` | TODOS los payloads |
| T0 (turno padre) | `…-d123-…` | despachos, waits, Stop |
| A1 (implementer) | agent_id `…-e0ed-…`, turno `…-e0f2-…` | Start 13, internos 16+18, Stop 19 |
| A2 (reviewer) | agent_id `…-e9c9-…`, turno `…-a911-…` | Start 15, internos 17+21, Stop 22 |

**Hecho 1 — `SubagentStart` SÍ dispara para subagentes de
`collaboration.spawn_agent`.** Un evento por agente (fixture-13 A1,
fixture-15 A2), con `agent_id` + `agent_type` declarados por el sistema,
`turn_id` propio del agente y `transcript_path` = transcript del agente
(verificable: el `agent_transcript_path` del Stop apunta al mismo archivo).

**Hecho 2 — cadena de identidad completa Start→interno→Stop por `agent_id`.**
El `agent_id` del Start coincide con el de los internos (`…-e0ed-…` en 13/16/18;
`…-e9c9-…` en 15/17/21) y con el del Stop (19/22). El `turn_id` del Stop
coincide con el del Start de su agente. Esto cierra los huecos 1 (correlación)
y 2 (identidad de finalización) del veredicto anterior **a partir del Start**:
el gate puede seguir a cada agente individualmente por `agent_id`, con rol
declarado por el sistema (`agent_type` del Start, no prosa) y cierre
identificado por agente (`SubagentStop` con `agent_id` + `agent_type` +
`agent_transcript_path` + `last_assistant_message`).

**Residual R1 — despacho↔Start sin clave compartida.** El despacho trae
`agent_type` + `task_name` (`leer_alfa`/`leer_beta`) + `tool_use_id`
(`call_…`); el Start no devuelve ninguno de los tres. Con tipos distintos el
orden temporal liga (despacho implementer → primer Start implementer), pero
con N agentes concurrentes del MISMO tipo el despacho sigue sin poder ligarse
a un `agent_id`. El gate no necesita esa liga para acreditar rol+cierre
(la cadena Start→Stop es autosuficiente), pero no puede atribuir `task_name`
a un agente.

## Corrida B — sonda de fallo (1 implementer, archivo inexistente), EXIT=0

Prompt: "implementer lee `archivo_inexistente.txt`; si no existe, que lo
informe como fallo". El agente completó informando el fallo en prosa. 8
payloads en `fixture-25-FALLO…32-FALLO`.

**Hecho 3 — `SubagentStop` NO distingue completed/failed a nivel máquina.**
El Stop del agente en fallo (fixture-30-FALLO) tiene EXACTAMENTE la misma
forma que el de éxito: mismos campos, `stop_hook_active:false`, sin campo de
estado. La única diferencia es la prosa de `last_assistant_message`
("FALLO: … no existe"). Cita (fixture-30-FALLO-SubagentStop.json):

```json
"hook_event_name": "SubagentStop",
"stop_hook_active": false,
"agent_id": "01a09be1-741f-7490-93b4-cfbcc42a3780",
"agent_type": "implementer",
"last_assistant_message": "FALLO: `archivo_inexistente.txt` no existe en `[LAB]/lab`."
```

**Residual R2 — éxito vs. fallo solo vía prosa/transcript, que no acredita.**
Un gate no puede emitir veredictos de éxito desde el Stop; como máximo
acredita rol + cierre + ruta de transcript auditable (`agent_transcript_path`).

## Qué quedó unknown (re-corrida)

- **R3 — fallo duro no observado.** Ninguna corrida produjo un abort,
  timeout o kill del subagente: ese camino no se capturó y se desconoce
  si emite `SubagentStop` (o algún otro evento). Postura del gate ante lo
  unknown: **sin `SubagentStop` = running = no acreditado** — hasta no
  observar lo contrario, un agente sin Stop se trata como en ejecución,
  nunca como cerrado ni acreditado.
- **Origen de `SubagentStart` sin negativo.** No se probó un escenario
  que NO deba disparar `SubagentStart` (p. ej. una invocación que no sea
  subagente de `collaboration.spawn_agent`): se desconoce si el evento
  puede originarse fuera del despacho delegado.

## Matriz actualizada (solo filas nuevas/cambiadas)

| Campo | Dónde aparece | Significado para el gate |
|---|---|---|
| `agent_id` (primer nivel) | SubagentStart + internos + SubagentStop, estable por agente | SÍ: clave de correlación Start→interno→Stop (A1×Start+2 internos+Stop, A2×Start+2 internos+Stop) |
| `agent_type` | SubagentStart (declarado por el sistema) + internos | rol del agente sin prosa; distingue tipos concurrentes |
| `turn_id` propio | SubagentStart = SubagentStop del mismo agente | liga cierre↔apertura por agente |
| `transcript_path` del Start = `agent_transcript_path` del Stop | Start/Stop | ruta auditable del transcript del agente |
| `last_assistant_message` (Stop) | SubagentStop | mensaje final en prosa; NO distingue éxito/fallo a nivel máquina (Hecho 3) |
| `stop_hook_active:false` | SubagentStop + Stop | sin hook de continuación activo; no es señal de éxito |
| `tool_use_id`/`task_name` del despacho | SOLO despacho | siguen sin reaparecer en Start/internos (R1) |

## Veredicto revisado: SEÑAL CONFIRMADA (señal confirmada con residuales R1/R2/R3)

El hallazgo del reviewer era real y la señal autoritativa EXISTE para
**identidad + rol + cierre por agente** (Hechos 1–2): `agent_id` estable en la
cadena Start→interno→Stop, `agent_type` declarado por el sistema en el Start,
`SubagentStop` identificado por agente con transcript auditable. Los huecos 1
y 2 del veredicto anterior se cierran en ese alcance.

Quedan los residuales R1 (despacho↔agente sin clave; mismo tipo concurrente
ambiguo a nivel despacho) y R2 (sin estado completed/failed máquina en el
Stop). **21.2 se ACTIVA con ese alcance recortado**: el gate puede acreditar
rol + cierre + transcript por agente (positivos con estos payloads); NO puede
atribuir `task_name` ni emitir veredictos de éxito desde el Stop — la
implementación futura debe tratar el éxito como no acreditable por hook y el
fallo solo vía transcript auditable, con negativos que lo demuestren. Sin
implementación y sin PASS en esta re-corrida: solo cambia el estado de 21.2 a
activada. `VERIFIED BY SUBAGENT` conserva su contrato zcode, sin ampliarse.

Higiene re-corrida: labs `/tmp/sx21b` borrados al final (llevaban auth
copiada); perfil real del operador solo LEÍDO (jamás escrito); fixtures sin
secretos (grep `gAAAAAB`/`sk-`/token limpio; blob opaco redactado); nada en
`hooks/` desplegados; sin merge.
