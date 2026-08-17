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
  # Here-string y no pipe: el `while` de un pipeline corre en SUBSHELL, asi que
  # el `fail=1` de `malo` se perderia y haria falta re-asignarlo afuera. Funciona
  # igual, pero es una trampa para la proxima edicion.
  while IFS= read -r l; do malo "$l"; done <<< "$malos_json"
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
  while IFS= read -r l; do malo "$l"; done <<< "$malos_jsonl"
fi

# Parsear no alcanza: un fixture puede ser JSON VALIDO y aun asi describir algo
# que el host jamas emite. Medido (revision de la Task 1.5): al escapar
# `C:\dev\demo\notas.txt` quedo `C:\\dev\\demo\notas.txt` — el `\d` se doblo
# bien, pero `\n` YA era un escape valido, asi que sobrevivio y el valor
# decodifica a una ruta con un SALTO DE LINEA adentro. Parseable, y falso.
#
# Este es el assert que ese error pedia: en los campos que son RUTAS no puede
# haber caracteres de control. Se limita a esas claves a proposito — un `\n` en
# un campo de texto (el contenido de un mensaje, por ejemplo) es legitimo.
caso "ningun campo de ruta decodifica a un caracter de control"
rutas_malas="$("$python_bin" - "$fixtures" <<'PY'
import json, pathlib, sys

CLAVES_RUTA = {"file_path", "filePath", "cwd", "transcript_path", "path",
               "notebook_path", "project_root"}
CONTROL = set(chr(c) for c in range(0x20)) | {chr(0x7f)}

def revisar(nodo, origen, salida):
    if isinstance(nodo, dict):
        for k, v in nodo.items():
            if k in CLAVES_RUTA and isinstance(v, str):
                malos = sorted({repr(c) for c in v if c in CONTROL})
                if malos:
                    salida.append(f"{origen}: {k}={v!r} trae {', '.join(malos)}")
            revisar(v, origen, salida)
    elif isinstance(nodo, list):
        for v in nodo:
            revisar(v, origen, salida)

salida = []
raiz = pathlib.Path(sys.argv[1])
for p in sorted(raiz.rglob("*.json")):
    try:
        revisar(json.loads(p.read_text(encoding="utf-8")), p, salida)
    except Exception:
        continue  # su invalidez ya la reporta el caso de arriba
for p in sorted(raiz.rglob("*.jsonl")):
    for n, linea in enumerate(p.read_text(encoding="utf-8").splitlines(), 1):
        if not linea.strip():
            continue
        try:
            revisar(json.loads(linea), f"{p}:{n}", salida)
        except Exception:
            continue
print("\n".join(salida))
PY
)"
if [ -n "$rutas_malas" ]; then
  while IFS= read -r l; do malo "$l"; done <<< "$rutas_malas"
fi

# Task 11.9 — la forma del Stop de zcode esta MEDIDA (11.6), asi que se pinnea.
#
# Por que hace falta un test y no alcanza con la linea base dorada: se midio
# (11.9) que alinear estos fixtures NO mueve ningun veredicto — `--check` sigue
# en verde con los 45 escenarios. Eso es bueno para el cambio y malo como
# candado: la baseline graba CONDUCTA, no payloads, asi que alguien podria
# revertir la forma y la capa dorada no se enteraria. Este caso es el guardia
# que falta.
#
# Las claves salen de docs/task-11.6-captura.md (captura real, 2026-08-17), no
# de la generalizacion de la 5.1 — que para este evento resulto FALSA:
# `lastAssistantMessage` NO existe. Se exige su ausencia a proposito: es lo que
# mantiene ciego al escenario 46-zcode-ambos-canales-ciegos, cuya rama de la
# 11.4 dispara solo si el gate no ve ningun canal de texto.
caso "los *.stop.zcode.json llevan la forma medida del Stop de zcode (11.6)"
forma_mala="$("$python_bin" - "$fixtures" <<'PY'
import json, pathlib, sys

# Medidas en la captura real de la 11.6. Las de texto van aparte porque el
# escenario 46 las omite a proposito (modela un Stop sin canal de texto).
BASE = {"cwd", "hookEventName", "hook_event_name", "mode", "permission_mode",
        "sessionId", "session_id", "stopHookActive", "stop_hook_active",
        "timestamp", "toolCallCount", "traceId", "transcriptPath",
        "transcript_path", "turnId"}
TEXTO = {"last_assistant_message", "responseText", "responsePreview"}
# zcode NO manda estas. Las dos ultimas son de la forma de Claude (1.4) y se
# habian colado por copia al reconstruir los fixtures en la Phase 5.
PROHIBIDAS = {"lastAssistantMessage", "background_tasks", "session_crons"}

salida = []
raiz = pathlib.Path(sys.argv[1])
vistos = 0
for p in sorted(raiz.rglob("*.stop.zcode.json")):
    try:
        d = json.loads(p.read_text(encoding="utf-8"))
    except Exception:
        continue  # su invalidez ya la reporta el primer caso
    vistos += 1
    claves = set(d)
    faltan = BASE - claves
    if faltan:
        salida.append(f"{p}: faltan claves medidas: {', '.join(sorted(faltan))}")
    sobran = PROHIBIDAS & claves
    if sobran:
        salida.append(f"{p}: trae claves que zcode NO manda: {', '.join(sorted(sobran))}")
    # zcode manda el trio de texto junto: si esta el canal que el gate lee,
    # tienen que estar sus dos companeros medidos.
    if "last_assistant_message" in claves and not TEXTO <= claves:
        salida.append(f"{p}: trae last_assistant_message sin {', '.join(sorted(TEXTO - claves))}")
if vistos < 10:
    salida.append(f"esperaba los ~12 stops de zcode, encontre {vistos}")
print("\n".join(salida))
PY
)"
if [ -n "$forma_mala" ]; then
  while IFS= read -r l; do malo "$l"; done <<< "$forma_mala"
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
