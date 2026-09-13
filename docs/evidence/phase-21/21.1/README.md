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

## Veredicto: LIMITACIÓN demostrada (no hay señal autoritativa)

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
