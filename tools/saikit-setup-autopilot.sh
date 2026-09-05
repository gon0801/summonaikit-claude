#!/usr/bin/env bash
# tools/saikit-setup-autopilot.sh - Task 18.7 (D15 + D20): asistente que crea
# .saikit/autopilot.json con 5 preguntas en espanol.
#
# QUE HACE. Pregunta (una por una, en espanol) y escribe la config que
# tools/saikit-merge.sh lee SOLO de origin/<rama>:
#
#   1. Mergear solo con tu si? (si/no) => merge
#   2. Mergear a <rama> publica la app? (si-publica/no/no-se) =>
#      merge_despliega ("nadie contesto" es unknown, no false)
#   3. URL https para checar que la app sigue viva? (vacio = ninguna) =>
#      salud_url (null si no hay)
#   4. Sin prueba de la app, mergeo solo? (si/no) => sin_verify_app
#   5. Te aviso por Telegram? (si/no) => telegram
#
# Defaults no preguntados: rama=master, revert_si_rojo=true (esquema 4.2 del
# plan; bajo la 18.5 reducida ese campo queda inerte: no hay revert
# automatico que lo consuma, solo el aviso con el comando listo).
#
# Cada respuesta tambien llega por flag (para tests y agentes); lo que falta
# se pregunta si stdin es terminal, y si no, toma el default seguro.
#
# LOCK (D20). Un PR a la vez por repo: el lock vive en
# $(git rev-parse --git-common-dir)/saikit-autopilot.lock, COMPARTIDO entre
# worktrees. Adquisicion atomica por mkdir (misma forma que
# tools/saikit-decision.sh:278-281); el dir guarda pid/host/started_at/pr.
# El trap EXIT libera SOLO el lock propio (compara el pid). Un lock ajeno se
# REPORTA y BLOQUEA (exit 3) - NUNCA se borra solo, ni con pid muerto ni
# viejo: solo --liberar-lock explicito lo quita.
#
# ADEMAS asegura idempotente .saikit/veredictos/.gitignore (una linea '*'):
# el hook lo crea al sellar, pero en un clon fresco con setup corrido y sin
# veredicto aun no existiria. El .gitignore raiz NO lo menciona a proposito:
# una sola fuente (medido: git check-ignore ya ignora los veredictos).
#
# USO:
#   tools/saikit-setup-autopilot.sh [--merge si|no] [--despliega publica|no|no-se]
#     [--salud-url <url|->] [--sin-verify-app si|no] [--telegram si|no]
#     [--rama <nombre>] [--pr <n>] [--ci-minimo si|no] [--liberar-lock]
#
# Tras escribir el JSON, si no hay workflows, ofrece un CI minimo
# (tools/saikit-ci-minimo.sh --ofrecer). No es la pregunta 6/6 del JSON.
#
# Exit: 0 ok; 2 uso o validacion; 3 lock ajeno (reporta y bloquea).
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib/veredicto_contract.sh"   # saikit_json_valido (sin jq)

# Gancho SOLO de test: dormir N segundos con el lock tomado, para que un caso
# de contencion orqueste la carrera con determinismo (precedente: el knee de
# la 17.8 en saikit-decision.sh). Sin la variable es 0: PRODUCCION INTACTA.
SOSTENER="${SAIKIT_SETUP_SOSTENER_SEG:-0}"

merge_flag=""; despliega_flag=""; salud_flag="__sin_dato__"; sve_flag=""
telegram_flag=""; rama_flag=""; pr_flag=""; ci_minimo_flag=""; liberar=0

# Defaults seguros cuando no hay terminal que pregunte.
merge_default="no"; despliega_default="no-se"; rama_default="master"
sve_default="no"; telegram_default="no"

