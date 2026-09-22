#!/usr/bin/env bash
# tests/test_saikit_merge.sh — Task 18.4: tools/saikit-merge.sh fail-closed y
# acotado (D18) + modo --revert-de (D19).
#
# QUE AFIRMA (DoD de la fila 18.4, columna 3 de Plans.md):
#   - Feliz: todo ok => NO mergea por defecto, reporta LISTO. Con
#     --confirmado => merge squash con --match-head-commit, body
#     "Saikit-Merge: <sha>", SIN --delete-branch y SIN --admin;
#     registra .saikit/veredictos/<sha>.merge.
#     Config con rama:main funciona igual.
#   - NO mergea y NOMBRA la razon: CI rojo / sin checks / pendiente /
#     mergeable UNKNOWN dos veces / base avanzada / base conflictiva /
#     head movido durante la comprobacion / recibo ausente o revocado /
#     reviewer ausente del recibo / verifier FAIL / identidad reutilizada /
#     bloqueante abierto / config ausente / merge_despliega unknown /
#     PR que toca autopilot.json / PR de otra rama base / repo distinto /
#     autor != cuenta / commit de otro email.
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
#     libera mientras nadie lo recupere. A.R6: dueno LOCAL muerto (o pid
#     reciclado) se recupera SOLO, con reclamo atomico (mv-arbitro); dueno
#     vivo, host ajeno e identidad indeterminable jamas se tocan, y
#     --liberar-lock sigue siendo la salida explicita.
#     REINTENTO con el lock libre: re-corre el gate completo del modo (normal:
#     base/recibo/CI; revert: punta, SIN estado propio). LIMITE DECLARADO: dos
#     clones independientes NO se excluyen (common-dirs distintos) — se mide
#     para que quede fijado. Determinismo por gancho de test
#     SAIKIT_MERGE_SOSTENER_SEG (duerme con el lock tomado; produccion = 0).
#
# INFRAESTRUCTURA: git REAL en sandbox (origin bare local alcanzado via
# url.<path>.insteadOf de la URL github que espera el script) y gh FALSO que
# responde solo las formas que el script usa, con argv grabado en un log. El
# recibo APPROVE lead <sha> se siembra en el fixture de comments del PR; el
# modo normal corre SIN directorios de estado, SIN veredicto sellado y SIN
# harness-evidence.log, y es repetible desde otro host (A3). El contrato
# del recibo en si lo prueba tests/test_entrega_contract.sh.
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
  # 20.28 costura: SB siempre detras de un symlink deliberado para que la
  # forma logica ($SB/...) difiera de pwd -P en CUALQUIER plataforma (tambien
  # cuando /tmp es real, como en ubuntu-latest). Sin esto el fix del lock es
  # inerte en CI.
  if [ -n "${SB_LINK_ROOT:-}" ]; then
    rm -rf "$SB_LINK_ROOT" "${SB_PHYS:-}"
  elif [ -n "${SB:-}" ]; then
    rm -rf "$SB"
  fi
  SB_PHYS="$(mktemp -d "${TMPDIR:-/tmp}/saikit-merge-phys-XXXXXX")" || exit 1
  SB_LINK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/saikit-merge-link-XXXXXX")" || exit 1
  ln -sfn "$SB_PHYS" "$SB_LINK_ROOT/logical"
  SB="$SB_LINK_ROOT/logical"
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
  "api repos/"*) forma=comments ;;
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
  "api repos/"*) emitir "$fix/comments.json"; exit 0 ;;
  "run list")  emitir "$fix/runs.json"; exit 0 ;;
  "pr view")
    case "$*" in
      *mergeCommit*) emitir "$fix/pr-merge.json" ;;
      *) # A5: con pr-head-2.json el head se MUEVE entre lecturas (la 1a
         # trae pr.json, las siguientes pr-head-2.json): simula un push
         # durante la comprobacion. Sin ese fixture, siempre pr.json.
         if [ -f "$fix/pr-head-2.json" ]; then
           cnt="$(cat "$fix/pr-view-count" 2>/dev/null || printf 0)"
           printf '%s' "$((cnt + 1))" > "$fix/pr-view-count"
           if [ "$cnt" -ge 1 ]; then emitir "$fix/pr-head-2.json"; else emitir "$fix/pr.json"; fi
         else
           emitir "$fix/pr.json"
         fi ;;
    esac
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
  # A3: el modo normal NO consulta estado de sesion (SAIKIT_ESTADO_ROOT se
  # fija solo en el caso de dos hosts, para probar que se ignora).
  export SAIKIT_ORDEN_LOG="$SB/orden.log"
  : > "$SAIKIT_ORDEN_LOG"
  export SAIKIT_MERGE_RETRY_SEG=0
  export PATH="$SB/bin:$PATH"
  # 18.25: el banco no hereda el entorno de color del corredor (ni un knob
  # del falso dejado por un caso anterior): cada caso arranca determinista.
  unset NO_COLOR CLICOLOR CLICOLOR_FORCE SAIKIT_GH_ANSI SAIKIT_GH_ANSI_SOLO

  refix
}

