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

## Raciño del desenlace de `pwsh` (glm r4 PR #86)

En dsh un comando con `exit != 0` es un **resultado de tool exitoso** (`isError:false`
con `value.exitCode` adentro), así que un `pytest`/`vitest` rojo pasaba el filtro del
adaptador y llegaba al hook como `PostToolUse` `{ tool_name:"Bash", tool_input:{ command } }`
**sin exit code ni texto de salida**. El raíl `verified` del hook veta con dos greps
sobre el payload (`"toolResult"...exit_code:[1-9]` y las señales de fallo
`FAILURE_SIGNAL_RE_CI/CS` sobre `$combined`); sin esos datos un runner rojo acreditaba
`verified=1` = **falso verde**. `toPostToolUse` enriquece el branch shell, usando `result`
que `tools/result` ya pasa a la callback de dsh:
- `tool_result.exit_code` en **snake** (dsh da `exitCode` camel; el veto grep esa forma),
  solo cuando es número. `exit_code:0` no dispara el `[1-9]`.
- `tool_response.output` (forma Claude) con stdout+stderr, para que
  `FAILURE_SIGNAL_RE_CI/CS` vea el texto de fallo.

## Subagentes en sesión propia (claude r3 PR #86, Gap1 + Gap2)

En dsh un subagente corre en su **propia sesión** (`result.value.subagentId`), así que
sus `tools/result` llegan con `agent` = id del hijo y el gate — que corre sobre la sesión
de la **madre** — no los ve. El adaptador mapea hijo→madre:

- **Gap1 — re-acreditación a la madre.** Al recibir el `tools/result` de spawn
  (`name:"subagent"` + `subagentId`), registra `childOf[subagentId] = { parent, role }`
  (rol inferido del spawn) y suma 1 a `liveKids[parent]`. Los `tools/result` posteriores
  con `agent` = id de un hijo registrado se traducen con la sesión de la **madre** y se
  les inyecta `agent_type:<rol>` de primer nivel (fallback A9 del hook), para que el gate
  atribuya el edit/run del implementer/verifier/adversary al rol correcto sobre la sesión
  de la madre. Los eventos de hijo se en-queuean bajo la sesión de la madre.
- **Gap2 — Stop con hijos vivos.** Mientras `liveKids[parent] > 0`, un
  `agent/turn-stopping` del padre es **intermedio** (el turno se corta para que corra un
  hijo), no el cierre real. Traducirlo a `Stop` quemaría el gate con la ceremonia a
  medias y dejaría pasar el turno final sin gate. `agent/turn-stopping` retorna sin
  enviar `Stop` mientras haya hijos vivos; al disponerse el último hijo
  (`agent/disposed`, que decrementa `liveKids[parent]`) el próximo turn-stopping del
  padre sí traduce. **A confirmar en el turno vivo de 15.5** que unpair exacto
  `dispose`-hijo cae antes del turn-stopping final del padre y que dsh no deja un hijo
  "zombi" que bloquee el Stop.


## Shape de los mensajes inyectados (codex r1 PR #86)

Los mensajes que el adaptador inyecta (`additionalContext` del contrato y el
`followup` del bloqueo) usan `{ role:"user", source:{ kind:"plugin",
plugin:"summonaikit-gate" }, content:[{type:"text",text}] }`. dsh define
`MessageSource` como sum type extensible por plugin (los `kind` medidos en 15.1 son
`user`, `subagent-settled`, `subagent-report`; la forma exacta del source plugin
visto por el validador de sesión **queda a confirmar en el turno vivo de 15.5** —
la string `source:"summonaikit-gate"` del pseudocódigo del plan es inválida). El
`cwd` se deriva de `agent.session.header.cwd` (dsh no pone `meta.cwd` en
`agent/created`), con fallback a `process.cwd()`. El estado por sesión
(`lastText`/`cwdOf`/`queues`) se limpia en `agent/disposed` (proceso dsh de larga
vida). El texto del asistente vive en `event.data.message.content[].text` y
`textOf()` toma solo los bloques `type:"text"` (un recibo solo en el `reasoning`
oculto no debe pasar el gate).

## Ejecución

```bash
node --test hosts/dsh/test/          # CI (Linux): scan del directorio
node --test hosts/dsh/test/*.test.js # Windows (el dir con `/` lo trata como modulo)
```

## Versión medida

`summonaikit.measuredAgainst` = `@deepseek-ai/dsh@0.1.1-rc.2`.
