#!/usr/bin/env bash
# tools/bump-ci-pins.sh — Mantenimiento de pins del CI minimo (fila 20.7).
#
# QUE HACE. Los pins de actions del generador tools/saikit-ci-minimo.sh
# (bloque PIN_<X>_{OWNER,SHA,TAG}) son inmutables por diseno: moverlos a
# mano, sin fuente verificable, es como no tenerlos. Este tool es el
# mecanismo, en dos modos que SOLO miran el generador: jamas escriben un
# workflow (ni el que el generador crea, ni los ajenos, ni ninguno).
#
#   --check  [--fuente <fixture>] [--generador <file>]
#       Compara cada (owner, tag, sha) del generador contra la fuente.
#       Exit 0 = al dia; 1 = hay pin obsoleto (el tag de la fuente apunta
#       a OTRO sha); 2 = no se pudo verificar (sin red, tag desconocido,
#       pin ilegible). Fail-closed: «al dia» solo se declara si CADA pin
#       se pudo mirar.
#
#   --proponer <owner/repo> <tag> [--fuente <fixture>] [--generador <file>]
#       Resuelve el sha commit real de <owner/repo>:<tag> e imprime por
#       stdout un diff UNIFICADO para revisar y aplicar a mano. NUNCA
#       escribe: ni el generador ni workflows. El pin resultante sigue
#       siendo owner@<sha-de-40> con el tag en comentario; un tag flotante
#       (@v4) no se adopta jamas.
#
# FUENTE. Default: API publica de GitHub — gh api si hay sesion, si no
# curl; endpoint commits/<tag> (resuelve tags anotados al commit). Sin
# red: exit 2 DECLARADO, no se inventan shas. --fuente <file> es un
# fixture sin red: lineas `owner/repo tag sha40` (vacias y # ignoradas).
#
# USO:
#   tools/bump-ci-pins.sh --check [--fuente <fixture>] [--generador <file>]
#   tools/bump-ci-pins.sh --proponer <owner/repo> <tag> [--fuente <fixture>]
#                         [--generador <file>]
#
# Gancho SOLO de test: SAIKIT_BUMP_CI_PINS_API (comando que recibe
# `owner/repo tag' y imprime el sha) overridea el cliente HTTP.
#
# Exit: 0 resuelto (al dia | propuesta impresa | nada que proponer);
#       1 obsoleto (solo --check); 2 uso / no se pudo consultar / ilegible.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

uso() { sed -n '2,38p' "$0"; }

die() { printf 'saikit-bump-ci-pins: %s\n' "$*" >&2; exit 2; }

pin_valido() {  # $1=sha → 0 si ^[0-9a-f]{40}$
  printf '%s' "$1" | grep -Eq '^[0-9a-f]{40}$'
}

pin_al_dia() {  # $1=sha de la fuente $2=sha pineado → 0 si coinciden
  [ "$1" = "$2" ]
}

# ---------------------------------------------------------------------------
# Borde: parse de los pins del generador. Un pin sin OWNER/SHA/TAG es
# ilegible y TODO muere cerrado: no se declara «al dia» lo que no se leyó.
# ---------------------------------------------------------------------------

pins_del_generador() {  # $1=generador → lineas `owner tag sha BASE' (o marcador PIN_*)
  awk '
    /^PIN_[A-Z0-9_]+_(OWNER|SHA|TAG)=/ {
      var=$0; sub(/=.*/, "", var)
      val=$0; sub(/^[^=]*=/, "", val)
      sub(/[[:space:]]+#.*$/, "", val)
      gsub(/'\''/, "", val)
      kind=var; sub(/^PIN_.*_/, "", kind)
      base=var; sub(/^PIN_/, "", base); sub(/_(OWNER|SHA|TAG)$/, "", base)
      pin[base "-" kind]=val; bases[base]=1
    }
    END {
      n=0
      for (b in bases) {
        o=pin[b "-OWNER"]; s=pin[b "-SHA"]; t=pin[b "-TAG"]
        if (o == "" || s == "" || t == "") { printf "PIN_ILEGIBLE %s\n", b; continue }
        printf "%s %s %s %s\n", o, t, s, b
        n++
      }
      if (n == 0) print "PIN_NINGUNO"
    }
  ' "$1" | sort
}

leer_pins() {  # $1=generador → stdout lineas validadas `owner tag sha BASE'
  local gen="$1" out="" owner tag sha base
  [ -f "$gen" ] || die "no encuentro el generador: $gen"
  out="$(pins_del_generador "$gen")"
  [ -n "$out" ] || die "el generador no expone pins: $gen"
  while read -r owner tag sha base; do
    [ -n "$base" ] || continue
    case "$owner" in
      PIN_ILEGIBLE) die "pin ilegible: falta OWNER, SHA o TAG para PIN_${tag} en $gen" ;;
      PIN_NINGUNO)  die "el generador no expone pins: $gen" ;;
    esac
    printf '%s' "$owner" | grep -Eq '^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$' \
      || die "PIN_${base}_OWNER ilegible: $owner"
    pin_valido "$sha" || die "PIN_${base}_SHA no es sha de 40 hex: $sha"
    printf '%s' "$tag" | grep -Eq '^[A-Za-z0-9._-]+$' \
      || die "PIN_${base}_TAG ilegible: $tag"
    printf '%s %s %s %s\n' "$owner" "$tag" "$sha" "$base"
  done < <(printf '%s\n' "$out")
}

