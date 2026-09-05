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
# Task 7.4 r1 (hallazgo CR PR #28): la herramienta de subagentes que el gate
# NOMBRA en sus mensajes tiene que existir en el host que los lee. En Grok se
# llama spawn_subagent (medido 7.1); "Task tool" ahi es una instruccion sin
# objeto y lleva a bloqueos en bucle. El contrato ya declara el "equivalente
# mas cercano" (linea Delegation rule), pero los mensajes de bloqueo no —
# unifico por TOOL_HINT.
TOOL_HINT="the Task tool"
if [ "$TARGET" = "grok" ]; then TOOL_HINT="the spawn_subagent tool"; fi
# Phase 15: en dsh la tool model-facing de delegacion es `subagent` (no Task).
if [ "$TARGET" = "dsh" ]; then TOOL_HINT="the subagent tool"; fi
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
# Task 16.4 (D1): recetario. El manifiesto se lee en runtime (un cat +
# sha256sum por receta) como indice de "que recetas hay y cual es su sha
# esperado". Desde el fix 1 de la revision del lead (16.4/16.6) ADEMAS se lee
# el titulo/carril del ARCHIVO autenticado (un awk por receta valida); el
# frontmatter se parsea solo para esas dos claves, nunca como fuente de datos
# no confiable. Override de entorno para el lab/golden (la ruta real cambia por
# corrida y NO se imprime).
RECETAS_DIR="${SAIKIT_RECETAS_DIR:-$HOOK_DIR/recetas}"
# recetas_menu(): stdout = bloque del contrato (menu o linea fija). Fail-open.
# D1/D4/D7/D8. De la revision del lead (16.4/16.6, fix 1): el sha256 del
# manifiesto autentica el ARCHIVO de la receta, no la linea del manifiesto.
# Quien pueda editar el manifiesto (o inyectar SAIKIT_RECETAS_DIR) escribiria el
# contrato de cada turno armado si el runtime confiara en sus columnas
# titulo/carril. Por eso el manifiesto es SOLO el indice de "que recetas hay y
# cual es su sha esperado"; el titulo y el carril que se muestran se leen del
# archivo cuya hash se acaba de verificar.
# Costo medido (MSYS2/Git Bash, esta maquina): el awk de abajo agrega UN fork
# por receta valida, ~25 ms (referencia: el sha256sum+cut que ya existia ~44 ms),
# una vez por turno armado — el contrato se arma en start_harness, no por evento,
# asi que es aceptable frente a arriesgar el contrato.
recetas_menu() {
  local m="$RECETAS_DIR/MANIFEST.sha256" sha tipo nombre carril titulo real n=0 omit=""
  local f_meta f_titulo f_carril
  if [ ! -r "$m" ]; then printf '%s\n' 'No recipe book on this host: follow this contract as usual.'; return 0; fi
  while IFS="$(printf '\t')" read -r sha tipo nombre carril titulo; do
    [ "$tipo" = "receta" ] || continue
    # D1 (adversary #1/#2): el manifiesto se lee en runtime y no es de confianza
    # ciega. Un nombre fuera de ^[a-z][a-z0-9-]*$ (traversal ../, glob *) no debe
    # usarse como ruta ni volcarse al contrato: se omite en silencio (el linter
    # del generador ya lo impide en un manifiesto propio; esto cubre el override
    # SAIKIT_RECETAS_DIR o un manifiesto editado a mano).
    printf '%s' "$nombre" | grep -Eq '^[a-z][a-z0-9-]*$' || continue
    real="$(sha256sum "$RECETAS_DIR/$nombre.md" 2>/dev/null | cut -c1-64)"
    if [ -n "$real" ] && [ "$real" = "$sha" ]; then
      # fix 1: titulo/carril del ARCHIVO autenticado, nunca del manifiesto (que
      # es el indice). El awk es un solo fork; ver nota de costo arriba. Ademas
      # (fix 1b) se lee SOLO el bloque de frontmatter: para en el segundo '---' y
      # toma la primera coincidencia de cada campo (misma tecnica que
      # _rl_frontmatter/_rl_campo del lint). Sin el corte, una receta cuyo cuerpo
      # documenta el formato con `titulo:`/`carril:` filtraria ese texto del
      # cuerpo, porque la ultima coincidencia pisa a la del frontmatter.
      f_meta="$(awk 'NR>1 && $0=="---"{exit} /^titulo:/&&!t{sub(/^titulo:[[:space:]]*/,"",$0);t=$0} /^carril:/&&!c{sub(/^carril:[[:space:]]*/,"",$0);c=$0} END{printf "%s\t%s",t,c}' "$RECETAS_DIR/$nombre.md")"
      f_titulo="${f_meta%%$'\t'*}"; f_carril="${f_meta#*$'\t'}"
      # 16.10: la instruccion pide lo que el gate PUEDE ver, y solo eso.
      #
      # La 16.8 midio seis turnos vivos y encontro que el contrato se obedece
      # exactamente donde el gate mira. El menu pedia tres cosas: elegir la
      # receta y declararla en el recibo, copiar los pasos a un todolist, y
      # anotar los saltos como "skip: <razon>". La declaracion aparecio 11 y 12
      # veces sobre 2 inyecciones por sesion — se cumplio de sobra. El todolist:
      # CERO en 6 de 6 (`TodoWrite` no se invoco ni una vez), y los saltos
      # tampoco (los 2 "skip:" por sesion son el texto de este mismo contrato,
      # no uso). La diferencia entre lo que se cumplio y lo que no es que el
      # recibo se revisa y el todolist no.
      #
      # Ademas el todolist es una herramienta de UN host: este contrato tambien
      # se inyecta en codex, grok y dsh. Pedir ahi una herramienta que puede no
      # existir es pedir lo imposible; y donde SI existe tampoco se uso — se
      # verifico que no hay ninguna restriccion de herramientas que lo explique.
      #
      # Asi que la instruccion deja de nombrar una herramienta y pide la
      # conducta, con su rastro en el recibo, que es la superficie que ya
      # demostro funcionar. Una instruccion que nadie obedece no es inocua:
      # entrena a leer el resto del contrato como decorativo.
      [ "$n" -eq 0 ] && printf '%s\n' 'Recipes (recetario): pick ONE that matches the task, read it in full, and follow its steps IN ORDER — do not improvise your own sequence. Declare it in the receipt as "Understand: ... Receta: <nombre>", and name there any step you did not do, as "skip: <razón>". If none matches, follow this contract as usual.'
      printf -- '- %s — %s — %s\n' "$nombre" "$f_titulo" "$f_carril"; n=$((n+1))
    else
      omit="$omit $nombre"
    fi
  done < "$m"
  [ "$n" -eq 0 ] && printf '%s\n' 'No recipe book on this host: follow this contract as usual.'
  [ -n "$omit" ] && for x in $omit; do printf '%s\n' "(recipe omitted: hash mismatch ($x) — reinstall with tools/install-hook.sh)"; done
  return 0
}
# receta_valida <nombre>: exit 0 si el recetario lista una receta <nombre> cuyo
# archivo instalado coincide con el sha del manifiesto; exit distinto en caso
# contrario (sin manifiesto, nombre inseguro, hash distinto). Es la misma
# comprobacion serie manifiesto+hash que hace recetas_menu, pero para UN nombre
# con fallo ESTRICTO (no fail-open): es el guard del alias (16.6), que no debe
# bajar el carril si la receta que nombra no existe — cae al lado seguro (full).
receta_valida() {  # $1 = nombre
  local nombre="$1" m="$RECETAS_DIR/MANIFEST.sha256" sha tipo nombre_m carril titulo real
  printf '%s' "$nombre" | grep -Eq '^[a-z][a-z0-9-]*$' || return 1
  [ -r "$m" ] || return 1
  while IFS="$(printf '\t')" read -r sha tipo nombre_m carril titulo; do
    [ "$tipo" = "receta" ] || continue
    [ "$nombre_m" = "$nombre" ] || continue
    real="$(sha256sum "$RECETAS_DIR/$nombre.md" 2>/dev/null | cut -c1-64)"
    [ -n "$real" ] && [ "$real" = "$sha" ] && return 0
    return 1
  done < "$m"
  return 1
}
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
# Task 6.4 (D2): la senal EXPLICITA de Codex va PRIMERO. El operador corre
# Codex desde adentro de Claude (codex-rescue, cross-review.ps1) y ahi el hook
# de Codex hereda CLAUDECODE=1 del proceso padre (medido 6.1: reproducido
# lanzando desde Claude); sin esta rama primero, ese turno se creeria claude y
# los dos hosts compartirian estado. Allowlist, no passthrough: SOLO el
# literal `codex` mapea (Core Rule 2 — un valor no reconocido no es evidencia
# de nada) y cualquier otro valor cae por las senales de abajo. Es la primera
# vez que HOST sale de una variable NUESTRA (la inyecta el .ps1 vecino como
# env real del proceso, el unico host donde llega — A10/6.1); si algun dia
# Codex inyecta una senal propia, esa es mejor evidencia y esta rama se
# reescribe. 7.3 insertara grok ENCIMA (orden final: grok > codex > zcode >
# claude > other).
if [ "${GROK_HOOK_EVENT+x}" = "x" ]; then
  # Task 7.3 (D2): GROK_HOOK_EVENT la inyecta el runner de hooks de Grok en
  # cada proceso que el spawnea (presente en los 12 dumps de env de 7.1). Va
  # por SETNESS, no valor: cuenta incluso EXPORTADA VACIA (hallazgo Greptile
  # P2 / CR r1 del PR #27 — `-n` la ignoraria y el proceso clasificaria por
  # las senales heredadas, p.ej. un CLAUDECODE=1 del padre), porque si el
  # runner la exporto, el proceso es de Grok — un evento que no reconozcamos
  # no cambia la identidad. NO se usa GROK_SESSION_ID a proposito: el operador
  # lanza Claude DESDE Grok y el hijo heredaria esa var y se creeria Grok —
  # el mismo error de identidad que la rama codex de abajo cierra en
  # direccion inversa. CLAUDECODE ausente en Grok (medido 7.1), y
  # Claude/zcode/Codex no setean GROK_HOOK_EVENT: sin colision medida.
  HOST=grok
elif [ "${SUMMONAIKIT_HOOK_TARGET:-}" = "codex" ]; then
  HOST=codex
# Phase 15 (D2): dsh no exporta senal propia medible desde el hook (el plugin
# corre en el proceso de dsh y lanza bash); el adaptador declara el target,
# igual que el wrapper de codex. Setness+valor exacto: un hijo lanzado DESDE
# dsh sin el adaptador no se cree dsh.
elif [ "${SUMMONAIKIT_HOOK_TARGET:-}" = "dsh" ]; then
  HOST=dsh
elif [ -n "${ZCODE_SESSION_ID:-}${ZCODE_PROJECT_DIR:-}" ]; then
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

# Task 14.2 — label VERIFIED BY SUBAGENT (host con canal interno ciego). Via
# ADICIONAL de credito de verificacion, SOLO en hosts donde el hook NO ve el
# canal interno ($HOST=zcode, medido en el turno vivo 2026-08-25). Ver
# docs/phase-14.1-atestacion-verificacion-delegada.md (§3.3 y §4.3); el label se
# matchea como SUBCADENA libre sobre $text (igual que ROLE FALLBACK, NO
# has_receipt_label): una frase que vive en cualquier parte del recibo.
SAIKIT_VERIFIED_SUBAGENT_RE='VERIFIED[[:space:]]+BY[[:space:]]+SUBAGENT:'
# Comando que el label DEBE nombrar (un comando re-corrible). UNION del
# vocabulario de runners (TEST_RUNNER_RE) + comandos de compilacion/type-check/
# sintaxis que hoy NO estan en la lista de runners pero son verificaciones
# legitimas. Con fronteras de palabra: "bateria"/"checks" NO cuentan.
#
# 18.18 — DOS ramas nuevas para el runner PROPIO del repo (tests/run.sh): en
# host ciego el label es el UNICO juez de la evidencia (saikit_verif_evidence_ok)
# y ninguna forma del runner del repo estaba en ESTE vocabulario, mientras que el
# carril de evento (TEST_RUNNER_CMD_RE) si la acepta — el verifier corria la
# bateria del repo y el gate la rechazaba igual. Decision de diseño (DECLARADA):
# NO se embebe TEST_RUNNER_CMD_RE literal porque sus anclas de POSICION
# `(^|[;&|]...)` no aplican a un span donde el comando viene tras el `: ` del
# label; se agregan las DOS formas internas de ese carril (verbo shell opcional +
# invocacion directa, segmentos de path estrictos `([^/[:space:]]*/)*` para que
# "contest/run.sh" no matchee) SIN exigir posicion, y la frontera derecha la
# sigue poniendo el cierre del wrapper de abajo. Viven en constante PROPIA (como
# TEST_RUNNER_RE dentro del mismo grupo central) para que la bateria de
# mutaciones pueda quitarlas SIN tocar al resto del vocabulario.
#
# Justificacion vs D13 (vocabulario cerrado): el vocabulario SIGUE cerrado — son
# las mismas formas que el carril de evento ya acepta, no "cualquier .sh" — y el
# credito sigue exigiendo resultado de EXITO en el MISMO span + veto global de
# fallos sobre TODOS los spans. La palabra en prosa `tests/run.sh` sin resultado
# en la misma linea no acredita, igual que `pytest` en prosa no acredita sin
# resultado. Limites declarados del lado del wrapper (heredados de su frontera,
# mas laxa que el terminador `([[:space:]]|$)` del carril de evento): un sufijo
# con `/` o un verbo delante del runner dentro del span ("echo bash
# tests/run.sh") pasan la frontera — aceptados a proposito: el span ES la
# declaracion del lead, no un comando que el hook ejecuta.
SAIKIT_VERIFIED_RUNNER_PROPIO_RE='(ba|z|da|k)?sh[[:space:]]+([^/[:space:]]*/)*tests?/run\.sh|(\./)?([^/[:space:]]*/)*tests?/run\.sh'
SAIKIT_VERIFIED_CMD_RE="(^|[^A-Za-z0-9_.-])($TEST_RUNNER_RE|py_compile|compileall|python[0-9]?[[:space:]]+-m[[:space:]]+py_compile|dotnet[[:space:]]+build|bash[[:space:]]+-n|sh[[:space:]]+-n|node[[:space:]]+--check|git[[:space:]]+diff[[:space:]]+--check|$SAIKIT_VERIFIED_RUNNER_PROPIO_RE)([^A-Za-z0-9_.-]|\.([^A-Za-z0-9_.-]|$)|$)"
# Resultado de EXITO que el label DEBE declarar (el veto de fallo aparte, abajo).
# OJO a dos aristas (grok r1 #3): el conteo de "passed" es [1-9][0-9]*, y NO se
# acepta "en verde" suelto (negable: "no en verde" lo matchearia) — queda "todo
# verde" y "sin errores", que no se niegan. La frontera del grupo sigue
# excluyendo "10 failed". PERO el conteo [1-9] NO alcanza para excluir
# "0 passed": la rama `pass(ed|ing)` pelada lo rematchea (CodeRabbit, PR #72) —
# ERE no tiene lookbehind, asi que "0 passed"/"0 passing"/"0 tests passed" se
# descalifican con el VETO propio del label (SAIKIT_VERIFIED_CERO_RE, abajo),
# no aca: cero pruebas corridas no es una verificacion.
SAIKIT_VERIFIED_RESULT_RE='(^|[^A-Za-z0-9_.-])(exit[[:space:]]+0|[1-9][0-9]*[[:space:]]+(pass(ed|ing)|ok|okay)|0[[:space:]]+(failed|failing|failures?|errors?)|pass(ed|ing)|ok|okay)([^A-Za-z0-9_.-]|\.([^A-Za-z0-9_.-]|$)|$)|todo[[:space:]]+verde|sin[[:space:]]+errores'
# Veto propio del label: un conteo CERO de exito ("0 passed", "0 passing",
# "0 tests passed", "0 ok") no acredita — "10 passed" no cae (el 0 va precedido
# de un digito). La frontera final ADMITE el punto: la linea del recibo suele
# terminar en "0 passed." (rojo medido: sin eso el veto no disparaba).
SAIKIT_VERIFIED_CERO_RE='(^|[^0-9.])0[[:space:]]+(tests?[[:space:]]+)?(pass(ed|ing)|ok|okay)([^A-Za-z0-9_-]|$)'
# Veto propio del label: FALLO PELADO sin conteo ("ok, failed.", "1 failure",
# "errors") — residual del PR #72 (Greptile r3). FAILURE_SIGNAL_RE_CI solo cubre
# `N failed` y `failed: N`; un `failed` a secas escrito por el lead es una
# declaracion de fallo explicita y acreditaba. Sin lookbehind en ERE, se hace en
# dos pasos: (1) extraer cada ocurrencia CON su palabra previa y su sufijo
# `[=:] N`; (2) descartar las NEGADAS — "0 failed", "no failures", "sin errores",
# "failures: 0" son formas de EXITO — y si queda alguna, veta. Fronteras de
# palabra a ambos lados: "unfailed"/"errorless" no cuentan.
# El span incluye el COMANDO (bots del PR #81): un `error`/`fail` que es parte
# de una ruta o un archivo (`tests/errors.py`, `error.py`, `errors/`) no es una
# declaracion de fallo — se descuenta por forma: `/` o `.` pegados antes no
# abren match (leading), y el sufijo `.ext` o `/` se captura y se descuenta
# (SAIKIT_VERIFIED_FALLO_RUTA_RE). El punto de FIN DE FRASE ("failed.") sigue
# vetando: solo se descuenta `.` seguido de alfanumerico. Limite declarado: un
# argumento suelto (`pytest -k error, 2 passed`) veta de mas.
# Puntuacion PEGADA (`0 failed,error`): grep -o consume la coma como sufijo del
# primer match y el segundo se queda sin frontera — se normaliza antes
# (saikit_verif_fallo_norm separa , ; ( ) con espacios).
SAIKIT_VERIFIED_FALLO_PELADO_RE='(^|[^A-Za-z0-9_/.-])([A-Za-z0-9]+[[:space:]]+)?(fail(ed|ing|ure|ures|s)?|error(s|es)?)([=:][[:space:]]*[0-9]+|\.[A-Za-z0-9]+|/|\.([^A-Za-z0-9]|$)|[^A-Za-z0-9_./-]|$)'
SAIKIT_VERIFIED_FALLO_NEGADO_RE='^[^A-Za-z0-9_-]?(0|no|sin|without|zero|cero|none|ningun|ningún)[[:space:]]|[=:][[:space:]]*0$'
SAIKIT_VERIFIED_FALLO_RUTA_RE='\.[A-Za-z0-9]+$|/$'
saikit_verif_fallo_norm() { sed 's/[,;()]/ & /g'; }
# Devuelve 0 (veta) si algun span trae un fallo pelado NO negado y NO ruta.
saikit_verif_fallo_pelado() {
  printf '%s\n' "$1" | saikit_verif_fallo_norm | grep -Eio "$SAIKIT_VERIFIED_FALLO_PELADO_RE" \
    | grep -Eiv "$SAIKIT_VERIFIED_FALLO_NEGADO_RE" | grep -Eivq "$SAIKIT_VERIFIED_FALLO_RUTA_RE"
}

# Task 14.2 — UN SOLO lugar define que host tiene el canal interno ciego. Hoy
# solo zcode lo tiene MEDIDO (turno vivo 2026-08-25). kimi es candidato con el
# canal `not_observed` — se agrega aca, y en ningun otro lado, cuando alguien lo
# mida. La condicion estaba escrita DOS veces (predicado + ruteo de la
# evidencia): con dos copias, el dia que se mida otro host una se actualiza y la
# otra no, y el sintoma seria un host medio-ciego imposible de razonar.
saikit_host_ciego() { [ "$HOST" = "zcode" ]; }

