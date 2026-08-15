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
# Task 9.5 (C10): la frontera IZQUIERDA excluye tambien `/` y `-`. Sin eso,
# REFERENCIAR un archivo (`docs/-saikit.md`) o citar un flag (`--saikit`) armaba
# la ceremonia entera — el mismo dano que `x-saikit`, por dos caracteres que
# faltaban en la clase. El `-` va ULTIMO en el bracket para que sea literal.
#
# Lo que sigue armando, atado por controles en caso_g1_sentinel_con_frontera:
# inicio de texto, espacio, `(`, `,`, comillas y `\n` decodificado. Apretar de
# mas aca seria repetir A8 (un recibo legitimo que deja de contar), por eso los
# controles positivos viven en el MISMO caso que los negativos.
#
# La deteccion del carril `:fast` (Task 10.1) ya usaba esta frontera apretada;
# esto alinea el sentinel con ella en vez de tener dos criterios distintos.
SAIKIT_SENTINEL_RE='(^|[^A-Za-z0-9_/-])-saikit([^A-Za-z0-9_-]|$)'
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
# A10 en zcode (Task 5.4): CLAUDECODE no llega (zcode no lo setea), asi que la
# secuencia nunca se exigia en el segundo host. zcode inyecta ZCODE_SESSION_ID /
# ZCODE_PROJECT_DIR (medido 5.1); con esa senal TARGET resuelve a "claude" y la
# ceremonia implementer->verifier->reviewer corre. No se crea TARGET=zcode: las
# formas de salida medidas (5.2) son las mismas que en Claude. glm sigue por
# CLAUDECODE=1 (exec claude) y no llega aca.
if [ -z "$TARGET" ] && [ -n "${ZCODE_SESSION_ID:-}${ZCODE_PROJECT_DIR:-}" ]; then
  TARGET="claude"
fi
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
# Task 5.3 (A4-cross-host): aislar el estado por host. Si el harness se registra
# desde zcode apuntando al MISMO $0 que Claude (~/.claude/hooks/…), STATE_ROOT
# (dirname $0) es identico y dos turnos sobre el mismo repo con la misma sesion
# escribian el mismo harness-state.env: un cierre de zcode pisaba el turno de
# Claude. La senal de host es el env (medido Task 5.1): ZCODE_SESSION_ID o
# ZCODE_PROJECT_DIR los inyecta zcode; CLAUDECODE=1 lo inyecta Claude/glm (A10).
# ZCODE_* gana: zcode setea CLAUDE_SESSION_ID/CLAUDE_PROJECT_DIR pero NO
# CLAUDECODE (5.1). HOST NO depende del payload, solo del env, asi que se
# resuelve aca (junto a PROFILE_DIR) sin esperar a los lectores JSON. unknown
# => other, NUNCA claude: colapsar a claude reabre el defecto cuando la senal
# falta (Core Rule 2). HOST se SUMA a la sesion (A4), no la reemplaza.
if [ -n "${ZCODE_SESSION_ID:-}${ZCODE_PROJECT_DIR:-}" ]; then
  HOST=zcode
elif [ "${CLAUDECODE:-}" = "1" ]; then
  HOST=claude
else
  HOST=other
fi
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

# Task 9.10 r2 (cross-review codex r1, hallazgo ALTA) — el runner bash propio
# del kit (`bash tests/run.sh`, el gate FINAL de este repo) vive en una
# constante PROPIA, aplicada SIN el wrapper de abajo. La r1 de 9.10 lo metio
# como dos ramas mas de TEST_RUNNER_RE y el wrapper — que solo sabe de
# FRONTERAS DE PALABRA, no de posicion — dejo pasar decoys: `bash
# contest/run.sh` ("contest" termina en "test"), `bash tests/run.sh/typo` (el
# `/` pasa por frontera derecha), y `grep/printf/echo bash tests/run.sh` (un
# espacio o comilla antes del verbo pasa la frontera izquierda). Todos
# acreditaban verified=1 sin correr la suite.
#
# TEST_RUNNER_CMD_RE exige POSICION DE COMANDO: inicio, o tras un separador de
# shell (; & | && ||); luego el verbo shell opcional (bash/zsh/dash/ksh/sh) o
# la invocacion directa; y segmentos de path ESTRICTOS — `([^/[:space:]]*/)*`
# seguido de `tests?/run\.sh` textual — para que "contest/run.sh" no matchee.
# El terminador `([[:space:]]|$)` impide sufijos typo ("/typo") y admite args
# despues del runner. OJO a por que NO va adentro de TEST_RUNNER_RE: el
# wrapper envuelve la alternacion ENTERA con `(^|[^A-Za-z0-9_.-])` — una rama
# que empieza en un separador quedaria fuera porque el char previo al `&&` es
# un word char (`/repo&&`), y un terminador interno compone mal con el grupo
# de frontera derecha del wrapper (consumiria el espacio y exigiria otro
# boundary sobre la palabra siguiente). Por eso esta constante se aplica
# aparte, en los DOS sitios donde el gate decide credito de verificacion.
#
# Limites declarados del lado estricto (sin credito el gate pide la razon,
# que es recuperable): `bash -e tests/run.sh` (espacio entre flag y ruta),
# `bash tests/run.sh&&otro` (sin espacio tras el runner) y el runner dentro de
# comillas NO cuentan. En la PROSA del recibo solo cuentan los runners
# clasicos (WORD_RE): una linea "Verify: bash tests/run.sh" no esta en
# posicion de comando — el credito del carril run.sh vive en el EVENTO.
TEST_RUNNER_CMD_RE='(^|[;&|](&|\|)?[[:space:]]+)(ba|z|da|k)?sh[[:space:]]+([^/[:space:]]*/)*tests?/run\.sh([[:space:]]|$)|(^|[;&|](&|\|)?[[:space:]]*)(\./)?([^/[:space:]]*/)*tests?/run\.sh([[:space:]]|$)'

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

