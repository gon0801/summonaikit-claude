#!/usr/bin/env bash
# tests/test_saikit_merge.sh — Task 18.4: tools/saikit-merge.sh fail-closed y
# acotado (D18) + modo --revert-de (D19).
#
# QUE AFIRMA (DoD de la fila 18.4, columna 3 de Plans.md):
#   - Feliz: todo ok => NO mergea por defecto, reporta LISTO. Con
#     --confirmado => merge squash con --match-head-commit, body
#     "Saikit-Merge: <sha>", SIN --delete-branch y SIN --admin; el veredicto
#     sellado queda byte-identico; registra .saikit/veredictos/<sha>.merge.
#     Config con rama:main funciona igual.
#   - NO mergea y NOMBRA la razon: CI rojo / sin checks / pendiente /
#     mergeable UNKNOWN dos veces / base avanzada / veredicto de otro sha /
#     veredicto reescrito tras el sello / commits despues del veredicto /
#     blast.nivel<4 / verifier FAIL / verify_app n/a sin sin_verify_app /
#     comando fuera de verify/ / config ausente / merge_despliega unknown /
#     PR que toca autopilot.json / PR de otra rama base / repo distinto /
#     autor != cuenta / commit de otro email / sin estado del hook /
#     reviewer no visto.
#   - Decision 2026-08-30: --confirmado REPITE el gate; si la base movio
#     entre el LISTO y el si, vuelve a NO-MERGE y no mergea.
#   - Merge ok + borrado remoto falla => reporta SIN reintentar.
#   - --revert-de: inverso exacto de la punta con trailer => mergea; arbol
#     distinto (incl. solo-whitespace, que patch-id no ve) / commit extra /
#     sin trailer / no es la punta => NO.
#
# INFRAESTRUCTURA: git REAL en sandbox (origin bare local alcanzado via
# url.<path>.insteadOf de la URL github que espera el script) y gh FALSO que
# responde solo las formas que el script usa, con argv grabado en un log. El
# estado del hook se siembra a mano con la MISMA derivacion que hace el hook
# (state/<host>/<cksum(project_root)>/<sesion>/harness-state.env); el sello
# en si ya lo prueba tests/test_veredicto_contract.sh.
#
# La mitad mutation-test vive al final: cada mutacion del script tiene que
# poner rojo al caso que la nombra; una mutacion que sobrevive en verde es un
# hueco y rompe esta suite.
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
MERGE="$repo/tools/saikit-merge.sh"

fail=0
CASO_ROJO=0
_mal()      { printf '      FAIL: %s\n' "$1"; CASO_ROJO=1; }
_contiene() { if ! printf '%s' "$2" | grep -Fq -- "$3"; then _mal "$1: no contiene [$3]"; fi; }
_no_contiene() { if printf '%s' "$2" | grep -Fq -- "$3"; then _mal "$1: contiene [$3] y no deberia"; fi; }

SB=""
OUT=""
RC=0
BASE_RAMA="master"

caso() { printf '  caso: %s\n' "$1"; CASO_ROJO=0; sb_reset master; }
fin_caso() {
  if [ "$CASO_ROJO" -ne 0 ]; then
    printf '    ROJO: %s\n' "$1" >&2
    fail=1
  else
    printf '    ok: %s\n' "$1"
  fi
}

# ------------------------------------------------------------------ sandbox
# sb_reset <rama-base>: monta work + origin bare + gh falso + estado del hook
# + veredicto sellado, todo consistente con el HEAD de feat/task.
sb_reset() {
  local rama_base="${1:-master}"
  BASE_RAMA="$rama_base"
  [ -n "$SB" ] && rm -rf "$SB"
  SB="$(mktemp -d "${TMPDIR:-/tmp}/saikit-merge-XXXXXX")" || exit 1
  git init --bare -q "$SB/origin.git"
  git clone -q "$SB/origin.git" "$SB/work" 2>/dev/null
  cd "$SB/work" || exit 1
  git symbolic-ref HEAD "refs/heads/$rama_base"
  git config user.email op@example.com
  git config user.name op
  # El script deriva el repo de la URL de origin; el sandbox usa un bare
  # local alcanzado via insteadOf para que la URL SEA la github esperada.
  git config "url.$SB/origin.git.insteadOf" "https://github.com/op/sandbox.git"
  git remote set-url origin "https://github.com/op/sandbox.git"

  mkdir -p .saikit
  printf '{"merge":true,"merge_despliega":"no","salud_url":null,"revert_si_rojo":true,"rama":"%s","sin_verify_app":false,"telegram":false}\n' "$rama_base" > .saikit/autopilot.json
  git add .saikit/autopilot.json
  printf 'app v1\n' > app.sh
  git add app.sh
  git commit -qm "chore: base"
  git push -q origin "$rama_base"

  git checkout -qb feat/task
  printf 'app v2\n' >> app.sh
  git commit -qam "feat: task"
  git push -q origin feat/task

  mkdir -p "$SB/bin" "$SB/ghfix"
  cat > "$SB/bin/gh" <<'GHEOF'
#!/usr/bin/env bash
# gh falso del banco de la 18.4: responde SOLO las formas que usa
# tools/saikit-merge.sh, con el argv grabado para que los casos assertionen
# sobre el comando exacto que se disparo.
set -u
[ -n "${SAIKIT_GH_LOG:-}" ] && printf 'gh %s\n' "$*" >> "$SAIKIT_GH_LOG"
fix="${SAIKIT_GH_FIX:?}"
case "$1 $2" in
  "repo view") cat "$fix/repo.json"; exit 0 ;;
  "api user")  cat "$fix/user.json"; exit 0 ;;
  "run list")  cat "$fix/runs.json"; exit 0 ;;
  "pr view")
    case "$*" in *mergeCommit*) cat "$fix/pr-merge.json" ;; *) cat "$fix/pr.json" ;; esac
    exit 0 ;;
  "pr merge")
    if [ -f "$fix/merge-fail" ]; then cat "$fix/merge-fail"; exit 1; fi
    [ -n "${SAIKIT_ORDEN_LOG:-}" ] && printf 'merge\n' >> "$SAIKIT_ORDEN_LOG"
    exit 0 ;;
