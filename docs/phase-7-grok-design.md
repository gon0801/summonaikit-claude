# Phase 7 — Grok Build TUI como host

Fecha: 2026-08-13

Diseño aprobado tras revisión. El ledger de tareas vive en `Plans.md` y el delta
de producto aprobado ya está en `docs/spec/00-project-spec.md`; cada tarea agrega
allí sólo los hechos que mida al cerrar.

Ubicación del archivo: `docs/` plano, como el resto de los planes de este repo
(`phase-6-codex-design.md`, `task-N.N-plan.md`). No se crea
`docs/superpowers/specs/` para no abrir un árbol nuevo en un layout deliberado.

## Purpose

Que un turno `-saikit` en Grok Build TUI gatee igual que uno en Claude Code:
mismos arreglos A1–A11, misma ceremonia implementer → verifier → reviewer,
mismo recibo. Hoy Grok no corre el kit. El operador ya lo usa como host de
trabajo (esta sesión es prueba de ello).

El Non-Goal original excluía `.codex` / `.cursor` / `.agents`; el delta aprobado
del spec ya reabrió `.codex` para Phase 6 y mantiene fuera sólo `.cursor` y
`.agents`. Grok entra explícitamente como runtime distinto (`~/.grok`), no por
una interpretación lateral de aquel Non-Goal. Phase 6 sigue su propio diseño;
esta fase no lo reemplaza.

## Premisas medidas (2026-08-13, no supuestas)

Estas mediciones son la base del alcance. Si alguna cae, la fase se
re-planifica. Las que salen de la documentación del TUI (user-guide 10, 16, 17)
están marcadas *doc*; las que salen de archivos del operador en disco, *disco*;
las que ya midió la captura real, *7.1* (`docs/task-7.1-captura.md`, 37
payloads, 5 rondas, Grok Build 1.0.3).

### El runtime ya tiene el seam

| Pieza del kit | En Grok |
|---|---|
| Armado | `UserPromptSubmit` + `hookSpecificOutput.additionalContext` (*doc*; la forma se mide en 7.2). El evento llega como `hookEventName: "user_prompt_submit"` (*7.1*) |
| Evidencia | `PostToolUse` (éxito **y falla**): `PostToolUseFailure` **no dispara** en 1.0.3 (*7.1*, 3 clases de falla probadas); la falla llega como `post_tool_use` con `toolResult` de error (`exit_code: 1`, `FileNotFound`, `NoMatchesFound`) |
| Bloqueo | `{"decision":"block","reason"}`, `exit 2`, `continue:false`+`stopReason` (*doc*; veredicto vivo en 7.2) |
| Ceremonia | `spawn_subagent` + eventos `SubagentStart` / `SubagentStop`. El rol llega por **tres canales** (*7.1*): `subagentType` de primer nivel en `SubagentStart`, `toolInput.subagent_type` en el despacho, y `subagentType` de primer nivel en los eventos internos del subagente |
| Señal de proceso | `GROK_HOOK_EVENT` y `GROK_SESSION_ID` presentes en el env del hook (*7.1*, 37/37 dumps); `CLAUDECODE` **ausente** (*7.1*) |
| Alias Claude | **Medido** (*7.1*): el matcher alias-expande — `Bash`→`run_terminal_command`, `Edit`→`search_replace`, `Write`→`write`, `Task`→`spawn_subagent`. La tool de escritura real es **`write`** (además de `search_replace`) |
| Roles custom | `~/.grok/agents/<name>.md` y **también `<repo>/.grok/agents/<name>.md`** (scope proyecto, *7.1*: `implementer` temporal resolvió desde el descartable) |

El vocabulario de **salida** del Stop es el de Claude, documentado como tal.
Eso no se afirma como medición: es la hipótesis de trabajo de la 7.2, igual
que lo fue para Codex.

### Lo que hay hoy en el perfil (*disco*)

| | Qué es | Veredicto |
|---|---|---|
| `~/.grok/hooks/` | Solo `imported-from-claude.json.disabled` (rtk / quality-kit / tokentracker). **No hay harness.** | no hay vendor que archivar |
| `[compat.claude] hooks = false` en `config.toml` | El TUI **no** carga `~/.claude/settings.json`. Es correcto: el hook vivo, llamado a ciegas, quedaría inerte o mentiroso (ver § Por qué no prender compat) | no se toca |
| `~/.grok/agents/verifier.md` | Perfil del operador, **sin** `saikit_owned`. Distinto del `agents/verifier.md` del repo | D7: no se pisa |
| `~/.grok/sessions/<cwd-encoded>/<uuid>/` | Transcripts reales: `chat_history.jsonl`, `updates.jsonl` | A6 puede contener si el hook vive bajo `~/.grok` |
| Personas bundled `implementer` / `reviewer` | Son **personas**, no agent types. Built-ins de tipo: `general-purpose`, `explore`, `plan` | no hay colisión de tipo; **verificado en 7.1** (agente temporal de proyecto resolvió) |

No hay un harness vendor en `~/.grok`. No hay manifiesto que ganar. El primer
install es destino **AUSENTE**, no VENDOR_CONOCIDO. Eso simplifica 7.5 frente
a 6.5.

### Por qué no prender `compat.claude.hooks`

Si se prendiera, Grok cargaría el comando registrado en
`~/.claude/settings.json` (el hook vivo de Claude). Ese archivo, hoy:

