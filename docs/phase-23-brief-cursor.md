# Brief para Cursor: Phase 23, dos PRs para Muse Code como quinto host

Este documento es para ti, Cursor. Vas a implementar dos entregas de
`Plans.md` en `summonaikit-claude`: un PR para la fila 23.2 y otro PR, con las
filas 23.3 y 23.4 juntas (tocan el mismo archivo y no se apilan). El operador
no está mirando y no se le pregunta nada. Si algo no se resuelve con este
brief, la fila de `Plans.md` y `AGENTS.md`, sigue la tabla **Cuando algo se
atora**. Nunca te quedes esperando una respuesta.

**Qué es el producto.** Un hook de bash, `hooks/summonaikit-harness.sh`, que
gatea cada turno de un agente de código, más su instalador
`tools/install-hook.sh`. Hoy corre en Claude Code, zcode, Codex, Grok y dsh.
Muse Code es el CLI de código de Meta y va a ser el quinto host.

**Qué ya está medido.** Todo lo que necesitas saber de Muse está en
`docs/task-23.1-captura-muse.md`, con evidencia en
`docs/evidence/phase-23/23.1/`. Léelo entero antes de escribir código. No
vuelvas a medir Muse con el modelo real: eso gasta créditos del operador y está
negado.

## Quién

| Rol | Quién | Qué hace |
|---|---|---|
| Implementador | Tú, Cursor | Las dos entregas, un PR por entrega, hasta CI verde |
| Lead | La sesión de Claude del operador | Revisa cada PR una vez; hace las corridas con Muse real |
| Revisores automáticos | CodeRabbit y el job `gate` del CI | Corren solos en cada PR |
| Operador | El dueño del repo | Solo mergea. Es su única acción |

## Arranque

1. Confirma que estás en el repo correcto, que este brief y la evidencia ya
   están en master, y que la fila de `Plans.md` que vas a seguir es la
   versión nueva:

   ```bash
   cd /Users/dn/dev/summonaikit-claude
   git fetch origin
   ok=1
   for f in docs/phase-23-brief-cursor.md docs/evidence/phase-23/23.1/complementarias/validacion-settings.txt; do
     git cat-file -e "origin/master:$f" 2>/dev/null || { echo "FALTA $f"; ok=0; }
   done
   [ "$ok" = 1 ] && git show origin/master:Plans.md | grep -q 'SAIKIT_MUSE_BIN' && echo BRIEF_EN_MASTER
   ```

   Si no imprime `BRIEF_EN_MASTER`, para y reporta: el PR de este brief no se
   ha mergeado.

2. Lee en este orden: `AGENTS.md` (sección **Protocolo de entrega**), las
   filas 23.2, 23.3 y 23.4 de `Plans.md`, y `docs/task-23.1-captura-muse.md`
   completo, con su sección de mediciones complementarias.

**Qué documento gana.** La fila de `Plans.md` es el contrato. Si este brief la
contradice, gana la fila y lo reportas en el PR. `AGENTS.md` fija el protocolo
de entrega y este brief no lo repite.

**Máquina.** La Mac del operador, Darwin arm64, con Muse instalado. Usa siempre
`/opt/homebrew/bin/bash`: el bash 3.2 de macOS no parsea el hook.

## Permisos

| Operación | Decisión |
|---|---|
| Crear ramas desde `origin/master`, commitear y hacer push de TUS ramas | Aprobado |
| Abrir PRs contra `master` | Aprobado |
| Correr tests sueltos, `pre-commit` y mutaciones acotadas | Aprobado |
| Correr Muse con `--provider echo`, las cinco variables aisladas (regla de abajo) y sin el lanzador `~/.local/bin/muse` | Aprobado |
| Correr Muse con el modelo real (sin `--provider echo`) | **Negado**. Esa corrida es del lead |
| Leer o escribir `~/.claude`, `~/.config/muse`, `~/.local/share/muse`, `~/.zcode`, `~/.grok`, `~/.dsh`, `~/.codex` o `~/.agents` | **Negado**. Toda medición va con `HOME` y los cuatro `XDG_*` aislados |
| `tools/install-hook.sh`, con o sin `--dry-run`, sin `HOME` y `XDG` aislados | **Negado**, sin excepción: ni siquiera en dry-run se lee el perfil real |
| Editar `Plans.md` | **Negado**. El lead cierra las filas |
| Regrabar la golden (`tools/golden-harness.sh --record`) fuera de la caja de rotación de cabecera | **Negado**. Solo se aprueba rotar las tres líneas de cabecera (regla de abajo); cualquier otra línea distinta es regresión y se arregla el código |
| Mergear, o empujar a `master` | **Negado** |
| Preguntarle algo al operador | **Negado** |

