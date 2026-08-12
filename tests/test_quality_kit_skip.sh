#!/usr/bin/env bash
# Task 2.3 + Task 4.1 — la costura con quality-kit, probada desde ESTE lado.
#
# El problema: `saikit-gate-heal.ps1` (quality-kit) parchea el hook por ANCLAS
# en cada SessionStart, y este repo lo instala por REEMPLAZO. Dos escritores
# sobre la misma ruta con modelos distintos pueden dejar el archivo doblemente
# parchado o truncado. La costura EVOLUCIONO en dos pasos:
#   - Task 2.3: quality-kit salteaba cualquier archivo con el marcador de
#     propiedad (skip por host).
#   - Task 4.1: .claude dejo de ser target del heal del todo (lo instala entero
#     este repo, con marcador y los dos parches adentro). La superficie de doble
#     escritor sobre .claude desaparece; el skip queda como red de seguridad
#     para .codex/.cursor/.agents.
#
# Por que el test vive TAMBIEN aca, y no solo en la bateria de quality-kit: el
# marcador es un artefacto de ESTE repo. Si un dia cambia su prefijo, la
# bateria del kit seguiria verde (usa su propio literal) y la costura se
# romperia en silencio. Este test mira los DOS artefactos reales a la vez:
# (1) que el heal nombre el prefijo del marcador (la red de seguridad sigue
# cableada) y (2) que .claude no este en $targets del heal (Task 4.1).
#
# El caso inverso —un hook SIN marcador se sigue parcheando igual que hoy—
# vive en la bateria de quality-kit (TEST GROUP 3n), que es donde estan los
# fixtures de hooks del vendor.
#
# Core Rule 4: fake USERPROFILE en un tmpdir. Jamas toca `~/.claude`.
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
fuente="$repo/hooks/summonaikit-harness.sh"
kit="${SAIKIT_QUALITY_KIT:-C:/Users/ehven/quality-kit}"
heal="$kit/saikit-gate-heal.ps1"

fail=0
caso() { printf '  caso: %s\n' "$1"; }
malo() { printf '    FAIL: %s\n' "$1" >&2; fail=1; }

# quality-kit es de otro repo: si no esta en esta maquina se declara el salto y
# se sale limpio. Una bateria que se pone roja porque un repo hermano no esta
# clonado entrena al operador a ignorarla.
if [ ! -r "$heal" ]; then
  echo "  SKIP: no hay quality-kit en $kit — la costura no se pudo verificar acá."
  echo "test_quality_kit_skip: OK (skip declarado)"
  exit 0
fi

if [ ! -r "$fuente" ]; then
  echo "test_quality_kit_skip: FAIL (no hay fuente en $fuente)" >&2
  exit 1
fi

# El prefijo sale de la fuente REAL, no de un literal escrito acá: es lo que
# vuelve al test capaz de ver una divergencia entre los dos repos.
marcador="$(sed -n '2p' "$fuente")"
prefijo="${marcador% *}"          # sin la version
prefijo="${prefijo% *}"           # sin el nombre del repo  => '# SAIKIT-CLAUDE-OWNED'

caso "el marcador de la fuente es el que quality-kit busca"
if [ -z "$prefijo" ] || [ "$prefijo" = "$marcador" ]; then
  malo "no se pudo derivar el prefijo del marcador desde la linea 2: '$marcador'"
elif ! grep -qF "$prefijo" "$heal"; then
  malo "saikit-gate-heal.ps1 no nombra '$prefijo': la costura no existe o cambio de forma"
fi

# --------------------------------------------------- 2) el heal REAL, corrido
caso "el heal real, sobre nuestra fuente real, la deja byte a byte igual"

pwsh_bin=''
for c in powershell.exe powershell pwsh; do
  if command -v "$c" >/dev/null 2>&1; then pwsh_bin="$c"; break; fi
done

if [ -z "$pwsh_bin" ]; then
  echo "  SKIP: no hay powershell en esta maquina — el caso end-to-end no se pudo correr."
else
  # (b) Task 4.1: .claude ya no es target del heal. Es la afirmacion que
  # discrimina y mide el rojo: con .claude AUN como target (pre-4.1) este caso
  # falla. El rojo de este invariant se midio en la bateria de quality-kit
  # (TEST GROUP 3q: .claude recibia el sentinel -> era target); aca es el espejo
  # desde este lado del repo y va verde una vez aplicada la 4.1.
  targets_line="$(grep -nE '^\$targets\s*=' "$heal" | head -1)"
  caso ".claude no esta en \$targets del heal (Task 4.1)"
  [ -n "$targets_line" ] || malo "no se encontro la linea \$targets en el heal"
  printf '%s\n' "$targets_line" | grep -qF '.claude' \
    && malo ".claude sigue como target del heal (Task 4.1 sin aplicar): $targets_line"

  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  mkdir -p "$tmp/home/.claude/hooks"
  destino="$tmp/home/.claude/hooks/summonaikit-harness.sh"
  cp "$fuente" "$destino"

  antes="$(cksum < "$destino")"

  if command -v cygpath >/dev/null 2>&1; then
    home_win="$(cygpath -w "$tmp/home")"
    heal_win="$(cygpath -w "$heal")"
  else
    home_win="$tmp/home"
    heal_win="$heal"
  fi

  out="$(USERPROFILE="$home_win" "$pwsh_bin" -NoProfile -ExecutionPolicy Bypass \
           -File "$heal_win" 2>&1)"; rc=$?
  despues="$(cksum < "$destino")"

  # (a) Task 4.1: .claude no se toca. Antes era por skip (marcador); desde la
  # 4.1 es por construccion (.claude no es target, no se itera). El cksum sigue
  # siendo la afirmacion fuerte y sigue siendo cierto por el motivo que toca.
  # (c) No se busca 'saltado': tras la 4.1 el heal no itera .claude, asi que la
  # linea 'saltado' ya no se emite para este perfil -- el contrato nuevo es
  # no-iteracion, medido arriba con el cksum.
  [ "$rc" -eq 0 ] || malo "el heal salio $rc; debe salir 0 siempre (no puede tumbar un arranque)"
  [ "$antes" = "$despues" ] || malo "el heal REESCRIBIO el hook .claude: tras la Task 4.1 no es target y no debe tocarlo: $out"
fi

if [ "$fail" -ne 0 ]; then
  echo "test_quality_kit_skip: FAIL" >&2
  exit 1
fi
echo "test_quality_kit_skip: OK"