# Skip explicito de verificacion (prosa del recibo). EN+IT de siempre; ES
# del vivo zcode 2026-08-13 ("No corri los candados"). Las formas con
# acento van en UTF-8 literal para matchear el payload aunque LANG=C.
# NO incluir "se corrio" suelto: el recibo que afirma que SI corrio la
# bateria (_RECIBO_SIN_RETRO) debe seguir pidiendo evidencia.
VERIFY_SKIP_RE='not run|not executed|skipped|non eseguit|saltat|no corri|no corrí|no se corrio|no se corrió|no se corrieron|no se ejecuto|no se ejecutó|no se ejecutaron|sin tests'

# Failure-signal patterns for the verification guard (record_tool_evidence).
# A11 (medido 59/59, Task 1.4): el tool_response real de Bash NO trae exitCode,
# asi que la unica forma de detectar que un runner revento es el TEXTO de su
# stdout/stderr. La rama vieja `exitCode[^0-9]*[1-9]` era codigo muerto y se
# retiro. Se divide en DOS regex porque -i es global en grep y case-sensitive
# iria mezclado con CI:
#
# CI (case-insensitive, -Eiq):
# - failure_type|permission_denied|command not found: las 3 originales (rechazo
#   o ausencia del tool). Se conservan para no romper los casos que ya viven.
# - AssertionError:|AssertionFailedError: — Node assert, pytest E-line, JUnit.
#   OJO (H2, cross-review codex 2026-08-12): se exige `:` despues del nombre
#   porque $combined incluye command_text, y sin el `:` un runner exitoso cuyo
#   COMANDO menciona la excepcion (p. ej. `pytest tests/test_typeerror.py`)
#   matcheaba como si hubiera fracasado. Los tracebacks reales siempre traen el
#   `:` (Exception: mensaje); los nombres de archivo, no.
# - Traceback (most recent call last): Python crudo sin pytest.
# - SyntaxError:|TypeError:|ReferenceError:|RangeError: — crashes JS/Python.
#   Mismo razonamiento del `:` que AssertionError.
# - error TS[0-9]: tsc en fracaso (su senal especifica, sin la palabra `failed`).
# - [1-9][0-9]*[[:space:]]+(failed|failing|failures?|errors?): pytest
#   `=== 1 failed ===`, vitest/jest `1 failed`, mocha `1 failing`, rspec
#   `1 failure`/`2 failures`, pytest `1 error`. La frontera del digito NO-cero
#   evita matchear `0 failed`, `0 errors` (limites medidos).
# - (failures?|errors?)[=:]([[:space:]]*)?[1-9]: phpunit `Failures: 1`,
#   unittest Python `failures=1`, `Errors: 5`. El digito NO-cero evita
#   `Failures: 0`.
FAILURE_SIGNAL_RE_CI='failure_type|permission_denied|command not found|AssertionError:|AssertionFailedError:|Traceback \(most recent call last\)|SyntaxError:|TypeError:|ReferenceError:|RangeError:|error TS[0-9]|[1-9][0-9]*[[:space:]]+(failed|failing|failures?|errors?)|(failures?|errors?)[=:]([[:space:]]*)?[1-9]'
# CS (case-SENSITIVE, -Eq, sin -i): frases literales donde -i daria falso
# positivo en prosa del log (`0 failures!`, `failed to connect`, `--- fail:`).
# Cubre los runners cuya senal de fracaso no trae numero inmediato. OJO: $combined
# es una sola linea (json_string_field colapsa saltos), asi que NO se puede usar
# `^FAIL`: el `FAIL` de go viaja DENTRO del JSON del payload, precedido por la
# comilla de `"stderr":"FAIL\t...`. Por eso `FAIL[^a-zA-Z]` sin ancla de inicio.
# - test result: FAILED. — cargo test.
# - FAIL[^a-zA-Z] — go test: `FAIL\tpkgname` (el `\` despues de FAIL no es letra).
#   No choca con `FAILED`/`FAILURES` (FAIL seguido de letra no matchea) ni con
#   `failed` (case-sensitive). Limite declarado: `test_FAIL.py` en un comando
#   que pasa seria falso positivo (raro, declarado).
# - FAILURES! — banner de phpunit.
# - ---[[:space:]]+FAIL: — go test individual (`--- FAIL: TestX`).
FAILURE_SIGNAL_RE_CS='test result: FAILED|FAIL[^a-zA-Z]|FAILURES!|---[[:space:]]+FAIL:'

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
# Task 5.3: HOST entra en PROJECT_DIR para que dos hosts sobre el mismo $0 no
# compartan estado. RN_PENDING_PATH hereda HOST de aca (ver comentario
# REVIEW-NOTICE): NO volver a colgarlo de un path sin HOST.
PROJECT_DIR="$STATE_ROOT/$HOST/$PROJECT_KEY"
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

