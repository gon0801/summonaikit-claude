#!/usr/bin/env bash
# tools/saikit-ci-minimo.sh — CLI profundo de la oferta de CI minimo.
#
# QUE HACE. Si el repo no tiene .github/workflows/*.{yml,yaml}, ofrece un
# workflow minimo (test del repo + verify/) con acciones pinneadas (sha de
# 40 hex embebido, sin red, sin secrets). Sin TTY asume no y AVISA que el
# autopilot no mergea. PRESENTE (cualquier yml/yaml en disco) es NOOP.
#
# El estado de la oferta es disco x voluntad, no un registro serializado.
# La Receta es pasos tipados; el YAML se renderiza al escribir.
#
# USO:
#   tools/saikit-ci-minimo.sh --ofrecer [--root <dir>] [--ci-minimo si|no]
#
# Exit: 0 resuelto (PRESENTE noop | ESCRITO | RECHAZADO con aviso);
#       2 uso / validacion / no se pudo escribir.
#
# Gancho SOLO de test: SAIKIT_CI_MINIMO (ruta que setup invoca).
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PIN_CHECKOUT_OWNER='actions/checkout'
PIN_CHECKOUT_SHA='11bd71901bbe5b1630ceea73d27597364c9af683'
PIN_CHECKOUT_TAG='v4.2.2'

DESTINO_REL='.github/workflows/saikit-ci-minimo.yml'
RUNNER='ubuntu-24.04'
TIMEOUT_MINUTES=15
WORKFLOW_NAME='saikit-ci-minimo'
# ${{ }} no se escribe crudo en <<EOF: bash lo come.
CONCURRENCY_GROUP='${{ github.workflow }}-${{ github.ref }}'

PIN_SETUP_PYTHON_OWNER='actions/setup-python'
PIN_SETUP_PYTHON_SHA='a26af69be951a213d495a4c3e4e4022e16d87065'
PIN_SETUP_PYTHON_TAG='v5.6.0'

PIN_SETUP_NODE_OWNER='actions/setup-node'
PIN_SETUP_NODE_SHA='49933ea5288caeca8642d1e84afbd3f7d6820020'
PIN_SETUP_NODE_TAG='v4.4.0'

# Refresh de pins (20.7): tools/bump-ci-pins.sh --check detecta pin obsoleto
# contra una fuente (fixture o API de GitHub) y --proponer emite el diff a
# revisar; nunca escribe ni adopta tag flotante. El tag vive en PIN_*_TAG
# porque el check lo compara. quality.yml de ESTE repo sigue en tags (los
# workflows reales son ajenos a este mecanismo).

uso() { sed -n '2,20p' "$0"; }

die() { printf 'saikit-ci-minimo: %s\n' "$*" >&2; exit 2; }

# ---------------------------------------------------------------------------
# Borde: disco, voluntad, test
# ---------------------------------------------------------------------------

workflows_en_disco() {  # $1=root → AUSENTE|PRESENTE
  local root="$1" wf="$1/.github/workflows"
  if [ -L "$root/.github" ] || [ -L "$wf" ]; then
    die ".github o workflows es un enlace simbolico; no se escribe a traves"
  fi
  [ -d "$wf" ] || { printf 'AUSENTE'; return; }
  if find "$wf" -maxdepth 1 \( -name '*.yml' -o -name '*.yaml' \) -type f 2>/dev/null \
      | grep -q .; then
    printf 'PRESENTE'
  else
    printf 'AUSENTE'
  fi
}

test_npm_real() {  # $1=package.json → 0 si scripts.test parece runner real
  # Alcance cerrado al objeto scripts (contar llaves). Un "test" en jest/config
  # fuera de scripts NO cuenta (bug lead #185). Se mira "test" ANTES de
  # procesar } en la misma linea (forma compacta "scripts": { "test": "jest" }).
  awk '
    /"scripts"[[:space:]]*:/ { in_scripts=1 }
    in_scripts {
      if (/"test"[[:space:]]*:/) { print; exit }
      for (i = 1; i <= length($0); i++) {
        c = substr($0, i, 1)
        if (c == "{") depth++
        if (c == "}") {
          depth--
          if (depth <= 0) { in_scripts=0; depth=0; break }
        }
      }
    }
  ' "$1" | grep -Eq 'node --test|vitest|jest|mocha|npm test'
}