# Task 14.2 — extrae el SPAN del label: desde 'VERIFIED BY SUBAGENT:' hasta el
# fin de ESA linea. El predicado (§4.3) evalua comando/resultado/veto SOLO sobre
# este fragmento, NO sobre el recibo entero — asi un 'pytest' mencionado en otra
# linea, un 'ok' suelto en otra, o un 'TypeError:'/fallo de otra linea NO cuentan
# (fix codex #2 credito por piezas dispersas / #3 falso positivo del veto).
# (grok r1 #2) se extrae con grep -Eio (case-INSENSITIVE) y con la CONSTANTE
# SAKIT_VERIFIED_SUBAGENT_RE, no con awk case-sensitive hardcodeado: el detector
# del label es -Eiq, asi que una forma 'Verified by subagent:' o en minusculas
# debe producir un span igual — si no, entra al camino exclusivo pero sale span
# vacio (no acredita), que es un falso negativo.
# (Greptile P1, PR #72) devuelve TODOS los spans, uno por linea — NO solo el
# primero: con `| head -n1` un recibo con un label de EXITO seguido de otro con
# `failed: 1` / `exit 1` acreditaba, porque el veto jamas veia el segundo. El
# predicado juzga cada span (abajo); el veto corre sobre todos.
saikit_verif_spans() {
  local saikit_span_text="$1"
  printf '%s' "$saikit_span_text" | grep -Eio "$SAIKIT_VERIFIED_SUBAGENT_RE[^[:cntrl:]]*"
}

# Task 14.2 — devuelve 0 si el label VERIFIED BY SUBAGENT acredita la
# verificacion en este turno (host con canal interno ciego + verifier
# despachado + predicado §4.3 sobre el SPAN del label: comando + resultado de
# EXITO + sin señal de FALLO). El veto reusa FAILURE_SIGNAL_RE_CI/CS en la forma
# EXACTA del raíl de evento (:1930-1935) — dos greps, variables EXPANDIDAS, la CS
# case-SENSITIVE — MAS `exit[[:space:]]+[1-9]`, este ultimo PROPIO del label: el
# raíl de evento recibe el exit por otro canal y FAILURE_SIGNAL_RE_CI/CS no
# cubre 'exit 1'. (Responsabilidad del lead: el diseño original tenia exit [1-9];
# se reuso la constante del raíl y se re-sumo el exit aca. NUNCA comillas
# simples: buscaria el literal del nombre y el veto jamas dispararia — §4.3.)
#
# 18.18 — cada salida SIN credito deja en $saikit_verif_motivo (GLOBAL a
# proposito, jamas `local`: el Stop la lee para nombrar la condicion incumplida)
# la razon especifica. Solo se setea cuando el label estuvo PRESENTE y fue el
# juez: saikit_verif_evidence_ok la resetea a "" antes de cada llamada, asi un
# turno SIN label (o en host no ciego) conserva el mensaje generico de siempre.
saikit_verif_subagente_credita() {
  local saikit_text="$1"
  local saikit_spans saikit_span saikit_credito saikit_cmd_visto
  saikit_host_ciego || return 1
  printf '%s' ",$agents_seen," | grep -q ",verifier," \
    || { saikit_verif_motivo="the VERIFIED BY SUBAGENT label was present but no verifier subagent ran this turn"; return 1; }
  saikit_spans="$(saikit_verif_spans "$saikit_text")"
  # Sin spans no hay motivo especifico (defensivo: evidence_ok solo llama con
  # label presente, asi que este retorno no deberia alcanzarse): mensaje generico.
  [ -n "$saikit_spans" ] || return 1
  # Veto sobre TODOS los spans (Greptile P1, PR #72): cualquier label con señal
  # de fallo descalifica el turno entero — un exito declarado antes o despues de
  # un fallo declarado no lo tapa. "Nunca mas laxo que el rail": el rail de
  # evento ve todas las lineas, el label tambien.
  # El cuarto grep (SAIKIT_VERIFIED_CERO_RE) descalifica "0 passed" y formas
  # hermanas: RESULT_RE las rematchea por la rama `passed` pelada (CodeRabbit).
  { printf '%s\n' "$saikit_spans" | grep -Eiq "$FAILURE_SIGNAL_RE_CI" \
    || printf '%s\n' "$saikit_spans" | grep -Eq "$FAILURE_SIGNAL_RE_CS" \
    || printf '%s\n' "$saikit_spans" | grep -Eiq 'exit[[:space:]]+[1-9]' \
    || printf '%s\n' "$saikit_spans" | grep -Eiq "$SAIKIT_VERIFIED_CERO_RE" \
    || saikit_verif_fallo_pelado "$saikit_spans"; } \
    && { saikit_verif_motivo="the VERIFIED BY SUBAGENT label was present but one of its spans declares a failure: declared failures never count as verification"; return 1; }
  # Credito: ALGUN span trae comando Y resultado de exito en la MISMA linea.
  # Comando en un span y resultado en otro siguen siendo piezas dispersas (codex
  # #2) y no acreditan.
  saikit_credito=1
  saikit_cmd_visto=0
  while IFS= read -r saikit_span; do
    [ -n "$saikit_span" ] || continue
    printf '%s' "$saikit_span" | grep -Eiq "$SAIKIT_VERIFIED_CMD_RE" || continue
    saikit_cmd_visto=1
    printf '%s' "$saikit_span" | grep -Eiq "$SAIKIT_VERIFIED_RESULT_RE" || continue
    saikit_credito=0
    break
  done <<SAIKIT_SPANS_EOF
$saikit_spans
SAIKIT_SPANS_EOF
  # Sin credito: el motivo distingue si ALGUN span nombro comando del
  # vocabulario (fallo el resultado en el MISMO span) o si ninguno lo nombro
  # (comando fuera del vocabulario cerrado).
  if [ "$saikit_credito" != "0" ]; then
    if [ "$saikit_cmd_visto" = "1" ]; then
      saikit_verif_motivo="the VERIFIED BY SUBAGENT label was present but its command line carries no SUCCESS result (e.g. exit 0) on the SAME line as the command"
    else
      saikit_verif_motivo="the VERIFIED BY SUBAGENT label was present but its command is not in the accepted vocabulary (runner words like pytest/npm test, or this repo's tests/run.sh)"
    fi
  fi
  return "$saikit_credito"
}

# Task 14.2 — devuelve 0 si la evidencia de verificacion esta satisfecha (sin
# contar verified=1, que se chequea afuera). Si el label VERIFIED BY SUBAGENT
# esta PRESENTE, el predicado §4.3 es el UNICO juez (no se consulta el fallback
# de prosa/runner): asi un label con fallo no acredita por la via laxa (A11) y el
# label queda a la par del raíl de evento — "nunca mas laxo que el raíl". Sin
# label, comportamiento identico al de antes (design 14.1 §3/§4.3).
saikit_verif_evidence_ok() {
  local saikit_ok_text="$1"
  # 18.18 — el motivo se resetea EN LA ENTRADA (no en la salida): un turno sin
  # label, o en host no ciego, no debe heredar el motivo de la ultima llamada y
  # el Stop tiene que armar el mensaje generico de siempre.
  saikit_verif_motivo=""
  # El label solo es juez en hosts de canal interno ciego (zcode). En cualquier
  # otro host (o sin label), la evidencia se juzga por el camino de antes
  # (prosa runner|skip OR runner en posicion de comando) — asi el label no cambia
  # el comportamiento en claude/codex/grok (la frase no los toca).
  if saikit_host_ciego && printf '%s' "$saikit_ok_text" | grep -Eiq "$SAIKIT_VERIFIED_SUBAGENT_RE"; then
    saikit_verif_subagente_credita "$saikit_ok_text"
  else
    { printf '%s' "$saikit_ok_text" | grep -Eiq "$TEST_RUNNER_WORD_RE|$VERIFY_SKIP_RE" \
      || printf '%s' "$saikit_ok_text" | grep -Eiq "$TEST_RUNNER_CMD_RE"; }
  fi
}

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
# Task 10.15 -- A11 VUELVE POR OTRA PUERTA. La 3.8 cerro A11 grepeando senales
# de fracaso en la salida del runner, y eso funciona cuando la salida EXISTE.
# En el evento de DESPACHO de un job en background todavia no hay salida: el
# tool_response dice "Command running in background with ID: ..." y nada mas.
# El guard de fallas no tiene que mirar, asi que acreditaba igual. MEDIDO en
# vivo (2026-08-15): se lanzo `bash tests/run.sh`, el log anoto `verified:`
# mientras el job corria, y esa bateria termino en FAIL. El gate dio por
# verificado un turno cuya verificacion fallo -- exactamente A11.
#
# No existe un segundo evento donde mirar el resultado: cuando el job termina,
# el aviso llega por la via del PROMPT como notificacion de tarea, no como un
# PostToolUse (medido al implementar la 10.14). Y desde la 10.14 el hook ignora
# esas notificaciones a proposito.
#
# Decision, siguiendo el precedente del spec (limites DECLARADOS en vez de
# chequeos fingidos, ver la fila A11): si no hay resultado observable, NO se
# acredita. Denegar credito falla del lado seguro; otorgarlo en falso es A11.
# El resultado real sigue viajando por la prosa del recibo, que el gate ya
# exige. Limite declarado: el grep va sobre el payload entero, asi que un
# comando que mencione literalmente estas cadenas tampoco acredita -- falso
# negativo, del lado seguro. Atado por caso_g2_runner_en_background_no_acredita.
SAIKIT_DESPACHO_BG_RE='running in background|moved to the background'
FAILURE_SIGNAL_RE_CI='failure_type|permission_denied|command not found|AssertionError:|AssertionFailedError:|Traceback \(most recent call last\)|SyntaxError:|TypeError:|ReferenceError:|RangeError:|error TS[0-9]|[1-9][0-9]*[[:space:]]+(failed|failing|failures?|errors?)|(failures?|errors?|failed)[=:]([[:space:]]*)?[1-9]'
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
FAILURE_SIGNAL_RE_CS='test result: FAILED|FAIL[^a-zA-Z]|FAILURES!|---[[:space:]]+FAIL:|FAILURE: Build failed|BUILD FAILED'

# Task 9.2 (C8): el primer token del comando. Si es echo o printf, el comando no
# acredita verificacion por mas que nombre un runner — `echo pytest` no corre
# pytest. Se aplica SOLO a la primera linea del comando (ver su uso).
ECHO_LEAD_RE='^[[:space:]]*(echo|printf)([[:space:]]|$)'

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
# Task 7.3 (D4): alias camel de Grok como FALLBACK — el snake gana si llega
# (misma postura que hookEventName en 5.4). En Grok el env del runner trae
# GROK_SESSION_ID garantizado (7.1, 12/12 dumps) y cubre A4 si el payload no
# entrega la clave; "el env es la via que el runner garantiza, no exime de
# leer el payload" — por eso es el ultimo recurso, no el primero.
if [ -z "$SESSION_ID" ]; then SESSION_ID="$(json_top_level_string sessionId)"; fi
if [ -z "$SESSION_ID" ] && [ "$HOST" = "grok" ]; then SESSION_ID="${GROK_SESSION_ID:-}"; fi
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

# >>> SAIKIT-STATE-TTL v1 >>>
# Task 9.7 (C13): `state/` crecia para siempre. Cada limpieza borraba los
# ARCHIVOS y dejaba el directorio de la sesion: una sesion = un dir vacio
# inmortal. Dos mitades, y una sin la otra no arregla nada.
#
# (a) podar_dir_sesion: `rmdir` best-effort al final de CADA limpieza. Es
#     `rmdir`, JAMAS `rm -rf`: si por lo que sea quedo algo adentro, el dir
#     sobrevive y se ve, en vez de borrarse en silencio.
podar_dir_sesion() { rm -f "$STATE_DIR/receta_alias" 2>/dev/null || true; rmdir "$STATE_DIR" 2>/dev/null || true; }

# (b) barrer_estado_viejo: al ARMAR, se llevan las hermanas del MISMO
#     proyecto+host cuyo `harness-state.env` pasa el TTL. Cubre las sesiones que
#     nunca cerraron limpio, que son justo las que (a) no alcanza a tocar.
#
#     TTL en minutos porque `-mmin` es lo portable: `touch -d '15 days ago'`,
#     `touch -t` y `find -mmin` se MIDIERON funcionando en MSYS2 antes de
#     escribir esto, asi que no hizo falta el TTL-por-env que preveia el plan.
#
#     Tres acotamientos, cada uno con su razon:
#       - sin `find` no se barre nada (fail-open, Core Rule 1);
#       - solo se borra lo que cae DEBAJO de $PROJECT_DIR (el `case` lo verifica
#         sobre la ruta ya resuelta, no sobre el patron);
#       - nunca el dir del turno que dispara el barrido.
#     El estado FRESCO de una hermana viva sobrevive: barrer por edad sin
#     discriminar seria A4 otra vez, borrandole el estado a una sesion en curso.
SAIKIT_STATE_TTL_MIN=20160   # 14 dias
barrer_estado_viejo() {
  command -v find >/dev/null 2>&1 || return 0
  [ -d "$PROJECT_DIR" ] || return 0
  find "$PROJECT_DIR" -mindepth 2 -maxdepth 2 -type f -name 'harness-state.env' \
       -mmin "+$SAIKIT_STATE_TTL_MIN" 2>/dev/null | while IFS= read -r _viejo; do
    _dir="$(dirname "$_viejo")"
    [ "$_dir" = "$STATE_DIR" ] && continue
    case "$_dir" in "$PROJECT_DIR"/?*) rm -rf "$_dir" 2>/dev/null || true ;; esac
  done
  return 0
}
# <<< SAIKIT-STATE-TTL v1 <<<

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
  # Task 7.3 (D4): el objeto padre se recibe como $2 (default tool_input) para
  # el alias camel de Grok — toolInput — sin duplicar el escanner. La
  # precedencia la da el CALLER (primero snake, fallback camel), no el orden
  # de aparicion en el payload.
  padre="${2:-tool_input}"
  # Atajo barato y equivalente — el escaner solo puede encontrar lo que este en
  # el texto. Un turno real son ~300 eventos y solo 8 traen el campo (medido en
  # la captura de la Task 1.4), asi que esto ahorra el proceso en la mayoria.
  case "$INPUT" in
    *"\"$field\""*) ;;
    *) return 0 ;;
  esac
  printf '%s' "$INPUT" | awk -v want="$field" -v padre="$padre" '
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
              if (depth == 2 && clave1 == padre && clave == want) { print txt; exit }
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
# Task 7.3 (D4): la clave se recibe como $1 (default snake) para el alias
# camel de Grok — lastAssistantMessage — sin duplicar el walker. La
# precedencia snake la da last_assistant_text, el wrapper de abajo.
assistant_text_payload() {
  clave_want="${1:-last_assistant_message}"
  case "$INPUT" in
    *"\"$clave_want\""*) ;;
    *) return 0 ;;
  esac
  printf '%s' "$INPUT" | awk -v want="$clave_want" '
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
        if (c == ":")                { if (depth == 1) c1 = ultima; espera = 1 }
        else if (c == "{" || c == "[") { depth++; espera = 0 }
        else if (c == "}" || c == "]") { depth--; espera = 0 }
        else if (c == ",")             { espera = 0 }
      }
    }'
}