1. Resuelve `HOST=other` (no hay `ZCODE_*` ni `CLAUDECODE=1` en un proceso
   Grok — **confirmado en 7.1**: `GROK_HOOK_EVENT`/`GROK_SESSION_ID` presentes,
   `CLAUDECODE` ausente en los 37 dumps de env).
2. Deja `TARGET` vacío ⇒ la ceremonia no corre.
3. Lee `session_id` / `tool_input` / `last_assistant_message` / `tool_name`
   en snake. El envelope de Grok tiene **claves camel** (`sessionId`,
   `toolInput`, `lastAssistantMessage`, `toolName`) con **valores snake** en
   `hookEventName`: `"user_prompt_submit"` / `"post_tool_use"` /
   `"subagent_start"` / `"stop"` (*7.1*, medido en los 37 payloads).
   `PHASE` ya entiende `hookEventName` y el literal `stop` (5.4);
   **no** entiende `user_prompt_submit` ⇒ el armado cae a `PHASE=tool` y el
   sentinel nunca dispara.
4. El review-notice busca `edit\|write\|multiedit`. En Grok la edición es
   `search_replace` **y `write`** (*7.1*).

Resultado: un gate que o no arma, o arma y no ve evidencia, o ve evidencia y
no exige roles. Peor que no tenerlo. `hooks = false` se queda.

### Lo que el hook actual no lee (código, 2026-08-13)

Lectores que ya tienen fallback camel (lección zcode 5.4):

- `hookEventName` (PHASE)
- `subagentType` (dentro de `json_tool_input_string`, que igual exige la clave
  padre `tool_input` en snake)

Lectores que **no** tienen fallback y Grok necesita:

| Campo Claude | Campo Grok | Quién lo lee hoy |
|---|---|---|
| `session_id` | `sessionId` (*7.1*) | `json_top_level_string session_id` (A4) |
| `tool_name` | `toolName` (*7.1*) | `json_string_field tool_name` |
| `tool_input` (objeto padre) | `toolInput` (*7.1*) | `json_tool_input_string` compara `clave1 == "tool_input"` |
| `last_assistant_message` | `lastAssistantMessage` (*7.1*: presente en los Stop `end_turn`) | walker del Stop (A2/A8) |
| `transcript_path` | `transcriptPath` (*7.1*, **confirmado**: apunta a `~/.grok/sessions/<cwd-encoded>/<uuid>/updates.jsonl` ⇒ A6 contiene) | `json_string_field` + contención A6 |
| `command` / `file_path` | `toolInput.command` / `toolInput.file_path` (*7.1*: `run_terminal_command` trae `command`; `write` y `search_replace` traen `file_path`) | evidencia y review-notice |

`GROK_SESSION_ID` llega por env (*7.1*, medido en los 37 dumps). Eso cubre A4
aunque `sessionId` del payload no se lea: el slot de sesión se puede construir
del env. No exime de leer el payload: el env es la vía limpia, el payload es la
vía que el resto de hosts ya usa.

### Phase 6 no bloquea la medición; sí serializa las costuras

Phase 6 está en `cc:TODO` (6.1–6.6). Las dos fases tocan el mismo archivo
(`hooks/summonaikit-harness.sh`: orden de `HOST`, `case` de PHASE, `case` de
ceremonia) y **no** el mismo destino de install.

El orden compuesto de `HOST` se declara acá (D2). 7.1 y 7.2 pueden correr ya:
no tocan el hook de producto ni el instalador. A partir de ahí se evita tener
dos writers sobre las mismas costuras: 7.3 depende de 6.4, 7.5 depende de 6.5 y
7.6 depende de 6.6. Las mutaciones de cada fase acreditan su rama, no la del
otro.

## Decisiones

### D1 — Segunda copia en `~/.grok/hooks/`, no plugin, no compat

Tres alternativas:

- **(a)** segunda copia en `~/.grok/hooks/summonaikit-harness.sh` + JSON de
  registro `~/.grok/hooks/summonaikit.json`;
- **(b)** una copia (`~/.claude/hooks/…`), el JSON de Grok apunta ahí;
- **(c)** plugin bajo `~/.grok/plugins/` (hooks + agents + `GROK_PLUGIN_DATA`).

**Se elige (a).** Mismo razonamiento que Codex D1, con una razón extra:

1. `PROFILE_DIR` sale de `dirname "$HOOK_DIR"`. Con el archivo en
   `~/.grok/hooks/`, la contención de A6 apunta a `~/.grok`, que es donde
   viven `sessions/`. Con (b) apuntaría a `~/.claude` y el transcript de Grok
   quedaría fuera: fail-open permanente, el mismo agujero que zcode aceptó
   porque no tenía opción (el override de proyecto de zcode no corre). Grok
   sí tiene opción.
2. No hay wrapper ajeno que adoptar. El JSON de registro lo escribe este
   repo. (b) ahorra una copia y pierde A6 por nada.
3. (c) pide trust + enable, mueve `PROFILE_DIR` al directorio del plugin
   (otra vez A6 fail-open, salvo código especial), y empaqueta de más. El
   gate es un script bash con tests. El plugin puede ser una tarea posterior
   de empaque; no es esta fase.

Consecuencia para el instalador: `--host grok` **sí escribe el archivo** (a
diferencia de `--host zcode`, que es append-only al user-config y exige que
el dest de Claude ya exista). Primero clasifica **sin escribir** hook, JSON y
agentes; si hook o JSON son desconocidos, termina con todo byte a byte intacto.
Sólo tras ese preflight publica tres cosas, en este orden:

1. el hook en `~/.grok/hooks/summonaikit-harness.sh` (tres estados; primer
   install = AUSENTE);
2. el JSON de registro `~/.grok/hooks/summonaikit.json` (nuestro / ausente /
   desconocido; desconocido no se pisa);
3. los 3 perfiles en `~/.grok/agents/` (mismo contrato que 5.6: un
   desconocido se reporta y se deja; no aborta los otros dos).

Se planta —destino intacto, exit ≠ 0— si el preflight ve hook/JSON desconocido o
si no puede preparar los temporales. Si una publicación posterior falla, hace
rollback con los backups de esta corrida. Un agente desconocido no aborta: se
deja intacto y se continúa con los otros dos, como fija D7.

`--dest` bajo `~/.grok` se habilita **solo** con `--host grok`. `~/.zcode`
sigue rechazado. El mensaje de "una sola copia" que 6.5 ya tiene que
reescribir se vuelve: **el destino lo decide `--host`, y cada host declara
su ruta.**

`compat.claude.hooks` no se toca. El registro de Grok es un JSON propio, no
una importación del de Claude.

### D2 — `HOST=grok` por `GROK_HOOK_EVENT`, primero en el orden

```bash
if   [ -n "${GROK_HOOK_EVENT:-}" ];                         then HOST=grok
elif [ "$SUMMONAIKIT_HOOK_TARGET" = "codex" ];              then HOST=codex   # Phase 6
elif [ -n "${ZCODE_SESSION_ID:-}${ZCODE_PROJECT_DIR:-}" ];  then HOST=zcode
elif [ "${CLAUDECODE:-}" = "1" ];                           then HOST=claude
else                                                              HOST=other
fi
```

**Por qué `GROK_HOOK_EVENT` y no `GROK_SESSION_ID`.** El operador corre Grok
y desde Grok puede lanzar Claude (esta sesión lo hace). Un hijo de Claude
heredaría `GROK_SESSION_ID` del entorno y el hook de Claude se creería Grok
— el mismo error de identidad que Phase 6 D2 cierra en la dirección
inversa. `GROK_HOOK_EVENT` la inyecta el **runner de hooks de Grok** en cada
proceso que él spawnea, y es reservada (un `env` del JSON no puede
pisarla). Un proceso de Claude no la tiene, aunque herede el resto.

Tres propiedades:

1. **Allowlist por presencia, no por valor.** Cualquier valor no vacío cuenta:
   el runner siempre manda el nombre del evento. Un valor que no reconocemos
   como evento no nos importa para `HOST`: si el runner lo setea, el proceso
   es de Grok.
2. **Sin regresión medible.** Claude no setea `GROK_HOOK_EVENT`. zcode tampoco.
   Codex tampoco. Los tres siguen cayendo donde caían.
3. Es la primera vez que `HOST` sale de una variable **del runtime de Grok**,
   no de un wrapper nuestro. Mejor señal que `SUMMONAIKIT_HOOK_TARGET`.

**7.1 lo confirma con evidencia** (no queda *doc*): `GROK_HOOK_EVENT` y
`GROK_SESSION_ID` aparecen en los 37 dumps de env del hook, `CLAUDECODE` está
ausente, y el `env` map del handler entrega `SUMMONAIKIT_HOOK_TARGET=grok` en
todos los eventos. La colisión inversa (Claude hijo de Grok heredando
`GROK_SESSION_ID`) sigue cubierta por no usar esa variable para `HOST`.

El estado queda en `state/grok/<project_key>/…` sin código adicional: sale
del llaveado que la 5.3 ya construyó. `normalizar` de `golden-harness.sh`
acepta host `[a-z]+`; `grok` entra sin tocarla.

A4 (sesión): preferir `GROK_SESSION_ID` del env cuando `HOST=grok` y el
payload no entregó `session_id`/`sessionId`. El env es la vía que el runner
garantiza.

### D3 — `TARGET` y ceremonia, condicionados a la 7.1

El JSON de registro pone `env.SUMMONAIKIT_HOOK_TARGET=grok`. A10 midió que
Claude **no** propaga el prefijo `VAR=val` del comando. El `env` map de Grok
es de primer nivel en el handler.

**Medido en 7.1 — se dio el desenlace fuerte.** De los tres declarados
(originalmente: rol+TARGET ⇒ rama propia; rol sin TARGET ⇒ fallback `claude`;
sin rol ⇒ no se prende), la captura confirmó el primero, por partida doble:

- **El rol llega por tres canales**: `subagentType` de primer nivel en
  `SubagentStart` (`"subagentType":"implementer"` + `subagentId`), el despacho
  `spawn_subagent` **sí emite `PostToolUse`** con `toolInput.subagent_type`
  (a diferencia de Codex, donde el despacho no genera evento), y los eventos
  internos del subagente traen `subagentType` de primer nivel.
- **El `env` map entrega `SUMMONAIKIT_HOOK_TARGET=grok`** en los 37 dumps.

Consecuencia: la ceremonia pasa a `case "$TARGET" in claude|codex|grok)` en
la 7.4, y el matcher del registro puede apoyarse en cualquiera de los tres
canales del rol. El disclaimer histórico queda: prenderla **sin** esta
medición habría convertido el gate de inerte en inservible — A9/A10.