esac
printf 'gh-falso: forma no soportada: %s\n' "$*" >&2
exit 1
GHEOF
  chmod +x "$SB/bin/gh"
  export SAIKIT_GH_FIX="$SB/ghfix"
  export SAIKIT_GH_LOG="$SB/gh.log"
  : > "$SAIKIT_GH_LOG"
  export SAIKIT_ESTADO_ROOT="$SB/estado"
  export SAIKIT_ORDEN_LOG="$SB/orden.log"
  : > "$SAIKIT_ORDEN_LOG"
  export SAIKIT_MERGE_RETRY_SEG=0
  export PATH="$SB/bin:$PATH"

  refix
}

# refix: re-escribe los fixtures que dependen del HEAD actual (sha del PR,
# veredicto sellado y estado del hook). Se llama tras commits nuevos.
refix() {
  SHA="$(git rev-parse HEAD)"
  printf '{"nameWithOwner":"op/sandbox"}' > "$SB/ghfix/repo.json"
  printf '{"login":"op"}' > "$SB/ghfix/user.json"
  printf '{"number":7,"baseRefName":"%s","headRefOid":"%s","author":{"login":"op"},"mergeable":"MERGEABLE"}' "$BASE_RAMA" "$SHA" > "$SB/ghfix/pr.json"
  printf '{"mergeCommit":{"oid":"f000000000000000000000000000000000000000"}}' > "$SB/ghfix/pr-merge.json"
  printf '[{"event":"pull_request","status":"completed","conclusion":"success","workflow":"ci"}]' > "$SB/ghfix/runs.json"

  mkdir -p .saikit/veredictos
  printf '{"sha":"%s","pr":7,"verifier":"PASS","verify_app":{"resultado":"PASS","comando":"bash verify/app.sh"},"blast":{"nivel":4,"hecho":"el drive de la app corre","comando":"bash tests/run.sh"},"adversary":"n/a","reviewer":"clean","decisiones":".saikit/decisiones/18.4.tsv"}' "$SHA" > ".saikit/veredictos/$SHA.json"

  local key sd
  rm -rf "$SB/estado"
  key="$(printf '%s' "$(pwd -P)" | cksum | cut -d' ' -f 1)"
  sd="$SB/estado/claude/$key/sess1"
  mkdir -p "$sd"
  {
    printf 'task_hash=h184\n'
    printf 'agents_seen=implementer,verifier,reviewer\n'
    printf 'lane=full\n'
    printf 'veredicto_sha256=%s\n' "$(sha256sum ".saikit/veredictos/$SHA.json" | cut -d' ' -f 1)"
  } > "$sd/harness-state.env"
  printf 'prompt task started: h184\nverified: bash tests/run.sh\nagent: reviewer\n' > "$sd/harness-evidence.log"
}

correr() {  # corre el script bajo prueba desde el work del sandbox
  OUT="$(bash "$MERGE" "$@" 2>&1)"
  RC=$?
}

merge_disparado() { grep -q '^gh pr merge' "$SAIKIT_GH_LOG" 2>/dev/null; }

# avanza la rama base del sandbox (para "base avanzada")
avanzar_base() {
  git checkout -q master
  printf 'app base nueva\n' >> app.sh
  git commit -qam "chore: base avanza"
  git push -q origin master
  git checkout -q feat/task
}

# ------------------------------------------------------------------ casos
caso "feliz_default_no_merguea_reporta_listo"
{
  correr
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC"
  _contiene "reporta LISTO" "$OUT" "LISTO:"
  if merge_disparado; then _mal "mergeo sin --confirmado"; fi
  [ -f ".saikit/veredictos/$SHA.merge" ] && _mal "registro .merge sin --confirmado"
}
fin_caso "feliz_default_no_merguea_reporta_listo"

caso "feliz_confirmado_merguea_con_trailer_y_match_head"
{
  h_antes="$(sha256sum ".saikit/veredictos/$SHA.json" | cut -d' ' -f 1)"
  correr --confirmado
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC"
  _contiene "merge ok" "$OUT" "MERGE-OK:"
  _contiene "squash" "$(cat "$SAIKIT_GH_LOG")" "--squash"
  _contiene "pinea el head" "$(cat "$SAIKIT_GH_LOG")" "--match-head-commit $SHA"
  _contiene "trailer en el body" "$(cat "$SAIKIT_GH_LOG")" "Saikit-Merge: $SHA"
  _no_contiene "nunca --admin" "$(cat "$SAIKIT_GH_LOG")" "--admin"
  _no_contiene "nunca --delete-branch en el merge" "$(cat "$SAIKIT_GH_LOG")" "--delete-branch"
  _contiene "registra merge_commit" "$(cat ".saikit/veredictos/$SHA.merge" 2>/dev/null)" "f000000000000000000000000000000000000000"
  _contiene "veredicto byte-identico" "$(sha256sum ".saikit/veredictos/$SHA.json" | cut -d' ' -f 1)" "$h_antes"
}
fin_caso "feliz_confirmado_merguea_con_trailer_y_match_head"

