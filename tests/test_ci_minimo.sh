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
BUMP_REAL="$repo/tools/bump-ci-pins.sh"
BUMP="$BUMP_REAL"
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
      *'npm ci'*|*'npm install'*|*'yarn install'*|*'pnpm install'*|*'pip install'*|*'corepack '*)
        printf 'SKIP\t%s\n' "$cmd" >> "$2"
        continue
        ;;
    esac
    rc=0
    ( cd "$SB/work" && eval "$cmd" ) >/dev/null 2>&1 || rc=$?
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
  if ! printf '%s\n' "$yml" | grep -Eq '^[[:space:]]*- uses:[[:space:]]*actions/setup-python@[0-9a-f]{40}'; then
    _mal "falta setup-python@40hex: $yml"
  fi
  printf '%s\n' "$yml" | grep -Fq "python-version: '3.12'" || _mal "falta python-version 3.12: $yml"
  if ! printf '%s\n' "$yml" | grep -Eq '^[[:space:]]*run:[[:space:]]*pip install'; then
    _mal "falta pip install: $yml"
  fi
  # Con requirements.txt + pytest.ini: debe instalar requirements Y pytest.
  printf 'flask==3.0.0\n' > requirements.txt
  rm -rf .github
  correr_gen --ci-minimo si
  [ "$RC" -eq 0 ] || _mal "con requirements rc=$RC: $OUT"
  yml="$(cat "$(yml_dest)")"
  printf '%s\n' "$yml" | grep -Fq 'pip install -r requirements.txt && pip install pytest' \
    || _mal "requirements sin pytest debe instalar ambos: $yml"
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

caso "verify_leeme_md_mayusculas_omite"
{
  mkdir -p verify
  printf '# mapa\n' > verify/LEEME.MD
  correr_gen --ci-minimo si
  [ "$RC" -eq 0 ] || _mal "rc=$RC: $OUT"
  printf '%s' "$OUT" | grep -Fq 'verify/ solo markdown' \
    || _mal "LEEME.MD debia omitir como SOLO_MD: $OUT"
  if printf '%s\n' "$(cat "$(yml_dest)")" | grep -Eq '^[[:space:]]*- name: verify/'; then
    _mal "LEEME.MD no debe emitir paso verify/"
  fi
}
fin_caso "verify_leeme_md_mayusculas_omite"

caso "verify_tiene_emite_mapa"
{
  mkdir -p verify
  printf '#!/usr/bin/env bash\nexit 0\n' > verify/app.sh
  chmod +x verify/app.sh
  correr_gen --ci-minimo si
  [ "$RC" -eq 0 ] || _mal "rc=$RC: $OUT"
  [ -f "$(yml_dest)" ] || _mal "no escribio: $OUT"
  yml="$(cat "$(yml_dest)")"
  printf '%s\n' "$yml" | grep -Eq '^[[:space:]]*- name: verify/' \
    || _mal "TIENE debe emitir paso verify/: $yml"
  printf '%s\n' "$yml" | grep -Fq 'bash tests/run.sh verify/' \
    || _mal "verify debe mapear test_cmd: $yml"
  if printf '%s\n' "$yml" | grep -Fq 'find verify'; then
    _mal "TIENE no usa find: $yml"
  fi
  inbox_correr "$(yml_dest)" "$SB/inbox.log"
  grep -Eq '^0[[:space:]]+bash tests/run\.sh$' "$SB/inbox.log" \
    || _mal "test del repo debia ser rc=0: $(cat "$SB/inbox.log")"
  grep -Eq '^0[[:space:]]+bash tests/run\.sh verify/' "$SB/inbox.log" \
    || _mal "verify mapeado debia correr: $(cat "$SB/inbox.log")"
}
fin_caso "verify_tiene_emite_mapa"

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
  if ! printf '%s\n' "$yml" | grep -Eq '^[[:space:]]*- uses:[[:space:]]*actions/setup-node@[0-9a-f]{40}'; then
    _mal "pnpm exige setup-node@40hex (ubuntu no trae pnpm): $yml"
  fi
  printf '%s\n' "$yml" | grep -Fq "node-version: '20'" || _mal "falta node-version 20: $yml"
  printf '%s\n' "$yml" | grep -Eq '^[[:space:]]*run:[[:space:]]*corepack enable[[:space:]]*$' \
    || _mal "falta corepack enable: $yml"
  printf '%s\n' "$yml" | grep -Eq '^[[:space:]]*run:[[:space:]]*pnpm install' \
    || _mal "falta pnpm install: $yml"
  node_line="$(printf '%s\n' "$yml" | grep -n 'uses:[[:space:]]*actions/setup-node' | head -1 | cut -d: -f1)"
  core_line="$(printf '%s\n' "$yml" | grep -n 'run:[[:space:]]*corepack enable' | head -1 | cut -d: -f1)"
  pnpm_line="$(printf '%s\n' "$yml" | grep -n 'run:[[:space:]]*pnpm install' | head -1 | cut -d: -f1)"
  test_line="$(printf '%s\n' "$yml" | grep -n 'run:[[:space:]]*pnpm test' | head -1 | cut -d: -f1)"
  [ -n "$node_line" ] && [ -n "$core_line" ] && [ -n "$pnpm_line" ] && [ -n "$test_line" ] \
    && [ "$node_line" -lt "$core_line" ] && [ "$core_line" -lt "$pnpm_line" ] \
    && [ "$pnpm_line" -lt "$test_line" ] \
    || _mal "orden toolchain: setup-node < corepack < install < test ($node_line $core_line $pnpm_line $test_line)"
  if printf '%s\n' "$yml" | grep -Eq '^[[:space:]]*run:[[:space:]]*npm '; then
    _mal "pnpm-lock.yaml no debe emitir npm: $yml"
  fi
}
fin_caso "pnpm_lock_emite_pnpm"

