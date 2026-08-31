#!/usr/bin/env bash
# skills/saikit-verificar-app/verificar.sh
# Genera `verify/` en el repo de un usuario y reporta el estado/antiguedad del
# mapa. Es la parte mecanica de la skill `saikit-verificar-app` (D11 / Task 17.1):
# - `generar <repo>`: escribe `verify/` con LEEME.md (sello fecha·sha), Launch,
#   Doctor, Drive, Evidence y Cleanup. Si el repo YA tiene un framework de test
#   acreditable, escribe el Drive (e2e de superficie) y el comando que lo corre;
#   si NO, propone un framework y deja el Drive "manual, pendiente" (verify_app:
#   n/a) sin instalar nada.
# - `estado <repo>`: imprime `unknown` (sin sello) | `al_dia` | `desactualizado`
#   | `viejo` | `sin_mapa`. Un mapa sin sello es SIEMPRE `unknown`, jamas "al dia".
#
# No instala frameworks, no corre el Drive (eso es del turno vivo), no usa node
# ni python: solo bash + sed/grep/git/date. Lee TEST_RUNNER_RE de la fuente del
# hook (misma convencion que la suite: SAIKIT_HOOK_VIVO, sino el hook del perfil)
# para no inventar un comando de Drive que el hook despues no acreditaria.
set -u

die() { printf 'FALLO: %s\n' "$*" >&2; exit 2; }

# --- hook fuente ------------------------------------------------ convencion de la suite
resolver_hook() {
  printf '%s' "${SAIKIT_HOOK_VIVO:-$HOME/.claude/hooks/summonaikit-harness.sh}"
}

leer_test_runner_re() {
  local hook
  hook="$(resolver_hook)"
  [ -r "$hook" ] || return 0
  sed -n "s/^TEST_RUNNER_RE='//p" "$hook" 2>/dev/null | sed "s/'$//" | head -n 1
}

# true si el comando lo acredita TEST_RUNNER_RE (leido del hook, con grep -o)
comando_acredita() {
  local cmd="$1" re
  re="$(leer_test_runner_re)"
  [ -n "$re" ] || return 1
  printf '%s' "$cmd" | grep -Eoq "$re" 2>/dev/null
}

# --- utilidades ---------------------------------------------------------------
sha_actual() { git -C "$1" rev-parse HEAD 2>/dev/null || true; }

# Detecta el framework de test que el repo YA tiene y devuelve el comando de
# Drive acreditable (incluye `verify/`). Vacio => no hay Drive automatizable.
drive_para_repo() {
  local repo="$1" cmd=""
  if [ -f "$repo/package.json" ]; then
    # node: `node --test` NO acredita suelto; se envuelve como `npm test -- verify/`
    if grep -Eq '"[^"]*node[[:space:]]+--test[^"]*"' "$repo/package.json" 2>/dev/null \
       || grep -Eq '"test"[[:space:]]*:[[:space:]]*"[^"]*"' "$repo/package.json" 2>/dev/null; then
      cmd="npm test -- verify/"
    fi
  elif [ -f "$repo/pyproject.toml" ] || [ -f "$repo/requirements.txt" ] || [ -f "$repo/pytest.ini" ]; then
    if grep -qiE 'pytest' "$repo/pyproject.toml" "$repo/requirements.txt" "$repo/pytest.ini" 2>/dev/null; then
      cmd="pytest verify/"
    fi
  fi
  if [ -n "$cmd" ] && comando_acredita "$cmd"; then
    printf '%s' "$cmd"
  fi
}

# Propone el framework mas liviano que la plataforma ya soporta (capability-first),
# con version pinneada; NO instala. Lo imprime para que el agente se lo pida al
# usuario (D11: sin si explicito no se instala).
proponer_framework() {
  local repo="$1"
  if find "$repo" -name '*.py' -not -path '*/verify/*' -print -quit 2>/dev/null | grep -q .; then
    printf 'pytest==8.3.5 (pinneado; solo lo instalo si me das tu si)'
  elif find "$repo" \( -name '*.js' -o -name '*.ts' -o -name '*.tsx' \) -not -path '*/verify/*' -print -quit 2>/dev/null | grep -q .; then
    printf 'npm test (node --test ya viene con node; no hay nada que instalar)'
  else
    printf 'pytest==8.3.5 (pinneado; solo lo instalo si me das tu si)'
  fi
}