caso "feliz_rama_main_funciona_igual"
{
  # El sandbox entero montado sobre main: config rama=main, PR base main.
  CASO_ROJO=0; sb_reset main
  correr
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC"
  _contiene "reporta LISTO con rama main" "$OUT" "LISTO:"
  if merge_disparado; then _mal "mergeo sin --confirmado (rama main)"; fi
}
fin_caso "feliz_rama_main_funciona_igual"

caso "confirmado_repite_el_gate_base_movio_no_merguea"
{
  # Decision 2026-08-30: el si confirma la INTENCION, no las condiciones.
  correr
  _contiene "listo la primera vez" "$OUT" "LISTO:"
  avanzar_base
  correr --confirmado
  [ "$RC" -ne 0 ] || _mal "mergeo con la base movida tras el LISTO"
  _contiene "vuelve a NO-MERGE con la razon" "$OUT" "NO-MERGE: base avanzada"
  if merge_disparado; then _mal "mergeo pese a la base avanzada"; fi
}
fin_caso "confirmado_repite_el_gate_base_movio_no_merguea"

caso "ci_rojo_no_merguea"
{
  printf '[{"event":"pull_request","status":"completed","conclusion":"failure","workflow":"ci"}]' > "$SB/ghfix/runs.json"
  correr --confirmado
  _contiene "razon CI rojo" "$OUT" "NO-MERGE: CI rojo"
  if merge_disparado; then _mal "mergeo con CI rojo"; fi
}
fin_caso "ci_rojo_no_merguea"

caso "sin_checks_no_merguea"
{
  printf '[]' > "$SB/ghfix/runs.json"
  correr --confirmado
  _contiene "razon sin checks" "$OUT" "NO-MERGE: sin checks"
  if merge_disparado; then _mal "mergeo sin checks (no es verde)"; fi
}
fin_caso "sin_checks_no_merguea"

caso "ci_pendiente_no_merguea"
{
  printf '[{"event":"pull_request","status":"in_progress","conclusion":null,"workflow":"ci"}]' > "$SB/ghfix/runs.json"
  correr --confirmado
  _contiene "razon CI pendiente" "$OUT" "NO-MERGE: CI pendiente"
  if merge_disparado; then _mal "mergeo con CI pendiente"; fi
}
fin_caso "ci_pendiente_no_merguea"

caso "mergeable_unknown_dos_veces_no_merguea"
{
  sed -i.bak 's/"mergeable":"MERGEABLE"/"mergeable":"UNKNOWN"/' "$SB/ghfix/pr.json"
  rm -f "$SB/ghfix/pr.json.bak"
  correr --confirmado
  _contiene "razon mergeable UNKNOWN" "$OUT" "NO-MERGE: mergeable UNKNOWN"
  if merge_disparado; then _mal "mergeo con mergeable UNKNOWN"; fi
}
fin_caso "mergeable_unknown_dos_veces_no_merguea"

caso "base_avanzada_no_merguea"
{
  avanzar_base
  correr --confirmado
  _contiene "razon base avanzada" "$OUT" "NO-MERGE: base avanzada"
  if merge_disparado; then _mal "mergeo con base vieja"; fi
}
fin_caso "base_avanzada_no_merguea"

caso "veredicto_de_otro_sha_no_merguea"
{
  sed -i.bak "s/\"sha\":\"$SHA\"/\"sha\":\"otro0000000000000000000000000000000000000\"/" ".saikit/veredictos/$SHA.json"
  rm -f ".saikit/veredictos/$SHA.json.bak"
  correr --confirmado
  _contiene "razon veredicto de otro sha" "$OUT" "NO-MERGE: veredicto de otro sha"
  if merge_disparado; then _mal "mergeo con veredicto de otro sha"; fi
}
fin_caso "veredicto_de_otro_sha_no_merguea"

caso "veredicto_reescrito_tras_el_sello_no_merguea"
{
  # El archivo en disco ya no es lo que el Write del reviewer materializo:
  # el sha256 del estado ya no calza con el archivo actual.
  printf '%s' "$(cat ".saikit/veredictos/$SHA.json")" | sed 's/"reviewer":"clean"/"reviewer":"clean","extra":1/' > ".saikit/veredictos/$SHA.json.new"
  mv ".saikit/veredictos/$SHA.json.new" ".saikit/veredictos/$SHA.json"
  correr --confirmado
  _contiene "razon veredicto reescrito" "$OUT" "NO-MERGE: veredicto reescrito tras el sello"
  if merge_disparado; then _mal "mergeo con el veredicto reescrito"; fi
}
fin_caso "veredicto_reescrito_tras_el_sello_no_merguea"

caso "commits_despues_del_veredicto_no_merguea"
{
  sha_viejo="$SHA"
  printf 'app v3\n' >> app.sh
  git commit -qam "feat: un commit mas"
  git push -q origin feat/task
  refix
  # Restaurar el veredicto viejo: existe veredicto para un ancestro, pero el
  # HEAD avanzo despues del sello.
  rm -f ".saikit/veredictos/$SHA.json"
  printf '{"sha":"%s","pr":7,"verifier":"PASS","verify_app":{"resultado":"PASS","comando":"bash verify/app.sh"},"blast":{"nivel":4,"hecho":"h","comando":"bash tests/run.sh"},"adversary":"n/a","reviewer":"clean","decisiones":"d"}' "$sha_viejo" > ".saikit/veredictos/$sha_viejo.json"
  correr --confirmado
  _contiene "razon commits despues del veredicto" "$OUT" "NO-MERGE: commits despues del veredicto"
  if merge_disparado; then _mal "mergeo con commits posteriores al veredicto"; fi
}
fin_caso "commits_despues_del_veredicto_no_merguea"