# cuerpo_aprobacion <sha> <lead> <impl> <ver> <rev> <v-res> <r-res> <bloq-json>
# — cuerpo (ya escapado para vivir dentro de un string JSON) de un comentario
# APPROVE lead <sha> con bloque ```json saikit-entrega.v1. El <bloq-json> va en
# crudo (p.ej. [{"id":"B1"}]) y se escapa junto al resto.
cuerpo_aprobacion() {
  local sha="$1" lead="$2" impl="$3" ver="$4" rev="$5" vres="$6" rres="$7" bloq="$8"
  local recibo recibo_esc
  [ -n "$bloq" ] || bloq="[]"
  recibo="$(printf '{"schema":"saikit-entrega.v1","repo":"op/sandbox","pr":7,"sha":"%s","clase":"codigo","implementer":{"id":"%s","evidencia":"artifact:implementacion"},"verifier":{"id":"%s","resultado":"%s","evidencia":"artifact:verificacion"},"reviewer":{"id":"%s","resultado":"%s","evidencia":"artifact:revision"},"ci":{"workflow":"ci","evidencia":"artifact:ci"},"bloqueantes":%s,"residuales":[]}' "$sha" "$impl" "$ver" "$vres" "$rev" "$rres" "$bloq")"
  recibo_esc="$(printf '%s' "$recibo" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  printf 'APPROVE lead %s\\n\\n```json\\n%s\\n```\\n' "$sha" "$recibo_esc"
}

# sembrar_recibo: siembra el comentario APPROVE lead <SHA> con un recibo
# completo en el fixture de comments. A3: NADA de estado del hook, veredicto
# ni evidence log — el feliz corre sin ninguno.
sembrar_recibo() {
  printf '[{"user":{"login":"op"},"body":"%s"}]' "$(cuerpo_aprobacion "$SHA" op worker-a worker-b worker-c PASS APPROVE "")" > "$SB/ghfix/comments.json"
}