# Task 7.3 (D4): el texto final del turno con precedencia snake — Grok manda
# lastAssistantMessage (camel, medido 7.1 en los 3 Stops de turno). Si ambos
# llegan, gana el snake: misma postura que sessionId/toolName/transcriptPath.
last_assistant_text() {
  t="$(assistant_text_payload last_assistant_message)"
  [ -n "$t" ] || t="$(assistant_text_payload lastAssistantMessage)"
  printf '%s' "$t"
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
          depth--; espera = 0
          # Task 9.6 (C12): al SALIR se resetea lo que al entrar se prendio. Sin
          # esto, en_text/en_assistant quedaban en 1 para siempre y la condicion
          # de emision NO mira depth — asi que un valor top-level POSTERIOR a
          # `message` (un requestId, por ejemplo) se concatenaba al texto del
          # asistente y aportaba etiquetas que el turno no escribio. Medido: una
          # fuga con `Retro:` cerraba un gate al que le faltaba justo esa.
          if (depth < 4) en_text = 0
          if (depth < 2) en_assistant = 0
          continue
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
    # Task 18.13 (c): el Write del veredicto es el artefacto de cierre del
    # reviewer, no una edicion de codigo: acreditarlo hacia que un turno de
    # SOLO revision reportara trabajo que no existio (la golden del escenario
    # 56 lo mostraba: last_code_edit=1).
    */.saikit/veredictos/*|.saikit/veredictos/*) return 0 ;;
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
# Task 13.4: write_state persiste ADEMAS el estado del candado adversary —
# epoca de armado (ISO UTC), rutas permitidas registradas, flag de violacion y
# rutas violadas, |-separadas. Disciplina M3 del design de la Phase 13: viven
# en el PROPIO harness-state.env que los caminos de limpieza existentes
# (A4-c2/c4) ya borran; un archivo nuevo huerfano bajo $STATE_DIR resurrectaria
# la violacion en el proximo armado y esta prohibido por diseno. El armado
# (start_harness) REEMPLAZA estos campos — jamas appendea a un estado previo
# sobreviviente (CodeRabbit Major #64-b). La epoca viaja en ISO UTC porque es
# la forma que el arnes de salida dorada ya normaliza (<TS>): en segundos la
# linea base dejaria de ser reproducible entre corridas.
write_state() {
  task_hash="$1"
  cycle="$2"
  implemented="$3"
  verified="$4"
  agents_seen="$5"
  lane="$6"
  adv_epoch="$7"
  adv_paths="$8"
  adv_violation="$9"
  adv_violation_paths="${10}"
  veredicto_sha256="${11:-}"
  autopilot="${12:-}"
  mkdir -p "$STATE_DIR" 2>/dev/null || true
  {
    printf 'task_hash=%s\n' "$task_hash"
    printf 'cycle=%s\n' "$cycle"
    printf 'implemented=%s\n' "$implemented"
    printf 'verified=%s\n' "$verified"
    printf 'agents_seen=%s\n' "$agents_seen"
    printf 'lane=%s\n' "$lane"
    printf 'adv_epoch=%s\n' "$adv_epoch"
    printf 'adv_paths=%s\n' "$adv_paths"
    printf 'adv_violation=%s\n' "$adv_violation"
    printf 'adv_violation_paths=%s\n' "$adv_violation_paths"
    # Sello del veredicto (D16): se escribe SOLO cuando hay hash (el hook lo
    # registra en el Write del reviewer sobre veredictos/). Ausente para
    # cualquier otro evento, asi la forma del estado de los demas turnos no
    # cambia (los escenarios de la linea base siguen byte-identicos).
    if [ -n "$veredicto_sha256" ]; then printf 'veredicto_sha256=%s\n' "$veredicto_sha256"; fi
    # 18.6: mismo patron que veredicto_sha256 — la linea autopilot se escribe
    # SOLO en turnos autopilot. Se exige =1 (no solo no-vacio): el armado pasa
    # "0" cuando el carril no se detecto, y escribir autopilot=0 cambiaria la
    # forma del estado de TODOS los turnos (linea base dejaria de ser
    # byte-identica); un sufijo typo cae a full con la linea AUSENTE.
    if [ "$autopilot" = "1" ]; then printf 'autopilot=%s\n' "$autopilot"; fi
  } > "$STATE_PATH" 2>/dev/null || true
}

# 18.6: parrafo del contrato para el carril autopilot. Decision del 2026-08-30:
# ya NO dice que mergea solo; prepara todo, para y pregunta antes de publicar,
# merge solo con el si del operador; sobrevive D21 (merge antes del recibo, SOLO
# tools/saikit-merge.sh, Close con sha mergeado o razon de no-merge); sin checks
# nuevos en el Stop; D7 (lo autorizado en setup no se vuelve a preguntar);
# sentinel POR TURNO (diferencia con el full-autonomy grant). UNA sola fuente:
# la emiten los TRES emisores del Stop (harness_context, build_gate_feedback y
# emit_budget_exhausted); en grok build_gate_feedback lo omite porque el
# bloqueo lleva harness_context adosado y ya viene ahi.
autopilot_parrafo() {
  cat <<'AUTOPILOT_P'
Autopilot lane (-saikit:autopilot):
- This turn runs the FULL ceremony above; the autopilot flag adds no new Stop checks.
  You prepare everything — implementation, verification, review, the PR itself — but you
  STOP AND ASK before publishing: the merge happens ONLY with the operator's explicit yes,
  never on your own. With that yes, the merge goes BEFORE the receipt and ONLY via
  tools/saikit-merge.sh, never a bare `gh pr merge`; the Close cites the merged sha or the
  reason no merge happened. The sentinel is PER-TURN: it grants no standing permission
  (that is the difference with a full-autonomy grant), and what the operator already
  authorized in setup is not asked again.
AUTOPILOT_P
}

# Task 10.12 -- el bloque de arriba (numerado 1-6, "1. Understand - ...")
# describe las ETAPAS en prosa con guion, no la FORMA del recibo que el Stop
# gate realmente lee (has_receipt_label exige que cada etiqueta EMPIECE su
# linea, seguida de dos puntos, sin importar el guion). Medido en vivo
# (2026-08-15): un recibo con las seis compuertas correctas pero decoradas
# ("Understand -- ...") fue rechazado entero y costo un ciclo completo de
# revision de los dos del presupuesto. El bloque "Receipt line shape" de mas
# abajo muestra la forma minima ("Etiqueta: ...") para que el modelo no copie
# el estilo con guion de la lista numerada al escribir el recibo real. Sobre
# el claim original de esta tarea ("has_receipt_label ya es correcto"
# respecto del inicio de linea): era FALSO hasta 18.23 — la regex no tenia
# ancla y una etiqueta a mitad de renglon contaba. 18.23 vuelve real ese
# claim (el ancla ^) y el bloque de forma afirma ademas la regla de
# parrafos: cada etiqueta del recibo abre su propio parrafo. Atado por
# caso_g1_contrato_muestra_forma_recibo.
harness_context() {
  # r2 (Greptile P1 / CR PR #28): el heredoc con delimitador entrecomillado NO
  # expande $TOOL_HINT — llegaba LITERAL al modelo ("delegate via $TOOL_HINT").
  # Sustitucion controlada a posteriori: unico punto donde la variable
  # entra al contrato, el resto del heredoc sigue sin expansion.
  _hc="$(cat <<'HARNESS_CONTEXT'
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
- PAUSED is ONLY for when you cannot proceed yet. If the work is DONE and you are asking for a decision (deploy? merge?), write the full receipt and put your question after it — do NOT add the PAUSED line: the receipt closes the gate cleanly and your question stands on its own.

Waiting on a subagent is not failing:
- A delegated implementer/verifier/reviewer subagent can take a long time to answer (tens of minutes is normal). Do not stall the turn waiting on it, and do not close it with a receipt you cannot honestly write yet.
- While you are waiting on that subagent, END THE TURN with a final line that reads exactly, naming the role you delegated to:
  SUMMONAIKIT HARNESS DELEGATED - awaiting <ROLE>
  where <ROLE> is implementer, verifier, reviewer, or adversary — naming one of those is what makes the line count.
- That line tells the harness you are correctly waiting on a subagent, so it will not demand a completed receipt. As soon as that subagent answers, resume the cycle: read its output and continue from where you left off. If the user sends a NEW message without -saikit before you resume, the gate stands down by design — the promised cycle still applies: finish it yourself, or ask them to re-arm with -saikit.

$RECETAS_MENU

Delegation rule:
- Delegate the implement, verify, and review gates to subagents via $TOOL_HINT, in this exact sequence:
  1) the implementer subagent, then 2) the verifier subagent, then 3) the reviewer subagent.
- Write the brief with the 8 fields of recetas/00-lider.md (GOAL, SCOPE, CONTEXT, ACCEPTANCE, VERIFY, TIMEBOX, FORBIDDEN, REPORT) when the recipe book is present.
- If your host does not surface those project-level agents in $TOOL_HINT, delegate to its
  nearest equivalent instead — an engineer/coding agent to implement, a test/QA agent to verify,
  a code-review agent to review. The gate maps host agent names to these roles by function, so a
  correctly-delegated turn still satisfies it.
- You (the lead) handle the Understand step yourself and act as closer and retro: ask the user up front, then reconcile the subagents' evidence and write the final receipt in plain language.
- The turn cannot end until an implementer-, verifier-, and reviewer-role subagent have each run, in that order.
- Commit BEFORE dispatching the reviewer — the code AND the trail (.saikit/decisiones/<task>.tsv and the blast artifact) — so `git rev-parse HEAD` during the review is the sha of the tree under review: the sealed verdict cites that sha, and the merge cross-checks it against the PR head.
- The adversary is an OPTIONAL fourth role, opt-in — a turn that does not dispatch it closes exactly as today. Delegate it between the verifier and the reviewer via $TOOL_HINT when the change touches auth, payments, migrations or pre-existing data, or this harness itself (the same bar that triggers a cross-review). It reports findings to an artifact under .saikit/findings/ and never repairs. When you ran an adversary this turn, dispatch the reviewer NAMING the artifact to adjudicate (e.g. "adjudica .saikit/findings/<file>.json"); if this turn did NOT run an adversary, the reviewer adjudicates nothing. Declared limit: an adversary whose invocation is never observed is indistinguishable from not invoked.
- Subagent crash fallback: if a role subagent dispatch fails on infrastructure (usage limit / 429 / tool error), retry it ONCE. If it fails again, perform that role YOURSELF following its role definition, and declare it in the receipt with a line reading exactly "ROLE FALLBACK: <ROLE> (reason)" — the gate accepts that declaration in place of the dispatch. Never silently skip a role. A dispatch stuck for many minutes with no output counts as failed — abandon it and apply this same fallback.

Fast lane (-saikit:fast):
- A turn armed with -saikit:fast is exempt from the three-subagent ceremony: you (the lead)
  implement directly. The receipt and real verification evidence (or a declared skip) are
  still required. A plain -saikit arm runs the full ceremony above.
$ALIAS_LINEA
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
- Two branches, always: (a) technical or reversible → decide it yourself from the repo and present the result; (b) product, preference or IRREVERSIBLE (force-push, deleting data, messages to third parties, deploys, payments) → ask the smallest set of plain-language questions FIRST and end the turn with the PAUSED line. A fact you could observe by running something is never a question for the human: sketch it (recipe boceto) and let the result decide.
- Never block on questions the repo already answers, and never silently guess on questions it cannot answer: if you must proceed without an answer, state the assumption in plain words to the user and record it in the diff.

User-facing surface baseline (language/framework/platform agnostic):
- For ANY user-facing surface you add or change, cover the full state matrix explicitly: loading, EMPTY (no data), error, and success — not only the happy path.
- Meet an accessibility baseline: semantic structure (a labelled region/heading, and a list or table for repeated/tabular data rather than nested generic containers), an accessible name for every control and icon-only action, visible keyboard focus, and a working keyboard path.
- Keep it responsive for long or overflowing content, and match the repo's existing component/section style instead of a generic template. Reuse the installed UI library's already-accessible primitives rather than re-implementing them.

Receipt line shape (this is what the gate checks, not the numbered stage list above): each receipt label opens its own paragraph (blank line between paragraphs); never glue several labels into one block. ADVERSARY:, ROLE FALLBACK: and VERIFIED BY SUBAGENT: get the same treatment. What matters within the line is that each label is followed by a COLON. A hyphen '-', asterisk '*' or plus '+' bullet, or markdown bold around the label is fine -- "- **Understand**: ..." counts; a blockquote ('>'), a nested bullet and a bullet without a space ('-Label:') do not. What does NOT count is replacing the colon with a dash or any other separator: the numbered stage list above is written "1. Understand - ...", and copying that dash into the receipt fails every label at once. Bare, the six lines are:
Understand: ...
Implement: ...
Verify: ...
Review: ...
Close: ...
Retro: ...
ADVERSARY: N findings, highest severity X — required ONLY in receipts of turns where an adversary actually ran (any lane); presence only, the numbers are never checked. ROLE FALLBACK: ADVERSARY (reason) substitutes the line when the dispatched adversary died without reporting.
VERIFIED BY SUBAGENT: <comando y resultado> — declaration ONLY for a receipt on a host whose INTERNAL channel is blind, i.e. the harness cannot see a delegated subagent's tool events (zcode today; kimi once measured). When you delegated verification to a verifier subagent and its evidence never reached the harness, name the exact command and its SUCCESS result here, on the SAME line as the label (e.g. `VERIFIED BY SUBAGENT: python -m py_compile app.py exit 0`); the harness reads the command and result only from the label's own line, so a command placed on the next line is not seen. A human re-runs the named command. Invalid on hosts that DO surface those events — there keep the real evidence; a declared failure (failed / exit non-zero) never counts. Golden: the 2026-08-25 zcode live turn (already documented in the smoke doc).

Final receipt required before stopping (write every line in plain, clear language):
SUMMONAIKIT HARNESS RECEIPT
Understand: in one or two plain sentences, what the user asked for, plus any question you asked or assumption you made.
Implement: changed files and implementation summary; for any read/listing/reporting surface, state whether its data source already existed or is newly created and the assumption recorded in code; or why no code change was needed.
Verify: exact commands/checks run and results, or an explicit skip that uses one of these phrases — not run, not executed, skipped, no corri, no se corrio, sin tests — plus a concrete reason. "No corri los candados" counts; "PASS" or od/wc alone does not.
Review: findings, risks, or "no findings" with basis.
Close: evidence summary and remaining gaps; state explicitly whether code was touched after the reviewer subagent last ran (yes/no); if you pushed a branch or opened a PR, state that git log origin/<default>..HEAD contains only this task's commits; if a verdict was sealed this turn, cite the sha and path of the sealed verdict (.saikit/veredictos/<sha>.json). Say first what changes for the user, then how, then why; never invent a link, citation or command you did not produce or read this turn.
Retro: harness/codebase-memory improvement, or "none".
HARNESS_CONTEXT
)"
  _menu="$(recetas_menu)"
  _alias="$(cat "$STATE_DIR/receta_alias" 2>/dev/null)"
  _alias_linea=""
  [ -n "$_alias" ] && _alias_linea="Fast lane by alias: this turn is -saikit:$( [ "$_alias" = investigar ] && echo pregunta || echo boceto ); the recipe is $_alias. Do NOT touch production code."
  _hc="${_hc//\$TOOL_HINT/$TOOL_HINT}"
  _hc="${_hc//\$RECETAS_MENU/$_menu}"
  _hc="${_hc//\$ALIAS_LINEA/$_alias_linea}"
  # 18.6, bloque 1 del contrato: el parrafo autopilot se emite SOLO cuando el
  # estado del turno tiene autopilot=1 (el output de turnos no-autopilot no
  # cambia). Bloque 2 (build_gate_feedback) emite el mismo parrafo — tocar uno
  # solo dejaria el gate afirmando cosas distintas segun la rama que emita.
  if [ "$(read_state_value autopilot)" = "1" ]; then
    _hc="$(printf '%s\n\n%s' "$_hc" "$(autopilot_parrafo)")"
  fi
  printf '%s' "$_hc"
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
# Task 10.16: la regla 1 nombra el LUGAR, no solo la frecuencia. El texto
# anterior decia "una corrida por tarea, al final" y se cumplio al pie de la
# letra en tres tareas seguidas (10.10, 10.8 y el paquete A) -- las tres en
# local. El diagnostico ya estaba ESCRITO en
# docs/task-10.4-datapoint-2026-08-15.md desde la primera, y se repitio igual:
# el agente cumplia la regla literalmente y se quedaba tranquilo. Medido en la
# maquina que sufrio el problema: crear un proceso cuesta 56 ms y una
# invocacion del hook 658 ms; la misma bateria son ~10 min en local y 2m58s en
# el CI de Linux. La mencion va CONDICIONADA ("si el repo tiene CI") porque el
# kit corre en repos que pueden no tenerlo.
#
# PR #33 (greptile P1): la regla nombra ABRIR EL PR, no solo empujar la rama.
# Muchas configuraciones corren CI en pull_request pero NO en un push de rama
# suelta -- medido en este mismo repo el 2026-08-16: se empujo
# fix/paquete-A-gate-v2 y no se creo ninguna corrida hasta abrir el PR. Una
# regla que mande a esperar un resultado que nunca llega es su propia perdida
# de tiempo. Coderabbit pidio ademas exigir Linux; se tomo PARCIAL: exigirlo
# dejaria la regla inaplicable en repos con CI de Windows o macOS, donde
# sacarla de la maquina propia sigue conviniendo. Se nombra de donde sale el
# ~6x sin convertirlo en requisito.
# Contraste deliberado con la Task 10.11, que decidio NO construir un candado
# porque el texto alcanzaba: aca el texto FALLO tres veces y la correccion
# sigue siendo texto -- porque lo que fallo fue que estaba INCOMPLETO, no que
# se ignorara. Atado por caso_g1_reglas_nombran_donde_correr_la_bateria.
# Task 11.1: datapoint de campo Kimi 2026-08-16 — una rama cortada de un master
# LOCAL llevo un commit no pusheado al PR sin que nadie lo decidiera; el bullet
# nuevo exige base origin/<default> + verificacion de git log antes del PR.
# Atado por caso_g1_reglas_exigen_base_de_rama_limpia.
standing_rules() {
  cat <<'STANDING_RULES'
SUMMONAIKIT STANDING RULES (session-wide — these apply whether or not the turn is armed with -saikit)
- Run the FULL test battery ONCE per task, at the end, and run it WHERE it is cheapest: if the repo has CI, push a branch, OPEN A PULL REQUEST, and read the CI result instead of running the battery on this machine. Opening the PR is not optional bookkeeping: many setups run CI on pull_request but NOT on a bare feature-branch push, so pushing alone leaves you waiting for a result that never arrives. If that CI run does not actually include the full battery, run the battery locally instead: the invariant is that the FULL battery runs once SOMEWHERE, not that CI was consulted. Locally, red/green ONLY the single test file you are changing, never the whole suite. Saying "once per task" without saying where is not enough: measured on a Windows machine, the same battery took ~10 min locally and 2m58s in Linux CI (that ~6x is where the win comes from; other CI platforms still beat blocking your own machine), and three tasks in a row paid the local price while technically obeying the rule.
- Create the task branch from origin/<default> (git fetch first), NEVER from your local default branch. Before opening the PR, verify `git log origin/<default>..HEAD` lists ONLY this task's commits; anything else means your base was dirty — rebase onto origin/<default> before the PR. Measured failure mode: a branch cut from a local master carried an unpushed local commit straight into the PR without anyone deciding it.
- Do NOT sit blocked waiting on a background job. Start it, keep doing other work; you are notified when it finishes.
- Before waiting on an external reviewer or CI, check whether it ALREADY finished instead of re-polling in a loop.
STANDING_RULES
}

# Acotado a los hosts con VEREDICTO, uno por uno. La 10.6 dejo solo claude (unico
# medido entonces); la 10.9 midio los otros tres el 2026-08-16 y el resultado NO
# fue uniforme — que es justo por lo que se mide en vez de extrapolar:
#
#   claude  ACEPTADA (10.6)  repo descartable + `claude -p` headless.
#   codex   ACEPTADA (10.9)  los dos oraculos coinciden: el nonce entra al
#                            rollout como mensaje role:"developer" (la forma que
#                            6.2 midio para UPS) y el modelo devuelve el token
#                            literal que el texto le pedia.
#   grok    IGNORADA (10.9)  las 3 formas emitieron y ninguna llego, ni a la
#                            respuesta ni a los archivos de sesion (1.0.4).
#   zcode   ACEPTADA (10.9)  turno real con el operador adelante. El texto entra
#                            al request del modelo como mensaje role="system" con
#                            el prefijo `SessionStart hook additional context:` y
#                            numeracion `#1` — la MISMA forma que 5.2 midio para
#                            UPS, solo cambia el nombre de la fase — y el modelo
#                            devolvio el token literal que ese texto le pedia.
#                            NO necesita rama propia: zcode resuelve a
#                            TARGET=claude por el fallback de la 5.4, asi que
#                            esta condicion ya lo cubre. Lo que cambio es el
#                            REGISTRO: install-hook.sh --host zcode pasa de 3 a 4
#                            fases, atado en test_install_hook.
#
# Registrarlos a ciegas es el error que la 6.2 evito por un pelo, y esta fila
# volvio a mostrarlo desde otro angulo: en Codex un hook nuevo ni siquiera CORRE
# sin su trusted_hash en config.toml, y se saltea en silencio.
#
# La forma emitida es UNA sola para los dos hosts que emiten, y eso esta medido,
# no supuesto: 6.2 midio que el esquema de Codex es ESTRICTO (una clave extra
# invalida la salida entera), asi que la forma limpia de Claude es tambien la
# unica que Codex acepta.
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

# Task 10.14 -- DEFECTO: una notificacion de tarea en background llega al hook
# como UserPromptSubmit (la dispara la regla permanente 2 de la 10.6: "lanzala
# y segui", que es la conducta que el kit mismo pide) y, al no traer el
# sentinel, start_harness la trataba como un turno humano nuevo y ejecutaba el
# desarme A4-c2 completo: un turno armado perdia el gate a mitad de camino, en
# silencio.
#
# MEDIDO sobre 46 turnos reales del transcript de esta sesion: el texto
# <task-notification> aparece en 5 de 5 notificaciones y 0 de 41 turnos
# humanos (igual <task-id> y </task-notification> -- discriminan perfecto). El
# cartel "[SYSTEM NOTIFICATION - NOT USER INPUT]" NO sirve de marca: 0/5 en el
# transcript crudo -- lo agrega el harness al MOSTRARLE el evento al modelo, no
# viaja en el payload del hook.
#
# NO se pudo medir si ese texto llega efectivamente al campo `prompt` del
# payload (exigiria tools/capture-payloads.sh en una sesion nueva con
# operador). Por eso el acotamiento de abajo exige las DOS condiciones a la
# vez -- el lado seguro: si el prompt viene vacio/ausente, no desarma (cubre la
# forma no medida); si trae la marca, tampoco (cubre la forma medida). Un
# prompt HUMANO real sin sentinel SIGUE desarmando -- eso es A4 y no se afloja,
# aflojarlo de mas revive el defecto que ese borrado cierra
# (caso_g1_prompt_sin_sentinel_desarma fija esa regresion).
# ESTRICTA: anclada al inicio del texto y con el cierre presente. La version
# laxa (solo "contiene la marca") la rechazaron DOS revisores independientes
# en el PR #30 -- greptile P1 y coderabbit Major, mismo hallazgo: un prompt
# HUMANO que pide `-saikit` y ademas MENCIONA la marca (hablar de este mismo
# defecto ya la menciona) salia por la guarda y se quedaba SIN gate. Perder el
# candado justo cuando se pidio es peor que el defecto que la guarda cierra.
# Medido: las 5 notificaciones reales EMPIEZAN con la marca en su primera
# linea; una mencion humana la lleva en medio del texto.
SAIKIT_TASK_NOTIFICATION_RE='^[[:space:]]*<task-notification>'
# Laxa: solo se usa para NO DESARMAR (nunca para saltear el armado), como red
# por si el host antepusiera algo a la marca y la estricta no matcheara.
SAIKIT_TASK_NOTIFICATION_LAXA_RE='<task-notification>'
SAIKIT_TASK_NOTIFICATION_CIERRE_RE='</task-notification>'

# La forma laxa exige las DOS marcas, apertura y cierre. Motivo MEDIDO (PR #30,
# hallazgo de greptile que quedo a medias hasta esta correccion): con solo la
# apertura, un prompt HUMANO sin sentinel que apenas MENCIONA la marca dejaba
# vivo el estado armado anterior, y el Stop gate le exigia recibo a un turno que
# nadie pidio -- el sintoma A4 por otra puerta. Verificado en el laboratorio
# antes de corregir: el estado sobrevivia. La marca de cierre discrimina igual de
# bien que la de apertura (5/5 notificaciones reales, 0/41 turnos humanos) y una
# mencion casual no la lleva. Atado por
# caso_g1_mencion_humana_sin_sentinel_si_desarma.
parece_notificacion_laxa() {
  printf '%s' "$1" | grep -Eq "$SAIKIT_TASK_NOTIFICATION_LAXA_RE" || return 1
  printf '%s' "$1" | grep -Eq "$SAIKIT_TASK_NOTIFICATION_CIERRE_RE"
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
  # Task 10.14 (hallazgo de la revision cruzada + reviewer, 2026-08-15): la
  # notificacion se ataja ANTES del gate del sentinel, no solo en la rama del
  # desarme. Motivo: el texto de una notificacion de tarea PUEDE CONTENER
  # `-saikit` -- en este repo es lo normal, porque los prompts a subagentes y
  # los fixtures lo llevan, y la notificacion incluye el resumen/resultado. Si
  # eso pasa y el chequeo viviera solo en la rama "sin sentinel", la ejecucion
  # tomaba la rama de ARMADO: write_state resetea cycle/implemented/verified a
  # cero y el log se SOBRESCRIBE, borrando en silencio evidencia ya acreditada
  # del turno en curso (por ejemplo un verified=1 ganado por una corrida real).
  # Un evento del sistema no debe armar NI desarmar: se deja pasar intacto.
  # Solo la forma ESTRICTA saltea el gate entero. Atado por
  # caso_g1_notificacion_con_sentinel_no_rearma y por
  # caso_g1_mencion_humana_de_la_marca_sigue_armando.
  if [ "$PHASE" = "prompt" ] \
     && printf '%s' "$prompt_text" | grep -Eq "$SAIKIT_TASK_NOTIFICATION_RE"; then
    emit_allow
  fi

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
    #
    # Task 10.14: el desarme se acota ADEMAS a un prompt NO vacio. La
    # notificacion en su forma ESTRICTA ya se atajo arriba; aca se usa la LAXA
    # como red: si el host antepusiera algo a la marca, la estricta no matchea y
    # sin esto volveriamos a desarmar con un evento del sistema. Nunca al reves:
    # la laxa JAMAS saltea el armado, para no perder el gate cuando se pidio.
    # aca no se repite ese chequeo -- repetirlo dejaria una clausula
    # inalcanzable y su mutacion no la atraparia nadie.
    #
    # COSTO RESIDUAL DECLARADO (hallazgo del reviewer, 2026-08-15): antes de
    # esta task un UserPromptSubmit con `prompt` vacio/ausente SI desarmaba, y
    # ahora no. Si algun host produjera esa forma para un turno HUMANO genuino
    # (el caso plausible: un mensaje que es solo un adjunto, sin texto) estando
    # vivo un turno -saikit abandonado, ese turno humano heredaria el estado
    # viejo y el Stop gate le exigiria recibo -- el sintoma de A4 por otra
    # puerta. Se acepta con este precedente MEDIDO: el fixture de la Task
    # 9.4/C9 mostro que en `claude` la forma sin campo `prompt` correlaciona
    # con eventos de SISTEMA (un resume), no con un mensaje humano nuevo. Si
    # aparece un host donde no valga, se mide y se acota por host.
    if [ "$PHASE" = "prompt" ] && [ -f "$STATE_PATH" ] \
       && [ -n "$prompt_text" ] \
       && ! parece_notificacion_laxa "$prompt_text"; then
      rm -f "$STATE_PATH" "$LOG_PATH" "$RN_ORDER_PATH" 2>/dev/null || true  # A4-c2 desarme
      podar_dir_sesion   # Task 9.7 (C13): el dir tambien se va, no solo los archivos
    fi
    # >>> SAIKIT-STANDING-RULES v1 >>>
    # Task 10.6: la fase session sin sentinel salia en silencio; ahora deja las
    # reglas permanentes. Va DESPUES del desarme y ANTES del emit_allow, y esta
    # acotado a session: si corriera en prompt, un turno sin sentinel dejaria de
    # ser mudo y se rompe caso_g1_no_arma_sin_sentinel (esa es la regresion que
    # atrapa una rama mal acotada, por eso 10.6 no agrega un caso propio).
    # No arma, no escribe estado y no toca el gate del sentinel.
    # Task 10.9: emiten claude (10.6), codex y zcode, los tres MEDIDOS. grok NO:
    # se midio y su additionalContext se ignora en esta fase.
    #
    # zcode no aparece en la condicion y sin embargo emite: viaja bajo
    # TARGET=claude por el fallback de la 5.4. Lo que lo habilito no fue este
    # `if` sino su REGISTRO — install-hook.sh --host zcode pasa a registrar la
    # 4a fase, atado en test_install_hook.
    if [ "$PHASE" = "session" ] && { [ "$TARGET" = "claude" ] || [ "$TARGET" = "codex" ]; }; then
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
  receta_alias=""
  # Alias de receta (16.6, fix 2): el alias SOLO baja el carril y nombra la
  # receta si esta EXISTE en el recetario con su sha verificado. Si no (sin
  # recetario, hash distinto, nombre inseguro): carril full, sin alias y sin
  # linea en el contrato — el mismo lado seguro al que ya cae un typo del sufijo.
  if printf '%s' "$prompt_text" | grep -Eq '(^|[^A-Za-z0-9_/-])-saikit:pregunta([^A-Za-z0-9_-]|$)'; then
    if receta_valida "investigar"; then lane="fast"; receta_alias="investigar"; fi
  fi
  if printf '%s' "$prompt_text" | grep -Eq '(^|[^A-Za-z0-9_/-])-saikit:boceto([^A-Za-z0-9_-]|$)'; then
    if receta_valida "boceto"; then lane="fast"; receta_alias="boceto"; fi
  fi
  # 18.6: carril autopilot. Misma frontera exacta que :fast — el RE del
  # sentinel no cambia. El flag NO baja el carril: autopilot gana sobre
  # :fast/:alias porque su parrafo solo tiene sentido con ceremonia completa.
  # Sufijo desconocido (-saikit:autopiloto) cae a full SIN flag, el mismo
  # lado seguro que el typo de :fast. Atado por caso_g1_autopilot_arma_full_con_flag.
  autopilot="0"
  if printf '%s' "$prompt_text" | grep -Eq '(^|[^A-Za-z0-9_/-])-saikit:autopilot([^A-Za-z0-9_-]|$)'; then
    autopilot="1"; lane="full"; receta_alias=""
  fi

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
  # Task 13.4: el armado INICIALIZA el estado del candado adversary — epoca
  # capturada ACA, antes de que exista cualquier evento del adversary, y los
  # tres campos restantes REEMPLAZADOS en vacio (jamas appendeados a un estado
  # previo sobreviviente de una sesion muerta con la misma llave, CodeRabbit
  # Major #64-b). ISO UTC: es la forma que la linea base dorada normaliza.
  adv_epoch_armado="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)"
  write_state "$task_hash" "0" "0" "0" "" "$lane" "$adv_epoch_armado" "" "" "" "" "$autopilot"
  rm -f "$STATE_DIR/receta_alias"; [ -n "$receta_alias" ] && printf '%s\n' "$receta_alias" > "$STATE_DIR/receta_alias"
  # Task 9.7 (C13): el barrido va DESPUES de write_state, asi el estado de este
  # turno ya existe y esta fresco — no puede barrerse a si mismo ni por edad ni
  # por el skip explicito. Fail-open: si no hay `find`, no se barre nada.
  barrer_estado_viejo
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
    -e 's,://[^[:space:]@/?#]*@,://[REDACTED]@,g' \
    -e 's/ghp_[A-Za-z0-9_-]*/[REDACTED]/g' \
    -e 's/github_pat_[A-Za-z0-9_-]*/[REDACTED]/g' \
    -e 's/gho_[A-Za-z0-9_-]*/[REDACTED]/g' \
    -e 's/(^|[^A-Za-z0-9])(sk-[A-Za-z0-9_-]*)/\1[REDACTED]/g' \
    -e 's/AKIA[0-9A-Z]{16}/[REDACTED]/g' \
    -e 's/xox[bp]-[A-Za-z0-9_-]*/[REDACTED]/g'
}