caso "setup_sin_runner_degrada"
{
  rm -f tests/run.sh
  correr_setup --ci-minimo si < /dev/null
  [ "$RC" -eq 0 ] || _mal "setup debia salir 0 tras degradar, dio $RC: $OUT"
  [ -f .saikit/autopilot.json ] || _mal "config debia persistir: $OUT"
  [ ! -e "$(yml_dest)" ] || _mal "sin runner no debe haber YAML"
  printf '%s' "$OUT" | grep -Eq 'ci-minimo no se pudo ofrecer|sin runner' \
    || _mal "debia avisar la degradacion: $OUT"
  printf '%s' "$OUT" | grep -Fq 'listo:' || _mal "debia llegar al listo: $OUT"
}
fin_caso "setup_sin_runner_degrada"

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

# --- 20.7: mantenimiento de pins (detector + propuesta revisable) -----------
#
# DoD de la fila: el detector distingue «al dia» de «obsoleto» con FIXTURE
# sin red (exit 0 vs 1); la propuesta es un diff revisable que NO escribe
# (ni el generador ni workflows ajenos) y no adopta tag flotante; el CI
# generado conserva las cinco exigencias tras aplicar la propuesta. Los
# tests no requieren red: --fuente (fixture) y el gancho
# SAIKIT_BUMP_CI_PINS_API simulan la consulta.

# Los pins ACTUALES del generador, espejados como «fuente que sabe» igual
# que sec.yml espeja el sha de checkout: si alguien mueve un pin, esta
# seccion lo exige verde de nuevo con fixture actualizado.
FIX_CHECKOUT_SHA='11bd71901bbe5b1630ceea73d27597364c9af683'
FIX_SETUP_PYTHON_SHA='a26af69be951a213d495a4c3e4e4022e16d87065'
FIX_SETUP_NODE_SHA='49933ea5288caeca8642d1e84afbd3f7d6820020'
FIX_SHA_NUEVO_SETUP_NODE='eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'
FIX_SHA_OTRO='ffffffffffffffffffffffffffffffffffffffff'

fixture_escribir() {  # $1=path $2=sha_de_setup_node
  cat > "$1" <<EOF
actions/checkout v4.2.2 $FIX_CHECKOUT_SHA
actions/setup-python v5.6.0 $FIX_SETUP_PYTHON_SHA
actions/setup-node v4.4.0 $2
EOF
}

caso "pins_detector_al_dia_fixture"
{
  fixture_escribir "$SB/f-al-dia" "$FIX_SETUP_NODE_SHA"
  OUT="$(bash "$BUMP" --check --fuente "$SB/f-al-dia" 2>&1)"
  RC=$?
  [ "$RC" -eq 0 ] || _mal "al dia debia ser exit 0, dio $RC: $OUT"
  printf '%s' "$OUT" | grep -Fq 'al dia' || _mal "no reporta al dia: $OUT"
  if printf '%s' "$OUT" | grep -Fq 'OBSOLETO'; then
    _mal "reporto OBSOLETO con fixture al dia: $OUT"
  fi
}
fin_caso "pins_detector_al_dia_fixture"