`emit_allow` / `emit_gate_failure` / `systemMessage` son las formas Claude.
Grok las documenta como válidas. Si 7.2 mide que alguna no funciona, nace
`TARGET=grok` con forma propia (como 5.4 invirtió el exit del budget en
zcode). No se adelanta.

Budget: Grok documenta `continue:false` como force-stop, que es lo que
`emit_budget_exhausted` emite hoy para no-zcode. Hipótesis: el exit 0 +
JSON alcanza. Se mide. Si Grok lo ignora, se usa `exit 2` (forma zcode) o
la que 7.2 declare.

### D4 — Lectores camel y `PHASE` entienden el envelope de Grok

Cambio de **Claude también**, no un fork. Cada lector gana el alias camel
como fallback, el snake sigue ganando si llega. Misma postura que
`hookEventName` en 5.4.

| Lector | Alias nuevo |
|---|---|
| `json_top_level_string session_id` | `sessionId` si el snake vino vacío |
| `json_string_field tool_name` | `toolName` |
| `json_tool_input_string` | `clave1` acepta `tool_input` **o** `toolInput` |
| walker `last_assistant_message` | `lastAssistantMessage` |
| `json_string_field transcript_path` | `transcriptPath` (confirmado por 7.1) |

`PHASE` gana los literales que Grok documenta:

```
UserPromptSubmit|beforeSubmitPrompt|user_prompt_submit)  PHASE=prompt
SessionStart|sessionStart|session_start)                 PHASE=session
Stop|stop)                                               PHASE=stop
*)                                                       PHASE=tool
```

**Medido en 7.1:** los literales de hoy son exactamente `user_prompt_submit`,
`post_tool_use`, `subagent_start` y `stop` (valor snake, clave camel
`hookEventName`). El case de arriba ya los cubre.

**Medido en 7.1, y no estaba en ninguna doc:** el `prompt` del payload de
`user_prompt_submit` llega **wrappeado** en `<user_query>…</user_query>` (el
prompt que Grok manda a un subagente va pelado). La detección del sentinel
`-saikit` en la 7.3 tiene que buscarlo **dentro** del wrapper, no anclado al
inicio del campo.

`post_tool_use`, `post_tool_use_failure`, `pre_tool_use`, `subagent_start`,
`subagent_stop` caen en `tool` y eso es lo que se quiere: `record_tool_evidence`
es quien anota roles y runners.

Sin esto, un `user_prompt_submit` real nunca arma. Es el defecto que la 7.3
cierra **aunque la ceremonia no se prenda**.

### D5 — Nombres de tool de Grok cuentan como evidencia

Hoy el review-notice y `implemented` buscan `edit|write|multiedit|…`.
`verified` busca el runner en `tool_name + command`. En Grok (*7.1*, medido):

| Evento | toolName | Qué tiene que contar |
|---|---|---|
| Shell | `run_terminal_command` (alias `Bash`) | `toolInput.command` → evidencia de runner / A11 |
| Edición | `search_replace` (alias `Edit`) **y `write`** (alias `Write`) | `implemented` + review-notice; ambas traen `toolInput.file_path` |
| Delegación | `spawn_subagent` (alias `Task`) | rol en `toolInput.subagent_type` (despacho) y `subagentType` primer nivel (SubagentStart/internos) |

**La expansión de alias del matcher está medida** (*7.1*): una entrada con
matcher estilo Claude (`Bash|Edit|Write|Task`) disparó sobre
`run_terminal_command`, `search_replace`, `write` y `spawn_subagent` reales.
Se pone el nombre nativo **además** del alias, para que el verificador del
registro no alarme en falso y para no depender de que el alias sobreviva un
release. Ojo: la tool de escritura real es `write` (minúscula) — el matcher
canónico la nombra explícitamente.

**Premisa caída (*7.1*): `PostToolUseFailure` no dispara en 1.0.3.** Tres
clases de falla probadas (`exit 1`, binario inexistente, `search_replace` sin
match) y cero eventos `post_tool_use_failure`; qué condición lo dispara queda
`unknown`. Las fallas llegan como **`post_tool_use` con `toolResult` de
error**: `exit_code: 1` en shell, o variantes `{"type":"SearchReplace",…}` /
`FileNotFound` / `NoMatchesFound` en edición. Consecuencia para A11 y la 7.3:
la evidencia de runner rojo se lee del `toolResult` del `PostToolUse`, no de
un evento aparte — sin esa lectura, un runner rojo no deja huella y se
acredita por ausencia. El evento `PostToolUseFailure` **igual se registra** en
el JSON (cuesta cero, y si un release futuro lo emite, la evidencia aparece),
pero ningún gate puede depender de él hoy.

### D6 — El Stop de cierre de sesión no es un gate

Grok dispara un Stop extra al cerrar la sesión. **Medido en 7.1:** el Stop de
turno trae `reason: "end_turn"` (con `promptId` y `lastAssistantMessage`) y el
de cierre trae `reason: "shutdown"` (sin `promptId` ni mensaje) — y el cierre
**también dispara en headless** (`grok -p`, 5 pares de Stops observados).
`channel_closed` no se observó: queda `unknown`, no ausente. La decisión del
hook en el Stop de cierre se parsea y se ignora (*doc*; la 7.2 lo mide en
vivo: la decisión sobre `shutdown` no debe mutar estado ni trabar la salida).

