#!/usr/bin/env bash
# SAIKIT-CLAUDE-OWNED summonaikit-claude 1.0.0
# SummonAI Kit harness hook. Project-agnostic: it enforces the implement ->
# verify -> review -> close -> retro gate against whatever stack the host repo
# uses, discovering the repo's own commands and conventions at runtime.

MAX_CYCLES=2

# >>> SAIKIT-SENTINEL-GATE v1 (parche local, re-aplicado por quality-kit/saikit-gate-heal.ps1) >>>
# El kit busca sus palabras clave como fragmentos, sin frontera de palabra, asi que
# en espanol se arma solo ("cualquier" contiene ui, "codex" contiene code). Con este
# parche el harness SOLO se arma si el prompt trae el sentinel explicito.
# El sentinel es unicamente -saikit: /harness-plan es del plugin claude-code-harness,
# otro sistema, y no debe despertar a este kit.
SAIKIT_SENTINEL_RE='(^|[^A-Za-z0-9_])-saikit([^A-Za-z0-9_-]|$)'
# <<< SAIKIT-SENTINEL-GATE v1 <<<

if [ "$SUMMONAIKIT_INTERNAL_GENERATION" = "1" ] 2>/dev/null; then
  exit 0
fi

INPUT="$(cat)"
TARGET="$SUMMONAIKIT_HOOK_TARGET"
# A10 (Task 3.7): el host NO propaga el prefijo VAR=val del comando registrado
# (medido 2026-08-11), asi que SUMMONAIKIT_HOOK_TARGET llega vacio en produccion
# y la rama de secuencia (claude) nunca corria -- [ "$TARGET" = "claude" ] era
# siempre falso. Claude Code setea CLAUDECODE=1 (medido); acierta para Claude y
# para glm (que hace exec claude). No setea cursor ni zcode, que quedan con
# TARGET vacio: correcto, la secuencia es una primitiva de Claude. La via
# "limpia" para cursor/zcode seria exportar TARGET dentro del bash -c del comando
# registrado, pero eso toca settings.json (que ningun tool de este repo genera) y
# queda fuera de esta tarea. PHASE no necesita este fallback: ya lo tiene al
# payload (hook_event_name, ver :1144).
if [ -z "$TARGET" ] && [ "$CLAUDECODE" = "1" ]; then TARGET="claude"; fi
PHASE="$SUMMONAIKIT_HOOK_PHASE"
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
# Directorio de PERFIL del host (dirname del HOOK_DIR). En install global es
# ~/.claude, que contiene projects/ donde Claude Code guarda los transcripts
# reales. Es la raiz de contencion de transcript_path (Task 3.6 / A6): ver
# transcript_en_perfil. Se deriva con cd+pwd para llegar a la forma canonica de
# MSYS (en Windows /c/Users/...), la misma a la que cd+pwd lleva cualquier
# transcript_path del payload (que llega con backslashes dobles literales porque
# json_string_field no decodifica escapes).
PROFILE_DIR="$(cd "$HOOK_DIR/.." 2>/dev/null && pwd)"
# Resolve the project from the WORKING directory, not the script location. This
# hook is installed at user level (~/.claude/hooks) and shared by every project,
# so deriving the project from $0 would always point at the home dir. The cwd is
# the project being worked in; fall back to pwd when git is absent.
PROJECT_ROOT="$(pwd)"
if command -v git >/dev/null 2>&1; then
  GIT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -n "$GIT_ROOT" ]; then PROJECT_ROOT="$GIT_ROOT"; fi
fi

# PROJECT_ROOT se resuelve arriba; el state-path (PROJECT_DIR + SESSION_KEY por
# sesion) se resuelve MAS ABAJO, tras los lectores json_*field, porque necesita
# leer session_id del payload (Task 3.4 / A4). Definirlo aca era llamar a
# json_string_field antes de que existiera — bash no hoistea funciones, y el
# bloque quedaba inerte (ver CORRECCION 1 del plan de la 3.4).

# Language/framework-agnostic test, type-check, and lint runners. Used both to
# mark verification evidence on a tool event and to credit a verification claim in
# the Stop gate, so detection stays consistent across ecosystems (JS/TS, Python,
# Ruby/Rails, PHP, .NET, JVM, Go, Rust, Elixir, Swift, C/C++, make). Add a host's
# runner here rather than in two places.
TEST_RUNNER_RE='bun[[:space:]]+(test|run[[:space:]]+(test|check-types|typecheck|lint))|npm[[:space:]]+(test|run[[:space:]]+(test|typecheck|lint))|pnpm[[:space:]]+(test|run[[:space:]]+(test|typecheck|lint))|yarn[[:space:]]+(test|typecheck|lint)|deno[[:space:]]+(test|lint|check)|vitest|jest|playwright[[:space:]]+test|cypress[[:space:]]+run|tsc|check-types|typecheck|cargo[[:space:]]+(test|nextest)|go[[:space:]]+test|gotestsum|pytest|unittest|tox|rspec|rake[[:space:]]+(test|spec)|rails[[:space:]]+test|bundle[[:space:]]+exec[[:space:]]+(rspec|rake|cucumber|minitest)|mix[[:space:]]+test|phpunit|pest|artisan[[:space:]]+test|composer[[:space:]]+(test|run[[:space:]]+test)|dotnet[[:space:]]+test|gradle[[:space:]]+(test|check)|gradlew[[:space:]]+(test|check)|mvn[[:space:]]+(test|verify)|swift[[:space:]]+test|ctest|ginkgo|make[[:space:]]+(test|check)'

# Wrapper con fronteras de palabra: el runner debe estar flanqueado por
# start/end o un caracter que NO forme parte de un nombre de archivo. Cierra A3
# (Task 3.3): sin esto, `cat pytest.log` matchea el fragmento `pytest` y cuenta
# como verificacion.
#
# El lado derecho acepta un punto que NO va seguido de alfanumerico. No es
# cosmetico: este regex se aplica a DOS superficies distintas -- el comando de
# un evento (:729) y la PROSA del asistente (:870, texto decodificado desde la
# 3.2). Sin esa alternativa, `Verify: se corrio pytest.` deja de contar y el
# gate exige de mas, que es el dano que la 3.2 acaba de cerrar en A8. Con ella,
# `pytest.log` sigue sin contar: ahi el punto va seguido de `l`.
#
# Limites declarados y medidos: `npm run test-e2e` y `pytest.exe` NO cuentan
# (sufijo pegado por guion / extension). Cae al lado estricto a proposito: sin
# credito el gate pide la razon explicita, que es recuperable; acreditar
# `cat pytest-viejo.log` no lo es.
TEST_RUNNER_WORD_RE='(^|[^A-Za-z0-9_.-])('"$TEST_RUNNER_RE"')([^A-Za-z0-9_.-]|\.([^A-Za-z0-9_.-]|$)|$)'

json_string_field() {
  field="$1"
  printf '%s' "$INPUT" | tr '\n' ' ' | sed -n "s/.*\"$field\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -n 1
}

json_number_field() {
  field="$1"
  printf '%s' "$INPUT" | tr '\n' ' ' | sed -n "s/.*\"$field\"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p" | head -n 1
}

# Lee un campo de string de PRIMER NIVEL del payload, y solo de ahi. Es el gemelo
# de json_tool_input_string (que acota a tool_input, depth 2) para campos como
# session_id, que viajan al ras del objeto raiz. Cierra el costado de A4 (Task
# 3.4, CORRECCION 2 del plan): json_string_field (el lector sed greedy) NO sirve
# para esto — su `.*` inicial sobre el payload crudo es justamente el defecto A1,
# y session_id puede aparecer como clave JSON real en otra parte del payload de
# Stop (background_tasks, session_crons), con lo que el estado se llavearia a
# mitad de turno con un valor que el turno no escribio.
#
# Mismo escaner char por char de la 3.1 (depth + in-string + escape), cambiando
# solo la condicion de match: clave == want a depth == 1. No decodifica escapes:
# un session_id escapado no mapea a ningun UUID real, y el saneamiento posterior
# (SESSION_KEY) lo neutraliza igual.
json_top_level_string() {
  field="$1"
  case "$INPUT" in
    *"\"$field\""*) ;;
    *) return 0 ;;
  esac
  printf '%s' "$INPUT" | awk -v want="$field" '
    { buf = buf $0 "\n" }
    END {
      n = length(buf)
      depth = 0; ins = 0; esc = 0; espera = 0
      ini = 0; ultima = ""; clave = ""
      for (i = 1; i <= n; i++) {
        c = substr(buf, i, 1)
        if (ins) {
          if (esc)            { esc = 0 }
          else if (c == "\\") { esc = 1 }
          else if (c == "\"") {
            ins = 0
            txt = substr(buf, ini, i - ini)
            if (espera) {
              if (depth == 1 && clave == want) { print txt; exit }
              espera = 0
            }
            ultima = txt
          }
          continue
        }
        if (c == "\"")                 { ins = 1; ini = i + 1 }
        else if (c == ":")             { clave = ultima; espera = 1 }
        else if (c == "{" || c == "[") { depth++; espera = 0 }
        else if (c == "}" || c == "]") { depth--; espera = 0 }
        else if (c == ",")             { espera = 0 }
      }
    }'
}