caso "pins_detector_obsoleto_fixture"
{
  gen_ck="$(cksum < "$GEN_REAL")"
  fixture_escribir "$SB/f-vieja" "$FIX_SHA_OTRO"
  OUT="$(bash "$BUMP" --check --fuente "$SB/f-vieja" 2>&1)"
  RC=$?
  [ "$RC" -eq 1 ] || _mal "obsoleto debia ser exit 1 (distinguible del 0), dio $RC: $OUT"
  printf '%s' "$OUT" | grep -Fq 'OBSOLETO' || _mal "no reporta OBSOLETO: $OUT"
  _contiene "nombra la action obsoleta" "$OUT" "actions/setup-node"
  _contiene "cita el sha de la fuente" "$OUT" "$FIX_SHA_OTRO"
  _contiene "cita el sha pineado" "$OUT" "$FIX_SETUP_NODE_SHA"
  _contiene "propone el camino" "$OUT" "--proponer"
  # El check es solo lectura: el generador queda intacto.
  [ "$(cksum < "$GEN_REAL")" = "$gen_ck" ] || _mal "el check modifico el generador"
}
fin_caso "pins_detector_obsoleto_fixture"

caso "pins_detector_falla_cerrado"
{
  # Tag ausente de la fuente: NO se puede declarar ni al dia ni obsoleto.
  printf 'actions/checkout v4.2.2 %s\n' "$FIX_CHECKOUT_SHA" > "$SB/f-incompleta"
  OUT="$(bash "$BUMP" --check --fuente "$SB/f-incompleta" 2>&1)"
  RC=$?
  [ "$RC" -eq 2 ] || _mal "tag ausente debia ser exit 2, dio $RC: $OUT"
  if printf '%s' "$OUT" | grep -Fq 'todos los pins al dia'; then
    _mal "declaro el veredicto al dia sin poder mirar un tag: $OUT"
  fi
  printf '%s' "$OUT" | grep -Eq 'no conoce|no se pudo' \
    || _mal "no declara el tag ausente: $OUT"
  # Fuente inexistente y fixture malformada: tambien exit 2, sin inventar.
  OUT="$(bash "$BUMP" --check --fuente "$SB/no-existe" 2>&1)"
  RC=$?
  [ "$RC" -eq 2 ] || _mal "fuente inexistente debia ser exit 2, dio $RC: $OUT"
  printf 'actions/checkout v4.2.2 nosha\n' > "$SB/f-mala"
  OUT="$(bash "$BUMP" --check --fuente "$SB/f-mala" 2>&1)"
  RC=$?
  [ "$RC" -eq 2 ] || _mal "fixture malformada debia ser exit 2, dio $RC: $OUT"
}
fin_caso "pins_detector_falla_cerrado"

# r1 (cross-review 20.x): un pin con OWNER, SHA o TAG ausente es ILEGIBLE y
# --check muere con exit 2 nombrando el pin y el campo — JAMAS «todos los
# pins al dia». Antes el marcador PIN_ILEGIBLE (menos de 4 campos) caia en el
# `[ -n "$base" ] || continue` del lector ANTES del case, se descartaba en
# silencio y los pins sanos tapaban al roto: exit 0 (rojo medido). Tres
# regresiones INDEPENDIENTES (una por campo) con los OTROS pins validos.
caso "pins_pin_incompleto_falla_cerrado_por_campo"
{
  for campo in OWNER SHA TAG; do
    sed "/^PIN_SETUP_NODE_$campo=/d" "$GEN_REAL" > "$SB/gen-sin-$campo.sh"
    fixture_escribir "$SB/f-sanos-$campo" "$FIX_SETUP_NODE_SHA"
    OUT="$(bash "$BUMP" --check --fuente "$SB/f-sanos-$campo" --generador "$SB/gen-sin-$campo.sh" 2>&1)"
    RC=$?
    [ "$RC" -eq 2 ] || _mal "pin sin $campo debia ser exit 2, dio $RC: $OUT"
    if printf '%s' "$OUT" | grep -Fq 'todos los pins al dia'; then
      _mal "con $campo ausente declaro el veredicto al dia: $OUT"
    fi
    printf '%s' "$OUT" | grep -Fq 'PIN_SETUP_NODE' \
      || _mal "con $campo ausente no nombra el pin roto: $OUT"
    printf '%s' "$OUT" | grep -Fq "$campo" \
      || _mal "con $campo ausente no nombra el campo: $OUT"
  done
}
fin_caso "pins_pin_incompleto_falla_cerrado_por_campo"