# ---------------------------------------------------------------------------
# Fuente: fixture o API publica. La fuente RESUELVE o muere (exit 2);
# nunca devuelve un sha que no haya validado.
# ---------------------------------------------------------------------------

sha_de_fixture() {  # $1=file $2=owner/repo $3=tag → sha | die
  local f="$1" par="$2" tag="$3" sha=""
  [ -f "$f" ] || die "la fuente no existe: $f"
  sha="$(awk -v o="$par" -v t="$tag" '
    /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
    $1 == o && $2 == t {
      if (NF != 3 || $3 !~ /^[0-9a-f]+$/ || length($3) != 40) {
        printf "malformada: %s\n", $0 > "/dev/stderr"; exit 1
      }
      print $3; exit 0
    }
  ' "$f")" || die "fixture malformada al resolver $par $tag (se espera: owner/repo tag sha40)"
  [ -n "$sha" ] || die "la fuente no conoce $par $tag; no se inventa sha"
  printf '%s' "$sha"
}

sha_de_api() {  # $1=owner/repo $2=tag → sha | die
  local par="$1" tag="$2" sha=""
  if [ -n "${SAIKIT_BUMP_CI_PINS_API:-}" ]; then
    sha="$("$SAIKIT_BUMP_CI_PINS_API" "$par" "$tag" 2>/dev/null)" \
      || die "no se pudo consultar $par $tag (SAIKIT_BUMP_CI_PINS_API fallo); sin sha no hay veredicto"
  elif command -v gh >/dev/null 2>&1; then
    # Endpoint commits/<tag>: resuelve tags anotados al COMMIT, que es lo
    # que un pin inmutable necesita (el sha del objeto tag no sirve).
    sha="$(gh api "repos/$par/commits/$tag" --jq .sha 2>/dev/null)" \
      || die "no se pudo consultar $par $tag con gh api; sin sha no hay veredicto"
  elif command -v curl >/dev/null 2>&1; then
    sha="$(curl -fsSL --max-time 20 "https://api.github.com/repos/$par/commits/$tag" \
      | python3 -c 'import json,sys; print(json.load(sys.stdin)["sha"])' 2>/dev/null)" \
      || die "no se pudo consultar $par $tag con curl; sin sha no hay veredicto"
  else
    die "sin red: no hay gh ni curl; usa --fuente <fixture> o reintenta con red"
  fi
  pin_valido "$sha" || die "la fuente devolvio algo que no es sha de 40 para $par $tag: ${sha:-vacio}"
  printf '%s' "$sha"
}

fuente_sha() {  # $1=owner/repo $2=tag → sha | die
  if [ -n "$fuente_flag" ]; then
    sha_de_fixture "$fuente_flag" "$1" "$2"
  else
    sha_de_api "$1" "$2"
  fi
}

# ---------------------------------------------------------------------------
# Modos publicos.
# ---------------------------------------------------------------------------

cmd_check() {
  local out="" owner tag sha base sha_fuente obsoletos=0 total=0
  out="$(leer_pins "$generador")" || exit 2
  while read -r owner tag sha base; do
    total=$((total + 1))
    sha_fuente="$(fuente_sha "$owner" "$tag")" || exit 2
    if pin_al_dia "$sha_fuente" "$sha"; then
      printf 'saikit-bump-ci-pins: al dia: %s %s (%s)\n' "$owner" "$tag" "$sha"
    else
      obsoletos=$((obsoletos + 1))
      printf 'saikit-bump-ci-pins: OBSOLETO: %s %s: el generador pinea %s y la fuente dice %s (PIN_%s_SHA)\n' \
        "$owner" "$tag" "$sha" "$sha_fuente" "$base"
    fi
  done < <(printf '%s\n' "$out")
  if [ "$obsoletos" -gt 0 ]; then
    printf 'saikit-bump-ci-pins: %d de %d pin(s) obsoleto(s); actualizar con: tools/bump-ci-pins.sh --proponer <owner/repo> <tag>\n' \
      "$obsoletos" "$total"
    exit 1
  fi
  printf 'saikit-bump-ci-pins: todos los pins al dia (%d)\n' "$total"
  exit 0
}