refix() {
  SHA="$(git rev-parse HEAD)"
  printf '{"nameWithOwner":"op/sandbox"}' > "$SB/ghfix/repo.json"
  printf '{"login":"op"}' > "$SB/ghfix/user.json"
  printf '{"number":7,"baseRefName":"%s","headRefOid":"%s","author":{"login":"op"},"mergeable":"MERGEABLE"}' "$BASE_RAMA" "$SHA" > "$SB/ghfix/pr.json"
  printf '{"mergeCommit":{"oid":"f000000000000000000000000000000000000000"}}' > "$SB/ghfix/pr-merge.json"
  printf '[{"event":"pull_request","status":"completed","conclusion":"success","workflowName":"ci","number":42,"headSha":"%s"}]' "$SHA" > "$SB/ghfix/runs.json"

  sembrar_recibo
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
  correr --confirmado
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC"
  _contiene "merge ok" "$OUT" "MERGE-OK:"
  _contiene "squash" "$(cat "$SAIKIT_GH_LOG")" "--squash"
  _contiene "pinea el head" "$(cat "$SAIKIT_GH_LOG")" "--match-head-commit $SHA"
  _contiene "trailer en el body" "$(cat "$SAIKIT_GH_LOG")" "Saikit-Merge: $SHA"
  _no_contiene "nunca --admin" "$(cat "$SAIKIT_GH_LOG")" "--admin"
  _no_contiene "nunca --delete-branch en el merge" "$(cat "$SAIKIT_GH_LOG")" "--delete-branch"
  _contiene "registra merge_commit" "$(cat ".saikit/veredictos/$SHA.merge" 2>/dev/null)" "f000000000000000000000000000000000000000"
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
  for f in "^gh repo view" "^gh pr view --json number" "^gh api user" "^gh run list" "^gh api repos/" "^gh pr view 7 --json mergeCommit"; do
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

# ------------------------------------------------- entrega con recibo (A3)
caso "feliz_sin_estado_ni_veredicto_ni_log"
{
  # El feliz NO necesita directorios de estado, veredicto sellado ni
  # harness-evidence.log: el banco ya no siembra ninguno.
  [ ! -e "$SB/estado" ] || _mal "el banco sembro estado del hook"
  [ ! -e ".saikit/veredictos/$SHA.json" ] || _mal "el banco sembro un veredicto"
  [ -z "$(find "$SB" -name 'harness-evidence.log' 2>/dev/null)" ] || _mal "el banco sembro un evidence log"
  correr
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC: $OUT"
  _contiene "reporta LISTO" "$OUT" "LISTO:"
  if merge_disparado; then _mal "mergeo sin --confirmado"; fi
  correr --confirmado
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC: $OUT"
  _contiene "merge ok" "$OUT" "MERGE-OK:"
  _contiene "consulto el recibo del PR" "$(cat "$SAIKIT_GH_LOG")" "api repos/op/sandbox/issues/7/comments"
}
fin_caso "feliz_sin_estado_ni_veredicto_ni_log"

caso "repetible_desde_dos_hosts"
{
  # Sin estado de sesion, el gate es repetible: dos hosts con raices de
  # estado distintas (y vacias) llegan al mismo LISTO.
  SAIKIT_ESTADO_ROOT="$SB/estado-host-a" correr
  [ "$RC" -eq 0 ] || _mal "host A: rc esperaba 0, dio $RC: $OUT"
  _contiene "host A LISTO" "$OUT" "LISTO:"
  SAIKIT_ESTADO_ROOT="$SB/estado-host-b" correr
  [ "$RC" -eq 0 ] || _mal "host B: rc esperaba 0, dio $RC: $OUT"
  _contiene "host B LISTO" "$OUT" "LISTO:"
  unset SAIKIT_ESTADO_ROOT
}
fin_caso "repetible_desde_dos_hosts"

caso "restos_viejos_no_bloquean"
{
  # Reanudacion con restos del sello retirado: un harness-state.env viejo con
  # veredicto_sha256/linked_seal_session y un veredicto viejo se IGNORAN, no
  # se exigen ni bloquean.
  mkdir -p "$SB/estado/claude/12345/sess-vieja"
  printf 'task_hash=viejo\nagents_seen=implementer\nlane=full\nveredicto_sha256=aaaa\nlinked_seal_session=x\n' > "$SB/estado/claude/12345/sess-vieja/harness-state.env"
  printf 'verified: algo viejo\n' > "$SB/estado/claude/12345/sess-vieja/harness-evidence.log"
  export SAIKIT_ESTADO_ROOT="$SB/estado"
  mkdir -p .saikit/veredictos
  printf '{"sha":"viejo","pr":7}' > ".saikit/veredictos/viejo.json"
  correr
  unset SAIKIT_ESTADO_ROOT
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC: $OUT"
  _contiene "LISTO pese a restos viejos" "$OUT" "LISTO:"
}
fin_caso "restos_viejos_no_bloquean"

c_recibo_sin_reviewer() {
  CASO_ROJO=0; sb_reset master
  b="$(cuerpo_aprobacion "$SHA" op worker-a worker-b worker-c PASS APPROVE "")"
  b="$(printf '%s' "$b" | sed 's/\\"reviewer\\":{[^}]*}/\\"reviewer\\":{}/')"
  printf '[{"user":{"login":"op"},"body":"%s"}]' "$b" > "$SB/ghfix/comments.json"
  correr --confirmado
  _contiene "razon sin reviewer" "$OUT" "NO-MERGE: recibo:"
  _contiene "nombra reviewer" "$OUT" "reviewer"
  if merge_disparado; then _mal "invoco el merge sin reviewer en el recibo"; fi
}

caso "recibo_sin_reviewer_no_invoca_merge"
{
  c_recibo_sin_reviewer
}
fin_caso "recibo_sin_reviewer_no_invoca_merge"

caso "recibo_verifier_fail_no_merguea"
{
  b="$(cuerpo_aprobacion "$SHA" op worker-a worker-b worker-c FAIL APPROVE "")"
  printf '[{"user":{"login":"op"},"body":"%s"}]' "$b" > "$SB/ghfix/comments.json"
  correr --confirmado
  _contiene "razon verifier" "$OUT" "NO-MERGE: recibo:"
  _contiene "nombra PASS" "$OUT" "PASS"
  if merge_disparado; then _mal "mergeo con verifier FAIL en el recibo"; fi
}
fin_caso "recibo_verifier_fail_no_merguea"

caso "recibo_identidad_reutilizada_no_merguea"
{
  b="$(cuerpo_aprobacion "$SHA" op worker-a worker-b worker-b PASS APPROVE "")"
  printf '[{"user":{"login":"op"},"body":"%s"}]' "$b" > "$SB/ghfix/comments.json"
  correr --confirmado
  _contiene "razon identidad" "$OUT" "NO-MERGE: recibo:"
  _contiene "nombra reutilizada" "$OUT" "reutilizada"
  if merge_disparado; then _mal "mergeo con identidad reutilizada"; fi
}
fin_caso "recibo_identidad_reutilizada_no_merguea"

caso "recibo_bloqueante_abierto_no_merguea"
{
  b="$(cuerpo_aprobacion "$SHA" op worker-a worker-b worker-c PASS APPROVE '[{"id":"B1"}]')"
  printf '[{"user":{"login":"op"},"body":"%s"}]' "$b" > "$SB/ghfix/comments.json"
  correr --confirmado
  _contiene "razon bloqueante" "$OUT" "NO-MERGE: recibo:"
  _contiene "nombra bloqueante" "$OUT" "bloqueante"
  if merge_disparado; then _mal "mergeo con bloqueante abierto"; fi
}
fin_caso "recibo_bloqueante_abierto_no_merguea"

caso "recibo_sin_aprobacion_no_merguea"
{
  printf '[{"user":{"login":"op"},"body":"solo un comentario sin formato"}]' > "$SB/ghfix/comments.json"
  correr --confirmado
  _contiene "razon sin recibo" "$OUT" "NO-MERGE: recibo: sin recibo"
  if merge_disparado; then _mal "mergeo sin recibo en el PR"; fi
}
fin_caso "recibo_sin_aprobacion_no_merguea"

caso "recibo_revocado_no_merguea"
{
  b="$(cuerpo_aprobacion "$SHA" op worker-a worker-b worker-c PASS APPROVE "")"
  printf '[{"user":{"login":"op"},"body":"%s"},{"user":{"login":"op"},"body":"REVOKE lead %s: aparecio un bloqueante"}]' "$b" "$SHA" > "$SB/ghfix/comments.json"
  correr --confirmado
  _contiene "razon revocado" "$OUT" "NO-MERGE: recibo:"
  _contiene "nombra revocado" "$OUT" "revocado"
  if merge_disparado; then _mal "mergeo con el recibo revocado"; fi
}
fin_caso "recibo_revocado_no_merguea"

caso "base_conflictiva_no_merguea"
{
  sed -i.bak 's/"mergeable":"MERGEABLE"/"mergeable":"CONFLICTING"/' "$SB/ghfix/pr.json"
  rm -f "$SB/ghfix/pr.json.bak"
  correr --confirmado
  _contiene "razon no mergeable" "$OUT" "NO-MERGE: el PR no es mergeable (CONFLICTING)"
  if merge_disparado; then _mal "mergeo con base conflictiva"; fi
}
fin_caso "base_conflictiva_no_merguea"

caso "head_avanza_durante_comprobacion_no_merguea"
{
  # A5: un push entre la lectura inicial y el efecto cambia el head; el gate
  # lo detecta al re-leer y no mergea.
  printf '{"number":7,"baseRefName":"%s","headRefOid":"ffffffffffffffffffffffffffffffffffffffff","author":{"login":"op"},"mergeable":"MERGEABLE"}' "$BASE_RAMA" > "$SB/ghfix/pr-head-2.json"
  correr --confirmado
  _contiene "razon head movido" "$OUT" "NO-MERGE: el head del PR avanzo durante la comprobacion"
  if merge_disparado; then _mal "mergeo con el head movido durante la comprobacion"; fi
}
fin_caso "head_avanza_durante_comprobacion_no_merguea"

c_head_avanza() {
  CASO_ROJO=0; sb_reset master
  printf '{"number":7,"baseRefName":"%s","headRefOid":"ffffffffffffffffffffffffffffffffffffffff","author":{"login":"op"},"mergeable":"MERGEABLE"}' "$BASE_RAMA" > "$SB/ghfix/pr-head-2.json"
  correr --confirmado
  _contiene "razon head movido" "$OUT" "NO-MERGE: el head del PR avanzo durante la comprobacion"
  if merge_disparado; then _mal "mergeo con el head movido durante la comprobacion"; fi
}

c_ci_intento_viejo() {
  # A4: un intento viejo fallido del MISMO workflow, reemplazado por un verde
  # nuevo, no bloquea: se juzga lo vigente.
  CASO_ROJO=0; sb_reset master
  printf '[{"event":"pull_request","status":"completed","conclusion":"failure","workflowName":"ci","number":41,"headSha":"%s"},{"event":"pull_request","status":"completed","conclusion":"success","workflowName":"ci","number":42,"headSha":"%s"}]' "$SHA" "$SHA" > "$SB/ghfix/runs.json"
  correr --confirmado
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC: $OUT"
  _contiene "merge ok" "$OUT" "MERGE-OK:"
}

caso "ci_intento_viejo_reemplazado_pasa"
{
  c_ci_intento_viejo
}
fin_caso "ci_intento_viejo_reemplazado_pasa"

c_ci_workflow_ajeno() {
  CASO_ROJO=0; sb_reset master
  printf '[{"event":"pull_request","status":"completed","conclusion":"success","workflowName":"docs-only-smoke","number":42,"headSha":"%s"}]' "$SHA" > "$SB/ghfix/runs.json"
  correr --confirmado
  [ "$RC" -ne 0 ] || _mal "mergeo con un workflow distinto del acreditado por el recibo"
  _contiene "nombra workflow requerido" "$OUT" "workflow requerido"
  if merge_disparado; then _mal "invoco el merge sin CI del workflow acreditado"; fi
}

caso "ci_verde_de_workflow_no_acreditado_no_merguea"
{
  c_ci_workflow_ajeno
}
fin_caso "ci_verde_de_workflow_no_acreditado_no_merguea"

caso "ci_verde_viejo_reemplazado_por_rojo_no_merguea"
{
  printf '[{"event":"pull_request","status":"completed","conclusion":"success","workflowName":"ci","number":41,"headSha":"%s"},{"event":"pull_request","status":"completed","conclusion":"failure","workflowName":"ci","number":42,"headSha":"%s"}]' "$SHA" "$SHA" > "$SB/ghfix/runs.json"
  correr --confirmado
  _contiene "razon CI rojo" "$OUT" "NO-MERGE: CI rojo"
  if merge_disparado; then _mal "mergeo con el intento vigente en rojo"; fi
}
fin_caso "ci_verde_viejo_reemplazado_por_rojo_no_merguea"

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
  printf '[{"event":"pull_request","status":"completed","conclusion":"failure","workflowName":"ci","number":42}]' > "$SB/ghfix/runs.json"
  correr --confirmado
  _contiene "razon CI rojo" "$OUT" "NO-MERGE: CI rojo"
  if merge_disparado; then _mal "mergeo con CI rojo"; fi
}
fin_caso "ci_rojo_no_merguea"

