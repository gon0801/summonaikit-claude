# Task 7.1 — La captura de Grok: qué se midió

Fecha: 2026-08-13. Grok Build TUI **1.0.3** (`grok 1.0.3 (1a29d5bc12) [stable]`,
modelo `grok-4.6`).
Repo descartable: `C:\dev\saikit-captura-grok`. **37 payloads** de **5 turnos
reales** headless (`grok -p`, `--always-approve`), más 4 invocaciones de
diagnóstico (trust y forma del comando, abajo). Rondas:

| Ronda | Turno | Payloads | Qué midió |
|---|---|---|---|
| 1 | simple, sin tools | 3 | `UserPromptSubmit`, `Stop` de turno, `Stop` de cierre |
| 2 | `echo` + crear `nota.txt` + `exit 1` | 11 | `PostToolUse` exitoso, forma de `toolInput`, `exit 1` |
| 3 | `search_replace` sobre archivo inexistente | 6 | error `FileNotFound` |
| 4 | `search_replace` sin match | 6 | error `NoMatchesFound` |
| 5 | delegación explícita `spawn_subagent` | 11 | despacho, `SubagentStart`, rol |

**El perfil quedó byte a byte intacto** — los cuatro cksum de antes y después
son idénticos (`perfil-cksums-antes.txt` en el descartable):

```
158636524 6059  config.toml
716294082 491   trusted_folders.toml   (se toco y se restauro byte a byte; ver § Trust)
3615174159 894  hooks/imported-from-claude.json.disabled
353659411 373   agents/verifier.md
```

## El veredicto que importa: **D3 se prende entero**

El rol del subagente **llega al gate por TRES canales** y el `env` map del JSON
**sí entrega** `SUMMONAIKIT_HOOK_TARGET=grok` al proceso del hook. Están las dos
condiciones de la rama fuerte de D3: `case "$TARGET" in claude|codex|grok)`.

Los tres canales del rol (todos medidos en la ronda 5, `subagent_type=implementer`):

1. **`SubagentStart`** — `subagentType: "implementer"` de primer nivel, más
   `subagentId` y `description`. Es el canal limpio que el diseño prefería.
2. **El despacho `spawn_subagent` SÍ emite `PostToolUse`** (a diferencia de
   Codex, donde quedó `unknown`): llega con `toolInput.subagent_type:
   "implementer"` y matchea el alias `Task`.
3. **Los eventos internos del subagente** (`run_terminal_command` adentro del
   hijo) traen **`subagentType` de primer nivel** — la forma `agent_type` de
   Codex/Claude, en camel.

Y el env de TODOS los hooks (12 archivos `.env` de la ronda 1 a la 5):

```
GROK_HOOK_EVENT=stop                      (o user_prompt_submit, post_tool_use, subagent_start)
GROK_SESSION_ID=019ffd4a-…
GROK_WORKSPACE_ROOT=C:/dev/saikit-captura-grok/
CLAUDE_PROJECT_DIR=C:/dev/saikit-captura-grok/
SUMMONAIKIT_HOOK_TARGET=grok              <- el env map del handler LLEGA
TERM=dumb
```

`CLAUDECODE` está **AUSENTE** (está en la allowlist del dump: si Grok la
seteara, aparecería). D2 queda confirmada con evidencia: `GROK_HOOK_EVENT`
existe, es por-evento, y no hay colisión con Claude.

## Las 11 preguntas del diseño (§7.1), una por una

### 1. Literales de `hookEventName` → D4

**snake_case como VALOR, camelCase como CLAVE.** Medido en los 37 payloads:
`user_prompt_submit`, `post_tool_use`, `subagent_start`, `stop`. Las claves del
envelope son camel (`sessionId`, `cwd`, `workspaceRoot`, `timestamp`,
`permissionMode`, `toolName`, `toolInput`, `transcriptPath`). D4 necesita los
literales snake (ya previstos) y los lectores camel (previstos). Nada cayó.

### 2. Herramienta de subagentes y campo del rol → D3

`spawn_subagent` (toolName literal). El rol viaja en `toolInput.subagent_type`
(en el despacho) y en `subagentType` de primer nivel (en `SubagentStart` y en
los eventos internos del hijo). Tres canales, todos con el valor `implementer`.

### 3. El matcher alias-expande de verdad → A9