# --- generar verify/ ----------------------------------------------------------
generar_verify() {
  local repo="$1"
  [ -d "$repo" ] || die "no existe el repo: $repo"
  if [ -f "$repo/verify/LEEME.md" ]; then
    printf 'AVISO: verify/LEEME.md ya existe; no se regraba (la skill corre UNA vez).\n' >&2
    return 2
  fi
  local cmd fecha sha
  cmd="$(drive_para_repo "$repo")"
  fecha="$(date +%F)"
  sha="$(sha_actual "$repo")"
  [ -n "$sha" ] || { printf 'AVISO: sin commit (git) el sello no se puede confirmar; no se genera verify/.\n' >&2; return 2; }
  mkdir -p "$repo/verify" || die "no pudo crear verify/"

  # Drive: archivo de test e2e de superficie, solo si el comando acredita.
  local drive_file=""
  if [ -n "$cmd" ]; then
    case "$cmd" in
      npm*) drive_file="drive.test.js" ;;
      pytest*) drive_file="test_drive.py" ;;
    esac
    if [ "$drive_file" = "drive.test.js" ]; then
      cat > "$repo/verify/$drive_file" <<'EOF'
// Drive e2e de superficie de usuario: la app como la ve el usuario, NO sus
// internos. Se corre con el COMANDO_DRIVE del Drive.md. Reutiliza el framework
// de test que el repo YA tiene (node --test) y lo apunta SOLO a `verify/`; NO es
// la suite unitaria del repo.
//
// COMPLETAR en el turno (el agente lee la app y agrega las funciones del mapa):
//   - _ENTRADA_: como se lanza la app por su superficie (p.ej. "app.js").
//   - Los test(...) de "crear X", "ver la lista", etc. con su salida esperada.
// Por ahora solo comprueba que la app arranca y produce salida (la primera
// superficie: "entrar").
const { test } = require('node:test');
const assert = require('node:assert');
const { execFileSync } = require('node:child_process');
const path = require('node:path');
const appRoot = path.join(__dirname, '..');
const entrada = process.env.APP_ENTRADA || '_ENTRADA_';
test('la app arranca y responde', () => {
  const out = execFileSync('node', [entrada], { cwd: appRoot, encoding: 'utf8' });
  assert.ok(out && out.length > 0, 'la app no produjo salida al arrancar');
});
EOF
    else
      cat > "$repo/verify/$drive_file" <<'EOF'
# Drive e2e de superficie de usuario: la app como la ve el usuario, NO sus
# internos. Se corre con el COMANDO_DRIVE del Drive.md. Reutiliza el framework
# de test que el repo YA tiene (pytest) y lo apunta SOLO a `verify/`; NO es la
# suite unitaria del repo.
#
# COMPLETAR en el turno (el agente lee la app y agrega las funciones del mapa):
#   - _ENTRADA_: como se lanza la app por su superficie (p.ej. "app.py").
#   - Los test_* de "crear X", "ver la lista", etc. con su salida esperada.
# Por ahora solo comprueba que la app arranca y produce salida (la primera
# superficie: "entrar").
import os
import subprocess
import sys

app_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
entrada = os.environ.get('APP_ENTRADA', '_ENTRADA_')

def test_la_app_arranca_y_responde():
    out = subprocess.run([sys.executable, entrada], cwd=app_root,
                         capture_output=True, text=True, check=True).stdout
    assert out.strip(), 'la app no produjo salida al arrancar'
EOF
    fi
  fi

  local card="manual, pendiente"
  [ -n "$cmd" ] && card="drive"

  cat > "$repo/verify/LEEME.md" <<EOF
---
generado: $fecha · $sha
verify_app: $([ "$card" = drive ] && echo drive || echo n/a)
---
# Mapa de funciones de la app

