# Phase 15 — summonaikit en el DeepSeek Harness (`dsh`): diseño

Fecha: 2026-08-27. Estado: diseño aprobado por el operador en sesión, pendiente
de su revisión escrita antes del plan.

**Contrato de datos (Core Rule 2 del spec):** `not_observed != absent`. Todo lo
que abajo dice "dsh hace X" viene de la documentación y los tipos del paquete
instalado (`@deepseek-ai/dsh` 0.1.1-rc.2 y sus plugins); lo que NO se midió en
un turno vivo queda marcado `unknown` y se mide en la Task 15.1 antes de
escribir código que dependa de ello.

## 1. Qué es "el harness de DeepSeek" en esta máquina

Hay dos cosas distintas con nombre DeepSeek:

| Comando | Qué es | summonaikit hoy |
|---|---|---|
| `deepseek` | Shim que lanza **Claude Code** con `ANTHROPIC_BASE_URL` apuntando a la API de DeepSeek (`deepseek-v4-pro`). | **Ya activo** (usa `~/.claude/hooks`). Fuera de alcance de esta fase. |
| `dsh` | **DeepSeek Harness** (`@deepseek-ai/dsh` 0.1.1-rc.2): app de plugins cordis; profiles compuestos por bundles + `cordis.patch.yml`; UI web (`dsh web`), `headless`, `tui`. Instalado solo el profile `web`. | **Ninguno.** Objetivo de esta fase. |

dsh no tiene hooks de shell (`hooks.json`, `settings.json`) como claude, codex,
grok, zcode o kimi. Su superficie de extensión es un **plugin** (JS) compuesto
en el árbol del profile. Los puntos de enganche relevantes, según los tipos de
`dsh-agent` (`runtime-types.d.ts`) y los README de `dsh-tools` y `dsh-subagent`:

- `agent/session-start`, `agent/created`, `agent/disposed`.
- `agent/pre-step` — waterfall cooperativo; recibe el lote de `UserMessage[]`
  propuesto y devuelve `PreStepDecision` = `{kind:'reject'}` o
  `{kind:'enter', messages}` (puede agregar mensajes durables al lote).
- `agent/turn-stopping` — serial, `void`; el turno "cierra solo cuando el inbox
  drena": un listener puede encolar trabajo (`agent.followup(message)`) y el
  turno sigue.
- `tools/pre-execute` (allow/deny), `tools/post-execute` (puede bloquear con
  feedback o adjuntar contexto), `tools/result` (solo observar).
- Subagentes: tool model-facing `subagent` (`dsh-tool-subagent`) con
  `persona` por hijo (`dsh-persona`) y `label`; presets de agente en
  directorios con `agent.cordis.yml` (`dsh-agent-presets`, raíz
  `~/.dsh/.agent-presets`, hoy vacía).
- Instrucciones: `dsh-agent-instructions` inyecta `~/.dsh/AGENTS.md` y el
  `AGENTS.md` del proyecto como `<system-reminder>` en el primer paso.
- Composición: `~/.dsh/profiles/<p>/cordis.patch.yml` (por profile) y
  `~/.dsh/cordis.patch.yml` (nivel home, aplica a todos). `dsh --dump-config`
  imprime el árbol compuesto sin arrancar.

## 2. Decisiones (con su razón)

**D1 — Reutilizar el hook bash; el port es un adaptador.** Un plugin de dsh
traduce eventos de dsh a los payloads que `hooks/summonaikit-harness.sh` ya
entiende y ejecuta el hook (`bash`, JSON por stdin, `SUMMONAIKIT_HOOK_TARGET=dsh`
en el entorno). Razón: una sola fuente de verdad — las reglas de 14 fases, las
~110 mutaciones y la línea base golden se heredan; reescribir el gate en JS
serían dos implementaciones a sincronizar. Descartado también "solo
instrucciones" (AGENTS.md + personas sin bloqueo): es el control decorativo que
el proyecto existe para eliminar.