**Sí, medido con las 3 variantes registradas a la vez** (lección 6.1 aplicada:
`ptu-alias` = `Bash|Edit|Write|Task`, `ptu-native` =
`run_terminal_command|search_replace|spawn_subagent`, `ptu-all` = sin matcher):

| toolName real | ptu-alias | ptu-native | ptu-all |
|---|---|---|---|
| `run_terminal_command` | **sí** (`Bash`) | sí | sí |
| `write` | **sí** (`Write`) | **no** | sí |
| `search_replace` | **sí** (`Edit`/`Write`) | sí | sí |
| `spawn_subagent` | **sí** (`Task`) | sí | sí |

Dos precisiones medidas que el diseño no tenía:

- La tool de **escritura** que el modelo eligió se llama **`write`**, no
  `search_replace` (el doc mapea `Edit`/`Write`→`search_replace`, pero `write`
  existe como tool aparte). El matcher `Write` la atrapó igual: el matching es
  case-insensitive o `write` está en la familia de alias — no se distinguió,
  y no hace falta: `Bash|Edit|Write|Task` cubre las cuatro.
- `search_replace` como matcher **no** atrapa a la tool `write` (ronda 2:
  ptu-native no disparó para `write`). Para D5, `implemented`/review-notice
  deben cubrir **ambos** nombres nativos: `search_replace` y `write`.

### 4. `GROK_HOOK_EVENT` / `GROK_SESSION_ID` / `CLAUDECODE` → D2

Las dos primeras presentes en los 12 dumps; `CLAUDECODE` ausente. Bonus
medido: `CLAUDE_PROJECT_DIR` también la inyecta el runner (alias documentado).

### 5. El `env` map entrega `SUMMONAIKIT_HOOK_TARGET=grok` → D3 rama TARGET

**Sí**, en los 12 dumps de hook. Claude no propagaba el prefijo `VAR=val` (A10);
el `env` map de Grok es de primer nivel y funciona.

### 6. `transcriptPath` y contención A6

**Existe, camel, y cae adentro de `~/.grok/sessions/`**:

```
C:\Users\ehven\.grok\sessions\C%3A%5Cdev%5Csaikit-captura-grok\<sessionId>\updates.jsonl
```

Con el hook en `~/.grok/hooks/`, `PROFILE_DIR=~/.grok` y **A6 contiene**. Ojo:
apunta a `updates.jsonl` (los updates ACP), no a `chat_history.jsonl` — ambos
existen en el mismo directorio; la 7.3 decide cuál parsea el recibo.

### 7. `lastAssistantMessage` en el Stop

**Sí**, en los tres Stops de turno (`"listo"`, `"hecho"`, `"hecho"`). El canal
1 del recibo vive sin parsear transcript.

### 8. `reason` del Stop de turno vs cierre → D6

Medido en los 5 turnos, sin excepción:

- Stop de turno: `reason: "end_turn"`, **con** `promptId`,
  `stopHookActive: false`, `lastAssistantMessage`, `backgroundTasks` y
  `sessionCrons` (arrays vacíos).
- Stop de cierre: `reason: "shutdown"`, **sin** `promptId` ni
  `lastAssistantMessage`. Existe incluso en headless `-p`: el proceso sale tras
  el turno y dispara el segundo Stop.

D6 queda confirmada literal: filtrar `reason == "end_turn"` solo en
`HOST=grok`. (`channel_closed` no se observó; `shutdown` es el literal de hoy.)

### 9. `PostToolUseFailure` → D5 / A11 — **premisa del diseño caída**

El evento **existe** (el loader aceptó la entrada sin warning) pero **no disparó
en ninguna de las tres clases de falla medidas**:

| Falla provocada | Qué llegó |
|---|---|
| Comando `exit 1` | `PostToolUse` normal, `toolResult.exit_code: 1`, `output_for_prompt: "exit: 1\n"` |
| `search_replace` sobre archivo inexistente | `PostToolUse` normal, `toolResult: {"type":"SearchReplace","FileNotFound":…}` |
| `search_replace` sin match | `PostToolUse` normal, `toolResult: {"type":"SearchReplace","NoMatchesFound":…}` |