caso "ci_verde_de_otro_sha_no_merguea"
{
  printf '[{"event":"pull_request","status":"completed","conclusion":"success","workflowName":"ci","number":42,"headSha":"0000000000000000000000000000000000000000"}]' > "$SB/ghfix/runs.json"
  correr --confirmado
  _contiene "razon sha ajeno" "$OUT" "NO-MERGE: CI verde pero de otro sha"
  if merge_disparado; then _mal "mergeo con verde de otro sha"; fi
}
fin_caso "ci_verde_de_otro_sha_no_merguea"

caso "ci_sin_headSha_no_merguea"
{
  printf '[{"event":"pull_request","status":"completed","conclusion":"success","workflowName":"ci","number":42}]' > "$SB/ghfix/runs.json"
  correr --confirmado
  _contiene "razon sin headSha" "$OUT" "NO-MERGE: CI sin headSha"
  if merge_disparado; then _mal "mergeo con verde sin headSha"; fi
}
fin_caso "ci_sin_headSha_no_merguea"

caso "ci_headSha_null_no_merguea"
{
  printf '[{"event":"pull_request","status":"completed","conclusion":"success","workflowName":"ci","number":42,"headSha":null}]' > "$SB/ghfix/runs.json"
  correr --confirmado
  _contiene "razon sin headSha" "$OUT" "NO-MERGE: CI sin headSha"
  if merge_disparado; then _mal "mergeo con verde y headSha null"; fi
}
fin_caso "ci_headSha_null_no_merguea"

