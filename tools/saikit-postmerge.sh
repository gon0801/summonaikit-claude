#!/usr/bin/env bash
# tools/saikit-postmerge.sh - Task 18.5 (D19 REDUCIDA por la decision del
# operador del 2026-08-30): aviso post-merge, NUNCA revert automatico.
#
# QUE HACE. Tras un merge confirmado por el operador, mira el run del
# merge_commit y la salud_url de la config y le DICE al operador si algo se
# rompio, con el comando de revert listo para copiar. NO ejecuta nada que
# cambie el arbol: ni git revert, ni push, ni gh pr merge. Lo que se pierde
# se declara: si el operador no mira el aviso, nada deshace el cambio solo.
#
# Corre en un turno DESARMADO (sin estado del hook): la autoridad es
# origin/<rama> + el trailer que solo pone tools/saikit-merge.sh, igual que
# el modo --revert-de de ese script.
#
#   1. fetch origin <rama>; la config se lee de origin/<rama> (nunca del
#      working tree): salud_url y telegram.
#   2. El merge_commit tiene que existir, llevar el trailer 'Saikit-Merge:'
#      y SER la punta de origin/<rama>. Si no, el aviso lo dice y NO se
#      ofrece revert (un revert a ciegas desharia trabajo ajeno).
#   3. Run por `gh run list --commit <merge_commit>`: vacio o pendiente =>
#      UNKNOWN con heartbeat acotado (SAIKIT_POSTMERGE_TIMEOUT_SEG, default
#      60; 0 = una sola lectura); concluido != success => ROJO.
#   4. GET a salud_url si hay: solo http(s), sin redirects, --max-time
#      (SAIKIT_POSTMERGE_SALUD_SEG, default 10). 2xx => ok; otra cosa o
#      fallo de curl => ROJO.
#   5. Mensaje en espanol, redactado (lib/redactar.sh), de a lo mas 4096
#      chars. telegram-send SOLO con telegram: true en la config.
#
# USO:
#   tools/saikit-postmerge.sh --merge-commit <sha> [--rama <rama>] [--pr <n>]
#
# Exit: 0 VERDE; 1 ROJO avisado (con bloque PARA REVERTIR); 2 no evaluable
# (uso, config, o merge_commit ajeno: sin trailer o no es la punta);
# 3 UNKNOWN (sin run aun, CI pendiente, o salud no observable).
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib/veredicto_contract.sh"   # saikit_json_* (sin jq)
. "$HERE/lib/redactar.sh"             # redactar (secretos fuera del aviso)

TIMEOUT_SEG="${SAIKIT_POSTMERGE_TIMEOUT_SEG:-60}"
REINTENTO_SEG="${SAIKIT_POSTMERGE_REINTENTO_SEG:-10}"
SALUD_SEG="${SAIKIT_POSTMERGE_SALUD_SEG:-10}"
MAX_MENSAJE=4096

MC=""; RAMA=""; PR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --merge-commit) MC="${2:-}"; shift 2 ;;
    --rama)         RAMA="${2:-}"; shift 2 ;;
    --pr)           PR="${2:-}"; shift 2 ;;
    -h|--help)      sed -n '2,40p' "$0"; exit 0 ;;
    *) printf 'saikit-postmerge: opcion desconocida: %s\n' "$1" >&2; exit 2 ;;
  esac
done
[ -n "$MC" ] || { printf 'saikit-postmerge: falta --merge-commit <sha>\n' >&2; exit 2; }

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" \
  || { printf 'saikit-postmerge: el cwd no es un repo git\n' >&2; exit 2; }
cd "$ROOT" || exit 2
if [ -z "$RAMA" ]; then
  RAMA="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" \
    || { printf 'saikit-postmerge: no se pudo derivar la rama; pasa --rama\n' >&2; exit 2; }
  [ "$RAMA" != "HEAD" ] || { printf 'saikit-postmerge: HEAD detached; pasa --rama\n' >&2; exit 2; }