# Como json_top_level_string pero DECODIFICANDO los escapes \n \" \\ \t del
# valor (los demas quedan crudos, mismo criterio medido de assistant_text_payload:
# no aparecen en los 308 payloads de la 1.4 y un escape no manejado cae del lado
# seguro). Cierra C1+C2 (auditoria 2026-08-13, Task 8.1) para el prompt:
#
# - C1: json_string_field cortaba el valor en la primera \" — `arregla el "bug"
#   -saikit` llegaba truncado y NO armaba; peor, una correccion CON sentinel y
#   con comillas antes tomaba la rama de DESARME y borraba el estado a media
#   ceremonia.
# - C2: el sentinel se grepeaba sobre el JSON crudo — un \n literal antes de
#   `-saikit` deja una `n` alfanumerica pegada y la frontera izquierda de
#   SAIKIT_SENTINEL_RE rechaza; el prompt multilinea con el sentinel en su
#   propia linea (la colocacion mas natural) jamas armaba.
#
# Decodificar es lo que vuelve reales la comilla y el salto que el usuario
# escribio. Es el gemelo parametrizado de assistant_text_payload (mismo escaner,
# mismo emisor); aquella queda como esta porque su clave es fija y sus casos ya
# la atan.
json_top_level_decoded() {
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
            if (espera && depth == 1 && c1 == want) { emiti = 0; exit }
            continue
          }
          if (emiti) printf "%s", c
          continue
        }
        if (c == "\"") {
          ins = 1; ini = i + 1
          if (espera && depth == 1 && c1 == want) emiti = 1
          continue
        }
        if (c == ":")                  { if (depth == 1) c1 = ultima; espera = 1 }
        else if (c == "{" || c == "[") { depth++; espera = 0 }
        else if (c == "}" || c == "]") { depth--; espera = 0 }
        else if (c == ",")             { espera = 0 }
      }
    }'
}

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
# Task 5.3: PROJECT_DIR ahora lleva HOST, asi que RN_PENDING tambien se aísla
# por host — un Stop de zcode no puede tomar/borrar el aviso pendiente de Claude.
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
# Task 10.1: write_state persiste tambien el carril (lane = full | fast). Un
# estado sin el campo (sembrado por el banco, o escrito por un hook previo a la
# 10.1) lee lane="" — y "" != "fast", o sea que el default ausente es el lado
# SEGURO: ceremonia completa. Ningun call site inventa un lane.
write_state() {
  task_hash="$1"
  cycle="$2"
  implemented="$3"
  verified="$4"
  agents_seen="$5"
  lane="$6"
  mkdir -p "$STATE_DIR" 2>/dev/null || true
  {
    printf 'task_hash=%s\n' "$task_hash"
    printf 'cycle=%s\n' "$cycle"
    printf 'implemented=%s\n' "$implemented"
    printf 'verified=%s\n' "$verified"
    printf 'agents_seen=%s\n' "$agents_seen"
    printf 'lane=%s\n' "$lane"
  } > "$STATE_PATH" 2>/dev/null || true
}

harness_context() {
  cat <<'HARNESS_CONTEXT'
SUMMONAIKIT HARNESS REQUIRED

Who you are working for:
- They own WHAT gets built and WHY; you own HOW.
- Adapt your register to the person you are actually working with: do not assume they cannot read code, and do not throw jargon at them without explaining it. If a technical term matters, explain what it means before you rely on it.
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
- That line tells the harness you are correctly waiting for the user, so it will not demand a completed receipt. Their reply will usually not carry -saikit, and a prompt without the sentinel stands the gate down by design; the cycle you promised still applies — run it yourself when they reply, or ask them to include -saikit in the reply to keep the gate enforced.

Waiting on a subagent is not failing:
- A delegated implementer/verifier/reviewer subagent can take a long time to answer (tens of minutes is normal). Do not stall the turn waiting on it, and do not close it with a receipt you cannot honestly write yet.
- While you are waiting on that subagent, END THE TURN with a final line that reads exactly, naming the role you delegated to:
  SUMMONAIKIT HARNESS DELEGATED - awaiting <ROLE>
  where <ROLE> is implementer, verifier, or reviewer — naming one of those three is what makes the line count.
- That line tells the harness you are correctly waiting on a subagent, so it will not demand a completed receipt. As soon as that subagent answers, resume the cycle: read its output and continue from where you left off. If the user sends a NEW message without -saikit before you resume, the gate stands down by design — the promised cycle still applies: finish it yourself, or ask them to re-arm with -saikit.

Delegation rule (Claude):
- Delegate the implement, verify, and review gates to subagents via the Task tool, in this exact sequence:
  1) the implementer subagent, then 2) the verifier subagent, then 3) the reviewer subagent.