cmd_proponer() {  # $1=owner/repo $2=tag
  local par="$1" tag="$2" sha base tmp prop_sha
  printf '%s' "$par" | grep -Eq '^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$' \
    || die "accion mal formada (se espera owner/repo): $par"
  printf '%s' "$tag" | grep -Eq '^[A-Za-z0-9._-]+$' \
    || die "tag mal formado: $tag"
  pin_valido "$tag" && die "eso parece un sha, no un tag: $tag"
  sha="$(fuente_sha "$par" "$tag")" || exit 2
  base="$(leer_pins "$generador" | awk -v p="$par" '$1 == p { print $4; exit }')" || exit 2
  [ -n "$base" ] || die "el generador no pinea $par; solo se refrescan pins existentes"
  tmp="$(mktemp "${TMPDIR:-/tmp}/saikit-bump-ci-pins.XXXXXX")" || die "no se pudo crear el temporal"
  # La propuesta toca SOLO las dos lineas literales del pin; los uses: del
  # generador referencian variables, asi que ningun workflow cambia de forma.
  if ! sed -e "s|^PIN_${base}_SHA='.*'|PIN_${base}_SHA='$sha'|" \
           -e "s|^PIN_${base}_TAG='.*'|PIN_${base}_TAG='$tag'|" \
           "$generador" > "$tmp"; then
    rm -f "$tmp"
    die "no se pudo construir la propuesta"
  fi
  # Guarda de borde: la propuesta tiene que re-parsear al nuevo pin. Si el
  # sed no calzo (bloque PIN_ movido o renombrado), NO se imprime nada.
  prop_sha="$(leer_pins "$tmp" | awk -v p="$par" '$1 == p { print $3; exit }')" || { rm -f "$tmp"; exit 2; }
  [ "$prop_sha" = "$sha" ] || { rm -f "$tmp"; die "la propuesta no quedo pineada a $sha; no se imprime"; }
  if cmp -s "$generador" "$tmp"; then
    rm -f "$tmp"
    printf 'saikit-bump-ci-pins: nada que proponer: el generador ya pinea %s %s en %s\n' "$par" "$tag" "$sha"
    exit 0
  fi
  printf 'saikit-bump-ci-pins: propuesta (NO aplicada) para %s %s -> %s\n' "$par" "$tag" "$sha"
  printf 'saikit-bump-ci-pins: revisa el diff y aplicalo a mano; este tool no escribe el generador ni ningun workflow\n'
  diff -u -L "$generador" -L "$generador (propuesta)" "$generador" "$tmp" || true
  rm -f "$tmp"
  exit 0
}

# ---------------------------------------------------------------------------
# Borde CLI.
# ---------------------------------------------------------------------------

modo=""
generador="$HERE/saikit-ci-minimo.sh"
fuente_flag=""
posicionales=""

while [ $# -gt 0 ]; do
  case "$1" in
    --check)    modo=check; shift ;;
    --proponer) modo=proponer; shift ;;
    --fuente|--generador)
      if [ $# -lt 2 ]; then die "$1 exige un valor"; fi
      case "$1" in
        --fuente)    fuente_flag="$2" ;;
        --generador) generador="$2" ;;
      esac
      shift 2 ;;
    -h|--help) uso; exit 0 ;;
    -*) die "opcion desconocida: $1 (se espera --check o --proponer)" ;;
    *) posicionales="$posicionales $1"; shift ;;
  esac
done

# shellcheck disable=SC2086  # owner/repo y tag no llevan espacios (validado)
set -- $posicionales

case "$modo" in
  check)
    [ "$#" -eq 0 ] || die "--check no toma argumentos posicionales: $*"
    cmd_check
    ;;
  proponer)
    if [ "$#" -lt 2 ]; then die "--proponer exige <owner/repo> <tag>"; fi
    if [ "$#" -gt 2 ]; then die "sobran argumentos: $*"; fi
    cmd_proponer "$1" "$2"
    ;;
  *)
    uso >&2
    exit 2
    ;;
esac
