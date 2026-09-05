#!/usr/bin/env bash
# tools/saikit-merge.sh — Task 18.4 (D18 + D19): gate de merge fail-closed
# y acotado del autopilot. SEGUNDA excepcion declarada al fail-open del
# harness (la primera es el instalador): mergear es la accion que no admite
# "dejar pasar", asi que TODO unknown rechaza y NOMBRA la razon.
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
#                                         # CI verde, veredicto sellado) y si
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
#
# EL MERGE, cuando toca: `gh pr merge --squash --match-head-commit <sha>
# --body "Saikit-Merge: <sha>"` SIN --delete-branch (el borrado remoto es un
# paso aparte; si falla se reporta sin reintentar). NUNCA --admin, nunca
# force. El merge_commit se registra en .saikit/veredictos/<sha>.merge — el
# veredicto sellado no se toca JAMAS (escribirlo ahi invalidaria el propio
# veredicto_sha256; hallazgo de CodeRabbit en el diseño).
#
# ESTADO DE SESION DEL HOOK (punto de diseño de 18.4, RESUELTO y DECLARADO):
# el gate exige cruzar `agents_seen`, `veredicto_sha256` y el
# harness-evidence.log del estado de SESION que escribe el hook en
#   <estado_root>/<host>/<cksum(project_root)>/<session_id>/harness-state.env
# Este script corre como tool Bash y NO conoce su session_id (no viaja en el
# entorno del proceso). REGLA EXPLICITA: se buscan TODOS los
# harness-state.env del proyecto (hosts/*/<key>/*/) que tengan
# veredicto_sha256 y se toma el de mtime MAS RECIENTE. Es determinista en la
# practica (la sesion viva acaba de sellar) y falla CERRADO en el caso
# ambiguo: si elige la sesion equivocada, el veredicto_sha256 de esa sesion
# no calza con el archivo actual y el gate rechaza. LIMITES DECLARADOS: (a)
# dos sesiones vivas del MISMO proyecto con veredictos sellados a la vez se
# resuelven por mtime y la perdedora no puede mergear hasta ser la mas
# reciente; (b) el cksum se computa sobre `pwd -P` del toplevel, la misma
# forma fisica que el hook canonicaliza — si el hook corrio desde una ruta
# distinta (p.ej. C:\ en Windows vs /c/), el estado no se encuentra y el gate
# falla cerrado con "sin estado del hook". Override para auditoria/tests:
# SAIKIT_ESTADO_ROOT (default ~/.claude/hooks/state, el HOOK_DIR del perfil).
#
# El delay del reintento de mergeable UNKNOWN es SAIKIT_MERGE_RETRY_SEG
# (default 3; los tests lo ponen en 0).
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib/veredicto_contract.sh"   # esquema del veredicto + parser JSON (sin jq)

CONFIRMADO=0
DRY_RUN=0
REVERT_DE=""

