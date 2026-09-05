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
RUNNER='ubuntu-latest'
WORKFLOW_NAME='saikit-ci-minimo'

# Si verify/ existe, se invoca un runner sobre esa ruta (no un echo).
# Si no existe, sale 0: el scaffold no exige verify en repos que aun no lo tienen.
# Sin comillas dobles internas: el YAML envuelve todo el run: en ".
VERIFY_CMD='bash -c '\''if [ ! -d verify ]; then echo saikit: verify/ ausente; exit 0; fi; if [ -f package.json ]; then npm test -- verify/; elif [ -f pytest.ini ] || { [ -f pyproject.toml ] && grep -Fq pytest pyproject.toml; } || { [ -f requirements.txt ] && grep -Fq pytest requirements.txt; }; then python -m pytest verify/; else find verify -type f -print -quit | grep -q .; fi'\'''

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
  awk '
    /"scripts"[[:space:]]*:/ { s=1 }
    s && /"test"[[:space:]]*:/ { print; exit }
  ' "$1" | grep -Eq 'node --test|vitest|jest|mocha|npm test'
}

rastros_pytest() {  # $1=root → 0 si pytest aparece
  local root="$1"
  [ -f "$root/pytest.ini" ] && return 0
  [ -f "$root/pyproject.toml" ] && grep -Fq pytest "$root/pyproject.toml" && return 0
  [ -f "$root/requirements.txt" ] && grep -Fq pytest "$root/requirements.txt" && return 0
  return 1
}

detectar_test_cmd() {  # $1=root → comando (nunca vacio)
  local root="$1"
  if [ -f "$root/tests/run.sh" ]; then
    printf 'bash tests/run.sh'
    return
  fi
  if [ -f "$root/package.json" ] && test_npm_real "$root/package.json"; then
    printf 'npm test'
    return
  fi
  if rastros_pytest "$root"; then
    printf 'python -m pytest'
    return
  fi
  printf 'bash tests/run.sh'
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

resolver_voluntad() {  # $1=flag o "" → SI|NO|DEFAULT_NO
  local flag="${1:-}"
  case "$flag" in
    si|SI|Si|s|S) printf 'SI' ;;
    no|NO|No|n|N) printf 'NO' ;;
    "")
      if [ -t 0 ]; then
        local r
        r="$(preguntar 'No hay workflows de GitHub Actions. Sin CI el autopilot no mergea (sin checks no es verde). Dejo un workflow minimo que corre el test del repo y verify/?' 'no')"
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

receta_emitir_yaml() {  # $1=test_cmd → YAML por stdout
  local test_cmd="$1"
  pin_valido "$PIN_CHECKOUT_SHA" || die "pin checkout no es sha de 40"
  cat <<EOF
name: $WORKFLOW_NAME
on:
  push:
  pull_request:
jobs:
  ci:
    runs-on: $RUNNER
    steps:
      - uses: $PIN_CHECKOUT_OWNER@$PIN_CHECKOUT_SHA  # $PIN_CHECKOUT_TAG
      - name: Test del repo
        run: $test_cmd
      - name: verify/
        run: "$VERIFY_CMD"
EOF
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
  mv -f "$tmp" "$dest" || { rm -f "$tmp"; die "no se pudo escribir $dest"; }
}

# ---------------------------------------------------------------------------
# Publico: --ofrecer. Setup y tests solo hablan con esto.
# ---------------------------------------------------------------------------

ofrecer() {
  local root disco voluntad test_cmd yaml
  root="${root_flag:-$(pwd)}"
  [ -d "$root" ] || die "--root no es un directorio: $root"
  disco="$(workflows_en_disco "$root")" || exit 2
  if [ "$disco" = PRESENTE ]; then
    printf 'saikit-ci-minimo: ya hay workflows, no se ofrece\n'
    return 0
  fi
  voluntad="$(resolver_voluntad "$ci_minimo_flag")" || exit 2
  case "$voluntad" in
    SI)
      test_cmd="$(detectar_test_cmd "$root")"
      yaml="$(receta_emitir_yaml "$test_cmd")" || exit 2
      escribir_atomico "$root" "$yaml"
      printf 'saikit-ci-minimo: escrito %s\n' "$DESTINO_REL"
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