# >>> SAIKIT-ADVERSARY-LOCK v1 (Task 13.4) >>>
# Candado del rol adversary (D3 + D2 capas 2-3, docs/phase-13-adversary-design.md).
# 13.1 midio CERO PreToolUse en todos los hosts: no existe canal de negacion
# previa, asi que el candado es DETECCION POST-HOC de escrituras atribuidas al
# adversary fuera de .saikit/findings/ + bloqueo en el Stop. Posturas de falla:
# fail-open por defecto (Core Rule 1) para todo lo de infraestructura; fail-
# closed SOLO por (1) violacion detectada — defecto probado por el propio evento
# que lo reporta — y (2) secreto matcheado en un artefacto de ESTA sesion —
# riesgo alto con ruta de fuga manual declarada (archivo:linea, redactar o
# borrar, re-cerrar). La atribucion usa los canales que $subagent ya resuelve
# (despacho o interno, M1); en hosts con canal interno unknown (zcode/kimi) el
# candado queda CIEGO declarado — no bloquea por atribucion ahi.
#
# Alcance por sesion (A1 + Greptile P1): todos estos mecanismos corren solo en
# sesiones armadas cuyo estado registra al adversary; el escaneo mira las rutas
# que ESTA sesion registro mas los archivos con mtime >= SU epoca de armado —
# los artefactos historicos de otras tareas no vuelven a bloquear nada.
# kimi #1 (cross-review r2 del PR #65): PROJECT_ROOT puede venir de `git
# rev-parse` en forma C:/ (Git Bash) mientras los blancos se canonicalizan con
# cd+pwd -P (forma /c/) — el prefijo se ancla con la MISMA maquinaria FISICA
# que canonicaliza los blancos, o el candado bloquea al reves TODA escritura
# legitima en Windows. codex #1: -P ademas resuelve dirs symlink intermedios.
# Fallback textual si el root no existe (fail-open, familia A6).
ADV_PROJECT_CANON="$(cd "$PROJECT_ROOT" 2>/dev/null && pwd -P)" || ADV_PROJECT_CANON=""
ADV_FINDINGS_DIR="${ADV_PROJECT_CANON:-$PROJECT_ROOT}/.saikit/findings"
VERDICTOS_DIR="${ADV_PROJECT_CANON:-$PROJECT_ROOT}/.saikit/veredictos"

# Familia de patrones del escaneo de secretos = la MISMA que redact_secrets
# lleva inline (claude #3 del cross-review): el hook corre en el repo CONSUMER,
# donde tools/check-secrets.sh no existe; duplicar sus formatos extendidos ser-
# ia drift sin candado de fuente unica. Capa reducida, declarada: falso
# negativo por regex que no matchea y falso positivo por repro legitimo, ambos
# con la ruta de fuga manual de arriba.
#
# Familia ampliada en la Task 17.3 / D12: ademas de `token=`/`password=` y las
# credenciales de URI, la familia cubre ahora las FORMAS DE TOKEN conocidas —
# ghp_, github_pat_, gho_, sk-, AKIA y xox[bp]- (el set que redact_secrets NO
# cubria, medido). La MISMA familia vive en tools/lib/redactar.sh, fuente unica
# para las HERRAMIENTAS del repo (rastro de decisiones y blast); el hook
# conserva su copia INLINE porque corre instalado, solo, en el repo consumer,
# donde `tools/` no existe. Quien toque la familia aca lo refleja en
# tools/lib/redactar.sh, y al reves — el test test_saikit_decision.sh lo canda.
# El valor exige AL MENOS un caracter ([^[:space:]]): un `token=` pelado no
# persiste nada. Y las formas YA redactadas se DESCUENTAN antes de grepear
# (lead + kimi #2, r2 PR #65): el artefacto redactado EXACTAMENTE como manda
# el perfil (token=[REDACTED], ://[REDACTED]@) no es un secreto persistido —
# sin el descuento, la disciplina de la capa 1 disparaba la capa 2 y el camino
# documentado como correcto bloqueaba el cierre. El sed preserva lineas (los
# numeros del reporte siguen validos) y una linea MIXTA (valor real junto al
# redactado) sigue matcheando por el vecino.
SAIKIT_ADV_SECRET_RE='([Tt][Oo][Kk][Ee][Nn]|[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd])=[^[:space:]]|://[^[:space:]@/?#]*@|ghp_[A-Za-z0-9]|github_pat_[A-Za-z0-9]|gho_[A-Za-z0-9]|(^|[^A-Za-z0-9])sk-[A-Za-z0-9]|AKIA[0-9A-Z]|xox[bp]-[A-Za-z0-9]'
# El reemplazo deja un ESPACIO donde estaba el marcador (adversary r1 EN VIVO,
# 13.9, hallazgo HIGH): sin el, un marcador que cierra un string JSON — la
# forma que el propio contrato del artefacto exige — dejaba `token="` con la
# comilla pegada al `=` y el regex volvia a matchear: el camino documentado
# como correcto bloqueaba en su formato canonico. El espacio corta el match
# ([^[:space:]]) sin romper la preservacion de lineas ni la linea mixta.
# Tres reglas, cada una con su razon (las dos primeras vinieron del port —
# summonaikit-kimi PR #13 — que las habia endurecido antes que este hook):
#   1. VALOR ENTRECOMILLADO (`token="[REDACTED]"`): la forma mas natural al
#      redactar dentro de un JSON. Sin esta regla el `=` quedaba seguido de `"`,
#      el strip no disparaba y el artefacto BIEN redactado bloqueaba el cierre.
#   2. Marcador seguido de DELIMITADOR: sin exigirlo, `token=[REDACTED]sk-real`
#      se descontaba entero y el secreto pegado EVADIA el escaneo — era un
#      limite residual declarado en el spec, y deja de serlo.
#      El delimitador lo exigen las DOS reglas: la 1 sin el dejaba pasar
#      `token="[REDACTED]"sk-real` (Greptile, PR #75) — el mismo agujero por
#      la puerta de al lado. Cualquier regla nueva que se agregue acá tiene
#      que exigirlo tambien, o reabre esta familia.
#
#      El delimitador es una LISTA BLANCA a proposito, y se mantiene como tal.
#      La primera version omitia `;` y `)`, asi que un `token=[REDACTED];` BIEN
#      redactado no matcheaba ninguna regla, sobrevivia entero y disparaba el
#      escaneo: el gate bloqueaba un artefacto correcto (Greptile P1, PR #75).
#      Se agregan esos dos; NO se invierte la lista.
#
#      Por que no invertirla, que era lo elegante: usar `[^A-Za-z0-9_-]` COMO
#      DELIMITADOR hace que cualquier signo termine el valor, y entonces
#      `token=[REDACTED]!secreto` se descuenta -> queda `token= !secreto`, el
#      espacio corta el match de `=[^[:space:]]` y el secreto SALE (Greptile P1,
#      PR #79). O sea la inversion cambia un bloqueo falso —ruidoso pero
#      visible— por una fuga silenciosa. Para un escaneo de secretos la
#      direccion correcta es fallar hacia BLOQUEAR, asi que gana la lista aunque
#      haya que completarla de a un signo: el costo de que le falte uno es
#      friccion que alguien ve, y el de que sobre es un secreto que nadie ve.
#      (Ojo: `[^A-Za-z0-9_-]` SI aparece abajo, pero en el otro rol — como
#      guardia de la COLA despues del delimitador, no como el delimitador. Ahi
#      aprieta en vez de aflojar.)
#      El criterio para agregar un signo: que la REDACCION pueda producirlo
#      despues del valor (cierre de JSON, de comando, de prosa). No alcanza con
#      que "sea puntuacion" — `!`, `$`, `@`, `#` son prefijos perfectos de un
#      secreto pegado y no cierran ningun valor.
#
#      COLA PEGADA TRAS EL DELIMITADOR: `token=[REDACTED],sk-real`. El
#      delimitador esta, asi que la regla de arriba descontaba y la cola con el
#      secreto sobrevivia. Esto NO lo trajeron `;` y `)` — pasaba igual con `,`,
#      `"` y `}` desde antes (Greptile P1, PR #79; medido sobre las dos listas).
#      Por eso el delimitador va en TRES ramas, y cada una admite un conjunto
#      distinto con una exigencia distinta:
#        a) espacio o fin de linea: descuenta siempre. Ahi el valor termino y lo
#           que siga es otra cosa; exigirle algo mas bloquearia la prosa normal
#           (`token=[REDACTED] aparecio en config`).
#        b) delimitadores de ESTRUCTURA (`] " [ , } >`): descuentan solo si lo
#           que sigue es otro caracter estructural o fin de linea. Asi
#           `token=[REDACTED]","uri"...` —forma JSON, la del camino real— se
#           descuenta, y `token=[REDACTED],sk-real` no.
#        c) `;` y `)`: descuentan solo si despues viene ESPACIO o fin de linea.
#
#      Por que (c) es mas estricta que (b), que es el punto fino de todo esto:
#      `;` y `)` no estaban en la lista original, asi que meterlos como
#      delimitadores comunes ABRE caminos que antes no existian para ellos, y
#      ningun guardia de UN caracter alcanza — siempre hay un relleno que lo
#      satisface. Medido: con el guardia "no puede ser continuacion de secreto"
#      (`[^A-Za-z0-9_-]`) lo saltea `token=[REDACTED];!sk-real`, y con el
#      guardia ESTRUCTURAL lo saltea `token=[REDACTED];]sk-real` — un `]` es
#      estructural (Greptile y CodeRabbit, PR #79). Exigir espacio/fin de linea
#      no se puede rellenar por construccion: cualquier caracter de relleno, por
#      definicion, no es espacio. Cubre las formas reales (`;` o `)` cerrando la
#      linea o seguidos de prosa) sin abrir nada.
#
#      Medida contra la version original en 16 formas: mejor o igual en todas,
#      peor en ninguna. Arregla los bloqueos falsos de `;` y `)`, y cierra dos
#      fugas que ya existian (`,sk-real` y `,!sk-real`).
#      Queda ABIERTO —igual que antes, no es regresion— el relleno estructural
#      tras un delimitador de (b): `token=[REDACTED],]sk-real`. Cerrarlo pide
#      inspeccionar la cola entera con conciencia del formato, que es otra
#      tarea; la forma JSON legitima tambien trae letras despues del
#      delimitador, asi que ninguna regex de una pasada las distingue.
#   3. Credenciales en URI, igual que antes.
# El espacio del reemplazo es load-bearing: corta el match de `=[^[:space:]]`.
SAIKIT_ADV_REDACTED_STRIP='s/="\[REDACTED\]"([[:space:]]|$)/= "\1/g; s/="\[REDACTED\]"([]"[,}>])([]"[{},;:)>[:space:]]|$)/= "\1\2/g; s/="\[REDACTED\]"([;)])([[:space:]]|$)/= "\1\2/g; s/=\[REDACTED\]([[:space:]]|$)/= \1/g; s/=\[REDACTED\]([]"[,}>])([]"[{},;:)>[:space:]]|$)/= \1\2/g; s/=\[REDACTED\]([;)])([[:space:]]|$)/= \1\2/g; s|://\[REDACTED\]@|:// |g'

