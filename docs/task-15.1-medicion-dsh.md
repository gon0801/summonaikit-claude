# Task 15.1 — Medición: qué trae dsh de verdad

Fecha: 2026-08-27. dsh medido: `@deepseek-ai/dsh@0.1.1-rc.2` (`dsh --version` → `0.1.1-rc.2`).

**Método.** Turno vivo disparado al server web del profile de medición
(`~/.dsh/profiles/saikit-medicion`, con el espía `summonaikit-spy`) en
`http://127.0.0.1:3081`, contra el repo desechable `C:/dev/saikit-captura/dsh-repo`
(`app.py`). Tarea EXACTA enviada:

```
-saikit agrega un docstring a app.py. Delegá la implementación a un subagente y la verificación a otro.
```

Disparo vía HTTP `POST /api/session.create` (`{cwd}`) + `POST /api/session.prompt`
(`mode:queue`, un bloque texto) — ver §Protocolo. Sesión padre:
`session-2e3255c6-d647-470d-ba3f-33e8ebe32228`. Modelo: `provider=deepseek-official`,
`model=deepseek-v4-flash-vision-exp`, `reasoningEffort=high`. El turno terminó con
`turn/end reason:completed`; el modelo delegó a **2 subagentes** (implementación y
verificación, ambos `isError:false`); `app.py` quedó con docstring de módulo + función.

Captura: `C:/dev/saikit-captura/dsh/captura.jsonl` — el turno principal `-saikit`
aporta **5456** líneas; el control sin `-saikit` agregó 377 → **5833** total (una
línea por evento). Los conteos de abajo son del turno principal (`-saikit`).

**Conteo por `event`:**

| `event` | count |
|---|---|
| `session/event` | 5371 |
| `agent/created` | 3 |
| `agent/session-start` | 3 |
| `agent/pre-step` | 20 |
| `agent/pre-step:decision` | 20 |
| `tools/pre-execute` | 17 |
| `tools/result` | 17 |
| `agent/turn-stopping` | 5 |

`tools/result` por `name`: `subagent` 2 · `read` 5 · `todo_write` 4 · `pwsh` 3 ·
`glob` 1 · `edit` 1 · `report` 1.

---

## Preguntas

### Q1 — `agent/pre-step`: ¿dónde viene el texto del usuario? ¿`step===1`?

**Observado:**
- `messages[]` trae el texto del usuario. En el primer `pre-step` del padre
  (`step 1`): `messages[0]` = `{role:"user", source:{kind:"user", rpcId}, id, content:[...]}`.
- El texto está en `content[].text`: `content:[{type:"text", text:"-saikit agrega un docstring a app.py. Delegá la implementación a un subagente y la verificación a otro."}]`.
- `step===1` aparece en el primer paso de **cada** turno (padre y subagentes), pero
  **no** identifica por sí solo el prompt humano: los subagentes también arrancan en
  `step:1` con su propio prompt (el de `description`/`prompt`), y dsh inyecta como
  `role:user` los reportes "Background subagent `<id>` …" en pasos variados
  (p. ej. hay un `pre-step` de `step:3` con `nmsg:1`).
- El prompt humano original está en el primer `pre-step` cuyo `messages[0].source.kind === "user"`
  y cuyo texto no es un reporte de subagente (`L1` → `-saikit agrega un docstring…`).
  Pasos posteriores **pueden** traer mensajes inyectados (`nmsg>0`); no siempre `[]`.

**Ausente:** no hay más campo que `content[].text` para el texto — siempre ese bloque.

**Nota/Ausente:** el espía volcó `{step, messages}` y **no** incluyó `payload.agent`
en `pre-step`. El payload real del plugin sí trae `payload.agent` (el adaptador 15.3
lo usa vía `sessionKey(payload.agent)`); para atribuir cada `pre-step` a su agente
hay que correlacionar con el id de `agent/turn-stopping`/`tools/result` más cercano.

### Q2 — `tools/result` de la delegación: ¿`subagent`, dónde la persona, `parent`?

**Observado:**
- `exec.name === "subagent"` para las 2 delegaciones.
- `exec.arguments = { description, prompt }` (**sin** campo `persona`,
  `subagent_type` ni `role`). El rol (implementer vs verifier) solo está en el
  **texto**: `description:"Add docstring to app.py"` / `"Verify docstring in app.py"`,
  y en el prompt (`"You are implementing…"` / `"You are verifying…"`).
- `exec.parent` está **ausente/undefined** en las 17 capturas de `tools/result` (no
  vale `null`). El tipo `ToolExecutionToken` de dsh lo sugiere como un token opaco no
  serializable — **inferencia por el fuente, a confirmar en 15.3**. El discriminador
  entre padre e hijo es `exec.agent` (el id del agente que llama): para las `subagent`
  del padre `agent=session-2e3255c6…`; para las tools de un subagente
  `agent=<id hijo>` (ejs. `107f7943-…`, `de2f699a-…`).

