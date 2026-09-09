#!/usr/bin/env bash
# ci-minimo driver — real saikit-ci-minimo.sh over a stdlib PTY (accept/reject)
# or without TTY (flags/defaults). Never fakes a PTY. Never claims live Actions.
set -euo pipefail
driver_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_root="$(cd "$driver_dir/../.." && pwd)"
# shellcheck source=../lib/runtime.sh
. "$skill_root/scripts/lib/runtime.sh"
# shellcheck source=../lib/driver.sh
. "$skill_root/scripts/lib/driver.sh"

: "${VERIFY_HOME:?}" "${VERIFY_REPO:?}" "${VERIFY_TMPDIR:?}"
: "${SAIKIT_FM_ATTEMPT_DIR:?}"

GEN="$VERIFY_REPO/tools/saikit-ci-minimo.sh"
PTY="${SAIKIT_FM_PTY:-$skill_root/scripts/lib/pty_driver.py}"
YML_REL=".github/workflows/saikit-ci-minimo.yml"

fm_unknown() { fm_assert "$1" "$2" unknown "$3" "$4"; }

pty_probe() {
  if [ "${SAIKIT_VERIFY_PTY:-}" = "missing" ]; then
    return 1
  fi
  PYTHONDONTWRITEBYTECODE=1 python3 "$PTY" --probe >/dev/null 2>&1
}

yml_of() { printf '%s/%s' "$1" "$YML_REL"; }

make_work() {
  local dest="$1" kind="${2:-bash}"
  rm -rf "$dest"
  mkdir -p "$dest"
  case "$kind" in
    bash)
      mkdir -p "$dest/tests"
      printf '#!/usr/bin/env bash\nexit 0\n' > "$dest/tests/run.sh"
      chmod +x "$dest/tests/run.sh"
      ;;
    bash_verify)
      mkdir -p "$dest/tests" "$dest/verify"
      printf '#!/usr/bin/env bash\nexit 0\n' > "$dest/tests/run.sh"
      chmod +x "$dest/tests/run.sh"
      printf '#!/usr/bin/env bash\nexit 0\n' > "$dest/verify/app.sh"
      chmod +x "$dest/verify/app.sh"
      ;;
    with_ci)
      mkdir -p "$dest/tests" "$dest/.github/workflows"
      printf '#!/usr/bin/env bash\nexit 0\n' > "$dest/tests/run.sh"
      chmod +x "$dest/tests/run.sh"
      printf '%s\n' 'name: ajeno' 'on: push' 'jobs:' '  x:' \
        '    runs-on: ubuntu-latest' '    steps:' '      - run: true' \
        > "$dest/.github/workflows/ajeno.yml"
      ;;
    empty)
      ;;
    npm)
      printf '%s\n' '{ "name": "app", "scripts": { "test": "jest" }, "devDependencies": { "jest": "29.0.0" } }' \
        > "$dest/package.json"
      printf '{ "name": "app", "lockfileVersion": 3 }\n' > "$dest/package-lock.json"
      ;;
    yarn)
      printf '%s\n' '{ "name": "app", "scripts": { "test": "jest" } }' > "$dest/package.json"
      printf '# yarn lockfile v1\n' > "$dest/yarn.lock"
      ;;
    pnpm)
      printf '%s\n' '{ "name": "app", "scripts": { "test": "jest" } }' > "$dest/package.json"
      printf 'lockfileVersion: 9.0\n' > "$dest/pnpm-lock.yaml"
      ;;
    pytest)
      printf '[pytest]\n' > "$dest/pytest.ini"
      ;;
    *)
      printf 'ci-minimo driver: kind desconocido: %s\n' "$kind" >&2
      return 2
      ;;
  esac
}

run_gen() {
  local work="$1"
  shift
  runtime_exec "$work" bash "$GEN" --ofrecer --root "$work" "$@" < /dev/null
}

