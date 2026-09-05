#!/usr/bin/env bash
# tests/test_ci_minimo.sh - Task CI minimo cuando no hay (D22).
#
# QUE AFIRMA (DoD de la fila, columna 3 de Plans.md):
#   - Cableado: setup INVOCA al generador (--ofrecer --root <work>).
#   - Aceptacion: --ci-minimo si escribe .github/workflows/saikit-ci-minimo.yml
#     con run: reales (test + verify), uses @sha40 y sin secrets.
#   - Default no sin TTY: no escribe; avisa que sin CI no mergea.
#   - PRESENTE: un workflow ajeno no se pisa.
#   - Tras declinar, merge con runs vacios => NO-MERGE sin checks.
#   - Cada guarda tiene mutacion discriminante (pin, secrets, cableado,
#     run solo en comentario).
#
# INFRAESTRUCTURA: git REAL en sandbox (mismo patron que
# tests/test_autopilot_config.sh). Sin acentos en este archivo.
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
SETUP_REAL="$repo/tools/saikit-setup-autopilot.sh"
SETUP="${SAIKIT_SETUP_TOOL:-$SETUP_REAL}"
GEN_REAL="$repo/tools/saikit-ci-minimo.sh"
GEN="$GEN_REAL"
MERGE="$repo/tools/saikit-merge.sh"

fail=0
CASO_ROJO=0
_mal()      { printf '      FAIL: %s\n' "$1"; CASO_ROJO=1; }
_contiene() { if ! printf '%s' "$2" | grep -Fq -- "$3"; then _mal "$1: no contiene [$3]"; fi; }

SB=""
OUT=""
RC=0

# ------------------------------------------------------------------ sandbox
sb_reset() {
  [ -n "$SB" ] && rm -rf "$SB"
  SB="$(mktemp -d "${TMPDIR:-/tmp}/saikit-ci-minimo-XXXXXX")" || exit 1
  git init --bare -q "$SB/origin.git"
  git clone -q "$SB/origin.git" "$SB/work" 2>/dev/null
  cd "$SB/work" || exit 1
  git symbolic-ref HEAD refs/heads/master
  git config user.email op@example.com
  git config user.name op
  printf 'base\n' > app.sh
  git add app.sh
  git commit -qm "chore: base"
  git push -q origin master
  mkdir -p tests
  printf '#!/usr/bin/env bash\nexit 0\n' > tests/run.sh
}

caso() { printf '  caso: %s\n' "$1"; CASO_ROJO=0; sb_reset; }
fin_caso() {
  if [ "$CASO_ROJO" -ne 0 ]; then
    printf '    ROJO: %s\n' "$1" >&2
    fail=1
  else
    printf '    ok: %s\n' "$1"
  fi
}

flags_setup() {
  printf '%s' '--merge no --despliega no --sin-verify-app no --telegram no'
}

correr_setup() {
  # shellcheck disable=SC2046
  OUT="$(bash "$SETUP" $(flags_setup) "$@" 2>&1)"
  RC=$?
}

correr_gen() {
  OUT="$(bash "$GEN" --ofrecer --root "$SB/work" "$@" 2>&1)"
  RC=$?
}

yml_dest() { printf '%s' "$SB/work/.github/workflows/saikit-ci-minimo.yml"; }

# Extrae lineas run: reales. Un '# run: ...' NO cuenta.
run_reales() {  # $1=yaml → stdout con las lineas run:
  [ -f "$1" ] || return 1
  grep -E '^[[:space:]]*run:' "$1" || true
}

# 0 si hay un run de test y uno de verify. El YAML solo-comentario falla.
afirma_run_reales() {  # $1=yaml
  local lineas
  lineas="$(run_reales "$1")"
  printf '%s\n' "$lineas" | grep -Eq 'bash tests/run\.sh|npm test|python -m pytest' || return 1
  printf '%s\n' "$lineas" | grep -Fq 'verify' || return 1
  return 0
}

afirma_sin_secrets() {  # $1=yaml
  [ -f "$1" ] || return 1
  ! grep -Fq 'secrets.' "$1"
}

# Cada uses: termina en @ + 40 hex. Tags (@v4) fallan.
# Cero uses: tambien falla (un workflow minimo sin checkout no cumple).
afirma_uses_sha() {  # $1=yaml
  local linea rest sha n=0
  [ -f "$1" ] || return 1
  while IFS= read -r linea; do
    n=$((n + 1))
    rest="${linea#*uses:}"
    rest="${rest#"${rest%%[![:space:]]*}"}"
    sha="${rest##*@}"
    sha="${sha%%[[:space:]#]*}"
    printf '%s' "$sha" | grep -Eq '^[0-9a-f]{40}$' || return 1
  done < <(grep -E '^[[:space:]]*(-[[:space:]]*)?uses:' "$1")
  [ "$n" -gt 0 ]
}