- If your host does not surface those project-level agents in the Task tool, delegate to its
  nearest equivalent instead — an engineer/coding agent to implement, a test/QA agent to verify,
  a code-review agent to review. The gate maps host agent names to these roles by function, so a
  correctly-delegated turn still satisfies it.
- You (the lead) handle the Understand step yourself and act as closer and retro: ask the user up front, then reconcile the subagents' evidence and write the final receipt in plain language.
- The turn cannot end until an implementer-, verifier-, and reviewer-role subagent have each run, in that order.
- Subagent crash fallback: if a role subagent dispatch fails on infrastructure (usage limit / 429 / tool error), retry it ONCE. If it fails again, perform that role YOURSELF following its role definition, and declare it in the receipt with a line reading exactly "ROLE FALLBACK: <ROLE> (reason)" — the gate accepts that declaration in place of the dispatch. Never silently skip a role. A dispatch stuck for many minutes with no output counts as failed — abandon it and apply this same fallback.

Fast lane (-saikit:fast):
- A turn armed with -saikit:fast is exempt from the three-subagent ceremony: you (the lead)
  implement directly. The receipt and real verification evidence (or a declared skip) are
  still required. A plain -saikit arm runs the full ceremony above.

Revision after findings (do this the CHEAP way):
- If the reviewer returns findings, do NOT restart the ceremony. Fix the exact
  findings, then have the verifier re-check ONLY those points (targeted
  commands, not the full battery), and the reviewer re-read ONLY the new diff.
- One full battery run per task, at the end, is enough evidence for the
  receipt. Re-running the entire suite after every fix wastes the turn.
- Batch your evidence: group verification commands into ONE shell invocation
  per checkpoint instead of dozens of single-command calls.

One ceremony per task, not per edit:
- Batch your edits: make all your changes first, then run the
  implement -> verify -> review sequence ONCE over the final stable diff.
- Trivial in-task edits (a rename, a move, a typo fix) do NOT re-trigger
  delegation: verify them yourself with a focused check and say so in the
  receipt.

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
- Resolve every technical choice yourself from the repo; never hand a user a technical decision to make.
- Never block on questions the repo already answers, and never silently guess on questions it cannot answer: if you must proceed without an answer, state the assumption in plain words to the user and record it in the diff.

User-facing surface baseline (language/framework/platform agnostic):
- For ANY user-facing surface you add or change, cover the full state matrix explicitly: loading, EMPTY (no data), error, and success — not only the happy path.
- Meet an accessibility baseline: semantic structure (a labelled region/heading, and a list or table for repeated/tabular data rather than nested generic containers), an accessible name for every control and icon-only action, visible keyboard focus, and a working keyboard path.
- Keep it responsive for long or overflowing content, and match the repo's existing component/section style instead of a generic template. Reuse the installed UI library's already-accessible primitives rather than re-implementing them.

Final receipt required before stopping (write every line in plain, clear language):
SUMMONAIKIT HARNESS RECEIPT
Understand: in one or two plain sentences, what the user asked for, plus any question you asked or assumption you made.
Implement: changed files and implementation summary; for any read/listing/reporting surface, state whether its data source already existed or is newly created and the assumption recorded in code; or why no code change was needed.
Verify: exact commands/checks run and results, or an explicit skip that uses one of these phrases — not run, not executed, skipped, no corri, no se corrio, sin tests — plus a concrete reason. "No corri los candados" counts; "PASS" or od/wc alone does not.
Review: findings, risks, or "no findings" with basis.
Close: evidence summary and remaining gaps; state explicitly whether code was touched after the reviewer subagent last ran (yes/no).
Retro: harness/codebase-memory improvement, or "none".
HARNESS_CONTEXT
}

# Task 10.1: los clasificadores del vendor (is_engineering_task,
# is_trivial_task, SUBSTANTIVE_RE, TRIVIAL_RE) se RETIRARON. Estuvieron muertos
# desde el parche sentinel (cero call sites, grep-verificado antes de borrar):
# el sentinel es la unica condicion de armado, y el carril fast NO se infiere de
# regex de trivialidad — se pide explicito (-saikit:fast).

# >>> SAIKIT-STANDING-RULES v1 >>>
# Task 10.6: reglas PERMANENTES, inyectadas una vez por sesion en la fase
# SessionStart. No gatean, no arman, no cuentan ciclos.
#
# Por que hace falta un canal aparte del contrato: la regla "una corrida de la
# bateria por tarea" YA vivia en harness_context() desde la 10.2 y se violo
# igual. harness_context() se llama dentro de start_harness, o sea SOLO en el
# camino armado; una sesion sin -saikit nunca lo ve. Medido en el transcript
# e86ddb2c (2026-08-14): 2.6 h bloqueado esperando, ~1.75 h de ellas evitables,
# con la regla presente en el kit y fuera del alcance del modelo.
#
# Cada linea lleva un numero medido atras. Sin numero no entra: este texto se
# paga en CADA sesion de CADA repo, con el mismo criterio que un CLAUDE.md.
standing_rules() {
  cat <<'STANDING_RULES'
SUMMONAIKIT STANDING RULES (session-wide — these apply whether or not the turn is armed with -saikit)
- Run the FULL test battery ONCE per task, at the end. Do red/green on the single test file you are changing, never on the whole suite.
- Do NOT sit blocked waiting on a background job. Start it, keep doing other work; you are notified when it finishes.
- Before waiting on an external reviewer or CI, check whether it ALREADY finished instead of re-polling in a loop.
STANDING_RULES
}