caso "pins_proponer_diff_revisable_sin_escribir"
{
  gen_ck="$(cksum < "$GEN_REAL")"
  mkdir -p .github/workflows
  printf 'name: ajeno\n' > .github/workflows/ajeno.yml
  ajeno_ck="$(cksum < .github/workflows/ajeno.yml)"
  printf 'actions/setup-node v4.5.0 %s\n' "$FIX_SHA_NUEVO_SETUP_NODE" > "$SB/f-nueva"
  OUT="$(bash "$BUMP" --proponer actions/setup-node v4.5.0 --fuente "$SB/f-nueva" 2>&1)"
  RC=$?
  [ "$RC" -eq 0 ] || _mal "proponer debia ser exit 0, dio $RC: $OUT"
  printf '%s' "$OUT" | grep -Eq '^---' || _mal "no es un diff: $OUT"
  _contiene "avisa que no aplica" "$OUT" "NO aplicada"
  _contiene "quita el sha viejo" "$OUT" "-PIN_SETUP_NODE_SHA='$FIX_SETUP_NODE_SHA'"
  _contiene "pone el sha nuevo" "$OUT" "+PIN_SETUP_NODE_SHA='$FIX_SHA_NUEVO_SETUP_NODE'"
  _contiene "quita el tag viejo" "$OUT" "-PIN_SETUP_NODE_TAG='v4.4.0'"
  _contiene "pone el tag nuevo" "$OUT" "+PIN_SETUP_NODE_TAG='v4.5.0'"
  # Tag flotante prohibido en la propuesta: ningun uses: apunta a @tag.
  if printf '%s' "$OUT" | grep -Eq 'uses:[[:space:]]*[^ @]+@v[0-9]'; then
    _mal "la propuesta adopta un tag flotante: $OUT"
  fi
  # NO escribio: generador intacto, workflow ajeno intacto, ningun nuevo.
  [ "$(cksum < "$GEN_REAL")" = "$gen_ck" ] || _mal "la propuesta sobrescribio el generador"
  [ "$(cksum < .github/workflows/ajeno.yml)" = "$ajeno_ck" ] \
    || _mal "la propuesta toco un workflow ajeno"
  [ ! -e "$(yml_dest)" ] || _mal "la propuesta escribio un workflow"
}
fin_caso "pins_proponer_diff_revisable_sin_escribir"