> **Prohibido**, sin excepción: tocar el perfil real del operador en
> cualquiera de las rutas de la tabla, correr Muse con el modelo real, editar
> `Plans.md`, regrabar la golden fuera de la rotación de cabecera, mergear,
> usar `--no-verify` y preguntarle al operador. Prohibido tocar el perfil de
> producción: la corrida real es del lead.

## Reglas de trabajo

1. **Un test suelto, en su sandbox.** Así se corre cualquier `tests/test_*.sh`
   durante el rojo/verde, cambiando solo el nombre del archivo:

   ```bash
   caja="$(mktemp -d)"; mkdir -p "$caja/home" "$caja/tmp"
   env -u XDG_CONFIG_HOME HOME="$caja/home" USERPROFILE="$caja/home" \
     TMPDIR="$caja/tmp" TMP="$caja/tmp" TEMP="$caja/tmp" \
     SAIKIT_HOOK_VIVO="$PWD/hooks/summonaikit-harness.sh" \
     /opt/homebrew/bin/bash tests/test_model_routing.sh; echo "rc=$?"
   rm -rf "$caja"
   ```

   Sin `SAIKIT_HOOK_VIVO` el test mide el hook instalado y no el que editas.
   La suite completa no se corre en local: la corre el CI del PR.

2. **Correr Muse aislado (solo para medir, nunca para instalar de verdad).**
   Muse solo corre con las cinco variables aisladas, cwd en un `mktemp`
   fuera de un repo git, y el binario por ruta absoluta real resuelta ANTES
   de aislar `HOME`. Nunca el lanzador `~/.local/bin/muse`.

   ```bash
   MUSE="/Users/dn/.local/bin/muse-bin-$(cat /Users/dn/.local/bin/.muse-version)"
   caja="$(mktemp -d)"; mkdir -p "$caja/home" "$caja/work"
   m() { ( cd "$caja/work" && env HOME="$caja/home" XDG_CONFIG_HOME="$caja/xdg" \
     XDG_DATA_HOME="$caja/data" XDG_STATE_HOME="$caja/state" XDG_CACHE_HOME="$caja/cache" \
     "$MUSE" "$@" ); }
   ```

   Con esas cinco variables aisladas se permite session log (sin
   `--no-session-log`) para ver el catálogo de un turno con
   `m export --session <id> --out t.json`.

3. **Mutaciones del hook.** Cada guarda nueva lleva una mutación en
   `tests/test_gate_mutations.sh`: una línea `G<n>|<nombre>|<qué rompe>` en la
   lista `MUTACIONES` y una función `mut_<nombre>() { sed '…'; }` anclada a un
   comentario marcador en el hook. El ejemplo a copiar es
   `mut_budget_zcode_sigue_0`, anclada a `# saikit-5.4-zcode-budget`. Los
   casos que matan las mutaciones de Muse viven en `tests/lib/gate_cases.sh`,
   sumados a la lista `CASOS_G<n>` del gate que cubren (ceremonia en G3, veto
   de `PreToolUse` en G7, host y armado en G1), porque
   `tests/test_gate_mutations.sh` solo corre esas listas. Precedentes:
   `caso_g3_codex_nativo_cierre_acredita`, `caso_g1_dsh_arma_y_aisla_estado`.
   Constructores de payload nuevos van como `lab_payload_muse_*` en
   `tests/lib/hook_lab.sh`. `tests/test_host_muse.sh` es opcional y solo para
   lo que no es guarda del gate. Corre una mutación acotada:

   ```bash
   caja="$(mktemp -d)"; mkdir -p "$caja/home" "$caja/tmp"
   env -u XDG_CONFIG_HOME HOME="$caja/home" USERPROFILE="$caja/home" TMPDIR="$caja/tmp" TMP="$caja/tmp" TEMP="$caja/tmp" \
     SAIKIT_HOOK_VIVO="$PWD/hooks/summonaikit-harness.sh" SAIKIT_MUTACIONES='G3|<nombre>|<qué rompe>' \
     /opt/homebrew/bin/bash tests/test_gate_mutations.sh; echo "rc=$?"; rm -rf "$caja"
   ```

   Sin `SAIKIT_HOOK_VIVO` el test muta el hook instalado en `~/.claude`, no el
   que editas.