**D2 — El hook gana `HOST=dsh` por la vía de codex.** Detección por
`SUMMONAIKIT_HOOK_TARGET=dsh` (setness/valor exacto, como codex), no por
variables heredadas del entorno (lección grok/codex: un hijo lanzado desde otro
host hereda vars y se cree ese host). Estado en `state/dsh/<SessionId>`.

**D3 — Fail-open del adaptador.** Si `bash` no está, el hook no existe, no es
ejecutable, revienta o devuelve JSON inválido, el plugin lo registra (log de la
sesión) y **deja pasar**. Nunca traba dsh por un error propio. La única
excepción al fail-open sigue siendo el instalador (falla cerrado si no puede
verificar el destino), como en todos los hosts.

**D4 — Personas, no presets, para los cuatro roles.** Los perfiles
`implementer`/`verifier`/`reviewer`/`adversary` se instalan como personas de
dsh (lo que `dsh-tool-subagent` aplica por hijo con `persona`), desde el mismo
texto fuente `agents/*.md`, con frontmatter traducido por el instalador y marca
`saikit_owned`. Los presets (`agent.cordis.yml`) recomponen el agente entero;
son más de lo que un rol necesita. **Formato y ruta exactos: `unknown` hasta
15.1.**

**D5 — Composición a nivel home.** La entrada del plugin va en
`~/.dsh/cordis.patch.yml` entre marcas propias: aplica a `web` hoy y a cualquier
profile futuro sin reinstalar. Alcance medido y cerrado: solo `web` (decisión
del operador); `headless`/`tui` quedan `unknown`.

**D6 — Ruteo de modelos.** Fila `dsh` en `tools/model-routing.sh`, vacía
(hereda el modelo de la sesión), como zcode/grok. Se llena solo si 15.1 mide que
dsh acepta modelo por persona (`agentOptions.model`).

**D7 — Canal interno.** dsh declara que las llamadas a `subagent` pasan por
`tools/*`, así que el verifier delegado dejaría rastro (a diferencia de zcode,
ciego). `saikit_host_ciego()` NO se toca hasta que 15.1 lo mida en vivo: dsh no
entra en la lista de ciegos ni en la de observables hasta entonces.

## 3. Traducción de eventos

| dsh | El plugin toma | Manda al hook | Con la respuesta |
|---|---|---|---|
| `agent/session-start` | `SessionId`, cwd del workspace | `SessionStart` | nada visible (el hook siembra/limpia estado) |
| `agent/pre-step` (lote con `UserMessage`) | el texto del usuario del lote | `UserPromptSubmit` `{prompt}` | si hay `hookSpecificOutput.additionalContext` (contrato al armar con `-saikit`), lo agrega al lote como mensaje inyectado; si no, devuelve el lote intacto |
| `tools/result` de `subagent` | `persona`, `label`, resultado | `PostToolUse` `{tool_name:"Task", tool_input:{subagent_type:<persona>}}` | nada (el hook registra `agents_seen`) |
| `tools/result` de tools de fs (`str_replace_editor`, `write`, …) | tool y ruta | `PostToolUse` `{tool_name:"Edit"|"Write", tool_input:{file_path}}` | nada (candado post-hoc del adversary) — **tools y campo de ruta: `unknown` hasta 15.1** |
| `agent/turn-stopping` | último texto del asistente del turno | `Stop` `{last_assistant_message, transcript_path?}` | `decision:"block"` + feedback → `agent.followup(feedback)`; el turno sigue. Sin bloqueo → cierra |

`session_id` = `SessionId` de dsh. `transcript_path`: el JSONL de
`dsh-session-persistence-jsonl` **si** su forma la entiende el walker del hook
(`role:assistant` + `content[].type:text`); si no, se omite y el gate juzga
solo `last_assistant_message` (fail-open ya existente). `unknown` hasta 15.1.

## 4. Componentes