# Gitignore del consumer (D2 capa 3): clase de efecto NUEVA declarada — hasta
# aqui el hook solo escribia bajo su state dir. Dispara con el PRIMER evento
# que resuelva a adversary por cualquier canal medido, despacho o interno (M1:
# anclarlo solo al despacho dejaba a codex sin gitignore para siempre). Idem-
# potente y conservador como el instalador: crea si ausente, JAMAS reescribe
# uno existente (aunque no cubra los artefactos: limite declarado, codex #4).
# Un .gitignore que sea symlink tampoco se toca (-L ademas de -e): escribir a
# traves de un enlace seria exactamente la escritura-fuera-del-dir que este
# candado existe para impedir.
adv_ensure_gitignore() {
  # Sin canon FISICO de la raiz no se escribe nada (mejora traida del port,
  # summonaikit-kimi PR #13): si `cd $PROJECT_ROOT && pwd -P` fallo,
  # ADV_FINDINGS_DIR cayo al fallback TEXTUAL, y crear ahi es escribir en una
  # ruta que nadie pudo resolver. El escaneo ya trata ese caso como fail-open;
  # el gitignore hace lo mismo en vez de escribir a ciegas.
  if [ -z "$ADV_PROJECT_CANON" ]; then return 0; fi
  # codex #1a (r2 PR #65): jamas crear a TRAVES de un enlace — un .saikit (o
  # un findings) symlink mandaria el gitignore fisico fuera del repo. Fail-open.
  if [ -L "${ADV_FINDINGS_DIR%/*}" ] || [ -L "$ADV_FINDINGS_DIR" ]; then return 0; fi
  mkdir -p "$ADV_FINDINGS_DIR" 2>/dev/null || return 0
  if [ ! -e "$ADV_FINDINGS_DIR/.gitignore" ] && [ ! -L "$ADV_FINDINGS_DIR/.gitignore" ]; then
    printf '*\n' > "$ADV_FINDINGS_DIR/.gitignore" 2>/dev/null || true
  fi
  return 0
}

# Sello del veredicto (D16, Task 18.3). En un PostToolUse de un Write atribuido
# al rol reviewer sobre `.saikit/veredictos/`, el hook registra en el estado de
# sesion `veredicto_sha256` = sha256 del archivo que el reviewer acaba de
# escribir (el tool_input.content que el Write materializo; en PostToolUse el
# archivo ya existe). Es un **registro de estado**, NO un check del Stop — el
# gate sigue advisory. Cualquier escritura posterior — del lider, de otro rol,
# por Edit o por Bash — cambia el archivo y el hash deja de coincidir (asi el
# merge de D18 detecta un veredicto tocado despues del sello).
verdict_ensure_gitignore() {
  # Igual disciplina que adv_ensure_gitignore: solo en sesion cuyo root pudo
  # resolverse, jamas a traves de un enlace, idempotente y sin tocar uno ajeno.
  if [ -z "$ADV_PROJECT_CANON" ]; then return 0; fi
  if [ -L "${VERDICTOS_DIR%/*}" ] || [ -L "$VERDICTOS_DIR" ]; then return 0; fi
  mkdir -p "$VERDICTOS_DIR" 2>/dev/null || return 0
  if [ ! -e "$VERDICTOS_DIR/.gitignore" ] && [ ! -L "$VERDICTOS_DIR/.gitignore" ]; then
    printf '*\n' > "$VERDICTOS_DIR/.gitignore" 2>/dev/null || true
  fi
  return 0
}

# ¿El blanco del Write es un veredicto? Se canonicaliza con `adv_canon_path`
# (backslash→slash, relativo→root, cd dirname && pwd -P) y se compara contra
# $VERDICTOS_DIR/*, asi la forma absoluta de Windows (C:\...) y la relativa
# (.saikit/veredictos/...) sellan igual. Los -L evitan un .saikit enlazado
# (misma disciplina que adv_path_dentro).
verdict_path_dentro() {
  local vp
  vp="$(adv_canon_path "$1")"
  [ -n "$vp" ] || return 1
  if [ -L "${VERDICTOS_DIR%/*}" ]; then return 1; fi
  if [ -L "$VERDICTOS_DIR" ]; then return 1; fi
  case "$vp" in
    "$VERDICTOS_DIR"/*) return 0 ;;
  esac
  return 1
}

# Decodifica los escapes JSON de un string LEIDO POR STDIN (el que
# `json_tool_input_string` devuelve con los escapes crudos: `\"`, `\n`, `\t`,
# `\\`, `\r`). Es lo que vuelve el `content` del Write equivalente al archivo que
# materializa (D16: el sello se hashea sobre el contenido real, no sobre la forma
# escapada). Decodifica `\r` a un retorno de carro (contenido CRLF).
verdict_unescape() {
  awk '
    { out = ""; esc = 0
      for (i = 1; i <= length($0); i++) {
        c = substr($0, i, 1)
        if (esc) {
          if      (c == "n") out = out "\n"
          else if (c == "t") out = out "\t"
          else if (c == "r") out = out "\r"
          else if (c == "\\") out = out "\\"
          else if (c == "\"") out = out "\""
          else                out = out "\\" c
          esc = 0
        } else if (c == "\\") { esc = 1 }
        else out = out c
      }
      printf "%s", out
    }'
}

verdict_registrar_sello() {
  # $1 = sha256 (ya computado por el llamador con el pipeline del handler del
  # Write: `printf '%s' "$vd_content" | verdict_unescape | sha256sum`). No se pasa
  # el contenido por `$(...)` porque la sustitucion de comando recorta el salto de
  # linea final; en su lugar el llamador computa el hash sobre el contenido exacto
  # decodificado. Registra veredicto_sha256 = $1: es lo que el Write materializo
  # en el archivo, asi la comparacion posterior (D18: sha256 del archivo actual vs
  # estado) coincide mientras el archivo no se toque, y deja de coincidir tras
  # cualquier escritura posterior.
  local vd_sha="$1" vd_task vd_cycle vd_impl vd_verif vd_agents vd_lane vd_ae vd_ap vd_av vd_avp
  vd_task="$(read_state_value task_hash)";  [ -z "$vd_task" ] && vd_task="unknown"
  vd_cycle="$(read_state_value cycle)";     [ -z "$vd_cycle" ] && vd_cycle="0"
  vd_impl="$(read_state_value implemented)"; [ -z "$vd_impl" ] && vd_impl="0"
  vd_verif="$(read_state_value verified)";   [ -z "$vd_verif" ] && vd_verif="0"
  vd_agents="$(read_state_value agents_seen)"
  vd_lane="$(read_state_value lane)"
  vd_ae="$(read_state_value adv_epoch)"
  vd_ap="$(read_state_value adv_paths)"
  vd_av="$(read_state_value adv_violation)"
  vd_avp="$(read_state_value adv_violation_paths)"
  write_state "$vd_task" "$vd_cycle" "$vd_impl" "$vd_verif" "$vd_agents" "$vd_lane" "$vd_ae" "$vd_ap" "$vd_av" "$vd_avp" "$vd_sha" "$(read_state_value autopilot)"
  if [ -n "$vd_sha" ]; then
    printf 'veredicto_sha256: %s\n' "$vd_sha" >> "$LOG_PATH" 2>/dev/null || true
  fi
  return 0
}

# Reescribe el estado preservando los 6 campos clasicos y poniendo los 4 del
# candado ($1 epoca, $2 rutas permitidas, $3 violacion, $4 rutas violadas);
# $5 opcional reemplaza el ciclo (lo usa el bloque temprano del Stop).
adv_reescribir_estado() {
  task_hash="$(read_state_value task_hash)"
  cycle="$(read_state_value cycle)"
  implemented="$(read_state_value implemented)"
  verified="$(read_state_value verified)"
  agents_seen="$(read_state_value agents_seen)"
  lane="$(read_state_value lane)"
  veredicto_sha256="$(read_state_value veredicto_sha256)"
  if [ -z "$task_hash" ]; then task_hash="unknown"; fi
  if [ -z "$cycle" ]; then cycle="0"; fi
  if [ -z "$implemented" ]; then implemented="0"; fi
  if [ -z "$verified" ]; then verified="0"; fi
  if [ -n "${5:-}" ]; then cycle="$5"; fi
  write_state "$task_hash" "$cycle" "$implemented" "$verified" "$agents_seen" "$lane" "$1" "$2" "$3" "$4" "$veredicto_sha256" "$(read_state_value autopilot)"
}

adv_registrar_violacion() {
  advv_nueva="$1"
  advv_epoch="$(read_state_value adv_epoch)"
  advv_paths="$(read_state_value adv_paths)"
  advv_lista="$(read_state_value adv_violation_paths)"
  if [ "$(read_state_value adv_violation)" != "1" ]; then
    printf 'adversary-write-violation: %s\n' "$(redact_secrets "$advv_nueva")" >> "$LOG_PATH" 2>/dev/null || true
  fi
  case "|$advv_lista|" in
    *"|$advv_nueva|"*) ;;
    *) if [ -n "$advv_lista" ]; then advv_lista="$advv_lista|$advv_nueva"; else advv_lista="$advv_nueva"; fi ;;
  esac
  adv_reescribir_estado "$advv_epoch" "$advv_paths" "1" "$advv_lista"
}

adv_registrar_path_permitido() {
  advp_nueva="$1"
  advp_epoch="$(read_state_value adv_epoch)"
  advp_lista="$(read_state_value adv_paths)"
  case "|$advp_lista|" in
    *"|$advp_nueva|"*) return 0 ;;
  esac
  if [ -n "$advp_lista" ]; then advp_lista="$advp_lista|$advp_nueva"; else advp_lista="$advp_nueva"; fi
  adv_reescribir_estado "$advp_epoch" "$advp_lista" "$(read_state_value adv_violation)" "$(read_state_value adv_violation_paths)"
}

# Canonicaliza el blanco de una escritura: backslashes de Windows a slashes
# (los lectores json_* no decodifican escapes y transcript_path ya midio esa
# forma), relativas ancladas al PROJECT_ROOT que el hook resuelve para su
# propio state (claude #4 — no al cwd del proceso, que un cd del turno puede
# mover), y resolucion FISICA de ../ y symlinks via cd+pwd -P — pwd LOGICO no
# resuelve un dir symlink intermedio (codex #1 / qwen #5, r2 PR #65) —, la
# familia de normalizacion A6/Task 3.6. Si el dir del blanco no existe (archivo borrado
# entre evento y chequeo), colapso textual de segmentos — sin dir no hay
# enlace que seguir. Vacio = no se pudo canonicalizar: el caller hace
# fail-open y lo declara por stderr.
adv_canon_path() {
  advc_p="${1//\\//}"
  case "$advc_p" in
    /*) ;;
    [A-Za-z]:/*) ;;
    *) advc_p="$PROJECT_ROOT/$advc_p" ;;
  esac
  advc_dir="$(cd "$(dirname "$advc_p")" 2>/dev/null && pwd -P)" || advc_dir=""
  if [ -n "$advc_dir" ]; then
    printf '%s/%s' "${advc_dir%/}" "$(basename "$advc_p")"
    return 0
  fi
  case "$advc_p" in
    [A-Za-z]:/*)
      if command -v cygpath >/dev/null 2>&1; then
        advc_p="$(cygpath -u "$advc_p" 2>/dev/null || printf '%s' "$advc_p")"
      fi
      ;;
  esac
  printf '%s' "$advc_p" | awk '
    $0 !~ /^\// { print ""; exit }
    {
      n = split($0, seg, "/"); sp = 0
      for (i = 1; i <= n; i++) {
        if (seg[i] == "" || seg[i] == ".") continue
        if (seg[i] == "..") { if (sp > 0) sp--; continue }
        pila[++sp] = seg[i]
      }
      out = ""
      for (i = 1; i <= sp; i++) out = out "/" pila[i]
      print out
    }'
}

# ¿El blanco canonico cae bajo findings/? La comparacion es sobre el prefijo
# LITERAL, sin resolver el directorio: un findings/ que SEA symlink es
# violacion de setup, no ruta permitida (claude #9 — canonicalizar ambos lados
# con realpath haria pasar todo a traves de un enlace plantado por el hueco de
# Bash). Y si el propio blanco es un symlink, se resuelve su destino real
# (readlink -f) antes de comparar: un enlace DENTRO de findings apuntando afuera
# escribe afuera.
adv_path_dentro() {
  # r2 PR #65 (codex #1a): el PADRE enlazado tambien es setup violado — sin
  # este check, un .saikit -> afuera dejaba el prefijo textual adentro.
  if [ -L "${ADV_FINDINGS_DIR%/*}" ]; then return 1; fi
  if [ -L "$ADV_FINDINGS_DIR" ]; then return 1; fi
  case "$1" in
    "$ADV_FINDINGS_DIR"/*) ;;
    *) return 1 ;;
  esac
  if [ -L "$1" ]; then
    advd_real="$(readlink -f "$1" 2>/dev/null || true)"
    [ -n "$advd_real" ] || return 1
    case "$advd_real" in
      "$ADV_FINDINGS_DIR"/*) return 0 ;;
    esac
    return 1
  fi
  return 0
}

# Deteccion post-hoc de Edit/Write (D3). El vocabulario de tools de edicion es
# el MISMO que usa la senal de orden del review-notice (Task 7.3 D5): una sola
# definicion de "que es una edicion" en el hook. La escritura PERMITIDA tambien
# se registra (adv_paths): es el alcance explicito del escaneo de secretos.
adv_guard_edit() {
  [ -n "$2" ] || return 0
  printf '%s' "$1" | grep -Eiq '^(edit|write|multiedit|notebookedit|apply_patch|str_replace_editor|create_file|edit_file|search_replace)$' || return 0
  advg_canon="$(adv_canon_path "$2")"
  if [ -z "$advg_canon" ]; then
    printf 'summonaikit-harness: adversary: ruta no canonicalizable (%s); candado fail-open para ese evento\n' "$2" >&2
    return 0
  fi
  if adv_path_dentro "$advg_canon"; then
    adv_registrar_path_permitido "$advg_canon"
  else
    adv_registrar_violacion "$advg_canon"
  fi
  return 0
}

# Bash best-effort (D3): redireccion/heredoc/tee OBVIOS en comandos atribuidos
# al adversary. MISMA familia declarada que la guardia G2 de runners: no es un
# parser de shell. Antes de extraer blancos se limpian los tramos ENTRECOMILLA-
# DOS (un programa awk con un > comparativo no es una redireccion) y se
# descartan blancos con expansion ($, backtick) o dup de fd (&N): no son
# "obvios". /dev/null no es una escritura de archivo. cp/mv/dd quedan fuera
# del vocabulario — huecos declarados al spec, como los runners encadenados.
SAIKIT_ADV_BASH_REDIRECT_RE=">>?[[:space:]]*[^;&|<>[:space:]\"']+"
SAIKIT_ADV_BASH_TEE_RE="(^|[;&|([[:space:]])tee([[:space:]]+-a)?[[:space:]]+[^;&|<>[:space:]\"']+"
adv_guard_bash() {
  [ -n "$2" ] || return 0
  printf '%s' "$1" | grep -Eiq '^(bash|run_terminal_command)$' || return 0
  advb_cmd="$(printf '%s' "$2" | sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g")"
  advb_blancos="$(
    {
      printf '%s' "$advb_cmd" | grep -Eo "$SAIKIT_ADV_BASH_REDIRECT_RE" | sed -E 's/^>>?[[:space:]]*//'
      printf '%s' "$advb_cmd" | grep -Eo "$SAIKIT_ADV_BASH_TEE_RE" | sed -E 's/^.*tee([[:space:]]+-a)?[[:space:]]+//'
    } | sort -u)"
  [ -n "$advb_blancos" ] || return 0
  while IFS= read -r advb_b; do
    [ -n "$advb_b" ] || continue
    case "$advb_b" in
      # /dev/null* (no solo exacto): el candado EN VIVO bloqueo al lead con
      # los blancos `/dev/null)` (el `)` de un subshell entra al token — el
      # regex no lo excluye) y `/dev/null/necho` (un `\n` literal del JSON —
      # los lectores json_* no decodifican escapes — pegado al blanco, con la
      # `\` vuelta `/` por la canonicalizacion). Nada real se escribe "bajo"
      # /dev/null (es un archivo): excluir el prefijo entero es la direccion
      # segura del best-effort, declarada.
      /dev/null*|'&'*) continue ;;
      *'$'*|*'`'*) continue ;;
    esac
    advb_canon="$(adv_canon_path "$advb_b")"
    [ -n "$advb_canon" ] || continue
    if ! adv_path_dentro "$advb_canon"; then
      adv_registrar_violacion "$advb_canon"
    fi
  done <<EOF
$advb_blancos
EOF
  return 0
}

# Escaneo de secretos del Stop (D2 capa 2). Disparo: SOLO sesiones con
# ,adversary, en agents_seen (el caller filtro; hallazgo A1). Alcance por
# sesion (Greptile P1): rutas REGISTRADAS por el candado como escritas por el
# adversary de esta sesion + cualquier archivo del dir con mtime posterior o
# IGUAL a la epoca de armado (igualdad de tick incluida, Greptile P2: -newermt
# estricto sobre epoca-1 deja dentro todo mtime >= epoca). Asi cae el artefacto
# escrito por Bash, que el candado de Edit/Write no ve. Match => fail-closed
# nombrando archivo y NUMERO de linea, JAMAS el contenido (misma disciplina que
# tools/check-secrets.sh:24-25); ilegible => fail-open; sin dir o sin epoca
# legible => rama fuera, fail-open declarado. Un evasor que RETROCEDA el mtime
# con touch escapa: instancia del hueco Bash declarado (CodeRabbit #64-a) —
# este escaneo persigue persistencia ACCIDENTAL, no evasores deliberados.
# Imprime el motivo de bloqueo, o vacio si no hay match.
adv_chequear_secretos() {
  advs_candidatos="$(read_state_value adv_paths | tr '|' '\n')"
  advs_epoca="$(date -u -d "$(read_state_value adv_epoch)" +%s 2>/dev/null || true)"
  # qwen #3 (r2 PR #65): D3 exige fail-open + DIAGNOSTICO en fallas de infra;
  # sin GNU date (BSD/macOS) la rama de mtime se salta y hay que decirlo.
  if [ -z "$advs_epoca" ]; then
    printf 'summonaikit-harness: adversary: epoca de armado ilegible (GNU date -d ausente?); escaneo por mtime omitido — fail-open declarado\n' >&2
  fi
  if [ -n "$advs_epoca" ] && [ -d "$ADV_FINDINGS_DIR" ]; then
    advs_candidatos="$advs_candidatos
$(find "$ADV_FINDINGS_DIR" -type f -newermt "@$((advs_epoca - 1))" 2>/dev/null || true)"
  fi
  advs_vistos=""
  while IFS= read -r advs_f; do
    [ -n "$advs_f" ] || continue
    # Pipe de cierre en la comparacion: sin el, el ULTIMO agregado nunca
    # deduplicaba y se grepeaba dos veces (kimi #4, r2 PR #65).
    case "$advs_vistos|" in
      *"|$advs_f|"*) continue ;;
    esac
    advs_vistos="$advs_vistos|$advs_f"
    [ -f "$advs_f" ] || continue
    [ -r "$advs_f" ] || continue
    advs_linea="$(sed -E "$SAIKIT_ADV_REDACTED_STRIP" "$advs_f" 2>/dev/null | grep -En "$SAIKIT_ADV_SECRET_RE" | head -n 1 | cut -d: -f1)"
    if [ -n "$advs_linea" ]; then
      # CodeRabbit r2: el NOMBRE del artefacto lo eligio el adversary y puede
      # cargar un valor con pinta de secreto — el path viaja REDACTADO, misma
      # disciplina que la rama de violacion y la linea de log.
      printf '%s\n' "- Possible secret persisted in adversary artifact $(redact_secrets "$advs_f"):$advs_linea (content NOT shown). Redact or delete that artifact, then re-close. Fail-closed on purpose: a persisted secret is one git add away from a commit; a false positive escapes through this same manual path.\n"
      return 0
    fi
  done <<EOF
