# Task 23.1: la captura de Muse Code

Fecha: 2026-09-17. Muse Code `1.3.0-R3401.1` en macOS (Darwin 25.6, arm64),
modelo `muse-spark-1.3`. Repo descartable en el scratchpad de la sesión, con un
`README.md` de una línea. Cinco turnos con el proveedor `echo` (cero costo) y
tres turnos reales contra la Meta Model API (centavos). Evidencia redactada en
`docs/evidence/phase-23/23.1/`.

**El perfil del operador no se tocó.** Los archivos de `~/.config/muse/`
conservan fechas anteriores a la sesión: `settings.json` 08:20,
`approval-policy.json` 00:13, `trust.json` 22:42 del día anterior. No existe
`~/.config/muse/agents/`. Los registros de usuario se midieron con
`XDG_CONFIG_HOME` apuntando a un directorio aislado.

**Efecto secundario declarado.** El lanzador `~/.local/bin/muse` actualiza el
binario solo al arrancar. Las primeras llamadas a `--help` lo movieron de
`1.3.0-R3233.1` a `1.3.0-R3401.1`. Todo lo de abajo se midió llamando al
binario versionado directamente, para que no cambiara a mitad de la captura.

## El veredicto: el gate corre en Muse con el mismo contrato de Claude

Muse implementa el contrato de hooks de Claude Code casi al pie de la letra.
El hook existente se inyecta, bloquea y lee el rol sin traducción de formas.
Lo que falta es reconocimiento del host y de sus nombres de herramienta, más
el formato de los perfiles de rol. No hace falta un adaptador como el de dsh.

Una premisa de terceros cayó. Un artículo de agosto (Muse 0.2.1) afirmaba que
`.muse/hooks.json` se ignoraba y que los hooks solo corrían como plugin
experimental. En la 1.3.0 los dos registros por archivo disparan.

## Lo medido