El filtro es **solo `HOST=grok`**. Un Stop de Claude/zcode/Codex no trae
`reason=end_turn` (nunca se midió ese campo ahí); aplicarlo global apagaría
el gate en los hosts que ya funcionan. En Grok, `stop_gate` sale inmediato
(emit_allow, sin tocar estado) salvo `reason == end_turn`. El campo viaja
camel (`reason`); se lee con `json_top_level_string`. La forma medida
(end_turn/shutdown) es la que el filtro clava; si un release futuro cambia el
literal del turno, el filtro se reescribe con lo medido: no se bloquea un Stop
de turno por un filtro más estricto que la realidad.

Tope de 8 continuaciones por turno (*doc*) vs `MAX_CYCLES=2`: no choca. Se
declara para no "arreglarlo".

### D7 — Perfiles de rol: tres estados, el `verifier.md` del operador no se pisa

`--host grok` instala `implementer` / `verifier` / `reviewer` desde `agents/`
del repo a `~/.grok/agents/`, mismo contrato que 5.6: ausente ⇒ escribe;
nuestro (marca `saikit_owned` en frontmatter) ⇒ repara si difiere;
**desconocido ⇒ no toca y lo dice**.

Medido hoy: `~/.grok/agents/verifier.md` existe, no lleva la marca, y no es
byte a byte el del repo. El instalador se planta en ese archivo y sigue con
los otros dos. No se "arregla" a mano desde esta fase. El operador decide
si lo mueve, si le pone la marca, o si el `verifier` de Grok es ése y el
repo no lo reemplaza.

`--quitar-grok` borra solo los que llevan la marca, con backup. El
`verifier.md` del operador sobrevive.

Grok carga `~/.grok/agents/<name>.md` como **agent type** y **también
`<repo>/.grok/agents/<name>.md`** (scope proyecto). Las personas bundled
`implementer` / `reviewer` no ocupan ese namespace. **Medido en 7.1:**
`spawn_subagent` con `subagent_type=implementer` resolvió a un
`implementer.md` temporal colocado en `<repo>/.grok/agents/` del descartable
(debug log: `Loaded role from file role=implementer`), sin tocar
`~/.grok/agents/` y sin colisionar con la persona bundled.

Frontmatter: el del repo trae `tools: Read, Edit, Write, …` (nombres Claude)
y `saikit_owned`. zcode 5.6 midió que esas claves extra no rompen su loader.
En Grok sí hay incompatibilidad medida (*7.1*): un frontmatter con
**`skills:` como string no parsea** (warnings medidos del loader sobre
`~/.claude/agents/*`). Consecuencia: la traducción del frontmatter **de la
copia instalada es obligatoria, no condicional** — la 7.5 la implementa con su
caso de test; la fuente del repo sigue siendo la de Claude/zcode y no se
parte en dos sabores. La 7.5 fija el mapeo exacto (qué claves se traducen o
se omiten) contra el loader real.

Subagentes no anidan (profundidad 1, *doc*). La ceremonia es el lead
spawneando los tres en secuencia. Un rol que intente spawnear a otro falla
en el runtime: no es un defecto del gate.

### D8 — Plugin, `AUDIT MODE`, `-harness-lite` y MODEL CHECK quedan fuera

El plugin de Grok es empaque. Esta fase entrega un hook que corre. Empaquetar
después no cambia el gate.

No se absorbe nada del sabor Codex (D5 de Phase 6). No se toca quality-kit:
su skip por marcador es host-agnostic y el archivo nuestro lo lleva.

## Arquitectura resultante

Una fuente (`hooks/summonaikit-harness.sh`), hasta cuatro hosts, tres rutas
instaladas cuando Phase 6 y Phase 7 cierren:

| Host | Ruta instalada | Señal de `HOST` | `TARGET` | Ceremonia |
|---|---|---|---|---|
| Claude | `~/.claude/hooks/…` | `CLAUDECODE=1` | fallback `claude` | sí |
| zcode | misma copia de Claude | `ZCODE_*` | fallback `claude` | sí |
| Codex | `~/.codex/hooks/…` (Phase 6) | `SUMMONAIKIT_HOOK_TARGET=codex` | `codex` si 6.1 | sí, si 6.1 |
| **Grok** | **`~/.grok/hooks/…` (segunda o tercera copia)** | **`GROK_HOOK_EVENT`** | **`grok` (el env map lo entrega — medido 7.1)** | **sí (habilitada por 7.1)** |
| cursor | no instalado | ninguna ⇒ `other` | no medido | no |

Staging: Grok **sí** corre hooks de proyecto (`<repo>/.grok/hooks/*.json`)
con el repo confiado. El trust se materializa como una entrada en
`~/.grok/trusted_folders.toml` — en TUI la escribe `/hooks-trust`; en
headless no hay flag (`--trust` no existe en 1.0.3, medido en 7.1) y la
entrada se agrega a mano con backup y restore. Es el override que zcode no
tenía. La 7.1 y un
staging pre-prod viven ahí, sin tocar el perfil. El hook del staging deriva
`PROFILE_DIR` de su `$0` (`<repo>/.grok/hooks` ⇒ `<repo>/.grok`), así que
A6 trata los transcripts de `~/.grok/sessions/` como fuera — mismo trade-off
que el staging de Claude (Task 3.6): el gate corre con
`lastAssistantMessage` y el canal transcript queda fail-open. Aceptable y
declarado. El install global no tiene ese agujero.

