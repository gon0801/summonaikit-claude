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
#   - 18.25: el gate atraviesa la salida de gh bajo el terminal del agente:
#     ANSI tty-modelado (SAIKIT_GH_ANSI=1) y CLICOLOR_FORCE=1 heredado del
#     harness no cambian el veredicto — el script neutraliza el color en un
#     punto y el falso COMPRUEBA esa condicion (no responde siempre limpio:
#     sin el export o sin el unset, la mutacion correspondiente da rojo).
#     gh pr merge queda fuera (su stdout no se parsea) y gh pr checks no
#     existe en el script (se usa run list, hallazgo 18.1 §2.1).
#   - 20.5 lock de integracion: con --confirmado (normal o --revert-de) el
#     script toma $(git-common-dir)/saikit-merge.lock. DOS PROCESOS: el
#     segundo NO llama merge y sale 3 (distinguible del NO-MERGE). DOS
#     WORKTREES del mismo clone: comparten common-dir, el hermano se bloquea.
#     CAIDA (kill -9) del tenedor: el lock SOBREVIVE y un tercero ajeno no lo
#     libera; la recuperacion es EXPLICITA (--liberar-lock), nunca automatica.
#     REINTENTO con el lock libre: re-corre el gate completo del modo (normal:
#     base/sello; revert: punta, SIN estado propio). LIMITE DECLARADO: dos
#     clones independientes NO se excluyen (common-dirs distintos) — se mide
#     para que quede fijado. Determinismo por gancho de test
#     SAIKIT_MERGE_SOSTENER_SEG (duerme con el lock tomado; produccion = 0).
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
# hueco y rompe esta suite. 20.1: cada caso corre PRIMERO como control sano
# contra el fuente sin mutar — un caso siempre-rojo no acredita mutantes y
# deja el banco en FAIL con la salida del caso; el propio banco se audita al
# final con un caso roto adrede (rechazado) y un mutante superviviente
# (rechazado).
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
#
# 18.25: ademas modela el CONTRATO MEDIDO del color de gh (2.98.0, 2026-09-05)
# para ejercitar el entorno hostil del agente: con CLICOLOR_FORCE=1 heredado
# gh colorea y pretty-imprime su --json incluso a un pipe y LE GANA a
# NO_COLOR; con NO_COLOR=1 (o CLICOLOR=0) responde limpio; con stdout-tty
# colorea. El falso COMPRUEBA esa condicion — NO responde siempre limpio,
# sino no probaria el neutralizado del script.
set -u
[ -n "${SAIKIT_GH_LOG:-}" ] && printf 'gh %s\n' "$*" >> "$SAIKIT_GH_LOG"
fix="${SAIKIT_GH_FIX:?}"

# forma de ESTA llamada, para el knob de aislamiento SAIKIT_GH_ANSI_SOLO.
forma=""
case "$1 $2" in
  "repo view") forma=repo ;;
  "api user")  forma=user ;;
  "run list")  forma=runs ;;
  "pr view")
    case "$*" in *mergeCommit*) forma=pr_merge ;; *) forma=pr ;; esac
    ;;
esac

# gh_colorea: el contrato medido, EN ESTE ORDEN:
#   1. CLICOLOR_FORCE=1 manda sobre todo (le gana a NO_COLOR; medido).
#   2. NO_COLOR=1 o CLICOLOR=0 => limpio (el neutralizado del script).
#   3. si no: color solo con stdout-tty — aqui lo modela SAIKIT_GH_ANSI=1
#      (sin esa var, el pipe del $(...) del script recibe JSON limpio).
# $1 = 0 desactiva la regla 3 (modo SAIKIT_GH_ANSI_SOLO): la forma pedida
# colorea salvo que las reglas 1-2 lo impidan — el knob AISLA la llamada,
# no re-modela el tty.
gh_colorea() {
  if [ "${CLICOLOR_FORCE:-0}" = 1 ]; then return 0; fi
  if [ "${NO_COLOR:-0}" = 1 ] || [ "${CLICOLOR:-1}" = 0 ]; then return 1; fi
  if [ "$1" = 1 ]; then [ "${SAIKIT_GH_ANSI:-0}" = 1 ]; return; fi
  return 0
}

colorear=0
if [ -n "${SAIKIT_GH_ANSI_SOLO:-}" ]; then
  # knob de aislamiento: colorea SOLO la forma pedida y SIN la regla 3; las
  # reglas 1-2 siguen mandando (con FORCE colorea igual, neutralizado no).
  if [ "$SAIKIT_GH_ANSI_SOLO" = "$forma" ]; then
    gh_colorea 0 && colorear=1
  fi
else
  gh_colorea 1 && colorear=1
fi

emitir() {  # $1 = fixture: la forma coloreada medida o el crudo del fixture
  if [ "$colorear" = 1 ]; then coloriza "$1"; else cat "$1"; fi
}

# coloriza: reproduce la forma EXACTA medida de gh con color: pretty con
# indent 2 espacios por nivel; llaves/corchetes/comas/dospuntos en 1;37;
# claves en 1;34; strings-valor en 32; numeros/true/false/null desnudos;
# contenedor vacio en una linea. El ESC entra por -v (portable BWK awk y
# gawk; \033 literal dentro del programa awk NO lo es).
coloriza() {
  awk -v esc="$(printf '\033')" '
    function sangria(d,  k, s) { s = ""; for (k = 0; k < d; k++) s = s "  "; return s }
    function pun(s) { return esc "[1;37m" s esc "[m" }
    function cla(s) { return esc "[1;34m" s esc "[m" }
    function val(s) { return esc "[32m" s esc "[m" }
    {
      n = length($0); i = 1; depth = 0; out = ""
      while (i <= n) {
        c = substr($0, i, 1)
        if (c == "\"") {
          j = i + 1; s = "\""
          while (j <= n) {
            ch = substr($0, j, 1)
            if (ch == "\\") { s = s ch substr($0, j + 1, 1); j += 2; continue }
            s = s ch
            if (ch == "\"") break
            j++
          }
          i = j + 1
          # clave o valor: si el proximo char no-espacio es ":", es clave.
          k = i
          while (k <= n && substr($0, k, 1) == " ") k++
          out = out ((substr($0, k, 1) == ":") ? cla(s) : val(s))
        } else if (c == "{") {
          if (substr($0, i + 1, 1) == "}") { out = out pun("{}"); i += 2; continue }
          depth++
          out = out pun("{") "\n" sangria(depth)
          i++
        } else if (c == "}") {
          depth--
          out = out "\n" sangria(depth) pun("}")
          i++
        } else if (c == "[") {
          if (substr($0, i + 1, 1) == "]") { out = out pun("[]"); i += 2; continue }
          depth++
          out = out pun("[") "\n" sangria(depth)
          i++
        } else if (c == "]") {
          depth--
          out = out "\n" sangria(depth) pun("]")
          i++
        } else if (c == ",") {
          out = out pun(",") "\n" sangria(depth)
          i++
        } else if (c == ":") {
          out = out pun(":") " "
          i++
        } else if (c == " ") {
          i++
        } else {
          # numero / true / false / null: desnudo hasta el delimitador.
          j = i; s = ""
          while (j <= n) {
            ch = substr($0, j, 1)
            if (ch == "," || ch == "}" || ch == "]" || ch == " ") break
            s = s ch; j++
          }
          out = out s
          i = j
        }
      }
      printf "%s\n", out
    }
  ' "$1"
}