run_pty() {
  local work="$1" timeout="$2" outjson="$3"
  shift 3
  PYTHONDONTWRITEBYTECODE=1 python3 "$PTY" \
    --timeout "$timeout" --cwd "$work" --out "$outjson" \
    --prompt-contains '[no]:' \
    "$@" -- bash "$GEN" --ofrecer --root "$work"
}

pty_field() {
  python3 - "$1" "$2" <<'PY'
import json, sys
path, key = sys.argv[1], sys.argv[2]
try:
    data = json.load(open(path, encoding="utf-8"))
except (OSError, json.JSONDecodeError):
    print("")
    raise SystemExit(0)
print(data.get(key, ""))
PY
}

run_reales() {
  local linea val
  [ -f "$1" ] || return 1
  while IFS= read -r linea; do
    val="${linea#*run:}"
    val="${val#"${val%%[![:space:]]*}"}"
    case "$val" in
      \"*) val="${val#\"}"; val="${val%%\"*}" ;;
      \'*) val="${val#\'}"; val="${val%%\'*}" ;;
      *) val="${val%%#*}"; val="${val%"${val##*[![:space:]]}"}" ;;
    esac
    [ -n "$val" ] || continue
    printf '%s\n' "$val"
  done < <(grep -E '^[[:space:]]*run:' "$1" || true)
  return 0
}

afirma_uses_sha() {
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

afirma_sin_secrets() {
  [ -f "$1" ] || return 1
  ! grep -Eq 'secrets\.|secrets\[|secrets:[[:space:]]*inherit' "$1"
}

yaml_parses() {
  if command -v ruby >/dev/null 2>&1; then
    ruby -ryaml -e 'YAML.load_file(ARGV[0])' "$1" 2>/dev/null
    return $?
  fi
  python3 - "$1" <<'PY'
import sys
text = open(sys.argv[1], encoding="utf-8").read()
for need in ("name:", "jobs:", "runs-on:", "steps:"):
    if need not in text:
        raise SystemExit(1)
PY
}

inbox_correr() {
  local yml="$1" log="$2" work="$3" cmd rc
  : > "$log"
  [ -f "$yml" ] || return 1
  while IFS= read -r cmd; do
    case "$cmd" in
      *'npm ci'*|*'npm install'*|*'yarn install'*|*'pnpm install'*|*'pip install'*|*'corepack '*)
        printf 'SKIP\t%s\n' "$cmd" >> "$log"
        continue
        ;;
    esac
    rc=0
    ( cd "$work" && eval "$cmd" ) >/dev/null 2>&1 || rc=$?
    printf '%s\t%s\n' "$rc" "$cmd" >> "$log"
  done < <(run_reales "$yml")
}

emit_has_run() {
  local yml="$1" want="$2" line
  [ -f "$yml" ] || return 1
  while IFS= read -r line; do
    [ "$line" = "$want" ] && return 0
  done < <(run_reales "$yml" || true)
  return 1
}

# ---------------------------------------------------------------------------
# Interactive accept
# ---------------------------------------------------------------------------
if fm_only ci-interactive; then
  work="$VERIFY_TMPDIR/ci-accept"
  make_work "$work" bash
  if ! pty_probe; then
    fm_unknown ci-interactive accept_write "escrito" "PTY ausente"
    fm_unknown ci-interactive accept_offer "oferta" "PTY ausente"
  else
    report="$VERIFY_TMPDIR/pty-accept.json"
    set +e
    run_pty "$work" 10 "$report" --answer si
    prc=$?
    set -e
    transcript="$(pty_field "$report" transcript)"
    dest="$(yml_of "$work")"
    fm_action ci-interactive act-accept "$prc" "$transcript" python3 "$PTY" -- accept
    # assert:accept_write
    if [ -f "$dest" ]; then
      fm_pass ci-interactive accept_write "escrito" "escrito $YML_REL"
    else
      fm_fail ci-interactive accept_write "escrito" "no escribio $dest"
    fi
    # assert:accept_write_end
    if printf '%s' "$transcript" | grep -Eq 'No hay workflows|verify/\?'; then
      fm_pass ci-interactive accept_offer "oferta" "oferta PTY visible"
    else
      fm_fail ci-interactive accept_offer "oferta" "$transcript"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Interactive reject
# ---------------------------------------------------------------------------
if fm_only ci-reject; then
  work="$VERIFY_TMPDIR/ci-reject"
  make_work "$work" bash
  if ! pty_probe; then
    fm_unknown ci-reject reject_no_write "ausente" "PTY ausente"
    fm_unknown ci-reject reject_aviso "sin CI" "PTY ausente"
  else
    report="$VERIFY_TMPDIR/pty-reject.json"
    set +e
    run_pty "$work" 10 "$report" --answer no
    prc=$?
    set -e
    transcript="$(pty_field "$report" transcript)"
    dest="$(yml_of "$work")"
    fm_action ci-reject act-reject "$prc" "$transcript" python3 "$PTY" -- reject
    # assert:reject_no_write
    if [ ! -e "$dest" ]; then
      fm_pass ci-reject reject_no_write "ausente" "ausente (sin escritura)"
    else
      fm_fail ci-reject reject_no_write "ausente" "escribio $dest"
    fi
    # assert:reject_no_write_end
    if printf '%s' "$transcript" | grep -Eq 'no mergea|sin checks'; then
      fm_pass ci-reject reject_aviso "sin CI" "sin CI el autopilot no mergea"
    else
      fm_fail ci-reject reject_aviso "sin CI" "$transcript"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Flags: --ci-minimo si without TTY
# ---------------------------------------------------------------------------
if fm_only ci-flags; then
  work="$VERIFY_TMPDIR/ci-flags"
  make_work "$work" bash_verify
  set +e
  out="$(run_gen "$work" --ci-minimo si 2>&1)"
  rc=$?
  set -e
  dest="$(yml_of "$work")"
  fm_action ci-flags act-flags "$rc" "$out" bash "$GEN" --flags
  if [ -f "$dest" ]; then
    fm_pass ci-flags flags_write "escrito" "escrito $YML_REL"
  else
    fm_fail ci-flags flags_write "escrito" "no escribio: $out"
  fi
  if [ -f "$dest" ] && yaml_parses "$dest"; then
    fm_pass ci-flags yaml_parses "parsea" "yaml parsea"
  else
    fm_fail ci-flags yaml_parses "parsea" "yaml no parsea"
  fi
  # assert:pins_sha40
  if [ -f "$dest" ] && afirma_uses_sha "$dest"; then
    fm_pass ci-flags pins_sha40 "sha40" "uses @sha40"
  else
    fm_fail ci-flags pins_sha40 "sha40" "uses no es sha40"
  fi
  # assert:pins_sha40_end
  if [ -f "$dest" ] && afirma_sin_secrets "$dest"; then
    fm_pass ci-flags no_secrets "sin secrets" "sin secrets"
  else
    fm_fail ci-flags no_secrets "sin secrets" "menciona secrets"
  fi
  # assert:run_test
  if [ -f "$dest" ] && emit_has_run "$dest" 'bash tests/run.sh'; then
    fm_pass ci-flags run_test "bash tests/run.sh" "run: bash tests/run.sh"
  else
    fm_fail ci-flags run_test "bash tests/run.sh" "falta run test $(run_reales "$dest" 2>/dev/null | tr '\n' '|')"
  fi
  # assert:run_test_end
  # assert:run_verify
  if [ -f "$dest" ] && emit_has_run "$dest" 'bash tests/run.sh verify/'; then
    fm_pass ci-flags run_verify "bash tests/run.sh verify/" "run: bash tests/run.sh verify/"
  else
    fm_fail ci-flags run_verify "bash tests/run.sh verify/" "falta run verify $(run_reales "$dest" 2>/dev/null | tr '\n' '|')"
  fi
  # assert:run_verify_end
fi

# ---------------------------------------------------------------------------
# Defaults without TTY
# ---------------------------------------------------------------------------
if fm_only ci-defaults; then
  work="$VERIFY_TMPDIR/ci-defaults"
  make_work "$work" bash
  set +e
  out="$(run_gen "$work" 2>&1)"
  rc=$?
  set -e
  dest="$(yml_of "$work")"
  fm_action ci-defaults act-defaults "$rc" "$out" bash "$GEN" --defaults
  if [ ! -e "$dest" ]; then
    fm_pass ci-defaults defaults_no_write "ausente" "ausente (sin TTY)"
  else
    fm_fail ci-defaults defaults_no_write "ausente" "escribio sin TTY"
  fi
  if printf '%s' "$out" | grep -Eq 'no mergea|sin checks'; then
    fm_pass ci-defaults defaults_aviso "sin CI" "sin CI el autopilot no mergea"
  else
    fm_fail ci-defaults defaults_aviso "sin CI" "$out"
  fi
fi

# ---------------------------------------------------------------------------
# Existing foreign workflow stays intact
# ---------------------------------------------------------------------------
if fm_only ci-preserve-foreign; then
  work="$VERIFY_TMPDIR/ci-foreign"
  make_work "$work" with_ci
  foreign="$work/.github/workflows/ajeno.yml"
  antes="$(cksum < "$foreign")"
  set +e
  out="$(run_gen "$work" --ci-minimo si 2>&1)"
  rc=$?
  set -e
  dest="$(yml_of "$work")"
  fm_action ci-preserve-foreign act-foreign "$rc" "$out" bash "$GEN" --foreign
  # assert:foreign_intact
  if [ "$(cksum < "$foreign")" = "$antes" ]; then
    fm_pass ci-preserve-foreign foreign_intact "intact" "foreign intact"
  else
    fm_fail ci-preserve-foreign foreign_intact "intact" "piso el workflow ajeno"
  fi
  # assert:foreign_intact_end
  if [ ! -e "$dest" ]; then
    fm_pass ci-preserve-foreign no_our_yml "ausente" "ausente (no escribio el nuestro)"
  else
    fm_fail ci-preserve-foreign no_our_yml "ausente" "escribio encima de PRESENTE"
  fi
fi

# ---------------------------------------------------------------------------
# Second accept is a no-op (same hash)
# ---------------------------------------------------------------------------
if fm_only ci-idempotent; then
  work="$VERIFY_TMPDIR/ci-idem"
  make_work "$work" bash
  set +e
  out1="$(run_gen "$work" --ci-minimo si 2>&1)"
  rc1=$?
  set -e
  dest="$(yml_of "$work")"
  if [ -f "$dest" ]; then
    antes="$(cksum < "$dest")"
  else
    antes=""
  fi
  set +e
  out2="$(run_gen "$work" --ci-minimo si 2>&1)"
  rc2=$?
  set -e
  fm_action ci-idempotent act-idem "$rc2" "$out2" bash "$GEN" --idempotent
  # assert:second_same_hash
  if [ -n "$antes" ] && [ -f "$dest" ] && [ "$(cksum < "$dest")" = "$antes" ] && [ "$rc1" -eq 0 ] && [ "$rc2" -eq 0 ]; then
    fm_pass ci-idempotent second_same_hash "same-hash" "segunda corrida same-hash"
  else
    fm_fail ci-idempotent second_same_hash "same-hash" "rc1=$rc1 rc2=$rc2 reescribio o falto yaml"
  fi
  # assert:second_same_hash_end
fi

# ---------------------------------------------------------------------------
# Admitted runners
# ---------------------------------------------------------------------------
if fm_only ci-runners; then
  _runner_case() {
    local kind="$1" asid="$2" pat="$3"
    local w dest out rc
    w="$VERIFY_TMPDIR/ci-run-$kind"
    make_work "$w" "$kind"
    set +e
    out="$(run_gen "$w" --ci-minimo si 2>&1)"
    rc=$?
    set -e
    dest="$(yml_of "$w")"
    fm_action ci-runners "act-$kind" "$rc" "$out" bash "$GEN" -- "$kind"
    if [ -f "$dest" ] && emit_has_run "$dest" "$pat"; then
      fm_pass ci-runners "$asid" "$pat" "runner $kind -> $pat"
    else
      fm_fail ci-runners "$asid" "$pat" "no emitio $pat ($(run_reales "$dest" 2>/dev/null | tr '\n' '|')): $out"
    fi
  }
  _runner_case bash runner_bash 'bash tests/run.sh'
  _runner_case npm runner_npm 'npm test'
  _runner_case yarn runner_yarn 'yarn test'
  _runner_case pnpm runner_pnpm 'pnpm test'
  _runner_case pytest runner_pytest 'python -m pytest'
fi

# ---------------------------------------------------------------------------
# Unsupported runner: exit 2, no write
# ---------------------------------------------------------------------------
if fm_only ci-unsupported; then
  work="$VERIFY_TMPDIR/ci-unsupported"
  make_work "$work" empty
  set +e
  out="$(run_gen "$work" --ci-minimo si 2>&1)"
  rc=$?
  set -e
  dest="$(yml_of "$work")"
  fm_action ci-unsupported act-unsup "$rc" "$out" bash "$GEN" --unsupported
  # assert:unsupported_exit_2
  if [ "$rc" -eq 2 ]; then
    fm_pass ci-unsupported unsupported_exit_2 "2" "exit 2 sin runner"
  else
    fm_fail ci-unsupported unsupported_exit_2 "2" "rc=$rc $out"
  fi
  # assert:unsupported_exit_2_end
  if [ ! -e "$dest" ]; then
    fm_pass ci-unsupported unsupported_no_write "ausente" "ausente (sin runner)"
  else
    fm_fail ci-unsupported unsupported_no_write "ausente" "escribio YAML sin runner"
  fi
fi

# ---------------------------------------------------------------------------
# Execute generated run: lines in the fixture. Not live Actions.
# ---------------------------------------------------------------------------
if fm_only ci-run-fixture; then
  work="$VERIFY_TMPDIR/ci-inbox"
  make_work "$work" bash_verify
  set +e
  out="$(run_gen "$work" --ci-minimo si 2>&1)"
  rc=$?
  set -e
  dest="$(yml_of "$work")"
  log="$VERIFY_TMPDIR/inbox.log"
  if [ -f "$dest" ]; then
    inbox_correr "$dest" "$log" "$work"
  else
    : > "$log"
  fi
  fm_action ci-run-fixture act-inbox "$rc" "$(cat "$log")" bash "$GEN" --inbox
  if grep -Eq '^0[[:space:]]+bash tests/run\.sh$' "$log"; then
    fm_pass ci-run-fixture fixture_ran_test "ran-test" "ran-test fixture rc=0"
  else
    fm_fail ci-run-fixture fixture_ran_test "ran-test" "test no corrio: $(cat "$log")"
  fi
  if grep -Eq '^0[[:space:]]+bash tests/run\.sh verify/' "$log"; then
    fm_pass ci-run-fixture fixture_ran_verify "ran-verify" "ran-verify fixture rc=0"
  else
    fm_fail ci-run-fixture fixture_ran_verify "ran-verify" "verify no corrio: $(cat "$log")"
  fi
  # assert:not_live_actions
  fm_pass ci-run-fixture not_live_actions "local-not-live" \
    "local-not-live generation; fixture run is not live Actions"
  # assert:not_live_actions_end
fi

# ---------------------------------------------------------------------------
# bump-ci-pins --check: pin ilegible muere cerrado nombrando pin y campo.
# r1 (cross-review 20.x): el marcador PIN_ILEGIBLE viaja con el campo que
# falta y el lector lo procesa ANTES de descartar lineas cortas — un pin sin
# OWNER/SHA/TAG nunca queda tapado por los sanos con «todos los pins al dia».
# Espejo driver del producto pins_pin_incompleto_falla_cerrado_por_campo.
# ---------------------------------------------------------------------------
if fm_only ci-pins-ilegible; then
  BUMP="$VERIFY_REPO/tools/bump-ci-pins.sh"
  GEN_REAL="$VERIFY_REPO/tools/saikit-ci-minimo.sh"
  work="$VERIFY_TMPDIR/ci-pins"
  rm -rf "$work"
  mkdir -p "$work"
  # Fuente fixture «que sabe» construida de los pins ACTUALES del generador
  # (misma forma que el fixture del producto: owner tag sha40 por linea).
  awk '
    /^PIN_[A-Z0-9_]+_(OWNER|SHA|TAG)=/ {
      var=$0; sub(/=.*/, "", var)
      val=$0; sub(/^[^=]*=/, "", val)
      sub(/[[:space:]]+#.*$/, "", val); gsub(/\047/, "", val)
      kind=var; sub(/^PIN_.*_/, "", kind)
      base=var; sub(/^PIN_/, "", base); sub(/_(OWNER|SHA|TAG)$/, "", base)
      pin[base "-" kind]=val; bases[base]=1
    }
    END {
      for (b in bases)
        printf "%s %s %s\n", pin[b "-OWNER"], pin[b "-TAG"], pin[b "-SHA"]
    }
  ' "$GEN_REAL" | sort > "$work/fuente.txt"
  fallos=""
  for campo in OWNER SHA TAG; do
    sed "/^PIN_SETUP_NODE_$campo=/d" "$GEN_REAL" > "$work/gen-sin-$campo.sh"
    set +e
    out="$(runtime_exec "$work" \
      bash "$BUMP" --check --fuente "$work/fuente.txt" \
      --generador "$work/gen-sin-$campo.sh" 2>&1)"
    rc=$?
    set -e
    fm_action ci-pins-ilegible "act-sin-$campo" "$rc" "$out" \
      bash "$BUMP" --check --generador "gen-sin-$campo.sh"
    [ "$rc" -eq 2 ] || fallos="$fallos sin-$campo:rc=$rc"
    printf '%s' "$out" | grep -Fq 'PIN_SETUP_NODE' \
      || fallos="$fallos sin-$campo:no-nombra-pin"
    printf '%s' "$out" | grep -Fq "$campo" \
      || fallos="$fallos sin-$campo:no-nombra-campo"
    if printf '%s' "$out" | grep -Fq 'todos los pins al dia'; then
      fallos="$fallos sin-$campo:declaro-al-dia"
    fi
  done
  # assert:pins_ilegible_exit_2
  case "$fallos" in
    *rc=*) fm_fail ci-pins-ilegible pins_ilegible_exit_2 "exit 2" "fallos:$fallos" ;;
    *) fm_pass ci-pins-ilegible pins_ilegible_exit_2 "exit 2" "exit 2 por OWNER, SHA y TAG" ;;
  esac
  # assert:pins_ilegible_nombra_pin_y_campo
  case "$fallos" in
    *no-nombra*) fm_fail ci-pins-ilegible pins_ilegible_nombra_pin_y_campo \
      "PIN_SETUP_NODE + campo" "fallos:$fallos" ;;
    *) fm_pass ci-pins-ilegible pins_ilegible_nombra_pin_y_campo \
      "PIN_SETUP_NODE + campo" "nombra pin y campo faltante" ;;
  esac
  # assert:pins_ilegible_no_al_dia
  case "$fallos" in
    *declaro-al-dia*) fm_fail ci-pins-ilegible pins_ilegible_no_al_dia \
      "sin «todos los pins al dia»" "declaro al dia con pin ilegible" ;;
    *) fm_pass ci-pins-ilegible pins_ilegible_no_al_dia \
      "sin «todos los pins al dia»" "jamas declara al dia lo ilegible" ;;
  esac
