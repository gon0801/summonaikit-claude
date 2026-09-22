#!/usr/bin/env bash
# tools/saikit-merge.sh — Bloque A (entrega sin sello): gate de merge
# fail-closed y acotado del autopilot. SEGUNDA excepcion declarada al
# fail-open del harness (la primera es el instalador): mergear es la accion
# que no admite "dejar pasar", asi que TODO unknown rechaza y NOMBRA la razon.
#
# USO:
#   tools/saikit-merge.sh                 # corre TODAS las comprobaciones y,
#                                         # con todas en verde, NO mergea:
#                                         # reporta LISTO y termina (decision
#                                         # del operador 2026-08-30: el merge
#                                         # lo autoriza el operador).
#   tools/saikit-merge.sh --confirmado    # el SI del operador. Confirma la
#                                         # INTENCION, no las condiciones:
#                                         # esta invocacion REPITE el gate
#                                         # completo (mismo sha, base al dia,
#                                         # CI verde, recibo del PR) y si
#                                         # algo cambio vuelve a NO-MERGE y
#                                         # avisa EN VEZ DE MERGEAR.
#   tools/saikit-merge.sh --dry-run       # dice que haria, sin hacerlo.
#   tools/saikit-merge.sh --revert-de <merge_commit> [--confirmado] [--dry-run]
#                                         # modo D19: merge del PR de revert.
#                                         # SIN estado del hook y SIN confiar
#                                         # en ningun JSON local — exige punta
#                                         # de origin/<rama>, trailer
#                                         # Saikit-Merge:, igualdad EXACTA de
#                                         # arboles (patch-id solo como extra),
#                                         # un solo commit y CI verde.
#   tools/saikit-merge.sh --liberar-lock
#                                         # recuperacion EXPLICITA del lock de
#                                         # integracion (20.5): muestra su
#                                         # contenido y lo quita. Desde A.R6 un
#                                         # dueno LOCAL muerto o con pid
#                                         # reciclado se recupera solo, con
#                                         # reclamo atomico; identidad
#                                         # indeterminable, host ajeno y dueno
#                                         # vivo jamas se tocan.
#
# EL MERGE, cuando toca: `gh pr merge --squash --match-head-commit <sha>
# --body "Saikit-Merge: <sha>"` SIN --delete-branch (el borrado remoto es un
# paso aparte; si falla se reporta sin reintentar). NUNCA --admin, nunca
# force. El merge_commit se registra en .saikit/veredictos/<sha>.merge
# (registro del efecto, no prueba de la entrega).
#
# RECIBO DE ENTREGA (saikit-entrega.v1; el sello quedo retirado). La
# autoridad es el PR, no el estado de sesion: el gate carga el ULTIMO recibo
# aplicable (comentario APPROVE lead <sha> con bloque ```json) y valida
# estructura y relaciones con tools/lib/entrega_contract.sh — coordenadas
# repo/PR/sha, implementer/verifier/reviewer con ids DISTINTOS, verifier
# PASS, reviewer APPROVE y sin bloqueantes abiertos. Para clases fast basta
# autor + lead. El recibo identifica el workflow que acredita la bateria; el
# gate exige ese workflow exacto. Sin recibo, revocado o incompleto =>
# NO-MERGE nombrado. El gate NO consulta directorios de
# estado, veredictos sellados ni harness-evidence.log: un host nuevo
# revalida el mismo PR sin sellar nada, y los restos viejos se ignoran.
# LIMITES DECLARADOS: (a) el validador comprueba estructura y relaciones, no
# la independencia criptografica de los agentes ni la verdad de la prosa;
# (b) los enlaces de evidencia los verifica el lead, no este script; (c) un
# REVOKE posterior del mismo autor anula el recibo, y los hallazgos
# posteriores en prosa los adjudica el lead. Detalle en la lib.
#
# CI VIGENTE (A4): en modo normal se juzga el workflow que acredita el recibo;
# los demas no lo sustituyen. De ese workflowName se toma SOLO el intento con
# mayor number: un fallo viejo reemplazado por un verde nuevo no bloquea, y un
# verde viejo reemplazado por un pendiente/rojo nuevo no alcanza. En revert,
# que no usa recibo, se juzgan todos los workflows vigentes. "Sin checks" NO
# es verde: se mira
# `gh run list --commit` (gh pr checks agrega bots de terceros; medido 18.1
# §2.1), y del run del evento pull_request si existe (el mismo head dispara
# push + pull_request). Decision 18.24 intacta: skipped = CI rojo; solo-push
# completed+success = verde (hay_pr=0 juzga todos los runs).
#
# El delay del reintento de mergeable UNKNOWN es SAIKIT_MERGE_RETRY_SEG
# (default 3; los tests lo ponen en 0).
#
# LOCK DE INTEGRACION (20.5). Con --confirmado (modo normal o --revert-de) se
# toma un lock en $(git rev-parse --git-common-dir)/saikit-merge.lock — el
# MISMO archivo para todos los worktrees del clone. Mismo diseño que el lock
# D20 del setup: mkdir atomico, el dir guarda pid/host/inicio/modo, el trap
# EXIT libera SOLO el propio (comparando el pid), un lock ajeno se REPORTA y
# BLOQUEA con exit 3 (distinguible del NO-MERGE del gate). SOLO se borra por
# --liberar-lock explicito, o por la recuperacion atomica de A.R6 cuando el
# dueno es LOCAL y esta muerto (o su pid fue reciclado: el proceso actual es
# mas joven que el lock): identidad indeterminable, host ajeno y dueno vivo
# jamas se tocan.
#   Revalidar al adquirir: el lock se toma al PRINCIPIO de la invocacion; TODO
#   lo que decide corre DESPUES de adquirirlo. Un reintento con el lock ya
#   libre vuelve a correr el gate completo desde cero (recibo en modo normal;
#   punta/trailer/arbol/CI en --revert-de, que sigue SIN estado propio) — no
#   hay nada heredado del intento anterior.
#   LIMITE DECLARADO: el lock es por git-common-dir. Dos clones independientes
#   del mismo repo tienen common-dirs DISTINTOS y NO se excluyen entre si:
#   este lock no promete exclusión entre clones.
# Exit: 0 ok/listo/dry-run/liberar; 1 NO-MERGE (gate); 2 uso; 3 lock ajeno.
set -u