**Implicación (diseño D4/D2):** la persona **no** es un campo estructurado
recuperable de los eventos. El `toPostToolUse` del plan 15.3 (que mapea `subagent`→
`Task` con `subagent_type` desde `arguments.persona`/`subagent_type` y valida
`ROLES`) devolvería `undefined` en dsh (no hay `subagent_type`) → el gate **no
registraría** el subagente. **Ajuste necesario en 15.3**: inferir el rol del texto
`description`/`prompt`, o usar otra señal de la creación del hijo.

### Q3 — tools de fs: nombres y campo de ruta

**Observado (nombres reales):**
- `read` → `arguments.file_path` (string).
- `edit` → `arguments.file_path`, `old_string`, `new_string`.
- `glob` → `arguments.pattern`.
- `todo_write` → `arguments.todos`.
- `pwsh` (shell; no bash) → `arguments.command`, `description`, `workdir`.
- `report` → `arguments.output`.

**Fixtures:** los 17 `tools/result` están cubiertos por `tools-result-subagent.jsonl`,
`tools-result-fs.jsonl` (`edit`/`read`/`glob`) y `tools-result-other.jsonl`
(`todo_write`/`pwsh`/`report`).

**Ausente:** `write` y `str_replace_editor` **no** aparecieron en este turno. La
tool de edición es `edit` con `file_path`.

**Ajuste del map del adaptador (15.3):** donde el diseño tenía
`FS_TOOLS = {write:"Write", str_replace_editor:"Edit", edit:"Edit"}`, en dsh la
observada es `edit`→`Edit` (`file_path`) y `write` no se usó.

### Q4 — `agent/turn-stopping` y dónde vive el texto final

**Observado:**
- `agent/turn-stopping` dispara **una vez por turno**: 5 eventos = 3 del padre
  (`turn:1,2,3`) + 1 por cada subagente (`turn:1`).
- `agent/turn-stopping` **no** trae el texto del asistente. El texto final vive en
  los `session/event` con `type:"assistant/message"` (20 en total). La forma real
  (medida en `session-events.jsonl`): está en `payload.event.data.message`, **no** en
  `payload.event.message` (campo directo ausente). `event.data.message` =
  `{role, content:[{type:"reasoning"|"text"|"tool-call"}], source, id}` y el texto en
  `event.data.message.content[].text`.
- También hay `assistant/chunk` (streaming), más numeroso.

**Implicación (15.3):** el adaptador toma `lastAssistantText` desde
`session/event`→`assistant/message`, leyendo `event.data.message.content[].text` del
último por sesión. **El `textOf` del plan 15.3 (`event?.message?.content`) NO funciona
en dsh**: hay que leer `event?.data?.message?.content`. Sin el gate instalado no hay
recibo `SUMMONAIKIT` (esperado): el texto final del turno es el resumen del agente.

### Q5 — ¿`agent.id` == `SessionId`? ¿`session.id` igual? ¿de dónde el `cwd`?

**Observado:**
- `agent.id` **es** el `SessionId`. En `agent/created` y `agent/session-start`, el
  agente padre lleva `agentId === sessionId === "session-2e3255c6-d647-470d-ba3f-33e8ebe32228"`.
- En `session/event`, el campo `session` **es la misma cadena** que el `agent.id`
  del `agent/turn-stopping` del mismo agente (padre: `session-2e3255c6…`; cada
  subagente: su propio id, `107f7943-…` / `de2f699a-…`). → `sessionKey()` única
  funciona (no hace falta doble clave).

**Unknown / a verificar:** `agent/created meta.cwd` **no** se observó en el JSONL:
el espía redujo el objeto `agent` a `{agentId, sessionId, status}` y **descartó
`meta`**. El cwd sí se fija a nivel de sesión (`session.create {cwd:"C:/dev/saikit-captura/dsh-repo"}`)
y aparece en `tools/result pwsh.arguments.workdir` y en el prompt del subagente.
El adaptador 15.3 asume `agent/created meta.cwd`; conviene verificarlo en vivo en
15.3 o usar el fallback `process.cwd()` existente.

### Q6 — JSONL de sesión: ¿`role:assistant` + `content[].type:text`?

**Observado:**
- El archivo de sesión en `~/.dsh/sessions/<key>/session.jsonl.zstd` está
  **comprimido con zstd** (magic `28 b5 2f fd`), no es JSONL plano.
- La forma interna coincide con lo que vemos en los `session/event`
  `assistant/message` (`message.content[].type:"text"` en bloques), pero eso es la
  proyección en vivo, no el archivo.

**Implicación (diseño §3, `transcript_path`):** el walker del hook lee **JSONL
plano**; con el archivo comprimido en zstd no lo leería sin descompresión. Por el
fail-open existente del gate, **`transcript_path` debe omitirse** (el gate juzga
solo `last_assistant_message`).

### Q7 — ¿Se inyecta `~/.dsh/AGENTS.md`?

**Observado: SÍ.** Con el marker `SPY-MARK-AGENTS-fd0b401a` en `~/.dsh/AGENTS.md`,
aparece **6 veces** en la captura, dentro de un `<system-reminder>` en un
`session/event type:user/message` (y reflejado en `agent/pre-step:decision`). →
`dsh-agent-instructions` inyecta `~/.dsh/AGENTS.md` como `<system-reminder>` en el
primer paso.