caso "pins_propuesta_aplicada_conserva_exigencias"
{
  # DoD: el diff propuesto, APLICADO a una copia del generador, sigue
  # generando un CI con las cinco exigencias. El repo no se toca.
  cp "$GEN_REAL" "$SB/gen-copia.sh"
  printf 'actions/setup-node v4.5.0 %s\n' "$FIX_SHA_NUEVO_SETUP_NODE" > "$SB/f-nueva"
  OUT="$( cd "$SB" && bash "$BUMP" --proponer actions/setup-node v4.5.0 \
      --fuente "$SB/f-nueva" --generador gen-copia.sh 2>&1)"
  RC=$?
  [ "$RC" -eq 0 ] || _mal "proponer rc=$RC: $OUT"
  printf '%s\n' "$OUT" > "$SB/propuesta.patch"
  if ! ( cd "$SB" && patch -p0 -s < propuesta.patch ); then
    _mal "el diff propuesto no aplica limpio: $OUT"
  fi
  grep -Fq "PIN_SETUP_NODE_SHA='$FIX_SHA_NUEVO_SETUP_NODE'" "$SB/gen-copia.sh" \
    || _mal "la copia aplicada no tiene el sha nuevo"
  # La copia patcheada genera el workflow: pnpm usa setup-node.
  rm -f tests/run.sh
  printf '%s\n' '{ "name": "app", "scripts": { "test": "jest" } }' > package.json
  printf 'lockfileVersion: 9.0\n' > pnpm-lock.yaml
  OUT="$(bash "$SB/gen-copia.sh" --ofrecer --root "$SB/work" --ci-minimo si 2>&1)"
  RC=$?
  [ "$RC" -eq 0 ] || _mal "generador patcheado rc=$RC: $OUT"
  [ -f "$(yml_dest)" ] || _mal "la copia patcheada no escribio: $OUT"
  if [ -f "$(yml_dest)" ]; then
    # 1) pins @sha40 — con el sha PROPUESTO, no el viejo.
    afirma_uses_sha "$(yml_dest)" || _mal "la propuesta rompio el pin sha40"
    grep -Fq "actions/setup-node@$FIX_SHA_NUEVO_SETUP_NODE" "$(yml_dest)" \
      || _mal "el YAML no pinea el sha propuesto: $(cat "$(yml_dest)")"
    # 2) run reales de test y 3) sin secrets.
    afirma_run_reales "$(yml_dest)" || _mal "faltan run: reales"
    afirma_sin_secrets "$(yml_dest)" || _mal "el YAML menciona secrets."
    # 4) permisos minimos.
    yml="$(cat "$(yml_dest)")"
    printf '%s\n' "$yml" | grep -Eq '^permissions:' || _mal "falta permissions:"
    printf '%s\n' "$yml" | grep -Eq 'persist-credentials:[[:space:]]*false' \
      || _mal "falta persist-credentials: false"
    # 5) job amarrado.
    printf '%s\n' "$yml" | grep -Eq 'runs-on:[[:space:]]*ubuntu-24\.04' \
      || _mal "falta ubuntu-24.04"
    printf '%s\n' "$yml" | grep -Eq 'timeout-minutes:[[:space:]]*15' \
      || _mal "falta timeout-minutes: 15"
    printf '%s\n' "$yml" | grep -Eq 'cancel-in-progress:[[:space:]]*true' \
      || _mal "falta cancel-in-progress: true"
  fi
}
fin_caso "pins_propuesta_aplicada_conserva_exigencias"

caso "pins_consulta_api_simulada"
{
  # Sin --fuente: la consulta va por el cliente HTTP (gancho de test).
  cat > "$SB/api-viva.sh" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  'actions/checkout v4.3.0') printf '%s\n' 'dddddddddddddddddddddddddddddddddddddddd'; exit 0 ;;
esac
exit 1
EOF
  chmod +x "$SB/api-viva.sh"
  OUT="$(SAIKIT_BUMP_CI_PINS_API="$SB/api-viva.sh" bash "$BUMP" \
    --proponer actions/checkout v4.3.0 2>&1)"
  RC=$?
  [ "$RC" -eq 0 ] || _mal "consulta simulada rc=$RC: $OUT"
  _contiene "resuelve el sha del tag" "$OUT" "+PIN_CHECKOUT_SHA='dddddddddddddddddddddddddddddddddddddddd'"
  _contiene "mueve el tag" "$OUT" "+PIN_CHECKOUT_TAG='v4.3.0'"
}
fin_caso "pins_consulta_api_simulada"

caso "pins_sin_red_falla_declarado"
{
  cat > "$SB/api-sin-red.sh" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "$SB/api-sin-red.sh"
  OUT="$(SAIKIT_BUMP_CI_PINS_API="$SB/api-sin-red.sh" bash "$BUMP" \
    --proponer actions/checkout v4.2.2 2>&1)"
  RC=$?
  [ "$RC" -eq 2 ] || _mal "sin red debia ser exit 2, dio $RC: $OUT"
  printf '%s' "$OUT" | grep -Eq 'no se pudo consultar|sin red' \
    || _mal "no declara la falta de consulta: $OUT"
  if printf '%s' "$OUT" | grep -Eq '^\+PIN_'; then
    _mal "sin red no debia emitir propuesta: $OUT"
  fi
  # El check tampoco inventa «al dia» sin poder consultar.
  OUT="$(SAIKIT_BUMP_CI_PINS_API="$SB/api-sin-red.sh" bash "$BUMP" --check 2>&1)"
  RC=$?
  [ "$RC" -eq 2 ] || _mal "check sin red debia ser exit 2, dio $RC: $OUT"
  if printf '%s' "$OUT" | grep -Fq 'todos los pins al dia'; then
    _mal "check declaro el veredicto al dia sin red: $OUT"
  fi
}
fin_caso "pins_sin_red_falla_declarado"

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

mut_sed_bump() {  # $1=sed-expr
  BASE="$SB-base-$$.sh"
  MUTADO="$SB-mutado-$$.sh"
  sed "s|^HERE=.*$|HERE=$repo/tools|" "$BUMP_REAL" > "$BASE"
  sed "$1" "$BASE" > "$MUTADO"
}