c_ci_skipped() {
  CASO_ROJO=0; sb_reset master
  printf '[{"event":"pull_request","status":"completed","conclusion":"skipped","workflowName":"ci","number":42}]' > "$SB/ghfix/runs.json"
  correr --confirmado
  _contiene "razon CI rojo" "$OUT" "NO-MERGE: CI rojo"
  _contiene "nombra skipped" "$OUT" "skipped"
  if merge_disparado; then _mal "mergeo con CI skipped"; fi
}

c_solo_push() {
  CASO_ROJO=0; sb_reset master
  printf '[{"event":"push","status":"completed","conclusion":"success","workflowName":"ci","number":42,"headSha":"%s"}]' "$SHA" > "$SB/ghfix/runs.json"
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
  printf '[{"event":"pull_request","status":"in_progress","conclusion":null,"workflowName":"ci","number":42}]' > "$SB/ghfix/runs.json"
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
  # 22.3: el verde del fixture es del HEAD del revert, no del feat/task que
  # dejo refix (HEAD avanzo con el merge de master + el revert).
  printf '[{"event":"pull_request","status":"completed","conclusion":"success","workflowName":"ci","number":42,"headSha":"%s"}]' "$RHEAD" > "$SB/ghfix/runs.json"
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
  # Misma forma fisica que la tool (pwd -P). La costura de sb_reset hace que
  # $SB/... (logico, via symlink) difiera de pwd -P en toda plataforma (20.28).
  # SAIKIT_MUT_LOCK_SIN_CANON=1 fuerza el esperado logico (mutante).
  if [ "${SAIKIT_MUT_LOCK_SIN_CANON:-0}" = 1 ]; then
    lock_expect="$SB/work/.git/saikit-merge.lock"
  else
    lock_expect="$(cd "$SB/work/.git" && pwd -P)/saikit-merge.lock"
  fi
  SAIKIT_MERGE_SOSTENER_SEG=6 bash "$MERGE" --confirmado > "$SB/a.log" 2>&1 &
  a_pid=$!
  esperar_lock "$lock_expect" \
    || { _mal "A no tomo el lock (worktree); el caso no mide"; wait "$a_pid" 2>/dev/null; return; }
  cd "$SB/otro" || { _mal "no se pudo entrar al worktree hermano"; return; }
  OUT="$(bash "$MERGE" --confirmado 2>&1)"; RC=$?
  [ "$RC" -eq 3 ] || _mal "desde el worktree hermano deberia bloquearse con 3, dio $RC: $OUT"
  _contiene "reporta el lock COMPARTIDO (common-dir)" "$OUT" "$lock_expect"
  _contiene "muestra como liberarlo" "$OUT" "--liberar-lock"
  if merge_disparado; then _mal "el worktree hermano llamo merge"; fi
  cd "$SB/work" || exit 1
  kill -9 "$a_pid" 2>/dev/null; wait "$a_pid" 2>/dev/null
  OUT2="$(bash "$MERGE" --liberar-lock 2>&1)"; RC2=$?
  [ "$RC2" -eq 0 ] || _mal "liberar-lock fallo tras la caida del tenedor: $OUT2"
  [ ! -d "$lock_expect" ] || _mal "liberar-lock no quito el lock"
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
  # A.R6: el lock huerfano tiene dueno LOCAL muerto: la recuperacion
  # automatica con reclamo atomico lo recupera y el tercero SI sigue hasta el
  # merge. Sigue siendo cierto que la SALIDA del tercero no libera un lock
  # ajeno: aqui el lock era huerfano y lo recupera ANTES de trabajar.
  correr --confirmado
  [ "$RC" -eq 0 ] || _mal "con dueno local muerto el tercero debio recuperarse y mergear, dio $RC: $OUT"
  _contiene "dice que recupero" "$OUT" "recuperado con reclamo atomico"
  _contiene "clasifica muerto" "$OUT" "dueno local muerto"
  _contiene "merge ok tras recuperar" "$OUT" "MERGE-OK:"
  [ ! -d ".git/saikit-merge.lock" ] || _mal "el recuperador debio liberar su lock al salir"
  # La via EXPLICITA sigue viva: un lock plantado a mano lo quita --liberar-lock.
  mkdir -p ".git/saikit-merge.lock"
  printf '999999' > ".git/saikit-merge.lock/pid"
  printf "$(hostname 2>/dev/null || printf '?')" > ".git/saikit-merge.lock/host"
  printf "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || printf '?')" > ".git/saikit-merge.lock/started_at"
  printf 'merge' > ".git/saikit-merge.lock/modo"
  OUT2="$(bash "$MERGE" --liberar-lock 2>&1)"; RC2=$?
  [ "$RC2" -eq 0 ] || _mal "--liberar-lock fallo: $OUT2"
  _contiene "muestra el contenido antes de quitar" "$OUT2" "999999"
  [ ! -d ".git/saikit-merge.lock" ] || _mal "--liberar-lock no quito el lock"
  # Tras liberar, el reintento ya no esta bloqueado y llega al final del gate.
  correr --confirmado
  [ "$RC" -eq 0 ] || _mal "tras liberar, el reintento deberia llegar al gate y mergear, dio $RC: $OUT"
  _contiene "merge ok" "$OUT" "MERGE-OK:"
}