| Premisa | Veredicto | Evidencia |
|---|---|---|
| Registro de proyecto en `<repo>/.muse/hooks.json`, forma de Claude (`{"hooks":{"<Evento>":[{"hooks":[{"type":"command","command":…,"timeout":…}]}]}}`) | Dispara, solo con el workspace confiado (`--trust-workspace`) | fixtures 00 a 05 |
| Registro de usuario en el bloque `hooks` de `~/.config/muse/settings.json` | Dispara **con y sin** confianza del workspace. Es el canal global | medido con XDG aislado, ver Reproducir |
| `settings.json` se valida de forma estricta | Una clave desconocida aborta **todo** comando al arrancar: `malformed settings file at …: unknown field …` | salida textual en la sección Riesgos |
| Eventos que disparan | `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `SubagentStart`, `SubagentStop`, `Stop`, `SessionEnd` | fixtures 00 a 19 |
| Forma del payload | snake_case con el vocabulario de Claude: `hook_event_name`, `session_id`, `turn_id`, `cwd`, `prompt`, `tool_name`, `tool_input`, `tool_response`, `tool_use_id`, `stop_hook_active`, `last_assistant_message`, `model`, `model_provider`, `permission_mode`. `transcript_path` llega `null` | fixtures 01, 02, 08, 10 |
| Entorno del hook | Limpio: solo `_ HOME LANG LOGNAME PATH PWD SHELL SHLVL TERM TMPDIR USER`. **Ninguna** variable `MUSE_*`, así que el hook no puede detectar el host solo. `PATH` se hereda de quien lanza Muse | `entorno-del-hook.txt` |
| Prefijo de entorno en el comando registrado | `SUMMONAIKIT_HOOK_TARGET=muse <cmd>` **llega** al proceso: el comando corre en un shell. (En Claude sobre Windows no llegaba, A10) | log del probe: `UserPromptSubmit target=muse` |
| `UserPromptSubmit` con `hookSpecificOutput.additionalContext` | Entra al contexto del modelo como bloque `developer` (`hook:user_prompt_submit:prompt:0`) | `salida-contexto-inyectado.json` |
| `Stop` con `{"decision":"block","reason":…}` | Fuerza otra pasada del modelo. La razón entra como bloque `developer` (`hook:stop:stop:0`). La segunda llamada trae `stop_hook_active` | `salida-contexto-inyectado.json`; el `Stop` disparó dos veces |
| Herramienta de delegación | `subagent_spawn`, con `tool_input = {command_id, objective, role, subagent_type}`. El rol viaja en `tool_input.subagent_type` | fixture 08 |
| Cuándo llega el `PostToolUse` del despacho | Al **aceptar** la tarea, no al terminarla. `tool_response` es un JSON en texto con `status` (`accepted` o `rejected`), `subagent_id` y `agent_path` (`main/reviewer/1`) | fixtures 06 y 10 |
| Fin del subagente | `subagent_wait` devuelve `status: ready` con `summary`. `SubagentStop` llega con la sesión del hijo y `subagent_id`, **sin rol** | fixtures 14 y 15 |
| Eventos internos del hijo | Llegan con el `session_id` **del hijo** y sin campo de rol | fixtures 12 y 13 |
| Orden medido | `PreToolUse subagent_spawn` (padre), `SubagentStart` (hijo), `PostToolUse subagent_spawn` (padre, trae `subagent_id`), internos del hijo, `SubagentStop`, `PostToolUse subagent_wait` | fixtures 08 a 15, por nombre de archivo |
| Subagentes internos de Muse | Cada turno corre recordatorios propios (`skill-reminder`, `goal-reminder`, `verify-reminder`) con sesión propia. Emiten `SubagentStart/Stop` y `Pre/PostToolUse submit_reminder_decision`, y gastan tokens del mismo modelo | fixtures 04 y 05 |
| Herramientas de edición y shell | `write_file {content, path}`, `edit_file {find, path, replace}`, `bash {command, description, workdir}` con `exit_code` en la respuesta, `read_file {path, …}` | fixtures 17 a 19 y 12 |
| Dónde descubre perfiles de agente | `<repo>/.agents/agents/<id>.md`, `<repo>/.agents/agents/<id>/AGENT.md` y `$XDG_CONFIG_HOME/muse/agents/<id>.md` (`~/.config/muse/agents/`). **No** lee `~/.agents/agents` (donde `--host kimi` instala), `.claude/agents`, `.codex/agents` ni `.muse/agents` | catálogo del turno: `Use an exact listed id:` |
| Qué frontmatter acepta | `name`, `description` (también multilínea), `tools` (texto o lista), `skills` **solo como lista YAML** (con ids `saikit:*`), `model: inherit` | ídem |
| Qué frontmatter tumba el perfil entero | `saikit_owned` (clave desconocida), `metadata`, `skills` como texto separado por comas, `reasoning_effort`, `effort` y un `model` concreto. Con el proveedor real el rechazo es visible: `Agent Definition \`reviewer\` is invalid … (KnownFieldInactive, Model)` | fixture 06 |
| Los cuatro perfiles del kit tal cual | **Rechazados los cuatro**, en silencio en el catálogo, por `skills` en texto y `saikit_owned` | catálogo sin ningún rol del kit |
| Dónde puede vivir la marca de propiedad | Como comentario YAML dentro del frontmatter (`# saikit_owned: summonaikit-claude`) o como comentario HTML en el cuerpo. Las dos formas dejan el perfil válido | catálogo con `own-comment` y `own-body` |
| Skills del kit | Ya visibles sin instalar nada: Muse carga `~/.claude/skills` y `~/.agents/skills` como fuente `user`. Aparecen `saikit:*`, `sencillo`, `saikit-verificar-app` y `saikit-setup-autopilot` | `muse skills list --source all` |
| Plugins | Un plugin con manifiesto de Claude Code valida: acepta `skills` y `hooks`, marca `agents` como `unsupported`. El manifiesto nativo `.muse-plugin/plugin.json` acepta `skills`, `commands`, `hooks`, `mcpServers` y `reminders`, y rechaza `agents` | `muse plugins validate --json` |

## Lo que el hook no reconoce hoy

Leído en `hooks/summonaikit-harness.sh` contra los fixtures de arriba.

1. **La ceremonia no se exige para `muse`.** La rama de secuencia solo se
   prende para `claude|codex|grok|dsh` (`:4263`).
2. **El mensaje nombra una herramienta que no existe.** `TOOL_HINT` dice "the
   Task tool" salvo en grok y dsh (`:63-66`). En Muse es `subagent_spawn`.
