# @summonaikit/dsh-gate — adaptador del gate para dsh (Phase 15)

Plugin de **dsh** (`@deepseek-ai/dsh`, `0.1.1-rc.2`) que traduce eventos del harness
al contrato que `hooks/summonaikit-harness.sh` ya entiende, y ejecuta el hook con
`SUMMONAIKIT_HOOK_TARGET=dsh`. Una sola fuente de verdad: las reglas del gate son las
del hook bash (D1); este adaptador es un port delgado + fail-open (D3).

## Traducciones (`translate.js`)

| dsh | Hook |
|---|---|
| `agent/session-start` | `SessionStart` |
| `agent/pre-step` (lote con `UserMessage`) | `UserPromptSubmit` `{ prompt }` (el texto solo cuando hay uno de usuario) |
| `tools/result` de `subagent` | `PostToolUse` `{ tool_name:"Task", tool_input:{ subagent_type, description } }` |
| `tools/result` de tools de fs (`edit`, …) | `PostToolUse` con `tool_name` `Edit`/`Write` y `tool_input:{ file_path }` |
| `agent/turn-stopping` | `Stop` `{ last_assistant_message }` |

`toSessionStart` / `toUserPromptSubmit` / `toPostToolUse` / `toStop` devuelven el
payload del hook o `undefined` cuando el evento no aplica. `spawn-hook.js` ejecuta el
hook con el payload por stdin y parsea la respuesta. `index.js` registra los
listeners, encola las llamadas por sesión y bloquea vía `agent.followup`.

## Adaptaciones por la medición (Task 15.1)

Estas difieren del pseudocódigo del plan y vienen de `docs/task-15.1-medicion-dsh.md`:

- **`subagent` sin `subagent_type`/`persona`.** En dsh la tool model-facing de
  delegación se llama `subagent` y sus `arguments` son `{ description, prompt }` —
  **no** hay campo estructurado con el rol. El adaptador **infiere** el rol del texto
  (heurística: `verify`→verifier, `review`→reviewer, `add/create`→implementer,
  `adversar`→adversary), probando **primero la descripción** (señal corta y típica)
  y el prompt solo como fallback. **Fail-safe:** devuelve `undefined` si **ninguna**
  o **más de una** regla coincide (ambiguo); una descripción ambigua se ignora (el
  evento se pierde y la ceremonia del gate reclamará el rol faltante). Confirmar en
  el turno vivo de 15.5 si dsh expone el rol por otro canal (p. ej. la persona del
  hijo en `agent/created`).
- **Texto final del asistente.** Vive en `session/event` `assistant/message` en
  `event.data.message.content[].text` — no en `event.message`. `textOf()` lee esa
  ruta (con el fallback del plan por robustez).
- **Tools de fs.** Observadas: `edit` (con `file_path`) y `read` (con `file_path`).
  `write`/`str_replace_editor` no aparecieron en el turno capturado; se conservan en
  el map por robustez. `read` no se mapea (es una lectura; el gate rastrea
  escrituras).

## Fail-open (D3)

`runHook` nunca traba dsh por un error propio: hook inexistente, `bash` ausente,
timeout, o salida no-JSON → se registra (log de sesión vía `ctx.logger.warn`) y se
**deja pasar**. La única excepción al fail-open es el instalador (15.4).

## Cola por sesión

Cada llamada al hook corre después de la anterior de la **misma sesión**, en el
orden en que dsh emitió los eventos (bots #83): `Stop` espera a que drenen los
`PostToolUse`, para que un `tools/result` del verifier que escribe `agents_seen` no
carreree contra el `Stop` que lee el estado.

## Shape de los mensajes inyectados (codex r1 PR #86)

Los mensajes que el adaptador inyecta (`additionalContext` del contrato y el
`followup` del bloqueo) usan `{ role:"user", source:{ kind:"plugin",
plugin:"summonaikit-gate" }, content:[{type:"text",text}] }`. dsh define
`MessageSource` como sum type: `{kind:'user'|'plugin'|'model'|'tool'}` con los
campos de cada uno — la string `source:"summonaikit-gate"` del pseudocódigo del
plan es **inválida** (el validador de sesión de dsh la rechaza). El `cwd` se
deriva de `agent.session.header.cwd` (dsh no pone `meta.cwd` en `agent/created`),
con fallback a `process.cwd()`. El estado por sesión (`lastText`/`cwdOf`/`queues`)
se limpia en `agent/disposed` (proceso dsh de larga vida). El texto del asistente
vive en `event.data.message.content[].text` y `textOf()` toma solo los bloques
`type:"text"` (un recibo solo en el `reasoning` oculto no debe pasar el gate).

## Ejecución

```bash
node --test hosts/dsh/test/          # CI (Linux): scan del directorio
node --test hosts/dsh/test/*.test.js # Windows (el dir con `/` lo trata como modulo)
```

## Versión medida

`summonaikit.measuredAgainst` = `@deepseek-ai/dsh@0.1.1-rc.2`.
