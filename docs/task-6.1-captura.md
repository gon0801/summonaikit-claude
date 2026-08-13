# Task 6.1 — La captura de Codex: qué se midió

Fecha: 2026-08-13. Codex CLI 0.147.0, modelo `gpt-5.6-sol`.
Repo descartable: `C:\dev\saikit-captura-codex`. **14 payloads** de **3 turnos
reales** con el operador adelante, en dos rondas: la ronda 1 (dos turnos, 7
payloads) midió la forma; la ronda 2 (un turno con delegación explícita, 7
payloads) midió el rol del subagente.

**El perfil no se tocó**, y eso es evidencia, no una promesa: los tres cksum de
`~/.codex/` son idénticos antes y después de las dos rondas —
`hooks.json 2271698800 2717`, `summonaikit-harness.sh 2998360912 55609`,
`summonaikit-harness.ps1 2437289870 1501`.

## El veredicto que importa: **D3 se prende**

El rol del subagente **llega al gate**, en `agent_type` de PRIMER NIVEL — la
misma forma que Claude después de la Task 3.7. `hooks/summonaikit-harness.sh`
ya lo lee (`:927`), así que **no hace falta código nuevo para leerlo**.

```
hook_event_name = PostToolUse
tool_name       = Bash            <- esta EN el matcher de ~/.codex/hooks.json
agent_type      = reviewer
agent_id        = 019ffc13-8426-76f1-a05a-d4acb9f46ca6
turn_id         = 019ffc13-8504-7ee3-b1ab-303ec1043d90
```

La 6.4 puede pasar la rama de ceremonia a `case "$TARGET" in claude|codex)`.

## Las cinco preguntas de la DoD

### 1. Cómo se llama la herramienta de subagentes y en qué campo viaja el rol

La herramienta es **`spawn_agent`** (medido en los rollouts: 2 usos en la ronda
2, más `wait_agent`). **Ningún evento del hook tiene `tool_name` igual a
`spawn_agent`, `Agent` ni `Task`** — el despacho en sí no aparece.

Lo que sí llega son los eventos **de adentro** del subagente, con
`tool_name: "Bash"` y **`agent_type` + `agent_id` de primer nivel**. En la ronda
2: 5 `PostToolUse`, de los cuales **2 traen `agent_type = reviewer`**.

Es exactamente el hallazgo A9 de Claude, con el mismo desenlace: el despacho no
llega, los eventos internos sí, y el rol viaja en `agent_type`.

**No se distinguió** si `spawn_agent` no emite evento en absoluto o si el
matcher lo filtra — ver § Lo que quedó sin resolver. No cambia el veredicto:
por la vía de los eventos internos el rol llega igual.

### 2. El matcher real de `hooks.json` atrapa la delegación

Sí, por la vía que importa. El matcher registrado es
`Bash|Edit|Write|apply_patch|Task|exec|local_shell_call|shell_command|commandExecution`,
y los eventos internos del subagente llegan como **`Bash`**, que está adentro.
**No hay que tocar el registro del operador para que el rol llegue.**

**Lo que esta respuesta NO cubre, y hay que leerlo pegado a lo anterior.** La
pregunta de la DoD, literal, es si el matcher atrapa *la delegación*. La
respuesta de arriba se acota a **la vía de los eventos internos**. Sobre el
**despacho** de `spawn_agent` la captura no puede afirmar nada: se observaron
**0** eventos y no se distinguió "no emite" de "lo filtra el matcher". Queda
`unknown`. Alcanza para la ceremonia —que es lo único que esta fase necesita—
y **no** para nada que dependa del evento de despacho.

### 3. `transcript_path` cae adentro de `~/.codex/sessions/`

**Sí**, en los 7 payloads de la ronda 1 y los 7 de la ronda 2:

```
C:\Users\ehven\.codex\sessions\2026\08\13\rollout-2026-08-13T10-01-23-019ffc12-…jsonl
```

Consecuencia directa para D1: con el hook instalado en `~/.codex/hooks/`,
`PROFILE_DIR` (que sale de `dirname "$HOOK_DIR"`) es `~/.codex`, así que **la
contención de A6 funciona**. Es mejor que zcode, donde el transcript es efímero
y quedó fail-open declarado.

### 4. `SUMMONAIKIT_HOOK_TARGET=codex` está en el env del hook

**Sí**, y **`CLAUDECODE` está AUSENTE** en una sesión real de Codex:

```
SUMMONAIKIT_HOOK_PHASE=prompt
PWD=/c/dev/saikit-captura-codex
SUMMONAIKIT_HOOK_TARGET=codex
TERM=xterm-256color
```

**Evidencia adicional para D2, medida por accidente.** Una prueba de cableado
lanzada *desde Claude Code* capturó el mismo env **más `CLAUDECODE=1`**. O sea
que la colisión que D2 previene —correr Codex desde adentro de Claude vía
`codex:codex-rescue` o `cross-review.ps1`, y que el hook de Codex se crea
Claude— **es real y está reproducida**, no es una hipótesis. Confirma poner la
señal explícita primero en el orden.