- `hosts/dsh/` — paquete `@summonaikit/dsh-gate` (ESM, sin build, sin deps
  fuera de Node). Un archivo principal que registra los listeners; un módulo
  `spawn-hook.js` (ejecuta el hook con timeout, parsea la respuesta, fail-open);
  un módulo `translate.js` (evento dsh → payload del hook), puro y testeable sin
  dsh. Config del plugin: `{ hook: <ruta>, timeoutMs, logLevel }`.
- `hooks/summonaikit-harness.sh` — rama `HOST=dsh`; lo mínimo que el `HOST`
  nuevo necesite (estado, target de salida). Sin nuevas reglas.
- `tools/install-hook.sh --host dsh [--dry-run] [--quitar-dsh]` — hook a
  `~/.dsh/hooks/`, plugin a `~/.dsh/plugins/summonaikit-dsh-gate/`, entrada
  entre marcas en `~/.dsh/cordis.patch.yml`, personas con marca. Tres estados,
  backups fechados, atómico; `--dry-run` no escribe (lección 13.9 #2).
- `tools/check-hook-registration.sh --dsh-home <dir>` — silencio = hook +
  entrada del patch + 4 personas presentes; habla si falta algo.
- `tools/model-routing.sh --host dsh` — fila vacía.
- `agents/*.md` — sin cambios de texto; el instalador traduce.
- Docs: este diseño; `docs/task-15.1-medicion-dsh.md`; spec § host dsh;
  `Plans.md` Phase 15; `docs/deploy-log.md` al desplegar.

## 5. Pruebas y medición (escalera)

1. **15.1 Captura.** Plugin espía mínimo (sin hook) que vuelca a JSONL cada
   evento real en un turno vivo en la UI web sobre un repo desechable:
   `session-start`, `pre-step`, `tools/result` de `subagent` y de fs,
   `turn-stopping`, y el JSONL de sesión. Entrega: `tests/fixtures/dsh/*.jsonl`
   + doc de medición con lo observado y lo `unknown`. Sin esto no se escribe
   el adaptador.
2. **Banco del adaptador** (Node, rápido): dsh falso que reproduce los fixtures
   + hook falso con respuestas conocidas. Casos con nombre: arma / no arma /
   bloquea-y-encola / cierra limpio / hook ausente → fail-open declarado /
   JSON inválido → fail-open.
3. **Gate (`hook_lab`)** con `HOST=dsh` y los payloads capturados: rojo medido
   pre-fix, caso que acredita + caso que bloquea, mutación por rama nueva
   (`HOST=dsh`, ruteo, candado), línea base golden con escenarios dsh y 0
   divergencias.
4. **Instalador**: instala / repara / no toca DESCONOCIDO / `--dry-run` no
   escribe / `--quitar-dsh` restaura; y `dsh --dump-config` muestra el plugin.
5. **Turno vivo (cierre)**: tarea real con `-saikit` en la UI web — contrato
   inyectado, roles por `subagent`, recibo sin evidencia bloqueado y devuelto,
   recibo completo cierra. Transcript guardado como evidencia.

Reglas de proceso heredadas: batería completa una vez, en CI; local solo el
driver del archivo tocado; tope de 2 rondas de bots/cross-review por PR, lo
residual se declara.

## 6. Límites declarados desde el diseño

- dsh es `0.1.1-rc.2`: sus eventos y config pueden moverse entre versiones.
  El instalador registra la versión de dsh contra la que se midió; una versión
  distinta se reporta, no se asume compatible.
- El gate en dsh es tan advisory como en los demás hosts (Non-Goal del spec):
  un lead que controla el texto del turno puede influirlo.
- `unknown` hasta 15.1: forma real de los payloads, formato/ruta de personas,
  tools de fs y campo de ruta, `transcript_path` utilizable, modelo por persona,
  y si el canal interno es observable en vivo.
- Fuera de alcance: `headless`/`tui`, el shim `deepseek` (ya cubierto por
  Claude Code), y cualquier regla nueva del gate.