rastros_pytest() {  # $1=root → 0 si pytest aparece
  local root="$1"
  [ -f "$root/pytest.ini" ] && return 0
  [ -f "$root/pyproject.toml" ] && grep -Fq pytest "$root/pyproject.toml" && return 0
  [ -f "$root/requirements.txt" ] && grep -Fq pytest "$root/requirements.txt" && return 0
  return 1
}

detectar_test_cmd() {  # $1=root → comando o return 2 (vacio es ilegal)
  local root="$1"
  if [ -f "$root/tests/run.sh" ]; then
    printf 'bash tests/run.sh'
    return 0
  fi
  if [ -f "$root/package.json" ] && test_npm_real "$root/package.json"; then
    if [ -f "$root/yarn.lock" ]; then
      printf 'yarn test'
    elif [ -f "$root/pnpm-lock.yaml" ]; then
      printf 'pnpm test'
    else
      printf 'npm test'
    fi
    return 0
  fi
  if rastros_pytest "$root"; then
    printf 'python -m pytest'
    return 0
  fi
  return 2
}

# Pura: solo el test_cmd congelado. Nunca re-detecta ni emite find.
verify_cmd_from() {  # $1=test_cmd → invocacion o die
  case "$1" in
    'bash tests/run.sh') printf 'bash tests/run.sh verify/' ;;
    'npm test')          printf 'npm test -- verify/' ;;
    'yarn test')         printf 'yarn test -- verify/' ;;
    'pnpm test')         printf 'pnpm test -- verify/' ;;
    'python -m pytest')  printf 'python -m pytest verify/' ;;
    *) die "no se puede mapear verify desde: $1" ;;
  esac
}

# AUSENTE = no hay dir (scaffold echo). SOLO_MD = solo md o vacio: omitir.
# -iname: LEEME.MD (mayusculas) sigue siendo markdown, no TIENE.
clasif_verify() {  # $1=root → AUSENTE|SOLO_MD|TIENE
  local root="$1"
  [ -d "$root/verify" ] || { printf 'AUSENTE'; return; }
  if find "$root/verify" -type f ! -iname '*.md' 2>/dev/null | grep -q .; then
    printf 'TIENE'
    return
  fi
  printf 'SOLO_MD'
}

texto_oferta() {  # $1=test_cmd
  printf 'No hay workflows de GitHub Actions. Sin CI el autopilot no mergea (sin checks no es verde). Dejo un workflow minimo que corre «%s» y verify/?' "$1"
}

preguntar() {  # $1=texto $2=default — copia de setup; no sourcear setup
  local texto="$1" def="$2" resp=""
  if [ -t 0 ]; then
    printf '%s [%s]: ' "$texto" "$def" >&2
    IFS= read -r resp || resp=""
    [ -n "$resp" ] || resp="$def"
    printf '%s' "$resp"
  else
    printf '%s' "$def"
  fi
}

resolver_voluntad() {  # $1=flag $2=test_cmd → SI|NO|DEFAULT_NO
  local flag="${1:-}" test_cmd="${2:-}"
  case "$flag" in
    si|SI|Si|s|S) printf 'SI' ;;
    no|NO|No|n|N) printf 'NO' ;;
    "")
      if [ -t 0 ]; then
        local r
        r="$(preguntar "$(texto_oferta "$test_cmd")" 'no')"
        case "$r" in
          si|SI|Si|s|S) printf 'SI' ;;
          *) printf 'DEFAULT_NO' ;;
        esac
      else
        printf 'DEFAULT_NO'
      fi
      ;;
    *) die "--ci-minimo exige si/no (llego: $flag)" ;;
  esac
}

aviso_sin_ci_no_mergea() {
  printf 'saikit-ci-minimo: sin CI el autopilot no mergea (sin checks no es verde)\n'
}

# ---------------------------------------------------------------------------
# Receta → YAML. Validacion en el borde de escritura.
# ---------------------------------------------------------------------------

pin_valido() {  # $1=sha → 0 si ^[0-9a-f]{40}$
  printf '%s' "$1" | grep -Eq '^[0-9a-f]{40}$'
}