**Las fallas llegan por `PostToolUse` con un `toolResult` de error.** Un runner
rojo NO es invisible (A11 respira), pero la señal no es el evento
`PostToolUseFailure`: es `toolResult.exit_code != 0` o la variante de error del
`toolResult`. Qué dispara `PostToolUseFailure` queda **`unknown`** (ver § Lo que
quedó sin resolver). Esto cambia D5: registrar el evento no alcanza; la
evidencia de falla hay que leerla en el `toolResult` del `PostToolUse`.

### 10. `subagent_type=implementer` y el agente temporal → D7

Se puso `.grok/agents/implementer.md` (frontmatter `name` + `description`,
mínimo) **en el repo descartable** y el spawn resolvió: `SubagentStart` reporta
`subagentType: "implementer"` y el hijo corrió su tarea. Los agentes de
proyecto (`<repo>/.grok/agents/`) existen como scope y **no colisionan con la
persona bundled** `implementer`. Nada se escribió en `~/.grok/agents/`.

Dato para la 7.5, medido de paso en los debug logs: Grok intenta cargar
`~/.claude/agents/*.md` del operador y **los rechaza** (`skills: invalid type:
string …, expected a sequence`): el frontmatter del repo con `skills:` en forma
string no parsea en Grok. La traducción de frontmatter que D7 anticipaba ("de
existir, tiene su caso") **hace falta** si la fuente mantiene esa clave.

### 11. Forma exacta de `toolInput`

| toolName | toolInput medido |
|---|---|
| `run_terminal_command` | `{"command": "echo hola-captura", "description": "…"}` |
| `write` | `{"file_path": "C:\\dev\\…\\nota.txt", "content": "hola\n"}` |
| `search_replace` | `{"file_path": "…", "old_string": "…", "new_string": "…"}` |
| `spawn_subagent` | `{"prompt": "…", "description": "…", "subagent_type": "implementer", "background": false}` |

Todo bajo `toolInput` camel; claves internas snake (`file_path`, `old_string`,
`subagent_type`). Los lectores de evidencia necesitan `toolInput.command` y
`toolInput.file_path`.

## Diff de forma contra Claude (como la tabla de la 6.1)

| Campo | Claude | Grok (medido) |
|---|---|---|
| claves del envelope | snake (`hook_event_name`, `session_id`, `tool_input`, `tool_name`, `transcript_path`, `last_assistant_message`, `stop_hook_active`) | **camel** (`hookEventName`, `sessionId`, `toolInput`, `toolName`, `transcriptPath`, `lastAssistantMessage`, `stopHookActive`) |
| valor del evento | PascalCase (`UserPromptSubmit`, `Stop`) | **snake** (`user_prompt_submit`, `stop`, `post_tool_use`, `subagent_start`) — invertido respecto de la clave |
| prompt | texto pelado | el del usuario llega **wrappeado**: `<user_query>\n…\n</user_query>`; el prompt interno de un subagente llega pelado |
| resultado de tool | `tool_response` | **`toolResult`** (+ `toolResultTruncated`, `toolInputTruncated`, `toolUseId`, `isBackgrounded`) |
| falla de comando | PostToolUse con exit en response | igual en la forma, pero el exit viaja en `toolResult.exit_code` y `output_for_prompt` |
| rol del subagente | `agent_type` (3.7) | `subagentType` (primer nivel) + `toolInput.subagent_type` |
| Stop de cierre | no observado | **existe**: `reason: "shutdown"` sin `promptId` |
| env de host | `CLAUDECODE=1` | `GROK_HOOK_EVENT`, `GROK_SESSION_ID`, `GROK_WORKSPACE_ROOT`, `CLAUDE_PROJECT_DIR`; `env` map propio funciona |
| permissionMode | `auto`/`dontAsk` medidos (1.4) | `bypassPermissions` con `--always-approve` |

## Hallazgo de plataforma: el shell de hooks en Windows es **powershell.exe**

Los primeros hooks dispararon pero morían con `exit code 1` sin escribir nada.
Un turno de probe con 4 formas de comando lo clavó (y el debug log lo confirma:
`xai_grok_config::shell: Windows shell: powershell.exe`):

| Comando registrado | Resultado |
|---|---|
| `bash -c '…'` | corre (bash resuelve por PATH) |
| `"C:/Program Files/Git/bin/bash.exe" "script" args` (forma zcode) | **exit 1** — en PowerShell un string quoted es una expresión, no una invocación |
| `/usr/bin/env bash -c '…'` | exit 1 — ruta virtual MSYS, no resuelve |
| `echo … > C:/dev/…` | corre, y el redirect escribe **UTF-16LE** (firma de PowerShell 5.1) |

La forma que invoca al bash.exe correcto sin depender del PATH es el call
operator: `& "C:/Program Files/Git/bin/bash.exe" "<script>" args`. Es la que
`capture-payloads.sh --host grok` genera. **Consecuencia para D1/7.5:** el JSON
canónico del diseño (`"command": "<abs>/summonaikit-harness.sh"` pelado) tal
cual está **no correría en Windows** — la 7.5 tiene que emitir la forma `&`
(o un shim). Premisa del diseño a ajustar, no corregida acá.

## Trust en headless: cómo se materializó

`GROK_FOLDER_TRUST=0` pone `Project trusted: yes` en `grok inspect` pero **no
alcanza**: la sesión cargó `hook_count=0` y ningún hook corrió. El gate real es
la entrada en `~/.grok/trusted_folders.toml`:

```toml
[folders.'C:\dev\saikit-captura-grok']
trusted = true
decided_at = <epoch>
```

Se agregó con backup (`trusted_folders.toml.bak` en el descartable) y se
**restauró byte a byte** al terminar (cksum idéntico al inicial; `grok inspect`
vuelve a decir `Project trusted: no`). No existe flag `--trust` en 1.0.3 (no
está en `grok --help`), aunque el doc lo menciona — queda declarado.

Detalle medido: el scan temprano del workspace loguea `discovery complete
total_hooks=0` aun con trust — los hooks de proyecto cargan después, al spawn de
la sesión (`loaded hooks hook_count=7`). No alarmarse por el primer conteo.

## Lo que quedó sin resolver, declarado

- **Qué dispara `PostToolUseFailure`.** Tres clases de falla (exit≠0,
  FileNotFound, NoMatchesFound) llegaron como `PostToolUse` con `toolResult` de
  error. El evento carga sin warning pero no se observó disparando. `unknown`,
  no ausente. Hipótesis no medida: fallas de runtime del propio tool
  (permisos del OS, crash interno), no errores de dominio.
- **Matcher case-insensitive vs familia de alias para `write`.** El matcher
  `Write` atrapó la tool `write`; no se distinguió el mecanismo. No cambia
  ninguna decisión.
- **`reason: "channel_closed"`.** Solo se observó `shutdown` como cierre.
- **`SessionStart`/`SessionEnd`/`PreToolUse`/`SubagentStop`**: no se
  registraron (fuera del set pedido). `SubagentStop` queda para la 7.2 si el
  bloqueo lo necesita.

## Consecuencias para las tareas que siguen

| Tarea | Qué cambia con esto |
|---|---|
| 7.2 | El Stop de cierre existe en headless y su decisión se ignora (doc); medir el contrato de salida con `reason=end_turn` filtrado |
| 7.3 | **D2 y D4 confirmados con evidencia.** D5 se reescribe: la falla se lee en `PostToolUse.toolResult` (`exit_code`, variantes `FileNotFound`/`NoMatchesFound`), no en `PostToolUseFailure`. Evidencia de edición: cubrir `search_replace` **y** `write`. El sentinel debe buscar `-saikit` dentro del wrapper `<user_query>`. A6 contiene (`transcriptPath` bajo `~/.grok/sessions/`, archivo `updates.jsonl`) |
| 7.4 | **D3 se prende entero**: `TARGET=grok` por `env` map + rol por `subagentType`/`toolInput.subagent_type`/`SubagentStart` |
| 7.5 | El comando del JSON canónico necesita la forma PowerShell (`& "…bash.exe" "…"`) en Windows. El frontmatter de los agentes necesita traducción (`skills:` string no parsea). El trust de proyecto NO es vía para staging headless sin tocar el perfil: exige entrada en `trusted_folders.toml` |
| 7.6 | Los escenarios Grok se construyen desde estos 37 payloads |

## Los payloads

37 en `C:\dev\saikit-captura-grok\capturas\ronda-{1..5}\`, crudos, con su `.env`
al lado. **No se commitean** (texto de turnos reales y rutas del perfil). Al
cerrar: `--quitar --host grok` ejecutado (JSON y marca fuera; `capturas/` y el
`implementer.md` temporal quedan solo en el descartable), trust restaurado,
perfil byte a byte idéntico.