Describe aca las 3 a 5 funciones principales de la app, EN ESPANOL, para alguien
que no lee codigo (p.ej. "entrar", "crear X", "ver la lista", "cerrar sesion").

1. _PENDIENTE_ (COMPLETAR en el turno: leer la app)
2. _PENDIENTE_
3. _PENDIENTE_

> Este mapa se sello el dia que se genero (fecha) y con el sha del commit. Si la
> app cambia, el sello queda viejo y el verifier lo reporta. No confies en un
> mapa que no coincide con el commit actual.
EOF

  cat > "$repo/verify/Launch.md" <<'EOF'
# Launch — como arranca la app

Describe en palabras simples como levantar la app (comando, direccion, o pasos).
_COMPLETAR_ (p.ej. `npm run dev`, `python app.py`).
EOF

  cat > "$repo/verify/Doctor.md" <<'EOF'
# Doctor — como saber que el entorno esta sano

Describe como comprobar que la maquina tiene lo necesario (dependencias,
variables de entorno, base de datos). _COMPLETAR_.
EOF

  cat > "$repo/verify/Drive.md" <<EOF
# Drive — como probar la app como usuario

El Drive corre la app por su superficie de usuario (e2e) bajo \`verify/\`, en el
framework que el repo YA tiene. NO es la suite unitaria del repo.

$([ -n "$cmd" ] && printf 'COMANDO_DRIVE: %s' "$cmd" || printf 'ESTADO_DRIVE: manual, pendiente')
$([ -n "$cmd" ] && printf 'ESTADO_DRIVE: drive' || printf '')
EOF

  cat > "$repo/verify/Evidence.txt" <<'EOF'
Registro de la ultima corrida del Drive. Pega aca la salida real del comando.
EOF

  cat > "$repo/verify/Cleanup.md" <<'EOF'
# Cleanup — como dejar todo como estaba

Describe que se hace al terminar (procesos, datos creados, archivos). _COMPLETAR_.
EOF

  if [ -n "$cmd" ]; then
    printf 'GENERADO: verify/ con Drive acreditable (%s)\n' "$cmd"
  else
    printf 'PROPONGO: %s\n' "$(proponer_framework "$repo")"
    printf 'GENERADO: verify/ (Drive manual, pendiente; verify_app: n/a)\n'
  fi
  return 0
}

# --- estado del mapa ----------------------------------------------------------
estado_mapa() {
  local repo="$1" leeme="$1/verify/LEEME.md"
  [ -f "$leeme" ] || { printf 'sin_mapa'; return 0; }
  local sello fecha sha actual dias
  sello="$(sed -n 's/^generado:[[:space:]]*//p' "$leeme" | head -n 1)"
  if [ -z "$sello" ]; then printf 'unknown'; return 0; fi
  fecha="${sello%%·*}"
  sha="${sello##*·}"
  fecha="$(printf '%s' "$fecha" | sed 's/[[:space:]]//g')"
  sha="$(printf '%s' "$sha" | sed 's/[[:space:]]//g')"
  [ -n "$sha" ] || { printf 'unknown'; return 0; }
  actual="$(sha_actual "$repo")"
  [ -n "$actual" ] || { printf 'unknown'; return 0; }
  if [ "$sha" != "$actual" ]; then printf 'desactualizado'; return 0; fi
  if [ -n "$fecha" ] && date -d "$fecha" >/dev/null 2>&1; then
    dias=$(( ( $(date +%s) - $(date -d "$fecha" +%s) ) / 86400 ))
    if [ "$dias" -gt 30 ]; then printf 'viejo'; return 0; fi
  fi
  printf 'al_dia'
}

main() {
  [ "$#" -ge 2 ] || { printf 'uso: verificar.sh generar <repo> | estado <repo>\n' >&2; exit 2; }
  case "$1" in
    generar) generar_verify "$2" ;;
    estado)  estado_mapa "$2" ;;
    *) printf 'accion desconocida: %s\n' "$1" >&2; exit 2 ;;
  esac
}

main "$@"