correr_mutacion() {  # $1=nombre $2=sed-expr $3=fun $4=setup|gen|bump
  local nombre="$1" expr="$2" fun="$3" sobre="${4:-gen}"
  case "$sobre" in
    setup) mut_sed_setup "$expr" ;;
    gen)   mut_sed_gen "$expr" ;;
    bump)  mut_sed_bump "$expr" ;;
  esac
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
  elif [ "$sobre" = bump ]; then
    BUMP="$MUTADO"
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
  BUMP="$BUMP_REAL"
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

c_pytest() {
  CASO_ROJO=0; sb_reset
  rm -f tests/run.sh
  printf '[pytest]\n' > pytest.ini
  OUT="$(bash "$GEN" --ofrecer --root "$SB/work" --ci-minimo si 2>&1)"
  [ -f "$(yml_dest)" ] || { _mal "no escribio: $OUT"; return; }
  grep -Eq '^[[:space:]]*- uses:[[:space:]]*actions/setup-python@[0-9a-f]{40}' "$(yml_dest)" \
    || _mal "falta setup-python@40hex"
}

c_verify_leeme() {
  CASO_ROJO=0; sb_reset
  mkdir -p verify
  printf '# mapa\n' > verify/LEEME.md
  OUT="$(bash "$GEN" --ofrecer --root "$SB/work" --ci-minimo si 2>&1)"
  [ -f "$(yml_dest)" ] || { _mal "no escribio: $OUT"; return; }
  if grep -Fq 'find verify' "$(yml_dest)"; then
    _mal "YAML tiene find verify"
  fi
  printf '%s' "$OUT" | grep -Fq 'verify/ solo markdown' \
    || _mal "no omitio SOLO_MD"
}

c_sin_runner() {
  CASO_ROJO=0; sb_reset
  rm -f tests/run.sh
  OUT="$(bash "$GEN" --ofrecer --root "$SB/work" --ci-minimo si 2>&1)"
  RC=$?
  [ "$RC" -eq 2 ] || _mal "rc=$RC esperaba 2: $OUT"
  [ ! -e "$(yml_dest)" ] || _mal "escribio YAML sin runner"
}

c_job() {
  CASO_ROJO=0; sb_reset
  OUT="$(bash "$GEN" --ofrecer --root "$SB/work" --ci-minimo si 2>&1)"
  [ -f "$(yml_dest)" ] || { _mal "no escribio: $OUT"; return; }
  grep -Eq 'runs-on:[[:space:]]*ubuntu-24\.04' "$(yml_dest)" || _mal "no ubuntu-24.04"
  if grep -Fq 'ubuntu-latest' "$(yml_dest)"; then _mal "ubuntu-latest"; fi
}

c_yarn() {
  CASO_ROJO=0; sb_reset
  rm -f tests/run.sh
  printf '%s\n' '{ "name": "app", "scripts": { "test": "jest" } }' > package.json
  printf '# yarn lockfile v1\n' > yarn.lock
  OUT="$(bash "$GEN" --ofrecer --root "$SB/work" --ci-minimo si 2>&1)"
  [ -f "$(yml_dest)" ] || { _mal "no escribio: $OUT"; return; }
  grep -Eq '^[[:space:]]*run:[[:space:]]*yarn test' "$(yml_dest)" || _mal "no yarn test"
  if grep -Eq '^[[:space:]]*run:[[:space:]]*npm ' "$(yml_dest)"; then _mal "emitio npm"; fi
}

c_pnpm() {
  CASO_ROJO=0; sb_reset
  rm -f tests/run.sh
  printf '%s\n' '{ "name": "app", "scripts": { "test": "jest" } }' > package.json
  printf 'lockfileVersion: 9.0\n' > pnpm-lock.yaml
  OUT="$(bash "$GEN" --ofrecer --root "$SB/work" --ci-minimo si 2>&1)"
  [ -f "$(yml_dest)" ] || { _mal "no escribio: $OUT"; return; }
  grep -Eq '^[[:space:]]*- uses:[[:space:]]*actions/setup-node@[0-9a-f]{40}' "$(yml_dest)" \
    || _mal "falta setup-node@40hex"
  grep -Eq 'corepack enable' "$(yml_dest)" || _mal "falta corepack enable"
}

