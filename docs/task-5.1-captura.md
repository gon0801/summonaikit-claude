# Task 5.1 — Captura real de zcode: diff de forma y dueño del rol

`[Test]` `[lane:gate]`. Medido el **2026-08-12** en un turno `-saikit` real de
**zcode** (CLI `zcode-app-cli` 3.7.5-11) sobre el repo descartable
`C:/dev/saikit-captura-zcode`, con `tools/capture-payloads.sh --host zcode`
registrando 5 entradas en el user-config (`~/.zcode/cli/config.json`).

**DoD cumplida:** las 3 fases (`UserPromptSubmit`, `PostToolUse`, `Stop`)
fueron capturadas; queda el diff de forma contra Claude; se declara el nombre
de la herramienta de subagentes y el campo del rol; y se midió el alias
`Task`↔`Agent`. **Cero payloads crudos, cero prompts, cero rutas de perfil
del operador** en este documento.

## Recuentos

- Archivos: **5** — `UserPromptSubmit`×1, `PostToolUse`×3, `Stop`×1.
- `hook_event_name`: `{PostToolUse: 3, Stop: 1, UserPromptSubmit: 1}`.
- `tool_name` (PostToolUse): `{Agent: 2, Bash: 1}`.
- `tool_input.subagent_type`: `{general-purpose: 2}`.
- `agent_type` top-level: `{}` **(ausente)**.
- Los 2 eventos `Agent` son el **mismo** tool call (`tool_use_id` idéntico)
  capturado por los matchers `Task` y `Agent` a la vez.

## Diff de forma contra Claude (fixture 05 / captura 1.4)

| Campo | Claude | zcode (5.1) |
|---|---|---|
| `hook_event_name` | sí | sí **+** `hookEventName` (camel) |
| `tool_name` (PostToolUse) | sí (`Agent`/`Bash`) | sí (`Agent`/`Bash`) **+** `toolName` |
| `tool_input.subagent_type` (Agent) | sí | sí (`general-purpose`) **+** `toolInput` |
| `agent_type` top-level | en eventos internos | **NO** — el rol va en `tool_input.subagent_type` y `tool_response.agentType` |
| `transcript_path` | sí (perfil persistente) | sí pero **temporal efímero**: `C:\Users\<user>\AppData\Local\Temp\zcode-claude-hook-<rand>\transcript.jsonl` (+ `transcriptPath`) |
| `session_id` | sí | sí (+ `sessionId`) |
| `cwd` | `C:\\dev\\demo` | `C:\\dev\\saikit-captura-zcode` (mismo escape `\\`) |
| `last_assistant_message` (Stop) | sí | sí (+ `responseText` / `responsePreview`) |
| `tool_response.exitCode` (Bash) | **no** (59/59 fixtures) | **sí** (`exitCode: 0` dentro de `tool_response`) |
| `prompt` (UserPromptSubmit) | string | string (con `\n` literales) |
| env `CLAUDECODE` | `1` | **ausente** |
| env `ZCODE_SESSION_ID` / `ZCODE_PROJECT_DIR` | (n/a) | **presentes** (también `CLAUDE_SESSION_ID` / `CLAUDE_PROJECT_DIR`) |
| `permission_mode` / `mode` | `auto` | `yolo` (+ `mode` camel) |
| Extras camelCase (sin equivalente en Claude) | — | `traceId`, `turnId`, `timestamp`, `toolCallCount`, `toolResultPreview`, `responsePreview` |

**Forma anidada real:** zcode emite **cada clave en DOS convenciones** —
snake_case (la que lee el hook) y camelCase duplicada. La forma snake_case
(`hook_event_name`, `tool_name`, `tool_input`, `tool_use_id`, `tool_response`,
`session_id`, `transcript_path`, `permission_mode`, `stop_hook_active`) es
idéntica a la de Claude y está presente en los 3 eventos. Esquema de ejemplo
(redactado):

```json
{"hook_event_name":"<evento>", "tool_name":"<tool>", "tool_input":{...},
 "tool_response":{...}, "session_id":"sess_<id>", "permission_mode":"yolo",
 "transcript_path":"C:\\Users\\<user>\\...\\Temp\\zcode-claude-hook-<rand>\\transcript.jsonl",
 "cwd":"C:\\dev\\saikit-captura-zcode",
 "hookEventName":"<evento>", "toolName":"<tool>", "toolInput":{...}, ...}
```