caso "blast_nivel_menor_de_4_no_merguea"
{
  sed -i.bak 's/"nivel":4/"nivel":3/' ".saikit/veredictos/$SHA.json"
  rm -f ".saikit/veredictos/$SHA.json.bak"
  correr --confirmado
  _contiene "razon blast bajo" "$OUT" "NO-MERGE: blast.nivel < 4"
  if merge_disparado; then _mal "mergeo con blast.nivel < 4"; fi
}
fin_caso "blast_nivel_menor_de_4_no_merguea"

caso "verifier_fail_no_merguea"
{
  sed -i.bak 's/"verifier":"PASS"/"verifier":"FAIL"/' ".saikit/veredictos/$SHA.json"
  rm -f ".saikit/veredictos/$SHA.json.bak"
  correr --confirmado
  _contiene "razon verifier" "$OUT" "NO-MERGE: verifier: FAIL"
  if merge_disparado; then _mal "mergeo con verifier FAIL"; fi
}
fin_caso "verifier_fail_no_merguea"

caso "verify_app_na_sin_sin_verify_app_no_merguea"
{
  printf '{"sha":"%s","pr":7,"verifier":"PASS","verify_app":{"resultado":"n/a","comando":null},"blast":{"nivel":4,"hecho":"h","comando":"bash tests/run.sh"},"adversary":"n/a","reviewer":"clean","decisiones":"d"}' "$SHA" > ".saikit/veredictos/$SHA.json"
  correr --confirmado
  _contiene "razon n/a sin permiso" "$OUT" "NO-MERGE: verify_app n/a sin sin_verify_app"
  if merge_disparado; then _mal "mergeo con verify_app n/a sin sin_verify_app"; fi
}
fin_caso "verify_app_na_sin_sin_verify_app_no_merguea"

caso "drive_fuera_de_verify_no_merguea"
{
  sed -i.bak 's|"comando":"bash verify/app.sh"|"comando":"npm test"|' ".saikit/veredictos/$SHA.json"
  rm -f ".saikit/veredictos/$SHA.json.bak"
  correr --confirmado
  _contiene "razon drive fuera de verify/" "$OUT" "NO-MERGE: verify/ fuera de"
  if merge_disparado; then _mal "mergeo con el drive fuera de verify/"; fi
}
fin_caso "drive_fuera_de_verify_no_merguea"

caso "config_ausente_no_merguea"
{
  git checkout -q master
  git rm -q .saikit/autopilot.json
  git commit -qm "chore: sin config"
  git push -q origin master
  git checkout -q feat/task
  correr --confirmado
  _contiene "razon config ausente" "$OUT" "NO-MERGE: config ausente"
  if merge_disparado; then _mal "mergeo sin config"; fi
}
fin_caso "config_ausente_no_merguea"

caso "config_unknown_no_merguea"
{
  git checkout -q master
  sed -i.bak 's/"merge_despliega":"no"/"merge_despliega":"unknown"/' .saikit/autopilot.json
  rm -f .saikit/autopilot.json.bak
  git commit -qam "chore: despliega unknown"
  git push -q origin master
  git checkout -q feat/task
  correr --confirmado
  _contiene "razon merge_despliega unknown" "$OUT" "NO-MERGE: merge_despliega unknown"
  if merge_disparado; then _mal "mergeo con merge_despliega unknown"; fi
}
fin_caso "config_unknown_no_merguea"

caso "pr_toca_autopilot_json_no_merguea"
{
  sed -i.bak 's/"telegram":false/"telegram":true/' .saikit/autopilot.json
  rm -f .saikit/autopilot.json.bak
  git commit -qam "feat: toca la config"
  git push -q origin feat/task
  refix
  correr --confirmado
  _contiene "razon toca autopilot.json" "$OUT" "NO-MERGE: el PR toca .saikit/autopilot.json"
  if merge_disparado; then _mal "mergeo un PR que toca autopilot.json"; fi
}
fin_caso "pr_toca_autopilot_json_no_merguea"

caso "pr_de_otra_rama_base_no_merguea"
{
  git checkout -q master
  git checkout -qb dev-base
  git push -q origin dev-base
  git checkout -q feat/task
  # PR apunta a dev-base pero la config declara rama master.
  sed -i.bak 's/"baseRefName":"master"/"baseRefName":"dev-base"/' "$SB/ghfix/pr.json"
  rm -f "$SB/ghfix/pr.json.bak"
  correr --confirmado
  _contiene "razon otra rama base" "$OUT" "NO-MERGE: otra rama base"
  if merge_disparado; then _mal "mergeo un PR de otra rama base"; fi
}
fin_caso "pr_de_otra_rama_base_no_merguea"

caso "pr_numero_mal_no_merguea"
{
  # Hallazgo de codex (cross-review PR #142): `number` solo se exigiia no
  # vacio; un gh que devuelva una CADENA-opcion (p.ej. --repo=otro/x) llegaba
  # entero como primer argumento de `gh pr merge`. El gate exige numero.
  sed -i.bak 's/"number":7/"number":"--repo=otro\/x"/' "$SB/ghfix/pr.json"
  rm -f "$SB/ghfix/pr.json.bak"
  correr --confirmado
  _contiene "razon numero de PR" "$OUT" "NO-MERGE: gh pr view no trajo un numero de PR"
  if merge_disparado; then _mal "disparo gh pr merge con un selector inyectado"; fi
}
fin_caso "pr_numero_mal_no_merguea"