3. **Las ediciones de Muse son invisibles.** La regex de edición no incluye
   `write_file` (`:2900`, `:3329`), y la ruta se lee de `tool_input.file_path`,
   que Muse no manda: usa `path`.
4. **Un despacho rechazado acreditaría el rol.** El camino genérico lee
   `tool_input.subagent_type` del `PostToolUse` (`:3223`) sin mirar
   `tool_response.status`. Además ese evento llega al aceptar, no al terminar.
   El precedente es 21.2 en codex: sin cierre no hay crédito.
5. **El veto de `PreToolUse` compara `Bash` exacto** (`:4585`). La herramienta
   de Muse es `bash` en minúsculas.
6. **Los internos del hijo caen en otra sesión.** El estado se llavea por
   `session_id` y el hijo trae el suyo. Lo que corra el verifier adentro no
   llega a la sesión del padre. El orden medido permite el vínculo que 20.13
   ya usa en grok: `SubagentStart` anuncia `subagent_id` y `child_session_id`,
   y el `PostToolUse` del despacho en el padre trae el mismo `subagent_id`.

## Lo que queda `unknown`

- **Semántica del `matcher`.** No se midió si filtra por `tool_name` con regex
  como en Claude. Sin matcher el hook corre en cada herramienta, incluidos los
  recordatorios internos.
- **`PreToolUse` con `permissionDecision: deny`.** El binario valida esa forma
  y exige `permissionDecisionReason` no vacío, pero no se midió en vivo.
- **`exit 2`.** No se midió en ningún evento.
- **Tope de continuaciones de `Stop`.** Existe
  `max_consecutive_stop_hook_continuations` en settings. No se midió su valor
  por defecto contra el `MAX_CYCLES=2` del hook.
- **`tools:` del perfil con nombres de Claude.** El perfil con
  `tools: Read, Edit, Write, Glob, Grep, Bash` entra al catálogo, pero no se
  midió si el hijo queda con esas herramientas mapeadas o sin ninguna.
- **Doble registro.** No se midió qué pasa si un repo trae `.muse/hooks.json`
  y el usuario tiene el mismo hook en `settings.json`.
- **Windows.** Solo se midió macOS. Las formas de comando de Windows no se
  infieren de estas.
- **Lectura de `CLAUDE.md` como reglas del proyecto.** La documenta Meta; no
  se midió acá.

## Riesgos que fijan el diseño del instalador

- **Un `settings.json` mal escrito deja a Muse sin arrancar.** Salida textual
  con un campo inválido:
  `malformed settings file at …/muse/settings.json: unknown field \`ag-set\`, expected \`safe_mode\``.
  El instalador tiene que validar el candidato antes de reemplazar. La
  palanca existe y es gratis: `XDG_CONFIG_HOME=<temporal> muse exec --provider echo "ping"`
  sale 1 con un settings inválido y 0 con uno válido (medido).
- **Muse se actualiza solo.** El contrato puede cambiar sin que nadie lo
  decida. El proveedor `echo` permite re-medirlo sin costo ni red.

## Reproducir

Todo corre en un repo git descartable y con un `XDG_CONFIG_HOME` temporal
para lo que toca registro de usuario.

```bash
B=~/.local/bin/muse-bin-<version>          # el binario, no el lanzador
cd <repo-descartable>
# 1) registro de proyecto: .muse/hooks.json con la forma de Claude y un
#    comando que guarda stdin y los nombres del entorno
$B exec --provider echo --trust-workspace --json "hola -saikit:fast"
# 2) contrato de salida: el comando emite additionalContext en UserPromptSubmit
#    y decision:block en el primer Stop; luego
$B export --session <id> --out t.json      # buscar context_block_updated source=runtime_hook
# 3) registro de usuario: mismo bloque "hooks" en $XDG/muse/settings.json
XDG_CONFIG_HOME=$XDG $B exec --provider echo "hola"
# 4) perfiles: archivos en .agents/agents/ y $XDG/muse/agents/; el catálogo
#    del turno está en el export, texto "Use an exact listed id:"
# 5) delegación real (gasta centavos):
$B exec --trust-workspace --disable-approval --user-input-auto-resolve \
  --reasoning-effort low --max-model-steps 12 --json \
  "Usa la herramienta subagent_spawn con subagent_type reviewer para que lea README.md …"
```