# ------------------------------------------------------------------ casos
caso "setup_invoca_generador"
{
  cat > "$SB/spy.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${SAIKIT_SPY_LOG:?}"
exit 0
EOF
  chmod +x "$SB/spy.sh"
  export SAIKIT_SPY_LOG="$SB/spy.argv"
  OUT="$(SAIKIT_CI_MINIMO="$SB/spy.sh" bash "$SETUP" --merge no --despliega no \
    --sin-verify-app no --telegram no < /dev/null 2>&1)"
  RC=$?
  [ "$RC" -eq 0 ] || _mal "setup deberia salir 0 con spy, dio $RC: $OUT"
  [ -f "$SAIKIT_SPY_LOG" ] || { _mal "el spy no fue invocado"; }
  if [ -f "$SAIKIT_SPY_LOG" ]; then
    _contiene "spy recibio --ofrecer" "$(cat "$SAIKIT_SPY_LOG")" "--ofrecer"
    root_esp="$(git -C "$SB/work" rev-parse --show-toplevel)"
    _contiene "spy recibio --root" "$(cat "$SAIKIT_SPY_LOG")" "--root"
    _contiene "spy recibio el work" "$(cat "$SAIKIT_SPY_LOG")" "$root_esp"
  fi
  unset SAIKIT_SPY_LOG
}
fin_caso "setup_invoca_generador"

caso "acepta_escribe_workflow"
{
  correr_setup --ci-minimo si < /dev/null
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC: $OUT"
  [ -f "$(yml_dest)" ] || _mal "no escribio $(yml_dest): $OUT"
}
fin_caso "acepta_escribe_workflow"

caso "run_reales_test_y_verify"
{
  correr_setup --ci-minimo si < /dev/null
  [ -f "$(yml_dest)" ] || _mal "no escribio el workflow: $OUT"
  if [ -f "$(yml_dest)" ]; then
    afirma_run_reales "$(yml_dest)" || _mal "faltan run: reales de test o verify"
  fi
}
fin_caso "run_reales_test_y_verify"

caso "comentario_no_cuenta_como_run"
{
  # El helper tiene que rechazar un run que solo vive en comentario.
  printf '# run: bash tests/run.sh\n# run: verify/\n' > "$SB/solo-comentario.yml"
  if afirma_run_reales "$SB/solo-comentario.yml"; then
    _mal "el helper acepto run: solo en comentario"
  fi
}
fin_caso "comentario_no_cuenta_como_run"

caso "sin_secrets"
{
  correr_setup --ci-minimo si < /dev/null
  [ -f "$(yml_dest)" ] || _mal "no escribio el workflow: $OUT"
  if [ -f "$(yml_dest)" ]; then
    afirma_sin_secrets "$(yml_dest)" || _mal "el YAML menciona secrets."
  fi
}
fin_caso "sin_secrets"

caso "uses_son_sha_40"
{
  correr_setup --ci-minimo si < /dev/null
  [ -f "$(yml_dest)" ] || _mal "no escribio el workflow: $OUT"
  if [ -f "$(yml_dest)" ]; then
    afirma_uses_sha "$(yml_dest)" || _mal "hay un uses: que no es @sha de 40 hex"
  fi
}
fin_caso "uses_son_sha_40"