c_pytest_req() {
  CASO_ROJO=0; sb_reset
  rm -f tests/run.sh
  printf '[pytest]\n' > pytest.ini
  printf 'flask==3.0.0\n' > requirements.txt
  OUT="$(bash "$GEN" --ofrecer --root "$SB/work" --ci-minimo si 2>&1)"
  [ -f "$(yml_dest)" ] || { _mal "no escribio: $OUT"; return; }
  grep -Fq 'pip install -r requirements.txt && pip install pytest' "$(yml_dest)" \
    || _mal "falta pip doble"
}

c_verify_tiene() {
  CASO_ROJO=0; sb_reset
  mkdir -p verify
  printf 'ok\n' > verify/app.sh
  OUT="$(bash "$GEN" --ofrecer --root "$SB/work" --ci-minimo si 2>&1)"
  [ -f "$(yml_dest)" ] || { _mal "no escribio: $OUT"; return; }
  grep -Eq '^[[:space:]]*- name: verify/' "$(yml_dest)" || _mal "falta paso verify"
  grep -Fq 'bash tests/run.sh verify/' "$(yml_dest)" || _mal "falta mapa test_cmd"
}

c_setup_degrada() {
  CASO_ROJO=0; sb_reset
  rm -f tests/run.sh
  OUT="$(bash "$SETUP" --merge no --despliega no --sin-verify-app no --telegram no --ci-minimo si < /dev/null 2>&1)"
  RC=$?
  [ "$RC" -eq 0 ] || _mal "setup rc=$RC"
  [ -f .saikit/autopilot.json ] || _mal "sin autopilot.json"
  [ ! -e "$(yml_dest)" ] || _mal "escribio YAML"
}

c_leeme_mayus() {
  CASO_ROJO=0; sb_reset
  mkdir -p verify
  printf '# mapa\n' > verify/LEEME.MD
  OUT="$(bash "$GEN" --ofrecer --root "$SB/work" --ci-minimo si 2>&1)"
  printf '%s' "$OUT" | grep -Fq 'verify/ solo markdown' || _mal "no omitio LEEME.MD"
}

c_pins_obsoleto() {
  CASO_ROJO=0; sb_reset
  fixture_escribir "$SB/f-vieja" "$FIX_SHA_OTRO"
  OUT="$(bash "$BUMP" --check --fuente "$SB/f-vieja" 2>&1)"
  RC=$?
  [ "$RC" -eq 1 ] || _mal "obsoleto debia ser exit 1, dio $RC: $OUT"
  printf '%s' "$OUT" | grep -Fq 'OBSOLETO' || _mal "no reporta OBSOLETO: $OUT"
}

c_pins_propuesta_seca() {
  CASO_ROJO=0; sb_reset
  cp "$GEN_REAL" "$SB/gen-copia.sh"
  printf 'actions/setup-node v4.5.0 %s\n' "$FIX_SHA_NUEVO_SETUP_NODE" > "$SB/f-nueva"
  antes="$(cksum < "$SB/gen-copia.sh")"
  OUT="$(bash "$BUMP" --proponer actions/setup-node v4.5.0 --fuente "$SB/f-nueva" \
      --generador "$SB/gen-copia.sh" 2>&1)"
  RC=$?
  [ "$RC" -eq 0 ] || _mal "proponer rc=$RC: $OUT"
  printf '%s' "$OUT" | grep -Fq '+PIN_SETUP_NODE_SHA' || _mal "no propuso el diff: $OUT"
  [ "$(cksum < "$SB/gen-copia.sh")" = "$antes" ] \
    || _mal "la propuesta escribio el generador en vez de dejarlo revisable"
}

# r1: acreditacion de la correccion del orden en leer_pins — el descarte de
# lineas vueltas al cuarto campo ([ -n "$base" ]) vuelven a tragarse el
# marcador PIN_ILEGIBLE y el check vuelve a declarar «todos los pins al dia»
# con un pin sin SHA (el rojo medido de la cross-review).
c_pins_ilegible() {
  CASO_ROJO=0; sb_reset
  sed "/^PIN_SETUP_NODE_SHA=/d" "$GEN_REAL" > "$SB/gen-sin-sha.sh"
  fixture_escribir "$SB/f-sanos" "$FIX_SETUP_NODE_SHA"
  OUT="$(bash "$BUMP" --check --fuente "$SB/f-sanos" --generador "$SB/gen-sin-sha.sh" 2>&1)"
  RC=$?
  [ "$RC" -eq 2 ] || _mal "pin sin SHA debia ser exit 2, dio $RC: $OUT"
  if printf '%s' "$OUT" | grep -Fq 'todos los pins al dia'; then
    _mal "declaro el veredicto al dia con un pin ilegible: $OUT"
  fi
}

