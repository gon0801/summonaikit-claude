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
están marcadas *doc*; las que salen de archivos del operador en disco, *disco*.
Ninguna de las *doc* sustituye a la captura 7.1.

### El runtime ya tiene el seam

| Pieza del kit | En Grok (*doc*, user-guide 10/16) |
|---|---|
| Armado | `UserPromptSubmit` + `hookSpecificOutput.additionalContext` |
| Evidencia | `PostToolUse` (éxito) y `PostToolUseFailure` (falla) |
| Bloqueo | `{"decision":"block","reason"}`, `exit 2`, `continue:false`+`stopReason` |
| Ceremonia | `spawn_subagent` + eventos `SubagentStart` / `SubagentStop` |
| Señal de proceso | `GROK_HOOK_EVENT`, `GROK_SESSION_ID`, `GROK_WORKSPACE_ROOT` (inyectadas por el runner, reservadas) |
| Alias Claude | `Bash`→`run_terminal_command`, `Task`→`spawn_subagent`, `Edit`/`Write`→`search_replace` |
| Roles custom | `~/.grok/agents/<name>.md` |

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
| Personas bundled `implementer` / `reviewer` | Son **personas**, no agent types. Built-ins de tipo: `general-purpose`, `explore`, `plan` | no hay colisión de tipo; se verifica en 7.1 |

No hay un harness vendor en `~/.grok`. No hay manifiesto que ganar. El primer
install es destino **AUSENTE**, no VENDOR_CONOCIDO. Eso simplifica 7.5 frente
a 6.5.

### Por qué no prender `compat.claude.hooks`

Si se prendiera, Grok cargaría el comando registrado en
`~/.claude/settings.json` (el hook vivo de Claude). Ese archivo, hoy:

1. Resuelve `HOST=other` (no hay `ZCODE_*` ni `CLAUDECODE=1` en un proceso
   Grok — *doc*; se confirma en 7.1).
2. Deja `TARGET` vacío ⇒ la ceremonia no corre.
3. Lee `session_id` / `tool_input` / `last_assistant_message` / `tool_name`
   en snake. El envelope de Grok es camel (`sessionId`, `toolInput`,
   `lastAssistantMessage`, `toolName`) y `hookEventName` vale
   `"pre_tool_use"` / `"user_prompt_submit"` / `"stop"` (*doc*, ejemplo
   oficial). `PHASE` ya entiende `hookEventName` y el literal `stop` (5.4);
   **no** entiende `user_prompt_submit` ⇒ el armado cae a `PHASE=tool` y el
   sentinel nunca dispara.
4. El review-notice busca `edit\|write\|multiedit`. En Grok la edición es
   `search_replace`.

Resultado: un gate que o no arma, o arma y no ve evidencia, o ve evidencia y
no exige roles. Peor que no tenerlo. `hooks = false` se queda.

### Lo que el hook actual no lee (código, 2026-08-13)

Lectores que ya tienen fallback camel (lección zcode 5.4):

- `hookEventName` (PHASE)
- `subagentType` (dentro de `json_tool_input_string`, que igual exige la clave
  padre `tool_input` en snake)

Lectores que **no** tienen fallback y Grok necesita:

| Campo Claude | Campo Grok (*doc*) | Quién lo lee hoy |
|---|---|---|
| `session_id` | `sessionId` | `json_top_level_string session_id` (A4) |
| `tool_name` | `toolName` | `json_string_field tool_name` |
| `tool_input` (objeto padre) | `toolInput` | `json_tool_input_string` compara `clave1 == "tool_input"` |
| `last_assistant_message` | `lastAssistantMessage` | walker del Stop (A2/A8) |
| `transcript_path` | ¿`transcriptPath`? | `json_string_field` + contención A6. **Nombre no afirmado** — 7.1 |
| `command` / `file_path` | `toolInput.command` / ¿`path`? | evidencia y review-notice |

`GROK_SESSION_ID` llega por env (*doc*). Eso cubre A4 aunque `sessionId` del
payload no se lea: el slot de sesión se puede construir del env. No exime de
leer el payload: el env es la vía limpia, el payload es la vía que el resto
de hosts ya usa.

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