caso "guardas_discriminantes"
{
  # Cada guarda falla por SU razon, no por la de al lado.
  cat > "$SB/tag.yml" <<'EOF'
name: x
jobs:
  ci:
    steps:
      - uses: actions/checkout@v4.2.2
      - name: test
        run: bash tests/run.sh
      - name: verify/
        run: bash -c 'if [ -d verify ]; then find verify -type f | head -n 5; else echo saikit: verify/ ausente; fi'
EOF
  afirma_sin_secrets "$SB/tag.yml" || _mal "tag.yml no tiene secrets; sin_secrets no debia fallar"
  afirma_run_reales "$SB/tag.yml" || _mal "tag.yml tiene run: reales; run_reales no debia fallar"
  if afirma_uses_sha "$SB/tag.yml"; then
    _mal "uses @v4 debia fallar la guarda de pin"
  fi

  cat > "$SB/sec.yml" <<'EOF'
name: x
jobs:
  ci:
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683
      - name: test
        run: bash tests/run.sh
      - name: verify/
        run: bash -c 'if [ -d verify ]; then find verify -type f | head -n 5; else echo saikit: verify/ ausente; fi'
      - name: leak
        run: echo ${{ secrets.FOO }}
EOF
  afirma_uses_sha "$SB/sec.yml" || _mal "sec.yml tiene sha 40; uses_sha no debia fallar"
  afirma_run_reales "$SB/sec.yml" || _mal "sec.yml tiene run: reales; run_reales no debia fallar"
  if afirma_sin_secrets "$SB/sec.yml"; then
    _mal "secrets.FOO debia fallar la guarda de secrets"
  fi

  cat > "$SB/com.yml" <<'EOF'
name: x
jobs:
  ci:
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683
      # run: bash tests/run.sh
      # run: verify/
EOF
  afirma_uses_sha "$SB/com.yml" || _mal "com.yml tiene sha 40; uses_sha no debia fallar"
  afirma_sin_secrets "$SB/com.yml" || _mal "com.yml no tiene secrets; sin_secrets no debia fallar"
  if afirma_run_reales "$SB/com.yml"; then
    _mal "run solo en comentario debia fallar run_reales"
  fi
}
fin_caso "guardas_discriminantes"

caso "default_no_sin_tty"
{
  correr_setup < /dev/null
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC: $OUT"
  [ ! -e "$(yml_dest)" ] || _mal "escribio el workflow sin TTY y sin flag"
  if ! printf '%s' "$OUT" | grep -Eq 'no mergea|sin checks'; then
    _mal "no aviso que sin CI no mergea / sin checks: $OUT"
  fi
}
fin_caso "default_no_sin_tty"

caso "presente_no_pisa"
{
  mkdir -p .github/workflows
  printf 'name: ajeno\non: push\njobs:\n  x:\n    runs-on: ubuntu-latest\n    steps:\n      - run: true\n' \
    > .github/workflows/ajeno.yml
  antes="$(cksum < .github/workflows/ajeno.yml)"
  correr_setup --ci-minimo si < /dev/null
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC: $OUT"
  [ "$(cksum < .github/workflows/ajeno.yml)" = "$antes" ] || _mal "piso el workflow ajeno"
  [ ! -e "$(yml_dest)" ] || _mal "escribio el nuestro encima de uno presente"
}
fin_caso "presente_no_pisa"

caso "flag_ci_minimo_exige_valor"
{
  OUT="$(timeout 5 bash "$SETUP" --ci-minimo 2>&1)"
  RC=$?
  [ "$RC" -eq 2 ] || _mal "rc esperaba 2, dio $RC: $OUT"
  _contiene "nombra que exige valor" "$OUT" "exige un valor"
  if printf '%s' "$OUT" | grep -Fq 'opcion desconocida'; then
    _mal "trato --ci-minimo como desconocida, no como flag con valor"
  fi
}
fin_caso "flag_ci_minimo_exige_valor"

caso "generador_solo"
{
  correr_gen --ci-minimo si
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC: $OUT"
  [ -f "$(yml_dest)" ] || _mal "el generador solo no escribio el workflow: $OUT"
}
fin_caso "generador_solo"

caso "idempotente_segunda_corrida"
{
  correr_gen --ci-minimo si
  [ -f "$(yml_dest)" ] || _mal "primera corrida no escribio: $OUT"
  antes="$(cksum < "$(yml_dest)")"
  correr_gen --ci-minimo si
  [ "$RC" -eq 0 ] || _mal "segunda corrida rc=$RC: $OUT"
  [ "$(cksum < "$(yml_dest)")" = "$antes" ] || _mal "la segunda corrida reescribio el yaml"
}
fin_caso "idempotente_segunda_corrida"