4. **Mutaciones del instalador.** Archivo nuevo
   `tests/test_install_muse_mutations.sh`, con el patrón de
   `tests/test_trail_install_mutations.sh`: `sed` sobre una copia de
   `tools/install-hook.sh`, `SAIKIT_INSTALL_TOOL=<mutante>`, y el test del
   instalador en rojo con la guarda rota.

5. **Fixtures de Muse.** Copia sin editar los fixtures que uses de
   `docs/evidence/phase-23/23.1/` a `tests/fixtures/muse/`. Los tests leen de
   `tests/fixtures/muse/`, nunca de `docs/`. Se permiten payloads DERIVADOS en
   `tests/fixtures/muse/derivados/`, con un `README.md` que da el comando `jq`
   de cada uno: (a) un `UserPromptSubmit` con `-saikit` con el `session_id`
   del fixture 07 y otro con el del 06, para armar esas sesiones; (b)
   `SubagentStart`/`SubagentStop` de `verify-reminder` y `goal-reminder` a
   partir de los fixtures 04 y 05; (c) un `PreToolUse` de `bash` con
   `tool_name` `bash` y otro con `bash_input`; (d) un `PostToolUse
   subagent_read_result` con `jq '.tool_name="subagent_read_result"'` sobre el
   fixture 15 (su forma real no está medida: `unknown`, corrida del lead). Todo
   caso negativo afirma
   PRIMERO que existe el `harness-state.env` de la sesión armada; si no
   existe, el caso pasa en vacío. Nota: `canonical_agent_role verify-reminder`
   hoy devuelve `verifier`, y el caso del recordatorio interno lo prueba (los
   recordatorios de Muse nunca acreditan aunque el mapeo exista).

6. **Commits.** El scope es el área, jamás el número de fila:
   `feat(hook): …`, `feat(install): …`, `test(install): …`. Mensajes en
   español, con la línea de coautoría que uses siempre.

7. **Pre-commit.** `pre-commit run --files <los que tocaste>` antes de cada
   commit. Si un candado falla, se arregla la causa.

8. **Qué va en cada PR.** El rojo medido antes del verde con su salida
   pegada, la lista de mutaciones con el caso que mata a cada una, y cada
   punto no medido como `unknown` con su razón. Nada que no hayas corrido.

## Entrega

`AGENTS.md`, sección **Protocolo de entrega**, manda: rama desde
`origin/master` con `git fetch` antes, `git log origin/master..HEAD` con solo
tus commits, PR abierto con el job `gate` del CI en verde, y ahí termina tu
entrega. Una ronda de revisión por PR como máximo, más una segunda solo si la
primera halló severidad alta. Tu entrega termina cuando el job `gate` queda
verde: si CodeRabbit ya comentó para entonces, atiéndelo; si comenta después,
lo atiende el lead. Aquí no hay cola de merge automática ni archivo de
progreso: el operador mergea a mano.

## PR A: 23.2, el hook reconoce el host muse

**Rama:** `feat/muse-hook`, desde `origin/master`. Independiente del PR B.

**Qué verá un usuario:** nada todavía. El hook no se registra en Muse hasta el
PR B. La prueba es el test.

**Diseño: Muse es un host ciego, como zcode.** Muse corre hooks en paralelo y
los eventos internos de un subagente hijo llegan con el `session_id` del
HIJO y sin rol (fixtures 12 y 13): el padre no los ve. Por eso no hay vínculo
padre-hijo, ni re-acreditación de internos del hijo, ni `link_record_child` /
`link_consume_child_seal` para Muse: esos símbolos son de grok y no se
reusan aquí. La verificación del subagente se declara con la línea `VERIFIED
BY SUBAGENT:` que ya existe.

**Contrato:** la fila 23.2 de `Plans.md`. Puntos de entrada en
`hooks/summonaikit-harness.sh`:

| Qué | Dónde |
|---|---|
| Host ciego | `saikit_host_ciego`, hook:395: el único lugar donde se agrega Muse (precedente Task 14.2 con zcode) |
| Resolución de `HOST` | el `if/elif` que termina en `HOST=other`, cerca de la línea 218. Muse no deja variables propias en el entorno: la señal es `SUMMONAIKIT_HOOK_TARGET=muse`, como codex y dsh |
| `TOOL_HINT` | líneas 63 a 66. Para Muse: "the subagent_spawn tool (then wait on each with subagent_wait)" |
| Rama de la ceremonia | `case "$TARGET" in claude\|codex\|grok\|dsh)`, línea 4263 |
| Detección de edición | regex en las líneas 2900 y 3329, que ya tienen `edit_file` pero no `write_file`: agrégalo a las dos (ningún otro host lo emite, así que la golden no cambia). Con `HOST=muse` y solo para `write_file`/`edit_file`, la ruta sale de `tool_input.path` cuando no hay `file_path`. El rojo se mide en `last_code_edit` de `harness-state-review-notice.env` y en la ruta del log (`implemented: notas.txt`), no en `implemented`, que en master ya vale 1 con el fixture 17 |
| Registro del rol | `subagent="$(json_tool_input_string subagent_type)"`, línea 3223, y `record_agent` |
| Crédito al cerrar | precedente en codex: `saikit_codex_role_event`, línea 1592 |
| Veto de `PreToolUse` | `pretool_merge_guard`, línea 4582; la comparación con `Bash` exacto está en la 4585. Acepta `tool_name` exacto `Bash` o `bash`. `bash_input` es OTRA herramienta de Muse (escribe en un bash ya corriendo), no una clave de `tool_input`: un `PreToolUse` con `tool_name` `bash_input` sale `emit_allow` aunque traiga `gh pr merge`, y eso se declara como límite en el PR |
| Deducción de fase | el `case` de las líneas 4739 a 4745 |
| Reglas permanentes de sesión | condición de hook:2175 |

**Diseño del crédito de rol (al CERRAR, no al aceptar).** Todo dentro de la
sesión del padre: un `PostToolUse subagent_spawn` con `status: accepted` en
sesión armada deja pendiente `subagent_id → rol` (el rol de
`tool_input.subagent_type`) en el estado de esa sesión. Se acredita el rol
cuando un `PostToolUse subagent_wait` o `subagent_read_result` de ESA sesión
devuelve `status: ready` con un `subagent_id` pendiente. De dónde sale cada
id: en el despacho, del `subagent_id` de nivel 1 del `tool_response` (el
`tool_input` de `subagent_spawn` no lo trae); en el cierre, de
`tool_input.subagent_id`, y si el `tool_response` trae `subagent_id` de nivel
1, los dos tienen que coincidir. `rejected` nunca deja pendiente. Un `subagent_id`
sin pendiente nunca acredita. Los recordatorios internos de Muse
(`skill-reminder`, `goal-reminder`, `verify-reminder`) nunca pasan por
`subagent_spawn` y nunca acreditan.

**Lectura de `tool_response`.** En Muse es un TEXTO que contiene JSON
(fixtures 06, 10 y 15): se lee `status` como la PRIMERA clave del objeto
interno y `subagent_id` como clave de nivel 1 de ese objeto. En el payload
crudo ese texto va escapado: el valor de `tool_response` empieza con
`{\"status\":\"<valor>\"`. Nunca con un grep sobre todo el texto: `summary`
lo escribe el modelo hijo. Caso hostil obligatorio: un `summary` que contiene
`{"status":"ready"}` junto a un status real distinto no acredita. Como un
`summary` llega doblemente escapado, un grep ingenuo tampoco lo ve, así que el
caso solo discrimina contra una lectura laxa: su mutación reemplaza la lectura
de la primera clave por `tr -d '\\' | grep -q '"status":"ready"'` sobre todo el
`tool_response`, y el caso hostil tiene que matarla.

**Datos medidos que fijan el diseño:**

- El `PostToolUse` de `subagent_spawn` llega al aceptar la tarea, con
  `tool_response` como texto JSON: `status` vale `accepted` o `rejected` y
  trae `subagent_id`. El cierre es `PostToolUse subagent_wait` (o
  `subagent_read_result`) con `status: ready` y el mismo `subagent_id`.
  Fixtures 06, 10 y 15.