# 18.25: la forma de la salida de gh no es estable — depende del entorno del
# agente que lo corre. Medido (gh 2.98.0, 2026-09-05): con CLICOLOR_FORCE=1
# heredado (harnesses de agentes) gh colorea y prety-imprime su --json incluso
# a un pipe (la captura de $(...)), y CLICOLOR_FORCE LE GANA a NO_COLOR; el
# parser estricto muere con el primer ESC (control char). Se neutraliza el
# color de TODAS las llamadas gh del script en un punto; si la salida aun asi
# no parsea, el gate sigue fallando cerrado igual que hoy.
export NO_COLOR=1 CLICOLOR=0
unset CLICOLOR_FORCE

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib/veredicto_contract.sh"   # parser JSON compartido (sin jq)
. "$HERE/lib/entrega_contract.sh"     # recibo saikit-entrega.v1 + lectura del PR

CONFIRMADO=0
DRY_RUN=0
REVERT_DE=""
LIBERAR_LOCK=0

uso() { sed -n '8,33p' "$0"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --confirmado) CONFIRMADO=1; shift ;;
    --dry-run)    DRY_RUN=1; shift ;;
    --revert-de)
      [ $# -ge 2 ] || { printf 'saikit-merge: --revert-de exige un merge_commit\n' >&2; exit 2; }
      REVERT_DE="$2"; shift 2 ;;
    --liberar-lock) LIBERAR_LOCK=1; shift ;;
    -h|--help)    uso; exit 0 ;;
    *)            printf 'saikit-merge: opcion desconocida: %s\n' "$1" >&2; uso >&2; exit 2 ;;
  esac
done

no_merge() {  # rechaza y NOMBRA la razon; todo fallo del gate pasa por aca
  printf 'NO-MERGE: %s\n' "$1"
  exit 1
}

# ---------------------------------------------------------------- preambulo
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" \
  || no_merge "el cwd no es un repo git"
PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd -P)"   # misma forma fisica que el hook
cd "$PROJECT_ROOT" || no_merge "no se pudo entrar al proyecto ($PROJECT_ROOT)"

# ------------------------------------------------ lock de integracion (20.5)
# El cwd ya es el toplevel: un common-dir relativo (`.git`) se resuelve contra
# el toplevel. Contra el cwd de INVOCACION apuntaria fuera del repo (misma
# leccion del cross-review kimi en el lock del setup, 18.7).
COMMON="$(git rev-parse --git-common-dir 2>/dev/null)" \
  || no_merge "no se pudo resolver el git-common-dir"
