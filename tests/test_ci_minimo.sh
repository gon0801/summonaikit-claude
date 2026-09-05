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

# Extrae valores de run: reales. '# run: ...' no cuenta; tampoco
# 'run: true  # bash tests/run.sh' (el comando util solo vive tras #).
run_reales() {  # $1=yaml → stdout con el valor util de cada run:
  local linea val
  [ -f "$1" ] || return 1
  while IFS= read -r linea; do
    val="${linea#*run:}"
    val="${val#"${val%%[![:space:]]*}"}"
    # Recorta comentario inline (ataque DoD: comando solo tras #).
    case "$val" in
      \"*) val="${val#\"}"; val="${val%%\"*}" ;;
      \'*) val="${val#\'}"; val="${val%%\'*}" ;;
      *) val="${val%%#*}"; val="${val%"${val##*[![:space:]]}"}" ;;
    esac
    [ -n "$val" ] || continue
    printf '%s\n' "$val"
  done < <(grep -E '^[[:space:]]*run:' "$1" || true)
}

# Ejecuta run: del YAML en $SB/work. uses: no se corre. Install (red) = SKIP.
inbox_correr() {  # $1=yml $2=log
  local cmd rc
  : > "$2"
  [ -f "$1" ] || return 1
  while IFS= read -r cmd; do
    case "$cmd" in
      *'npm ci'*|*'npm install'*|*'yarn install'*|*'pnpm install'*|*'pip install'*)
        printf 'SKIP\t%s\n' "$cmd" >> "$2"
        continue
        ;;
    esac
    rc=0
    ( cd "$SB/work" && eval "$cmd" ) || rc=$?
    printf '%s\t%s\n' "$rc" "$cmd" >> "$2"
  done < <(run_reales "$1")
}

# Test del repo = linea exacta (incl. yarn/pnpm). find verify ya no es verde.
# SOLO_MD puede omitir el paso verify/; si hay linea, tiene que ser el mapa o ausente.
afirma_run_reales() {  # $1=yaml
  local lineas
  lineas="$(run_reales "$1")"
  printf '%s\n' "$lineas" | grep -Exq 'bash tests/run\.sh|npm test|yarn test|pnpm test|python -m pytest' || return 1
  if printf '%s\n' "$lineas" | grep -Fq 'find verify'; then
    return 1
  fi
  if printf '%s\n' "$lineas" | grep -Eq 'verify/'; then
    printf '%s\n' "$lineas" | grep -Eq 'npm test -- verify/|yarn test -- verify/|pnpm test -- verify/|python -m pytest verify/|bash tests/run\.sh verify/|verify/ ausente' || return 1
  fi
  return 0
}