fi
ORIGEN="origin/$RAMA"

aviso() {  # $1=codigo $2...=lineas - imprime redactado y truncado
  local codigo="$1"; shift
  local texto
  texto="$(printf '%s\n' "$@")"
  texto="$(redactar "$texto")"
  # El cuerpo se trunca con holgura bajo los 4096 del contrato (el prefijo
  # "CODIGO: " y el salto final tambien cuentan para el que mide la salida).
  texto="${texto:0:$((MAX_MENSAJE - 16))}"
  printf '%s: %s\n' "$codigo" "$texto"
}

# ------------------------------------------------- fetch + config (D15)
git fetch -q origin "$RAMA" 2>/dev/null \
  || { aviso UNKNOWN "no se pudo hacer git fetch origin $RAMA; sin la punta no se observa nada (reintenta a mano)"; exit 3; }
CFG_RAW="$(git show "$ORIGEN:.saikit/autopilot.json" 2>/dev/null)" \
  || { printf 'saikit-postmerge: config ausente: no hay .saikit/autopilot.json en %s\n' "$ORIGEN" >&2; exit 2; }
saikit_json_valido "$CFG_RAW" \
  || { printf 'saikit-postmerge: config invalida: .saikit/autopilot.json en %s no es JSON valido\n' "$ORIGEN" >&2; exit 2; }
SALUD="$(saikit_json_get "$CFG_RAW" salud_url)" || SALUD="<null>"
TG="$(saikit_json_get "$CFG_RAW" telegram)" || TG="false"

# ------------------------------------------------- el commit es nuestro?
git cat-file -e "$MC" 2>/dev/null \
  || { printf 'saikit-postmerge: el merge_commit %s no existe en este repo\n' "$MC" >&2; exit 2; }
if ! git log -1 --format=%B "$MC" 2>/dev/null | grep -Fq 'Saikit-Merge:'; then
  aviso AVISO "el commit $MC no trae el trailer 'Saikit-Merge:': no es un merge del autopilot. No se ofrece revert; si hay que deshacerlo, a mano y con criterio."
  exit 2
fi
PUNTA="$(git rev-parse "$ORIGEN" 2>/dev/null)" \
  || { aviso UNKNOWN "no se pudo resolver la punta de $ORIGEN"; exit 3; }
[ "$PUNTA" = "$MC" ] || {
  aviso AVISO "el commit $MC ya no es la punta de $ORIGEN (la punta es $PUNTA): algo aterrizo despues. Revertir a ciegas desharia trabajo ajeno, asi que no se ofrece revert; mira que cambio y deshaz a mano."
  exit 2
}

# ------------------------------------------------- run del merge_commit
RUNS_RAW=""
esperado_fin=$(( $(date +%s) + TIMEOUT_SEG ))
while :; do
  RUNS_RAW="$(gh run list --commit "$MC" --json status,conclusion 2>/dev/null)" \
    || { aviso UNKNOWN "gh run list fallo para $MC; sin el run no se observa nada"; exit 3; }
  saikit_json_valido "$RUNS_RAW" \
    || { aviso UNKNOWN "gh run list devolvio algo que no es JSON"; exit 3; }
  FLAT="$(saikit_json_flat "$RUNS_RAW")"
  n=0; pendientes=0; rojos=""
  while :; do
    ev_st="$(printf '%s\n' "$FLAT" | awk -F'\t' -v p="[$n].status" '$1 == p { print $2; exit }')"
    [ -n "$ev_st" ] || break
    if [ "$ev_st" != "completed" ]; then
      pendientes=$((pendientes + 1))
    else
      conc="$(printf '%s\n' "$FLAT" | awk -F'\t' -v p="[$n].conclusion" '$1 == p { print $2; exit }')"
      [ "$conc" = "success" ] || rojos="$rojos [$n]=$conc"
    fi
    n=$((n + 1))
  done
  if [ "$n" -eq 0 ] || [ "$pendientes" -gt 0 ]; then
    [ "$(date +%s)" -lt "$esperado_fin" ] || break
    sleep "$REINTENTO_SEG"
    continue
  fi
  break