## Las dos preguntas de la DoD

### 1. ¿Cómo se llama la herramienta de subagentes y en qué campo viaja el rol?

- **Nombre:** `Agent` (`tool_name: "Agent"`).
- **Rol:** viaja en **`tool_input.subagent_type`** = `"general-purpose"` (snake,
  igual que Claude). También aparece en `tool_response.agentType`.
- **No existe** `agent_type` a primer nivel en este evento. (El spec lo listaba
  por aparecer en el bundle; en el payload real de `PostToolUse` no está
  top-level.)

### 2. ¿El alias `Task`↔`Agent` hace llegar la delegación?

**Sí, funciona.** El matcher `Task` disparó para un `tool_name=Agent`: el
archivo `*-task.json` contiene `tool_name=Agent`. El matcher `Agent` también
disparó (`*-agent.json`, `tool_name=Agent`). Ambos capturaron **el mismo**
tool call (`tool_use_id` idéntico), idénticos salvo en `transcript_path`.

- En **Claude** esto no pasa: el matcher registrado nombra `Task` y la
  herramienta se llama `Agent` ⇒ esos eventos **no llegan nunca** (la mitad de
  A9 que falta).
- En **zcode** el alias `Task`→`Agent` cierra ese hueco: la delegación llega.

**Implicancia concreta para el harness:** el matcher PostToolUse del harness
vivo es `Bash|Edit|Write|apply_patch|Task` (incluye `Task`, **no** `Agent`).
En Claude, `Agent` no matchea ⇒ el hook no ve la delegación por PostToolUse.
En zcode, el alias hace que `Task` matchee `Agent` ⇒ **el mismo matcher, sin
tocar, atrapa la delegación**. La detección de delegación (A9) funciona en
zcode sin cambiar el matcher.

## Env del hook (A10 / detección de target)

- `CLAUDECODE`: **ausente** en zcode (en Claude vale `1`). El fallback
  `CLAUDECODE=1` que hoy usa el harness para inferir `TARGET=claude` **no
  dispara** en zcode.
- `ZCODE_SESSION_ID` y `ZCODE_PROJECT_DIR`: **presentes** (zcode también setea
  `CLAUDE_SESSION_ID` / `CLAUDE_PROJECT_DIR`). Son la señal disponible para
  distinguir zcode.
- `PWD`, `TERM`: presentes en ambos.

## Veredicto (§E3): ¿se tumbó alguna premisa?

**Ninguna.** La forma snake_case que lee el hook está presente y es compatible;
el alias `Task`↔`Agent` funciona; `hooks.enabled:true` en el user-config basta;
omisión de matcher en `UserPromptSubmit`/`Stop` confirmada (dispararon sin él).
**Phase 5 sigue como adaptación del hook existente, no como port propio.**

Hechos **nuevos** (no en las premisas) que 5.2–5.5 tienen que resolver:

1. **`CLAUDECODE` ausente** → la detección de target (A10 / gate G6) necesita
   usar `ZCODE_SESSION_ID` o `ZCODE_PROJECT_DIR`. Decisión de 5.2/5.4.
2. **`transcript_path` efímero** (temp, no perfil) → revisar la contención A6
   del harness en zcode (5.3).
3. **`tool_response.exitCode` presente** en Bash → inofensivo hoy (A11 retiró
   el uso de exitCode), pero registrado por si 5.2 lo necesita.
4. **Claves camelCase duplicadas** → inofensivas: el hook lee snake_case.
5. **`mode:"yolo"`** (no `auto`) → el permiso/bypass de zcode se nombra distinto.

## Cómo se midió / fuente

- Repo descartable: `C:/dev/saikit-captura-zcode` (NO se commitea; `capturas/`
  y `.zcode/` en su `.gitignore`).
- Registro: `tools/capture-payloads.sh --instalar <repo> --host zcode`
  (5 entradas en `~/.zcode/cli/config.json`, idempotentes, con backup en
  `~/.zcode/cli/saikit-backups/`). Limpieza: `--quitar <repo>`.
- Prompt: un turno `-saikit` que delegó a un subagente (`general-purpose`) y
  corrió `echo saikit-5.1`. El nombre de la herramienta **no** se mencionó en
  el prompt, para no contaminar la medición.
- `type: command` (no `process`): es la forma del 100% de los hooks del config
  real de zcode, y stdin llegó confirmado bajo `command`.
