# Fixtures dsh (Phase 15, Task 15.1)

Captura de un turno vivo en el **DeepSeek Harness** (`dsh`), para medir la forma de
los eventos que el adaptador `@summonaikit/dsh-gate` (15.3) traducirá al hook.

## Origen

- **dsh medido:** `@deepseek-ai/dsh@0.1.1-rc.2` (`dsh --version`).
- **Fecha:** 2026-08-27.
- **Turno (sesión padre):** `session-2e3255c6-d647-470d-ba3f-33e8ebe32228`
  (el turno sin `-saikit` usa `session-ef62c1f7-4b9f-49cf-81ba-064d68093778`, en
  `pre-step-control.jsonl`).
- **Workspace/cwd:** `C:/dev/saikit-captura/dsh-repo` (repo desechable con `app.py`).
- **Tarea del turno medido:** `-saikit agrega un docstring a app.py. Delegá la
  implementación a un subagente y la verificación a otro.`
  → el modelo delegó a **2 subagentes** (implementación y verificación, ambos
  `isError:false`); `app.py` quedó con docstring de módulo + función.
- **Modelo:** `provider=deepseek-official`, `model=deepseek-v4-flash-vision-exp`,
  `reasoningEffort=high`.
- **Disparo:** no fue por WebSocket; fue HTTP `POST /api/session.create` +
  `POST /api/session.prompt` (ver `docs/task-15.1-medicion-dsh.md` §Protocolo).

## Archivos

| Archivo | Qué contiene |
|---|---|
| `pre-step.jsonl` | `agent/pre-step` del turno medido (paso 1 con el texto del usuario; pasos ≥2 con `messages:[]`). |
| `pre-step-control.jsonl` | `agent/pre-step` del turno sin `-saikit` (mismo shape, prompt sin prefijo). |
| `tools-result-subagent.jsonl` | `tools/result` de las 2 delegaciones (name `subagent`). |
| `tools-result-fs.jsonl` | `tools/result` de tools de fs (`edit`/`read`/`glob`); `edit` primero. |
| `turn-stopping.jsonl` | `agent/turn-stopping` (3 turnos del padre + 2 de subagentes). |
| `session-events.jsonl` | `session/event` `assistant/message` (la forma del texto final del asistente). |

## Hechos clave medidos (relevantes para 15.3)

- `agent/id` **es** el `SessionId` (`agentId === sessionId`); `session/event` usa la
  misma cadena. `sessionKey()` única ambas partes.
- La delegación es `tools/result` con `name:"subagent"` y `arguments: {description,
  prompt}` — **sin** `subagent_type` ni `persona`. El rol (implementer/verifier) solo
  está en el texto de `description`/`prompt`. El adaptador 15.3 NO puede mapear
  `subagent → Task {subagent_type}` con la forma actual sin inferirlo del texto.
- `exec.parent` es siempre `None`; el discriminador padre/hijo es `exec.agent`.
- Tools de fs de edición: `edit` con `arguments.file_path` (y `old_string`/
  `new_string`); `read` con `file_path`. **No** apareció `write` ni
  `str_replace_editor`.
- El texto final del asistente vive en `session/event` `assistant/message`
  (`message.content[].text`), no en `agent/turn-stopping`.
- El JSONL de sesión (`~/.dsh/sessions/…/session.jsonl.zstd`) está **comprimido con
  zstd** (magic `28 b5 2f fd`); el walker del hook, que lee JSONL plano, no lo leería
  sin descompresión.

## Redacción

Se redactaron las rutas del home (`C:\Users\ehven` → `C:/Users/<REDACTED>`) y se
validó que ningún patrón de secreto (`token=`, `sk-…`, `://user:pass@`) quede sin
`[REDACTED]` (verificación automatizada en la extracción; la redacción del espía ya
cubre los tokens — Q8 del doc).