El estado queda en `state/grok/<project_key>/…` sin código adicional: sale
del llaveado que la 5.3 ya construyó. `normalizar` de `golden-harness.sh`
acepta host `[a-z]+`; `grok` entra sin tocarla.

A4 (sesión): preferir `GROK_SESSION_ID` del env cuando `HOST=grok` y el
payload no entregó `session_id`/`sessionId`. El env es la vía que el runner
garantiza.

### D3 — `TARGET` y ceremonia, condicionados a la 7.1

El JSON de registro pone `env.SUMMONAIKIT_HOOK_TARGET=grok`. A10 midió que
Claude **no** propaga el prefijo `VAR=val` del comando. El `env` map de Grok
es de primer nivel en el handler (*doc*). Eso se **mide** en 7.1, no se
cree.

Tres desenlaces, declarados:

| 7.1 mide | Qué se prende |
|---|---|
| El rol llega (vía `toolInput.subagent_type` / `subagentType` / `SubagentStart`) **y** el `env` map entrega `TARGET=grok` | `case "$TARGET" in claude\|codex\|grok)` en la ceremonia |
| El rol llega, el `env` map **no** entrega `TARGET` | fallback: `HOST=grok` ⇒ `TARGET=claude` (patrón zcode 5.4). La ceremonia ya corre. No se inventa `TARGET=grok` |
| El rol **no** llega | La ceremonia **no se prende**. `HOST=grok` igual aísla estado. Queda escrito como límite, no como pendiente |

**El cambio de ceremonia no se hace antes de la medición.** Prenderla sin el
rol convierte el gate de inerte en inservible — A9/A10, otra vez.

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
| `json_string_field transcript_path` | `transcriptPath` (si 7.1 lo confirma) |

`PHASE` gana los literales que Grok documenta:

```
UserPromptSubmit|beforeSubmitPrompt|user_prompt_submit)  PHASE=prompt
SessionStart|sessionStart|session_start)                 PHASE=session
Stop|stop)                                               PHASE=stop
*)                                                       PHASE=tool
```

`post_tool_use`, `post_tool_use_failure`, `pre_tool_use`, `subagent_start`,
`subagent_stop` caen en `tool` y eso es lo que se quiere: `record_tool_evidence`
es quien anota roles y runners.

Sin esto, un `user_prompt_submit` real nunca arma. Es el defecto que la 7.3
cierra **aunque la ceremonia no se prenda**.

### D5 — Nombres de tool de Grok cuentan como evidencia

Hoy el review-notice y `implemented` buscan `edit|write|multiedit|…`.
`verified` busca el runner en `tool_name + command`. En Grok:

| Evento | toolName (*doc*) | Qué tiene que contar |
|---|---|---|
| Shell | `run_terminal_command` (alias `Bash`) | `command` → evidencia de runner / A11 |
| Edición | `search_replace` (alias `Edit`/`Write`) | `implemented` + review-notice |
| Delegación | `spawn_subagent` (alias `Task`) | rol, si viaja en `toolInput` |

El matcher del JSON registra `Bash|Edit|Write|apply_patch|Task|Agent|spawn_subagent|run_terminal_command|search_replace`.
Grok alias-expande en el matcher (*doc*): `Bash` ya pega a
`run_terminal_command`. Se pone el nombre nativo **además** del alias, para
que el verificador del registro no alarme en falso y para no depender de que
el alias sobreviva un release.

`PostToolUseFailure` se registra como evento propio, mismo comando. En Grok
`PostToolUse` **no dispara en falla** (*doc*). Sin este evento, A11 es
invisible: un runner rojo no deja huella y se acredita por ausencia. El
payload de falla es *doc*-conocido (`toolName`, resultado); la forma exacta
la fija 7.1.

### D6 — El Stop de cierre de sesión no es un gate

Grok dispara un Stop extra al cerrar la sesión (`reason` =
`channel_closed` / `shutdown`). La decisión se parsea y se ignora (*doc*).
Si el hook no filtra, cuenta un ciclo o limpia estado al salir.