c_lock_reintento_revalida() {
  # REINTENTO revalida (modo normal): B bloqueado por el lock; tras liberar,
  # la base avanzo mientras esperaba y el reintento RE-CORRE el gate completo
  # (recibo incluido: es el mismo camino de siempre, ahora bajo el lock) y NO
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
  # recibo es cosa del modo normal).
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
  # A3: sin sello que sembrar — el clon hermano usa el mismo fixture de
  # comments (mismo HEAD, mismo SHA) y el gate no consulta estado.
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

plantar_lock_huerfano() {  # $1 pid, $2 host, $3 started_at
  mkdir -p ".git/saikit-merge.lock"
  printf '%s' "$1" > ".git/saikit-merge.lock/pid"
  printf '%s' "$2" > ".git/saikit-merge.lock/host"
  printf '%s' "$3" > ".git/saikit-merge.lock/started_at"
  printf 'merge' > ".git/saikit-merge.lock/modo"
}

c_lock_recuperar_muerto() {
  # A.R6, caso muerto: dueno LOCAL con pid inexistente. La recuperacion
  # automatica con reclamo atomico toma el lock y el gate sigue hasta el
  # merge; el clasificador lo nombra.
  CASO_ROJO=0; sb_reset master
  : > "$SAIKIT_GH_LOG"
  plantar_lock_huerfano 999999 "$(hostname 2>/dev/null || printf '?')" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  correr --confirmado
  [ "$RC" -eq 0 ] || _mal "debio recuperar el huerfano muerto y mergear, dio $RC: $OUT"
  _contiene "clasifica muerto" "$OUT" "dueno local muerto"
  _contiene "dice reclamo atomico" "$OUT" "recuperado con reclamo atomico"
  _contiene "merge ok" "$OUT" "MERGE-OK:"
  [ ! -d ".git/saikit-merge.lock" ] || _mal "el recuperador debio liberar su lock al salir"
}

c_lock_recuperar_reciclado() {
  # A.R6, caso pid reutilizado: el pid vive pero el proceso es MAS JOVEN que
  # el lock, asi que el que lo tomo ya no existe. Misma recuperacion, con su
  # propia clasificacion.
  CASO_ROJO=0; sb_reset master
  : > "$SAIKIT_GH_LOG"
  sleep 30 & rec_pid=$!
  plantar_lock_huerfano "$rec_pid" "$(hostname 2>/dev/null || printf '?')" "2020-01-01T00:00:00Z"
  correr --confirmado
  kill "$rec_pid" 2>/dev/null; wait "$rec_pid" 2>/dev/null
  [ "$RC" -eq 0 ] || _mal "debio recuperar el pid reciclado y mergear, dio $RC: $OUT"
  _contiene "clasifica reciclado" "$OUT" "dueno local reciclado"
  _contiene "dice reclamo atomico" "$OUT" "recuperado con reclamo atomico"
  _contiene "merge ok" "$OUT" "MERGE-OK:"
  [ ! -d ".git/saikit-merge.lock" ] || _mal "el recuperador debio liberar su lock al salir"
}

c_lock_host_ajeno_no_se_toca() {
  # A.R6, caso host ajeno: el lock dice otro host; este clone no lo toca ni
  # con pid muerto (pudo vivir en otra maquina del common-dir compartido).
  CASO_ROJO=0; sb_reset master
  : > "$SAIKIT_GH_LOG"
  plantar_lock_huerfano 999999 "otro-host-de-otra-maquina" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  correr --confirmado
  [ "$RC" -eq 3 ] || _mal "un lock de host ajeno debe bloquear con 3, dio $RC: $OUT"
  _contiene "nombra el host ajeno" "$OUT" "otro host"
  if merge_disparado; then _mal "mergeo con el lock de otro host puesto"; fi
  [ -d ".git/saikit-merge.lock" ] || _mal "se toco el lock de un host ajeno"
  [ "$(cat .git/saikit-merge.lock/pid 2>/dev/null)" = "999999" ] || _mal "el contenido del lock ajeno cambio"
  bash "$MERGE" --liberar-lock >/dev/null 2>&1
}

c_lock_indeterminable_no_se_toca() {
  # A.R6, caso identidad indeterminable: sin pid no hay verificacion posible;
  # no se borra, se informa y el carril queda libre de seguir con otras filas.
  CASO_ROJO=0; sb_reset master
  : > "$SAIKIT_GH_LOG"
  plantar_lock_huerfano "" "$(hostname 2>/dev/null || printf '?')" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  correr --confirmado
  [ "$RC" -eq 3 ] || _mal "sin identidad debe bloquear con 3, dio $RC: $OUT"
  _contiene "nombra la identidad indeterminable" "$OUT" "identidad indeterminable"
  if merge_disparado; then _mal "mergeo con un lock sin identidad"; fi
  [ -d ".git/saikit-merge.lock" ] || _mal "se toco un lock sin identidad"
  bash "$MERGE" --liberar-lock >/dev/null 2>&1
}

c_lock_dos_recuperadores() {
  # A.R6, caso dos recuperadores: los dos ven el huerfano y quedan parqueados
  # DENTRO de la ventana (SAIKIT_MERGE_RECUPERAR_PAUSA, gancho de test). El
  # mv es el arbitro: exactamente uno recupera y mergea; el otro sale 3 sin
  # tocar nada. Un mutante que quite el reclamo atomico deja este caso rojo.
  CASO_ROJO=0; sb_reset master
  : > "$SAIKIT_GH_LOG"
  plantar_lock_huerfano 999999 "$(hostname 2>/dev/null || printf '?')" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  SAIKIT_MERGE_RECUPERAR_PAUSA=2 bash "$MERGE" --confirmado > "$SB/r1.log" 2>&1 &
  r1=$!
  SAIKIT_MERGE_RECUPERAR_PAUSA=2 bash "$MERGE" --confirmado > "$SB/r2.log" 2>&1 &
  r2=$!
  wait "$r1"; rc1=$?
  wait "$r2"; rc2=$?
  ganadores=0; bloqueados=0
  for par in "$rc1:$r1" "$rc2:$r2"; do
    rc="${par%%:*}"; quien="${par#*:}"
    log="$SB/r1.log"; [ "$quien" = "$r2" ] && log="$SB/r2.log"
    if [ "$rc" -eq 0 ]; then
      ganadores=$((ganadores + 1))
      grep -q "recuperado con reclamo atomico" "$log"         || _mal "el ganador no dice que recupero: $(cat "$log")"
    else
      bloqueados=$((bloqueados + 1))
      grep -q "LOCK de integracion ocupado" "$log"         || _mal "el perdedor no reporta el lock ocupado (rc $rc): $(cat "$log")"
    fi
  done
  [ "$ganadores" -eq 1 ] || _mal "exactamente un recuperador debio ganar, hubo $ganadores"
  [ "$bloqueados" -eq 1 ] || _mal "exactamente un recuperador debio bloquearse, hubo $bloqueados"
  [ ! -d ".git/saikit-merge.lock" ] || _mal "el ganador debio liberar su lock al salir"
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
  # Costura symlink de sb_reset + forzar esperado logico. Debe quedar ROJO
  # (CASO_ROJO=1); si sobrevive en verde el mutante no discrimina.
  CASO_ROJO=0
  SAIKIT_MUT_LOCK_SIN_CANON=1
  c_lock_dos_worktrees
  unset SAIKIT_MUT_LOCK_SIN_CANON
  if [ "$CASO_ROJO" -eq 0 ]; then
    _mal "mutante sin canon sobrevivio en verde bajo costura symlink"
  else
    CASO_ROJO=0
    printf '    ok: mutante sin canon queda rojo (costura symlink)\n'
  fi
}
fin_caso "mutante_lock_path_sin_canonicalizar_se_pone_rojo"

caso "lock_recupera_dueno_local_muerto"
{
  c_lock_recuperar_muerto
}
fin_caso "lock_recupera_dueno_local_muerto"

caso "lock_recupera_pid_reciclado"
{
  c_lock_recuperar_reciclado
}
fin_caso "lock_recupera_pid_reciclado"

caso "lock_host_ajeno_no_se_toca"
{
  c_lock_host_ajeno_no_se_toca
}
fin_caso "lock_host_ajeno_no_se_toca"

caso "lock_identidad_indeterminable_no_se_toca"
{
  c_lock_indeterminable_no_se_toca
}
fin_caso "lock_identidad_indeterminable_no_se_toca"

caso "lock_dos_recuperadores_un_solo_ganador"
{
  c_lock_dos_recuperadores
}
fin_caso "lock_dos_recuperadores_un_solo_ganador"

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
  # Fuera de SB_LINK_ROOT: sb_reset borra el arbol del symlink y $SB-mutado
  # (hermano de logical/) moria con el reset (20.28 costura).
  MUTADO="${TMPDIR:-/tmp}/saikit-merge-mutado-$$.sh"
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
  printf '[{"event":"pull_request","status":"in_progress","conclusion":null,"workflowName":"ci","number":42}]' > "$SB/ghfix/runs.json"
  correr --confirmado
  _contiene "razon CI pendiente" "$OUT" "NO-MERGE: CI pendiente"
  if merge_disparado; then _mal "mergeo con CI pendiente"; fi
}