caso "repo_distinto_no_merguea"
{
  printf '{"nameWithOwner":"otro/repo"}' > "$SB/ghfix/repo.json"
  correr --confirmado
  _contiene "razon repo distinto" "$OUT" "NO-MERGE: repo distinto"
  if merge_disparado; then _mal "mergeo con gh apuntando a otro repo"; fi
}
fin_caso "repo_distinto_no_merguea"

caso "autor_distinto_de_la_cuenta_no_merguea"
{
  sed -i.bak 's/"author":{"login":"op"}/"author":{"login":"otro"}/' "$SB/ghfix/pr.json"
  rm -f "$SB/ghfix/pr.json.bak"
  correr --confirmado
  _contiene "razon autor" "$OUT" "NO-MERGE: autor del PR distinto de la cuenta"
  if merge_disparado; then _mal "mergeo un PR de otro autor"; fi
}
fin_caso "autor_distinto_de_la_cuenta_no_merguea"

caso "commit_de_otro_email_no_merguea"
{
  git -c user.email=ajeno@example.com commit -qam "feat: commit ajeno" --allow-empty
  git push -q origin feat/task
  refix
  correr --confirmado
  _contiene "razon email ajeno" "$OUT" "NO-MERGE: commit de otro email"
  if merge_disparado; then _mal "mergeo con un commit de otro email"; fi
}
fin_caso "commit_de_otro_email_no_merguea"

caso "sin_estado_del_hook_no_merguea"
{
  rm -rf "$SB/estado"
  correr --confirmado
  _contiene "razon sin estado" "$OUT" "NO-MERGE: sin estado del hook"
  if merge_disparado; then _mal "mergeo sin estado del hook"; fi
}
fin_caso "sin_estado_del_hook_no_merguea"

caso "reviewer_no_visto_en_el_estado_no_merguea"
{
  key="$(printf '%s' "$(pwd -P)" | cksum | cut -d' ' -f 1)"
  sd="$SB/estado/claude/$key/sess1"
  sed -i.bak 's/agents_seen=implementer,verifier,reviewer/agents_seen=implementer,verifier/' "$sd/harness-state.env"
  rm -f "$sd/harness-state.env.bak"
  correr --confirmado
  _contiene "razon reviewer no visto" "$OUT" "NO-MERGE: el reviewer no paso"
  if merge_disparado; then _mal "mergeo sin reviewer en agents_seen"; fi
}
fin_caso "reviewer_no_visto_en_el_estado_no_merguea"

caso "merge_ok_borrado_remoto_falla_reporta_sin_reintentar"
{
  # pre-receive del origin rechaza TODO push (incluido el --delete): el merge
  # ya ocurrio y el borrado se reporta, una sola vez, sin reintentar.
  printf '#!/bin/sh\necho delete >> "%s/orden.log"\nexit 1\n' "$SB" > "$SB/origin.git/hooks/pre-receive"
  chmod +x "$SB/origin.git/hooks/pre-receive"
  correr --confirmado
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0 (el merge salio bien), dio $RC"
  _contiene "merge ok" "$OUT" "MERGE-OK:"
  _contiene "reporta el borrado fallido" "$OUT" "BORRADO-FALLO"
  _contiene "dice que no reintenta" "$OUT" "sin reintentar"
  # Codex BAJO-5 (adjudicado): el gh falso marca "merge" y el pre-receive
  # marca "delete", ambos en orden.log — el orden de las lineas es el orden
  # de ejecucion. Una regresion que borre la rama ANTES de mergear invierte
  # las lineas y este caso la atrapa.
  orden="$(grep -h . "$SB/orden.log" 2>/dev/null || true)"
  [ "$(printf '%s\n' "$orden" | sed -n '1p')" = "merge" ] || _mal "el borrado no fue despues del merge; orden=[$orden]"
  [ "$(printf '%s\n' "$orden" | sed -n '2p')" = "delete" ] || _mal "no hubo un intento de borrado tras el merge; orden=[$orden]"
  n="$(printf '%s\n' "$orden" | grep -c delete || true)"
  [ "$n" -eq 1 ] || _mal "intentos de borrado: esperaba 1, hubo $n"
}
fin_caso "merge_ok_borrado_remoto_falla_reporta_sin_reintentar"

caso "dry_run_dice_que_haria_sin_hacerlo"
{
  correr --dry-run
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC"
  _contiene "dice que haria" "$OUT" "DRY-RUN:"
  _contiene "nombra el match-head-commit que usaria" "$OUT" "--match-head-commit $SHA"
  if merge_disparado; then _mal "el dry-run disparo un merge"; fi
}
fin_caso "dry_run_dice_que_haria_sin_hacerlo"

# ------------------------------------------------------------- --revert-de
# monta_revert: master con un squash-merge con trailer (MC), y una rama
# revert/task cuyo HEAD es el inverso exacto. Sin estado del hook a proposito:
# D19 no lo exige.
monta_revert() {  # $1 = "sin-trailer": el merge commit se crea SIN el
                   # trailer desde el arranque (rehacerlo despues dejaba el
                   # rango con 2 commits y el caso media otro check)
  sb_reset master
  rm -rf "$SB/estado"
  git checkout -q master
  printf 'app v2\n' > app.sh   # el cambio que el squash aterrizo
  if [ "${1:-}" = "sin-trailer" ]; then
    git commit -qam "feat: task (#7)"
  else
    git commit -qam "feat: task (#7)

Saikit-Merge: $SHA"
  fi
  git push -q origin master
  MC="$(git rev-parse HEAD)"
  git checkout -qb revert/task
  git revert --no-edit "$MC" >/dev/null 2>&1
  git push -q origin revert/task
  RHEAD="$(git rev-parse HEAD)"
  printf '{"number":8,"baseRefName":"master","headRefOid":"%s","author":{"login":"op"},"mergeable":"MERGEABLE"}' "$RHEAD" > "$SB/ghfix/pr.json"
}