afirma_sin_secrets() {  # $1=yaml
  [ -f "$1" ] || return 1
  ! grep -Eq 'secrets\.|secrets\[|secrets:[[:space:]]*inherit' "$1"
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

yaml_parsea() {  # $1=yaml — 0 si un parser real lo acepta (DoD check-yaml)
  ruby -ryaml -e 'YAML.load_file(ARGV[0])' "$1" 2>/dev/null
}

caso "acepta_escribe_workflow"
{
  correr_setup --ci-minimo si < /dev/null
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC: $OUT"
  [ -f "$(yml_dest)" ] || _mal "no escribio $(yml_dest): $OUT"
  if [ -f "$(yml_dest)" ]; then
    yaml_parsea "$(yml_dest)" || _mal "el YAML no parsea (check-yaml lo rechazaria)"
  fi
  _contiene "listo nombra el workflow" "$OUT" ".github/workflows/saikit-ci-minimo.yml"
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
  printf '# run: bash tests/run.sh\n# run: find verify\n' > "$SB/solo-comentario.yml"
  if afirma_run_reales "$SB/solo-comentario.yml"; then
    _mal "el helper acepto run: solo en comentario"
  fi
  # Ataque DoD: comando util solo tras # en la misma linea.
  printf 'run: true  # bash tests/run.sh\nrun: true  # find verify -type f\n' > "$SB/inline-comentario.yml"
  if afirma_run_reales "$SB/inline-comentario.yml"; then
    _mal "el helper acepto run: true con el comando solo en comentario inline"
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
        run: bash tests/run.sh verify/
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
        run: bash tests/run.sh verify/
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

# --- lead #185: cuatro huecos verificados ---------------------------------

# Invertido #185: sin scripts.test real el fallback inventaba bash tests/run.sh
# (medido 2026-09-05, rc=0, YAML con run: bash tests/run.sh). Ahora exit 2.
caso "npm_real_no_mira_fuera_de_scripts"
{
  rm -f tests/run.sh
  cat > package.json <<'EOF'
{
  "name": "app",
  "scripts": {
    "build": "echo build"
  },
  "jest": {
    "test": "node_modules/jest/bin/jest.js"
  }
}
EOF
  correr_gen --ci-minimo si
  [ "$RC" -eq 2 ] || _mal "sin runner real rc=$RC (esperaba 2): $OUT"
  [ ! -e "$(yml_dest)" ] || _mal "no debia escribir YAML: $(cat "$(yml_dest)")"
  if printf '%s' "$OUT" | grep -Fq 'npm test'; then
    _mal "emitio npm test por un test: fuera de scripts"
  fi
  printf '%s' "$OUT" | grep -Fq 'tests/run.sh' || _mal "el mensaje no nombra tests/run.sh: $OUT"
  printf '%s' "$OUT" | grep -Fq 'scripts.test' || _mal "el mensaje no nombra scripts.test: $OUT"
}
fin_caso "npm_real_no_mira_fuera_de_scripts"

caso "npm_real_scripts_compacto_en_una_linea"
{
  rm -f tests/run.sh
  printf '%s\n' '{ "name": "app", "scripts": { "test": "jest" }, "devDependencies": { "jest": "29.0.0" } }' > package.json
  printf '{ "name": "app", "lockfileVersion": 3 }\n' > package-lock.json
  correr_gen --ci-minimo si
  [ -f "$(yml_dest)" ] || _mal "no escribio: $OUT"
  if ! grep -E '^[[:space:]]*run:[[:space:]]*npm test[[:space:]]*$' "$(yml_dest)" >/dev/null; then
    _mal "scripts.test compacto debia emitir npm test: $(cat "$(yml_dest)")"
  fi
  if ! grep -E '^[[:space:]]*run:[[:space:]]*npm ci[[:space:]]*$' "$(yml_dest)" >/dev/null; then
    _mal "debia emitir npm ci: $(cat "$(yml_dest)")"
  fi
}
fin_caso "npm_real_scripts_compacto_en_una_linea"

caso "npm_instala_antes_en_checkout_fresco"
{
  # Sin tests/run.sh; scripts.test real + package-lock => npm ci antes de npm test.
  rm -f tests/run.sh
  cat > package.json <<'EOF'
{
  "name": "app",
  "scripts": {
    "test": "jest"
  },
  "devDependencies": {
    "jest": "29.0.0"
  }
}
EOF
  printf '{ "name": "app", "lockfileVersion": 3 }\n' > package-lock.json
  correr_gen --ci-minimo si
  [ -f "$(yml_dest)" ] || _mal "no escribio: $OUT"
  yml="$(cat "$(yml_dest)")"
  if ! printf '%s\n' "$yml" | grep -Eq '^[[:space:]]*run:[[:space:]]*npm ci[[:space:]]*$'; then
    _mal "checkout fresco con lockfile exige run: npm ci: $yml"
  fi
  if ! printf '%s\n' "$yml" | grep -Eq '^[[:space:]]*run:[[:space:]]*npm test[[:space:]]*$'; then
    _mal "falta run: npm test: $yml"
  fi
  # Orden: npm ci aparece antes que npm test en el archivo.
  ci_line="$(printf '%s\n' "$yml" | grep -n 'run:[[:space:]]*npm ci' | head -1 | cut -d: -f1)"
  test_line="$(printf '%s\n' "$yml" | grep -n 'run:[[:space:]]*npm test' | head -1 | cut -d: -f1)"
  [ -n "$ci_line" ] && [ -n "$test_line" ] && [ "$ci_line" -lt "$test_line" ] \
    || _mal "npm ci debe ir antes de npm test (ci=$ci_line test=$test_line)"
}
fin_caso "npm_instala_antes_en_checkout_fresco"

caso "permisos_minimos_y_sin_persist_credentials"
{
  correr_gen --ci-minimo si
  [ -f "$(yml_dest)" ] || _mal "no escribio: $OUT"
  yml="$(cat "$(yml_dest)")"
  if ! printf '%s\n' "$yml" | grep -Eq '^permissions:'; then
    _mal "falta permissions: de tope"
  fi
  if ! printf '%s\n' "$yml" | grep -Eq '^[[:space:]]*contents:[[:space:]]*read[[:space:]]*$'; then
    _mal "falta permissions.contents: read"
  fi
  if ! printf '%s\n' "$yml" | grep -Eq 'persist-credentials:[[:space:]]*false'; then
    _mal "checkout debe llevar persist-credentials: false"
  fi
}
fin_caso "permisos_minimos_y_sin_persist_credentials"

caso "carrera_no_pisa_workflow_aparecido"
{
  # Gancho de test: entre el consentimiento y el publish, aparece el destino.
  # Sin rechequeo + mv -n, el generador lo pisa (bug lead #185).
  export SAIKIT_CI_BEFORE_WRITE='mkdir -p .github/workflows; printf "name: competidor\n" > .github/workflows/saikit-ci-minimo.yml'
  correr_gen --ci-minimo si
  unset SAIKIT_CI_BEFORE_WRITE
  [ -f "$(yml_dest)" ] || _mal "el destino debia existir (el competidor): $OUT"
  if grep -Fq 'name: saikit-ci-minimo' "$(yml_dest)"; then
    _mal "piso el workflow que aparecio durante la oferta"
  fi
  if ! grep -Fq 'name: competidor' "$(yml_dest)"; then
    _mal "no preservo el competidor: $(cat "$(yml_dest)")"
  fi
  if ! printf '%s' "$OUT" | grep -Eqi 'carrera|no se pisa|ya hay|aparecio'; then
    _mal "debia reportar la carrera: $OUT"
  fi
}
fin_caso "carrera_no_pisa_workflow_aparecido"

# (a) medido 2026-09-05 pytest.ini solo: rc=0, YAML con
#   run: python -m pytest
# y SIN uses: actions/setup-python@<40hex> ni pip install. Nace rojo en Actions.
caso "pytest_toolchain_en_yaml"
{
  rm -f tests/run.sh
  printf '[pytest]\n' > pytest.ini
  correr_gen --ci-minimo si
  [ "$RC" -eq 0 ] || _mal "rc=$RC: $OUT"
  [ -f "$(yml_dest)" ] || _mal "no escribio: $OUT"
  yml="$(cat "$(yml_dest)")"
  if ! printf '%s\n' "$yml" | grep -Eq 'uses:[[:space:]]*actions/setup-python@[0-9a-f]{40}'; then
    _mal "falta setup-python@40hex: $yml"
  fi
  printf '%s\n' "$yml" | grep -Fq "python-version: '3.12'" || _mal "falta python-version 3.12: $yml"
  if ! printf '%s\n' "$yml" | grep -Eq '^[[:space:]]*run:[[:space:]]*pip install( pytest| -r requirements\.txt)[[:space:]]*$'; then
    _mal "falta pip install: $yml"
  fi
  pip_line="$(printf '%s\n' "$yml" | grep -n 'run:[[:space:]]*pip install' | head -1 | cut -d: -f1)"
  pytest_line="$(printf '%s\n' "$yml" | grep -n 'run:[[:space:]]*python -m pytest' | head -1 | cut -d: -f1)"
  [ -n "$pip_line" ] && [ -n "$pytest_line" ] && [ "$pip_line" -lt "$pytest_line" ] \
    || _mal "pip debe ir antes de pytest (pip=$pip_line pytest=$pytest_line)"
  inbox_correr "$(yml_dest)" "$SB/inbox.log"
  grep -Eq '^SKIP[[:space:]]+pip install' "$SB/inbox.log" || _mal "pip debia skipearse (sin red): $(cat "$SB/inbox.log")"
  if grep -Eq 'setup-python' "$SB/inbox.log"; then
    _mal "uses: no se ejecuta; el log no debe nombrar setup-python: $(cat "$SB/inbox.log")"
  fi
}
fin_caso "pytest_toolchain_en_yaml"

# (b) medido 2026-09-05 run.sh + verify/LEEME.md: rc=0 y VERIFY_CMD con
#   find verify -type f -print -quit | grep -q .
# LEEME.md basta para rc=0. Trampa: el test del repo ya es verde.
caso "verify_leeme_no_enciende_verde"
{
  mkdir -p verify
  printf '# mapa de la skill saikit-verificar-app\n' > verify/LEEME.md
  correr_gen --ci-minimo si
  [ "$RC" -eq 0 ] || _mal "rc=$RC: $OUT"
  [ -f "$(yml_dest)" ] || _mal "no escribio: $OUT"
  yml="$(cat "$(yml_dest)")"
  if printf '%s\n' "$yml" | grep -Fq 'find verify'; then
    _mal "YAML no debe tener find verify: $yml"
  fi
  omitio=0
  printf '%s' "$OUT" | grep -Fq 'verify/ solo markdown' && omitio=1
  if [ "$omitio" -eq 1 ]; then
    if printf '%s\n' "$yml" | grep -Eq '^[[:space:]]*- name: verify/'; then
      _mal "SOLO_MD no debe emitir paso verify/: $yml"
    fi
  fi
  inbox_correr "$(yml_dest)" "$SB/inbox.log"
  grep -Eq '^0[[:space:]]+bash tests/run\.sh$' "$SB/inbox.log" \
    || _mal "test del repo debia ser rc=0: $(cat "$SB/inbox.log")"
  if [ "$omitio" -eq 0 ]; then
    if ! grep -Eq '^[1-9][0-9]*[[:space:]].*verify/' "$SB/inbox.log"; then
      _mal "sin omitir, verify debia ser rc!=0: $(cat "$SB/inbox.log")"
    fi
  fi
}
fin_caso "verify_leeme_no_enciende_verde"

# (c) medido 2026-09-05 vacio/Makefile/Cargo/package.json-sin-test:
#   rc=0, YAML con run: bash tests/run.sh (fallback inventado).
caso "sin_runner_exit_2"
{
  _sin_runner() {
    local etiqueta="$1"
    correr_gen --ci-minimo si
    [ "$RC" -eq 2 ] || _mal "$etiqueta rc=$RC (esperaba 2): $OUT"
    [ ! -e "$(yml_dest)" ] || _mal "$etiqueta escribio YAML"
    printf '%s' "$OUT" | grep -Fq 'tests/run.sh' || _mal "$etiqueta no nombra tests/run.sh: $OUT"
    printf '%s' "$OUT" | grep -Fq 'scripts.test' || _mal "$etiqueta no nombra scripts.test: $OUT"
    printf '%s' "$OUT" | grep -Fq 'pytest' || _mal "$etiqueta no nombra pytest: $OUT"
  }
  rm -f tests/run.sh
  _sin_runner vacio

  sb_reset
  rm -f tests/run.sh
  printf 'all:\n\techo hi\n' > Makefile
  _sin_runner makefile

  sb_reset
  rm -f tests/run.sh
  printf '[package]\nname = "x"\nversion = "0.1.0"\n' > Cargo.toml
  _sin_runner cargo

  sb_reset
  rm -f tests/run.sh
  printf '%s\n' '{ "name": "app", "scripts": { "build": "echo build" } }' > package.json
  _sin_runner pkg
}
fin_caso "sin_runner_exit_2"

caso "job_amarrado"
{
  correr_gen --ci-minimo si
  [ -f "$(yml_dest)" ] || _mal "no escribio: $OUT"
  yml="$(cat "$(yml_dest)")"
  printf '%s\n' "$yml" | grep -Eq '^[[:space:]]*runs-on:[[:space:]]*ubuntu-24\.04[[:space:]]*$' \
    || _mal "runs-on debe ser ubuntu-24.04: $yml"
  printf '%s\n' "$yml" | grep -Eq '^[[:space:]]*timeout-minutes:[[:space:]]*15[[:space:]]*$' \
    || _mal "falta timeout-minutes: 15: $yml"
  printf '%s\n' "$yml" | grep -Eq '^[[:space:]]*concurrency:' \
    || _mal "falta concurrency: $yml"
  printf '%s\n' "$yml" | grep -Eq 'cancel-in-progress:[[:space:]]*true' \
    || _mal "falta cancel-in-progress: true: $yml"
  if printf '%s\n' "$yml" | grep -Fq 'ubuntu-latest'; then
    _mal "ubuntu-latest no amarra: $yml"
  fi
}
fin_caso "job_amarrado"

caso "yarn_lock_emite_yarn"
{
  rm -f tests/run.sh
  printf '%s\n' '{ "name": "app", "scripts": { "test": "jest" } }' > package.json
  printf '# yarn lockfile v1\n' > yarn.lock
  correr_gen --ci-minimo si
  [ "$RC" -eq 0 ] || _mal "rc=$RC: $OUT"
  [ -f "$(yml_dest)" ] || _mal "no escribio: $OUT"
  yml="$(cat "$(yml_dest)")"
  printf '%s\n' "$yml" | grep -Eq '^[[:space:]]*run:[[:space:]]*yarn test[[:space:]]*$' \
    || _mal "yarn.lock debia emitir yarn test: $yml"
  printf '%s\n' "$yml" | grep -Eq '^[[:space:]]*run:[[:space:]]*yarn install' \
    || _mal "falta yarn install: $yml"
  if printf '%s\n' "$yml" | grep -Eq '^[[:space:]]*run:[[:space:]]*npm '; then
    _mal "yarn.lock no debe emitir npm: $yml"
  fi
}
fin_caso "yarn_lock_emite_yarn"

caso "pnpm_lock_emite_pnpm"
{
  rm -f tests/run.sh
  printf '%s\n' '{ "name": "app", "scripts": { "test": "jest" } }' > package.json
  printf 'lockfileVersion: 9.0\n' > pnpm-lock.yaml
  correr_gen --ci-minimo si
  [ "$RC" -eq 0 ] || _mal "rc=$RC: $OUT"
  [ -f "$(yml_dest)" ] || _mal "no escribio: $OUT"
  yml="$(cat "$(yml_dest)")"
  printf '%s\n' "$yml" | grep -Eq '^[[:space:]]*run:[[:space:]]*pnpm test[[:space:]]*$' \
    || _mal "pnpm-lock.yaml debia emitir pnpm test: $yml"
  printf '%s\n' "$yml" | grep -Eq '^[[:space:]]*run:[[:space:]]*pnpm install' \
    || _mal "falta pnpm install: $yml"
  if printf '%s\n' "$yml" | grep -Eq '^[[:space:]]*run:[[:space:]]*npm '; then
    _mal "pnpm-lock.yaml no debe emitir npm: $yml"
  fi
}
fin_caso "pnpm_lock_emite_pnpm"

caso "escrito_cita_el_comando"
{
  correr_gen --ci-minimo si
  [ "$RC" -eq 0 ] || _mal "rc=$RC: $OUT"
  _contiene "cita el comando que corre" "$OUT" "(corre: bash tests/run.sh)"
}
fin_caso "escrito_cita_el_comando"

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

c_permisos() {
  CASO_ROJO=0; sb_reset
  OUT="$(bash "$GEN" --ofrecer --root "$SB/work" --ci-minimo si 2>&1)"
  RC=$?
  [ -f "$(yml_dest)" ] || { _mal "no escribio el workflow: $OUT"; return; }
  yml="$(cat "$(yml_dest)")"
  printf '%s\n' "$yml" | grep -Eq '^permissions:' || _mal "falta permissions:"
  printf '%s\n' "$yml" | grep -Eq '^[[:space:]]*contents:[[:space:]]*read[[:space:]]*$' \
    || _mal "falta contents: read"
  printf '%s\n' "$yml" | grep -Eq 'persist-credentials:[[:space:]]*false' \
    || _mal "falta persist-credentials: false"
}

c_carrera() {
  CASO_ROJO=0; sb_reset
  export SAIKIT_CI_BEFORE_WRITE='mkdir -p .github/workflows; printf "name: competidor\n" > .github/workflows/saikit-ci-minimo.yml'
  OUT="$(bash "$GEN" --ofrecer --root "$SB/work" --ci-minimo si 2>&1)"
  RC=$?
  unset SAIKIT_CI_BEFORE_WRITE
  [ -f "$(yml_dest)" ] || { _mal "falta el destino: $OUT"; return; }
  if grep -Fq 'name: saikit-ci-minimo' "$(yml_dest)"; then
    _mal "piso el workflow de la carrera"
  fi
  grep -Fq 'name: competidor' "$(yml_dest)" || _mal "no preservo competidor"
}

while IFS=$'\t' read -r nombre expr fun sobre; do
  [ -n "$nombre" ] || continue
  correr_mutacion "$nombre" "$expr" "$fun" "$sobre"
done <<'MUTS'
no_invoca_desde_setup	s|bash "\$GEN" --ofrecer --root "\$ROOT".*|true|	c_wiring	setup
escribe_tag_no_sha	s/PIN_CHECKOUT_SHA=.*/PIN_CHECKOUT_SHA=v4.2.2/	c_uses_sha	gen
mete_secrets	s/WORKFLOW_NAME='saikit-ci-minimo'/WORKFLOW_NAME='saikit-ci-minimo secrets.FOO'/	c_sin_secrets	gen
run_solo_en_comentario	s|run: \$test_cmd|run: true  # $test_cmd|	c_run_reales	gen
default_no_escribe_igual	s/printf 'DEFAULT_NO'/printf 'SI'/	c_default_no	gen
sin_permissions	s/^permissions:/#permissions:/	c_permisos	gen
persist_credentials_on	s/persist-credentials: false/persist-credentials: true/	c_permisos	gen
carrera_sin_guarda	s/if \[ -e "\$dest" \] || \[ "\$(workflows_en_disco "\$root")" = PRESENTE \]; then/if false; then/;s/mv -n/mv -f/;s/|| \[ -e "\$tmp" \]/|| false/	c_carrera	gen
MUTS

if [ "$fail" -ne 0 ]; then
  echo "test_ci_minimo: FAIL" >&2
  exit 1
fi
echo "test_ci_minimo: OK"
