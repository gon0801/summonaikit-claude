#!/usr/bin/env bash
# Task 2.3 — la costura con quality-kit, probada desde ESTE lado.
#
# El problema: `saikit-gate-heal.ps1` (quality-kit) parchea el hook por ANCLAS
# en cada SessionStart, y este repo lo instala por REEMPLAZO. Dos escritores
# sobre la misma ruta con modelos distintos pueden dejar el archivo doblemente
# parchado o truncado. La costura acordada es por host: quality-kit saltea
# cualquier archivo que lleve el marcador de propiedad.
#
# Por que el test vive TAMBIEN aca, y no solo en la bateria de quality-kit: el
# marcador es un artefacto de ESTE repo. Si un dia cambia su prefijo, la
# bateria del kit seguiria verde (usa su propio literal) y la costura se
# rompería en silencio. Este test mira los DOS artefactos reales a la vez.
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

  # El cksum es la afirmacion fuerte y es la UNICA que discrimina: nuestra
  # fuente es el archivo vivo, que ya trae los dos parches del kit adentro
  # (Task 2.1, byte a byte), asi que buscar los marcadores `SAIKIT-SENTINEL-GATE`
  # o `SAIKIT-REVIEW-NOTICE` despues del heal daria verde con o sin la costura.
  # El caso que mira los marcadores vive en la bateria de quality-kit, sobre
  # fixtures que no los traen.
  [ "$rc" -eq 0 ] || malo "el heal salio $rc; debe salir 0 siempre (no puede tumbar un arranque)"
  [ "$antes" = "$despues" ] || malo "el heal REESCRIBIO nuestro hook: la costura no esta aplicada"
  printf '%s' "$out" | grep -qi 'saltado' \
    || malo "el heal no declara que salteo el archivo; el salto tiene que ser visible: $out"
fi

if [ "$fail" -ne 0 ]; then
  echo "test_quality_kit_skip: FAIL" >&2
  exit 1
fi
echo "test_quality_kit_skip: OK"
