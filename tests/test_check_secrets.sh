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
  SAIKIT_GITLEAKS="$gl" bash "$tool" "$tmp/trampa.txt" >/dev/null 2>&1
  [ $? -eq 1 ] || malo "gitleaks teniendo binario no detecto la trampa"
else
  printf '    skip: sin binario gitleaks en esta maquina (el CI lo ejerce con la action)\n'
fi

# --- fallback forzado: PATH sin gitleaks ----------------------------------
caso "fallback sin gitleaks: las tres trampas se detectan"
for t in trampa.txt trampa_url.txt trampa_par.txt; do
  PATH="/usr/bin" SAIKIT_GITLEAKS= bash "$tool" "$tmp/$t" >/dev/null 2>&1
  [ $? -eq 1 ] || malo "el fallback dejo pasar $t"
done

caso "fallback sin gitleaks: el archivo limpio pasa"
PATH="/usr/bin" SAIKIT_GITLEAKS= bash "$tool" "$tmp/limpio.sh" >/dev/null 2>&1
[ $? -eq 0 ] || malo "el fallback bloqueo un archivo limpio"

caso "fallback: el comentario documental user:pass no triggerea"
PATH="/usr/bin" SAIKIT_GITLEAKS= bash "$tool" "$tmp/doc_comentario.txt" >/dev/null 2>&1
[ $? -eq 0 ] || malo "el fallback acuso el ejemplo documental ://user:pass@ (umbral {5,} roto)"

caso "fallback: los falsos declarados del repo no triggerean"
for f in "tests/lib/gate_cases.sh" "docs/task-3.5-plan.md" "Plans.md" "hooks/summonaikit-harness.sh"; do
  [ -f "$repo/$f" ] || continue
  PATH="/usr/bin" SAIKIT_GITLEAKS= bash "$tool" "$repo/$f" >/dev/null 2>&1
  [ $? -eq 0 ] || malo "el fallback acuso como secreto el falso declarado: $f"
done

caso "el reporte no imprime el valor del secreto"
out="$(PATH="/usr/bin" SAIKIT_GITLEAKS= bash "$tool" "$tmp/trampa.txt" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || malo "la trampa del reporte no dio exit 1 (rc=$rc)"
case "$out" in
  *ghp_ABCDEF*) malo "el reporte filtro el valor trampa completo" ;;
esac

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