caso "merge_sin_checks_tras_declinar"
{
  # Camino de producto: declinar el offer y el veto de merge sigue en pie.
  correr_setup --merge si --despliega no --sin-verify-app no --telegram no --ci-minimo no < /dev/null
  [ "$RC" -eq 0 ] || _mal "setup al declinar deberia salir 0, dio $RC: $OUT"
  [ ! -e "$(yml_dest)" ] || _mal "declinar no debia escribir el workflow"
  if printf '%s' "$OUT" | grep -q ci_scaffold; then
    _mal "el setup metio ci_scaffold (no va en el JSON)"
  fi

  git config "url.$SB/origin.git.insteadOf" "https://github.com/op/sandbox.git"
  git remote set-url origin "https://github.com/op/sandbox.git"
  git add .saikit/autopilot.json
  git commit -qm "chore: config autopilot"
  git push -q origin master

  git checkout -qb feat/task
  printf 'app v2\n' >> app.sh
  git commit -qam "feat: task"
  git push -q origin feat/task

  mkdir -p "$SB/bin" "$SB/ghfix"
  cat > "$SB/bin/gh" <<'GHEOF'
#!/usr/bin/env bash
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

  SHA="$(git rev-parse HEAD)"
  printf '{"nameWithOwner":"op/sandbox"}' > "$SB/ghfix/repo.json"
  printf '{"login":"op"}' > "$SB/ghfix/user.json"
  printf '{"number":7,"baseRefName":"master","headRefOid":"%s","author":{"login":"op"},"mergeable":"MERGEABLE"}' "$SHA" > "$SB/ghfix/pr.json"
  printf '{"mergeCommit":{"oid":"f000000000000000000000000000000000000000"}}' > "$SB/ghfix/pr-merge.json"
  printf '[]' > "$SB/ghfix/runs.json"

  mkdir -p .saikit/veredictos
  printf '{"sha":"%s","pr":7,"verifier":"PASS","verify_app":{"resultado":"PASS","comando":"bash verify/app.sh"},"blast":{"nivel":4,"hecho":"el drive de la app corre","comando":"bash tests/run.sh"},"adversary":"n/a","reviewer":"clean","decisiones":".saikit/decisiones/18.8.tsv"}' "$SHA" > ".saikit/veredictos/$SHA.json"

  key="$(printf '%s' "$(pwd -P)" | cksum | cut -d' ' -f 1)"
  sd="$SB/estado/claude/$key/sess1"
  mkdir -p "$sd"
  {
    printf 'task_hash=h188\n'
    printf 'agents_seen=implementer,verifier,reviewer\n'
    printf 'lane=full\n'
    printf 'veredicto_sha256=%s\n' "$(sha256sum ".saikit/veredictos/$SHA.json" | cut -d' ' -f 1)"
  } > "$sd/harness-state.env"
  printf 'prompt task started: h188\nverified: bash tests/run.sh\nagent: reviewer\n' > "$sd/harness-evidence.log"

  OUT="$(bash "$MERGE" --confirmado 2>&1)"
  RC=$?
  [ "$RC" -ne 0 ] || _mal "merge debia rechazar sin checks, rc=$RC: $OUT"
  _contiene "razon sin checks" "$OUT" "NO-MERGE: sin checks"
  if grep -q '^gh pr merge' "$SAIKIT_GH_LOG" 2>/dev/null; then
    _mal "mergeo sin checks tras declinar el CI minimo"
  fi
}
fin_caso "merge_sin_checks_tras_declinar"

# ------------------------------------------------------- mutation-test
mut_sed_setup() {  # $1=sed-expr
  BASE="$SB-base-$$.sh"
  MUTADO="$SB-mutado-$$.sh"
  sed "s|^HERE=.*$|HERE=$repo/tools|" "$SETUP_REAL" > "$BASE"
  sed "$1" "$BASE" > "$MUTADO"
}

mut_sed_gen() {  # $1=sed-expr
  BASE="$SB-base-$$.sh"
  MUTADO="$SB-mutado-$$.sh"
  sed "s|^HERE=.*$|HERE=$repo/tools|" "$GEN_REAL" > "$BASE"
  sed "$1" "$BASE" > "$MUTADO"
}

correr_mutacion() {  # $1=nombre $2=sed-expr $3=fun $4=setup|gen
  local nombre="$1" expr="$2" fun="$3" sobre="${4:-gen}"
  if [ "$sobre" = setup ]; then
    mut_sed_setup "$expr"
  else
    mut_sed_gen "$expr"
  fi
  if [ ! -f "$BASE" ] || [ ! -f "$MUTADO" ]; then
    printf '    FAIL: mutacion %s no produjo archivos\n' "$nombre" >&2
    fail=1
    return
  fi
  if cmp -s "$BASE" "$MUTADO"; then
    printf '    FAIL: mutacion %s no cambio nada - el sed quedo obsoleto\n' "$nombre" >&2
    fail=1
    rm -f "$MUTADO" "$BASE"
    return
  fi
  if ! bash -n "$MUTADO" 2>/dev/null; then
    printf '    FAIL: mutacion %s no parsea; asi no prueba nada\n' "$nombre" >&2
    fail=1
    rm -f "$MUTADO" "$BASE"
    return
  fi
  if [ "$sobre" = setup ]; then
    SETUP="$MUTADO"
  else
    GEN="$MUTADO"
  fi
  CASO_ROJO=0
  "$fun"
  if [ "$CASO_ROJO" -ne 0 ]; then
    printf '    mutacion %s atrapada por %s\n' "$nombre" "$fun"
  else
    printf '    FAIL: ningun caso detecto la mutacion [%s]\n' "$nombre" >&2
    fail=1
  fi
  SETUP="${SAIKIT_SETUP_TOOL:-$SETUP_REAL}"
  GEN="$GEN_REAL"
  rm -f "$MUTADO" "$BASE"
}