while IFS=$'\t' read -r nombre expr fun sobre; do
  [ -n "$nombre" ] || continue
  correr_mutacion "$nombre" "$expr" "$fun" "$sobre"
done <<'MUTS'
no_invoca_desde_setup	s|if ! bash "\$GEN" --ofrecer --root "\$ROOT".*|if ! true; then|	c_wiring	setup
escribe_tag_no_sha	s/PIN_CHECKOUT_SHA=.*/PIN_CHECKOUT_SHA=v4.2.2/	c_uses_sha	gen
mete_secrets	s/WORKFLOW_NAME='saikit-ci-minimo'/WORKFLOW_NAME='saikit-ci-minimo secrets.FOO'/	c_sin_secrets	gen
run_solo_en_comentario	s|run: \$test_cmd|run: true  # $test_cmd|	c_run_reales	gen
default_no_escribe_igual	s/if \[ ! -t 0 \]; then/if false; then/;s/printf 'DEFAULT_NO'/printf 'SI'/	c_default_no	gen
sin_permissions	s/^permissions:/#permissions:/	c_permisos	gen
persist_credentials_on	s/persist-credentials: false/persist-credentials: true/	c_permisos	gen
carrera_sin_guarda	s/if \[ -e "\$dest" \] || \[ "\$(workflows_en_disco "\$root")" = PRESENTE \]; then/if false; then/;s/mv -n/mv -f/;s/|| \[ -e "\$tmp" \]/|| false/	c_carrera	gen
sin_setup_python	s/uses: \$PIN_SETUP_PYTHON_OWNER@\$PIN_SETUP_PYTHON_SHA/# uses: $PIN_SETUP_PYTHON_OWNER@$PIN_SETUP_PYTHON_SHA/	c_pytest	gen
verify_vuelve_a_find	s/printf 'SOLO_MD'/printf 'TIENE'/;s@bash tests/run.sh verify/@find verify -type f -print -quit | grep -q .@	c_verify_leeme	gen
fallback_eterno	s/return 2/printf 'bash tests\/run.sh'; return 0/	c_sin_runner	gen
ubuntu_latest	s/ubuntu-24.04/ubuntu-latest/	c_job	gen
yarn_emite_npm	s/printf 'yarn test'/printf 'npm test'/	c_yarn	gen
sin_setup_node_pnpm	s/uses: \$PIN_SETUP_NODE_OWNER@\$PIN_SETUP_NODE_SHA/# uses: $PIN_SETUP_NODE_OWNER@$PIN_SETUP_NODE_SHA/	c_pnpm	gen
pip_sin_pytest_extra	s/pip install -r requirements.txt \&\& pip install pytest/pip install -r requirements.txt/	c_pytest_req	gen
tiene_omite_verify	s/printf 'TIENE'/printf 'SOLO_MD'/	c_verify_tiene	gen
setup_propaga_exit2	s|if ! bash "\$GEN" --ofrecer --root "\$ROOT".*|bash "$GEN" --ofrecer --root "$ROOT" \${ci_minimo_flag:+--ci-minimo "\$ci_minimo_flag"} \|\| exit 2\nif false; then|	c_setup_degrada	setup
leeme_md_case_sensitive	s/-iname '\*\.md'/-name '*.md'/	c_leeme_mayus	gen
detector_siempre_al_dia	s/\[ "\$1" = "\$2" \]/return 0/	c_pins_obsoleto	bump
proponer_escribe_directo	s|diff -u -L "\$generador" -L "\$generador (propuesta)" "\$generador" "\$tmp" \|\| true|cp "$tmp" "$generador"; diff -u -L "$generador" -L "$generador" "$generador" "$tmp" \|\| true|	c_pins_propuesta_seca	bump
pin_ilegible_se_descarta	s/\[ -n "\$owner" \] || continue/[ -n "$base" ] || continue/	c_pins_ilegible	bump
MUTS

if [ "$fail" -ne 0 ]; then
  echo "test_ci_minimo: FAIL" >&2
  exit 1
fi
echo "test_ci_minimo: OK"