- En `Stop`, el camino actual de claude bloquea en Muse: JSON, motivo a
  stderr y `exit 2`. No inviertas el exit como en codex o grok. Evidencia:
  `complementarias/stop-semantica.txt`.
- `SessionStart` en Muse NO entra a la condición de reglas permanentes de
  hook:2175 (no medido); se registra igual y queda `unknown`.

**Fuera de alcance, declarado como límite en el PR:** el sello del veredicto
(exige `write` y `file_path`, líneas 2555 y 3291) y el candado del adversary
para hijos de Muse (los eventos del hijo no traen rol). Con Muse como host
ciego, se declaran igual que en zcode.

**`unknown` que este PR declara:** un resultado auto-entregado sin
`subagent_wait` ni `subagent_read_result` (queda `unknown`, corrida del lead
en la 23.6); un spawn en workspace NO confiado (Muse avisa "Agent delegation:
auto unavailable: workspace is untrusted"); dos hooks de la misma sesión
corriendo en paralelo sobre el mismo estado (Muse corre hooks en paralelo,
ver `doble-registro.txt`); `SessionStart`; Windows.

**Golden.** Aprobado SOLO rotar la cabecera. Tras editar el hook:

```bash
caja="$(mktemp -d)"; mkdir -p "$caja/home" "$caja/tmp"
env -u XDG_CONFIG_HOME HOME="$caja/home" USERPROFILE="$caja/home" \
  TMPDIR="$caja/tmp" TMP="$caja/tmp" TEMP="$caja/tmp" \
  /opt/homebrew/bin/bash tools/golden-harness.sh --record --baseline "$caja/base.txt" \
  --hook "$PWD/hooks/summonaikit-harness.sh"
diff tests/golden/baseline.txt "$caja/base.txt"; rm -rf "$caja"
```

Si difieren exactamente las tres líneas `# hook_sha256:`, `# hook_bytes:` y
`# hook_lineas:`, copia esa base y pega el `git diff -U0` en el PR (precedente
PR #328). Cualquier otra línea distinta es regresión: se arregla el código, no
la golden.

**Archivos:**

| Puede tocar | No toca |
|---|---|
| `hooks/summonaikit-harness.sh` | `tools/` |
| `tests/lib/gate_cases.sh`, `tests/lib/hook_lab.sh` | `agents/`, `recetas/`, `skills/` |
| `tests/test_gate_mutations.sh` | `Plans.md`, `docs/` |
| `tests/test_host_muse.sh` (nuevo, opcional) | |
| `tests/fixtures/muse/` (nuevo) | |
| `tests/golden/baseline.txt` (SOLO las tres líneas de cabecera) | |

## PR B: 23.3 y 23.4 juntas, el instalador y los perfiles

**Rama:** `feat/muse-instalador`, desde `origin/master`. Independiente del PR
A y del resto. Las filas 23.3 y 23.4 se entregan en este mismo PR porque las
dos tocan `tools/install-hook.sh`: un PR apilado contradice `AGENTS.md`
("rama desde `origin/master`") y CodeRabbit no revisa PRs cuya base no es
`master`.

**Qué verá un usuario:** `bash tools/install-hook.sh --host muse --dry-run`
dice qué registraría y dónde, y el catálogo de agentes lista `implementer`,
`verifier`, `reviewer` y `adversary`. El dry-run se corre en la caja aislada
de la regla 2, en dos pasos: primero `bash tools/install-hook.sh` sin
`--host`, para dejar la copia de claude en `$caja/home/.claude/hooks` (el
preflight la exige idéntica); después
`SAIKIT_MUSE_BIN="$MUSE" bash tools/install-hook.sh --host muse --dry-run`,
con `$MUSE` resuelto antes de aislar `HOME`, porque en la caja no existe
`$HOME/.local/bin`. El gate completo en Muse requiere además el hook de
la 23.2 desplegado en `~/.claude/hooks` por el lead: esa corrida es del lead.

**Contrato:** las filas 23.3 y 23.4 de `Plans.md`. Puntos de entrada en
`tools/install-hook.sh`:

| Qué | Dónde |
|---|---|
| Patrón a copiar: host que reusa la copia de claude y escribe un JSON de usuario | `zcode_instalar` (línea 694), `zcode_quitar` (847), `zcode_harness_cmd` (478) |
| Resolvedor de bash POSIX | la rama de Task 18.15 dentro de `zcode_bash_win` (línea 441) |
| Validación de `--host` y guardas de `--dest` | el `if` de la línea 165 y los bloques que le siguen |
| Conjunto autoritativo de `--check` | comentario de la línea 2142; el `if [ "$HOST" = "kimi" ] ... ]` de la línea 281 a 291 |
| Verificador de registro | `tools/check-hook-registration.sh`, con sus modos zcode y codex como patrón |
| Traducción de un perfil por host | `agente_traducido`, línea 1083 |
| Máquina de estados de perfiles | `instalar_agentes_con_vendor`, línea 2519 |
| Host sin modelo por agente, a copiar | `kimi_instalar_agentes` (línea 2643) y la rama `kimi)` de `tools/model-routing.sh` |
| Preflight de copia idéntica | `install-hook.sh:707-719`, patrón `NUESTRO_IDENTICO` |

**23.3: registro en el instalador.**

- Settings: `${XDG_CONFIG_HOME:-$HOME/.config}/muse/settings.json`, con
  `"schema_version": 1` obligatorio (`2` no se soporta). Forma del bloque,
  igual que en Claude:
  `{"hooks":{"<Evento>":[{"matcher":"…","hooks":[{"type":"command","command":"…","timeout":<segundos>}]}]}}`.
- Cinco eventos, `SubagentStart` ya NO se registra: `SessionStart` (fase
  `session`), `UserPromptSubmit` (fase `prompt`), `PreToolUse` (matcher
  `bash`, sin fase), `PostToolUse` (matcher `bash`, `edit_file`,
  `write_file`, `subagent_spawn`, `subagent_wait` y `subagent_read_result`
  separados por barra vertical, fase `tool`), `Stop` (fase `stop`). Todos con
  `timeout` 30 segundos: es medido que el corte por timeout en Muse es
  SILENCIOSO, el host falla abierto.
- Comando:
  `SUMMONAIKIT_HOOK_TARGET=muse SUMMONAIKIT_HOOK_PHASE=<fase> "<bash>" "<DEST>" --saikit-harness-id 23.3`
  (sin el prefijo de fase donde no hay fase). `<DEST>` es la copia de claude,
  `$HOME/.claude/hooks/summonaikit-harness.sh`. Preflight: `<DEST>` debe estar
  `NUESTRO_IDENTICO` (como zcode). Instalar purga toda entrada con
  `--saikit-harness-id 23.3` que no sea la canónica; `--quitar-muse` quita
  solo esas entradas y los grupos que queden vacíos, más los perfiles con la
  marca de Muse.
- Bash: `<bash>` sale del resolvedor POSIX; antes de escribir se valida
  `"$bash" -c '[ "${BASH_VERSINFO[0]}" -ge 4 ]'` y `"$bash" -n "$DEST"`; si
  cualquiera falla, `exit 2` (el bash 3.2 de macOS no parsea el hook, y en
  Muse un `exit 2` con stderr bloquearía cada prompt). Costura de test
  `SAIKIT_MUSE_BASH`, con la semántica de `SAIKIT_ZCODE_BASH_WIN` (puesta =
  no se busca en disco; vacía o inexistente = falla). En MSYS/Windows
  `--host muse` sale `unknown` (`exit 4`): no medido.
- Binario de Muse para validar:
  `$HOME/.local/bin/muse-bin-$(cat "$HOME/.local/bin/.muse-version")`, nunca
  el lanzador `~/.local/bin/muse` (se autoactualiza en cada llamada). Costura
  `SAIKIT_MUSE_BIN`: puesta, no se busca en disco. Puesta y vacía, o apuntando
  a un archivo que no existe, equivale a sin binario. Sin binario, `unknown`
  (`exit 4`) sin tocar nada, también en `--dry-run`.
- **Validación DIFERENCIAL y POSITIVA**, en la caja de la regla 2 con las
  cinco variables aisladas y cwd `mktemp` no-git verificado: (1) se valida el
  settings ACTUAL y el CANDIDATO con los mismos reemplazos; (2) en ambas
  copias, `mcpServers` se elimina (medido: la validación los ejecuta), los
  comandos ajenos pasan a `/usr/bin/true` y NUESTROS comandos pasan a
  `touch <caja>/<Evento>`; (3) `exec --no-session-log --provider echo "ping"`;
  (4) válido si rc 0, sin `malformed settings`, las líneas de DETALLE de avisos
  del candidato son un subconjunto de las del actual (los previos se
  reportan, no bloquean), y EXISTEN las marcas `<caja>/UserPromptSubmit` y
  `<caja>/Stop`. Las líneas de detalle son las que empiezan con
  `muse:   settings.json:` (tres espacios). La línea resumen
  `muse: Hooks: N runnable · M warning` NO se compara: su conteo `runnable`
  cambia siempre que el candidato agrega hooks. Medido en 1.3.0: con un evento
  ajeno inválido, actual y candidato comparten la línea de detalle
  `UnsupportedEvent` y solo difieren en el resumen. El aviso
  `Agent delegation: auto unavailable: workspace is untrusted` sale en toda
  validación aislada: es esperado y no cuenta como aviso. Casos: un aviso ajeno previo sí instala; un aviso nuevo
  nuestro no instala; un bloque escrito `Hooks` (mayúscula) se rechaza por
  falta de marcas; un JSON roto se rechaza. `--quitar-muse` solo exige que el
  resultado parsee y no necesita binario. `--dry-run` también valida (no
  escribe en el perfil).
- **Muse falso para el CI.** El CI corre en `ubuntu-latest` y no tiene Muse.
  En los tests, `SAIKIT_MUSE_BIN` apunta a `tests/fixtures/muse/muse-falso.sh`,
  un script bash que imita lo medido en `validacion-settings.txt`: lee
  `$XDG_CONFIG_HOME/muse/settings.json` con `jq`; con JSON roto, sin
  `schema_version` o con `schema_version` distinto de 1, escribe
  `malformed settings …` a stderr y sale 1; por cada evento no soportado bajo
  `hooks` imprime el resumen y la línea de detalle
  `muse:   settings.json: UnsupportedEvent: …`; ejecuta los `command` de
  `.hooks.UserPromptSubmit` y `.hooks.Stop` (solo la clave `hooks` en
  minúscula) y sale 0. Una mutación que haga que el instalador ignore la falta
  de marcas debe ponerse roja con el caso `Hooks`. Los mismos cuatro casos de
  validación se corren además una vez con el binario real en la Mac, en la
  caja de la regla 2, y su salida se pega en el PR.
- Settings ausente: si no existe el directorio
  `${XDG_CONFIG_HOME:-$HOME/.config}/muse/`, Muse no está instalado y sale
  `exit 2` con ese mensaje. Si existe el directorio pero no el archivo, se
  crea `{"schema_version":1,"hooks":{…}}`.
- `--dest` bajo `${XDG_CONFIG_HOME:-$HOME/.config}/muse` se rechaza sin
  `--host muse` (misma guarda que codex/grok/dsh). El kit nunca escribe
  `.muse/hooks.json` de proyecto: doble registro es doble ejecución en
  paralelo, medido en `doble-registro.txt`.
- `--check`: `--check --host muse` sale `exit 2` igual que zcode (sin copia
  propia, reusa la de claude). `--check` sin host suma una fila de REGISTRO
  `muse` (cinco eventos apuntando a la copia de claude), exigida solo si
  existe `${XDG_CONFIG_HOME:-$HOME/.config}/muse/`.

**23.4: perfiles de rol.**

- Destino: `${XDG_CONFIG_HOME:-$HOME/.config}/muse/agents/<rol>.md`.
- Marca en el DESTINO:
  `^#[[:space:]]*saikit_owned:[[:space:]]*summonaikit-claude[[:space:]]*$`
  dentro del primer frontmatter, reconocida SOLO para `--host muse` (la regex
  global `ZCODE_AGENT_MARCA_RE` no cambia; la fuente se sigue validando con
  ella).
- El frontmatter traducido lleva `skills` como lista YAML y no lleva `model`
  ni ningún campo de effort: Muse marca `model` como `KnownFieldInactive` y
  una clave desconocida tumba el perfil entero.
- Casos: segunda corrida es ya al día (no DESCONOCIDO); perfil editado a mano
  es NUESTRO_DISTINTO, se repara con backup; archivo sin marca es
  DESCONOCIDO.
- `tools:` traducido: `Read`→`read_file`, `Edit`→`edit_file`,
  `Write`→`write_file`, `Bash`→`bash`, `Glob` y `Grep`→`search`, sin repetir
  nombres. `herramientas-muse.txt` se copia a `tests/fixtures/muse/`; el test
  ignora la línea 1 (cabecera) y compara nombres exactos.
- El catálogo con el modelo `echo` se ve con session log en la caja aislada
  de la regla 2 y `m export`; sin binario, `unknown`. La aceptación del
  despacho con el modelo real la mide el lead: `echo` no detecta
  `unknown_tool`.

**Fila 23.5, referencia.** No es de este PR, pero su texto cambia de "se
cablea a `--check --host muse`" a "se cablea como paso de `--check` sin host
o como comando del doctor, decidido y declarado": declara esa decisión aquí
si el diseño del `--check` de este PR ya la resuelve.

**Archivos:**

| Puede tocar | No toca |
|---|---|
| `tools/install-hook.sh` | `hooks/` |
| `tools/check-hook-registration.sh` | `agents/*.md` (la fuente no cambia; se traduce al instalar) |
| `tools/model-routing.sh` | `recetas/`, `skills/` |
| `tests/test_install_hook.sh`, `tests/test_hook_registration.sh`, `tests/test_install_provenance.sh`, `tests/test_model_routing.sh` | `Plans.md`, `docs/`, `README.md`, `AGENTS.md` (los actualiza la 23.7) |
| `tests/test_install_muse_mutations.sh` (nuevo) | |
| `tests/fixtures/muse/` | |
| `.cursor/skills/verify-summonaikit/` solo si un test del feature map falla por el host nuevo | |

## Cuando algo se atora

| Situación | Acción |
|---|---|
| El arranque no imprime `BRIEF_EN_MASTER` | Para. Reporta que el PR del brief no está mergeado |
| El brief contradice la fila de `Plans.md` | Sigue la fila y anótalo en el PR |
| Un punto de la DoD solo se mide con Muse real o con el perfil del operador | No lo midas. Márcalo `unknown` con la razón "corrida del lead" y sigue con el resto |
| Un test falla en local y no tocaste nada relacionado | Córrelo igual sobre `origin/master` en un worktree aparte. Si también falla ahí, es previo: decláralo en el PR y sigue |
| El CI falla en un job que tu cambio no toca | Mira si `master` está rojo con `gh run list --branch master --limit 3`. Si lo está, decláralo en el PR; si no, es tuyo y se arregla |
| La golden difiere en más de las tres líneas de cabecera, o un test de otro host cambia | Es una regresión tuya. Se arregla el código; la golden no se regraba |
| Una mutación dice "la mutación no cambió nada" | Casi siempre se corrió fuera de la caja aislada, sin `SAIKIT_HOOK_VIVO`: revisa el comando y corre de nuevo dentro de la caja |
| El settings actual del operador ya trae avisos previos al validar | Se reportan, no bloquean: si el candidato no agrega avisos nuevos, instala |
| Muse avisa "Agent delegation: auto unavailable: workspace is untrusted" | `unknown`, corrida del lead |
| No hay binario de Muse en la máquina | Lo que dependa del Muse real queda `unknown`. Los tests usan el Muse falso de `tests/fixtures/muse/muse-falso.sh` vía `SAIKIT_MUSE_BIN`, y `SAIKIT_MUSE_BASH` para el resolvedor de bash. Sigue |
| Un nombre de línea de este brief ya no coincide con el código | Busca el símbolo por nombre con `grep -n`. Los números son de `origin/master` al 2026-09-18 UTC |
| CodeRabbit comenta antes de que el job `gate` quede verde | Arregla lo que sea un defecto real. Lo demás, contéstalo en el hilo con la razón |
| CodeRabbit comenta después de que el job `gate` ya quedó verde | Tu entrega ya terminó: lo atiende el lead |
| Terminaste el PR A antes que el PR B, o viceversa | Normal. Los dos son independientes y salen de `origin/master` |

## Cierre

Son dos PRs: `feat/muse-hook` (fila 23.2) y `feat/muse-instalador` (filas 23.3
y 23.4 juntas). No hay gasto de API: el modelo real de Muse está negado.
Fuera de alcance: la 23.5 (probe del contrato), la 23.6 (medición viva, del
lead) y la 23.7 (docs y cierre).

Cuando los dos PRs estén abiertos con el job `gate` en verde, tu último
mensaje lista las dos URLs, el head SHA de cada una, las mutaciones que
agregaste y los `unknown` que declaraste.