uso() { sed -n '2,44p' "$0"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --confirmado) CONFIRMADO=1; shift ;;
    --dry-run)    DRY_RUN=1; shift ;;
    --revert-de)
      [ $# -ge 2 ] || { printf 'saikit-merge: --revert-de exige un merge_commit\n' >&2; exit 2; }
      REVERT_DE="$2"; shift 2 ;;
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
  || no_merge "gh repo view devolvio algo inesperado: $REPO_GH_RAW"
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
  local raw flat i n hay_pr ev st conc
  raw="$(gh run list --commit "$SHA" --json event,status,conclusion 2>/dev/null)" \
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
  i=0
  while [ "$i" -lt "$n" ]; do
    ev="$(jget "[$i].event")"
    if [ "$hay_pr" = 1 ] && [ "$ev" != "pull_request" ]; then i=$((i + 1)); continue; fi
    st="$(jget "[$i].status")"
    if [ "$st" != completed ]; then no_merge "CI pendiente: el run $i no concluyo (status $st)"; fi
    conc="$(jget "[$i].conclusion")"
    if [ "$conc" != success ]; then no_merge "CI rojo: el run $i concluyo $conc"; fi
    i=$((i + 1))
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
    printf 'LISTO:   tools/saikit-merge.sh --confirmado\n'
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

ci_chequear

# ------------------------------------------------- veredicto sellado (D16)
VEREDICTO="$VERDICTOS/$SHA.json"
if [ ! -f "$VEREDICTO" ]; then
  # hay veredicto para un ANCESTRO del HEAD? => commits posteriores al sello.
  for otro in "$VERDICTOS"/*.json; do
    [ -f "$otro" ] || continue
    osha="$(saikit_json_get "$(cat "$otro")" sha 2>/dev/null)" || continue
    if git merge-base --is-ancestor "$osha" HEAD 2>/dev/null; then
      no_merge "commits despues del veredicto: hay veredicto para $osha pero HEAD avanzo a $SHA"
    fi
  done
  no_merge "sin veredicto para $SHA en $VERDICTOS"
fi
if ! val_out="$(veredicto_validar "$VEREDICTO" "$SHA")"; then
  no_merge "veredicto de otro sha (o esquema invalido): $val_out"
fi
V_TXT="$(cat "$VEREDICTO")"
V_VERIFIER="$(saikit_json_get "$V_TXT" verifier)"
V_REVIEWER="$(saikit_json_get "$V_TXT" reviewer)"
V_VA_RES="$(saikit_json_get "$V_TXT" verify_app.resultado)"
V_VA_CMD="$(saikit_json_get "$V_TXT" verify_app.comando)"
V_BL_NIVEL="$(saikit_json_get "$V_TXT" blast.nivel)"
V_BL_CMD="$(saikit_json_get "$V_TXT" blast.comando)"
[ "$V_VERIFIER" = "PASS" ] || no_merge "verifier: FAIL (el veredicto dice $V_VERIFIER)"
[ "$V_REVIEWER" = "clean" ] || no_merge "reviewer con findings (el veredicto dice $V_REVIEWER)"
if ! [ "$V_BL_NIVEL" -ge 4 ] 2>/dev/null; then
  no_merge "blast.nivel < 4 (dio ${V_BL_NIVEL:-vacio})"
fi
if [ "$V_VA_RES" = "PASS" ]; then
  if ! printf '%s' "$V_VA_CMD" | grep -q -- 'verify/'; then
    no_merge "verify/ fuera de lugar: el comando del drive no esta bajo verify/ (${V_VA_CMD:-vacio})"
  fi
elif [ "$V_VA_RES" = "n/a" ]; then
  if [ "$CFG_SIN_VERIFY_APP" != "true" ]; then
    no_merge "verify_app n/a sin sin_verify_app: la config no autoriza mergear sin prueba de la app"
  fi
else
  no_merge "verify_app con resultado distinto de PASS/n/a: $V_VA_RES"
fi

# --------------------------------------- cruce con el estado del hook (D18)
# Regla del punto de diseño: ver cabecera. Fail-closed: sin estado, no merge.
estado_encontrar() {
  local key f m best_m=-1
  ESTADO_FILE=""
  key="$(printf '%s' "$PROJECT_ROOT" | cksum | cut -d' ' -f 1)"
  for f in "${SAIKIT_ESTADO_ROOT:-$HOME/.claude/hooks/state}"/*/"$key"/*/harness-state.env; do
    [ -f "$f" ] || continue
    grep -q '^veredicto_sha256=' "$f" 2>/dev/null || continue
    m="$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || printf '0')"
    if [ "$m" -gt "$best_m" ]; then best_m="$m"; ESTADO_FILE="$f"; fi
  done
  if [ -z "$ESTADO_FILE" ]; then
    no_merge "sin estado del hook: no hay harness-state.env con veredicto_sha256 para este proyecto (¿corrio el sello en otra sesion o desde otra ruta?)"
  fi
}
estado_encontrar
AGENTS_SEEN="$(sed -n 's/^agents_seen=//p' "$ESTADO_FILE")"
printf ',%s,' "$AGENTS_SEEN" | grep -q ',reviewer,' \
  || no_merge "el reviewer no paso por esta sesion (agents_seen: ${AGENTS_SEEN:-vacio})"
SELLO="$(sed -n 's/^veredicto_sha256=//p' "$ESTADO_FILE")"
hash_actual="$(sha256sum "$VEREDICTO" | cut -d' ' -f 1)"
[ "$SELLO" = "$hash_actual" ] \
  || no_merge "veredicto reescrito tras el sello: el sha256 del archivo actual ($hash_actual) no es el sellado ($SELLO)"
EVID_LOG="$(dirname "$ESTADO_FILE")/harness-evidence.log"
[ -f "$EVID_LOG" ] || no_merge "sin harness-evidence.log en la sesion del sello"
awk -v c="$V_BL_CMD" 'index($0, "verified: ") == 1 && index($0, c) > 0 { ok = 1 } END { exit ok ? 0 : 1 }' "$EVID_LOG" \
  || no_merge "el comando del blast no aparece con exito en harness-evidence.log ($V_BL_CMD)"

merge_final