# Keep gate state isolated per project AND per session (Task 3.4 / A4). Antes el
# estado se llaveaba solo por proyecto, asi que dos sesiones del mismo repo
# compartian harness-state.env y un turno -saikit abandonado en una cobraba
# recibo a la otra. session_id viaja en cada payload (medido Task 1.4), asi que
# se llavea por proyecto Y sesion. Patron calcado de la variante .codex
# (resolve_state_paths, ver comentario REVIEW-NOTICE de mas abajo).
#
# El valor de session_id viene del payload y NO se mete crudo en una ruta: es
# una primitiva de escritura descontrolada (familia de A6, Task 3.6). Se SANEA
# (no se hashea): un session_id real es un UUID, asi que el directorio queda
# legible (descubrible a mano), sin colisiones y sin traversal. Hashear con
# cksum (CRC32) es colisionable y su modo de falla es reapertura de A4. PROJECT
# si se hashea porque su ruta trae `:` y `\` (ilegales en un nombre de dir).
STATE_ROOT="$HOOK_DIR/state"
PROJECT_KEY="$(printf '%s' "$PROJECT_ROOT" | cksum | cut -d ' ' -f 1)"
PROJECT_DIR="$STATE_ROOT/$PROJECT_KEY"
SESSION_ID="$(json_top_level_string session_id)"
if [ -z "$SESSION_ID" ]; then
  # session_id ausente -> slot nombrado y descubrible, no un slot unico que
  # colapsaria todo y reintroduciria A4. Edge case: session_id SIEMPRE viene en
  # payloads reales (medido Task 1.4).
  SESSION_ID="sin-session"
fi
SESSION_KEY="$(printf '%s' "$SESSION_ID" | sed 's/[^A-Za-z0-9_-]/_/g' | cut -c1-64)"
STATE_DIR="$PROJECT_DIR/$SESSION_KEY"
STATE_PATH="$STATE_DIR/harness-state.env"
LOG_PATH="$STATE_DIR/harness-evidence.log"

# Lee un campo de string del objeto `tool_input` de PRIMER NIVEL, y solo de ahi.
# Cierra el defecto A1 (Task 3.1).
#
# Por que json_string_field no alcanza, medido 2026-08-09: su `sed` arranca con
# `.*` greedy sobre el payload CRUDO, que incluye `tool_response` — texto que el
# turno no escribio. Cualquier `subagent_type` que aparezca como clave JSON en
# otro nivel se tomaba como el subagente que corrio, y con varias ocurrencias
# ganaba la ULTIMA: con `tool_input.subagent_type=implementer` y un eco
# `reviewer` mas adelante, el hook anotaba reviewer. No solo inventaba un rol,
# BORRABA el legitimo.
#
# Que hace el escaner y que NO hace. Recorre el payload caracter por caracter
# llevando dos cosas: si esta adentro de una string (respetando la barra de
# escape) y a que profundidad de llaves/corchetes esta. Con eso alcanza para la
# unica pregunta que hace falta: "esta clave, esta adentro del tool_input de
# primer nivel?". NO es un parser JSON — no valida el documento, no entiende
# numeros ni literales, y no decodifica escapes.
#
# Los escapes se dejan CRUDOS a proposito. Un valor escapado no mapea a ningun
# rol en canonical_agent_role, asi que el error cae del lado seguro: no se
# acredita un subagente que no se pudo leer limpio. Decodificar aca abriria la
# puerta a que un nombre con escapes unicode acredite un rol que no dice.
#
# Dependencias: NINGUNA nueva. awk ya lo usan json_escape y el task_hash, o sea
# que si faltara el hook ya estaria roto antes de llegar aca. Si el escaner no
# devuelve nada no se registra rol: el mismo desenlace que un payload sin el
# campo. Inventar uno para "dejar pasar" es exactamente A1.
json_tool_input_string() {
  field="$1"
  # Atajo barato y equivalente — el escaner solo puede encontrar lo que este en
  # el texto. Un turno real son ~300 eventos y solo 8 traen el campo (medido en
  # la captura de la Task 1.4), asi que esto ahorra el proceso en la mayoria.
  case "$INPUT" in
    *"\"$field\""*) ;;
    *) return 0 ;;
  esac
  printf '%s' "$INPUT" | awk -v want="$field" '
    { buf = buf $0 "\n" }
    END {
      n = length(buf)
      depth = 0; ins = 0; esc = 0; espera = 0
      ini = 0; ultima = ""; clave = ""; clave1 = ""
      for (i = 1; i <= n; i++) {
        c = substr(buf, i, 1)
        if (ins) {
          if (esc)            { esc = 0 }
          else if (c == "\\") { esc = 1 }
          else if (c == "\"") {
            ins = 0
            txt = substr(buf, ini, i - ini)
            if (espera) {
              if (depth == 2 && clave1 == "tool_input" && clave == want) { print txt; exit }
              espera = 0
            }
            ultima = txt
          }
          continue
        }
        if (c == "\"")                 { ins = 1; ini = i + 1 }
        else if (c == ":")             { clave = ultima; if (depth == 1) clave1 = clave; espera = 1 }
        else if (c == "{" || c == "[") { depth++; espera = 0 }
        else if (c == "}" || c == "]") { depth--; espera = 0 }
        else if (c == ",")             { espera = 0 }
      }
    }'
}

# Extrae el texto decodificado del asistente para el gate del Stop (Task 3.2).
# Cierra A2 (la pausa/recibo se busca en el tail crudo, que incluye tool_result)
# y A8 (los saltos escapados del JSONL rompen la frontera [^[:alpha:]] de las
# etiquetas). Dos canales medidos (Task 1.4): last_assistant_message del payload
# y los bloques text de message.content con role:"assistant" en el transcript.
#
# Por que DOS funciones y no una con fallback, declarado: awk no "falla" con JSON
# malo — devuelve vacio. Un "si el walker falla, caer a last_assistant_message"
# no es accionable (nunca se dispara) y ademas no es fail-open: con text vacio el
# gate reclama las 6 etiquetas y BLOQUEA. Cada canal vive en su funcion; si el
# transcript no existe o es ilegible, el canal 2 queda vacio y se evalua solo el
# canal 1 — exactamente lo que hoy pasa con el tail vacio, sin rama especial.
#
# Por que esta SI decodifica y la 3.1 (json_tool_input_string) NO: alla un valor
# escapado no mapea a ningun rol, asi que el error cae del lado seguro. Aca el
# caso de uso es texto multilinea, y una etiqueta detras de \n TIENE que contar:
# decodificar \n \" \\ \t es lo que vuelve real el salto que has_receipt_label
# supone. Los demas escapes (\uXXXX, \/, \b, \f) se dejan crudos: no aparecen en
# los 308 payloads medidos (Task 1.4), y un escape no manejado no mapea a
# ninguna etiqueta — cae del mismo lado seguro que en la 3.1.
#
# Dependencias: NINGUNA nueva. awk ya es dependencia dura (json_escape,
# json_tool_input_string, task_hash). Si faltara, el hook estaria roto antes.

# Canal 1: last_assistant_message del payload Stop (clave de primer nivel).
assistant_text_payload() {
  case "$INPUT" in
    *'"last_assistant_message"'*) ;;
    *) return 0 ;;
  esac
  printf '%s' "$INPUT" | awk '
    { buf = buf $0 "\n" }
    END {
      n = length(buf)
      depth = 0; ins = 0; esc = 0; espera = 0
      ini = 0; ultima = ""; c1 = ""; emiti = 0
      for (i = 1; i <= n; i++) {
        c = substr(buf, i, 1)
        if (ins) {
          if (esc) {
            if (emiti) {
              if      (c == "n")  printf "\n"
              else if (c == "t")  printf "\t"
              else if (c == "\\") printf "\\"
              else if (c == "\"") printf "\""
              else                printf "\\%s", c
            }
            esc = 0; continue
          }
          if (c == "\\") { esc = 1; continue }
          if (c == "\"") {
            ins = 0
            ultima = substr(buf, ini, i - ini)
            if (espera && depth == 1 && c1 == "last_assistant_message") { emiti = 0; exit }
            continue
          }
          if (emiti) printf "%s", c
          continue
        }
        if (c == "\"") {
          ins = 1; ini = i + 1
          if (espera && depth == 1 && c1 == "last_assistant_message") emiti = 1
          continue
        }
        if (c == ":")                { if (depth == 1) c1 = ultima; espera = 1 }
        else if (c == "{" || c == "[") { depth++; espera = 0 }
        else if (c == "}" || c == "]") { depth--; espera = 0 }
        else if (c == ",")             { espera = 0 }
      }
    }'
}