$advs_candidatos
EOF
  return 0
}
# <<< SAIKIT-ADVERSARY-LOCK v1 <<<

mark_evidence() {
  kind="$1"
  detail="$2"
  task_hash="$(read_state_value task_hash)"
  cycle="$(read_state_value cycle)"
  implemented="$(read_state_value implemented)"
  verified="$(read_state_value verified)"
  agents_seen="$(read_state_value agents_seen)"
  lane="$(read_state_value lane)"
  adv_epoch="$(read_state_value adv_epoch)"
  adv_paths="$(read_state_value adv_paths)"
  adv_violation="$(read_state_value adv_violation)"
  adv_violation_paths="$(read_state_value adv_violation_paths)"
  veredicto_sha256="$(read_state_value veredicto_sha256)"
  if [ -z "$task_hash" ]; then task_hash="unknown"; fi
  if [ -z "$cycle" ]; then cycle="0"; fi
  if [ -z "$implemented" ]; then implemented="0"; fi
  if [ -z "$verified" ]; then verified="0"; fi

  if [ "$kind" = "implemented" ]; then implemented="1"; fi
  if [ "$kind" = "verified" ]; then verified="1"; fi
  write_state "$task_hash" "$cycle" "$implemented" "$verified" "$agents_seen" "$lane" "$adv_epoch" "$adv_paths" "$adv_violation" "$adv_violation_paths" "$veredicto_sha256" "$(read_state_value autopilot)"
  printf '%s: %s\n' "$kind" "$(redact_secrets "$detail")" >> "$LOG_PATH" 2>/dev/null || true
}

# Map a host's agent/subagent name onto a canonical harness role
# (implementer | verifier | reviewer | adversary | closer | retro), or empty
# when the name carries no harness role. Hosts surface different agent names: Claude Code's
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
    adversary) printf 'adversary'; return 0 ;;
    closer) printf 'closer'; return 0 ;;
    retro) printf 'retro'; return 0 ;;
  esac
  # Task 13.4/13.5 (D6): el keyword adversar va ANTES de la rama reviewer. La
  # trampa medida: `adversarial-audit` matcheaba `audit` y acreditaba REVIEWER
  # sin review real — un nombre adversario llenaba el slot de review. Con esta
  # precedencia, adversarial-* resuelve a adversary (con su orden y su linea de
  # recibo propios) y el slot de reviewer sigue exigiendo su propio despacho.
  # El stem queda en `adversar`, tan acotado como el vocabulario del rol: NO se
  # amplian a attack/exploit/... (falsos positivos con herramientas de seguridad).
  if printf '%s' "$name" | grep -Eq '(^|[^a-z])adversar'; then printf 'adversary'; return 0; fi
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
  adv_epoch="$(read_state_value adv_epoch)"
  adv_paths="$(read_state_value adv_paths)"
  adv_violation="$(read_state_value adv_violation)"
  adv_violation_paths="$(read_state_value adv_violation_paths)"
  veredicto_sha256="$(read_state_value veredicto_sha256)"
  if [ -z "$task_hash" ]; then task_hash="unknown"; fi
  if [ -z "$cycle" ]; then cycle="0"; fi
  if [ -z "$implemented" ]; then implemented="0"; fi
  if [ -z "$verified" ]; then verified="0"; fi
  case ",$agents_seen," in
    *",$agent,"*)
      # Trampa de orden con adversary TARDIO (hallada por Greptile en el port,
      # PR #12 de summonaikit-kimi 2026-08-26; confirmada aca ejecutandola).
      # El dedupe conserva la posicion de la PRIMERA aparicion, asi que un lead
      # que ya corrio la ceremonia y DESPUES agrega el adversary queda con
      # `implementer,verifier,reviewer,adversary`: orden invalido para la regex
      # de 4 roles, y ningun re-despacho lo arregla — el turno solo salia
      # agotando presupuesto. Era el camino HONESTO castigado (el lead que
      # reacciona "esto tocaba auth, mejor lo ataco").
      # Arreglo acotado: un RE-despacho del reviewer, y solo cuando el adversary
      # ya esta en agents_seen, MUEVE al reviewer al final — porque lo que la
      # regla de orden protege es que la adjudicacion ocurra DESPUES del ataque,
      # y eso es exactamente lo que acaba de pasar. Alcance minimo a proposito:
      # cualquier otro rol re-despachado conserva su posicion (el dedupe de
      # siempre), y un adversary que corrio SIN reviewer posterior sigue
      # bloqueando (lo fija caso_g3_adversary_fuera_de_orden_bloquea, que
      # siembra el mismo agents_seen sin re-despacho).
      if [ "$agent" = "reviewer" ]; then
        case ",$agents_seen," in
          *",adversary,"*)
            # Quita el token exacto y re-anexa al final. Sin tr/paste (que el
            # hook no usa en ningun otro lado): comas de borde + un sed, y las
            # expansiones POSIX limpian los bordes.
            ra_lista="$(printf ',%s,' "$agents_seen" | sed 's/,reviewer,/,/')"
            ra_lista="${ra_lista#,}"; ra_lista="${ra_lista%,}"
            if [ -z "$ra_lista" ]; then agents_seen="reviewer"; else agents_seen="$ra_lista,reviewer"; fi
            ;;
        esac
      fi
      ;;
    *)
      if [ -z "$agents_seen" ]; then agents_seen="$agent"; else agents_seen="$agents_seen,$agent"; fi
      ;;
  esac
  write_state "$task_hash" "$cycle" "$implemented" "$verified" "$agents_seen" "$lane" "$adv_epoch" "$adv_paths" "$adv_violation" "$adv_violation_paths" "$veredicto_sha256" "$(read_state_value autopilot)"
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
  # Task 7.3 (D4): fallbacks camel de Grok — el snake gana si llega. El padre
  # de command/file_path pasa a toolInput en el fallback (medido 7.1: claves
  # camel en el envelope, snake adentro del objeto).
  [ -n "$tool_name" ] || tool_name="$(json_top_level_string toolName)"
  command_text="$(json_tool_input_string command)"
  [ -n "$command_text" ] || command_text="$(json_tool_input_string command toolInput)"
  file_path="$(json_tool_input_string file_path)"
  [ -n "$file_path" ] || file_path="$(json_tool_input_string file_path toolInput)"
  combined="$event_name $tool_name $command_text $file_path $INPUT"

  # Record harness subagent runs (the delegation tool carries a subagent_type in
  # its tool_input) so the Stop gate can enforce the implementer -> verifier ->
  # reviewer sequence. Se lee SOLO de `tool_input` de primer nivel: el resto del
  # payload trae el resultado de la herramienta, que el turno no escribio (A1).
  subagent="$(json_tool_input_string subagent_type)"
  # Task 7.3 (D4): tres canales medidos en Grok (7.1 ronda 5) — el despacho
  # spawn_subagent SI emite post_tool_use con toolInput.subagent_type (a
  # diferencia de Codex), y los eventos SubagentStart/internos del hijo traen
  # subagentType de PRIMER nivel. Fallbacks, no reemplazos: el snake de Claude
  # sigue ganando.
  [ -n "$subagent" ] || subagent="$(json_tool_input_string subagent_type toolInput)"
  if [ -z "$subagent" ]; then subagent="$(json_top_level_string subagentType)"; fi
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
  # >>> SAIKIT-ADVERSARY-LOCK v1 (Task 13.4) >>>
  # El candado corre solo en sesiones armadas (el early-exit de arriba ya lo
  # acoto, A1) y solo para eventos que resuelvan a adversary por cualquiera de
  # los canales medidos — $subagent ya lleva el despacho o el interno (M1).
  # Orden: primero el gitignore del consumer (el dir conviene que exista antes
  # de canonicalizar escrituras dentro), despues los guards de Edit/Write y
  # Bash. Los guards reescriben el estado preservando todo lo demas.
  adv_event_role=""
  if [ -n "$subagent" ]; then adv_event_role="$(canonical_agent_role "$subagent")"; fi
  if [ "$adv_event_role" = "adversary" ]; then
    adv_ensure_gitignore
    adv_guard_edit "$tool_name" "$file_path"
    adv_guard_bash "$tool_name" "$command_text"
  fi
  # <<< SAIKIT-ADVERSARY-LOCK v1 <<<
  # >>> SAIKIT-REVIEW-NOTICE v1 >>>
  rn_order_now="$(rn_bump_counter)"
  if [ -n "$subagent" ] && [ "$(canonical_agent_role "$subagent")" = "reviewer" ]; then
    rn_mark_review "$rn_order_now"
  fi
  # <<< SAIKIT-REVIEW-NOTICE v1 <<<

  # Task 18.13 (c): el Write del veredicto del reviewer NO es trabajo — es el
  # artefacto de cierre de la propia revision. Acreditarlo hacia que un turno
  # de SOLO revision reportara trabajo que no existio (la golden del escenario
  # 56 lo media: implemented=1 y last_code_edit=1). El flag guarda el grep
  # laxo de implemented de abajo; para last_code_edit, rn_is_noncode_path
  # excluye .saikit/veredictos/. Es el MISMO molde que el sello (D16):
  # reviewer por un canal medido + Write bajo veredictos/, calculado UNA sola
  # vez y reusado por el sello mas abajo.
  vd_write_reviewer=""
  if [ -n "$subagent" ] && [ "$(canonical_agent_role "$subagent")" = "reviewer" ] \
     && [ -n "$file_path" ] \
     && printf '%s' "$tool_name" | grep -Eiq '^(write)$' \
     && verdict_path_dentro "$file_path"; then
    vd_write_reviewer=1
  fi

  if [ -z "$vd_write_reviewer" ] && printf '%s' "$combined" | grep -Eiq 'afterFileEdit|Edit|Write|apply_patch|file_path|edits'; then
    mark_evidence "implemented" "${file_path:-file edit}"
  fi

  # >>> SAIKIT-VEREDICTO-SELLO v1 (D16, Task 18.3) >>>
  # El sello corre SOLO en sesiones armadas (el early-exit de arriba ya lo acoto)
  # y solo cuando el evento resuelve a reviewer por un canal medido ($subagent ya
  # lleva el despacho o el interno, M1) Y es un Write cuyo blanco cae bajo
  # .saikit/veredictos/ — la resolucion que el flag vd_write_reviewer de la
  # 18.13 (c) calcula arriba una sola vez. Es registro de estado — NO agrega
  # nada al Stop gate.
  if [ -n "$vd_write_reviewer" ]; then
    verdict_ensure_gitignore
    vd_content="$(json_tool_input_string content)"
    [ -z "$vd_content" ] && vd_content="$(json_tool_input_string content toolInput)"
    if [ -n "$vd_content" ]; then
      vd_sha="$(printf '%s' "$vd_content" | verdict_unescape | sha256sum | cut -c1-64)"
    else
      vd_sha=""
    fi
    verdict_registrar_sello "$vd_sha"
  fi
  # <<< SAIKIT-VEREDICTO-SELLO v1 <<<

  # >>> SAIKIT-REVIEW-NOTICE v1 >>>
  # Senal PRECISA para el orden, distinta del grep laxo de arriba (ese matchea
  # casi cualquier payload que mencione "edit" o una ruta). Solo cuenta un
  # tool_name realmente de edicion MAS un file_path real; sin ambos, no se
  # registra nada -- mejor perder una edicion que fecharla mal. Por diseno
  # (pedido explicito) esta senal NUNCA lanza git ni un proceso por archivo:
  # es solo el nombre de la herramienta del evento que el hook ya recibe.
  # Task 7.3 (D5): search_replace es la tool de edicion nativa de Grok (write
  # ya estaba en la lista); ambas traen toolInput.file_path (medido 7.1).
  if [ -n "$file_path" ] && printf '%s' "$tool_name" | grep -Eiq '^(edit|write|multiedit|notebookedit|apply_patch|str_replace_editor|create_file|edit_file|search_replace)$'; then
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
  # Task 7.3 (D5): en Grok las fallas de tool llegan como post_tool_use NORMAL
  # con toolResult de error — PostToolUseFailure no disparo nunca en 1.0.3
  # (medido 7.1, 3 clases de falla). Senales medidas: toolResult.exit_code != 0
  # (comando que revienta) y las variantes de error del objeto (FileNotFound /
  # NoMatchesFound, forma medida a primer nivel del toolResult). Sin esta
  # lectura un runner rojo no dejaba huella en $combined y acreditaba por
  # ausencia. El veto es SOLO del credito de verificacion (advisory, como todo
  # el gate); los hosts snake no traen toolResult y no se ven afectados.
  toolresult_err=""
  # exit_code viaja como NUMERO ("exit_code":1, sin comillas — medido 7.1), asi
  # que los lectores de strings del hook no lo ven (medido: output_for_prompt
  # sale, exit_code no). Patron grep ACOTADO al interior del toolResult: el
  # [^}]* no puede cruzar su cierre, y un eco de exit_code en OTRO objeto del
  # payload (clase C3) no puede colarse porque se exige "toolResult" antes sin
  # llaves de por medio. "exit_code":0 no matchea ([1-9] directo tras el ':').
  if printf '%s' "$INPUT" | grep -Eq '"toolResult"[^}]*"exit_code"[[:space:]]*:[[:space:]]*[1-9]'; then
    toolresult_err="1"
  fi
  if printf '%s' "$INPUT" | grep -Eq '"toolResult"[:[:space:]]*\{[^}]*"(FileNotFound|NoMatchesFound)"'; then
    toolresult_err="1"
  fi
  # Task 9.2 (C8), mitad que faltaba. Dos cambios sobre la condicion de credito:
  #
  #   1. ECHO_LEAD_RE: si el PRIMER token del comando es echo/printf, ese
  #      comando JAMAS acredita. `echo pytest` ponia al runner en posicion de
  #      comando legitima — TEST_RUNNER_CMD_RE lo daba por bueno — y acreditaba
  #      verificacion sin correr nada.
  #      Se mira SOLO la primera linea (`head -n 1`), no el comando entero: con
  #      `grep -E '^...'` sobre todo el texto, un comando multilinea legitimo que
  #      tuviera un `echo` en cualquier linea perderia el credito.
  #   2. el credito deja de mirar `tool_name`: las DOS ramas corren sobre
  #      `$command_text` SOLO. Un `tool_name` llamado como un runner —posible
  #      con una tool MCP— mas un comando `ls -la` acreditaba verificacion sin
  #      que corriera nada, y ECHO_LEAD_RE no lo tapa (el comando no empieza con
  #      echo). Hallado en la review del PR #22 y atado por
  #      caso_g2_tool_name_runner_con_comando_ajeno_no_marca.
  #
  #      La review proponia dejar SOLO TEST_RUNNER_CMD_RE. Se probo y rompio
  #      tres casos legitimos: esa constante cubre UNICAMENTE el runner propio
  #      del repo (`tests/run.sh`, Task 9.10) — pytest, vitest y compania viven
  #      en WORD_RE. Aplicarla tal cual borraba el credito de todos los runners
  #      normales. El agujero era real; la receta, no.
  #
  # LIMITE del lado estricto, declarado y ATADO por
  # caso_g2_echo_seguido_de_runner_no_acredita: `echo hola && pytest` tampoco
  # acredita. Distinguirlo exigiria parsear el shell, y este gate es advisory —
  # se elige perder un credito legitimo antes que regalar uno falso.
  if ! printf '%s' "$command_text" | head -n 1 | grep -Eiq "$ECHO_LEAD_RE" \
     && { printf '%s' "$command_text" | grep -Eiq "$TEST_RUNNER_WORD_RE" \
          || printf '%s' "$command_text" | grep -Eiq "$TEST_RUNNER_CMD_RE"; }; then
    if [ -z "$toolresult_err" ] \
       && ! printf '%s' "$INPUT" | grep -Eiq "$SAIKIT_DESPACHO_BG_RE" \
       && ! { printf '%s' "$combined" | grep -Eiq "$FAILURE_SIGNAL_RE_CI" \
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
  # Task 9.3 (C11): la frontera izquierda excluye ademas la comilla simple y
  # la doble — el feedback del gate y cualquier explicacion de su mecanica
  # citan las etiquetas como 'Understand:', y esa cita satisfacia las seis sin
  # recibo real. Limite declarado: una etiqueta legitima precedida por
  # apostrofo deja de contar (recuperable — el gate pide el recibo de nuevo);
  # y citar el TEMPLATE completo con sus saltos reales sigue contando, porque
  # es indistinguible de un recibo (advisory por diseno). A8 (prosa corrida)
  # intacto: el \n decodificado no es comilla.
  # 18.23: el ancla ^ de linea vuelve real lo que el contrato siempre afirmo:
  # la etiqueta tiene que EMPEZAR su linea (con vineta o negrita permitidas,
  # como antes). Hasta aca la frontera izquierda era el unico filtro y una
  # etiqueta pegada a mitad de parrafo contaba igual — un recibo entero en un
  # solo bloque daba por cumplidas las seis. La cita en prosa (C11,
  # 'Understand:' entre comillas) queda estructuralmente afuera sin la
  # frontera de comillas: una cita nunca empieza la linea. LIMITE DECLARADO:
  # la linea en blanco entre parrafos NO se parsea (los hosts colapsan los
  # espacios en blanco de forma distinta; exigirla seria fragil) — la regla
  # de parrafos se AFIRMA en el contrato y en el caso de forma, no se verifica.
  # 18.23 r1 (hallazgo ALTO del adversary, fixture 31, codex-cli 0.147.0): el
  # \n LITERAL (backslash + n, dos caracteres) tambien es frontera de linea,
  # porque es la forma de transporte real de codex — \\n doble en el JSON
  # crudo, y el decodificador de una capa lo deja plano. Sin esta alternancia
  # el recibo honesto de codex quedaba sin NINGUNA etiqueta a inicio de linea
  # y se bloqueaba entero. Alternancia en el matcher, NO pre-procesamiento:
  # el decodificador compartido queda intacto (lo exigio la review; ademas
  # esquiva el problema BSD/GNU de reemplazos con sed/awk). El recibo pegado
  # con ESPACIOS sigue bloqueando: no hay \n literal delante de las
  # etiquetas. RESIDUAL DECLARADO: un recibo citado con \n literales es
  # indistinguible de esa forma (misma postura advisory de la cita del
  # template). La vineta se ensancha a [-*+] (hallazgo MEDIO): asterisco y
  # plus cuentan igual que el guion; blockquote ('>'), vineta anidada y
  # vineta sin espacio ('-Label:') quedan fuera.
  printf '%s' "$text" | grep -Eiq "(^|\\\\n)[[:space:]]*([-*+][[:space:]]+)?(\*\*|__)?($label|$alt)(\*\*|__)?[[:space:]]*:"
}