fi

# ---------------------------------------------------------------------------
# bump-ci-pins --proponer: propuesta REVISABLE resuelta sin red por el gancho
# SAIKIT_BUMP_CI_PINS_API. r3 (cross-review hosts, Grok): --proponer tenia
# gotcha pero no ficha — la instruccion del bloque exigia cubrir el
# mantenimiento --check/--proponer. Espejo driver del producto
# pins_proponer_api_simulada_revisable (tests/test_ci_minimo.sh).
# ---------------------------------------------------------------------------
if fm_only ci-pins-proponer; then
  BUMP="$VERIFY_REPO/tools/bump-ci-pins.sh"
  GEN_REAL="$VERIFY_REPO/tools/saikit-ci-minimo.sh"
  work="$VERIFY_TMPDIR/ci-pins-prop"
  rm -rf "$work"
  mkdir -p "$work"
  cat > "$work/api.sh" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  'actions/setup-node v4.5.0') printf '%s\n' 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'; exit 0 ;;
esac
exit 1
EOF
  chmod +x "$work/api.sh"
  gen_ck="$(cksum < "$GEN_REAL")"
  set +e
  out="$(runtime_exec "$work" \
    env SAIKIT_BUMP_CI_PINS_API="$work/api.sh" \
    bash "$BUMP" --proponer actions/setup-node v4.5.0 2>&1)"
  rc=$?
  set -e
  fm_action ci-pins-proponer "act-proponer" "$rc" "$out" \
    env SAIKIT_BUMP_CI_PINS_API=api.sh bash bump-ci-pins.sh --proponer actions/setup-node v4.5.0
  fallos=""
  [ "$rc" -eq 0 ] || fallos="$fallos rc=$rc"
  printf '%s' "$out" | grep -Eq '^---' || fallos="$fallos no-diff"
  printf '%s' "$out" | grep -Fq 'NO aplicada' || fallos="$fallos sin-aviso"
  printf '%s' "$out" | grep -Fq "+PIN_SETUP_NODE_SHA='eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'" \
    || fallos="$fallos sin-sha-nuevo"
  printf '%s' "$out" | grep -Eq 'uses:[[:space:]]*[^ @]+@v[0-9]' && fallos="$fallos tag-flotante"
  [ "$(cksum < "$GEN_REAL")" = "$gen_ck" ] || fallos="$fallos escribio-generador"
  # assert:proponer_resuelve_sin_red
  case "$fallos" in
    *rc=*|*sin-sha-nuevo*) fm_fail ci-pins-proponer proponer_resuelve_sin_red "rc 0 con sha del gancho" "fallos:$fallos" ;;
    *) fm_pass ci-pins-proponer proponer_resuelve_sin_red "rc 0 con sha del gancho" "sha 40hex via SAIKIT_BUMP_CI_PINS_API" ;;
  esac
  # assert:proponer_diff_revisable_no_aplicado
  case "$fallos" in
    *no-diff*|*sin-aviso*) fm_fail ci-pins-proponer proponer_diff_revisable_no_aplicado "diff --- + NO aplicada" "fallos:$fallos" ;;
    *) fm_pass ci-pins-proponer proponer_diff_revisable_no_aplicado "diff --- + NO aplicada" "diff unificado con aviso de no aplicada" ;;
  esac
  # assert:proponer_cksum_intacto
  case "$fallos" in
    *escribio-generador*) fm_fail ci-pins-proponer proponer_cksum_intacto "generador intacto" "la propuesta escribio el generador" ;;
    *) fm_pass ci-pins-proponer proponer_cksum_intacto "generador intacto" "cksum del generador sin cambios" ;;
  esac
  # assert:proponer_sin_tag_flotante
  case "$fallos" in
    *tag-flotante*) fm_fail ci-pins-proponer proponer_sin_tag_flotante "ningun uses @tag" "la propuesta adopto @vN" ;;
    *) fm_pass ci-pins-proponer proponer_sin_tag_flotante "ningun uses @tag" "el pin queda owner@sha40" ;;
  esac
fi

exit 0