## Medición primero (7.1 y 7.2)

Ninguna toca el hook de producto, el instalador ni el registro global. Las dos
corren en un repo descartable y sí crean una entrada
de folder trust, que se declara y se revoca al terminar. `capture-payloads.sh` y
`probe-zcode-output.sh` ganan `--host grok` — es andamiaje de
medición, igual que 5.1, no producto. Valen aunque el resto de la fase se
cancele, igual que 5.1/5.2 y 6.1/6.2.

**Medido en 7.1 sobre el trust:** no existe flag `--trust` en 1.0.3 (pese a la
doc), y `GROK_FOLDER_TRUST=0` hace que `grok inspect` diga `Project trusted:
yes` pero **no carga los hooks** (`hook_count=0`). La vía real es la entrada
del repo en `~/.grok/trusted_folders.toml` (único estado global permitido: se
hace con backup, se declara y se restaura byte a byte al terminar). Los hooks
de proyecto **sí corren en headless** (`grok -p`) con ese trust: las 5 rondas
de la 7.1 fueron `grok -p`, sin operador en la TUI.

Grok recarga hooks a mitad de sesión (`r` en `/hooks`). En headless cada
invocación es un proceso nuevo, así que el reload no aplica; en TUI la
captura pide **sesión nueva** después de registrar igual.

### 7.1 — Payloads reales de Grok Build TUI 1.0.3 — **CERRADA (2026-08-13)**

Medida y escrita en `docs/task-7.1-captura.md`: 37 payloads en 5 rondas de
`grok -p` sobre `C:\dev\saikit-captura-grok`, con
`tools/capture-payloads.sh --host grok`. Respuestas clave: literales
`hookEventName` snake en claves camel; rol por tres canales; matcher
alias-expande; `GROK_HOOK_EVENT`/`GROK_SESSION_ID` presentes, `CLAUDECODE`
ausente; `env` map entrega `TARGET`; `transcriptPath` dentro de
`~/.grok/sessions/`; `lastAssistantMessage` presente; `reason` =
`end_turn`/`shutdown`; `PostToolUseFailure` no dispara; agente temporal
resuelve desde `<repo>/.grok/agents/`; formas de `toolInput` medidas. Perfil
byte a byte intacto (cksums antes/después); trust revocado.

**Condición no negociable (vigente para 7.6):** los fixtures de la línea base
se construyen desde estos payloads, no reconstruidos. Lección de la 1.4.

### 7.2 — Contrato de salida

Las 4 formas (`hookSpecificOutput.additionalContext`, `decision:block`,
`continue:false`+`stopReason`, `systemMessage`) más `exit 2` en el `Stop`,
un turno cada una. Se reusa `tools/probe-zcode-output.sh` con un
`--host grok` que registra en el proyecto descartable, no en un user-config
global.

Lo que la 7.2 hereda de la 7.1 (medido, no se re-litiga):

- El `command` del JSON se emite en forma PowerShell (`& "<bash.exe>"
  "<probe>"`), no estilo zcode — el shell de hooks en Windows es
  powershell.exe.
- El trust del repo descartable se hace por `trusted_folders.toml`
  (backup + restore), no por flag ni env var.
- `grok -p` headless corre los hooks de proyecto: la 7.2 se mide en turnos
  headless, sin operador adelante (a diferencia de la 5.2).
- El Stop de cierre (`reason=shutdown`) dispara también en headless: la DoD
  de "el Stop de cierre ignora la decisión sin mutar estado" se mide en el
  mismo turno que el Stop `end_turn`, no pide una sesión aparte.
- Los transcripts viven en `~/.grok/sessions/<cwd-encoded>/<uuid>/`
  (`updates.jsonl`, `chat_history.jsonl`): son el oráculo para buscar el nonce
  de `additionalContext`, junto al `--debug-file` del propio proceso.

**Hipótesis de trabajo, declarada como tal:** Grok honra el vocabulario
Claude (*doc*). Es una creencia, no una medición. La 5.2 encontró que
`continue:false`+exit 0 era ignorado en zcode; la 7.2 existe por eso.

## Instalador y registro

**`--host grok`** (D1). Tres estados en el hook y en el JSON. Escritura
atómica del hook (`bash -n` sobre temporal, `cmp`, `mv` en el mismo dir).
El JSON se escribe entero por este repo (no es append a un archivo ajeno):
si es nuestro o ausente, se publica el canónico; si es desconocido, se
planta. Identidad de "nuestro": el archivo se llama `summonaikit.json` **y**
lleva `"saikit_owned": "summonaikit-claude"` en el objeto raíz. **Medido en
7.1:** el loader tolera la clave top-level de marcado — el JSON de captura la
llevaba y sus hooks dispararon las 37 veces. El hook sigue identificándose
por el marcador de la línea 2.

**Premisa caída (7.1), y cambia el JSON de abajo:** el shell que ejecuta los
hooks en Windows es **powershell.exe** (log del runtime:
`xai_grok_config::shell: Windows shell: powershell.exe`). La forma estilo
zcode (`"exe" "script"`) muere con exit 1 bajo PowerShell, y un redirect
escribiría UTF-16LE. El `command` canónico es la forma de invocación de
PowerShell: `& "<bash.exe>" "<hook>"`.

Registro canónico (forma medida por 7.1; los timeouts los fija 7.5 si hace
falta otro set):