caso "revert_inverso_exacto_merguea"
{
  monta_revert
  correr --revert-de "$MC"
  _contiene "listo" "$OUT" "LISTO:"
  if merge_disparado; then _mal "mergeo el revert sin --confirmado"; fi
  correr --revert-de "$MC" --confirmado
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC"
  _contiene "merge ok" "$OUT" "MERGE-OK:"
  _contiene "pinea el head del revert" "$(cat "$SAIKIT_GH_LOG")" "--match-head-commit $RHEAD"
  _contiene "trailer del revert" "$(cat "$SAIKIT_GH_LOG")" "Saikit-Merge: $RHEAD"
  _no_contiene "nunca --admin (revert)" "$(cat "$SAIKIT_GH_LOG")" "--admin"
}
fin_caso "revert_inverso_exacto_merguea"

caso "revert_arbol_distinto_por_whitespace_no_merguea"
{
  monta_revert
  # Cambio EXTRA solo de whitespace sobre el revert: patch-id NO lo ve, la
  # igualdad exacta de arboles SI (hallazgo de CodeRabbit). Se AMENDA para
  # seguir teniendo UN solo commit: lo que cambia es el arbol, no el conteo.
  printf ' \n' >> app.sh
  git commit -qa --amend --no-edit
  git push -qf origin revert/task
  RHEAD="$(git rev-parse HEAD)"
  printf '{"number":8,"baseRefName":"master","headRefOid":"%s","author":{"login":"op"},"mergeable":"MERGEABLE"}' "$RHEAD" > "$SB/ghfix/pr.json"
  correr --revert-de "$MC" --confirmado
  _contiene "razon arbol distinto" "$OUT" "NO-MERGE: arbol distinto"
  if merge_disparado; then _mal "mergeo un revert que no es el inverso exacto"; fi
}
fin_caso "revert_arbol_distinto_por_whitespace_no_merguea"

caso "revert_commit_extra_no_merguea"
{
  monta_revert
  printf 'otra cosa\n' > extra.sh
  git add extra.sh
  git commit -qm "feat: commit extra"
  git push -q origin revert/task
  RHEAD="$(git rev-parse HEAD)"
  printf '{"number":8,"baseRefName":"master","headRefOid":"%s","author":{"login":"op"},"mergeable":"MERGEABLE"}' "$RHEAD" > "$SB/ghfix/pr.json"
  correr --revert-de "$MC" --confirmado
  _contiene "razon commit extra" "$OUT" "NO-MERGE: commit extra"
  if merge_disparado; then _mal "mergeo un revert con commit extra"; fi
}
fin_caso "revert_commit_extra_no_merguea"

caso "revert_sin_trailer_no_merguea"
{
  monta_revert sin-trailer
  correr --revert-de "$MC" --confirmado
  _contiene "razon sin trailer" "$OUT" "NO-MERGE: sin trailer"
  if merge_disparado; then _mal "mergeo un revert de un commit sin trailer"; fi
}
fin_caso "revert_sin_trailer_no_merguea"

caso "revert_no_es_la_punta_no_merguea"
{
  monta_revert
  # Algo aterriza en master DESPUES del merge commit.
  git checkout -q master
  printf 'post\n' > post.sh
  git add post.sh
  git commit -qm "chore: algo mas aterrizo"
  git push -q origin master
  git checkout -q revert/task
  correr --revert-de "$MC" --confirmado
  _contiene "razon no es la punta" "$OUT" "NO-MERGE: no es la punta"
  if merge_disparado; then _mal "mergeo un revert de un commit que ya no es la punta"; fi
}
fin_caso "revert_no_es_la_punta_no_merguea"

caso "nunca_admin_en_el_fuente"
{
  # Complemento del assert de argv: el CODIGO del script ni siquiera
  # menciona --admin (la cabecera lo prohibe en prosa; una brega con gh que
  # salte el gate seria la via para saltarse el si del operador; D24 lo
  # niega por otra via en 18.11).
  if grep -v '^#' "$MERGE" | grep -q -- '--admin'; then
    _mal "el codigo (fuera de comentarios) menciona --admin"
  fi
}
fin_caso "nunca_admin_en_el_fuente"

cd - >/dev/null 2>&1 || true

if [ "$fail" -ne 0 ]; then
  echo "test_saikit_merge: FAIL (casos)" >&2
  exit 1
fi

# ------------------------------------------------------- mutation-test propio
# Cada mutacion rompe UNA proteccion del script; el caso que la nombra tiene
# que ponerse rojo. Si una mutacion sobrevive en verde, el test no prueba esa
# proteccion y esta suite falla (la debilidad historica del repo: tests que
# pasan igual sin el fix).
mut_sed() {  # $1=sed-expr, aplica sobre el fuente y deja el mutado en $MUTADO
  # HERE se reescribe al tools/ del repo: la copia mutada vive en el TMPDIR y
  # si no, no resuelve lib/veredicto_contract.sh y muere en el source — todas
  # las mutaciones daban "atrapadas" por no poder correr (medido midiendo el
  # hallazgo MEDIO-1 de qwen: el motivo real del rojo era el source, no el
  # caso). Un mutado que no corre no prueba nada.
  MUTADO="$SB-mutado-$$.sh"
  { sed "$1" "$MERGE"; } | sed "s|^HERE=.*$|HERE=$repo/tools|" > "$MUTADO"
}