### 5. Forma de los campos

**snake_case, con los mismos nombres que Claude.** No hace falta adaptar los
lectores `json_*`.

| Fase | Claves |
|---|---|
| `UserPromptSubmit` | `cwd, hook_event_name, model, permission_mode, prompt, session_id, transcript_path, turn_id` |
| `PostToolUse` | las de arriba menos `prompt`, más `tool_input, tool_name, tool_response, tool_use_id` — y `agent_id, agent_type` **sólo** en los eventos de adentro de un subagente |
| `Stop` | `cwd, hook_event_name, last_assistant_message, model, permission_mode, session_id, stop_hook_active, transcript_path, turn_id` |

Diferencias contra Claude, todas aditivas o inertes:

- **`turn_id` es nuevo** (Claude no lo trae). No se usa: la 3.4 ya llavea por
  `session_id`, y cambiar a `turn_id` rompería el estado entre turnos de una
  misma tarea, que es justo lo que el gate necesita conservar.
- **`permission_mode = default`.** En Claude se midió `auto`/`dontAsk` y
  **nunca** `default` (Task 1.4). El hook no ramifica por ese campo; se anota
  para que nadie lo tome como invariante.
- `Stop` trae `last_assistant_message` y `stop_hook_active`, igual que Claude:
  el recibo tiene **dos canales** (payload y transcript) también acá.
- No hay duplicación camelCase, a diferencia de zcode (Task 5.1).

## Por qué el sentinel no armó nada durante la captura

El operador lo notó y es correcto que no armara: **es estructural, no un
defecto**. El wrapper `~/.codex/hooks/summonaikit-harness.ps1` corre **UN solo
hook por turno** y prefiere `<repo>/.codex/hooks/summonaikit-harness.sh` cuando
el cwd resuelve a un repo git. El shim de captura vive en esa ruta, así que
**reemplaza al harness real**: guarda el payload y sale 0, sin inyectar contrato
ni gatear.

Es la misma propiedad que `tools/stage-override.sh` documenta para Claude
("corre UN hook, no dos"). Consecuencia práctica para cualquier captura futura:
**el modelo no recibe el contrato, así que no delega por su cuenta** — la
delegación hay que pedirla explícitamente en el prompt.

Se declara acá porque no estaba escrito en el plan de la 6.1 y costó dos rondas
descubrirlo.

## Lo que quedó sin resolver, declarado

**Si `spawn_agent` emite `PostToolUse` y el matcher lo filtra, o si no emite
nada.** Se intentó distinguirlo registrando un `<repo>/.codex/hooks.json` de
proyecto con `PostToolUse` **sin matcher**: capturó **cero** eventos, o sea que
Codex no lo ejecutó.

La causa medida es que `config.toml` lleva un bloque `hooks.state` con un
**`trusted_hash` por entrada de hook** — incluidas las de proyecto
(`…\goncloud-MCP-2\.codex\hooks.json:stop:0:0`). Un `hooks.json` nuevo no está
en esa lista, así que no corre. No se persiguió: **no cambia ningún veredicto de
esta tarea**, porque el rol llega igual por los eventos internos.

Queda anotado por si la 6.5 necesitara alguna vez registrar algo a nivel
proyecto: hay una capa de confianza por hash que hay que atravesar.

**Otro hueco que sigue, heredado de Claude:** un subagente de sólo lectura que
no ejecute ninguna herramienta cubierta por el matcher no genera eventos, y su
rol no se registra. El gate sigue siendo **advisory**.

## Consecuencias para las tareas que siguen

| Tarea | Qué cambia con esto |
|---|---|
| 6.4 | **D3 se prende**: `case "$TARGET" in claude\|codex)`. D2 se confirma con evidencia medida, no supuesta |
| 6.5 | El matcher ya cubre la vía por la que llega el rol, así que **para la ceremonia** no hay que tocar `~/.codex/hooks.json`. **No** tomar eso como "el registro está completo": el evento de despacho de `spawn_agent` sigue `unknown` |
| 6.6 | Los escenarios 26+ se construyen desde estos 11 payloads. `agent_type` es el campo que tiene que aparecer en el escenario de ceremonia |

## Los payloads

14 en total, en `C:\dev\saikit-captura-codex\capturas\`:

| | `UserPromptSubmit` | `PostToolUse` | `Stop` |
|---|---|---|---|
| ronda 1 (2 turnos) | 2 | 3 | 2 |
| ronda 2 (1 turno, con delegación) | 1 | **5** — 2 de ellos con `agent_type` | 1 |

**No se commitean**: traen el texto del turno y rutas del perfil. La ronda 1
quedó archivada en `capturas/ronda-1/`. Al cerrar se quitó el shim
(`--quitar --host codex`) y el `hooks.json` de proyecto del experimento.