```json
{
  "saikit_owned": "summonaikit-claude",
  "hooks": {
    "UserPromptSubmit": [{
      "hooks": [{
        "type": "command",
        "command": "& \"C:\\Program Files\\Git\\bin\\bash.exe\" \"<abs>\\summonaikit-harness.sh\"",
        "timeout": 30,
        "env": { "SUMMONAIKIT_HOOK_TARGET": "grok" }
      }]
    }],
    "PostToolUse": [{
      "matcher": "Bash|Edit|Write|apply_patch|Task|Agent|spawn_subagent|run_terminal_command|search_replace|write",
      "hooks": [{
        "type": "command",
        "command": "& \"C:\\Program Files\\Git\\bin\\bash.exe\" \"<abs>\\summonaikit-harness.sh\"",
        "timeout": 30,
        "env": { "SUMMONAIKIT_HOOK_TARGET": "grok" }
      }]
    }],
    "PostToolUseFailure": [{
      "matcher": "Bash|run_terminal_command",
      "hooks": [{
        "type": "command",
        "command": "& \"C:\\Program Files\\Git\\bin\\bash.exe\" \"<abs>\\summonaikit-harness.sh\"",
        "timeout": 30,
        "env": { "SUMMONAIKIT_HOOK_TARGET": "grok" }
      }]
    }],
    "SubagentStart": [{
      "hooks": [{
        "type": "command",
        "command": "& \"C:\\Program Files\\Git\\bin\\bash.exe\" \"<abs>\\summonaikit-harness.sh\"",
        "timeout": 30,
        "env": { "SUMMONAIKIT_HOOK_TARGET": "grok" }
      }]
    }],
    "Stop": [{
      "hooks": [{
        "type": "command",
        "command": "& \"C:\\Program Files\\Git\\bin\\bash.exe\" \"<abs>\\summonaikit-harness.sh\"",
        "timeout": 600,
        "env": { "SUMMONAIKIT_HOOK_TARGET": "grok" }
      }]
    }]
  }
}
```

`PostToolUseFailure` queda registrado pese a que 7.1 midió que **no dispara**
en 1.0.3 (D5): cuesta cero y si un release futuro lo emite, la evidencia
aparece. Ningún gate depende de él hoy.

**El bloque de arriba es JSON válido a propósito** (salvo el placeholder
`<abs>`, que va adentro de un string): es la plantilla que la 7.5 va a
consumir, y un comentario `/* … */` la volvería imparseable en el primer
`jq`. Por eso las entradas se repiten enteras en vez de abreviarse.

`SubagentStart` va **sin matcher** deliberadamente: vacío significa todos los
tipos de subagente. `Stop` timeout 600 s es el default de Grok para gates
(*doc*); se pone explícito. Matcher en `UserPromptSubmit`/`Stop` no se pone:
Grok lo ignora con warning (*doc*). `SubagentStop` no se registra: la ceremonia corre en
el lead (Stop del padre), no en el hijo. `SubagentStart` sí, porque es el
canal limpio del rol.

`check-hook-registration.sh` gana `--grok-hooks-dir` (default
`~/.grok/hooks`). Tres afirmaciones **separadas**, no colapsadas:

1. existe un JSON que nombra al hook (no basta con mencionarlo: misma
   lección de 0.4);
2. el archivo que nombra existe y lleva el marcador de propiedad;
3. el matcher de `PostToolUse` cubre la herramienta de delegación
   (`spawn_subagent` o su alias `Task`).

Exit 0 siempre. Lo que no se pudo mirar es `unknown`. Contrato intacto.

No hay entrada nueva en `vendor-manifest.sha256`: no hay vendor. Si 7.1
encuentra un harness ajeno en esa ruta, se reabre D1 y se gana el hash
antes de instalar.

`--restore-vendor` sobre un dest que nunca fue vendor ⇒ exit 6, no toca.
Correcto. La vuelta atrás de Grok es `--quitar-grok` (saca JSON nuestro +
hook nuestro + agentes con marca), no restaurar un vendor que no existió.

## Testing

**Línea base dorada.** zcode tomó 17–25; Codex reserva 26+. Como 7.6 depende de
6.6, Grok toma **el siguiente bloque libre en master después del bloque Codex**,
no un número clavado hoy. Un escenario por gate, mitad que pasa y mitad que
bloquea. Construidos desde 7.1.

El token de filename `grok` exporta `GROK_HOOK_EVENT=stop` (o el evento del
paso), `GROK_SESSION_ID=…` y `SUMMONAIKIT_HOOK_TARGET=grok` — 7.1 midió que el
env map lo entrega de verdad, así que no es un `TARGET` inventado. Misma
disciplina que el token `zcode` (5.5): el arnés reproduce la señal del
runtime, no la que nos gustaría.

**Mutaciones.** Tres nuevas, cada una con su caso:

| Mutación | Qué rompe | Quién la atrapa |
|---|---|---|
| `mut_host_grok_sin_rama` | revierte `HOST=grok` (D2) | aislamiento de estado grok↔claude |
| `mut_phase_sin_snake` | saca `user_prompt_submit` del case (D4) | armado con envelope Grok |
| `mut_ceremonia_sin_grok` | vuelve a `[ "$TARGET" = "claude" ]` (D3 prendió `TARGET=grok` — 7.1) | ceremonia en target grok |

Las tres existen: D3 prendió `TARGET=grok` con evidencia de 7.1.