correr_mutacion() {  # $1=nombre, $2=sed-expr, $3=funcion de caso
  local nombre="$1" expr="$2" fun="$3"
  mut_sed "$expr"
  if cmp -s "$MERGE" "$MUTADO"; then
    printf '    FAIL: mutacion %s no cambio nada — el sed quedo obsoleto\n' "$nombre" >&2
    fail=1
    return
  fi
  if ! bash -n "$MUTADO" 2>/dev/null; then
    printf '    FAIL: mutacion %s no parsea; asi no prueba nada\n' "$nombre" >&2
    fail=1
    return
  fi
  MERGE="$MUTADO"
  CASO_ROJO=0
  "$fun"
  if [ "$CASO_ROJO" -ne 0 ]; then
    printf '    mutacion %s atrapada por %s\n' "$nombre" "$fun"
  else
    printf '    FAIL: ningun caso detecto la mutacion [%s]\n' "$nombre" >&2
    fail=1
  fi
  MERGE="$repo/tools/saikit-merge.sh"
  rm -f "$MUTADO"
}

c_feliz() {
  CASO_ROJO=0; sb_reset master
  correr
  _contiene "reporta LISTO" "$OUT" "LISTO:"
  if merge_disparado; then _mal "mergeo sin --confirmado"; fi
}

c_confirmado() {
  CASO_ROJO=0; sb_reset master
  correr --confirmado
  _contiene "pinea el head" "$(cat "$SAIKIT_GH_LOG")" "--match-head-commit $SHA"
  _no_contiene "nunca --admin" "$(cat "$SAIKIT_GH_LOG")" "--admin"
}

c_ci_pendiente() {
  CASO_ROJO=0; sb_reset master
  printf '[{"event":"pull_request","status":"in_progress","conclusion":null,"workflow":"ci"}]' > "$SB/ghfix/runs.json"
  correr --confirmado
  _contiene "razon CI pendiente" "$OUT" "NO-MERGE: CI pendiente"
  if merge_disparado; then _mal "mergeo con CI pendiente"; fi
}

c_ci_rojo() {
  CASO_ROJO=0; sb_reset master
  printf '[{"event":"pull_request","status":"completed","conclusion":"failure","workflow":"ci"}]' > "$SB/ghfix/runs.json"
  correr --confirmado
  _contiene "razon CI rojo" "$OUT" "NO-MERGE: CI rojo"
  if merge_disparado; then _mal "mergeo con CI rojo"; fi
}

c_base_avanzada() {
  CASO_ROJO=0; sb_reset master
  avanzar_base
  correr --confirmado
  _contiene "razon base avanzada" "$OUT" "NO-MERGE: base avanzada"
  if merge_disparado; then _mal "mergeo con base vieja"; fi
}

c_reescrito() {
  CASO_ROJO=0; sb_reset master
  printf '%s' "$(cat ".saikit/veredictos/$SHA.json")" | sed 's/"reviewer":"clean"/"reviewer":"clean","extra":1/' > ".saikit/veredictos/$SHA.json.new"
  mv ".saikit/veredictos/$SHA.json.new" ".saikit/veredictos/$SHA.json"
  correr --confirmado
  _contiene "razon veredicto reescrito" "$OUT" "NO-MERGE: veredicto reescrito tras el sello"
  if merge_disparado; then _mal "mergeo con el veredicto reescrito"; fi
}

c_verify_na() {
  CASO_ROJO=0; sb_reset master
  printf '{"sha":"%s","pr":7,"verifier":"PASS","verify_app":{"resultado":"n/a","comando":null},"blast":{"nivel":4,"hecho":"h","comando":"bash tests/run.sh"},"adversary":"n/a","reviewer":"clean","decisiones":"d"}' "$SHA" > ".saikit/veredictos/$SHA.json"
  correr --confirmado
  _contiene "razon n/a sin permiso" "$OUT" "NO-MERGE: verify_app n/a sin sin_verify_app"
  if merge_disparado; then _mal "mergeo con verify_app n/a sin sin_verify_app"; fi
}

c_verify_ruta() {
  CASO_ROJO=0; sb_reset master
  sed -i.bak 's|"comando":"bash verify/app.sh"|"comando":"npm test"|' ".saikit/veredictos/$SHA.json"
  rm -f ".saikit/veredictos/$SHA.json.bak"
  correr --confirmado
  _contiene "razon drive fuera de verify/" "$OUT" "NO-MERGE: verify/ fuera de"
  if merge_disparado; then _mal "mergeo con el drive fuera de verify/"; fi
}

c_rama_base() {
  CASO_ROJO=0; sb_reset master
  git checkout -q master
  git checkout -qb dev-base
  git push -q origin dev-base
  git checkout -q feat/task
  sed -i.bak 's/"baseRefName":"master"/"baseRefName":"dev-base"/' "$SB/ghfix/pr.json"
  rm -f "$SB/ghfix/pr.json.bak"
  correr --confirmado
  _contiene "razon otra rama base" "$OUT" "NO-MERGE: otra rama base"
  if merge_disparado; then _mal "mergeo un PR de otra rama base"; fi
}

c_email() {
  CASO_ROJO=0; sb_reset master
  git -c user.email=ajeno@example.com commit -qam "feat: commit ajeno" --allow-empty
  git push -q origin feat/task
  refix
  correr --confirmado
  _contiene "razon email ajeno" "$OUT" "NO-MERGE: commit de otro email"
  if merge_disparado; then _mal "mergeo con un commit de otro email"; fi
}

c_sin_estado() {
  CASO_ROJO=0; sb_reset master
  rm -rf "$SB/estado"
  correr --confirmado
  _contiene "razon sin estado" "$OUT" "NO-MERGE: sin estado del hook"
  if merge_disparado; then _mal "mergeo sin estado del hook"; fi
}