build_gate_feedback() {
  missing="$1"
  next_cycle="$2"
  _gf="$(cat <<EOF
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

Required receipt shape (each receipt label opens its own paragraph, with a blank line between paragraphs; never glue several labels into one block. ADVERSARY:, ROLE FALLBACK: and VERIFIED BY SUBAGENT: get the same treatment. Each gate is one line whose label is followed by a COLON, inside the receipt block; a hyphen '-', asterisk '*' or plus '+' bullet, or markdown bold around the label is fine; a blockquote ('>'), a nested bullet and a bullet without a space ('-Label:') do not count, and replacing the colon with a dash is not; write them in plain language):
SUMMONAIKIT HARNESS RECEIPT
Understand: ...
Implement: ...
Verify: ...
Review: ...
Close: ...
Retro: ...
EOF
)"
  # 18.6, bloque 2 del contrato: mismo parrafo que harness_context (bloque 1),
  # SOLO cuando el estado del turno tiene autopilot=1 — el feedback de turnos
  # no-autopilot no cambia. Tocar un bloque solo dejaria el gate afirmando
  # cosas distintas segun la rama que emita. Excepcion grok: emit_gate_failure
  # le adosa harness_context entero (7.4), que ya trae el parrafo; agregarlo
  # aca tambien lo duplicaba en el mismo reason (medido: 2 en grok, 1 en
  # claude). Atado por caso_g1_autopilot_parrafo_una_vez_en_grok.
  if [ "$TARGET" != "grok" ] && [ "$(read_state_value autopilot)" = "1" ]; then
    _gf="$(printf '%s\n\n%s' "$_gf" "$(autopilot_parrafo)")"
  fi
  printf '%s\n' "$_gf"
}

emit_gate_failure() {
  feedback="$1"
  if [ "$TARGET" = "cursor" ]; then
    emit_cursor_json "followup_message" "$feedback"
    exit 0
  fi

  escaped="$(json_escape "$feedback")"
  # Task 7.4 (re-planificacion del armado, medido 7.2): additionalContext es
  # IGNORADO por Grok en las 4 formas medidas, y UPS no esta en
  # blockingEvents — el unico canal medido que llega al modelo es el REASON
  # del decision:block (7.2: el modelo lo cito textual en el turno block0).
  # Asi que en grok el contrato viaja ADOSADO a cada bloqueo del Stop: llega
  # al primer Stop bloqueado en vez de al armado (declarado como limite), y
  # llega completo cada vez (idempotente, el modelo relee lo que falto).
  if [ "$TARGET" = "grok" ]; then
    feedback="$feedback

$(harness_context)"
    escaped="$(json_escape "$feedback")"
  fi
  printf '{"decision":"block","reason":"%s"}\n' "$escaped"
  printf '%s\n' "$feedback" >&2
  # Task 6.4 (medido 6.2, 12 turnos headless): Codex DESCARTA el stdout del
  # hook cuando el exit no es 0 — el mismo JSON con exit 2 no bloquea (1 Stop,
  # 0 hook_prompt) y con exit 0 bloquea (4 Stops, 3 hook_prompt). El bloqueo
  # de codex viaja con exit 0; claude/zcode conservan el exit 2 medido en 5.2.
  # Task 7.4 (medido 7.2): grok igual que codex — PowerShell devuelve el
  # exit 2 como 1 y Grok hace fail-open en Stop (exit 2 = IGNORADA); el JSON
  # con exit 0 = ACEPTADA y mueve el Stop de forma fiable.
  if [ "$TARGET" = "codex" ] || [ "$TARGET" = "grok" ]; then
    exit 0    # saikit-6.4-codex-block (mutacion: exit 0 -> exit 2)
  fi
  exit 2
}

emit_budget_exhausted() {
  missing="$1"
  message="SUMMONAIKIT HARNESS REVISION BUDGET EXHAUSTED

The harness gate failed after 2 structured revision cycles.

Still missing:
$missing

Stop now, report the failed gates, and ask the user before another retry."
  # 18.6: tercer emisor de feedback del Stop (hallazgo adversary #1, medido):
  # sin esto, agotar el presupuesto era la unica salida del gate que perdia las
  # reglas de merge del turno autopilot. El flag llega por $2 porque los
  # callers borran el estado (A4-c4) ANTES de llamar; caida a leerlo si viene
  # solo $1.
  if [ "${2:-$(read_state_value autopilot)}" = "1" ]; then
    message="$message

$(autopilot_parrafo)"
  fi

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
  # Phase 15: dsh consume {"decision":"block","reason":"..."} del stdout (el
  # adaptador @summonaikit/dsh-gate parsea ese JSON, no continue:false/stopReason).
  # Sin esto el presupuesto agotado cerraria silenciosamente en dsh.
  if [ "$TARGET" = "dsh" ]; then
    printf '{"decision":"block","reason":"%s"}\n' "$escaped"
    printf '%s\n' "$message" >&2
    exit 0
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

  # Task 7.3 (D6): Grok dispara DOS Stops por turno headless (medido 7.1, 5/5
  # pares): el de turno trae reason="end_turn" con promptId y
  # lastAssistantMessage; el de CIERRE (el proceso que sale) trae
  # reason="shutdown" sin ninguno de los dos. 7.2 lo midio en vivo: el Stop de
  # cierre RECIBE la decision y la ignora, sin segundo ciclo — tratarlo como
  # Stop de turno contaria ciclo, limpiaria estado ajeno o crearia estado en
  # un proceso que ya se va. Sale inmediato, sin tocar NADA. Acotado a
  # HOST=grok a proposito: un Stop de Claude/zcode/Codex no trae reason, y
  # exigirlo globalmente apagaria el gate en todos los demas hosts. `reason`
  # VACIO no exime (Core Rule 2: no observado != no-end_turn) — sigue el
  # camino normal del gate. channel_closed sigue unknown (no observado).
  if [ "$HOST" = "grok" ]; then
    stop_reason="$(json_top_level_string reason)"
    if [ -n "$stop_reason" ] && [ "$stop_reason" != "end_turn" ]; then
      emit_allow
    fi
  fi

  # Task 8.1 (C3, misma clase): transcript_path con el lector top-level — el
  # greedy podia tomar una ruta de otra parte del payload. La contencion de A6
  # (transcript_en_perfil) sigue intacta detras; los escapes quedan crudos como
  # siempre (cd+pwd los normaliza, ver :1084).
  transcript_path="$(json_top_level_string transcript_path)"
  # Task 7.3 (D4): alias camel de Grok (transcriptPath, medido 7.1 — cae en
  # ~/.grok/sessions/, o sea DENTRO del perfil: la contencion A6 contiene).
  # Fallback, no reemplazo: el snake sigue ganando.
  [ -n "$transcript_path" ] || transcript_path="$(json_top_level_string transcriptPath)"
  tail_text=""
  # Task 11.4: la observabilidad del canal transcript se decide ACA, una sola
  # vez — observado = ruta presente + legible + dentro del perfil (A6). El
  # flag lo consume el chequeo de unknown honesto de mas abajo; no se vuelve
  # a llamar a transcript_en_perfil para no duplicar su diagnostico por stderr.
  transcript_observed=0
  if [ -n "$transcript_path" ] && [ -r "$transcript_path" ]; then
    if transcript_en_perfil "$transcript_path"; then
      transcript_observed=1
      tail_text="$(tail -n 160 "$transcript_path" 2>/dev/null || true)"
    fi
  fi
  # Task 3.2: $text se arma con SOLO texto del asistente, decodificado, de los
  # dos canales (last_assistant_message + content[].text role:assistant del tail).
  # Antes era $INPUT + tail crudo, que incluia tool_result y los \n escapados del
  # JSONL — raiz de A2 (exige de menos) y A8 (exige de mas). El tail -n 160 se
  # conserva como recorte: leer el transcript entero agrandaria el hueco (un
  # recibo de hace 5 turnos satisfaria el gate) y es caro en Windows. Ver
  # docs/task-3.2-plan.md CORRECCION 2.
  text="$(last_assistant_text)
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
  # Task 7.3: last_assistant_text = el walker con precedencia snake/camel.
  text_hatch="$(last_assistant_text)"
  if [ -z "$text_hatch" ]; then text_hatch="$text"; fi

  # >>> SAIKIT-ADVERSARY-LOCK v1 (Task 13.4) >>>
  # Chequeos de violacion y secreto ANTES de las escotillas tempranas (A2 del
  # review de 13.1): PAUSED y DELEGATED hacen emit_allow sin senal, y sin este
  # orden un lead cuyo adversary escribio fuera del dir cerraba el turno con
  # una frase de pausa — la unica entrada fail-closed del diseno, eludida por
  # una escotilla escrita para otro proposito. Con adv_early activo se bloquea
  # aca mismo y las escotillas de abajo quedan inalcanzables (el bloque sale
  # con exit; no hace falta condicionarlas). Sin adversary ni violacion en el
  # estado, este bloque es no-op y el Stop sigue byte-identico al de hoy.
  adv_early_missing=""
  adv_st_violation="$(read_state_value adv_violation)"
  adv_st_agents="$(read_state_value agents_seen)"
  adv_adv_presente=0
  case ",$adv_st_agents," in
    *,adversary,*) adv_adv_presente=1 ;;
  esac
  if [ "$adv_st_violation" = "1" ]; then
    # qwen #1 / codex #2 (r2 PR #65): el remedio prometido tiene que ser el
    # que FUNCIONA. El flag persiste a proposito toda la sesion (limpiarlo sin
    # verificar el revert seria perdonar la escritura; verificarlo seria git
    # en el Stop) — la salida real es revertir y RE-ARMAR (-saikit) en un
    # turno nuevo, cuyo armado reinicia el estado; o agotar el presupuesto.
    # qwen #7: los paths viajan REDACTADOS al feedback, como en la linea de log.
    adv_early_missing="- The adversary subagent wrote outside .saikit/findings/ (registered: $(redact_secrets "$(read_state_value adv_violation_paths)")). No receipt label satisfies this entry: inspect and revert the unauthorized write (e.g. git restore <file>, or delete the created file), then re-arm with -saikit in a fresh turn — re-closing THIS turn stays blocked on purpose (the flag persists for the session and the block never verifies the revert; a new armed turn resets it).\n"
  elif [ "$adv_adv_presente" = "1" ]; then
    adv_early_missing="$(adv_chequear_secretos)"
  fi
  if [ -n "$adv_early_missing" ]; then
    adv_cycle="$(read_state_value cycle)"
    case "$adv_cycle" in ''|*[!0-9]*) adv_cycle=0 ;; esac
    if [ "$adv_cycle" -ge "$MAX_CYCLES" ] 2>/dev/null; then
      _ap_budget="$(read_state_value autopilot)"  # 18.6: antes del rm (A4-c4)
      rm -f "$STATE_PATH" "$LOG_PATH" "$RN_ORDER_PATH" 2>/dev/null || true
      podar_dir_sesion
      emit_budget_exhausted "$adv_early_missing" "$_ap_budget"
    fi
    adv_reescribir_estado "$(read_state_value adv_epoch)" "$(read_state_value adv_paths)" "$(read_state_value adv_violation)" "$(read_state_value adv_violation_paths)" "$((adv_cycle + 1))"
    feedback="$(build_gate_feedback "$adv_early_missing" "$((adv_cycle + 1))")"
    emit_gate_failure "$feedback"
  fi
  # <<< SAIKIT-ADVERSARY-LOCK v1 <<<

  # A clarifying pause is a valid way to end the turn: the agent asked the
  # user a question and is waiting for the answer. Do not demand a receipt or
  # the implement -> verify -> review sequence in that case. Task 11.2: the
  # hatch now ALSO requires that no receipt is present -- same second clause
  # DELEGATED got from the cross-review (cycle 1). Field datapoint (Kimi,
  # 2026-08-16): an agent that finished the work wrote the full receipt AND
  # added the PAUSED line to ask for a decision; the hatch fired before the
  # receipt was evaluated, so a complete receipt skipped validation and left
  # live state on disk, and a broken one + PAUSED closed silently. With the
  # receipt present the turn falls through to the normal gate: complete =>
  # clean close (state cleared), broken => missing-label feedback. Declared
  # limit (same accepted trade-off as DELEGATED's): the marker match is an
  # unanchored substring, so a legitimate pause that QUOTES the phrase
  # "SUMMONAIKIT HARNESS RECEIPT" without a real receipt falls to the normal
  # gate and may get blocked.
  if printf '%s' "$text_hatch" | grep -Eiq 'SUMMONAIKIT HARNESS PAUSED' \
     && ! printf '%s' "$text_hatch" | grep -Eiq "$RECEIPT_MARKER_RE"; then
    emit_allow
  fi

  # Sibling escape hatch (arreglo 1): the agent delegated to a subagent that is
  # still running (implementer/verifier/reviewer subagents measured at 30-100
  # min) and is correctly waiting on it, not failing. Unlike PAUSED above, this
  # one REQUIRES the role to be named -- one of the three canonical roles --
  # so it stays auditable instead of a blanket skip-the-gate (same discipline
  # ROLE FALLBACK already uses, see D4/Task 6.3 below). A DELEGATED line that
  # names no role does not match and falls through to the normal receipt gate.
  # (Task 11.2 note: since the PAUSED hatch gained the same !receipt clause,
  # "unlike PAUSED" no longer holds for the receipt half -- both hatches now
  # require the receipt to be absent. It still holds for the role half: only
  # DELEGATED names a role.)
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
  # Task 13.5 (D6): la alternancia gana a adversary — un lead que delega
  # adversary en vivo y escribe la forma exacta caia al gate normal y quemaba
  # un ciclo (hallazgo alto del cross-review del plan). Mismo trade-off
  # declarado de siempre: substring sin anclar sobre texto sin recibo.
  if printf '%s' "$text_hatch" | grep -Eiq 'SUMMONAIKIT HARNESS DELEGATED.*awaiting[[:space:]]+(implementer|verifier|reviewer|adversary)' \
     && ! printf '%s' "$text_hatch" | grep -Eiq "$RECEIPT_MARKER_RE"; then
    emit_allow
  fi

  # Task 11.4 (datapoint post-11.3, host zcode 2026-08-16) — unknown honesto.
  # El gate juzga el recibo por DOS canales de texto: last_assistant_message
  # (o su alias camel) en el payload y el tail del transcript. Si AMBOS estan
  # no observados — campo AUSENTE del payload y transcript ausente, ilegible o
  # fuera del perfil (A6) — exigir el recibo afirma AUSENCIA desde la
  # NO-OBSERVACION: Core Rule 2 violada adentro del propio stop_gate, y cada
  # bloqueo consume ciclo (un turno completo y honesto agoto los 2 ciclos en
  # zcode pidiendo evidencia que el gate por diseño no podia ver; el ROLE
  # FALLBACK declarado en el recibo tampoco salva, porque el recibo viaja por
  # el canal ciego). Postura: fail-open declarado — diagnostico fuerte por
  # stderr y log, exit 0 SIN consumir ciclo, estado de la sesion limpio
  # (mismo desenlace que el presupuesto agotado, A4).
  # Distincion clave: campo PRESENTE sin recibo = ausencia OBSERVADA => el gate
  # sigue bloqueando como siempre (claude/codex medidos 1.4/6.2 no pierden
  # dientes). La deteccion de presencia es la misma subcadena que usa
  # assistant_text_payload: una clave anidada (p.ej. en tool_input) cuenta como
  # observado — no dispara el unknown, o sea queda del lado que sigue
  # exigiendo. NO toca A6: el camino 1 (extender la contencion al tmpdir de
  # zcode) queda gateado por la medicion de la Task 11.6.
  canal_payload_observed=0
  case "$INPUT" in
    *"\"last_assistant_message\""*|*"\"lastAssistantMessage\""*) canal_payload_observed=1 ;;
  esac
  # (el chequeo del unknown honesto vive mas abajo, tras leer cycle del estado)

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

  # Task 11.4 (datapoint post-11.3, host zcode 2026-08-16) — unknown honesto.
  # El gate juzga el recibo por DOS canales de texto: last_assistant_message
  # (o su alias camel) en el payload y el tail del transcript. Si AMBOS estan
  # no observados — campo AUSENTE del payload y transcript ausente, ilegible o
  # fuera del perfil (A6) — exigir el recibo afirma AUSENCIA desde la
  # NO-OBSERVACION: Core Rule 2 violada adentro del propio stop_gate, y cada
  # bloqueo consume ciclo (un turno completo y honesto agoto los 2 ciclos en
  # zcode pidiendo evidencia que el gate por diseño no podia ver; el ROLE
  # FALLBACK declarado en el recibo tampoco salva, porque el recibo viaja por
  # el canal ciego). Postura: fail-open declarado — diagnostico fuerte por
  # stderr y log, exit 0 SIN consumir ciclo, estado de la sesion limpio
  # (mismo desenlace que el presupuesto agotado, A4).
  # Distincion clave: campo PRESENTE sin recibo = ausencia OBSERVADA => el gate
  # sigue bloqueando como siempre (claude/codex medidos 1.4/6.2 no pierden
  # dientes). La deteccion de presencia es la misma subcadena que usa
  # assistant_text_payload: una clave anidada (p.ej. en tool_input) cuenta como
  # observado — no dispara el unknown, o sea queda del lado que sigue
  # exigiendo. NO toca A6: el camino 1 (extender la contencion al tmpdir de
  # zcode) queda gateado por la medicion de la Task 11.6.
  # NO se loguea a $LOG_PATH a proposito (review 11.4, hallazgo medio): el
  # cierre borra el log de la sesion una linea mas abajo, asi que un append
  # seria evidencia efimera que no hace lo que declara. El presupuesto agotado
  # (A4) tampoco loguea; el diagnostico vivible es el stderr.
  if [ "$canal_payload_observed" -eq 0 ] && [ "$transcript_observed" -eq 0 ]; then
    printf 'summonaikit-harness: unknown honesto — ningun canal de texto observable (last_assistant_message/lastAssistantMessage ausente del payload y transcript ausente, ilegible o fuera del perfil); no se juzga el recibo desde la no-observacion (Core Rule 2). Cierro sin consumir ciclo de revision y limpio el estado de esta sesion.\n' >&2
    rm -f "$STATE_PATH" "$LOG_PATH" "$RN_ORDER_PATH" 2>/dev/null || true
    podar_dir_sesion
    emit_allow
  fi

  missing=""
  if ! printf '%s' "$text" | grep -Eiq 'SUMMONAIKIT HARNESS RECEIPT'; then
    missing="$missing- Missing SUMMONAIKIT HARNESS RECEIPT.\n"
  fi
  if ! has_receipt_label "Understand" "Capito" "$text"; then
    missing="$missing- Missing Understand gate summary (each receipt label opens its own paragraph: add a line beginning 'Understand:' inside the SUMMONAIKIT HARNESS RECEIPT block, restating the request in plain words). If you instead need to ask the user first, end the turn with the line 'SUMMONAIKIT HARNESS PAUSED - awaiting your answer'.\n"
  fi
  if ! has_receipt_label "Implement" "Implementazione" "$text"; then
    missing="$missing- Missing Implement gate summary (each receipt label opens its own paragraph: add a line beginning 'Implement:' inside the SUMMONAIKIT HARNESS RECEIPT block).\n"
  fi
  if ! has_receipt_label "Verify" "Verifica" "$text"; then
    missing="$missing- Missing Verify gate summary (each receipt label opens its own paragraph: add a line beginning 'Verify:' inside the SUMMONAIKIT HARNESS RECEIPT block).\n"
  fi
  if ! has_receipt_label "Review" "Revisione" "$text"; then
    missing="$missing- Missing Review gate summary (each receipt label opens its own paragraph: add a line beginning 'Review:' inside the SUMMONAIKIT HARNESS RECEIPT block).\n"
  fi
  if ! has_receipt_label "Close" "Chiusura" "$text"; then
    missing="$missing- Missing Close gate summary (each receipt label opens its own paragraph: add a line beginning 'Close:' inside the SUMMONAIKIT HARNESS RECEIPT block).\n"
  fi
  if ! has_receipt_label "Retro" "Retrospettiva" "$text"; then
    missing="$missing- Missing Retro gate summary (each receipt label opens its own paragraph: add a line beginning 'Retro:' inside the SUMMONAIKIT HARNESS RECEIPT block).\n"
  fi
  # Task 13.5 (D4/B1): la linea ADVERSARY del recibo se exige cuando ESTE turno
  # corrio un adversary (,adversary, en agents_seen), en CUALQUIER lane — los
  # labels del recibo ya se exigen en fast y este no es excepcion. Sin adversary
  # en agents_seen este bloque no corre y el recibo sigue exactamente igual
  # (anti-regresion del costo, D1). Label-only: el gate NUNCA valida N contra
  # el JSON del artefacto (validarlo exigiria parsear en el Stop un archivo que
  # otro modelo reescribio — TOCTOU declarado de D2). ROLE FALLBACK: ADVERSARY
  # sustituye la linea para el despacho que acredito agents_seen pero murio sin
  # reportar — misma disciplina substring sin anclar de los otros tres roles.
  case ",$agents_seen," in
    *,adversary,*)
      if ! has_receipt_label "ADVERSARY" "ADVERSARIO" "$text" \
         && ! printf '%s' "$text" | grep -Eiq 'ROLE FALLBACK: *ADVERSARY'; then
        missing="$missing- Missing ADVERSARY line (this turn ran an adversary subagent: each receipt label opens its own paragraph: add a line beginning 'ADVERSARY:' inside the SUMMONAIKIT HARNESS RECEIPT block with the findings count and the highest severity — presence only, the gate never checks the numbers. If the adversary was dispatched but died without reporting, declare ROLE FALLBACK: ADVERSARY (reason) instead).\n"
      fi
      ;;
  esac
  # VERIFY_SKIP_RE: EN+IT historicos + ES natural. Vivo 2026-08-13: zcode
  # escribio "No corri los candados" y el gate lo rechazo porque solo
  # aceptaba skipped/not run. "se corrio la bateria" NO matchea (falta "no ").
  # Task 9.10 r2: el runner bash propio tambien se acepta aqui via
  # TEST_RUNNER_CMD_RE — grep ancla ^ por LINEA, asi que en prosa solo cuenta
  # una linea que ESTEME en posicion de comando; el credito real del carril
  # run.sh vive en el evento (arriba), este es el fallback de prosa.
  # Task 14.2 — via ADICIONAL de credito: label VERIFIED BY SUBAGENT en hosts con
  # canal interno ciego ($HOST=zcode). Las 5 condiciones del contrato (14.1 §3):
  # prefijo literal + comando+resultado (§4.3) + HOST ciego (sobre $HOST, JAMAS
  # $TARGET: en zcode el fallback 5.4 deja TARGET=claude) + verifier en
  # agents_seen + verified!=1 (la condicion de este if). Cuando el label esta
  # PRESENTE, la evidencia la juzga SOLO el predicado §4.3 (con el veto de fallo),
  # NO el fallback de prosa/runner — asi un label con fallo no acredita por la
  # via laxa de prosa (A11) y el label queda a la par del raíl de evento. Sin
  # label, comportamiento identico al de antes.
  # Task 14.2 / grok r1 #1: se juzga sobre $text_hatch (el texto del turno
  # ACTUAL, last_assistant_message) NO sobre $text (que concatena el tail de 160
  # lineas del transcript con turnos ANTERIORES). Un 'VERIFIED BY SUBAGENT:' que
  # un turno previo dejo en el tail NO debe encender la via exclusiva del label
  # ni servir su span para acreditar el turno nuevo — la misma clase que las
  # escotillas PAUSED/DELEGATED ya cierran con text_hatch (Task 8.2).
  if [ "$verified" != "1" ] && ! saikit_verif_evidence_ok "$text_hatch"; then
    # 18.18 — cuando el label estuvo PRESENTE y no acredito, saikit_verif_motivo
    # (seteado por saikit_verif_subagente_credita) nombra la condicion incumplida
    # en vez del reclamo generico: el lead ve QUE falto (verifier, fallo declarado,
    # resultado fuera del span, comando fuera del vocabulario) y no solo que falto.
    # Vacio = el label no fue el juez este turno: mensaje generico intacto.
    if [ -n "${saikit_verif_motivo:-}" ]; then
      missing="$missing- Missing verification evidence: ${saikit_verif_motivo}.\n"
    else
      missing="$missing- Missing verification evidence or explicit skipped-check reason (on a host with a blind channel, a \`VERIFIED BY SUBAGENT: <command> <result>\` on one line counts; otherwise declare an explicit skipped-check reason).\n"
    fi
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
  # Task 6.4 (D3): la ceremonia acepta codex. 6.1 midio que el rol LLEGA en
  # Codex (agent_type de primer nivel en los eventos internos, forma identica
  # a Claude post-3.7), asi que la rama se prende — la condicion del diseno
  # ("solo si 6.1 mide que el rol llega") esta cumplida y medida. cursor y
  # other siguen fuera; zcode entra por su fallback TARGET=claude (5.4).
  # Task 7.4 (D3): grok entra — 7.1 midio el rol por TRES canales
  # (SubagentStart.subagentType top-level, despacho spawn_subagent con
  # toolInput.subagent_type que SI emite post_tool_use, e internos del hijo
  # con subagentType), y el env map entrega TARGET=grok en los 37 dumps. La
  # condicion del diseño ("solo si 7.1 mide que el rol llega") cumplida por
  # partida doble. Los tres canales ya los leia la 7.3.
  # Phase 15 (D3): dsh entra — 15.1 midio el rol por tools/* (no ciego, D7), y el
  # adaptador @summonaikit/dsh-gate traduce la tool `subagent` a un PostToolUse
  # con subagent_type (D4), asi que la ceremonia se exige como en claude.
  case "$TARGET" in claude|codex|grok|dsh)
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
      *) if ! printf '%s' "$text" | grep -Eiq 'ROLE FALLBACK: *IMPLEMENTER'; then missing="$missing- Missing implementer subagent run (delegate the change via $TOOL_HINT, or declare ROLE FALLBACK: IMPLEMENTER (reason) in the receipt if that subagent is down after one retry).\n"; fi ;;
    esac
    case ",$agents_seen," in
      *",verifier,"*) ;;
      *) if ! printf '%s' "$text" | grep -Eiq 'ROLE FALLBACK: *VERIFIER'; then missing="$missing- Missing verifier subagent run (delegate verification via $TOOL_HINT, or declare ROLE FALLBACK: VERIFIER (reason) in the receipt if that subagent is down after one retry).\n"; fi ;;
    esac
    case ",$agents_seen," in
      *",reviewer,"*) ;;
      *) if ! printf '%s' "$text" | grep -Eiq 'ROLE FALLBACK: *REVIEWER'; then missing="$missing- Missing reviewer subagent run (delegate review via $TOOL_HINT, or declare ROLE FALLBACK: REVIEWER (reason) in the receipt if that subagent is down after one retry).\n"; fi ;;
    esac
    if printf '%s' "$agents_seen" | grep -q implementer && printf '%s' "$agents_seen" | grep -q verifier && printf '%s' "$agents_seen" | grep -q reviewer; then
      if ! printf '%s' "$agents_seen" | grep -Eq 'implementer.*verifier.*reviewer'; then
        missing="$missing- Subagents ran out of order; required sequence is implementer -> verifier -> reviewer.\n"
      fi
    fi
    # Task 13.5 (D4): con adversary en agents_seen, la secuencia exigida lo
    # incluye ENTRE verifier y reviewer. La regex de 3 roles de arriba ya
    # matcheaba con adversary en el medio — ESTA es la que exige su posicion:
    # rechaza adversary-antes-de-verifier y adversary-despues-de-reviewer. El
    # "adversary sin verifier previo" sin verifier en agents_seen lo atrapa la
    # rama missing-verifier de arriba; con verifier tardio, esta.
    if printf '%s' "$agents_seen" | grep -q implementer && printf '%s' "$agents_seen" | grep -q verifier && printf '%s' "$agents_seen" | grep -q adversary && printf '%s' "$agents_seen" | grep -q reviewer; then
      if ! printf '%s' "$agents_seen" | grep -Eq 'implementer.*verifier.*adversary.*reviewer'; then
        missing="$missing- Subagents ran out of order; required sequence is implementer -> verifier -> adversary -> reviewer.\n"
      fi
    fi
  ;;
  esac
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
  rn_pendiente_borrable=""
  if [ -n "$rn_check_last_code_edit" ] && [ -n "$rn_check_last_review" ] && [ "$rn_check_last_code_edit" -gt "$rn_check_last_review" ] 2>/dev/null; then
    rn_ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)"
    printf '%s review-notice: code was edited after the last reviewer subagent run (tool-name signal only -- an edit made via a shell command, e.g. sed/heredoc/git apply, is NOT detected by this check).\n' "$rn_ts" >> "$LOG_PATH" 2>/dev/null || true
    mkdir -p "$STATE_DIR" 2>/dev/null || true
    # Task 10.2: la coletilla ata el aviso a la disciplina de re-review dirigido
    # (el contrato de arriba ya la pide): re-review del delta, no ceremonia nueva.
    printf 'SAIKIT REVIEW NOTICE: in your previous turn, code was edited after the reviewer subagent last ran, and those edits were not reviewed. Re-review the new diff only; do not restart the ceremony.\n' > "$RN_PENDING_PATH" 2>/dev/null || true
    rn_notice_fired="1"
  elif [ -n "$rn_check_last_code_edit" ] || [ -n "$rn_check_last_review" ]; then
    # Task 9.8 (C14): el borde declarado es "el Stop de una sesion con
    # secuencia limpia PUEDE borrar el aviso" — y ese borde es el CIERRE
    # limpio, no cualquier Stop. Aca solo se ANOTA que la secuencia se observo
    # limpia; el rm vive abajo, dentro de [ -z "$missing" ], junto al del
    # RN_ORDER. Antes el rm corria aqui, en TODO Stop: uno que BLOQUEABA se
    # llevaba el aviso que una sesion hermana dejo para el proximo turno del
    # proyecto (RN_PENDING_PATH es per-proyecto a proposito).
    rn_pendiente_borrable=1
  fi
  # <<< SAIKIT-REVIEW-NOTICE v1 <<<
  if [ -z "$missing" ]; then
    # >>> SAIKIT-REVIEW-NOTICE v1 >>>
    rm -f "$RN_ORDER_PATH" 2>/dev/null || true
    # Task 9.8 (C14): el aviso pendiente desactualizado solo lo borra un
    # cierre LIMPIO cuya secuencia se observo limpia (el elif de arriba). Si
    # el aviso disparo en ESTE Stop (rama if), el flag no se seteo y el
    # pendiente queda para el turno siguiente, como siempre.
    if [ "$rn_pendiente_borrable" = "1" ]; then
      rm -f "$RN_PENDING_PATH" 2>/dev/null || true
    fi
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
    podar_dir_sesion   # Task 9.7 (C13): el dir tambien se va, no solo los archivos
    emit_allow
  fi

  if [ "$cycle" -ge "$MAX_CYCLES" ] 2>/dev/null; then
    # Presupuesto agotado limpia el estado de ESTA sesion (STATE_PATH/LOG_PATH/
    # RN_ORDER_PATH). RN_PENDING_PATH queda (per-project, ver comentario
    # REVIEW-NOTICE). Sin esto, cycle=MAX sobrevivia en disco y el turno seguia
    # cobrando recibo despues de declararse agotado (A4).
    _ap_budget="$(read_state_value autopilot)"  # 18.6: antes del rm (A4-c4)
    rm -f "$STATE_PATH" "$LOG_PATH" "$RN_ORDER_PATH" 2>/dev/null || true  # A4-c4 presupuesto
    podar_dir_sesion   # Task 9.7 (C13): el dir tambien se va, no solo los archivos
    emit_budget_exhausted "$missing" "$_ap_budget"
  fi

  next_cycle=$((cycle + 1))
  write_state "$task_hash" "$next_cycle" "$implemented" "$verified" "$agents_seen" "$lane" \
    "$(read_state_value adv_epoch)" "$(read_state_value adv_paths)" "$(read_state_value adv_violation)" "$(read_state_value adv_violation_paths)" \
    "$(read_state_value veredicto_sha256)" "$(read_state_value autopilot)"
  feedback="$(build_gate_feedback "$missing" "$next_cycle")"
  emit_gate_failure "$feedback"
}