case "$COMMON" in
  /*) ;;
  *) COMMON="$(cd "$COMMON" 2>/dev/null && pwd -P)" \
       || no_merge "no se pudo resolver el common-dir ($COMMON)" ;;
esac
LOCK_DIR="$COMMON/saikit-merge.lock"

mostrar_lock() {  # reporta el contenido del lock, campo por campo
  printf '  lock: %s\n' "$LOCK_DIR"
  printf '    pid: %s\n' "$(cat "$LOCK_DIR/pid" 2>/dev/null || printf '(sin pid)')"
  printf '    host: %s\n' "$(cat "$LOCK_DIR/host" 2>/dev/null || printf '(sin host)')"
  printf '    inicio: %s\n' "$(cat "$LOCK_DIR/started_at" 2>/dev/null || printf '(sin inicio)')"
  printf '    modo: %s\n' "$(cat "$LOCK_DIR/modo" 2>/dev/null || printf '(sin modo)')"
}

# Recuperacion EXPLICITA del lock (20.5): muestra el contenido y lo quita.
# Sin lock es no-op en verde. Es la UNICA via de recuperacion: el lock ajeno
# nunca se borra solo (ver abajo).
if [ "$LIBERAR_LOCK" = 1 ]; then
  if [ ! -d "$LOCK_DIR" ]; then
    printf 'saikit-merge: sin lock de integracion: nada que liberar (%s no existe)\n' "$LOCK_DIR"
    exit 0
  fi
  printf 'saikit-merge: lock de integracion encontrado, se libera:\n'
  mostrar_lock
  rm -f "$LOCK_DIR"/pid "$LOCK_DIR"/host "$LOCK_DIR"/started_at "$LOCK_DIR"/modo 2>/dev/null
  rmdir "$LOCK_DIR" 2>/dev/null \
    || { printf 'saikit-merge: no se pudo quitar %s\n' "$LOCK_DIR" >&2; exit 2; }
  printf 'saikit-merge: lock de integracion liberado\n'
  exit 0
fi

# Adquisicion SOLO para la invocacion que puede producir el efecto (la que
# trae --confirmado, en cualquiera de los dos modos): LISTO y --dry-run no
# integran nada y no toman el lock. mkdir es atomico: si ya existe, otro
# saikit-merge del mismo clone lo tiene (o lo dejo). Se REPORTA y se BLOQUEA
# con exit 3 (distinguible del NO-MERGE del gate). La caida del tenedor
# (kill -9) NO corre el trap y el lock SOBREVIVE; desde A.R6 la recuperación
# de un dueno LOCAL muerto (o con el pid reciclado) es automatica y atomica
# por reclamo (ver abajo): identidad indeterminable, host ajeno o dueno vivo
# jamas se tocan, y --liberar-lock sigue siendo la salida explicita.
SOSTENER="${SAIKIT_MERGE_SOSTENER_SEG:-0}"
candado_propio=0
liberar_propio() {
  if [ "$candado_propio" -ne 1 ]; then return 0; fi
  if [ "$(cat "$LOCK_DIR/pid" 2>/dev/null || true)" = "$$" ]; then
    rm -f "$LOCK_DIR"/pid "$LOCK_DIR"/host "$LOCK_DIR"/started_at "$LOCK_DIR"/modo 2>/dev/null
    rmdir "$LOCK_DIR" 2>/dev/null || true
  fi
  candado_propio=0
}

# segundos_de_vida <pid>: etime de ps a segundos; vacio si no se pudo medir.
segundos_de_vida() {
  local e d=0 h=0
  e="$(ps -o etime= -p "$1" 2>/dev/null | tr -d ' ')" || return 1
  case "$e" in ''|*[!0-9:-]*) return 1;; esac
  case "$e" in *-*) d="${e%%-*}"; e="${e#*-}";; esac
  case "$e" in *:*:*) h="${e%%:*}"; e="${e#*:}";; esac
  case "$e" in
    *:*) printf '%s\n' $(( d*86400 + h*3600 + ${e%%:*}*60 + ${e##*:} ));;
    *) return 1;;
  esac
}

# edad_inicio_iso <started_at>: segundos desde la marca UTC del lock; 1 sin dato.
edad_inicio_iso() {
  INICIO_ISO="$1" python3 -c '
import os, datetime
try:
    t = datetime.datetime.strptime(os.environ["INICIO_ISO"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)
    print(int(datetime.datetime.now(datetime.timezone.utc).timestamp() - t.timestamp()))
except Exception:
    raise SystemExit(1)
' 2>/dev/null
}

lock_tomar_campos() {  # escribe pid/host/started_at/modo y arma el trap propio
  printf '%s' "$$" > "$LOCK_DIR/pid" \
    || { rmdir "$LOCK_DIR" 2>/dev/null; no_merge "no se pudo escribir el lock de integracion"; }
  printf '%s' "$(hostname 2>/dev/null || printf '?')" > "$LOCK_DIR/pid.host.tmp" 2>/dev/null \
    && mv "$LOCK_DIR/pid.host.tmp" "$LOCK_DIR/host" 2>/dev/null || true
  printf '%s' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || printf '?')" > "$LOCK_DIR/started_at" 2>/dev/null || true
  if [ -n "$REVERT_DE" ]; then MODO_LOCK=revert; else MODO_LOCK=merge; fi
  printf '%s' "$MODO_LOCK" > "$LOCK_DIR/modo" 2>/dev/null || true
  candado_propio=1
  trap 'liberar_propio' EXIT
}

if [ "$CONFIRMADO" = 1 ]; then
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    lock_tomar_campos
  else
    # A.R6: clasificar al dueno ANTES de rendirse. Sin pid, con pid no
    # numerico o sin host: identidad INDETERMINABLE, el lock no se toca. Con
    # host ajeno: menos aun (puede haber un merge en curso desde otra
    # maquina que comparte el common-dir). Dueno local vivo: no se roba.
    # Dueno local muerto, o pid reciclado (el proceso del pid es MAS JOVEN
    # que el lock, asi que el que tomo el lock ya no existe): recuperacion
    # ATOMICA por reclamo — mv a una tumba (el mv es el arbitro entre dos
    # recuperadores), re-verificacion del pid dentro de la tumba, y mkdir
    # nuevo. El perdedor de la carrera ve la tumba perdida o el lock sano
    # del ganador y sale 3 sin tocar nada.
    lock_pid="$(cat "$LOCK_DIR/pid" 2>/dev/null || true)"
    lock_host="$(cat "$LOCK_DIR/host" 2>/dev/null || true)"
    lock_inicio="$(cat "$LOCK_DIR/started_at" 2>/dev/null || true)"
    lock_local="$(hostname 2>/dev/null || printf '?')"
    lock_clase="indeterminable"
    case "$lock_pid" in
      ''|*[!0-9]*) : ;;
      *)
        case "$lock_host" in
          ''|'?') : ;;
          "$lock_local")
            if ! kill -0 "$lock_pid" 2>/dev/null; then
              lock_clase="muerto"
            else
              e_lock="$(edad_inicio_iso "$lock_inicio")" || e_lock=""
              e_proc="$(segundos_de_vida "$lock_pid")" || e_proc=""
              # Margen de 5 s: en una maquina cargada, la edad del lock y el
              # etime del dueno difieren en segundos de puro redondeo; sin
              # margen un dueno vivo se leeria reciclado (medido en CI). El
              # caso real de pid reciclado lleva el lock huerfano desde hace
              # mucho mas que el margen.
              if [ -n "$e_lock" ] && [ -n "$e_proc" ] && [ $((e_lock - e_proc)) -gt 5 ]; then
                lock_clase="reciclado"
              else
                lock_clase="vivo"
              fi
            fi ;;
          *) lock_clase="ajeno" ;;
        esac ;;
    esac
    if [ "$lock_clase" = "muerto" ] || [ "$lock_clase" = "reciclado" ]; then
      # Gancho SOLO de test: pausa ENTRE la clasificacion y el reclamo, para
      # que el caso de dos recuperadores los parquee a los dos dentro de la
      # ventana con determinismo. Sin la variable es 0: PRODUCCION INTACTA.
      sleep "${SAIKIT_MERGE_RECUPERAR_PAUSA:-0}" 2>/dev/null || true
      tumba="$LOCK_DIR.muerto.$$-${RANDOM:-0}"
      if mv "$LOCK_DIR" "$tumba" 2>/dev/null \
         && [ "$(cat "$tumba/pid" 2>/dev/null || true)" = "$lock_pid" ] \
         && rm -f "$tumba"/pid "$tumba"/host "$tumba"/started_at "$tumba"/modo 2>/dev/null \
         && rmdir "$tumba" 2>/dev/null \
         && mkdir "$LOCK_DIR" 2>/dev/null; then
        printf 'saikit-merge: lock de un dueno local %s (pid %s): recuperado con reclamo atomico\n' "$lock_clase" "$lock_pid" >&2
        lock_tomar_campos
      else
        [ -d "$tumba" ] && { mv "$tumba" "$LOCK_DIR" 2>/dev/null || true; }
        printf 'saikit-merge: LOCK de integracion ocupado, no se sigue (%s):\n' "$LOCK_DIR" >&2
        mostrar_lock >&2
        exit 3
      fi
    else
      printf 'saikit-merge: LOCK de integracion ocupado, no se sigue (%s):\n' "$LOCK_DIR" >&2
      mostrar_lock >&2
      case "$lock_clase" in
        vivo)
          printf '  el dueno (pid %s en %s) sigue vivo: no se roba un merge en curso\n' "$lock_pid" "$lock_host" >&2
          printf '  no se borra solo: si el dueno murio, liberalo explicito con:\n' >&2
          printf '    bash tools/saikit-merge.sh --liberar-lock\n' >&2 ;;
        ajeno)
          printf '  el dueno esta en otro host (%s): este clone no toca ese lock\n' "$lock_host" >&2 ;;
        *)
          printf '  identidad indeterminable (pid=%s host=%s): sin identidad no se borra\n' "${lock_pid:-(sin pid)}" "${lock_host:-(sin host)}" >&2 ;;
      esac
      exit 3
    fi
  fi
fi

# Gancho SOLO de test (precedente: SAIKIT_SETUP_SOSTENER_SEG de la 18.7):
# dormir N segundos con el lock tomado, para que un caso de contencion
# orqueste la carrera con determinismo. Sin la variable es 0: PRODUCCION
# INTACTA.
if [ "$SOSTENER" -gt 0 ] 2>/dev/null && [ "$candado_propio" = 1 ]; then
  sleep "$SOSTENER"
fi

RAMA_PR="$(git rev-parse --abbrev-ref HEAD)"
[ "$RAMA_PR" != "HEAD" ] || no_merge "HEAD detached; el gate necesita la rama del PR"
SHA="$(git rev-parse HEAD)"
VERDICTOS="$PROJECT_ROOT/.saikit/veredictos"

# repo del cwd: lo que declara la URL de origin vs lo que resuelve gh.
# `git config` (crudo, sin reescritura insteadOf) — `git remote get-url`
# devuelve la URL YA reescrita y romperia la comparacion.
REPO_URL="$(git config remote.origin.url)" \
  || no_merge "no hay remote origin; no se puede identificar el repo"
REPO_LOCAL=""
case "$REPO_URL" in
  https://github.com/*) REPO_LOCAL="${REPO_URL#https://github.com/}" ;;
  git@github.com:*)     REPO_LOCAL="${REPO_URL#git@github.com:}" ;;
  *) no_merge "no se pudo derivar el repo del remote origin ($REPO_URL): el gate exige un remote github" ;;
esac
REPO_LOCAL="${REPO_LOCAL%.git}"
REPO_GH_RAW="$(gh repo view --json nameWithOwner 2>/dev/null)" \
  || no_merge "gh repo view no respondio en este cwd"
REPO_GH="$(saikit_json_get "$REPO_GH_RAW" nameWithOwner)" \
  || no_merge "gh repo view devolvio algo inesperado (¿color forzado del terminal? nunca deberia verse con el entorno neutralizado): $REPO_GH_RAW"
[ "$REPO_GH" = "$REPO_LOCAL" ] || no_merge "repo distinto: origin apunta a $REPO_LOCAL y gh a $REPO_GH"

# PR de la rama actual.
pr_leer() {
  PR_RAW="$(gh pr view --json number,baseRefName,headRefOid,author,mergeable 2>/dev/null)" \
    || no_merge "no hay PR de la rama actual ($RAMA_PR), o gh no pudo leerlo"
  saikit_json_valido "$PR_RAW" || no_merge "gh pr view devolvio JSON invalido"
  PR="$(saikit_json_get "$PR_RAW" number)"
  PR_BASE="$(saikit_json_get "$PR_RAW" baseRefName)"
  PR_HEAD="$(saikit_json_get "$PR_RAW" headRefOid)"
  PR_AUTOR="$(saikit_json_get "$PR_RAW" author.login)"
  MERGEABLE="$(saikit_json_get "$PR_RAW" mergeable)"
}
pr_leer
case "$PR" in
  ''|*[!0-9]*) no_merge "gh pr view no trajo un numero de PR valido: [$PR]" ;;
esac

# mergeable UNKNOWN: GitHub lo calcula en diferido; UN reintento, no mas.
if [ "$MERGEABLE" = "UNKNOWN" ]; then
  sleep "${SAIKIT_MERGE_RETRY_SEG:-3}"
  pr_leer
  [ "$MERGEABLE" = "UNKNOWN" ] && no_merge "mergeable UNKNOWN tras el reintento; GitHub todavia no calculo el PR"
fi
[ "$MERGEABLE" = "MERGEABLE" ] || no_merge "el PR no es mergeable ($MERGEABLE)"

# cuenta de gh (para el autor del PR y los emails noreply de los commits).
USER_RAW="$(gh api user 2>/dev/null)" || no_merge "gh api user no respondio; no se pudo identificar la cuenta"
LOGIN="$(saikit_json_get "$USER_RAW" login)" || no_merge "gh api user no trajo login"

# ------------------------------------------------------------ config (D15)
# Leida SOLO de origin/<rama base del PR>, nunca del working tree ni del head.
git fetch -q origin "$PR_BASE" 2>/dev/null || no_merge "no se pudo hacer git fetch origin $PR_BASE"
CFG_RAW="$(git show "origin/$PR_BASE:.saikit/autopilot.json" 2>/dev/null)" \
  || no_merge "config ausente: no hay .saikit/autopilot.json en origin/$PR_BASE"
saikit_json_valido "$CFG_RAW" || no_merge "config ausente: .saikit/autopilot.json en origin/$PR_BASE no es JSON valido"
CFG_MERGE="$(saikit_json_get "$CFG_RAW" merge)"
CFG_DESPLIEGA="$(saikit_json_get "$CFG_RAW" merge_despliega)"
CFG_RAMA="$(saikit_json_get "$CFG_RAW" rama)"
CFG_SIN_VERIFY_APP="$(saikit_json_get "$CFG_RAW" sin_verify_app)"
[ "$CFG_MERGE" = "true" ] || no_merge "la config no autoriza a mergear (merge != true)"
[ "$CFG_DESPLIEGA" = "publica" ] || [ "$CFG_DESPLIEGA" = "no" ] \
  || no_merge "merge_despliega unknown: el operador no decidio si mergear publica; no se mergea"
if [ "$CFG_RAMA" != "$PR_BASE" ]; then
  no_merge "otra rama base: el PR apunta a $PR_BASE y la config declara rama $CFG_RAMA"
fi
RAMA="$PR_BASE"
ORIGEN="origin/$RAMA"

# head del PR == sha local (el PR es de ESTA punta).
[ "$PR_HEAD" = "$SHA" ] || no_merge "el PR apunta a otro head ($PR_HEAD != $SHA local)"

# autor del PR = cuenta de gh (el PR lo abrio el propio flujo).
[ "$PR_AUTOR" = "$LOGIN" ] || no_merge "autor del PR distinto de la cuenta (PR de $PR_AUTOR, cuenta $LOGIN)"

# ------------------------------------------------------------- CI del head
# "sin checks" NO es verde: se mira `gh run list --commit` (gh pr checks
# agrega bots de terceros; medido 18.1 §2.1), y del run del evento
# pull_request si existe (el mismo head dispara push + pull_request).
# Decision 18.24: skipped = CI rojo (mismo balde que cancelled/neutral;
# n>0, no es «sin checks», no slogan nuevo). solo-push completed+success
# = verde: hay_pr=0 juzga todos los runs. Exigir pull_request seria
# politica nueva. Ver .saikit/decisiones/18.24.tsv.
ci_chequear() {
  local requerido="${1:-}"
  local raw flat i n hay_pr ev st conc head w num lista ganadores seleccionados
  raw="$(gh run list --commit "$SHA" --json event,status,conclusion,headSha,workflowName,number 2>/dev/null)" \
    || no_merge "no se pudo leer el CI (gh run list fallo)"
  saikit_json_valido "$raw" || no_merge "gh run list devolvio algo que no es JSON"
  flat="$(saikit_json_flat "$raw")"
  jget() { printf '%s\n' "$flat" | awk -F'\t' -v p="$1" '$1 == p { print $2; exit }'; }
  n=0; hay_pr=0
  while [ -n "$(jget "[$n].event")" ]; do
    [ "$(jget "[$n].event")" = "pull_request" ] && hay_pr=1
    n=$((n + 1))
  done
  [ "$n" -gt 0 ] || no_merge "sin checks: gh run list no trajo ningun run para $SHA (que no haya CI no es verde)"
  # A4: de cada workflowName se juzga SOLO el intento con mayor number (un
  # fallo viejo reemplazado por un verde nuevo no bloquea; un verde viejo
  # reemplazado por un pendiente/rojo nuevo no alcanza). Sin workflowName
  # (gh viejo) cada run es su propio grupo y se juzgan todos.
  i=0; lista=""; seleccionados=0
  while [ "$i" -lt "$n" ]; do
    ev="$(jget "[$i].event")"
    if [ "$hay_pr" = 1 ] && [ "$ev" != "pull_request" ]; then i=$((i + 1)); continue; fi
    w="$(jget "[$i].workflowName")"
    [ -n "$w" ] && [ "$w" != "<null>" ] || w="~sin-nombre-$i"
    if [ -n "$requerido" ] && [ "$w" != "$requerido" ]; then i=$((i + 1)); continue; fi
    num="$(jget "[$i].number")"
    case "$num" in ''|*[!0-9]*) num=0 ;; esac
    lista="$lista$w	$num	$i
"
    seleccionados=$((seleccionados + 1))
    i=$((i + 1))
  done
  if [ -n "$requerido" ] && [ "$seleccionados" -eq 0 ]; then
    no_merge "sin CI del workflow requerido por el recibo ($requerido) para $SHA"
  fi
  ganadores="$(printf '%s' "$lista" | awk -F'\t' '{ if (!($1 in best) || $2 > bestnum[$1]) { best[$1]=$3; bestnum[$1]=$2 } } END { for (k in best) print best[k] }')"
  for i in $ganadores; do
    st="$(jget "[$i].status")"
    if [ "$st" != completed ]; then no_merge "CI pendiente: el run $i no concluyo (status $st)"; fi
    conc="$(jget "[$i].conclusion")"
    if [ "$conc" != success ]; then no_merge "CI rojo: el run $i concluyo $conc"; fi
    # 22.3: frescura propia — el verde tiene que ser del sha exacto bajo gate,
    # no de otro head (el --commit se pide pero gh podria traer de mas; el gh
    # falso del test ignora flags, asi que la correspondencia local es la
    # proteccion real).
    # 22.3r1 (review Codigo): presencia exigida — un headSha ausente o null NO
    # es fresco (not_observed != fresh): se rechaza con motivo explicito en
    # vez de aceptar por silencio. El aplanador entrega null como <null>.
    head="$(jget "[$i].headSha")"
    if [ -z "$head" ] || [ "$head" = "<null>" ]; then no_merge "CI sin headSha: el run $i no trae el sha del head (no observado no es fresco)"; fi
    if [ "$head" != "$SHA" ]; then no_merge "CI verde pero de otro sha ($head != $SHA)"; fi
  done
}

# ------------------------------------------------------------------ merge
borrado_remoto() {
  if git push origin --delete "$RAMA_PR" >/dev/null 2>&1; then
    printf 'BORRADO-OK: rama remota %s borrada (paso aparte)\n' "$RAMA_PR"
  else
    printf 'BORRADO-FALLO: no se pudo borrar la rama remota %s — se reporta sin reintentar (el merge ya esta hecho)\n' "$RAMA_PR"
  fi
  return 0
}

merge_final() {
  if [ "$DRY_RUN" = 1 ]; then
    printf 'DRY-RUN: gate en verde; haria: gh pr merge %s --squash --match-head-commit %s --body "Saikit-Merge: %s" (sin --delete-branch)\n' "$PR" "$SHA" "$SHA"
    printf 'DRY-RUN: borrado remoto aparte: git push origin --delete %s\n' "$RAMA_PR"
    exit 0
  fi
  if [ "$CONFIRMADO" != 1 ]; then
    printf 'LISTO: todas las condiciones del gate estan en verde para %s (PR %s). El merge lo autoriza el operador:\n' "$SHA" "$PR"
    # Con "bash " adelante (20.2): un checkout sin bit de ejecucion (copia
    # extraida, zip, algunos filesystems) no puede correr la forma pelada.
    printf 'LISTO:   bash tools/saikit-merge.sh --confirmado\n'
    exit 0
  fi
  # Con --confirmado el gate completo ACABA de correr otra vez en esta
  # invocacion (arriba); si algo hubiera cambiado, ya habria salido por
  # NO-MERGE en vez de llegar aca.
  gh pr merge "$PR" --squash --match-head-commit "$SHA" --body "Saikit-Merge: $SHA" \
    || no_merge "gh pr merge rechazo el merge (¿cambio el head o la punta mientras corria?)"
  MC_RAW="$(gh pr view "$PR" --json mergeCommit 2>/dev/null)" \
    || no_merge "el merge salio pero gh pr view --json mergeCommit no respondio; mirar el PR a mano"
  MERGE_COMMIT="$(saikit_json_get "$MC_RAW" mergeCommit.oid)" \
    || no_merge "no se pudo leer el merge_commit: $MC_RAW"
  # El directorio puede NO existir: lo crea el hook y su .gitignore lleva '*',
  # asi que no viaja en un clon fresco — que es JUSTO donde corre --revert-de
  # (ese modo no exige veredicto, asi que nada garantiza el dir). Sin `set -e`
  # una redireccion fallida no detenia nada y MERGE-OK anunciaba un registro
  # inexistente (CodeRabbit, PR #142). Misma postura que borrado_remoto: el
  # merge YA esta hecho, se reporta y no se reintenta — pero NO se miente sobre
  # lo que se escribio. El veredicto sellado no se toca en ningun caso.
  if mkdir -p "$VERDICTOS" 2>/dev/null \
     && printf '%s\n' "$MERGE_COMMIT" > "$VERDICTOS/$SHA.merge" 2>/dev/null; then
    REGISTRO="registrado en .saikit/veredictos/$SHA.merge"
  else
    printf 'REGISTRO-FALLO: no se pudo escribir %s/%s.merge — se reporta sin reintentar (el merge ya esta hecho)\n' "$VERDICTOS" "$SHA"
    REGISTRO="SIN registrar (ver REGISTRO-FALLO)"
  fi
  borrado_remoto
  printf 'MERGE-OK: %s (%s)\n' "$MERGE_COMMIT" "$REGISTRO"
  exit 0
}

# ------------------------------------------------- modo --revert-de (D19)
# Sin estado del hook y sin confiar en ningun JSON local: la autoridad es
# origin/<rama> + el trailer que solo pone este script + la igualdad exacta
# de arboles. NO exige reviewer, blast ni veredicto: es la inversa mecanica
# de algo ya revisado.
if [ -n "$REVERT_DE" ]; then
  PUNTA="$(git rev-parse "$ORIGEN" 2>/dev/null)" \
    || no_merge "no se pudo resolver la punta de $ORIGEN"
  [ "$PUNTA" = "$REVERT_DE" ] || no_merge "no es la punta de origin/$RAMA: la punta es $PUNTA y se pidio revertir $REVERT_DE (si algo aterrizo despues, se reporta, no se revierte)"
  git log -1 --format=%B "$REVERT_DE" 2>/dev/null | grep -Fq 'Saikit-Merge:' \
    || no_merge "sin trailer Saikit-Merge en $REVERT_DE: solo un merge de este script se revierte por aca"
  N_REV="$(git rev-list --count "$ORIGEN..HEAD")"
  [ "$N_REV" -eq 1 ] || no_merge "commit extra: el PR de revert debe traer UN commit y trae $N_REV"
  T_REVERT="$(git rev-parse 'HEAD^{tree}')"
  T_PREVIO="$(git rev-parse "$REVERT_DE"^^{tree})"
  [ "$T_REVERT" = "$T_PREVIO" ] || no_merge "arbol distinto: el revert NO es el inverso exacto de $REVERT_DE (el arbol de HEAD no es el que habia antes del merge)"
  # patch-id SOLO como comprobacion adicional: no ve cambios de whitespace,
  # que la igualdad de arboles si ve (hallazgo de CodeRabbit en el diseño).
  P1="$(git diff HEAD^ HEAD | git patch-id --stable | awk '{print $1}')"
  P2="$(git diff "$REVERT_DE^" "$REVERT_DE" | git patch-id --stable | awk '{print $1}')"
  if [ "$P1" = "$P2" ]; then
    printf 'PATCH-ID: iguales (comprobacion extra)\n'
  else
    printf 'PATCH-ID: distintos (extra informativo; la igualdad de arboles manda)\n'
  fi
  ci_chequear
  merge_final
fi

# ------------------------------------------------------------- verificacion
# rama al dia con la base (si no: merge de config.rama en la rama y CI de nuevo).
git merge-base --is-ancestor "$ORIGEN" HEAD || no_merge "base avanzada: origin/$RAMA tiene commits que esta rama no integra; merge de la base y CI de nuevo"

# un PR que toca autopilot.json JAMAS se auto-mergea (la config es la autoridad).
# El exit de git diff se exige (hallazgo de qwen): un diff que falla con salida
# vacia no puede pasar por "no toca la config".
ARCHIVOS_PR="$(git diff --name-only "$ORIGEN...HEAD")" \
  || no_merge "no se pudo listar los archivos del PR (git diff fallo)"
if printf '%s\n' "$ARCHIVOS_PR" | grep -Fxq '.saikit/autopilot.json'; then
  no_merge "el PR toca .saikit/autopilot.json: la config no se autoreescribe via merge"
fi

# commits del rango: no vacio y solo del user.email local o de la cuenta de gh
# (asi se observa "solo commits de la task"; hallazgo de grok: "autor ajeno"
# sin definir bloqueaba al propio usuario).
EMAIL_LOCAL="$(git config user.email)"
N_COMMITS="$(git rev-list --count "$ORIGEN..HEAD")"
[ "$N_COMMITS" -gt 0 ] || no_merge "no hay commits en el rango origin/$RAMA..HEAD"
while IFS=' ' read -r csha email; do
  [ -n "$csha" ] || continue
  case "$email" in
    "$EMAIL_LOCAL"|"$LOGIN@users.noreply.github.com"|*"+$LOGIN@users.noreply.github.com") continue ;;
    *) no_merge "commit de otro email: $csha es de $email" ;;
  esac
done <<< "$(git log --format='%H %ae' "$ORIGEN..HEAD")"

# ------------------------------------------------- recibo de entrega (A2/A3)
# La autoridad es el PR: ultimo APPROVE lead <sha> aplicable + validacion de
# estructura y relaciones. Sin estado de sesion: ni agents_seen, ni sello, ni
# evidence log. Los motivos ya vienen con el prefijo "recibo:" de la lib.
recibo_tmp="$(mktemp "${TMPDIR:-/tmp}/saikit-recibo-XXXXXX")" \
  || no_merge "no se pudo crear el temporal del recibo"
if ! motivo="$(entrega_recibo_del_pr "$REPO_GH" "$PR" "$SHA" "$LOGIN" 2>&1 >"$recibo_tmp")"; then
  rm -f "$recibo_tmp"
  no_merge "$motivo"
fi
if [ ! -s "$recibo_tmp" ]; then
  rm -f "$recibo_tmp"
  no_merge "recibo vacio del PR $REPO_GH#$PR para $SHA"
fi
if ! motivo="$(entrega_validar "$recibo_tmp" "$REPO_GH" "$PR" "$SHA" 2>&1)"; then
  rm -f "$recibo_tmp"
  no_merge "$motivo"
fi
recibo_txt="$(cat "$recibo_tmp")" \
  || { rm -f "$recibo_tmp"; no_merge "no se pudo releer el recibo validado"; }
recibo_flat="$(saikit_json_flat "$recibo_txt")"
CI_WORKFLOW="$(entrega_flat_hoja "$recibo_flat" "ci.workflow")" \
  || { rm -f "$recibo_tmp"; no_merge "recibo: falta ci.workflow"; }
rm -f "$recibo_tmp"

ci_chequear "$CI_WORKFLOW"

# A5: el head puede moverse mientras corre el gate (push durante la
# comprobacion): se re-lee el PR justo antes del efecto y se exige el MISMO
# sha. --match-head-commit protege el merge mismo; esto nombra la causa.
pr_leer
[ "$PR_HEAD" = "$SHA" ] || no_merge "el head del PR avanzo durante la comprobacion ($PR_HEAD != $SHA)"

merge_final