c_borrado() {
  CASO_ROJO=0; sb_reset master
  printf '#!/bin/sh\necho delete >> "%s/orden.log"\nexit 1\n' "$SB" > "$SB/origin.git/hooks/pre-receive"
  chmod +x "$SB/origin.git/hooks/pre-receive"
  correr --confirmado
  _contiene "reporta el borrado fallido" "$OUT" "BORRADO-FALLO"
  n="$(grep -c delete "$SB/orden.log" 2>/dev/null || true)"
  [ "$n" -eq 1 ] || _mal "intentos de borrado: esperaba 1, hubo ${n:-0}"
}

c_verifier_fail() {
  CASO_ROJO=0; sb_reset master
  sed -i.bak 's/"verifier":"PASS"/"verifier":"FAIL"/' ".saikit/veredictos/$SHA.json"
  rm -f ".saikit/veredictos/$SHA.json.bak"
  correr --confirmado
  _contiene "razon verifier" "$OUT" "NO-MERGE: verifier: FAIL"
  if merge_disparado; then _mal "mergeo con verifier FAIL"; fi
}

c_autor() {
  CASO_ROJO=0; sb_reset master
  sed -i.bak 's/"author":{"login":"op"}/"author":{"login":"otro"}/' "$SB/ghfix/pr.json"
  rm -f "$SB/ghfix/pr.json.bak"
  correr --confirmado
  _contiene "razon autor" "$OUT" "NO-MERGE: autor del PR distinto de la cuenta"
  if merge_disparado; then _mal "mergeo un PR de otro autor"; fi
}

c_revert_trailer() {
  CASO_ROJO=0; monta_revert sin-trailer
  correr --revert-de "$MC" --confirmado
  _contiene "razon sin trailer" "$OUT" "NO-MERGE: sin trailer"
  if merge_disparado; then _mal "mergeo un revert de un commit sin trailer"; fi
}

c_revert_arbol() {
  CASO_ROJO=0; monta_revert
  printf ' \n' >> app.sh
  git commit -qa --amend --no-edit
  git push -q origin revert/task
  RHEAD="$(git rev-parse HEAD)"
  printf '{"number":8,"baseRefName":"master","headRefOid":"%s","author":{"login":"op"},"mergeable":"MERGEABLE"}' "$RHEAD" > "$SB/ghfix/pr.json"
  correr --revert-de "$MC" --confirmado
  _contiene "razon arbol distinto" "$OUT" "NO-MERGE: arbol distinto"
  if merge_disparado; then _mal "mergeo un revert que no es el inverso exacto"; fi
}

c_revert_punta() {
  CASO_ROJO=0; monta_revert
  git checkout -q master
  printf 'post\n' > post.sh
  git add post.sh
  git commit -qm "chore: algo mas aterrizo"
  git push -q origin master
  git checkout -q revert/task
  correr --revert-de "$MC" --confirmado
  _contiene "razon no es la punta" "$OUT" "NO-MERGE: no es la punta"
  if merge_disparado; then _mal "mergeo un revert de un commit que ya no es la punta"; fi
}

# Tabla mutacion -> caso que la atrapa. Los sed apuntan a lineas UNICAS del
# fuente; correr_mutacion falla si el sed dejo de cambiar nada (obsoleto).
while IFS=$'\t' read -r nombre expr fun; do
  [ -n "$nombre" ] || continue
  correr_mutacion "$nombre" "$expr" "$fun"
done <<'MUTS'
confirmado_default_si	s/^CONFIRMADO=0$/CONFIRMADO=1/	c_feliz
sin_match_head_commit	s/ --match-head-commit "\$SHA"//	c_confirmado
ci_pendiente_es_verde	s/\[ "\$st" != completed \]/false/	c_ci_pendiente
ci_rojo_es_verde	s/\[ "\$conc" != success \]/false/	c_ci_rojo
base_vieja_pasa	s/git merge-base --is-ancestor "\$ORIGEN" HEAD/true/	c_base_avanzada
sello_no_se_compara	s|\[ "\$SELLO" = "\$hash_actual" \]|true|	c_reescrito
verify_na_flojo	s|\[ "\$CFG_SIN_VERIFY_APP" != "true" \]|false|	c_verify_na
verify_ruta_floja	s|grep -q -- 'verify/'|true|	c_verify_ruta
rama_base_floja	s|\[ "\$CFG_RAMA" != "\$PR_BASE" \]|false|	c_rama_base
email_ajeno_pasa	s|no_merge "commit de otro email: \$csha es de \$email"|continue|	c_email
estado_opcional	s|if \[ -z "\$ESTADO_FILE" \]; then|if false; then|	c_sin_estado
borrado_reintenta	s|^  borrado_remoto$|  borrado_remoto; borrado_remoto|	c_borrado
verifier_flojo	s|\[ "\$V_VERIFIER" = "PASS" \]|true|	c_verifier_fail
autor_flojo	s|\[ "\$PR_AUTOR" = "\$LOGIN" \]|true|	c_autor
revert_trailer_opcional	s|grep -Fq 'Saikit-Merge:'|true|	c_revert_trailer
revert_arbol_por_patchid	s|\[ "\$T_REVERT" = "\$T_PREVIO" \]|true|	c_revert_arbol
revert_punta_floja	s|\[ "\$PUNTA" = "\$REVERT_DE" \]|true|	c_revert_punta
MUTS

if [ "$fail" -ne 0 ]; then
  echo "test_saikit_merge: FAIL" >&2
  exit 1
fi
echo "test_saikit_merge: OK"