uso() { sed -n '2,44p' "$0"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --merge|--despliega|--salud-url|--sin-verify-app|--telegram|--rama|--pr|--ci-minimo)
      # El bug de la Task 0.4, que este repo ya pago dos veces (decision.sh y
      # el cross-review de esta fila): `shift 2` con un solo argumento no
      # consume nada y el while gira para siempre (rc=124 por timeout). Un
      # flag con valor EXIGE el valor.
      if [ $# -lt 2 ]; then
        printf 'saikit-setup-autopilot: %s exige un valor\n' "$1" >&2; exit 2
      fi
      case "$1" in
        --merge)          merge_flag="$2" ;;
        --despliega)      despliega_flag="$2" ;;
        --salud-url)      salud_flag="$2" ;;
        --sin-verify-app) sve_flag="$2" ;;
        --telegram)       telegram_flag="$2" ;;
        --rama)           rama_flag="$2" ;;
        --pr)             pr_flag="$2" ;;
        --ci-minimo)      ci_minimo_flag="$2" ;;
      esac
      shift 2 ;;
    --liberar-lock)   liberar=1; shift ;;
    -h|--help)        uso; exit 0 ;;
    *) printf 'saikit-setup-autopilot: opcion desconocida: %s\n' "$1" >&2; uso >&2; exit 2 ;;
  esac
done

# Repo y lock ANTES de todo (hasta --liberar-lock los necesita).
INVOC="$(pwd -P 2>/dev/null)" \
  || { printf 'saikit-setup-autopilot: no se pudo resolver el cwd\n' >&2; exit 2; }
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" \
  || { printf 'saikit-setup-autopilot: el cwd no es un repo git\n' >&2; exit 2; }
COMMON="$(git rev-parse --git-common-dir 2>/dev/null)" \
  || { printf 'saikit-setup-autopilot: no se pudo resolver el git-common-dir\n' >&2; exit 2; }