install_step() {  # $1=root $2=test_cmd → pasos YAML o vacio
  local root="$1" test_cmd="$2" pip_cmd
  case "$test_cmd" in
    'npm test')
      if [ -f "$root/package-lock.json" ]; then
        cat <<EOF
      - name: Install deps
        run: npm ci
EOF
      else
        cat <<EOF
      - name: Install deps
        run: npm install
EOF
      fi
      ;;
    'yarn test')
      cat <<EOF
      - name: Install deps
        run: yarn install --frozen-lockfile
EOF
      ;;
    'pnpm test')
      # ubuntu-24.04 trae npm/yarn, no pnpm. Sin setup-node + corepack nace rojo.
      pin_valido "$PIN_SETUP_NODE_SHA" || die "pin setup-node no es sha de 40"
      cat <<EOF
      - uses: $PIN_SETUP_NODE_OWNER@$PIN_SETUP_NODE_SHA  # $PIN_SETUP_NODE_TAG
        with:
          node-version: '20'
      - name: Enable pnpm
        run: corepack enable
      - name: Install deps
        run: pnpm install --frozen-lockfile
EOF
      ;;
    'python -m pytest')
      pin_valido "$PIN_SETUP_PYTHON_SHA" || die "pin setup-python no es sha de 40"
      # requirements.txt puede no listar pytest; instalar ambos cierra el hueco.
      if [ -f "$root/requirements.txt" ]; then
        pip_cmd='pip install -r requirements.txt && pip install pytest'
      else
        pip_cmd='pip install pytest'
      fi
      cat <<EOF
      - uses: $PIN_SETUP_PYTHON_OWNER@$PIN_SETUP_PYTHON_SHA  # $PIN_SETUP_PYTHON_TAG
        with:
          python-version: '3.12'
      - name: Install deps
        run: $pip_cmd
EOF
      ;;
  esac
}

receta_emitir_yaml() {  # $1=root $2=test_cmd $3=clasif → YAML por stdout
  local root="$1" test_cmd="$2" clasif="$3" vcmd
  pin_valido "$PIN_CHECKOUT_SHA" || die "pin checkout no es sha de 40"
  cat <<EOF
name: $WORKFLOW_NAME
permissions:
  contents: read
on:
  push:
  pull_request:
jobs:
  ci:
    runs-on: $RUNNER
    timeout-minutes: $TIMEOUT_MINUTES
    concurrency:
      group: $CONCURRENCY_GROUP
      cancel-in-progress: true
    steps:
      - uses: $PIN_CHECKOUT_OWNER@$PIN_CHECKOUT_SHA  # $PIN_CHECKOUT_TAG
        with:
          persist-credentials: false
EOF
  install_step "$root" "$test_cmd"
  cat <<EOF
      - name: Test del repo
        run: $test_cmd
EOF
  case "$clasif" in
    AUSENTE)
      cat <<EOF
      - name: verify/
        run: "echo saikit: verify/ ausente; exit 0"
EOF
      ;;
    SOLO_MD)
      ;;
    TIENE)
      vcmd="$(verify_cmd_from "$test_cmd")"
      cat <<EOF
      - name: verify/
        run: "$vcmd"
EOF
      ;;
    *) die "clasif_verify desconocida: $clasif" ;;
  esac
}

yaml_seguro() {  # $1=yaml → 0 o die
  local yaml="$1" linea rest sha n=0
  printf '%s' "$yaml" | grep -Eq 'secrets\.|secrets\[|secrets:[[:space:]]*inherit' \
    && die "secrets prohibidos en el workflow"
  while IFS= read -r linea; do
    n=$((n + 1))
    rest="${linea#*uses:}"
    rest="${rest#"${rest%%[![:space:]]*}"}"
    sha="${rest##*@}"
    sha="${sha%%[[:space:]#]*}"
    pin_valido "$sha" || die "uses no es sha de 40: $linea"
  done < <(printf '%s\n' "$yaml" | grep -E '^[[:space:]]*(-[[:space:]]*)?uses:')
  [ "$n" -gt 0 ] || die "el workflow no tiene uses:"
}

