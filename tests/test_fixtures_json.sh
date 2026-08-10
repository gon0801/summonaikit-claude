#!/usr/bin/env bash
# Task 1.5 — los fixtures tienen que ser JSON de verdad.
#
# Por que existe este test. La Task 1.4 declaro haber corregido que "los 54
# fixtures no eran JSON valido", y quedaron 5 sin corregir: los 4 del escenario
# 16 y una linea del transcript del 14, todos por `"cwd": "C:\dev\demo"` — `\d`
# no es un escape valido. Nadie lo noto porque el hook de hoy lee el payload con
# `sed` greedy y lo trata como TEXTO OPACO: un fixture roto pasa igual.
#
# Eso deja de ser cierto en la Phase 3. Las Tasks 3.1 y 3.2 reemplazan ese
# parseo por un parser JSON real —es el arreglo de A1 y A2— y ahi los escenarios
# que sostienen justamente A2 y A9 dejan de parsear. Este test es el guardia que
# lo habria atrapado, y el que impide que vuelva a pasar.
#
# Core Rule 4: solo lectura sobre el arbol del repo.
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
fixtures="$repo/tests/fixtures"

fail=0
caso() { printf '  caso: %s\n' "$1"; }
malo() { printf '    FAIL: %s\n' "$1" >&2; fail=1; }

python_bin=''
for c in python3 python py; do
  if command -v "$c" >/dev/null 2>&1; then python_bin="$c"; break; fi
done
if [ -z "$python_bin" ]; then
  # Core Rule 2: sin interprete no se pudo mirar. No se afirma que esten bien.
  echo "  SKIP: no hay python para parsear los fixtures."
  echo "test_fixtures_json: OK (skip declarado)"
  exit 0
fi

[ -d "$fixtures" ] || { echo "test_fixtures_json: FAIL (no hay $fixtures)" >&2; exit 1; }

caso "todo *.json de fixtures parsea con un parser JSON real"
malos_json="$("$python_bin" - "$fixtures" <<'PY'
import json, pathlib, sys
raiz = pathlib.Path(sys.argv[1])
for p in sorted(raiz.rglob("*.json")):
    try:
        json.loads(p.read_text(encoding="utf-8"))
    except Exception as e:
        print(f"{p}: {e}")
PY
)"
if [ -n "$malos_json" ]; then
  printf '%s\n' "$malos_json" | while IFS= read -r l; do malo "$l"; done
  fail=1
fi

caso "todo *.jsonl de fixtures parsea linea por linea"
malos_jsonl="$("$python_bin" - "$fixtures" <<'PY'
import json, pathlib, sys
raiz = pathlib.Path(sys.argv[1])
for p in sorted(raiz.rglob("*.jsonl")):
    for n, linea in enumerate(p.read_text(encoding="utf-8").splitlines(), 1):
        if not linea.strip():
            continue
        try:
            json.loads(linea)
        except Exception as e:
            print(f"{p}:{n}: {e}")
PY
)"
if [ -n "$malos_jsonl" ]; then
  printf '%s\n' "$malos_jsonl" | while IFS= read -r l; do malo "$l"; done
  fail=1
fi

# Sin esto, borrar el arbol de fixtures dejaria el test en verde con cobertura
# cero: "0 archivos, 0 malos" no es lo mismo que "todos validos".
caso "hay fixtures que revisar (un arbol vacio no pasa como verde)"
n_json="$(find "$fixtures" -name '*.json' | wc -l | tr -d ' ')"
n_jsonl="$(find "$fixtures" -name '*.jsonl' | wc -l | tr -d ' ')"
[ "$n_json" -ge 40 ] || malo "esperaba decenas de *.json, encontre $n_json"
[ "$n_jsonl" -ge 10 ] || malo "esperaba varios *.jsonl, encontre $n_jsonl"

if [ "$fail" -ne 0 ]; then
  echo "test_fixtures_json: FAIL" >&2
  exit 1
fi
echo "test_fixtures_json: OK ($n_json json, $n_jsonl jsonl)"