El filtro es **solo `HOST=grok`**. Un Stop de Claude/zcode/Codex no trae
`reason=end_turn` (nunca se midió ese campo ahí); aplicarlo global apagaría
el gate en los hosts que ya funcionan. En Grok, `stop_gate` sale inmediato
(emit_allow, sin tocar estado) salvo `reason == end_turn`. El campo viaja
camel (`reason`); se lee con `json_top_level_string`. Si 7.1 mide que el
Stop de turno **no** trae `reason` (o trae otro literal), el filtro se
reescribe con lo medido: no se bloquea un Stop de turno por un filtro más
estricto que la realidad.

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

Grok carga `~/.grok/agents/<name>.md` como **agent type**. Las personas
bundled `implementer` / `reviewer` no ocupan ese namespace (*doc*). 7.1
confirma que `spawn_subagent` con `subagent_type=implementer` resuelve al
archivo user-level y no a la persona.

Frontmatter: el del repo trae `tools: Read, Edit, Write, …` (nombres Claude)
y `saikit_owned`. zcode 5.6 midió que esas claves extra no rompen su loader.
Grok documenta alias de tools. Si 7.1 mide que el loader rechaza una clave o
un nombre de tool, se adapta el frontmatter **de la copia instalada**, no se
parte la fuente en dos sabores. La fuente del repo sigue siendo la de
Claude/zcode; el instalador puede traducir `tools:` al escribir el dest, si
hace falta. Esa traducción, de existir, tiene su caso.

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
| **Grok** | **`~/.grok/hooks/…` (segunda o tercera copia)** | **`GROK_HOOK_EVENT`** | **`grok` si el env map llega; si no, fallback `claude` si 7.1 habilita** | **sí, si 7.1 lo habilita** |
| cursor | no instalado | ninguna ⇒ `other` | no medido | no |

Staging: Grok **sí** corre hooks de proyecto (`<repo>/.grok/hooks/*.json`)
tras `/hooks-trust` (*doc*). Es el override que zcode no tenía. La 7.1 y un
staging pre-prod viven ahí, sin tocar el perfil. El hook del staging deriva
`PROFILE_DIR` de su `$0` (`<repo>/.grok/hooks` ⇒ `<repo>/.grok`), así que
A6 trata los transcripts de `~/.grok/sessions/` como fuera — mismo trade-off
que el staging de Claude (Task 3.6): el gate corre con
`lastAssistantMessage` y el canal transcript queda fail-open. Aceptable y
declarado. El install global no tiene ese agujero.

## Medición primero (7.1 y 7.2)

Ninguna toca el hook de producto, el instalador ni el registro global. Las dos
corren en un repo descartable con el operador adelante y sí crean una entrada
de folder trust, que se declara y se revoca al terminar. `capture-payloads.sh` y
`probe-zcode-output.sh` pueden ganar `--host grok` — es andamiaje de
medición, igual que 5.1, no producto. Valen aunque el resto de la fase se
cancele, igual que 5.1/5.2 y 6.1/6.2.

Grok recarga hooks a mitad de sesión (`r` en `/hooks`). Aun así la captura
pide **sesión nueva** después de registrar: no se afirma que el reload
alcance para un envelope limpio hasta medirlo.

### 7.1 — Payloads reales de Grok Build TUI 1.0.3

Registro **solo** en `<repo-descartable>/.grok/hooks/`. No se toca
`~/.grok/hooks/` ni `config.toml`. Hace falta `/hooks-trust` (o `--trust`)
en ese repo. `tools/capture-payloads.sh` gana `--host grok` que escribe ese
JSON (mismo binario, tercer modo de install).

Un turno `-saikit` más los disparos dirigidos necesarios para capturar
`UserPromptSubmit`, `PostToolUse` exitoso, `PostToolUseFailure`,
`SubagentStart`, `Stop reason=end_turn` y el Stop de cierre. Preguntas, cada una
con una decisión colgando:

| Pregunta | Qué decide |
|---|---|
| ¿`hookEventName` es `user_prompt_submit` / `stop` / `pre_tool_use`? | D4 (PHASE) |
| ¿Cómo se llama la herramienta de subagentes y **en qué campo viaja el rol**? ¿`SubagentStart` lo trae? | Si D3 se prende, y por qué canal |
| ¿El matcher `Bash\|…\|Task` alias-expande a `spawn_subagent` de verdad? | La otra mitad de A9 |
| ¿`GROK_HOOK_EVENT` y `GROK_SESSION_ID` están en el env del hook? ¿`CLAUDECODE` también? | D2 entera |
| ¿El `env` map entrega `SUMMONAIKIT_HOOK_TARGET=grok`? | D3, rama TARGET |
| ¿Hay `transcript_path` / `transcriptPath`? ¿Apunta adentro de `~/.grok/sessions/`? | A6 contiene o fail-open |
| ¿`lastAssistantMessage` viaja en el Stop? | Si el canal 1 del recibo vive |
| ¿`reason` en el Stop de turno es `end_turn`? ¿El de cierre es otro? | D6 |
| ¿`PostToolUseFailure` existe y qué trae? | D5 / A11 |
| ¿`subagent_type=implementer` resuelve a `~/.grok/agents/implementer.md` (habrá que poner uno temporal en el descartable)? | D7 |
| Forma exacta (`toolInput.command` vs `command`, path de edición) | Lectores de evidencia |

**Condición no negociable:** los fixtures de la línea base se construyen
desde estos payloads, no reconstruidos. Lección de la 1.4.

### 7.2 — Contrato de salida

Las 4 formas (`hookSpecificOutput.additionalContext`, `decision:block`,
`continue:false`+`stopReason`, `systemMessage`) más `exit 2` en el `Stop`,
un turno cada una. Se reusa `tools/probe-zcode-output.sh` con un
`--host grok` que registra en el proyecto descartable, no en un user-config
global.

**Hipótesis de trabajo, declarada como tal:** Grok honra el vocabulario
Claude (*doc*). Es una creencia, no una medición. La 5.2 encontró que
`continue:false`+exit 0 era ignorado en zcode; la 7.2 existe por eso.

## Instalador y registro

**`--host grok`** (D1). Tres estados en el hook y en el JSON. Escritura
atómica del hook (`bash -n` sobre temporal, `cmp`, `mv` en el mismo dir).
El JSON se escribe entero por este repo (no es append a un archivo ajeno):
si es nuestro o ausente, se publica el canónico; si es desconocido, se
planta. Identidad de "nuestro": el archivo se llama `summonaikit.json` **y**
lleva `"saikit_owned": "summonaikit-claude"` en el objeto raíz. Grok ignora
claves de evento que no reconoce (*doc*); una clave top-level de marcado es
la apuesta, y si 7.1 mide que el loader rechaza claves extra, la identidad
pasa a ser "filename + byte-igual al canónico generado" — se declara en la
7.5, no se inventa un parser. El hook sigue identificándose por el marcador
de la línea 2.

Registro canónico (forma; los matchers y timeouts los fija 7.1 si la
medición pide otro set):

```json
{
  "saikit_owned": "summonaikit-claude",
  "hooks": {
    "UserPromptSubmit": [{
      "hooks": [{
        "type": "command",
        "command": "<abs>/summonaikit-harness.sh",
        "timeout": 30,
        "env": { "SUMMONAIKIT_HOOK_TARGET": "grok" }
      }]
    }],
    "PostToolUse": [{
      "matcher": "Bash|Edit|Write|apply_patch|Task|Agent|spawn_subagent|run_terminal_command|search_replace",
      "hooks": [{
        "type": "command",
        "command": "<abs>/summonaikit-harness.sh",
        "timeout": 30,
        "env": { "SUMMONAIKIT_HOOK_TARGET": "grok" }
      }]
    }],
    "PostToolUseFailure": [{
      "matcher": "Bash|run_terminal_command",
      "hooks": [{
        "type": "command",
        "command": "<abs>/summonaikit-harness.sh",
        "timeout": 30,
        "env": { "SUMMONAIKIT_HOOK_TARGET": "grok" }
      }]
    }],
    "SubagentStart": [{
      "hooks": [{
        "type": "command",
        "command": "<abs>/summonaikit-harness.sh",
        "timeout": 30,
        "env": { "SUMMONAIKIT_HOOK_TARGET": "grok" }
      }]
    }],
    "Stop": [{
      "hooks": [{
        "type": "command",
        "command": "<abs>/summonaikit-harness.sh",
        "timeout": 600,
        "env": { "SUMMONAIKIT_HOOK_TARGET": "grok" }
      }]
    }]
  }
}
```

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
paso) y `GROK_SESSION_ID=…`, **no** un `TARGET=grok` inventado, salvo que
7.1 haya medido que el env map lo entrega de verdad. Misma disciplina que
el token `zcode` (5.5): el arnés reproduce la señal del runtime, no la que
nos gustaría.