done

ROJO_MOTIVO=""
if [ "$n" -eq 0 ]; then
  aviso UNKNOWN "sin run aun para $MC en $ORIGEN: el CI todavia no arranca o el commit no disparo workflow. Vuelve a mirar en unos minutos con: tools/saikit-postmerge.sh --merge-commit $MC --rama $RAMA"
  exit 3
fi
if [ "$pendientes" -gt 0 ]; then
  aviso UNKNOWN "CI pendiente para $MC ($pendientes run(s) sin concluir). Vuelve a mirar con: tools/saikit-postmerge.sh --merge-commit $MC --rama $RAMA"
  exit 3
fi
[ -z "$rojos" ] || ROJO_MOTIVO="CI rojo en $MC:$rojos"

# ------------------------------------------------- salud
SALUD_TXT="sin URL de salud en la config (n/a)"
if [ "$SALUD" != "<null>" ] && [ -n "$SALUD" ]; then
  case "$SALUD" in
    http://*|https://*) ;;
    *) printf 'saikit-postmerge: salud_url con esquema no http(s): %s\n' "$SALUD" >&2; exit 2 ;;
  esac
  command -v curl >/dev/null 2>&1 \
    || { aviso UNKNOWN "hay salud_url pero no hay curl en este host: la salud no es observable"; exit 3; }
  codigo="$(curl -sS -o /dev/null -w '%{http_code}' --max-time "$SALUD_SEG" -- "$SALUD" 2>/dev/null)"
  rc_curl=$?
  if [ "$rc_curl" -ne 0 ]; then
    ROJO_MOTIVO="${ROJO_MOTIVO:+$ROJO_MOTIVO; }la salud no responde (curl rc=$rc_curl)"
    SALUD_TXT="salud CAIDA (curl rc=$rc_curl)"
  elif printf '%s' "$codigo" | grep -Eq '^2'; then
    SALUD_TXT="salud ok (http $codigo)"
  else
    ROJO_MOTIVO="${ROJO_MOTIVO:+$ROJO_MOTIVO; }la salud devolvio http $codigo"
    SALUD_TXT="salud CAIDA (http $codigo)"
  fi
fi

corto="$(printf '%s' "$MC" | cut -c1-12)"

# ------------------------------------------------- veredicto
if [ -z "$ROJO_MOTIVO" ]; then
  MENSAJE="merge $MC en $ORIGEN: VERDE. CI en success; $SALUD_TXT. Nada que deshacer."
  aviso VERDE "$MENSAJE"
  rc=0
else
  MENSAJE="merge $MC en $ORIGEN: ROJO ($ROJO_MOTIVO). $SALUD_TXT. Este script NO revierte solo: abajo va el comando listo para copiar."
  BLOQUE="PARA REVERTIR (copiar y pegar; este script NO lo ejecuto):
  git fetch origin $RAMA
  git checkout -b revert-$corto $ORIGEN
  git revert $MC
  git push -u origin revert-$corto
  gh pr create --base $RAMA --title \"Revert $corto\" --body \"Revert de $MC ($ROJO_MOTIVO)\"
  tools/saikit-merge.sh --revert-de $MC   # solo con tu si; repite el gate"
  aviso ROJO "$MENSAJE" "" "$BLOQUE"
  rc=1
fi

# ------------------------------------------------- telegram (solo opt-in)
if [ "$TG" = "true" ]; then
  if command -v telegram-send >/dev/null 2>&1; then
    telegram-send "${MENSAJE:0:$MAX_MENSAJE}" >/dev/null 2>&1 \
      || printf 'TELEGRAM-FALLO: telegram-send no pudo enviar (el aviso de arriba sigue valiendo)\n'
  else
    printf 'TELEGRAM: pendiente a mano (telegram: true pero telegram-send no esta en el PATH)\n'
  fi
fi
exit "$rc"