# El common-dir relativo lo es AL CWD DE INVOCACION (medido: `../.git` desde
# un subdir; cross-review kimi): resolverlo contra ROOT apunta fuera del repo
# y el script reportaba un falso "LOCK ocupado" en /saikit-autopilot.lock.
case "$COMMON" in
  /*) ;;
  *) COMMON="$(cd "$INVOC" && cd "$COMMON" && pwd -P)" \
    || { printf 'saikit-setup-autopilot: no se pudo resolver %s desde %s\n' "$COMMON" "$INVOC" >&2; exit 2; } ;;
esac
LOCK_DIR="$COMMON/saikit-autopilot.lock"

mostrar_lock() {  # reporta el contenido del lock ajeno, campo por campo
  printf '  lock: %s\n' "$LOCK_DIR"
  printf '    pid: %s\n' "$(cat "$LOCK_DIR/pid" 2>/dev/null || printf '(sin pid)')"
  printf '    host: %s\n' "$(cat "$LOCK_DIR/host" 2>/dev/null || printf '(sin host)')"
  printf '    inicio: %s\n' "$(cat "$LOCK_DIR/started_at" 2>/dev/null || printf '(sin inicio)')"
  printf '    pr: %s\n' "$(cat "$LOCK_DIR/pr" 2>/dev/null || printf '(sin pr)')"
}

if [ "$liberar" -eq 1 ]; then
  if [ ! -d "$LOCK_DIR" ]; then
    printf 'saikit-setup-autopilot: sin lock: nada que liberar (%s no existe)\n' "$LOCK_DIR"
    exit 0
  fi
  printf 'saikit-setup-autopilot: lock encontrado, se libera:\n'
  mostrar_lock
  rm -f "$LOCK_DIR"/pid "$LOCK_DIR"/host "$LOCK_DIR"/started_at "$LOCK_DIR"/pr 2>/dev/null
  rmdir "$LOCK_DIR" 2>/dev/null \
    || { printf 'saikit-setup-autopilot: no se pudo quitar %s\n' "$LOCK_DIR" >&2; exit 2; }
  printf 'saikit-setup-autopilot: lock liberado\n'
  exit 0
fi

# ------------------------------------------------------------- lock: tomar
# mkdir es atomico: si ya existe, otro setup lo tiene (o lo dejo). Se REPORTA
# y se BLOQUEA con exit 3. NUNCA se borra solo - ni con pid muerto ni viejo:
# un proceso igual pudo vivir en otra maquina (trampa de la fila).
candado_propio=0
liberar_propio() {
  if [ "$candado_propio" -ne 1 ]; then return 0; fi
  if [ "$(cat "$LOCK_DIR/pid" 2>/dev/null || true)" = "$$" ]; then
    rm -f "$LOCK_DIR"/pid "$LOCK_DIR"/host "$LOCK_DIR"/started_at "$LOCK_DIR"/pr 2>/dev/null
    rmdir "$LOCK_DIR" 2>/dev/null || true
  fi
  candado_propio=0
}
if mkdir "$LOCK_DIR" 2>/dev/null; then
  printf '%s' "$$" > "$LOCK_DIR/pid" \
    || { rmdir "$LOCK_DIR" 2>/dev/null; printf 'saikit-setup-autopilot: no se pudo escribir el lock\n' >&2; exit 2; }
  printf '%s' "$(hostname 2>/dev/null || printf '?')" > "$LOCK_DIR/pid.host.tmp" 2>/dev/null && mv "$LOCK_DIR/pid.host.tmp" "$LOCK_DIR/host" 2>/dev/null || true
  printf '%s' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || printf '?')" > "$LOCK_DIR/started_at" 2>/dev/null || true
  printf '%s' "${pr_flag:-}" > "$LOCK_DIR/pr" 2>/dev/null || true
  candado_propio=1
  trap 'liberar_propio' EXIT
else
  # NUNCA se borra solo
  printf 'saikit-setup-autopilot: LOCK ocupado, no se sigue (%s):\n' "$LOCK_DIR" >&2
  mostrar_lock >&2
  printf '  no se borra solo: si el dueno murio, liberalo explicito con:\n' >&2
  printf '    tools/saikit-setup-autopilot.sh --liberar-lock\n' >&2
  exit 3
fi

# Gancho de test (ver cabecera): sostener el lock para la contencion.
if [ "$SOSTENER" -gt 0 ] 2>/dev/null; then sleep "$SOSTENER"; fi

# ------------------------------------------------------------- preguntas
preguntar() {  # $1=texto $2=default - pregunta solo con terminal; si no, default
  local texto="$1" def="$2" resp=""
  if [ -t 0 ]; then
    printf '%s [%s]: ' "$texto" "$def" >&2
    IFS= read -r resp || resp=""
    [ -n "$resp" ] || resp="$def"
    printf '%s' "$resp"
  else
    printf '%s' "$def"
  fi
}

normalizar_si_no() {  # $1=valor $2=nombre - sale 2 si no es si/no
  case "$1" in
    si|SI|Si|s|S) printf 'true' ;;
    no|NO|No|n|N|"") printf 'false' ;;
    *) printf 'saikit-setup-autopilot: %s exige si/no (llego: %s)\n' "$2" "$1" >&2; return 1 ;;
  esac
}

merge_resp="${merge_flag:-}"
[ -n "$merge_resp" ] || merge_resp="$(preguntar '1/5 Mergear solo con tu si explicito? (si/no)' "$merge_default")"
merge_json="$(normalizar_si_no "$merge_resp" --merge)" || exit 2

despliega_resp="${despliega_flag:-}"
[ -n "$despliega_resp" ] || despliega_resp="$(preguntar '2/5 Mergear a la rama publica la app? (si-publica/no/no-se)' "$despliega_default")"
case "$despliega_resp" in
  si-publica|publica) despliega_json="publica" ;;
  no)                 despliega_json="no" ;;
  no-se|nose|"")      despliega_json="unknown" ;;
  *) printf 'saikit-setup-autopilot: --despliega exige publica|no|no-se (llego: %s)\n' "$despliega_resp" >&2; exit 2 ;;
esac

salud_resp="$salud_flag"
if [ "$salud_resp" = "__sin_dato__" ]; then
  salud_resp="$(preguntar '3/5 URL https para checar que la app sigue viva? (vacio = ninguna)' "")"
fi
# Veto JSON (cross-review kimi+grok): salud_url se interpola cruda en el
# JSON. Una `"` o `\` rompia el archivo o inyectaba claves (`https://x","
# inyectada":"` validaba con rc=0). Se veta ANTES de escribir, no despues.
case "$salud_resp" in
  *\"*|*\\*|*[[:cntrl:]]*)
    printf 'saikit-setup-autopilot: --salud-url no puede traer comillas, barras invertidas ni controles\n' >&2; exit 2 ;;
esac
case "$salud_resp" in
  ""|"-") salud_json="null" ;;
  http://*|https://*) salud_json="\"$salud_resp\"" ;;
  *) printf 'saikit-setup-autopilot: la URL de salud tiene que ser http(s) o vacia (llego: %s)\n' "$salud_resp" >&2; exit 2 ;;
esac

sve_resp="${sve_flag:-}"
[ -n "$sve_resp" ] || sve_resp="$(preguntar '4/5 Sin prueba de la app, mergeo solo? (si/no)' "$sve_default")"
sve_json="$(normalizar_si_no "$sve_resp" --sin-verify-app)" || exit 2

telegram_resp="${telegram_flag:-}"
[ -n "$telegram_resp" ] || telegram_resp="$(preguntar '5/5 Te aviso por Telegram cuando el post-merge mire el run? (si/no)' "$telegram_default")"
telegram_json="$(normalizar_si_no "$telegram_resp" --telegram)" || exit 2

rama_resp="${rama_flag:-$rama_default}"
case "$rama_resp" in
  ""|*[[:space:]]*) printf 'saikit-setup-autopilot: --rama no puede ser vacia ni llevar espacios\n' >&2; exit 2 ;;
esac
# Mismo veto JSON que salud_url: la rama tambien se interpola cruda.
case "$rama_resp" in
  *\"*|*\\*|*[[:cntrl:]]*)
    printf 'saikit-setup-autopilot: --rama no puede traer comillas, barras invertidas ni controles\n' >&2; exit 2 ;;
esac

# ------------------------------------------------------------- escribir
SAIKIT_DIR="$ROOT/.saikit"
CFG="$SAIKIT_DIR/autopilot.json"
# .saikit simbolico: mkdir -p lo seguiria y escribiria mas alla del repo
# (hallazgo del lead, PR #161). Se rechaza ANTES de crear/escribir nada.
if [ -L "$SAIKIT_DIR" ]; then
  printf 'saikit-setup-autopilot: %s es un enlace simbolico; no se escribe a traves (quitalo a mano si es tuyo)\n' "$SAIKIT_DIR" >&2
  exit 2
fi
mkdir -p "$SAIKIT_DIR" 2>/dev/null \
  || { printf 'saikit-setup-autopilot: no se pudo crear %s\n' "$SAIKIT_DIR" >&2; exit 2; }

# Existente corrupto: se REPORTA y no se toca (fail-closed; precedente 17.3:
# un rastro manoseado no se silicona en silencio).
if [ -f "$CFG" ] && ! saikit_json_valido "$(cat "$CFG")"; then
  printf 'saikit-setup-autopilot: %s existe y no es JSON valido; no se toca (arreglalo o borralo a mano)\n' "$CFG" >&2
  exit 2
fi

contenido="$(printf '{"merge":%s,"merge_despliega":"%s","salud_url":%s,"revert_si_rojo":true,"rama":"%s","sin_verify_app":%s,"telegram":%s}' \
  "$merge_json" "$despliega_json" "$salud_json" "$rama_resp" "$sve_json" "$telegram_json")"
# Escritura atomica (patron de tools/install-hook.sh): temporal EN EL MISMO
# dir, validar el temporal, y recien entonces mv -f. Escribir directo a $CFG
# perdia la config previa ANTES de validar: si lo producido no validaba (una
# regresion del veto de arriba), el aviso salia con la config buena ya pisada
# (hallazgo del lead, PR #161).
umask_prev="$(umask)"
umask 077
CFG_TMP="$(mktemp "$SAIKIT_DIR/.autopilot.json.XXXXXX")" \
  || { umask "$umask_prev"; printf 'saikit-setup-autopilot: no se pudo crear el temporal para %s\n' "$CFG" >&2; exit 2; }
if ! printf '%s\n' "$contenido" > "$CFG_TMP"; then
  rm -f "$CFG_TMP"; umask "$umask_prev"
  printf 'saikit-setup-autopilot: no se pudo escribir %s\n' "$CFG" >&2
  exit 2
fi
if ! saikit_json_valido "$(cat "$CFG_TMP")"; then
  rm -f "$CFG_TMP"; umask "$umask_prev"
  printf 'saikit-setup-autopilot: lo escrito no valida como JSON; no se sigue (%s queda intacto)\n' "$CFG" >&2
  exit 2
fi
mv -f "$CFG_TMP" "$CFG" \
  || { rm -f "$CFG_TMP"; umask "$umask_prev"; printf 'saikit-setup-autopilot: no se pudo escribir %s\n' "$CFG" >&2; exit 2; }
umask "$umask_prev"

# .gitignore de veredictos, idempotente (ver cabecera: por que no en la raiz).
# Veto de componentes simbolicos (review ronda 2): mkdir -p sigue un
# veredictos/ que sea symlink (el destino "ya existe" a traves del enlace) y el
# printf >> escribiria el .gitignore FUERA del repo. Lo mismo si el .gitignore
# mismo es un enlace: el append escribe a traves. mv -f sobre autopilot.json
# esta cerrado por diseno (rename no sigue el enlace).
if [ -L "$SAIKIT_DIR/veredictos" ] || [ -L "$SAIKIT_DIR/veredictos/.gitignore" ]; then
  printf 'saikit-setup-autopilot: %s/veredictos (o su .gitignore) es un enlace simbolico; no se escribe a traves (quitalo a mano si es tuyo)\n' "$SAIKIT_DIR" >&2
  exit 2
fi
mkdir -p "$SAIKIT_DIR/veredictos" 2>/dev/null \
  || { printf 'saikit-setup-autopilot: no se pudo crear %s/veredictos\n' "$SAIKIT_DIR" >&2; exit 2; }
if ! grep -q -x -F '*' "$SAIKIT_DIR/veredictos/.gitignore" 2>/dev/null; then
  printf '*\n' >> "$SAIKIT_DIR/veredictos/.gitignore" \
    || { printf 'saikit-setup-autopilot: no se pudo asegurar el .gitignore de veredictos\n' >&2; exit 2; }
fi

GEN="${SAIKIT_CI_MINIMO:-$HERE/saikit-ci-minimo.sh}"
# Exit 2 del generador (sin runner, validacion) no tumba el setup: el JSON ya
# esta escrito. Sin degradar, --ci-minimo si + repo vacio deja config sin YAML.
if ! bash "$GEN" --ofrecer --root "$ROOT" ${ci_minimo_flag:+--ci-minimo "$ci_minimo_flag"}; then
  printf 'saikit-setup-autopilot: ci-minimo no se pudo ofrecer o escribir; el setup sigue (config ya persistida)\n'
fi

printf 'saikit-setup-autopilot: listo: %s\n' "$CFG"
printf '  merge=%s despliega=%s rama=%s pr=%s\n' "$merge_json" "$despliega_json" "$rama_resp" "${pr_flag:-(sin pr)}"
# Si el generador dejo el yml, el merge necesita ESE archivo en origin, no solo
# el JSON (hallazgo interrogate: seguir el listo al pie dejaba el workflow
# untracked y el veto sin checks seguia).
if [ -f "$ROOT/.github/workflows/saikit-ci-minimo.yml" ]; then
  printf '  incluye tambien .github/workflows/saikit-ci-minimo.yml en el commit.\n'
fi
printf '  commitea y pushea a origin/%s: el merge lee la config (y el CI) de ahi, no de tu disco.\n' "$rama_resp"
exit 0