# Acotado a TARGET=claude a proposito: es el unico host donde se MIDIO que
# SessionStart acepta hookSpecificOutput.additionalContext y que el texto llega
# al modelo (repo descartable + claude -p headless; docs/task-10.6-plan.md).
# zcode, Codex y Grok quedan `unknown`, no "no lo tienen": registrarlos a ciegas
# es el error que la 6.2 evito por un pelo — ahi Codex resulto DESCARTAR el
# stdout cuando el exit no es 0, algo que ninguna otra fase sugeria.
#
# Emite JSON completo y sale por su cuenta: el emit_allow que sigue no imprime
# nada para claude, asi que esta funcion es la unica salida de este camino.
emit_standing_rules() {
  escaped="$(json_escape "$(standing_rules)")"
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$escaped"
  exit 0
}
# <<< SAIKIT-STANDING-RULES v1 <<<

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
  # Task 8.1 (C1+C2): el prompt se lee con el lector top-level DECODIFICADO —
  # el sed greedy cortaba en la primera \" (no armaba / desarmaba con el
  # sentinel presente) y los \n crudos rompian la frontera del sentinel.
  prompt_text="$(json_top_level_decoded prompt)"
  # Task 9.4 (C9): el fallback al payload CRUDO se acota a la fase `session`.
  # Sin acotar, un payload sin campo `prompt` hacia que el sentinel se buscara
  # en el PAYLOAD ENTERO: un `-saikit` en cualquier otro campo — la forma real
  # es un resume, donde el texto viejo viaja en un campo de resumen — armaba la
  # ceremonia entera sin que nadie la pidiera, y el gate quedaba exigiendo
  # recibo por un turno que no lo pidio. Medido en
  # caso_g1_prompt_sin_campo_no_arma (rojo antes del acotamiento).
  #
  # Se CONSERVA en `session` porque ahi cursor si arma con el sentinel en el
  # texto y no hay campo `prompt` que leer (medido, caso_g6_armado_por_target).
  if [ -z "$prompt_text" ] && [ "$PHASE" = "session" ]; then prompt_text="$INPUT"; fi
  # LIMITE que sobrevive, heredado de la Task 10.6 (hallazgo Major de CodeRabbit,
  # PR #19) y NO cerrado por este acotamiento: dentro de `session`, el `summary`
  # de una sesion reanudada suele CITAR el prompt anterior, que llevaba -saikit.
  # Ese texto viejo sigue matcheando y la sesion arma: sale el contrato en vez de
  # las reglas permanentes. Cerrarlo exigiria distinguir "peticion" de "resumen"
  # DENTRO de session, y ahi el unico host medido que arma asi es cursor.
  # Atado por caso_g1_session_con_sentinel_en_summary_arma_y_no_da_reglas.
  # >>> SAIKIT-SENTINEL-GATE v1 >>>
  # El sentinel es la unica condicion de armado (REEMPLAZO a los clasificadores
  # is_engineering_task / is_trivial_task del vendor, retirados en la Task 10.1
  # tras estar muertos desde este parche, cero call sites). Si lo escribiste,
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
    # >>> SAIKIT-STANDING-RULES v1 >>>
    # Task 10.6: la fase session sin sentinel salia en silencio; ahora deja las
    # reglas permanentes. Va DESPUES del desarme y ANTES del emit_allow, y esta
    # acotado a session: si corriera en prompt, un turno sin sentinel dejaria de
    # ser mudo y se rompe caso_g1_no_arma_sin_sentinel (esa es la regresion que
    # atrapa una rama mal acotada, por eso 10.6 no agrega un caso propio).
    # No arma, no escribe estado y no toca el gate del sentinel.
    if [ "$PHASE" = "session" ] && [ "$TARGET" = "claude" ]; then
      emit_standing_rules
    fi
    # <<< SAIKIT-STANDING-RULES v1 <<<
    emit_allow
  fi
  # <<< SAIKIT-SENTINEL-GATE v1 <<<

  # Task 10.1: carril fast. r1 hallazgo 4 (verificado con grep): -saikit:fast YA
  # ARMA con el sentinel de siempre (el `:` pasa la frontera derecha), asi que el
  # RE del sentinel NO cambia — lo nuevo es solo la DETECCION del carril. El
  # match del sufijo es EXACTO (:fast con frontera derecha propia); cualquier
  # otro sufijo (-saikit:fasst, -saikit:rapido) arma FULL — limite declarado: un
  # typo del carril cae al lado seguro (ceremonia completa), nunca a un fast
  # silencioso. Atado por caso_g1_sufijo_desconocido_arma_full.
  lane="full"
  if printf '%s' "$prompt_text" | grep -Eq '(^|[^A-Za-z0-9_/-])-saikit:fast([^A-Za-z0-9_-]|$)'; then lane="fast"; fi

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
  write_state "$task_hash" "0" "0" "0" "" "$lane"
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
  lane="$(read_state_value lane)"
  if [ -z "$task_hash" ]; then task_hash="unknown"; fi
  if [ -z "$cycle" ]; then cycle="0"; fi
  if [ -z "$implemented" ]; then implemented="0"; fi
  if [ -z "$verified" ]; then verified="0"; fi

  if [ "$kind" = "implemented" ]; then implemented="1"; fi
  if [ "$kind" = "verified" ]; then verified="1"; fi
  write_state "$task_hash" "$cycle" "$implemented" "$verified" "$agents_seen" "$lane"
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
  lane="$(read_state_value lane)"
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
  write_state "$task_hash" "$cycle" "$implemented" "$verified" "$agents_seen" "$lane"
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
  # Task 8.1 (C3, clase A1): tool_name/command/file_path se leian con el sed
  # greedy, que devuelve la ULTIMA ocurrencia del payload — una clave "command"
  # DENTRO de tool_response (texto que el turno no escribio) acreditaba
  # verified=1 por un comando que nunca corrio, falsificando el comentario de
  # :972 ("never in the raw payload"). Mismo cierre que la 3.1 hizo para
  # subagent_type: command/file_path acotados a tool_input, tool_name al primer
  # nivel. event_name queda con el lector viejo: solo alimenta $combined, que
  # ya incluye $INPUT entero para el grep laxo de "implemented".
  tool_name="$(json_top_level_string tool_name)"
  command_text="$(json_tool_input_string command)"
  file_path="$(json_tool_input_string file_path)"
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
  # falsely mark the work verified. The failure-signal guard consults the full
  # payload (command + file_path + tool_response) porque A11 (medido 59/59,
  # Task 1.4) demostro que el host NO entrega exitCode en el tool_response de
  # Bash: la unica senal de fracaso disponible es el TEXTO de stdout/stderr del
  # runner. Dos regex: CI para patrones con digito no-cero y crashes; CS para
  # frases literales donde -i daria falso positivo en prosa (`0 failures!`).
  # Task 9.10 r2: el runner bash propio (tests/run.sh) se acredita por
  # TEST_RUNNER_CMD_RE sobre $command_text SOLO — posicion de comando estricta,
  # sin wrapper (ver el comentario de la constante). No se concatena
  # tool_name: el ancla ^ y el separador son del COMANDO, y un tool_name
  # delante moveria el inicio de linea.
  if printf '%s' "$tool_name $command_text" | grep -Eiq "$TEST_RUNNER_WORD_RE" \
     || printf '%s' "$command_text" | grep -Eiq "$TEST_RUNNER_CMD_RE"; then
    if ! { printf '%s' "$combined" | grep -Eiq "$FAILURE_SIGNAL_RE_CI" \
           || printf '%s' "$combined" | grep -Eq  "$FAILURE_SIGNAL_RE_CS"; }; then
      mark_evidence "verified" "${command_text:-verification command}"
    fi
  fi

  emit_allow
}