### Q8 — Redacción: ¿se escapó algún secreto?

**Observado: limpio.** Chequeo preciso sobre toda la captura:
- `token\s*=` → 0
- `\bsk-[A-Za-z0-9]{8,}` → 0
- `://user:pass@` → 0

Ningún hit sin `[REDACTED]`. Los hits crudos de un chequeo grosero eran falsos
positivos (`task-` contiene `sk-`; `://` en URLs normales de `request/header`).
También se verificó `redact()` unitario: `token=x`, `api_key=sk-…`, `https://u:p@h`
→ `[REDACTED]`.

**Cobertura del redactor (medida):** el espía redacta (a) patrones de valor (`token=`,
`sk-…`, `://user:pass@`), (b) **claves** sensibles a nivel de objeto (`SENSITIVE_KEY`:
`token`, `password`, `authorization`, `bearer`, `api_key`, `secret`, `cookie`,
`set-cookie`, `x-api-key`, …), y (c) la forma JSON-en-string (`"api_key": "x"`), sin
sobre-redactar (`token_count`/`model` no se tocan). En esta captura no hubo secretos
que escapar, pero la cobertura es estas 3 capas. **El espía redacta antes de escribir.**

---

## Protocolo de disparo (corrige la hipótesis del diseño)

El envío del mensaje **NO** es por WebSocket. Flujo medido:
- **Upstream (cliente→server):** HTTP `POST /api/<method>`, body
  `{type:"client-request", rpcId, method, payload}`,
  `content-type:application/json` obligatorio (415 si falta). Usados:
  `session.create {cwd}`, `session.prompt {sessionId, mode:"queue", content:[{type:"text",text}]}`,
  `session.models {sessionId}` (advisory, `.routable`).
- **Downstream (server→cliente):** WebSocket **downlink-only** (el server cierra el
  socket `close(1008,"downlink only")` si el cliente manda frames). Dos streams:
  `WS /api/events.mux` (frames `session/event`, `session/subscribed`, `session/queue`,
  `session/projection`) y `WS /api/events.host` (`host/session-added`,
  `host/session-status`, `host/agent-error`).
- **Auth/trust:** el fence `isTrustedApiRequest` **no** exige cookie ni
  `.anonymous-user-id`. Pasa con `Host` loopback (`127.0.0.1`/`localhost`/`[::1]`) y
  **omitiendo** `origin` y `sec-fetch-site`. Verificado: POST sin origin → 200;
  `sec-fetch-site:cross-site` → 403; origin `http://evil.example` → 403.

**Vocabularios:** el espía (cordis) usa `agent/pre-step`, `tools/result`,
`agent/turn-stopping`; el mux de sesión usa `step/start`, `tool/result`, `turn/end`.
El dato válido para el gate es el del espía (el adaptador consume ese).

## Control: turno SIN `-saikit`

Segundo turno (sesión `session-ef62c1f7-4b9f-49cf-81ba-064d68093778`, cwd
`C:/dev/saikit-captura/dsh-repo`), tarea `Describí qué hace el módulo app.py.`
(sin prefijo `-saikit`), ~6 s, read-only.

- `pre-step` step=1 trae el mismo shape que con `-saikit`:
  `messages[0].content[].text = "Describí qué hace el módulo app.py."` (sin
  `-saikit`); step≥2 con `messages:[]`.
- Tools usadas: `glob`, `read` (ambas con `arguments` igual que en Q3); **sin**
  `subagent` (esperado, tarea simple).
- `agent/turn-stopping` una vez (`turn:1`).
- Conteo de eventos propios: `session/event` 364 · `agent/created` 1 ·
  `agent/session-start` 1 · `tools/pre-execute` 2 · `tools/result` 2 ·
  `agent/turn-stopping` 1.

Conclusión del control: el espía captura el prompt crudo del usuario en `pre-step`
y las tools reales **con o sin** `-saikit`; el prefijo solo modifica el contenido
del texto, no el shape de los eventos. (Sin el gate instalado no hay diferencia de
comportamiento observable entre ambos en los eventos del espía.)

---

## Fixtures

Referencia validada en `tests/fixtures/dsh/README.md` (Paso 5) — evento por archivo,
extraídos de la sesión `session-2e3255c6-d647-470d-ba3f-33e8ebe32228`
(`pre-step.jsonl`, `tools-result-subagent.jsonl`, `tools-result-fs.jsonl`,
`turn-stopping.jsonl`, `session-events.jsonl`, `agent-created.jsonl`,
`agent-session-start.jsonl`), más `pre-step-control.jsonl` del turno sin `-saikit`.
Q5 (ids) queda respaldado por `agent-created.jsonl`/`agent-session-start.jsonl`;
**Q6** (magic zstd `28 b5 2f fd`) y **Q7** (marker `SPY-MARK-AGENTS-fd0b401a` en
`session/event type:user/message`) son observaciones de la captura/archivo de
sesión local y se citan con exactitud, pero no se representan como fixtures de
evento (son propiedades de archivo / del control `~/.dsh/AGENTS.md`).