case "$1 $2" in
  "repo view") emitir "$fix/repo.json"; exit 0 ;;
  "api user")  emitir "$fix/user.json"; exit 0 ;;
  "run list")  emitir "$fix/runs.json"; exit 0 ;;
  "pr view")
    case "$*" in *mergeCommit*) emitir "$fix/pr-merge.json" ;; *) emitir "$fix/pr.json" ;; esac
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
  # 18.25: el banco no hereda el entorno de color del corredor (ni un knob
  # del falso dejado por un caso anterior): cada caso arranca determinista.
  unset NO_COLOR CLICOLOR CLICOLOR_FORCE SAIKIT_GH_ANSI SAIKIT_GH_ANSI_SOLO

  refix
}

# refix: re-escribe los fixtures que dependen del HEAD actual (sha del PR,
# veredicto sellado y estado del hook). Se llama tras commits nuevos.
# sembrar_sello: veredicto sellado + estado del hook para el root $1 (20.5:
# aditivo, para poder sembrar tambien un clon hermano sin pisar el del work).
sembrar_sello() {  # $1=root del repo a sembrar
  local key sd
  mkdir -p "$1/.saikit/veredictos"
  printf '{"sha":"%s","pr":7,"verifier":"PASS","verify_app":{"resultado":"PASS","comando":"bash verify/app.sh"},"blast":{"nivel":4,"hecho":"el drive de la app corre","comando":"bash tests/run.sh"},"adversary":"n/a","reviewer":"clean","decisiones":".saikit/decisiones/18.4.tsv"}' "$SHA" > "$1/.saikit/veredictos/$SHA.json"
  key="$(printf '%s' "$1" | cksum | cut -d' ' -f 1)"
  sd="$SB/estado/claude/$key/sess1"
  mkdir -p "$sd"
  {
    printf 'task_hash=h184\n'
    printf 'agents_seen=implementer,verifier,reviewer\n'
    printf 'lane=full\n'
    printf 'veredicto_sha256=%s\n' "$(sha256sum "$1/.saikit/veredictos/$SHA.json" | cut -d' ' -f 1)"
  } > "$sd/harness-state.env"
  printf 'prompt task started: h184\nverified: bash tests/run.sh\nagent: reviewer\n' > "$sd/harness-evidence.log"
}

refix() {
  SHA="$(git rev-parse HEAD)"
  printf '{"nameWithOwner":"op/sandbox"}' > "$SB/ghfix/repo.json"
  printf '{"login":"op"}' > "$SB/ghfix/user.json"
  printf '{"number":7,"baseRefName":"%s","headRefOid":"%s","author":{"login":"op"},"mergeable":"MERGEABLE"}' "$BASE_RAMA" "$SHA" > "$SB/ghfix/pr.json"
  printf '{"mergeCommit":{"oid":"f000000000000000000000000000000000000000"}}' > "$SB/ghfix/pr-merge.json"
  printf '[{"event":"pull_request","status":"completed","conclusion":"success","workflow":"ci"}]' > "$SB/ghfix/runs.json"

  rm -rf "$SB/estado"
  sembrar_sello "$(pwd -P)"
}

correr() {  # corre el script bajo prueba desde el work del sandbox
  OUT="$(bash "$MERGE" "$@" 2>&1)"
  RC=$?
}

merge_disparado() { grep -q '^gh pr merge' "$SAIKIT_GH_LOG" 2>/dev/null; }

c_listo_emision() {
  # 20.2: ver el caso listo_emite_forma_ejecutable_con_scripts_100644. Vive
  # como c_ para que la mutacion emision_listo_sin_bash la corra contra el
  # mutado (y su control sano contra el fuente sin mutar).
  CASO_ROJO=0; sb_reset master
  rm -rf tools
  cp -R "$repo/tools" tools
  cp "$MERGE" tools/saikit-merge.sh   # el (posible) mutado, no el del repo
  find tools -type f -exec chmod 644 {} +
  correr
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC"
  _contiene "reporta LISTO" "$OUT" "LISTO:"
  cmd="$(printf '%s\n' "$OUT" | grep -F 'tools/saikit-merge.sh --confirmado' | head -1 | sed 's/^LISTO:[[:space:]]*//')"
  [ -n "$cmd" ] || _mal "no se pudo extraer el comando de LISTO"
  : > "$SAIKIT_GH_LOG"
  OUT2="$(eval "$cmd" 2>&1)"; RC2=$?
  [ "$RC2" -eq 0 ] || _mal "la forma emitida fallo con scripts 100644 (rc=$RC2): $OUT2"
  _contiene "argv capturado: la forma emitida llega al merge" "$(cat "$SAIKIT_GH_LOG")" "pr merge 7 --squash --match-head-commit $SHA"
  [ -f ".saikit/veredictos/$SHA.merge" ] || _mal "la forma emitida no completo el flujo del merge"
}

c_sin_checks() {
  CASO_ROJO=0; sb_reset master
  printf '[]' > "$SB/ghfix/runs.json"
  correr --confirmado
  _contiene "razon sin checks" "$OUT" "NO-MERGE: sin checks"
  if merge_disparado; then _mal "mergeo sin checks (no es verde)"; fi
}

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

caso "feliz_bajo_terminal_ansi_no_merguea_por_presentacion"
{
  # 18.25: el entorno del agente modela un stdout con terminal; el falso
  # colorea su --json y el gate tiene que atravesarlo igual: el neutralizado
  # del script (NO_COLOR/CLICOLOR) come el color ANTES de que el parser
  # estricto vea un solo ESC.
  export SAIKIT_GH_ANSI=1
  correr --confirmado
  unset SAIKIT_GH_ANSI
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC: $OUT"
  _contiene "merge ok" "$OUT" "MERGE-OK:"
  _contiene "registro del merge" "$(cat ".saikit/veredictos/$SHA.merge" 2>/dev/null)" "f000000000000000000000000000000000000000"
  # el gate atraveso TODAS las llamadas gh del barrido bajo el entorno hostil
  for f in "^gh repo view" "^gh pr view --json number" "^gh api user" "^gh run list" "^gh pr view 7 --json mergeCommit"; do
    grep -Eq -- "$f" "$SAIKIT_GH_LOG" || _mal "el gh log no trajo la forma [$f]"
  done
}
fin_caso "feliz_bajo_terminal_ansi_no_merguea_por_presentacion"