escribir_atomico() {  # $1=root $2=yaml
  local root="$1" yaml="$2"
  local dest="$root/$DESTINO_REL"
  local dir tmp
  dir="$(dirname "$dest")"
  if [ -L "$root/.github" ] || [ -L "$dir" ] || [ -L "$dest" ]; then
    die ".github, workflows o el destino es un enlace simbolico"
  fi
  yaml_seguro "$yaml"
  mkdir -p "$dir" || die "no se pudo crear $dir"
  tmp="$(mktemp "$dir/.saikit-ci-minimo.yml.XXXXXX")" \
    || die "no se pudo crear el temporal para $dest"
  if ! printf '%s\n' "$yaml" > "$tmp"; then
    rm -f "$tmp"
    die "no se pudo escribir $dest"
  fi
  yaml_seguro "$(cat "$tmp")" || { rm -f "$tmp"; exit 2; }
  # Gancho SOLO de test: simula que el destino aparece entre consentimiento y publish.
  if [ -n "${SAIKIT_CI_BEFORE_WRITE:-}" ]; then
    ( cd "$root" && eval "$SAIKIT_CI_BEFORE_WRITE" ) || true
  fi
  # Rechequeo de carrera: algo pudo crear workflows mientras la oferta pendia.
  if [ -e "$dest" ] || [ "$(workflows_en_disco "$root")" = PRESENTE ]; then
    rm -f "$tmp"
    die "carrera: ya hay workflow; no se pisa"
  fi
  # mv -n no reemplaza; si el destino aparece entre el rechequeo y el mv,
  # el temporal sigue ahi y lo tratamos como carrera.
  if ! mv -n "$tmp" "$dest" 2>/dev/null || [ -e "$tmp" ]; then
    rm -f "$tmp"
    die "carrera: el destino aparecio al publicar; no se pisa"
  fi
}

# ---------------------------------------------------------------------------
# Publico: --ofrecer. Setup y tests solo hablan con esto.
# ---------------------------------------------------------------------------

ofrecer() {
  local root disco voluntad test_cmd yaml clasif
  root="${root_flag:-$(pwd)}"
  [ -d "$root" ] || die "--root no es un directorio: $root"
  disco="$(workflows_en_disco "$root")" || exit 2
  if [ "$disco" = PRESENTE ]; then
    printf 'saikit-ci-minimo: ya hay workflows, no se ofrece\n'
    return 0
  fi
  # Flag no / sin TTY: no detectar. El aviso no cita un comando inventado.
  case "$ci_minimo_flag" in
    no|NO|No|n|N)
      aviso_sin_ci_no_mergea
      return 0
      ;;
    "")
      if [ ! -t 0 ]; then
        aviso_sin_ci_no_mergea
        return 0
      fi
      ;;
  esac
  test_cmd="$(detectar_test_cmd "$root")" \
    || die "sin runner: no tests/run.sh, no scripts.test real, no rastros pytest"
  voluntad="$(resolver_voluntad "$ci_minimo_flag" "$test_cmd")" || exit 2
  case "$voluntad" in
    SI)
      clasif="$(clasif_verify "$root")"
      yaml="$(receta_emitir_yaml "$root" "$test_cmd" "$clasif")" || exit 2
      escribir_atomico "$root" "$yaml"
      printf 'saikit-ci-minimo: escrito %s (corre: %s)\n' "$DESTINO_REL" "$test_cmd"
      if [ "$clasif" = SOLO_MD ]; then
        printf 'saikit-ci-minimo: verify/ solo markdown; no se emite el paso verify/\n'
      fi
      ;;
    NO|DEFAULT_NO)
      aviso_sin_ci_no_mergea
      ;;
    *) die "voluntad desconocida: $voluntad" ;;
  esac
}

root_flag=""
ci_minimo_flag=""
modo=""

while [ $# -gt 0 ]; do
  case "$1" in
    --ofrecer) modo=ofrecer; shift ;;
    --root|--ci-minimo)
      if [ $# -lt 2 ]; then die "$1 exige un valor"; fi
      case "$1" in
        --root)      root_flag="$2" ;;
        --ci-minimo) ci_minimo_flag="$2" ;;
      esac
      shift 2 ;;
    -h|--help) uso; exit 0 ;;
    *) die "opcion desconocida: $1" ;;
  esac
done

[ "$modo" = ofrecer ] || { uso >&2; exit 2; }
ofrecer
exit 0