c_ci_rojo() {
  CASO_ROJO=0; sb_reset master
  printf '[{"event":"pull_request","status":"completed","conclusion":"failure","workflowName":"ci","number":42}]' > "$SB/ghfix/runs.json"
  correr --confirmado
  _contiene "razon CI rojo" "$OUT" "NO-MERGE: CI rojo"
  if merge_disparado; then _mal "mergeo con CI rojo"; fi
}

c_ci_sha_ajeno() {
  CASO_ROJO=0; sb_reset master
  printf '[{"event":"pull_request","status":"completed","conclusion":"success","workflowName":"ci","number":42,"headSha":"0000000000000000000000000000000000000000"}]' > "$SB/ghfix/runs.json"
  correr --confirmado
  _contiene "razon sha ajeno" "$OUT" "NO-MERGE: CI verde pero de otro sha"
  if merge_disparado; then _mal "mergeo con verde de otro sha"; fi
}

c_ci_sha_ausente() {
  CASO_ROJO=0; sb_reset master
  printf '[{"event":"pull_request","status":"completed","conclusion":"success","workflowName":"ci","number":42}]' > "$SB/ghfix/runs.json"
  correr --confirmado
  _contiene "razon sin headSha" "$OUT" "NO-MERGE: CI sin headSha"
  if merge_disparado; then _mal "mergeo con verde sin headSha"; fi
}