# Canal 2: bloques {"type":"text","text":...} de message.content con
# role:"assistant" en el transcript (JSONL, una entrada por linea). Lee de stdin.
# La decision de que texto cuenta la toma el walker (exige role:assistant +
# content[].type:text exacto). Un atajo `index($0,"\"assistant\"")` se probo y se
# saco: era un acelerador declarado NO autoridad, pero en la practica FILTRABA
# lineas que el walker necesitaba ver (un mensaje user con type:text no contiene
# la palabra "assistant" y se saltaba entero — la mutacion de role no era
# atrapable). Sin el atajo el walker es la unica autoridad; el costo se declara
# en la medicion de la Task 3.2.
#
# Premisa del orden, declarada: type viene antes de text en cada content item, y
# role viene antes de content en cada mensaje (es asi en los 308 payloads medidos
# y en todos los hosts conocidos). Si vinieran despues, el text no se emitiria —
# fallo visible (el gate reclama etiquetas), no silencioso. Es consistente con
# como el hook ya depende del orden de campos para todos sus greps de sed.
# (Hallazgo [baja] de la revision cruzada codex, 2026-08-11: la premisa de role
# antes de content no estaba declarada explicitamente.)
assistant_text_transcript() {
  awk '
    {
      linea = $0; n = length(linea)
      depth = 0; ins = 0; esc = 0; espera = 0
      ini = 0; ultima = ""; c1 = ""; c2 = ""; c4 = ""
      en_assistant = 0; en_text = 0; emiti = 0
      for (i = 1; i <= n; i++) {
        c = substr(linea, i, 1)
        if (ins) {
          if (esc) {
            if (espera && en_text && en_assistant && c4 == "text") {
              if      (c == "n")  { printf "\n"; emiti = 1 }
              else if (c == "t")  { printf "\t"; emiti = 1 }
              else if (c == "\\") { printf "\\"; emiti = 1 }
              else if (c == "\"") { printf "\""; emiti = 1 }
              else                { printf "\\%s", c; emiti = 1 }
            }
            esc = 0; continue
          }
          if (c == "\\") { esc = 1; continue }
          if (c == "\"") {
            ins = 0
            ultima = substr(linea, ini, i - ini)
            if (espera) {
              if (depth == 2 && c2 == "role" && ultima == "assistant") en_assistant = 1
              if (depth == 4 && c4 == "type" && ultima == "text") en_text = 1
              espera = 0
            }
            continue
          }
          if (espera && en_text && en_assistant && c4 == "text") { printf "%s", c; emiti = 1 }
          continue
        }
        if (c == "\"") { ins = 1; ini = i + 1; continue }
        if (c == ":")  {
          if (depth == 1) c1 = ultima
          if (depth == 2) c2 = ultima
          if (depth == 4) c4 = ultima
          espera = 1; continue
        }
        if (c == "{" || c == "[") { depth++; if (depth == 4) en_text = 0; espera = 0; continue }
        if (c == "}" || c == "]") {
          # Al cerrar un content item (depth 4->3), si emitimos texto, agregar
          # un salto. Sin esto, dos bloques type:text del mismo mensaje se
          # concatenan ("prefijo" + "Understand: ..." -> "prefijoUnderstand:")
          # y la frontera [^[:alpha:]] de has_receipt_label falla. Hallazgo de
          # la revision cruzada (codex, 2026-08-11).
          if (depth == 4 && emiti) { printf "\n"; emiti = 0 }
          depth--; espera = 0; continue
        }
        if (c == ",")             { espera = 0; continue }
      }
      if (emiti) printf "\n"
    }
  '
}

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | awk 'BEGIN { first = 1 } { gsub(/\r/, ""); if (!first) printf "\\n"; printf "%s", $0; first = 0 }'
}

read_state_value() {
  key="$1"
  if [ ! -f "$STATE_PATH" ]; then return 0; fi
  grep "^$key=" "$STATE_PATH" 2>/dev/null | tail -n 1 | cut -d= -f2-
}

# >>> SAIKIT-REVIEW-NOTICE v1 (parche local, re-aplicado por quality-kit/saikit-gate-heal.ps1) >>>
# ADVISORY-ONLY, NUNCA bloquea el turno: el gate de ceremonia de arriba solo
# comprueba que implementer/verifier/reviewer CORRIERON, no que el codigo
# entregado sea el mismo que se reviso -- el lider podia correr los tres
# subagentes y seguir editando despues, y eso quedaba invisible sin este
# parche. NO agrega motivos de bloqueo a $missing ni cambia ningun exit code.
#
# QUE HACE, en una frase: el Stop gate compara la ultima edicion de codigo
# contra la ultima corrida del reviewer (por NOMBRE de herramienta, sin git,
# sin lanzar un proceso por archivo -- limitacion declarada por escrito en la
# propia linea de log). Si detecta la secuencia mala: (1) una linea CON
# TIMESTAMP en harness-evidence.log, de auditoria; (2) el aviso se guarda en
# su PROPIO archivo (RN_PENDING_PATH) porque $LOG_PATH lo reescribe
# start_harness con '>' al armar el turno siguiente, y lo perderia justo
# cuando hace falta mostrarlo. El PROXIMO turno que se arme (ancla RN-B) lee
# ese archivo, lo antepone al contrato inyectado (ancla RN-H) y lo borra en
# el momento, para que no se repita en el turno de despues.
#
# RN_ORDER_PATH se deriva de STATE_PATH (no de STATE_DIR a secas) para
# heredar automaticamente cualquier sufijo de sesion que ya traiga (la
# variante .codex reescribe STATE_PATH por sesion via resolve_state_paths,
# ANTES de llegar aqui) -- sin esto, dos sesiones de Codex concurrentes en el
# mismo proyecto compartirian un solo contador y se contaminarian entre si.
#
# RN_PENDING_PATH, en cambio, va por PROYECTO a proposito (PROJECT_DIR, sin
# sufijo de sesion — ojo: STATE_DIR ya NO sirve para esto desde la Task 3.4,
# porque ahora lleva sufijo de sesion). Llavearlo por sesion perdia el aviso en
# silencio en la
# variante .codex: el Stop lo escribia bajo la clave de SU sesion y el turno
# siguiente (otra session_id -- otra corrida de la CLI, u otro id del host)
# lo buscaba bajo otra clave y no lo encontraba jamas (fallo observado en la
# bateria, codex NEW (a)). Por proyecto es seguro porque el contenido es una
# CADENA CONSTANTE: dos sesiones concurrentes escribiendo a la vez escriben
# bytes identicos, y que una sesion hermana del mismo proyecto vea el aviso
# es informacion verdadera, no contaminacion. Borde aceptado y documentado:
# el Stop de una sesion con secuencia limpia puede borrar el aviso pendiente
# de otra (el elif de mas abajo) -- para una senal advisory, preferible a
# perder la entrega entre sesiones.
RN_ORDER_PATH="${STATE_PATH%.env}-review-notice.env"
RN_PENDING_PATH="$PROJECT_DIR/review-notice-pending.log"

rn_read_order() {
  rn_key="$1"
  if [ ! -f "$RN_ORDER_PATH" ]; then return 0; fi
  grep "^$rn_key=" "$RN_ORDER_PATH" 2>/dev/null | tail -n 1 | cut -d= -f2-
}

rn_write_order() {
  rn_counter="$1"
  rn_last_code_edit="$2"
  rn_last_review="$3"
  mkdir -p "$STATE_DIR" 2>/dev/null || true
  {
    printf 'counter=%s\n' "$rn_counter"
    printf 'last_code_edit=%s\n' "$rn_last_code_edit"
    printf 'last_review=%s\n' "$rn_last_review"
  } > "$RN_ORDER_PATH" 2>/dev/null || true
}

# Avanza el contador en uno y lo devuelve por stdout. Corre en CADA
# PostToolUse -- mismo costo que el resto de record_tool_evidence, que ya
# hace varias subshells por evento -- nunca itera archivos ni el repo.
rn_bump_counter() {
  rn_counter="$(rn_read_order counter)"
  rn_last_code_edit="$(rn_read_order last_code_edit)"
  rn_last_review="$(rn_read_order last_review)"
  case "$rn_counter" in ''|*[!0-9]*) rn_counter=0 ;; esac
  rn_counter=$((rn_counter + 1))
  rn_write_order "$rn_counter" "$rn_last_code_edit" "$rn_last_review"
  printf '%s' "$rn_counter"
}