caso "feliz_bajo_color_forzado_del_harness"
{
  # 18.25: el mecanismo EXACTO medido en vivo (grok headless): el harness
  # hereda CLICOLOR_FORCE=1 y gh colorea incluso a un pipe (y le gana a
  # NO_COLOR); el script lo unset-ea y el falso responde limpio.
  export CLICOLOR_FORCE=1
  correr --confirmado
  unset CLICOLOR_FORCE
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC: $OUT"
  _contiene "merge ok" "$OUT" "MERGE-OK:"
}
fin_caso "feliz_bajo_color_forzado_del_harness"

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

c_ci_skipped() {
  CASO_ROJO=0; sb_reset master
  printf '[{"event":"pull_request","status":"completed","conclusion":"skipped","workflow":"ci"}]' > "$SB/ghfix/runs.json"
  correr --confirmado
  _contiene "razon CI rojo" "$OUT" "NO-MERGE: CI rojo"
  _contiene "nombra skipped" "$OUT" "skipped"
  if merge_disparado; then _mal "mergeo con CI skipped"; fi
}

c_solo_push() {
  CASO_ROJO=0; sb_reset master
  printf '[{"event":"push","status":"completed","conclusion":"success","workflow":"ci"}]' > "$SB/ghfix/runs.json"
  correr --confirmado
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC: $OUT"
  _contiene "merge ok" "$OUT" "MERGE-OK:"
}

caso "ci_skipped_es_rojo"
{
  c_ci_skipped
}
fin_caso "ci_skipped_es_rojo"

caso "solo_push_success_es_verde"
{
  c_solo_push
}
fin_caso "solo_push_success_es_verde"

