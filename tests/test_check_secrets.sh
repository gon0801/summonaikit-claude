#!/usr/bin/env bash
# Deteccion de secretos (tools/check-secrets.sh) — item Recommended de
# Plans.md: "CI + pre-commit con deteccion de secretos en este repo".
#
# Lo que este archivo afirma, y por que:
#
#   - Una trampa OBVIA (ghp_ de 36 chars) se detecta con CUALQUIER motor que
#     este disponible — el script elige gitleaks si lo hay y si no cae al
#     grep. El caso corre con el motor que sea y tambien hay uno que FUERZA
#     el fallback (PATH sin gitleaks), para que las dos mitades queden
#     probadas aunque el operador tenga gitleaks instalado.
#   - Los falsos conocidos del repo (credenciales de PRUEBA de la Task 3.5)
#     no triggerean el fallback: tests/, docs/ y Plans.md estan excluidos de
#     ese motor a proposito y declarado en el script. Si alguien le saca la
#     exclusion, este caso se pone rojo con el archivo real del repo.
#   - El reporte NO imprime la linea con el secreto (solo archivo:linea).
#     Filtrar en la herramienta lo que viene a impedir seria el chiste del
#     dia: se comprueba que el stdout no contenga el valor trampa.
#   - Sin archivos => exit 2 (no hay nada que afirmar); solo archivos
#     borrados => exit 0 (nada que escanear).
#
# Core Rule 4: las trampas viven en un tmpdir, nunca en el arbol del repo.
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
tool="$repo/tools/check-secrets.sh"

fail=0
caso() { printf '  caso: %s\n' "$1"; }
malo() { printf '    FAIL: %s\n' "$1" >&2; fail=1; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/saikit-secrets-XXXXXX")" || exit 1
trap 'rm -rf "$tmp"' EXIT

if [ ! -f "$tool" ]; then
  echo "    FAIL: no existe $tool" >&2
  echo "test_check_secrets: FAIL" >&2
  exit 1
fi

# --- fixtures -------------------------------------------------------------
printf 'GITHUB_TOKEN=ghp_ABCDEF1234567890abcdefABCDEF1234567890\n' > "$tmp/trampa.txt"
printf 'curl -H "Authorization: Bearer sk-proj-abcdefghijklmnopqrstuvwxyz0123456789" https://api\n' > "$tmp/trampa_url.txt"
printf 'psql "postgresql://admin:sup3rs3cret4largo@host/db"\n' > "$tmp/trampa_par.txt"
printf 'echo "listo"\ncp a b\n' > "$tmp/limpio.sh"
# El comentario documental del patron ("user:pass@", "admin:pass@"): sin el
# umbral {5,} de re_url, el propio tools/check-secrets.sh se auto-acusa por
# sus comentarios (medido). Este caso ata esa decision.
printf '# vease el literal ://user:pass@ y el ejemplo postgresql://admin:pass@host/db\n' > "$tmp/doc_comentario.txt"

# Forzado del motor fallback: `PATH=/usr/bin` a secas ASUME que gitleaks no
# esta ahi (hallazgo CodeRabbit del PR #24). Se VERIFICA en vez de asumirlo;
# si existiera, los casos fallback se declaran skip — no se simula con un stub
# truene-lo-que-truene: un gitleaks presente ES motor para el script.
if [ -x /usr/bin/gitleaks ]; then
  fb_ok=0
else
  fb_ok=1
fi
fb() { PATH="/usr/bin" env -u SAIKIT_GITLEAKS bash "$tool" "$@"; }

# --- motor disponible (el que el script elija) ----------------------------
caso "trampa ghp_ detectada con el motor disponible"
bash "$tool" "$tmp/trampa.txt" >/dev/null 2>&1
[ $? -eq 1 ] || malo "la trampa ghp_ paso con el motor disponible"

caso "archivo limpio pasa con el motor disponible"
bash "$tool" "$tmp/limpio.sh" >/dev/null 2>&1
[ $? -eq 0 ] || malo "archivo limpio bloqueado con el motor disponible"

# --- motor gitleaks, SOLO si hay binario (en el CI no lo hay: skip) -------
gl="$(command -v gitleaks 2>/dev/null || true)"
[ -z "$gl" ] && [ -x /tmp/gitleaks-bin/gitleaks.exe ] && gl=/tmp/gitleaks-bin/gitleaks.exe
caso "trampa ghp_ detectada por gitleaks cuando el binario existe"
if [ -n "$gl" ]; then
  out="$(SAIKIT_GITLEAKS="$gl" bash "$tool" "$tmp/trampa.txt" 2>&1)"; rc=$?
  [ "$rc" -eq 1 ] || malo "gitleaks teniendo binario no detecto la trampa (rc=$rc)"
  case "$out" in
    *trampa.txt:1*) ;;
    *) malo "el reporte gitleaks no trae archivo:linea (hallazgo CR PR #24)" ;;
  esac
  case "$out" in
    *ghp_ABCDEF*) malo "el reporte gitleaks filtro el valor trampa" ;;
  esac