c_wiring() {
  CASO_ROJO=0; sb_reset
  cat > "$SB/spy.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${SAIKIT_SPY_LOG:?}"
exit 0
EOF
  chmod +x "$SB/spy.sh"
  export SAIKIT_SPY_LOG="$SB/spy.argv"
  OUT="$(SAIKIT_CI_MINIMO="$SB/spy.sh" bash "$SETUP" --merge no --despliega no \
    --sin-verify-app no --telegram no < /dev/null 2>&1)"
  RC=$?
  [ -f "$SAIKIT_SPY_LOG" ] || _mal "el spy no fue invocado"
  unset SAIKIT_SPY_LOG
}

c_acepta() {
  CASO_ROJO=0; sb_reset
  OUT="$(bash "$GEN" --ofrecer --root "$SB/work" --ci-minimo si 2>&1)"
  RC=$?
  [ -f "$(yml_dest)" ] || _mal "no escribio el workflow: $OUT"
}

c_uses_sha() {
  CASO_ROJO=0; sb_reset
  OUT="$(bash "$GEN" --ofrecer --root "$SB/work" --ci-minimo si 2>&1)"
  RC=$?
  [ -f "$(yml_dest)" ] || { _mal "no escribio el workflow: $OUT"; return; }
  afirma_uses_sha "$(yml_dest)" || _mal "uses no es sha de 40 hex"
}

c_sin_secrets() {
  CASO_ROJO=0; sb_reset
  OUT="$(bash "$GEN" --ofrecer --root "$SB/work" --ci-minimo si 2>&1)"
  RC=$?
  [ -f "$(yml_dest)" ] || { _mal "no escribio el workflow: $OUT"; return; }
  afirma_sin_secrets "$(yml_dest)" || _mal "el YAML menciona secrets."
}

c_run_reales() {
  CASO_ROJO=0; sb_reset
  OUT="$(bash "$GEN" --ofrecer --root "$SB/work" --ci-minimo si 2>&1)"
  RC=$?
  [ -f "$(yml_dest)" ] || { _mal "no escribio el workflow: $OUT"; return; }
  afirma_run_reales "$(yml_dest)" || _mal "faltan run: reales de test o verify"
}

c_default_no() {
  CASO_ROJO=0; sb_reset
  OUT="$(bash "$GEN" --ofrecer --root "$SB/work" < /dev/null 2>&1)"
  RC=$?
  [ ! -e "$(yml_dest)" ] || _mal "escribio el workflow sin TTY"
  if ! printf '%s' "$OUT" | grep -Eq 'no mergea|sin checks'; then
    _mal "no aviso que sin CI no mergea"
  fi
}

while IFS=$'\t' read -r nombre expr fun sobre; do
  [ -n "$nombre" ] || continue
  correr_mutacion "$nombre" "$expr" "$fun" "$sobre"
done <<'MUTS'
no_invoca_desde_setup	s|bash "\$GEN" --ofrecer --root "\$ROOT".*|true|	c_wiring	setup
escribe_tag_no_sha	s/PIN_CHECKOUT_SHA=.*/PIN_CHECKOUT_SHA=v4.2.2/	c_uses_sha	gen
mete_secrets	s/WORKFLOW_NAME='saikit-ci-minimo'/WORKFLOW_NAME='saikit-ci-minimo secrets.FOO'/	c_sin_secrets	gen
run_solo_en_comentario	s/run: \$test_cmd/# run: $test_cmd/	c_run_reales	gen
MUTS

if [ "$fail" -ne 0 ]; then
  echo "test_ci_minimo: FAIL" >&2
  exit 1
fi
echo "test_ci_minimo: OK"