# >>> SAIKIT-PRETOOL-MERGE v1 (Task 18.11 / D24) >>>
# Medicion citada: https://code.claude.com/docs/en/hooks
# PreToolUse niega con stdout JSON y exit 0 (exit != 0 = crash, puede
# fail-open). NO reusar {"decision":"block"} del Stop.
#
# Snippet para settings.json del operador (Claude; operator-owned —
# install-hook.sh NO escribe settings.json, igual que SessionStart / 10.6):
#   "PreToolUse": [
#     { "matcher": "Bash",
#       "hooks": [{ "type": "command",
#         "command": "SUMMONAIKIT_HOOK_TARGET=claude bash \"$HOME/.claude/hooks/summonaikit-harness.sh\"" }] }
#   ]
# NO fijar SUMMONAIKIT_HOOK_PHASE=tool: el env pisa el payload y este brazo
# no corre. PHASE unset (hook_event_name → pretool) o =pretool.
#
# Tabla de decision (inputs: tool_name, command_text, cwd):
#   no-Bash                         → pass (emit_allow, stdout vacio)
#   texto 'gh pr merge'             → deny  (siempre; tambien encadenado a hatch)
#   texto gh api … /merge           → deny
#   git push + dest master|main     → deny  (conjunto minimo D24)
#   token saikit-merge.sh           → hatch: hash == pin o deny (fail-closed)
#   resto                           → pass
# Los patrones a pelo van PRIMERO: un hatch pinneado no es permiso para
# `…; gh pr merge` / `&&` / orden invertido en el mismo command. Pin:
# tools/MANIFEST.sha256 (hermano del script resuelto) o SAIKIT_KIT_MANIFEST
# (solo ruta, no flag). Escapes del command quedan crudos (mismo limite
# que el Bash del adversary). Infra de un comando que NO es merge: fail-open.

emit_pretool_deny() {
  escaped="$(json_escape "$1")"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$escaped"
  exit 0
}

pretool_es_gh_pr_merge() { printf '%s' "$1" | grep -Fq 'gh pr merge'; }
pretool_es_gh_api_merge() { printf '%s' "$1" | grep -Eq 'gh[[:space:]]+api[^[:cntrl:]]*/merge'; }
pretool_es_git_push_protegida() {
  printf '%s' "$1" | grep -Eq 'git[[:space:]]+push' || return 1
  printf '%s' "$1" | grep -Eq '(^|[^[:alnum:]_-])(master|main)([^[:alnum:]_-]|$)'
}
pretool_es_hatch() { printf '%s' "$1" | grep -q 'saikit-merge\.sh'; }
pretool_token_hatch() {
  printf '%s' "$1" | grep -Eo '[^[:space:];|&<>]+saikit-merge\.sh' | head -n 1
}
pretool_pins_iguales() { [ "$1" = "$2" ]; }

pretool_hatch_verifica() {
  _pt_cmd="$1"
  _pt_cwd="$2"
  _pt_tok="$(pretool_token_hatch "$_pt_cmd")"
  [ -n "$_pt_tok" ] || return 1
  case "$_pt_tok" in
    /*|[A-Za-z]:*) _pt_path="$_pt_tok" ;;
    *)
      if [ -n "$_pt_cwd" ]; then
        _pt_path="$_pt_cwd/$_pt_tok"
      else
        _pt_path="$_pt_tok"
      fi
      ;;
  esac
  [ -f "$_pt_path" ] || return 1
  _pt_dir="$(cd "$(dirname "$_pt_path")" 2>/dev/null && pwd)" || return 1
  _pt_path="$_pt_dir/$(basename "$_pt_path")"
  if [ -n "${SAIKIT_KIT_MANIFEST:-}" ]; then
    _pt_pin="$SAIKIT_KIT_MANIFEST"
  else
    _pt_pin="$_pt_dir/MANIFEST.sha256"
  fi
  [ -f "$_pt_pin" ] || return 1
  _pt_esp="$(awk -F '\t' '/^#/ {next} $2=="saikit-merge.sh" {print $1; exit}' "$_pt_pin")"
  [ -n "$_pt_esp" ] || return 1
  _pt_real="$(sha256sum "$_pt_path" 2>/dev/null | cut -c1-64)"
  [ -n "$_pt_real" ] || return 1
  pretool_pins_iguales "$_pt_real" "$_pt_esp"
}

pretool_merge_guard() {
  _pt_tool="$(json_top_level_string tool_name)"
  [ -n "$_pt_tool" ] || _pt_tool="$(json_top_level_string toolName)"
  if [ "$_pt_tool" != "Bash" ]; then
    emit_allow
  fi
  _pt_cmd="$(json_tool_input_string command)"
  [ -n "$_pt_cmd" ] || _pt_cmd="$(json_tool_input_string command toolInput)"
  _pt_cwd="$(json_top_level_string cwd)"
  if pretool_es_gh_pr_merge "$_pt_cmd"; then
    emit_pretool_deny "merge denied: use tools/saikit-merge.sh (not gh pr merge)"
  fi
  if pretool_es_gh_api_merge "$_pt_cmd"; then
    emit_pretool_deny "merge denied: use tools/saikit-merge.sh (not gh api /merge)"
  fi
  if pretool_es_git_push_protegida "$_pt_cmd"; then
    emit_pretool_deny "merge denied: git push to master/main is blocked; use tools/saikit-merge.sh"
  fi
  if pretool_es_hatch "$_pt_cmd"; then
    if pretool_hatch_verifica "$_pt_cmd" "$_pt_cwd"; then
      emit_allow
    fi
    emit_pretool_deny "merge denied: saikit-merge.sh hash does not match the kit manifest"
  fi
  emit_allow
}
# <<< SAIKIT-PRETOOL-MERGE v1 <<<

if [ -z "$PHASE" ]; then
  # 5.4: un Stop realista de zcode trae SOLO hookEventName (camel), no
  # hook_event_name (5.1 midio ambos; 5.2 midio camel-only). Sin leer camel,
  # PHASE cae a "tool" y stop_gate no corre. json_top_level_string (no el sed
  # greedy de json_string_field) por el mismo motivo que session_id (3.4).
  event="$(json_top_level_string hook_event_name)"
  [ -n "$event" ] || event="$(json_top_level_string hookEventName)"
  # Task 7.3 (D4): literales snake de Grok (valor del evento, medido 7.1 en los
  # 37 payloads). Sin user_prompt_submit, un envelope Grok real caeria a
  # PHASE=tool y NUNCA armaria — es el defecto que esta task cierra aunque la
  # ceremonia (7.4) no se prenda. post_tool_use/subagent_start ya caen a tool,
  # que es lo que se quiere: record_tool_evidence anota roles y runners.
  # 18.11: PreToolUse NUNCA cae a tool — record_tool_evidence acreditaria el
  # comando como si ya hubiera corrido y despues emit_allow.
  case "$event" in
    UserPromptSubmit|beforeSubmitPrompt|user_prompt_submit) PHASE="prompt" ;;
    SessionStart|sessionStart|session_start) PHASE="session" ;;
    Stop|stop) PHASE="stop" ;;
    PreToolUse|preToolUse|pre_tool_use) PHASE="pretool" ;;
    *) PHASE="tool" ;;
  esac
fi

case "$PHASE" in
  prompt|session) start_harness ;;
  tool) record_tool_evidence ;;
  stop|verify) stop_gate ;;
  pretool) pretool_merge_guard ;;
  *) emit_allow ;;
esac