**Mutaciones.** Tres nuevas, cada una con su caso:

| Mutación | Qué rompe | Quién la atrapa |
|---|---|---|
| `mut_host_grok_sin_rama` | revierte `HOST=grok` (D2) | aislamiento de estado grok↔claude |
| `mut_phase_sin_snake` | saca `user_prompt_submit` del case (D4) | armado con envelope Grok |
| `mut_ceremonia_sin_grok` | (solo si D3 prendió `TARGET=grok`) vuelve a `[ "$TARGET" = "claude" ]` | ceremonia en target grok |

Si D3 no prende `TARGET=grok` y cae al fallback `claude`, la tercera
mutación no existe: no hay rama que revertir. No se inventa cobertura.

`test_install_hook.sh` gana los tres estados con `--host grok` (hook + JSON
+ agentes). `test_hook_registration.sh` gana las tres afirmaciones.
`tests/fixtures/arnes-falso/escenarios/0N-grok/` espeja al `03-zcode`.
Fixtures nuevos por `test_fixtures_json.sh` (parseo **y** fidelidad de
rutas).

## La forma de la fase

| | Tarea | Toca el perfil Grok | Valor si se cancela el resto |
|---|---|---|---|
| 7.1 | Capturar payloads reales | no (repo descartable + `/hooks-trust`) | dice si la ceremonia es siquiera posible |
| 7.2 | Medir el contrato de salida | no (mismo descartable) | dice si el bloqueo funciona |
| 7.3 | D2 + D4 + D5 + D6 (HOST, PHASE, camel, tools, reason), después de 6.4 | no (código + tests) | Claude/zcode ganan lectores camel; un envelope Grok deja de caer a `PHASE=tool` |
| 7.4 | Ceremonia (D3), si 7.1 habilita | no (código + tests) | — |
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

Staging en repo descartable (`<repo>/.grok/hooks/` + `/hooks-trust`),
después install global con `--host grok`. A diferencia de Codex 6.6 (directo
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
| 7.1 mide que el rol no llega ⇒ la ceremonia no se puede exigir | D3 no se prende. El resto (HOST, PHASE, camel, A6, install) sigue valiendo |
| 7.2 mide que Grok ignora `decision:block` y `exit 2` ⇒ el gate es decorativo | Se declara con evidencia y se decide si hace falta forma propia |
| Grok setea `CLAUDECODE=1` (*no documentado*) | D2 pone `GROK_HOOK_EVENT` primero. 7.1 lo confirma. Si ambas están, Grok gana |
| Claude lanzado desde Grok hereda `GROK_SESSION_ID` | D2 no usa esa variable para `HOST` |
| `~/.grok/agents/verifier.md` del operador bloquea D7 | Fail-closed en ese archivo, declarado. Los otros dos se instalan |
| Un release de Grok cambia `hookEventName` de `user_prompt_submit` a `UserPromptSubmit` | D4 acepta las dos. 7.1 clava la de hoy |
| 6.4 y 7.3 pelean el chain de `HOST` | `Depends` serializa 7.3 detrás de 6.4; orden compuesto y mutaciones acreditan cada rama |
| Folder-trust: el operador olvida `/hooks-trust` en el staging | 7.1 no afirma captura si `/hooks` no lista el JSON. El install global no pide trust (hooks de `~/.grok/hooks/` son always-trusted, *doc*) |