has_receipt_label() {
  label="$1"
  alt="$2"
  text="$3"
  # Task 8.3 (C7): la alternativa (\*\*|__)? acepta el cierre de markdown bold
  # entre la etiqueta y el `:` — `- **Understand**: ...` es la forma MAS
  # natural en que el modelo escribe el recibo, y sin esto las SEIS etiquetas
  # fallaban a la vez y un recibo honesto se bloqueaba (falso rojo => ciclos de
  # revision de mas). El `**`/`__` de apertura ya pasaba por la frontera
  # izquierda [^[:alpha:]]. El recibo plano sigue contando igual (A8 intacto).
  printf '%s' "$text" | grep -Eiq "(^|[^[:alpha:]])($label|$alt)(\*\*|__)?[[:space:]]*:"
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
  # 5.4: en zcode, continue:false+exit 0 es IGNORADO (medido 5.2). El corte por
  # presupuesto depende de exit 2, que en Stop SI bloquea en zcode (5.2). Solo se
  # invierte el exit del budget para el segundo host; Claude sigue intacto. El
  # JSON de continue:false sobra en zcode (con exit 2 no se parsea): no se emite.
  if [ -n "${ZCODE_SESSION_ID:-}${ZCODE_PROJECT_DIR:-}" ]; then
    printf '%s\n' "$message" >&2
    exit 2    # saikit-5.4-zcode-budget (mutacion: exit 2 -> exit 0)
  fi
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

# Marcador de "el texto del asistente ya trae un bloque de recibo" (completo o
# roto). Usado SOLO por la escotilla DELEGATED de mas abajo (fix de la
# cross-review, ciclo 1): la escotilla no debe disparar una vez que hay
# recibo, o sustituye en silencio al gate de verdad. Se declara como
# constante propia (no inline) para que una mutacion pueda apuntar SOLO a
# esta definicion, sin tocar de paso el chequeo separado y no relacionado de
# "Missing SUMMONAIKIT HARNESS RECEIPT" mas abajo en stop_gate.
RECEIPT_MARKER_RE='SUMMONAIKIT HARNESS RECEIPT'

stop_gate() {
  if [ ! -f "$STATE_PATH" ]; then
    emit_allow
  fi

  # Task 8.1 (C3, misma clase): transcript_path con el lector top-level — el
  # greedy podia tomar una ruta de otra parte del payload. La contencion de A6
  # (transcript_en_perfil) sigue intacta detras; los escapes quedan crudos como
  # siempre (cd+pwd los normaliza, ver :1084).
  transcript_path="$(json_top_level_string transcript_path)"
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

  # Task 8.2 (C4): las escotillas PAUSED/DELEGATED se evaluan sobre el texto
  # del turno ACTUAL, no sobre $text entero — el tail de 160 lineas conserva
  # turnos anteriores, y con eso un PAUSED viejo dejaba pasar el gate entero de
  # un turno que no pauso, y un recibo viejo hacia fallar la clausula
  # "recibo ausente" de DELEGATED (bloqueaba una delegacion legitima: falso
  # rojo => ciclos de revision de mas). last_assistant_message ES el mensaje
  # final del turno (medido Task 1.4); si el host no lo manda, fallback al
  # texto completo — mismo fail-open de siempre, no se apaga ningun canal.
  # Las ETIQUETAS del recibo siguen mirando $text entero (los dos canales):
  # acotarlas repetiria A2/A8 y rompe caso_g4_recibo_solo_en_transcript_pasa.
  text_hatch="$(assistant_text_payload)"
  if [ -z "$text_hatch" ]; then text_hatch="$text"; fi

  # A clarifying pause is a valid way to end the turn: the agent asked the
  # user a question and is waiting for the answer. Do not demand a receipt or
  # the implement -> verify -> review sequence in that case.
  if printf '%s' "$text_hatch" | grep -Eiq 'SUMMONAIKIT HARNESS PAUSED'; then
    emit_allow
  fi

  # Sibling escape hatch (arreglo 1): the agent delegated to a subagent that is
  # still running (implementer/verifier/reviewer subagents measured at 30-100
  # min) and is correctly waiting on it, not failing. Unlike PAUSED above, this
  # one REQUIRES the role to be named -- one of the three canonical roles --
  # so it stays auditable instead of a blanket skip-the-gate (same discipline
  # ROLE FALLBACK already uses, see D4/Task 6.3 below). A DELEGATED line that
  # names no role does not match and falls through to the normal receipt gate.
  #
  # Bug found by cross-review (cycle 1), reproduced with execution, fixed
  # here: the hatch must ALSO require that no receipt is present yet. Without
  # this second clause, a BROKEN receipt (missing labels, zero subagents
  # dispatched, no ROLE FALLBACK declared) that merely mentioned "DELEGATED"
  # in passing (e.g. inside the Close bullet) closed the turn silently with
  # exit 0 and no feedback -- exactly the skip-the-gate this hatch exists to
  # avoid. It also let a COMPLETE, valid receipt that happens to mention
  # "DELEGATED" in Retro (plausible: the receipt shape invites harness-
  # improvement notes there) exit 0 WITHOUT clearing state, so a clean close
  # stopped being clean. Requiring the receipt to be absent fixes both: a
  # broken receipt now falls through to the normal missing-label feedback
  # below, and a complete receipt closes clean through the regular path
  # (state cleared), never through this hatch.
  #
  # Declared limit (same trade-off as ROLE FALLBACK above): the match is
  # still an unanchored substring over assistant text that has NO receipt at
  # all -- a message that happens to cite the exact phrase "SUMMONAIKIT
  # HARNESS DELEGATED - awaiting <role>" without having genuinely delegated
  # would still close the turn. Accepted on purpose, same reason the gate as
  # a whole is advisory/fail-open by design.
  if printf '%s' "$text_hatch" | grep -Eiq 'SUMMONAIKIT HARNESS DELEGATED.*awaiting[[:space:]]+(implementer|verifier|reviewer)' \
     && ! printf '%s' "$text_hatch" | grep -Eiq "$RECEIPT_MARKER_RE"; then
    emit_allow
  fi

  implemented="$(read_state_value implemented)"
  verified="$(read_state_value verified)"
  cycle="$(read_state_value cycle)"
  task_hash="$(read_state_value task_hash)"
  agents_seen="$(read_state_value agents_seen)"
  lane="$(read_state_value lane)"
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
  # VERIFY_SKIP_RE: EN+IT historicos + ES natural. Vivo 2026-08-13: zcode
  # escribio "No corri los candados" y el gate lo rechazo porque solo
  # aceptaba skipped/not run. "se corrio la bateria" NO matchea (falta "no ").
  # Task 9.10 r2: el runner bash propio tambien se acepta aqui via
  # TEST_RUNNER_CMD_RE — grep ancla ^ por LINEA, asi que en prosa solo cuenta
  # una linea que ESTEME en posicion de comando; el credito real del carril
  # run.sh vive en el evento (arriba), este es el fallback de prosa.
  if [ "$verified" != "1" ] && ! { printf '%s' "$text" | grep -Eiq "$TEST_RUNNER_WORD_RE|$VERIFY_SKIP_RE" \
                                      || printf '%s' "$text" | grep -Eiq "$TEST_RUNNER_CMD_RE"; }; then
    missing="$missing- Missing verification evidence or explicit skipped-check reason.\n"
  fi

  # Sequential subagent enforcement (Claude only — Task/subagent_type is a Claude
  # Code primitive). The first three gates must each run as their own subagent,
  # in order. closer/retro stay receipt sections the lead writes.
  # Task 10.1: con lane=fast (armado con -saikit:fast) la ceremonia de
  # subagentes NO se exige — el recibo y la evidencia de verificacion siguen
  # exigidos arriba, ahi no cambia nada. Un lane ausente/vacio (estado sembrado
  # por el banco o escrito por un hook pre-10.1) != "fast" => ceremonia
  # completa: el default ausente es el lado seguro.
  if [ "$(read_state_value lane)" != "fast" ]; then
  if [ "$TARGET" = "claude" ]; then
    # D4 (Task 6.3): absorbe la escotilla "ROLE FALLBACK" del sabor Codex del
    # kit -- un subagente caido por infraestructura (429, limite de uso, error
    # de herramienta) trababa el turno sin salida. La declaracion en el recibo
    # sustituye al despacho; sin ella, el motivo de siempre sigue exigiendo.
    #
    # Limite declarado (revision cruzada, ciclo 1): el match es SUBCADENA SIN
    # ANCLAR sobre el texto del asistente -- si el propio agente cita "ROLE
    # FALLBACK: <ROL>" mientras ese rol falta de verdad, lo perdona. Aceptado a
    # proposito: anclar mas estricto repite A8 (un recibo legitimo en texto
    # corrido dejaba de contar), y el gate es advisory/fail-open por diseno --
    # mismo trade-off que el README ya declara para el gate entero.
    case ",$agents_seen," in
      *",implementer,"*) ;;
      *) if ! printf '%s' "$text" | grep -Eiq 'ROLE FALLBACK: *IMPLEMENTER'; then missing="$missing- Missing implementer subagent run (delegate the change via the Task tool, or declare ROLE FALLBACK: IMPLEMENTER (reason) in the receipt if that subagent is down after one retry).\n"; fi ;;
    esac
    case ",$agents_seen," in
      *",verifier,"*) ;;
      *) if ! printf '%s' "$text" | grep -Eiq 'ROLE FALLBACK: *VERIFIER'; then missing="$missing- Missing verifier subagent run (delegate verification via the Task tool, or declare ROLE FALLBACK: VERIFIER (reason) in the receipt if that subagent is down after one retry).\n"; fi ;;
    esac
    case ",$agents_seen," in
      *",reviewer,"*) ;;
      *) if ! printf '%s' "$text" | grep -Eiq 'ROLE FALLBACK: *REVIEWER'; then missing="$missing- Missing reviewer subagent run (delegate review via the Task tool, or declare ROLE FALLBACK: REVIEWER (reason) in the receipt if that subagent is down after one retry).\n"; fi ;;
    esac
    if printf '%s' "$agents_seen" | grep -q implementer && printf '%s' "$agents_seen" | grep -q verifier && printf '%s' "$agents_seen" | grep -q reviewer; then
      if ! printf '%s' "$agents_seen" | grep -Eq 'implementer.*verifier.*reviewer'; then
        missing="$missing- Subagents ran out of order; required sequence is implementer -> verifier -> reviewer.\n"
      fi
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
    # Task 10.2: la coletilla ata el aviso a la disciplina de re-review dirigido
    # (el contrato de arriba ya la pide): re-review del delta, no ceremonia nueva.
    printf 'SAIKIT REVIEW NOTICE: in your previous turn, code was edited after the reviewer subagent last ran, and those edits were not reviewed. Re-review the new diff only; do not restart the ceremony.\n' > "$RN_PENDING_PATH" 2>/dev/null || true
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
  write_state "$task_hash" "$next_cycle" "$implemented" "$verified" "$agents_seen" "$lane"
  feedback="$(build_gate_feedback "$missing" "$next_cycle")"
  emit_gate_failure "$feedback"
}

if [ -z "$PHASE" ]; then
  # 5.4: un Stop realista de zcode trae SOLO hookEventName (camel), no
  # hook_event_name (5.1 midio ambos; 5.2 midio camel-only). Sin leer camel,
  # PHASE cae a "tool" y stop_gate no corre. json_top_level_string (no el sed
  # greedy de json_string_field) por el mismo motivo que session_id (3.4).
  event="$(json_top_level_string hook_event_name)"
  [ -n "$event" ] || event="$(json_top_level_string hookEventName)"
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