c_base_avanzada() {
  CASO_ROJO=0; sb_reset master
  avanzar_base
  correr --confirmado
  _contiene "razon base avanzada" "$OUT" "NO-MERGE: base avanzada"
  if merge_disparado; then _mal "mergeo con base vieja"; fi
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




c_borrado() {
  CASO_ROJO=0; sb_reset master
  printf '#!/bin/sh\necho delete >> "%s/orden.log"\nexit 1\n' "$SB" > "$SB/origin.git/hooks/pre-receive"
  chmod +x "$SB/origin.git/hooks/pre-receive"
  correr --confirmado
  _contiene "reporta el borrado fallido" "$OUT" "BORRADO-FALLO"
  n="$(grep -c delete "$SB/orden.log" 2>/dev/null || true)"
  [ "$n" -eq 1 ] || _mal "intentos de borrado: esperaba 1, hubo ${n:-0}"
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
ci_sin_chequeo_sha	s#\[ "\$head" != "\$SHA" \]#false#	c_ci_sha_ajeno
ci_sin_presence_sha	s#if \[ -z "\$head" \] || \[ "\$head" = "<null>" \]; then#if false; then#	c_ci_sha_ausente
skipped_es_verde	s/\[ "\$conc" != success \]/[ "$conc" != success ] \&\& [ "$conc" != skipped ]/	c_ci_skipped
solo_push_exige_pr	s/\[ "\$n" -gt 0 \] || no_merge "sin checks/[ "$hay_pr" = 0 ] \&\& no_merge "exige pull_request"; [ "$n" -gt 0 ] || no_merge "sin checks/	c_solo_push
base_vieja_pasa	s/git merge-base --is-ancestor "\$ORIGEN" HEAD/true/	c_base_avanzada
rama_base_floja	s|\[ "\$CFG_RAMA" != "\$PR_BASE" \]|false|	c_rama_base
email_ajeno_pasa	s|no_merge "commit de otro email: \$csha es de \$email"|continue|	c_email
borrado_reintenta	s|^  borrado_remoto$|  borrado_remoto; borrado_remoto|	c_borrado
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
recuperacion_sin_arbitro	s|if mv "$LOCK_DIR" "$tumba" 2>/dev/null \|if cp -R "$LOCK_DIR" "$tumba" 2>/dev/null \|	c_lock_dos_recuperadores
trap_no_libera	s|^liberar_propio() {$|liberar_propio() { return 0; #|	c_lock_libera_propio
recibo_opcional	s/$(entrega_validar/$(true/	c_recibo_sin_reviewer
ci_juzga_intento_viejo	s/\$2 > bestnum\[$1\]/$2 < bestnum[$1]/	c_ci_intento_viejo
ci_acepta_workflow_ajeno	s/if \[ -n "\$requerido" \] \&\& \[ "\$w" != "\$requerido" \]; then/if false; then/	c_ci_workflow_ajeno
recheck_head_opcional	s/no_merge "el head del PR avanzo/true # sin recheck; no_merge "el head del PR avanzo/	c_head_avanza
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
  [ -n "${SB_LINK_ROOT:-}" ] && rm -rf "$SB_LINK_ROOT" "${SB_PHYS:-}"
  exit 1
fi
[ -n "${SB_LINK_ROOT:-}" ] && rm -rf "$SB_LINK_ROOT" "${SB_PHYS:-}"
echo "test_saikit_merge: OK"