rn_mark_code_edit() {
  rn_counter="$(rn_read_order counter)"
  rn_last_review="$(rn_read_order last_review)"
  rn_write_order "$rn_counter" "$1" "$rn_last_review"
}

rn_mark_review() {
  rn_counter="$(rn_read_order counter)"
  rn_last_code_edit="$(rn_read_order last_code_edit)"
  rn_write_order "$rn_counter" "$rn_last_code_edit" "$1"
}

# Clasificacion codigo vs no-codigo para la senal de orden, deliberadamente
# sesgada hacia "es codigo". Normaliza separadores de Windows y mayusculas
# ANTES de clasificar, para que una ruta real de Windows (docs\imagen.png) o
# una extension en mayusculas (README.Md) no caigan del lado equivocado solo
# por como vino escrita.
#
# MEDIO 2 de la revision cruzada (2026-08-08): se suman extensiones de
# tracker/metadata (json/yaml/yml/toml) y lockfiles de dependencias -- pero
# SOLO cuando el nombre del archivo es evidentemente eso: un tracker
# (changelog/status/todo/tracker/version) o un lockfile real (cualquier
# *.lock, mas los nombres fijos que no terminan en .lock como
# package-lock.json). Deliberadamente NO se excluye json/yaml/toml en
# general: ese es el riesgo concreto de una exclusion mas ancha -- un .json
# de CONFIGURACION real (tsconfig.json, la config propia de una app) editado
# despues de revisar tiene que seguir avisando, y una exclusion por extension
# sola lo habria callado.
rn_is_noncode_path() {
  rn_path="$1"
  rn_norm="$(printf '%s' "$rn_path" | tr 'A-Z\134' 'a-z/')"
  rn_base="${rn_norm##*/}"
  case "$rn_norm" in
    *.md|*.txt|*.rst|*.adoc|*.markdown) return 0 ;;
    */docs/*|docs/*) return 0 ;;
    *.lock) return 0 ;;
  esac
  case "$rn_base" in
    package-lock.json|yarn.lock|pnpm-lock.yaml|composer.lock) return 0 ;;
    changelog.json|changelog.yaml|changelog.yml) return 0 ;;
    status.json|status.yaml|status.yml) return 0 ;;
    todo.json|todo.yaml|todo.yml) return 0 ;;
    *tracker*.json|*tracker*.yaml|*tracker*.yml|*tracker*.toml) return 0 ;;
    version.json|version.yaml|version.yml) return 0 ;;
  esac
  return 1
}

# Lee el aviso pendiente del turno anterior (si lo hay) y lo BORRA en el
# mismo paso, para que no se repita en el turno siguiente -- se llama desde
# la ancla RN-B, lo antes posible dentro del camino armado, antes de que
# nada mas lo toque. Fail-open: sin archivo, silencio.
rn_take_pending() {
  if [ ! -f "$RN_PENDING_PATH" ]; then return 0; fi
  cat "$RN_PENDING_PATH" 2>/dev/null || true
  rm -f "$RN_PENDING_PATH" 2>/dev/null || true
}
# <<< SAIKIT-REVIEW-NOTICE v1 <<<
write_state() {
  task_hash="$1"
  cycle="$2"
  implemented="$3"
  verified="$4"
  agents_seen="$5"
  mkdir -p "$STATE_DIR" 2>/dev/null || true
  {
    printf 'task_hash=%s\n' "$task_hash"
    printf 'cycle=%s\n' "$cycle"
    printf 'implemented=%s\n' "$implemented"
    printf 'verified=%s\n' "$verified"
    printf 'agents_seen=%s\n' "$agents_seen"
  } > "$STATE_PATH" 2>/dev/null || true
}

harness_context() {
  cat <<'HARNESS_CONTEXT'
SUMMONAIKIT HARNESS REQUIRED

Who you are working for:
- The person giving you this task is non-technical (a founder, marketer, product manager, designer, or operator). They cannot read code and did not write any. They own WHAT gets built and WHY; you own HOW.
- Talk to them only in plain language: no code, no file names, no library/tool/jargon words in anything you say to them. If a technical detail matters, first explain what it means in one plain sentence.
- Never ask them to make a technical decision (which library, which data model, fail-open vs fail-closed, which framework). Decide those yourself from the repo and tell them the result in plain words.

Run the work as a gated harness:
1. Understand - FIRST, restate the request back in your own plain words so the user can confirm you got it right. If anything about the desired OUTCOME is unclear, ambiguous, or hard to undo, ask short plain-language questions about what they want (never about how to build it) and WAIT for the answer before building. This step is yours as the lead; do not delegate it.
2. Implement - write code and run focused checks while editing.
3. Verify - use fresh-eyes verification and scenario tests where relevant.
4. Review - inspect principles, code quality, regressions, and skill gotchas.
5. Close - reconcile evidence, changed files, skipped checks, and readiness, and explain what changed for the user in plain words.
6. Retro - capture what should improve in the harness or codebase memory.

Asking is not failing:
- When you need an answer before you can do the work well, ask your plain-language questions and then END THE TURN with a final line that reads exactly:
  SUMMONAIKIT HARNESS PAUSED - awaiting your answer
- That line tells the harness you are correctly waiting for the user, so it will not demand a completed receipt. Run the full cycle once they reply.

Delegation rule (Claude):
- Delegate the implement, verify, and review gates to subagents via the Task tool, in this exact sequence:
  1) the implementer subagent, then 2) the verifier subagent, then 3) the reviewer subagent.
- If your host does not surface those project-level agents in the Task tool, delegate to its
  nearest equivalent instead — an engineer/coding agent to implement, a test/QA agent to verify,
  a code-review agent to review. The gate maps host agent names to these roles by function, so a
  correctly-delegated turn still satisfies it.
- You (the lead) handle the Understand step yourself and act as closer and retro: ask the user up front, then reconcile the subagents' evidence and write the final receipt in plain language.
- The turn cannot end until an implementer-, verifier-, and reviewer-role subagent have each run, in that order.

Gate rule:
- Do not advance past a stage without concrete evidence.
- On failure, revise from the first failed gate with structured feedback.
- Revision budget is 2 cycles max. Do not blindly retry.

Context rule:
- Use Context7 for library/framework/API/CLI/cloud basics.
- Use the installed skill references for repo-specific patterns, gotchas, files, and anti-patterns.

Capability-first contract (language/framework/platform agnostic):
- Before adding a new dependency or hand-rolling a mechanism, check — via Context7 and the repo's own deps/config/SDKs — whether the capability the task needs is ALREADY provided by the deploy platform or by a library/framework already installed, and prefer that. Don't add a package for something an installed library already does (e.g. an interaction an existing UI library already supports), and don't reinvent a primitive the platform manages. Identify what's already present from the repo; never assume a provider.
- Run guards (auth/session, validation, authorization) before side effects (email, payments, analytics, storage, persisted writes).
- For ANY guard or limiter, declare its failure stance explicitly — fail-open (allow on guard-infrastructure failure) vs fail-closed (deny on failure) — choose the stance that matches the task's risk, and implement the branch you chose; never leave the failure behavior unstated.
- Before accepting any hand-rolled, in-process, or generic-store implementation of a capability the task needs, first identify the DETECTED platform and look up its OWN native primitive for that SPECIFIC capability (use Context7 and the platform's own docs/SDK/config in the repo). Prefer that native primitive and wire it through the repo's infra/config and typed runtime boundary. A generic durable store is a LAST-RESORT fallback only when no native primitive and no installed library fits; if you fall back, justify in writing why the native primitive does not apply — do not defer the native option to "later".
- The verifier rejects a new dependency or an improvised/in-process/ad-hoc solution when the detected platform or an already-installed library already covers the capability, unless the user explicitly chose otherwise.

Data-source precondition (language/framework/platform agnostic):
- Before building any surface that reads, lists, displays, or reports existing data, first confirm the backing data source actually exists — inspect the repo's schema/models/storage and the procedures or endpoints that would supply it. Do not assume prior data is already captured.
- If the source does NOT exist yet, treat it as a gap: either ask one clarifying question, OR state the assumption EXPLICITLY before coding (for example: this is newly tracked, collection starts now, and there is no historical data to backfill) — and write that assumption into the code itself (a comment or doc on the new source/record path), not only in chat, because reviewers see the diff, not the conversation.
- When a gap is found, the change is a complete slice: create the source, the write path that records new entries going forward, the read path, and the surface that shows them — wired to the existing auth/identity and reusing the repo's own conventions.
- Never claim or imply data that cannot exist yet; what the surface promises must match what is actually recorded.

Missing-information rule (language/framework/platform agnostic):
- Before coding, separate what the REPO can answer (conventions, schema, existing helpers — go read it) from what only the USER can answer (what they want, who it is for, what "done" looks like to them, naming and tone, anything irreversible).
- If a decision that shapes the outcome depends on user-only information, ASK the user the smallest set of key questions FIRST, in plain language, and wait for the answer. A good plain-language question beats a wrong guess. Ask about the outcome they want, never about how to build it.
- Resolve every technical choice yourself from the repo; never hand a non-technical user a technical decision to make.
- Never block on questions the repo already answers, and never silently guess on questions it cannot answer: if you must proceed without an answer, state the assumption in plain words to the user and record it in the diff.

User-facing surface baseline (language/framework/platform agnostic):
- For ANY user-facing surface you add or change, cover the full state matrix explicitly: loading, EMPTY (no data), error, and success — not only the happy path.
- Meet an accessibility baseline: semantic structure (a labelled region/heading, and a list or table for repeated/tabular data rather than nested generic containers), an accessible name for every control and icon-only action, visible keyboard focus, and a working keyboard path.
- Keep it responsive for long or overflowing content, and match the repo's existing component/section style instead of a generic template. Reuse the installed UI library's already-accessible primitives rather than re-implementing them.

Final receipt required before stopping (write every line in plain language a non-technical user can follow):
SUMMONAIKIT HARNESS RECEIPT
Understand: in one or two plain sentences, what the user asked for, plus any question you asked or assumption you made.
Implement: changed files and implementation summary; for any read/listing/reporting surface, state whether its data source already existed or is newly created and the assumption recorded in code; or why no code change was needed.
Verify: exact commands/checks run and results, or skipped with a concrete reason.
Review: findings, risks, or "no findings" with basis.
Close: evidence summary and remaining gaps; state explicitly whether code was touched after the reviewer subagent last ran (yes/no).
Retro: harness/codebase-memory improvement, or "none".
HARNESS_CONTEXT
}

is_engineering_task() {
  text="$1"
  printf '%s' "$text" | grep -Eiq 'implement|fix|debug|build|create|add|change|update|rewrite|refactor|hook|skill|agent|cli|code|test|verify|review|frontend|backend|database|auth|api|schema|migration|component|ui|ux|bug|patch'
}

# Substantive-work signals. When any appear, the task is real implementation and
# the full gate runs even if cosmetic words are also present ("change the auth
# flow" must gate, "change the heading text" must not). Platform/stack-agnostic.
SUBSTANTIVE_RE='implement|feature|endpoint|route|handler|\bapi\b|graphql|schema|migration|database|\bdb\b|\bsql\b|query|model|table|index|transaction|concurren|race condition|\bauth\b|login|signup|sign-?in|session|password|token|oauth|permission|authoriz|payment|billing|checkout|webhook|subscription|invoice|refactor|rewrite|re-?architect|redesign|integrat|algorithm|parser|encrypt|hash|security|vulnerab|injection|rate.?limit|throttle|state machine|workflow|queue|cron|scheduled|background (job|task)|deploy|infrastructure|pipeline|new (page|screen|view|route|component|model|table|service|endpoint|module)|business logic|validation|upload|file handling|cache|caching|websocket|stream'

# Trivial-edit signals. Low-risk, narrow changes that do not need the implement
# -> verify -> review gate (the user can still ask for it explicitly).
TRIVIAL_RE='typo|misspell|spell(ing)?|wording|copywrit|copy edit|rephras|reword|reorder|\btext\b|\blabel\b|caption|placeholder text|heading text|title text|\bstring\b|wording|spacing|whitespace|indent(ation)?|\bformat(ting)?\b|prettier|lint(er)? (fix|warning|error)|^lint$|rename|comment|docstring|\bdocs?\b|documentation|readme|changelog|version bump|bump (the )?version|colou?r|margin|padding|\bfont\b|font.?size|\bpx\b|alignment|capitaliz|punctuation|emoji|trailing (space|whitespace|newline)|semicolon|tweak (the )?(copy|wording|text|spacing|color|colour|margin|padding)'

# A task is trivial when it matches a cosmetic/minor signal AND carries no
# substantive-work signal. Substantive always wins.
is_trivial_task() {
  text="$1"
  if printf '%s' "$text" | grep -Eiq "$SUBSTANTIVE_RE"; then
    return 1
  fi
  printf '%s' "$text" | grep -Eiq "$TRIVIAL_RE"
}

emit_cursor_json() {
  key="$1"
  message="$2"
  escaped="$(json_escape "$message")"
  printf '{"%s":"%s"}\n' "$key" "$escaped"
}

emit_allow() {
  if [ "$TARGET" = "cursor" ]; then
    if [ "$PHASE" = "prompt" ]; then
      printf '{"continue":true}\n'
    else
      printf '{}\n'
    fi
  fi
  exit 0
}

start_harness() {
  prompt_text="$(json_string_field prompt)"
  if [ -z "$prompt_text" ]; then prompt_text="$INPUT"; fi
  # >>> SAIKIT-SENTINEL-GATE v1 >>>
  # El sentinel REEMPLAZA a is_engineering_task / is_trivial_task: es la unica
  # condicion de armado. Dejarlas activas ademas del sentinel hacia que un prompt
  # con -saikit pero sin palabras en ingles siguiera durmiendo. Si lo escribiste,
  # lo quieres. Aplica igual a la fase session, cuyo payload nunca trae sentinel.
  if ! printf '%s' "$prompt_text" | grep -Eq "$SAIKIT_SENTINEL_RE"; then
    # Sin sentinel: si habia estado armado para ESTA sesion, desarmar (borrar).
    # Antes no se tocaba y un turno -saikit abandonado segui cobrando recibo a
    # turnos que no lo pidieron (A4). La correccion al vuelo (prompt CON -saikit)
    # no pasa por aca: re-arma mas abajo y conserva el estado. Acotado a
    # PHASE=prompt: un SessionStart sin sentinel no debe limpiar estado (cursor
    # arma en session con -saikit en el texto, ver caso_g6_armado_por_target).
    if [ "$PHASE" = "prompt" ] && [ -f "$STATE_PATH" ]; then
      rm -f "$STATE_PATH" "$LOG_PATH" "$RN_ORDER_PATH" 2>/dev/null || true  # A4-c2 desarme
    fi
    emit_allow
  fi
  # <<< SAIKIT-SENTINEL-GATE v1 <<<

  task_hash="$(printf '%s' "$prompt_text" | cksum | awk '{print $1}')"
  # >>> SAIKIT-REVIEW-NOTICE v1 >>>
  # Reinicia el contador de orden; STATE_DIR (y por lo tanto RN_ORDER_PATH)
  # persiste entre turnos. El aviso pendiente del turno anterior (si lo hay)
  # se lee y se borra ACA, lo antes posible dentro del camino armado -- antes
  # de que write_state, el log o el contrato hagan nada mas (ancla RN-H mas
  # abajo antepone rn_pending_text al contrato ya armado).
  rm -f "$RN_ORDER_PATH" 2>/dev/null || true
  rn_pending_text="$(rn_take_pending)"
  # <<< SAIKIT-REVIEW-NOTICE v1 <<<
  write_state "$task_hash" "0" "0" "0" ""
  printf 'prompt task started: %s\n' "$task_hash" > "$LOG_PATH" 2>/dev/null || true

  context="$(harness_context)"
  # >>> SAIKIT-REVIEW-NOTICE v1 >>>
  # Antepone el aviso pendiente del turno anterior (si lo hubo) al contrato
  # recien armado. rn_pending_text se leyo y se borro mas arriba (ancla
  # RN-B), antes de que nada mas lo tocara.
  if [ -n "$rn_pending_text" ]; then
    context="$rn_pending_text

$context"
  fi
  # <<< SAIKIT-REVIEW-NOTICE v1 <<<
  escaped="$(json_escape "$context")"

  if [ "$TARGET" = "cursor" ]; then
    if [ "$PHASE" = "session" ]; then
      printf '{"additional_context":"%s"}\n' "$escaped"
    else
      printf '{"continue":true}\n'
    fi
    exit 0
  fi

  printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"%s"}}\n' "$escaped"
  exit 0
}

# Redacta credenciales que viajan en la linea de comandos antes de persistirlas
# en harness-evidence.log. Cierra A5 (Task 3.5): sin esto, un comando con
# token=/password=/://user:pass@ queda en claro en disco hasta que el turno
# cierre -- y una sesion abandonada lo conserva indefinidamente.
#
# BEST-EFFORT contra las tres formas que nombra la DoD, NO un scanner de
# secretos. Postura de fallo: si un patron no matchea, el texto pasa crudo -- el
# peor caso es que algo no se redacte, NUNCA que se altere la decision del gate
# (lane:fast: no toca verified/implemented, solo lo que se escribe al log).
#
# El valor puede venir entrecomillado: sin la alternativa de comillas, un
# `password='hunter two'` filtraba su segunda mitad (hallazgo de la revision
# cruzada con codex). La autoridad de una URI termina en / ? o # (RFC 3986):
# acotar la clase a eso es lo que preserva el host, que es la clausula 2 de la
# DoD. `-E` es POSIX Issue 8 y lo soportan GNU/BSD/busybox; la flag `I` NO se
# usa a proposito (es extension y su fallo es silencioso: sed sale con error y
# la linea del log queda sin detalle).
redact_secrets() {
  printf '%s' "$1" | sed -E \
    -e "s/([Tt][Oo][Kk][Ee][Nn]|[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd])=('[^']*'|\"[^\"]*\"|[^[:space:]]*)/\1=[REDACTED]/g" \
    -e 's,://[^[:space:]@/?#]*@,://[REDACTED]@,g'
}

mark_evidence() {
  kind="$1"
  detail="$2"
  task_hash="$(read_state_value task_hash)"
  cycle="$(read_state_value cycle)"
  implemented="$(read_state_value implemented)"
  verified="$(read_state_value verified)"
  agents_seen="$(read_state_value agents_seen)"
  if [ -z "$task_hash" ]; then task_hash="unknown"; fi
  if [ -z "$cycle" ]; then cycle="0"; fi
  if [ -z "$implemented" ]; then implemented="0"; fi
  if [ -z "$verified" ]; then verified="0"; fi

  if [ "$kind" = "implemented" ]; then implemented="1"; fi
  if [ "$kind" = "verified" ]; then verified="1"; fi
  write_state "$task_hash" "$cycle" "$implemented" "$verified" "$agents_seen"
  printf '%s: %s\n' "$kind" "$(redact_secrets "$detail")" >> "$LOG_PATH" 2>/dev/null || true
}

# Map a host's agent/subagent name onto a canonical harness role
# (implementer | verifier | reviewer | closer | retro), or empty when the name
# carries no harness role. Hosts surface different agent names: Claude Code's
# global set exposes backend-engineer / test-engineer / code-reviewer rather than
# the project-level implementer / verifier / reviewer files SummonAI Kit installs,
# and Cursor/Aider/others differ again. Matching is by role KEYWORD, not a
# hard-coded per-host list, so it stays host-agnostic — any host whose agent name
# names its function resolves to the right gate. Keyword precedence is
# review > verify/test > implement, so a name like "test-engineer" resolves to
# verifier (not implementer via the generic "engineer" signal). Generic agents
# (general-purpose, plan, explore, docs) carry no role and stay unmapped so they
# never satisfy a gate by accident. The leading (^|[^a-z]) boundary matches the
# role stem at a token start only, so "preview" never reads as "review".
# The implement keywords (engineer/build/debug/...) are deliberately broad: any
# engineering/coding agent counts as the implementer. This gate is structural, not
# semantic — it confirms a subagent ran in the implement slot, not that it wrote
# code — and breadth is required so a host's coding agent (Claude Code's
# backend-engineer / data-engineer) resolves; narrowing it would re-break that.
# It never weakens the gate: an implementer match still does not satisfy the
# separate verifier and reviewer slots, which a turn must also fill, in order.
canonical_agent_role() {
  name="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$name" in
    implementer) printf 'implementer'; return 0 ;;
    verifier) printf 'verifier'; return 0 ;;
    reviewer) printf 'reviewer'; return 0 ;;
    closer) printf 'closer'; return 0 ;;
    retro) printf 'retro'; return 0 ;;
  esac
  if printf '%s' "$name" | grep -Eq '(^|[^a-z])(review|critique|critic|audit)'; then printf 'reviewer'; return 0; fi
  if printf '%s' "$name" | grep -Eq '(^|[^a-z])(verif|test|qa|quality|validat)'; then printf 'verifier'; return 0; fi
  if printf '%s' "$name" | grep -Eq '(^|[^a-z])(implement|engineer|developer|coder|build|debug|backend|frontend|fullstack|refactor)'; then printf 'implementer'; return 0; fi
  return 0
}

# Record a harness subagent invocation (any host agent name that normalizes to a
# canonical role) into persistent state so the Stop gate can verify the sequence
# ran — robust to the transcript tail window dropping the Task call.
record_agent() {
  agent="$(canonical_agent_role "$1")"
  if [ -z "$agent" ]; then return 0; fi
  task_hash="$(read_state_value task_hash)"
  cycle="$(read_state_value cycle)"
  implemented="$(read_state_value implemented)"
  verified="$(read_state_value verified)"
  agents_seen="$(read_state_value agents_seen)"
  if [ -z "$task_hash" ]; then task_hash="unknown"; fi
  if [ -z "$cycle" ]; then cycle="0"; fi
  if [ -z "$implemented" ]; then implemented="0"; fi
  if [ -z "$verified" ]; then verified="0"; fi
  case ",$agents_seen," in
    *",$agent,"*) ;;
    *)
      if [ -z "$agents_seen" ]; then agents_seen="$agent"; else agents_seen="$agents_seen,$agent"; fi
      ;;
  esac
  write_state "$task_hash" "$cycle" "$implemented" "$verified" "$agents_seen"
  printf 'agent: %s\n' "$agent" >> "$LOG_PATH" 2>/dev/null || true
}

record_tool_evidence() {
  # >>> SAIKIT-SENTINEL-GATE v1 >>>
  # Sin tarea armada NO se crea archivo de estado. Si no, mark_evidence lo crearia
  # con task_hash=unknown en cualquier edicion y el Stop gate se activaria solo,
  # anulando el sentinel.
  if [ ! -f "$STATE_PATH" ]; then emit_allow; fi
  # <<< SAIKIT-SENTINEL-GATE v1 <<<
  event_name="$(json_string_field hook_event_name)"
  tool_name="$(json_string_field tool_name)"
  command_text="$(json_string_field command)"
  file_path="$(json_string_field file_path)"
  combined="$event_name $tool_name $command_text $file_path $INPUT"

  # Record harness subagent runs (the delegation tool carries a subagent_type in
  # its tool_input) so the Stop gate can enforce the implementer -> verifier ->
  # reviewer sequence. Se lee SOLO de `tool_input` de primer nivel: el resto del
  # payload trae el resultado de la herramienta, que el turno no escribio (A1).
  subagent="$(json_tool_input_string subagent_type)"
  if [ -z "$subagent" ]; then subagent="$(json_tool_input_string subagentType)"; fi
  # A9 (Task 3.7): los eventos INTERNOS del subagente (los que matchean el
  # matcher y llegan al gate) llevan el rol en agent_type de PRIMER NIVEL, no en
  # subagent_type (que solo esta en los eventos Agent, que el matcher no cubre).
  # Medido en la captura de 3.7 (9 de 12 PostToolUse con agent_type top-level).
  # Es FALLBACK, no reemplazo: si subagent_type llega, gana. Un agent_type sin rol
  # (general-purpose, Explore) no registra nada porque canonical_agent_role no lo
  # mapea. OJO: $subagent tiene un segundo consumidor abajo (rn_mark_review,
  # bloque :834-839), asi que esto tambien enciende la senal de orden del
  # review-notice. Es deliberado y esta declarado en el plan (CORRECCION 3):
  # marcar el ultimo evento interno del reviewer data cuando la revision corrio,
  # no cuando se pidio.
  if [ -z "$subagent" ]; then subagent="$(json_top_level_string agent_type)"; fi
  if [ -n "$subagent" ]; then record_agent "$subagent"; fi
  # >>> SAIKIT-REVIEW-NOTICE v1 >>>
  rn_order_now="$(rn_bump_counter)"
  if [ -n "$subagent" ] && [ "$(canonical_agent_role "$subagent")" = "reviewer" ]; then
    rn_mark_review "$rn_order_now"
  fi
  # <<< SAIKIT-REVIEW-NOTICE v1 <<<

  if printf '%s' "$combined" | grep -Eiq 'afterFileEdit|Edit|Write|apply_patch|file_path|edits'; then
    mark_evidence "implemented" "${file_path:-file edit}"
  fi

  # >>> SAIKIT-REVIEW-NOTICE v1 >>>
  # Senal PRECISA para el orden, distinta del grep laxo de arriba (ese matchea
  # casi cualquier payload que mencione "edit" o una ruta). Solo cuenta un
  # tool_name realmente de edicion MAS un file_path real; sin ambos, no se
  # registra nada -- mejor perder una edicion que fecharla mal. Por diseno
  # (pedido explicito) esta senal NUNCA lanza git ni un proceso por archivo:
  # es solo el nombre de la herramienta del evento que el hook ya recibe.
  if [ -n "$file_path" ] && printf '%s' "$tool_name" | grep -Eiq '^(edit|write|multiedit|notebookedit|apply_patch|str_replace_editor|create_file|edit_file)$'; then
    if ! rn_is_noncode_path "$file_path"; then
      rn_mark_code_edit "$rn_order_now"
    fi
  fi
  # <<< SAIKIT-REVIEW-NOTICE v1 <<<

  # Credit verification only when a test/type-check RUNNER appears in the COMMAND
  # (tool_name + command), never in a file path or the raw payload — otherwise
  # editing vitest.config.ts or reading a Gemfile.lock that names rspec would
  # falsely mark the work verified. The failure-signal guard still consults the
  # full payload, since exit codes live in the tool result, not the command.
  if printf '%s' "$tool_name $command_text" | grep -Eiq "$TEST_RUNNER_WORD_RE"; then
    if ! printf '%s' "$combined" | grep -Eiq 'exitCode[^0-9]*[1-9]|failure_type|permission_denied|command not found'; then
      mark_evidence "verified" "${command_text:-verification command}"
    fi
  fi

  emit_allow
}

has_receipt_label() {
  label="$1"
  alt="$2"
  text="$3"
  printf '%s' "$text" | grep -Eiq "(^|[^[:alpha:]])($label|$alt)[[:space:]]*:"
}

build_gate_feedback() {
  missing="$1"
  next_cycle="$2"
  cat <<EOF
SUMMONAIKIT HARNESS GATE

Failed gates:
$missing

Structured revision required:
1. Return to the first missing gate.
2. Use real evidence, not a marker file or a claim.
3. Preserve the Context7 split: Context7 for library basics, skill references for repo gotchas.
4. End with the required SUMMONAIKIT HARNESS RECEIPT.

Revision loop on failure:
- Current revision cycle: $next_cycle/$MAX_CYCLES.
- Budget: 2 cycles max.
- Do not blindly retry.

Required receipt shape (each gate is one line that BEGINS with its label and a colon, inside the receipt block; write them in plain language):
SUMMONAIKIT HARNESS RECEIPT
Understand: ...
Implement: ...
Verify: ...
Review: ...
Close: ...
Retro: ...
EOF
}

emit_gate_failure() {
  feedback="$1"
  if [ "$TARGET" = "cursor" ]; then
    emit_cursor_json "followup_message" "$feedback"
    exit 0
  fi

  escaped="$(json_escape "$feedback")"
  printf '{"decision":"block","reason":"%s"}\n' "$escaped"
  printf '%s\n' "$feedback" >&2
  exit 2
}

emit_budget_exhausted() {
  missing="$1"
  message="SUMMONAIKIT HARNESS REVISION BUDGET EXHAUSTED

The harness gate failed after 2 structured revision cycles.

Still missing:
$missing

Stop now, report the failed gates, and ask the user before another retry."

  if [ "$TARGET" = "cursor" ]; then
    emit_cursor_json "followup_message" "$message"
    exit 0
  fi

  escaped="$(json_escape "$message")"
  printf '{"continue":false,"stopReason":"%s"}\n' "$escaped"
  printf '%s\n' "$message" >&2
  exit 0
}

# Decide si una ruta de transcript esta DENTRO del directorio de perfil del host.
# Cierra A6 (Task 3.6): transcript_path viene del payload, y hacerle tail sin
# acotar es una primitiva de lectura de archivo arbitrario. El perfil es
# dirname(HOOK_DIR): en install global ~/.claude, que contiene projects/ donde
# Claude Code guarda los transcripts reales. Una ruta fuera del perfil se rechaza.
#
# Por que el perfil y no "el dir de transcripts": ese dir no es derivable de forma
# portable (la codificacion de la ruta del proyecto es interna del host; zcode usa
# otro layout en la Phase 5; el banco escribe en $sb/entrada). El perfil es un
# superset derivable que igual cierra la lectura arbitraria de /etc/passwd,
# ~/.ssh/id_rsa, el repo, %APPDATA%, etc.
#
# POR QUE cd+pwd Y NO COMPARAR EL STRING (medido, no supuesto): json_string_field
# NO decodifica escapes, asi que en Windows transcript_path llega como
# C:\\Users\\...\\x.jsonl (backslashes DOBLES literales) mientras HOOK_DIR llega
# como /c/Users/... . Comparar prefijos crudos daria FUERA siempre y apagaria el
# canal transcript en toda la produccion. cd+pwd lleva las dos a la misma forma
# (/c/Users/ehven/.claude, o /tmp/... en el banco via el mount virtual de MSYS), y
# de paso normaliza .. y symlinks. El "/" separador del segundo patron evita que
# ~/.claude haga sombra sobre ~/.claude-otro.
#
# Fail-open (Core Rule 2): todo lo que no se puede afirmar como dentro devuelve
# falso, el transcript se trata como no observado (transcript=unknown) y el gate
# corre con el otro canal -- mismo desenlace que un archivo ilegible. El guardia
# de PROFILE_DIR vacio NO se puede colapsar: con la variable vacia el patron
# "$PROFILE_DIR"/* se vuelve /* y aceptaria CUALQUIER ruta absoluta, o sea la
# contencion entera abierta.
#
# Limites declarados: sigue symlinks (uno bajo el perfil que apunte afuera se
# resuelve a su destino real y podria quedar fuera); y el STAGING (hook en
# <repo>/.claude/hooks) deja su transcript en ~/.claude/projects, fuera de
# <repo>/.claude, asi que en staging el canal transcript queda desactivado y el
# gate corre solo con last_assistant_message. Es aceptable: el gate es advisory,
# el recibo en un payload real de Claude viaja por last_assistant_message (medido
# Task 1.4), y staging es diagnostico. El reporte por stderr se lo dice al
# operador. Lo que queda adentro del perfil (.credentials.json, history.jsonl,
# transcripts de otras sesiones) sigue legible: la contencion acota la raiz, no es
# un permiso por archivo -- declarado en el plan.
transcript_en_perfil() {
  if [ -n "$PROFILE_DIR" ]; then
    _tp_dir="$(cd "$(dirname "$1")" 2>/dev/null && pwd)" || _tp_dir=""
    case "$_tp_dir" in
      "$PROFILE_DIR"|"$PROFILE_DIR"/*) return 0 ;;
    esac
  fi
  printf 'summonaikit-harness: transcript_path fuera del perfil del host (%s); se ignora, transcript=unknown (fail-open, no bloquea)\n' "$1" >&2
  return 1
}

stop_gate() {
  if [ ! -f "$STATE_PATH" ]; then
    emit_allow
  fi

  transcript_path="$(json_string_field transcript_path)"
  tail_text=""
  if [ -n "$transcript_path" ] && [ -r "$transcript_path" ] && transcript_en_perfil "$transcript_path"; then
    tail_text="$(tail -n 160 "$transcript_path" 2>/dev/null || true)"
  fi
  # Task 3.2: $text se arma con SOLO texto del asistente, decodificado, de los
  # dos canales (last_assistant_message + content[].text role:assistant del tail).
  # Antes era $INPUT + tail crudo, que incluia tool_result y los \n escapados del
  # JSONL — raiz de A2 (exige de menos) y A8 (exige de mas). El tail -n 160 se
  # conserva como recorte: leer el transcript entero agrandaria el hueco (un
  # recibo de hace 5 turnos satisfaria el gate) y es caro en Windows. Ver
  # docs/task-3.2-plan.md CORRECCION 2.
  text="$(assistant_text_payload)
$(printf '%s' "$tail_text" | assistant_text_transcript)"

  # A clarifying pause is a valid way to end the turn: the agent asked the
  # non-technical user a question and is waiting for the answer. Do not demand a
  # receipt or the implement -> verify -> review sequence in that case.
  if printf '%s' "$text" | grep -Eiq 'SUMMONAIKIT HARNESS PAUSED'; then
    emit_allow
  fi

  implemented="$(read_state_value implemented)"
  verified="$(read_state_value verified)"
  cycle="$(read_state_value cycle)"
  task_hash="$(read_state_value task_hash)"
  agents_seen="$(read_state_value agents_seen)"
  if [ -z "$implemented" ]; then implemented="0"; fi
  if [ -z "$verified" ]; then verified="0"; fi
  if [ -z "$cycle" ]; then cycle="0"; fi
  if [ -z "$task_hash" ]; then task_hash="unknown"; fi

  missing=""
  if ! printf '%s' "$text" | grep -Eiq 'SUMMONAIKIT HARNESS RECEIPT'; then
    missing="$missing- Missing SUMMONAIKIT HARNESS RECEIPT.\n"
  fi
  if ! has_receipt_label "Understand" "Capito" "$text"; then
    missing="$missing- Missing Understand gate summary (add a line beginning 'Understand:' inside the SUMMONAIKIT HARNESS RECEIPT block, restating the request in plain words). If you instead need to ask the user first, end the turn with the line 'SUMMONAIKIT HARNESS PAUSED - awaiting your answer'.\n"
  fi
  if ! has_receipt_label "Implement" "Implementazione" "$text"; then
    missing="$missing- Missing Implement gate summary (add a line beginning 'Implement:' inside the SUMMONAIKIT HARNESS RECEIPT block).\n"
  fi
  if ! has_receipt_label "Verify" "Verifica" "$text"; then
    missing="$missing- Missing Verify gate summary (add a line beginning 'Verify:' inside the SUMMONAIKIT HARNESS RECEIPT block).\n"
  fi
  if ! has_receipt_label "Review" "Revisione" "$text"; then
    missing="$missing- Missing Review gate summary (add a line beginning 'Review:' inside the SUMMONAIKIT HARNESS RECEIPT block).\n"
  fi
  if ! has_receipt_label "Close" "Chiusura" "$text"; then
    missing="$missing- Missing Close gate summary (add a line beginning 'Close:' inside the SUMMONAIKIT HARNESS RECEIPT block).\n"
  fi
  if ! has_receipt_label "Retro" "Retrospettiva" "$text"; then
    missing="$missing- Missing Retro gate summary (add a line beginning 'Retro:' inside the SUMMONAIKIT HARNESS RECEIPT block).\n"
  fi
  if [ "$verified" != "1" ] && ! printf '%s' "$text" | grep -Eiq "$TEST_RUNNER_WORD_RE|not run|not executed|skipped|non eseguit|saltat"; then
    missing="$missing- Missing verification evidence or explicit skipped-check reason.\n"
  fi

  # Sequential subagent enforcement (Claude only — Task/subagent_type is a Claude
  # Code primitive). The first three gates must each run as their own subagent,
  # in order. closer/retro stay receipt sections the lead writes.
  if [ "$TARGET" = "claude" ]; then
    case ",$agents_seen," in
      *",implementer,"*) ;;
      *) missing="$missing- Missing implementer subagent run (delegate the change via the Task tool).\n" ;;
    esac
    case ",$agents_seen," in
      *",verifier,"*) ;;
      *) missing="$missing- Missing verifier subagent run (delegate verification via the Task tool).\n" ;;
    esac
    case ",$agents_seen," in
      *",reviewer,"*) ;;
      *) missing="$missing- Missing reviewer subagent run (delegate review via the Task tool).\n" ;;
    esac
    if printf '%s' "$agents_seen" | grep -q implementer && printf '%s' "$agents_seen" | grep -q verifier && printf '%s' "$agents_seen" | grep -q reviewer; then
      if ! printf '%s' "$agents_seen" | grep -Eq 'implementer.*verifier.*reviewer'; then
        missing="$missing- Subagents ran out of order; required sequence is implementer -> verifier -> reviewer.\n"
      fi
    fi
  fi

  # >>> SAIKIT-REVIEW-NOTICE v1 >>>
  # Chequeo ADVISORY: compara el evento de la ultima edicion de codigo contra
  # el evento de la ultima corrida del reviewer. NUNCA agrega un motivo a
  # $missing ni cambia el exit code. Corre en CADA llamada al Stop gate (no
  # solo en el cierre limpio), asi que un ciclo de revision (gate fallido, el
  # agente sigue editando, Stop se llama de nuevo) siempre ve el estado MAS
  # RECIENTE: si la secuencia mala ya no esta (por ejemplo corrio el reviewer
  # de nuevo despues), el elif de abajo borra un aviso pendiente que hubiera
  # quedado desactualizado de un intento anterior del mismo turno. Postura de
  # fallo: si el contador no existe, no se puede leer, o trae basura no
  # numerica (los dos campos vacios), NO se toca nada -- ni se escribe ni se
  # borra (nunca ruido, nunca un falso "todo bien").
  rn_check_last_code_edit="$(rn_read_order last_code_edit)"
  rn_check_last_review="$(rn_read_order last_review)"
  case "$rn_check_last_code_edit" in ''|*[!0-9]*) rn_check_last_code_edit="" ;; esac
  case "$rn_check_last_review" in ''|*[!0-9]*) rn_check_last_review="" ;; esac
  rn_notice_fired=""
  if [ -n "$rn_check_last_code_edit" ] && [ -n "$rn_check_last_review" ] && [ "$rn_check_last_code_edit" -gt "$rn_check_last_review" ] 2>/dev/null; then
    rn_ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)"
    printf '%s review-notice: code was edited after the last reviewer subagent run (tool-name signal only -- an edit made via a shell command, e.g. sed/heredoc/git apply, is NOT detected by this check).\n' "$rn_ts" >> "$LOG_PATH" 2>/dev/null || true
    mkdir -p "$STATE_DIR" 2>/dev/null || true
    printf 'SAIKIT REVIEW NOTICE: in your previous turn, code was edited after the reviewer subagent last ran, and those edits were not reviewed.\n' > "$RN_PENDING_PATH" 2>/dev/null || true
    rn_notice_fired="1"
  elif [ -n "$rn_check_last_code_edit" ] || [ -n "$rn_check_last_review" ]; then
    rm -f "$RN_PENDING_PATH" 2>/dev/null || true
  fi
  # <<< SAIKIT-REVIEW-NOTICE v1 <<<
  if [ -z "$missing" ]; then
    # >>> SAIKIT-REVIEW-NOTICE v1 >>>
    rm -f "$RN_ORDER_PATH" 2>/dev/null || true
    # Canal INMEDIATO (ademas del pendiente que lee el turno siguiente): en un
    # cierre limpio donde el aviso disparo, se emite el campo systemMessage
    # del contrato de hooks de Claude Code -- documentado como universal, se
    # muestra AL USUARIO y no toca la decision (sin campo decision + exit 0 =
    # allow igual que siempre). Asi el usuario se entera al final del MISMO
    # turno, no recien cuando vuelva a armar -saikit en este proyecto. Solo
    # target no-cursor, el mismo criterio que ya usa emit_gate_failure (el
    # vendor emite JSON estilo Claude para todo lo que no es cursor). Si el
    # host ignorase este stdout en exit 0, el peor caso es el silencio de hoy
    # (fail-open); el pendiente del turno siguiente sigue existiendo igual.
    if [ "$rn_notice_fired" = "1" ] && [ "$TARGET" != "cursor" ]; then
      printf '{"systemMessage":"SAIKIT REVIEW NOTICE: code was edited after the reviewer subagent last ran in this turn; those edits were not re-reviewed. The next -saikit turn on this project will see this notice too. (Tool-name signal only -- edits made via shell commands are not detected.)"}\n'
    fi
    # <<< SAIKIT-REVIEW-NOTICE v1 <<<
    rm -f "$STATE_PATH" "$LOG_PATH" 2>/dev/null || true
    emit_allow
  fi

  if [ "$cycle" -ge "$MAX_CYCLES" ] 2>/dev/null; then
    # Presupuesto agotado limpia el estado de ESTA sesion (STATE_PATH/LOG_PATH/
    # RN_ORDER_PATH). RN_PENDING_PATH queda (per-project, ver comentario
    # REVIEW-NOTICE). Sin esto, cycle=MAX sobrevivia en disco y el turno seguia
    # cobrando recibo despues de declararse agotado (A4).
    rm -f "$STATE_PATH" "$LOG_PATH" "$RN_ORDER_PATH" 2>/dev/null || true  # A4-c4 presupuesto
    emit_budget_exhausted "$missing"
  fi

  next_cycle=$((cycle + 1))
  write_state "$task_hash" "$next_cycle" "$implemented" "$verified" "$agents_seen"
  feedback="$(build_gate_feedback "$missing" "$next_cycle")"
  emit_gate_failure "$feedback"
}

if [ -z "$PHASE" ]; then
  event="$(json_string_field hook_event_name)"
  case "$event" in
    UserPromptSubmit|beforeSubmitPrompt) PHASE="prompt" ;;
    SessionStart|sessionStart) PHASE="session" ;;
    Stop|stop) PHASE="stop" ;;
    *) PHASE="tool" ;;
  esac
fi

case "$PHASE" in
  prompt|session) start_harness ;;
  tool) record_tool_evidence ;;
  stop|verify) stop_gate ;;
  *) emit_allow ;;
esac