else
  printf '    skip: sin binario gitleaks en esta maquina (el CI lo ejerce en su job)\n'
fi

caso "gitleaks: 2+ archivos escanean SOLO los pasados (P1 del PR #24)"
if [ -n "$gl" ]; then
  mkdir -p "$tmp/sub"
  printf 'limpio a\n' > "$tmp/sub/a.txt"
  printf 'limpio b\n' > "$tmp/sub/b.txt"
  printf 'ghp_ABCDEF1234567890abcdefABCDEF1234567890\n' > "$tmp/sub/trampa.txt"
  # Pre-fix esto daba exit 1: con 2+ fuentes gitleaks escaneaba el DIRECTORIO
  # hermano y encontraba trampa.txt, que nunca fue pasada como argumento.
  SAIKIT_GITLEAKS="$gl" bash "$tool" "$tmp/sub/a.txt" "$tmp/sub/b.txt" >/dev/null 2>&1
  [ $? -eq 0 ] || malo "con 2+ archivos gitleaks escaneo mas que los pasados"
else
  printf '    skip: sin binario gitleaks en esta maquina\n'
fi

# --- fallback forzado: PATH=/usr/bin VERIFICADO sin gitleaks -------------
if [ "$fb_ok" -eq 1 ]; then
  caso "fallback sin gitleaks: las tres trampas se detectan"
  for t in trampa.txt trampa_url.txt trampa_par.txt; do
    fb "$tmp/$t" >/dev/null 2>&1
    [ $? -eq 1 ] || malo "el fallback dejo pasar $t"
  done

  caso "fallback sin gitleaks: el archivo limpio pasa"
  fb "$tmp/limpio.sh" >/dev/null 2>&1
  [ $? -eq 0 ] || malo "el fallback bloqueo un archivo limpio"

  caso "fallback: el comentario documental user:pass no triggerea"
  fb "$tmp/doc_comentario.txt" >/dev/null 2>&1
  [ $? -eq 0 ] || malo "el fallback acuso el ejemplo documental ://user:pass@ (umbral {5,} roto)"

  caso "fallback: los falsos declarados del repo no triggerean"
  for f in "tests/lib/gate_cases.sh" "docs/task-3.5-plan.md" "Plans.md" "hooks/summonaikit-harness.sh"; do
    [ -f "$repo/$f" ] || continue
    fb "$repo/$f" >/dev/null 2>&1
    [ $? -eq 0 ] || malo "el fallback acuso como secreto el falso declarado: $f"
  done

  caso "el reporte del fallback trae archivo:linea y no imprime el valor"
  out="$(fb "$tmp/trampa.txt" 2>&1)"; rc=$?
  [ "$rc" -eq 1 ] || malo "la trampa del reporte no dio exit 1 (rc=$rc)"
  case "$out" in
    *trampa.txt:1*) ;;
    *) malo "el reporte del fallback no trae archivo:linea" ;;
  esac
  case "$out" in
    *ghp_ABCDEF*) malo "el reporte filtro el valor trampa completo" ;;
  esac
else
  caso "fallback sin gitleaks"
  printf '    skip: hay gitleaks en /usr/bin, el fallback no se puede forzar con este PATH\n'
fi

# --- aridad ---------------------------------------------------------------
caso "sin archivos => exit 2"
bash "$tool" >/dev/null 2>&1
[ $? -eq 2 ] || malo "sin archivos no salio 2"

caso "solo archivos inexistentes => exit 0 (nada que escanear)"
bash "$tool" "$tmp/no-existe.nii" >/dev/null 2>&1
[ $? -eq 0 ] || malo "archivo inexistente no dio exit 0"

if [ "$fail" -ne 0 ]; then
  echo "test_check_secrets: FAIL" >&2
  exit 1
fi
echo "test_check_secrets: OK"