`test_install_hook.sh` gana los tres estados con `--host grok` (hook + JSON
+ agentes). `test_hook_registration.sh` gana las tres afirmaciones.
`tests/fixtures/arnes-falso/escenarios/0N-grok/` espeja al `03-zcode`.
Fixtures nuevos por `test_fixtures_json.sh` (parseo **y** fidelidad de
rutas).

## La forma de la fase

| | Tarea | Toca el perfil Grok | Valor si se cancela el resto |
|---|---|---|---|
| 7.1 | Capturar payloads reales — **cerrada 2026-08-13** | no (repo descartable + trust declarado/revocado) | dice si la ceremonia es siquiera posible: **sí** |
| 7.2 | Medir el contrato de salida | no (mismo descartable) | dice si el bloqueo funciona |
| 7.3 | D2 + D4 + D5 + D6 (HOST, PHASE, camel, tools, reason), después de 6.4 | no (código + tests) | Claude/zcode ganan lectores camel; un envelope Grok deja de caer a `PHASE=tool` |
| 7.4 | Ceremonia (D3) — **habilitada por 7.1** | no (código + tests) | — |
| 7.5 | `--host grok` + verificador del registro + agentes (D1, D7), después de 6.5 | no (código + tests) | — |
| 7.6 | Línea base del target + instalar + turno real, después de 6.6 | **sí** | — |

El harness global de Grok no se instala hasta la 7.6. 7.1/7.2 sólo dejan el
folder trust explícitamente declarado para el repo descartable y lo revocan al
terminar.

**7.1/7.2 no dependen de que Phase 6 cierre.** El código y el release sí se
serializan detrás de 6.4/6.5/6.6 para evitar conflictos y colisión de números.
Phase 5 está cerrada (5.1–5.6 en `cc:完了`). Las piezas que se reusan: línea
base por target (5.5), segunda forma de registro en el instalador (5.4),
perfiles de agente con tres estados (5.6), probe de salida (5.2) y captura
(5.1).

## Puesta en producción

Staging en repo descartable (`<repo>/.grok/hooks/` + entrada en
`trusted_folders.toml`, declarada y revocada), después install global con
`--host grok`. A diferencia de Codex 6.6 (directo
al perfil por decisión del operador), acá el override de proyecto **sí
corre**, así que el staging es real y se usa.

Red de seguridad: backup fechado del hook y del JSON antes de publicar;
`--quitar-grok` para sacar lo nuestro sin tocar el `verifier.md` ajeno.

Tras el install: sesión nueva de Grok en un repo cualquiera. Prompt con
`-saikit` arma (estado bajo `~/.grok/hooks/state/grok/…`); prompt pelado no
crea nada. `~/.claude/hooks/` se verifica byte a byte intacto.

## Non-Goals y límites declarados

- **`.cursor` y `.agents` quedan fuera.** Su divergencia sigue declarada.
- **Phase 6 no cambia de alcance.** Su 6.4 sólo gana la obligación de preservar
  el orden compuesto si la rama Grok ya existe; 7.3/7.5/7.6 se serializan detrás
  de las costuras equivalentes de Codex.
- **No se prende `compat.claude.hooks`.** El registro es un JSON propio.
- **No se empaqueta como plugin.** Empaque ≠ gate.
- **No se absorbe `AUDIT MODE`, `-harness-lite`, ni MODEL CHECK.**
- **No se toca quality-kit.**
- **No se pisa `~/.grok/agents/verifier.md` del operador.**
- **El gate sigue siendo advisory.** Quien controla el texto del turno
  sigue pudiendo nombrar un rol en el `toolInput`, citar un runner sin
  correrlo, u omitir un subagente de solo lectura.
- **No se traduce el contrato inyectado al dialecto de tools de Grok**
  salvo que 7.1 mida que el modelo no entiende `Task` / `Bash` (los alias
  del runtime cubren el matcher; el texto del contrato es otra superficie).
  Si hace falta, es una tarea propia y se declara.

## Riesgos

| Riesgo | Mitigación |
|---|---|
| ~~7.1 mide que el rol no llega~~ **No se dio** (7.1: el rol llega por 3 canales) | D3 se prende; riesgo cerrado |
| 7.2 mide que Grok ignora `decision:block` y `exit 2` ⇒ el gate es decorativo | Se declara con evidencia y se decide si hace falta forma propia |
| ~~Grok setea `CLAUDECODE=1`~~ **No se dio** (7.1: ausente en los 37 dumps) | D2 pone `GROK_HOOK_EVENT` primero; si un release lo prende, Grok igual gana |
| Claude lanzado desde Grok hereda `GROK_SESSION_ID` | D2 no usa esa variable para `HOST` |
| `~/.grok/agents/verifier.md` del operador bloquea D7 | Fail-closed en ese archivo, declarado. Los otros dos se instalan |
| Un release de Grok cambia `hookEventName` de `user_prompt_submit` a `UserPromptSubmit` | D4 acepta las dos. 7.1 clavó la de hoy (snake) |
| 6.4 y 7.3 pelean el chain de `HOST` | `Depends` serializa 7.3 detrás de 6.4; orden compuesto y mutaciones acreditan cada rama |
| Folder-trust en el staging | **Medido (7.1):** no hay flag `--trust`; la vía es la entrada en `trusted_folders.toml` (declarada y revocada). El install global no pide trust (hooks de `~/.grok/hooks/` son always-trusted, *doc*) |