caso "sin_checks_no_merguea"
{
  c_sin_checks
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

# 20.13: bajo grok, seal_boot sin linked_seal_session no es autoridad de merge.
caso "grok_seal_boot_sin_vinculo_no_merguea"
{
  key="$(printf '%s' "$(pwd -P)" | cksum | cut -d' ' -f 1)"
  rm -rf "$SB/estado"
  sd="$SB/estado/grok/$key/child-seal-boot"
  mkdir -p "$sd"
  {
    printf 'task_hash=h2013\n'
    printf 'agents_seen=reviewer\n'
    printf 'lane=seal_boot\n'
    printf 'veredicto_sha256=%s\n' "$(sha256sum ".saikit/veredictos/$SHA.json" | cut -d' ' -f 1)"
  } > "$sd/harness-state.env"
  printf 'verified: bash tests/run.sh\nagent: reviewer\n' > "$sd/harness-evidence.log"
  correr --confirmado
  _contiene "razon seal_boot grok sin vinculo" "$OUT" "NO-MERGE: sin estado del hook"
  if merge_disparado; then _mal "mergeo con seal_boot grok sin linked_seal_session"; fi
}
fin_caso "grok_seal_boot_sin_vinculo_no_merguea"

caso "grok_padre_con_linked_seal_session_listo"
{
  key="$(printf '%s' "$(pwd -P)" | cksum | cut -d' ' -f 1)"
  rm -rf "$SB/estado"
  sd="$SB/estado/grok/$key/parent-linked"
  mkdir -p "$sd"
  {
    printf 'task_hash=h2013\n'
    printf 'agents_seen=implementer,verifier,reviewer\n'
    printf 'lane=full\n'
    printf 'veredicto_sha256=%s\n' "$(sha256sum ".saikit/veredictos/$SHA.json" | cut -d' ' -f 1)"
    printf 'linked_children=child-x\n'
    printf 'linked_seal_session=child-x\n'
  } > "$sd/harness-state.env"
  printf 'prompt task started: h2013\nverified: bash tests/run.sh\nagent: reviewer\n' > "$sd/harness-evidence.log"
  correr
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC: $OUT"
  _contiene "LISTO con padre grok vinculado" "$OUT" "LISTO:"
  if merge_disparado; then _mal "mergueo en default sin --confirmado"; fi
}
fin_caso "grok_padre_con_linked_seal_session_listo"

caso "grok_dos_linked_seal_session_no_merguea"
{
  key="$(printf '%s' "$(pwd -P)" | cksum | cut -d' ' -f 1)"
  rm -rf "$SB/estado"
  hash="$(sha256sum ".saikit/veredictos/$SHA.json" | cut -d' ' -f 1)"
  for sess in parent-a parent-b; do
    sd="$SB/estado/grok/$key/$sess"
    mkdir -p "$sd"
    {
      printf 'task_hash=h2013\n'
      printf 'agents_seen=implementer,verifier,reviewer\n'
      printf 'lane=full\n'
      printf 'veredicto_sha256=%s\n' "$hash"
      printf 'linked_seal_session=child-%s\n' "$sess"
    } > "$sd/harness-state.env"
    printf 'verified: bash tests/run.sh\nagent: reviewer\n' > "$sd/harness-evidence.log"
  done
  correr --confirmado
  _contiene "razon vinculo ambiguo" "$OUT" "NO-MERGE: vinculo padre-hijo ambiguo"
  if merge_disparado; then _mal "mergeo con dos linked_seal_session grok"; fi
}
fin_caso "grok_dos_linked_seal_session_no_merguea"

# 20.13 corrección: linked viejo (sello de otro sha) no cuenta para ambigüedad;
# el vigente del verdict actual deja LISTO. Sin el filtro por hash, n_linked=2
# bloquearía merge para siempre tras la primera tarea del mismo repo.
caso "grok_linked_viejo_mas_vigente_listo"
{
  key="$(printf '%s' "$(pwd -P)" | cksum | cut -d' ' -f 1)"
  rm -rf "$SB/estado"
  hash_vigente="$(sha256sum ".saikit/veredictos/$SHA.json" | cut -d' ' -f 1)"
  sd_viejo="$SB/estado/grok/$key/parent-tarea1-viejo"
  mkdir -p "$sd_viejo"
  {
    printf 'task_hash=h2013-old\n'
    printf 'agents_seen=implementer,verifier,reviewer\n'
    printf 'lane=full\n'
    printf 'veredicto_sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n'
    printf 'linked_children=child-old\n'
    printf 'linked_seal_session=child-old\n'
  } > "$sd_viejo/harness-state.env"
  printf 'verified: bash tests/run.sh\nagent: reviewer\n' > "$sd_viejo/harness-evidence.log"
  sd_nuevo="$SB/estado/grok/$key/parent-tarea2-vigente"
  mkdir -p "$sd_nuevo"
  {
    printf 'task_hash=h2013-new\n'
    printf 'agents_seen=implementer,verifier,reviewer\n'
    printf 'lane=full\n'
    printf 'veredicto_sha256=%s\n' "$hash_vigente"
    printf 'linked_children=child-new\n'
    printf 'linked_seal_session=child-new\n'
  } > "$sd_nuevo/harness-state.env"
  printf 'prompt task started: h2013-new\nverified: bash tests/run.sh\nagent: reviewer\n' > "$sd_nuevo/harness-evidence.log"
  correr
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC: $OUT"
  _contiene "LISTO pese a linked viejo" "$OUT" "LISTO:"
  _no_contiene "no declara ambiguo por linked viejo" "$OUT" "vinculo padre-hijo ambiguo"
  if merge_disparado; then _mal "mergueo en default sin --confirmado"; fi
}
fin_caso "grok_linked_viejo_mas_vigente_listo"

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

caso "listo_emite_forma_ejecutable_con_scripts_100644"
{
  # 20.2: el comando que LISTO le da al operador para copiar tiene que correr
  # TAL CUAL aunque el checkout no tenga bit de ejecucion (100644: copia
  # extraida, zip, algunos filesystems). Se ejecuta de VERDAD la linea emitida
  # contra una copia del repo con el bit quitado — chmod 644, JAMAS chmod +x
  # (esconderia el defecto que este caso afirma) — y el argv del merge llega
  # al doble de gh. Nada real: gh es el falso del banco, origin el bare local.
  c_listo_emision
}
fin_caso "listo_emite_forma_ejecutable_con_scripts_100644"

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

# ------------------------------------------------- lock de integracion (20.5)
# Dos procesos reales, dos worktrees del mismo clone, caida del tenedor,
# reintento que revalida y el limite declarado entre clones. Determinismo por
# gancho de test (no sleeps a ciegas): SAIKIT_MERGE_SOSTENER_SEG duerme al
# tenedor CON el lock tomado (precedente: SAIKIT_SETUP_SOSTENER_SEG, 18.7).
esperar_lock() {  # $1=ruta del lock; espera a que exista, acotado a ~10 s
  local cont=0
  while [ ! -d "$1" ] && [ "$cont" -lt 100 ]; do
    sleep 0.1; cont=$((cont + 1))
  done
  [ -d "$1" ]
}

c_b_bloquea() {
  # Parte comun de contencion (pre: sb_reset hecho, gh log truncado): A
  # duerme CON el lock tomado; B corre --confirmado y NO llama merge, sale 3.
  # Deja $a_pid vivo (duerme): el llamador decide esperarlo o matarlo.
  SAIKIT_MERGE_SOSTENER_SEG=6 bash "$MERGE" --confirmado > "$SB/a.log" 2>&1 &
  a_pid=$!
  esperar_lock ".git/saikit-merge.lock" \
    || { _mal "A no tomo el lock; el caso no mide contencion"; wait "$a_pid" 2>/dev/null; return 1; }
  correr --confirmado
  [ "$RC" -eq 3 ] || _mal "el segundo proceso deberia bloquearse con 3, dio $RC: $OUT"
  _contiene "reporta el lock" "$OUT" "saikit-merge.lock"
  _contiene "muestra como liberarlo" "$OUT" "--liberar-lock"
  if merge_disparado; then _mal "el segundo proceso llamo merge pese al lock del primero"; fi
  return 0
}

c_lock_dos_procesos() {
  # DOS PROCESOS sobre el mismo worktree (caso de banco COMPLETO): tras
  # bloquear a B, A despierta, mergea y LIBERA su lock al salir (trap propio).
  CASO_ROJO=0; sb_reset master
  : > "$SAIKIT_GH_LOG"
  c_b_bloquea || return 0
  wait "$a_pid"; a_rc=$?
  [ "$a_rc" -eq 0 ] || _mal "A deberia terminar en 0, dio $a_rc: $(cat "$SB/a.log")"
  _contiene "A si mergueo" "$(cat "$SB/a.log")" "MERGE-OK:"
  [ ! -d ".git/saikit-merge.lock" ] || _mal "A no libero su lock al salir"
}

c_lock_exclusion() {
  # Mitad economica de c_lock_dos_procesos (caballo de las mutaciones): solo
  # la exclusion de B; A se mata y se recupera por la via explicita.
  CASO_ROJO=0; sb_reset master
  : > "$SAIKIT_GH_LOG"
  c_b_bloquea || return 0
  kill -9 "$a_pid" 2>/dev/null; wait "$a_pid" 2>/dev/null
  bash "$MERGE" --liberar-lock >/dev/null 2>&1
}

c_lock_libera_propio() {
  # Sin SOSTENER (rapido): una invocacion que completa mergea y suelta su
  # propio lock al salir — el trap de EXIT libera, y solo lo propio.
  CASO_ROJO=0; sb_reset master
  correr --confirmado
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC: $OUT"
  _contiene "merge ok" "$OUT" "MERGE-OK:"
  [ ! -d ".git/saikit-merge.lock" ] || _mal "el dueno no libero su lock al salir"
}

c_lock_dos_worktrees() {
  # DOS WORKTREES del mismo clone: comparten git-common-dir, asi que el lock
  # tomado desde el work principal BLOQUEA al hermano.
  CASO_ROJO=0; sb_reset master
  git worktree add -q "$SB/otro" -b feat/otro 2>/dev/null \
    || { _mal "no se pudo crear el segundo worktree"; return; }
  # Misma forma fisica que la tool (pwd -P). En macOS $SB puede ser /var/...
  # mientras el common-dir canónico es /private/var/... (20.28).
  lock_canon="$(cd "$SB/work/.git" && pwd -P)/saikit-merge.lock"
  SAIKIT_MERGE_SOSTENER_SEG=6 bash "$MERGE" --confirmado > "$SB/a.log" 2>&1 &
  a_pid=$!
  esperar_lock "$lock_canon" \
    || { _mal "A no tomo el lock (worktree); el caso no mide"; wait "$a_pid" 2>/dev/null; return; }
  cd "$SB/otro" || { _mal "no se pudo entrar al worktree hermano"; return; }
  OUT="$(bash "$MERGE" --confirmado 2>&1)"; RC=$?
  [ "$RC" -eq 3 ] || _mal "desde el worktree hermano deberia bloquearse con 3, dio $RC: $OUT"
  _contiene "reporta el lock COMPARTIDO (common-dir)" "$OUT" "$lock_canon"
  _contiene "muestra como liberarlo" "$OUT" "--liberar-lock"
  if merge_disparado; then _mal "el worktree hermano llamo merge"; fi
  cd "$SB/work" || exit 1
  kill -9 "$a_pid" 2>/dev/null; wait "$a_pid" 2>/dev/null
  OUT2="$(bash "$MERGE" --liberar-lock 2>&1)"; RC2=$?
  [ "$RC2" -eq 0 ] || _mal "liberar-lock fallo tras la caida del tenedor: $OUT2"
  [ ! -d "$lock_canon" ] || _mal "liberar-lock no quito el lock"
}

c_lock_caida() {
  # CAIDA del tenedor (kill -9: el trap no corre) => el lock SOBREVIVE; un
  # tercero ajeno queda bloqueado y SU salida no libera el lock de nadie; la
  # recuperacion va por la via EXPLICITA (--liberar-lock), nunca automatica.
  CASO_ROJO=0; sb_reset master
  : > "$SAIKIT_GH_LOG"
  SAIKIT_MERGE_SOSTENER_SEG=6 bash "$MERGE" --confirmado > "$SB/a.log" 2>&1 &
  a_pid=$!
  esperar_lock ".git/saikit-merge.lock" \
    || { _mal "A no tomo el lock; el caso no mide caida"; wait "$a_pid" 2>/dev/null; return; }
  kill -9 "$a_pid"; wait "$a_pid" 2>/dev/null
  [ -d ".git/saikit-merge.lock" ] || _mal "la caida (SIGKILL) libero el lock: el trap no corre con -9 y el lock tiene que sobrevivir"
  # Tercero ajeno: bloqueado por el huerfano...
  correr --confirmado
  [ "$RC" -eq 3 ] || _mal "el tercero deberia bloquearse con 3 (lock huerfano), dio $RC: $OUT"
  _contiene "reporta el pid del dueno caido" "$OUT" "$a_pid"
  _contiene "dice que no se borra solo" "$OUT" "no se borra solo"
  if merge_disparado; then _mal "el tercero llamo merge con un lock huerfano presente"; fi
  # ...y su salida NO libera el lock ajeno (el trap compara el pid).
  [ -d ".git/saikit-merge.lock" ] || _mal "la salida del tercero libero un lock ajeno"
  # Recuperacion EXPLICITA: --liberar-lock muestra el contenido y lo quita.
  OUT2="$(bash "$MERGE" --liberar-lock 2>&1)"; RC2=$?
  [ "$RC2" -eq 0 ] || _mal "--liberar-lock fallo: $OUT2"
  _contiene "muestra el contenido antes de quitar" "$OUT2" "$a_pid"
  [ ! -d ".git/saikit-merge.lock" ] || _mal "--liberar-lock no quito el lock"
  # Tras liberar, el reintento ya no esta bloqueado y llega al final del gate.
  correr --confirmado
  [ "$RC" -eq 0 ] || _mal "tras liberar, el reintento deberia llegar al gate y mergear, dio $RC: $OUT"
  _contiene "merge ok" "$OUT" "MERGE-OK:"
}

c_lock_reintento_revalida() {
  # REINTENTO revalida (modo normal): B bloqueado por el lock; tras liberar,
  # la base avanzo mientras esperaba y el reintento RE-CORRE el gate completo
  # (sello incluido: es el mismo camino de siempre, ahora bajo el lock) y NO
  # mergea. Nada queda cacheado del intento anterior.
  CASO_ROJO=0; sb_reset master
  : > "$SAIKIT_GH_LOG"
  SAIKIT_MERGE_SOSTENER_SEG=6 bash "$MERGE" --confirmado > "$SB/a.log" 2>&1 &
  a_pid=$!
  esperar_lock ".git/saikit-merge.lock" \
    || { _mal "A no tomo el lock; el caso no mide reintento"; wait "$a_pid" 2>/dev/null; return; }
  correr --confirmado
  [ "$RC" -eq 3 ] || _mal "el intento bloqueado deberia salir 3, dio $RC: $OUT"
  kill -9 "$a_pid"; wait "$a_pid" 2>/dev/null
  bash "$MERGE" --liberar-lock >/dev/null 2>&1
  avanzar_base
  correr --confirmado
  [ "$RC" -eq 1 ] || _mal "el reintento con la base avanzada deberia NO-MERGE (1), dio $RC: $OUT"
  _contiene "re-corrio el gate completo desde cero" "$OUT" "NO-MERGE: base avanzada"
  if merge_disparado; then _mal "el reintento mergeo sin revalidar la base"; fi
}

c_revert_lock() {
  # Modo --revert-de cubierto por el mismo lock. El revert es STATELESS: no
  # hay estado del hook en el sandbox y el flujo llega al merge igual (el
  # sello es cosa del modo normal).
  CASO_ROJO=0; monta_revert
  [ ! -d "$SB/estado" ] || _mal "precondicion rota: monta_revert debia dejar el repo SIN estado (revert stateless)"
  : > "$SAIKIT_GH_LOG"
  SAIKIT_MERGE_SOSTENER_SEG=6 bash "$MERGE" --revert-de "$MC" --confirmado > "$SB/a.log" 2>&1 &
  a_pid=$!
  esperar_lock ".git/saikit-merge.lock" \
    || { _mal "A no tomo el lock (revert); el caso no mide"; wait "$a_pid" 2>/dev/null; return; }
  _contiene "el lock declara el modo revert" "$(cat .git/saikit-merge.lock/modo 2>/dev/null)" "revert"
  correr --revert-de "$MC" --confirmado
  [ "$RC" -eq 3 ] || _mal "el segundo revert deberia bloquearse con 3, dio $RC: $OUT"
  _contiene "reporta el lock" "$OUT" "saikit-merge.lock"
  if merge_disparado; then _mal "el segundo revert llamo merge"; fi
  wait "$a_pid"; a_rc=$?
  [ "$a_rc" -eq 0 ] || _mal "A (revert) deberia terminar en 0, dio $a_rc: $(cat "$SB/a.log")"
  _contiene "A si mergueo el revert" "$(cat "$SB/a.log")" "MERGE-OK:"
  [ ! -d ".git/saikit-merge.lock" ] || _mal "A no libero su lock al salir (revert)"
}

c_revert_lock_reintento() {
  # REINTENTO revalida (modo revert): tras liberar, la punta de master cambio
  # mientras el reintento esperaba; re-corre punta/trailer/arbol/CI y NO
  # mergea. El revert sigue SIN estado propio: nada de esto consulta sello.
  CASO_ROJO=0; monta_revert
  : > "$SAIKIT_GH_LOG"
  SAIKIT_MERGE_SOSTENER_SEG=6 bash "$MERGE" --revert-de "$MC" --confirmado > "$SB/a.log" 2>&1 &
  a_pid=$!
  esperar_lock ".git/saikit-merge.lock" \
    || { _mal "A no tomo el lock (revert reintento); el caso no mide"; wait "$a_pid" 2>/dev/null; return; }
  correr --revert-de "$MC" --confirmado
  [ "$RC" -eq 3 ] || _mal "el revert bloqueado deberia salir 3, dio $RC: $OUT"
  kill -9 "$a_pid"; wait "$a_pid" 2>/dev/null
  bash "$MERGE" --liberar-lock >/dev/null 2>&1
  # La punta de master avanzo mientras el reintento espero.
  git checkout -q master
  printf 'post\n' > post.sh
  git add post.sh
  git commit -qm "chore: algo mas aterrizo"
  git push -q origin master
  git checkout -q revert/task
  correr --revert-de "$MC" --confirmado
  [ "$RC" -eq 1 ] || _mal "el reintento del revert con la punta cambiada deberia NO-MERGE (1), dio $RC: $OUT"
  _contiene "revalido la punta desde cero" "$OUT" "NO-MERGE: no es la punta"
  if merge_disparado; then _mal "el reintento del revert mergeo sin revalidar la punta"; fi
}

c_lock_entre_clones() {
  # LIMITE DECLARADO (20.5): el lock vive en el git-common-dir, asi que dos
  # clones INDEPENDIENTES del mismo repo NO se excluyen entre si. A sostiene
  # el lock del clone principal; B, en un clon hermano (common-dir propio,
  # sembrado con su veredicto y estado), pasa de largo y mergea. Se mide para
  # que el limite quede fijado como comportamiento, no como promesa rota.
  CASO_ROJO=0; sb_reset master
  git clone -q "$SB/origin.git" "$SB/clone2" 2>/dev/null \
    || { _mal "no se pudo clonar el hermano"; return; }
  git -C "$SB/clone2" config "url.$SB/origin.git.insteadOf" "https://github.com/op/sandbox.git"
  git -C "$SB/clone2" remote set-url origin "https://github.com/op/sandbox.git"
  git -C "$SB/clone2" config user.email op@example.com
  git -C "$SB/clone2" config user.name op
  git -C "$SB/clone2" checkout -q feat/task
  # La forma FISICA del root (pwd -P): el script clavea el estado con la
  # misma derivacion, y en macOS $SB viene por /tmp (symlink de /private/tmp).
  sembrar_sello "$(cd "$SB/clone2" && pwd -P)"
  SAIKIT_MERGE_SOSTENER_SEG=6 bash "$MERGE" --confirmado > "$SB/a.log" 2>&1 &
  a_pid=$!
  esperar_lock "$SB/work/.git/saikit-merge.lock" \
    || { _mal "A no tomo el lock (clon hermano); el caso no mide"; wait "$a_pid" 2>/dev/null; return; }
  cd "$SB/clone2" || { _mal "no se pudo entrar al clon hermano"; return; }
  correr --confirmado
  [ "$RC" -eq 0 ] || _mal "el clon hermano deberia mergear sin exclusion entre clones, dio $RC: $OUT"
  _contiene "merge ok del hermano" "$OUT" "MERGE-OK:"
  [ ! -d "$SB/clone2/.git/saikit-merge.lock" ] || _mal "el hermano no libero su propio lock al salir"
  cd "$SB/work" || exit 1
  [ -d "$SB/work/.git/saikit-merge.lock" ] || _mal "el lock del clone principal no deberia verse afectado por el hermano"
  kill -9 "$a_pid" 2>/dev/null; wait "$a_pid" 2>/dev/null
  OUT2="$(bash "$MERGE" --liberar-lock 2>&1)"; RC2=$?
  [ "$RC2" -eq 0 ] || _mal "limpieza: liberar-lock fallo: $OUT2"
}

caso "lock_segundo_proceso_no_llama_merge_exit_3"
{
  c_lock_dos_procesos
}
fin_caso "lock_segundo_proceso_no_llama_merge_exit_3"

caso "lock_dos_worktrees_del_mismo_clone_el_segundo_no_merguea"
{
  c_lock_dos_worktrees
}
fin_caso "lock_dos_worktrees_del_mismo_clone_el_segundo_no_merguea"

caso "mutante_lock_path_sin_canonicalizar_se_pone_rojo"
{
  # Discriminante 20.28: si raw != canon, comparar contra raw (sin pwd -P)
  # falla la igualdad exacta que la tool usa tras canonicalizar.
  CASO_ROJO=0; sb_reset master
  raw="$SB/work/.git/saikit-merge.lock"
  canon="$(cd "$SB/work/.git" && pwd -P)/saikit-merge.lock"
  if [ "$raw" = "$canon" ]; then
    printf '    ok: raw==canon en esta plataforma; mutante no discrimina\n'
  else
    reported="$canon"
    if [ "$reported" = "$raw" ]; then
      _mal "mutante: raw y canon debian diferir"
    fi
    # La asercion mutante (igualdad/contiene exacto del raw contra reportado
    # canonico) queda roja; no se relaja a «contiene saikit-merge.lock».
    if [ "$reported" = "$raw" ] || [ "$reported" = "saikit-merge.lock" ]; then
      _mal "mutante sin canonicalizar sobrevive"
    fi
    grep -E 'lock_canon=.*pwd -P' "$here/test_saikit_merge.sh" >/dev/null \
      || _mal "falta lock_canon con pwd -P en c_lock_dos_worktrees"
  fi
}
fin_caso "mutante_lock_path_sin_canonicalizar_se_pone_rojo"

caso "lock_caida_no_libera_ajeno_recuperacion_explicita"
{
  c_lock_caida
}
fin_caso "lock_caida_no_libera_ajeno_recuperacion_explicita"

caso "lock_reintento_tras_liberar_revalida_el_gate_normal"
{
  c_lock_reintento_revalida
}
fin_caso "lock_reintento_tras_liberar_revalida_el_gate_normal"

caso "revert_lock_segundo_proceso_no_merguea"
{
  c_revert_lock
}
fin_caso "revert_lock_segundo_proceso_no_merguea"

caso "revert_lock_reintento_revalida_punta"
{
  c_revert_lock_reintento
}
fin_caso "revert_lock_reintento_revalida_punta"

caso "lock_no_excluye_entre_clones_declarado"
{
  c_lock_entre_clones
}
fin_caso "lock_no_excluye_entre_clones_declarado"

cd - >/dev/null 2>&1 || true

if [ "$fail" -ne 0 ]; then
  echo "test_saikit_merge: FAIL (casos)" >&2
  exit 1
fi

c_revert_registro() {
  # Hallazgo de CodeRabbit en el PR #142, CONFIRMADO por el lead.
  #
  # En --revert-de el directorio `.saikit/veredictos/` puede NO existir: lo crea
  # el hook y su .gitignore lleva `*`, asi que NO viaja en un clon fresco — que
  # es justo donde se revierte. Sin `mkdir -p`, la redireccion del registro
  # fallaba, y como el script corre con `set -u` pero SIN `set -e`, seguia
  # adelante e imprimia MERGE-OK igual: reportaba un registro que no escribio.
  #
  # El banco no lo veia por dos razones a la vez: `monta_revert` llama a
  # `sb_reset`, que crea el directorio, y NO habia ningun caso FELIZ de revert
  # (los tres existentes son negativos), asi que esa rama de `merge_final` no se
  # ejercitaba nunca. Este caso cierra las dos.
  CASO_ROJO=0
  monta_revert
  rm -rf ".saikit/veredictos"
  if [ -d ".saikit/veredictos" ]; then _mal "el caso no arranca sin el directorio"; fi
  correr --revert-de "$MC" --confirmado
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC"
  _contiene "merge ok" "$OUT" "MERGE-OK:"
  _no_contiene "no anuncia un registro que no hizo" "$OUT" "SIN registrar"
  _contiene "registro escrito" "$(cat ".saikit/veredictos/$RHEAD.merge" 2>/dev/null)" "f000000000000000000000000000000000000000"
}
caso "revert_ok_sin_dir_de_veredictos_registra_igual"
c_revert_registro
fin_caso "revert_ok_sin_dir_de_veredictos_registra_igual"

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
  # 20.1 — control sano ANTES del mutado: el caso se corre contra el fuente
  # SANO y tiene que salir verde. Un caso siempre-rojo "atraparia" cualquier
  # mutante por la razon equivocada y acreditaria una proteccion que nadie
  # probo (residual 18.4). Si el control falla, la mutacion NO acredita nada
  # y el defecto del caso no se oculta: se reporta con su salida concreta y
  # el banco queda en FAIL. La salida del caso se captura a un archivo
  # hermano del mutado (fuera de $SB, que el proximo sb_reset borra).
  local ctrl="$MUTADO.control"
  CASO_ROJO=0
  "$fun" >"$ctrl" 2>&1
  if [ "$CASO_ROJO" -ne 0 ]; then
    printf '    FAIL: mutacion %s: control sano fallo — el caso %s ya esta rojo contra el fuente SANO; NO acredita mutante (defecto del caso, no atrapada). Salida:\n' "$nombre" "$fun" >&2
    cat "$ctrl" >&2
    rm -f "$ctrl" "$MUTADO"
    fail=1; return
  fi
  rm -f "$ctrl"
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

c_grok_seal_boot_sin_vinculo() {
  # 20.13: mutacion grok_sin_exigir_vinculo acepta seal_boot y mergea.
  CASO_ROJO=0; sb_reset master
  key="$(printf '%s' "$(pwd -P)" | cksum | cut -d' ' -f 1)"
  rm -rf "$SB/estado"
  sd="$SB/estado/grok/$key/child-seal-boot"
  mkdir -p "$sd"
  {
    printf 'task_hash=h2013\n'
    printf 'agents_seen=reviewer\n'
    printf 'lane=seal_boot\n'
    printf 'veredicto_sha256=%s\n' "$(sha256sum ".saikit/veredictos/$SHA.json" | cut -d' ' -f 1)"
  } > "$sd/harness-state.env"
  printf 'verified: bash tests/run.sh\nagent: reviewer\n' > "$sd/harness-evidence.log"
  correr --confirmado
  _contiene "razon seal_boot grok sin vinculo" "$OUT" "NO-MERGE: sin estado del hook"
  if merge_disparado; then _mal "mergeo con seal_boot grok sin linked_seal_session"; fi
}

c_grok_linked_viejo_mas_vigente() {
  # 20.13: mutacion grok_cuenta_linked_viejos vuelve a contar stale → ambiguo.
  CASO_ROJO=0; sb_reset master
  key="$(printf '%s' "$(pwd -P)" | cksum | cut -d' ' -f 1)"
  rm -rf "$SB/estado"
  hash_vigente="$(sha256sum ".saikit/veredictos/$SHA.json" | cut -d' ' -f 1)"
  sd_viejo="$SB/estado/grok/$key/parent-tarea1-viejo"
  mkdir -p "$sd_viejo"
  {
    printf 'task_hash=h2013-old\n'
    printf 'agents_seen=implementer,verifier,reviewer\n'
    printf 'lane=full\n'
    printf 'veredicto_sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n'
    printf 'linked_children=child-old\n'
    printf 'linked_seal_session=child-old\n'
  } > "$sd_viejo/harness-state.env"
  printf 'verified: bash tests/run.sh\nagent: reviewer\n' > "$sd_viejo/harness-evidence.log"
  sd_nuevo="$SB/estado/grok/$key/parent-tarea2-vigente"
  mkdir -p "$sd_nuevo"
  {
    printf 'task_hash=h2013-new\n'
    printf 'agents_seen=implementer,verifier,reviewer\n'
    printf 'lane=full\n'
    printf 'veredicto_sha256=%s\n' "$hash_vigente"
    printf 'linked_children=child-new\n'
    printf 'linked_seal_session=child-new\n'
  } > "$sd_nuevo/harness-state.env"
  printf 'prompt task started: h2013-new\nverified: bash tests/run.sh\nagent: reviewer\n' > "$sd_nuevo/harness-evidence.log"
  correr
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC: $OUT"
  _contiene "LISTO pese a linked viejo" "$OUT" "LISTO:"
  _no_contiene "no declara ambiguo por linked viejo" "$OUT" "vinculo padre-hijo ambiguo"
  if merge_disparado; then _mal "mergueo en default sin --confirmado"; fi
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

c_ansi() {
  # 18.25: sin el export neutralizador, el falso colorea bajo el terminal
  # modelado y el parser estricto rechaza por PRESENTACION.
  CASO_ROJO=0; sb_reset master
  export SAIKIT_GH_ANSI=1
  correr --confirmado
  unset SAIKIT_GH_ANSI
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC: $OUT"
  _contiene "merge ok" "$OUT" "MERGE-OK:"
}

c_ansi_force() {
  # 18.25: sin el unset, CLICOLOR_FORCE heredado colorea aunque el script
  # exporte NO_COLOR (FORCE le gana; medido).
  CASO_ROJO=0; sb_reset master
  export CLICOLOR_FORCE=1
  correr --confirmado
  unset CLICOLOR_FORCE
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC: $OUT"
  _contiene "merge ok" "$OUT" "MERGE-OK:"
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
sin_checks_n_opcional	s/\[ "\$n" -gt 0 \]/true/	c_sin_checks
ci_pendiente_es_verde	s/\[ "\$st" != completed \]/false/	c_ci_pendiente
ci_rojo_es_verde	s/\[ "\$conc" != success \]/false/	c_ci_rojo
skipped_es_verde	s/\[ "\$conc" != success \]/[ "$conc" != success ] \&\& [ "$conc" != skipped ]/	c_ci_skipped
solo_push_exige_pr	s/\[ "\$n" -gt 0 \] || no_merge "sin checks/[ "$hay_pr" = 0 ] \&\& no_merge "exige pull_request"; [ "$n" -gt 0 ] || no_merge "sin checks/	c_solo_push
base_vieja_pasa	s/git merge-base --is-ancestor "\$ORIGEN" HEAD/true/	c_base_avanzada
sello_no_se_compara	s|\[ "\$SELLO" = "\$hash_actual" \]|true|	c_reescrito
verify_na_flojo	s|\[ "\$CFG_SIN_VERIFY_APP" != "true" \]|false|	c_verify_na
verify_ruta_floja	s|grep -q -- 'verify/'|true|	c_verify_ruta
rama_base_floja	s|\[ "\$CFG_RAMA" != "\$PR_BASE" \]|false|	c_rama_base
email_ajeno_pasa	s|no_merge "commit de otro email: \$csha es de \$email"|continue|	c_email
estado_opcional	s|if \[ -z "\$ESTADO_FILE" \]; then|if false; then|	c_sin_estado
grok_sin_exigir_vinculo	s|grep -q '^linked_seal_session=' "\$f" 2>/dev/null || continue|true|	c_grok_seal_boot_sin_vinculo
grok_cuenta_linked_viejos	s|\[ -n "\$sello_f" \] && \[ "\$sello_f" = "\$hash_file" \] || continue|true|	c_grok_linked_viejo_mas_vigente
borrado_reintenta	s|^  borrado_remoto$|  borrado_remoto; borrado_remoto|	c_borrado
verifier_flojo	s|\[ "\$V_VERIFIER" = "PASS" \]|true|	c_verifier_fail
autor_flojo	s|\[ "\$PR_AUTOR" = "\$LOGIN" \]|true|	c_autor
revert_trailer_opcional	s|grep -Fq 'Saikit-Merge:'|true|	c_revert_trailer
revert_arbol_por_patchid	s|\[ "\$T_REVERT" = "\$T_PREVIO" \]|true|	c_revert_arbol
revert_punta_floja	s|\[ "\$PUNTA" = "\$REVERT_DE" \]|true|	c_revert_punta
registro_sin_mkdir	s|mkdir -p "\$VERDICTOS" 2>/dev/null|true|	c_revert_registro
sin_neutralizar_gh	s/^export NO_COLOR=1 CLICOLOR=0$/true/	c_ansi
sin_unset_color_force	s/^unset CLICOLOR_FORCE$/true/	c_ansi_force
emision_listo_sin_bash	s|LISTO:   bash tools/saikit-merge.sh --confirmado|LISTO:   tools/saikit-merge.sh --confirmado|	c_listo_emision
lock_sin_guard	s|^  if mkdir "\$LOCK_DIR" 2>/dev/null; then$|  if true; then|	c_lock_exclusion
lock_mkdir_no_atomico	s|^  if mkdir "\$LOCK_DIR" 2>/dev/null; then$|  if mkdir -p "\$LOCK_DIR" 2>/dev/null; then|	c_lock_exclusion
trap_no_libera	s|^liberar_propio() {$|liberar_propio() { return 0; #|	c_lock_libera_propio
MUTS

# ---------------------------------------- meta: el banco se audita a si mismo
# 20.1 (residual 18.4): un caso SIEMPRE-ROJO — rojo ya contra el fuente
# SANO — "atrapa" cualquier mutante por la razon equivocada y acredita
# protecciones que nadie probo. correr_mutacion tiene que correr el control
# sano ANTES del mutado; si ese control falla, la mutacion no acredita nada,
# el defecto del caso NO se oculta (fail=1) y el reporte nombra la causa
# concreta. Se mide con un caso roto ADREDE y una mutacion real; el fail se
# salva/restaura para no envenenar esta pasada cuando el candado funciona.
c_roto_adrede() {
  CASO_ROJO=0; sb_reset master
  correr
  _contiene "caso roto adrede" "$OUT" "NO-MERGE: texto que el sano nunca emite"
}

fail_previo="$fail"; fail=0
meta_out="$(mktemp "${TMPDIR:-/tmp}/saikit-merge-meta-XXXXXX")"
# Sin $( ): la sustitucion correria correr_mutacion en una subshell y su
# fail=1 no llegaria nunca al shell del test. El archivo si lo conserva.
correr_mutacion "selftest_caso_siempre_rojo" 's/^CONFIRMADO=0$/CONFIRMADO=1/' c_roto_adrede >"$meta_out" 2>&1
res="$fail"; fail="$fail_previo"  # el veredicto acumulado se restaura: el meta juzga SOLO su llamada
if [ "$res" -ne 0 ] \
   && grep -Fq 'control sano' "$meta_out" \
   && grep -Fq 'c_roto_adrede' "$meta_out" \
   && grep -Fq 'caso roto adrede' "$meta_out"; then
  printf '    ok: banco rechaza caso siempre-rojo (control sano rojo => no acredita y FAIL)\n'
else
  printf '    FAIL: el banco no rechazo un caso siempre-rojo — salida del intento:\n' >&2
  cat "$meta_out" >&2
  fail=1
fi
rm -f "$meta_out"

# Espejo del candado conservado: un mutante que NINGUN caso detecta
# (superviviente) tambien deja el banco en FAIL. Caso sano-verde adrede que
# no observa nada de lo que la mutacion rompe.
c_indiferente_adrede() {
  CASO_ROJO=0; sb_reset master
  correr
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC"
}

fail_previo="$fail"; fail=0
meta_out="$(mktemp "${TMPDIR:-/tmp}/saikit-merge-meta-XXXXXX")"
correr_mutacion "selftest_mutante_superviviente" 's/^CONFIRMADO=0$/CONFIRMADO=1/' c_indiferente_adrede >"$meta_out" 2>&1
res="$fail"; fail="$fail_previo"  # idem: juzga SOLO su llamada
if [ "$res" -ne 0 ] && grep -Fq 'selftest_mutante_superviviente' "$meta_out" && grep -Fq 'ningun caso detecto' "$meta_out"; then
  printf '    ok: banco rechaza mutante superviviente (caso sano-verde que no detecta)\n'
else
  printf '    FAIL: el banco acredito un mutante que ningun caso detecto\n' >&2
  fail=1
fi
rm -f "$meta_out"

if [ "$fail" -ne 0 ]; then
  echo "test_saikit_merge: FAIL" >&2
  exit 1
fi
echo "test_saikit_merge: OK"
