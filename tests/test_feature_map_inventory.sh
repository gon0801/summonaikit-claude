#!/usr/bin/env bash
# tests/test_feature_map_inventory.sh — Task 19.1: catálogo, discovery y lint.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
. "$here/lib/sandbox.sh"; sandbox_init
fail=0
caso() { printf '  caso: %s\n' "$1"; }
malo() { printf '    FAIL: %s\n' "$1" >&2; fail=1; }

LINT="$repo/.cursor/skills/verify-summonaikit/scripts/lint-feature-map.py"
SKILL="$repo/.cursor/skills/verify-summonaikit"
CTRL="$SKILL/scripts/control-summonaikit"

run_lint() {
  python3 "$LINT" --repo "$1" --skill "$2" "${@:3}"
}

# --- verde sobre el checkout real ---
caso "mapa real => 0"
out="$(run_lint "$repo" "$SKILL" 2>&1)" || malo "lint real fallo: $out"
printf '%s\n' "$out" | grep -q 'feature-map: OK' || malo "sin OK: $out"

caso "controlador sin extension parsea (bash -n)"
bash -n "$CTRL" || malo "bash -n fallo en control-summonaikit"

caso "helper interno clasificado no exige ejecutor"
python3 - <<PY || malo "helper no clasificado como internal"
import json
from pathlib import Path
c=json.loads(Path("$SKILL/features/catalog.json").read_text())
h=c["helpers"]["scripts/lint-feature-map.py"]
assert h["kind"]=="internal"
PY

# --- fixture skill mínima sobre sandbox ---
mk_min_skill() {  # $1=dir
  local d="$1"
  mkdir -p "$d/features" "$d/scripts"
  cp "$CTRL" "$d/scripts/control-summonaikit"
  chmod +x "$d/scripts/control-summonaikit"
  cp "$LINT" "$d/scripts/lint-feature-map.py"
  if [ -d "$SKILL/scripts/lib" ]; then
    mkdir -p "$d/scripts/lib"
    for f in "$SKILL/scripts/lib"/*; do
      [ -f "$f" ] || continue
      case "$f" in *.pyc) continue ;; esac
      cp "$f" "$d/scripts/lib/"
    done
  fi
  cp "$SKILL/features/README.md" "$d/features/README.md"
  # copy four cards + descriptors + catalog from real as base
  for f in install-guardian gate-turn audit-ledger check-deploy-log saikit-merge saikit-postmerge; do
    cp "$SKILL/features/$f.md" "$d/features/$f.md"
    cp "$SKILL/features/$f.json" "$d/features/$f.json"
  done
  cp "$SKILL/features/catalog.json" "$d/features/catalog.json"
  if [ -d "$SKILL/schemas" ]; then
    mkdir -p "$d/schemas"
    cp "$SKILL/schemas/"*.json "$d/schemas/" 2>/dev/null || true
  fi
  if [ -d "$SKILL/scripts/drivers" ]; then
    mkdir -p "$d/scripts/drivers"
    cp "$SKILL/scripts/drivers/"*.sh "$d/scripts/drivers/" 2>/dev/null || true
  fi
}

mk_min_repo() {  # $1=dir — árbol descubrible mínimo alineado al catálogo
  local d="$1"
  mkdir -p "$d/tools/lib" "$d/hooks" "$d/hosts/dsh/spy" "$d/hosts/dsh/test" \
    "$d/agents" "$d/recetas/pendientes" \
    "$d/skills/saikit-setup-autopilot" \
    "$d/skills/saikit-verificar-app" \
    "$d/skills/sencillo"
  # create every path the real catalog classifies/excludes
  python3 - <<PY
import json
from pathlib import Path
repo=Path("$d")
cat=json.loads(Path("$SKILL/features/catalog.json").read_text())
for path in list(cat["surfaces"])+list(cat["exclusions"]):
    p=repo/path
    p.parent.mkdir(parents=True, exist_ok=True)
    if not p.exists():
        p.write_text("# fixture\n", encoding="utf-8")
PY
}

caso "superficie nueva sin clasificar => 1"
R="$SANDBOX/uncat"; S="$SANDBOX/uncat-skill"
mkdir -p "$R" "$S"; mk_min_repo "$R"; mk_min_skill "$S"
printf '#!/bin/sh\n' > "$R/tools/nuevo-publico.sh"
chmod +x "$R/tools/nuevo-publico.sh"
run_lint "$R" "$S" >/dev/null 2>&1 && malo "acepto superficie sin clasificar" \
  || true
out="$(run_lint "$R" "$S" 2>&1 || true)"
printf '%s' "$out" | grep -q 'sin clasificar' || malo "motivo sin 'sin clasificar': $out"

caso "ficha sin ejecutor (descriptor activo sin executor) => 1"
R="$SANDBOX/noexec"; S="$SANDBOX/noexec-skill"
mkdir -p "$R" "$S"; mk_min_repo "$R"; mk_min_skill "$S"
python3 - <<PY
import json
from pathlib import Path
p=Path("$S/features/gate-turn.json")
d=json.loads(p.read_text())
del d["executor"]
p.write_text(json.dumps(d), encoding="utf-8")
PY
run_lint "$R" "$S" >/dev/null 2>&1 && malo "acepto ficha activa sin ejecutor"
out="$(run_lint "$R" "$S" 2>&1 || true)"
printf '%s' "$out" | grep -qi 'sin ejecutor' || malo "motivo sin 'sin ejecutor': $out"

caso "ejecutor huerfano en scripts/drivers => 1"
R="$SANDBOX/orphan"; S="$SANDBOX/orphan-skill"
mkdir -p "$R" "$S"; mk_min_repo "$R"; mk_min_skill "$S"
mkdir -p "$S/scripts/drivers"
printf '#!/bin/bash\n' > "$S/scripts/drivers/fantasma.sh"
run_lint "$R" "$S" >/dev/null 2>&1 && malo "acepto ejecutor huerfano"
out="$(run_lint "$R" "$S" 2>&1 || true)"
printf '%s' "$out" | grep -q 'huerfano\|huérfano' || malo "motivo sin huerfano: $out"

caso "ID duplicado entre descriptores => 1"
R="$SANDBOX/dup"; S="$SANDBOX/dup-skill"
mkdir -p "$R" "$S"; mk_min_repo "$R"; mk_min_skill "$S"
python3 - <<PY
import json
from pathlib import Path
# two active descriptors claim the same id
d=json.loads(Path("$S/features/gate-turn.json").read_text())
d["id"]="install-guardian"
Path("$S/features/gate-turn.json").write_text(json.dumps(d), encoding="utf-8")
PY
run_lint "$R" "$S" >/dev/null 2>&1 && malo "acepto ID duplicado entre descriptores"
out="$(run_lint "$R" "$S" 2>&1 || true)"
printf '%s' "$out" | grep -qi 'duplicado' || malo "sin motivo de id duplicado: $out"

caso "fuente de skill no permitida (artifacts/pyc) => 1"
R="$SANDBOX/allow"; S="$SANDBOX/allow-skill"
mkdir -p "$R" "$S"; mk_min_repo "$R"; mk_min_skill "$S"
mkdir -p "$S/artifacts"
printf 'leak\n' > "$S/artifacts/nope.txt"
run_lint "$R" "$S" >/dev/null 2>&1 && malo "acepto artifact versionado"
out="$(run_lint "$R" "$S" 2>&1 || true)"
printf '%s' "$out" | grep -q 'no permitida' || malo "sin motivo allowlist: $out"

caso "scripts/lib no inventariado en helpers => 1"
R="$SANDBOX/libjunk"; S="$SANDBOX/libjunk-skill"
mkdir -p "$R" "$S"; mk_min_repo "$R"; mk_min_skill "$S"
mkdir -p "$S/scripts/lib"
printf '#!/bin/sh\necho junk\n' > "$S/scripts/lib/junk.sh"
run_lint "$R" "$S" >/dev/null 2>&1 && malo "acepto scripts/lib basura"
out="$(run_lint "$R" "$S" 2>&1 || true)"
printf '%s' "$out" | grep -q 'no permitida' || malo "sin motivo lib junk: $out"

caso "features JSON huerfano (fuera del catalogo) => 1"
R="$SANDBOX/fant"; S="$SANDBOX/fant-skill"
mkdir -p "$R" "$S"; mk_min_repo "$R"; mk_min_skill "$S"
printf '{"schema_version":1,"id":"fantasma"}\n' > "$S/features/fantasma.json"
run_lint "$R" "$S" >/dev/null 2>&1 && malo "acepto JSON huerfano"
out="$(run_lint "$R" "$S" 2>&1 || true)"
printf '%s' "$out" | grep -q 'no permitida' || malo "sin motivo JSON huerfano: $out"

caso "legacy function inventada => 1"
R="$SANDBOX/leg"; S="$SANDBOX/leg-skill"
mkdir -p "$R" "$S"; mk_min_repo "$R"; mk_min_skill "$S"
python3 - <<PY
import json
from pathlib import Path
p=Path("$S/features/gate-turn.json")
d=json.loads(p.read_text())
d["executor"]={"kind":"legacy","command":"drive-gate-scenario","function":"cmd_no_existe"}
p.write_text(json.dumps(d), encoding="utf-8")
PY
run_lint "$R" "$S" >/dev/null 2>&1 && malo "acepto function legacy inventada"
out="$(run_lint "$R" "$S" 2>&1 || true)"
printf '%s' "$out" | grep -qi 'no existe\|legacy' || malo "sin motivo legacy: $out"

caso "H2 fuera de orden => 1"
R="$SANDBOX/h2"; S="$SANDBOX/h2-skill"
mkdir -p "$R" "$S"; mk_min_repo "$R"; mk_min_skill "$S"
python3 - <<PY
from pathlib import Path
p=Path("$S/features/audit-ledger.md")
lines=p.read_text(encoding="utf-8").splitlines(True)
out=[]
for ln in lines:
    if ln.startswith("## Sub-features"):
        out.append("## Gotchas\n")
    elif ln.startswith("## Gotchas"):
        out.append("## Sub-features\n")
    else:
        out.append(ln)
p.write_text("".join(out), encoding="utf-8")
PY
run_lint "$R" "$S" >/dev/null 2>&1 && malo "acepto H2 fuera de orden"
out="$(run_lint "$R" "$S" 2>&1 || true)"
printf '%s' "$out" | grep -q 'H2' || malo "sin motivo H2: $out"

caso "triple incompleto (sin Case lines) => 1"
R="$SANDBOX/trip"; S="$SANDBOX/trip-skill"
mkdir -p "$R" "$S"; mk_min_repo "$R"; mk_min_skill "$S"
python3 - <<PY
from pathlib import Path
import re
p=Path("$S/features/check-deploy-log.md")
text=p.read_text(encoding="utf-8")
text=re.sub(r"(?m)^- Case \`.*\n", "", text)
p.write_text(text, encoding="utf-8")
PY
run_lint "$R" "$S" >/dev/null 2>&1 && malo "acepto ficha sin triples"
out="$(run_lint "$R" "$S" 2>&1 || true)"
printf '%s' "$out" | grep -qi 'triple\|Case' || malo "sin motivo triple: $out"

caso "aserción sin caso (required_assertions vacías) => 1"
R="$SANDBOX/asrt"; S="$SANDBOX/asrt-skill"
mkdir -p "$R" "$S"; mk_min_repo "$R"; mk_min_skill "$S"
python3 - <<PY
import json
from pathlib import Path
p=Path("$S/features/audit-ledger.json")
d=json.loads(p.read_text())
d["cases"][0]["required_assertions"]=[]
p.write_text(json.dumps(d), encoding="utf-8")
PY
run_lint "$R" "$S" >/dev/null 2>&1 && malo "acepto asercion sin caso"
out="$(run_lint "$R" "$S" 2>&1 || true)"
printf '%s' "$out" | grep -q 'required_assertions' || malo "sin motivo assertions: $out"

caso "exclusion sin razon => 1"
R="$SANDBOX/ex"; S="$SANDBOX/ex-skill"
mkdir -p "$R" "$S"; mk_min_repo "$R"; mk_min_skill "$S"
python3 - <<PY
import json
from pathlib import Path
p=Path("$S/features/catalog.json")
c=json.loads(p.read_text())
c["exclusions"]["tools/probe-zcode-output.sh"]={"reason":""}
p.write_text(json.dumps(c), encoding="utf-8")
PY
run_lint "$R" "$S" >/dev/null 2>&1 && malo "acepto exclusion sin razon"
out="$(run_lint "$R" "$S" 2>&1 || true)"
printf '%s' "$out" | grep -q 'exclusión sin razón\|exclusion sin' || malo "sin motivo exclusion: $out"

caso "JSON mal formado => 1"
R="$SANDBOX/badj"; S="$SANDBOX/badj-skill"
mkdir -p "$R" "$S"; mk_min_repo "$R"; mk_min_skill "$S"
printf '{not json' > "$S/features/catalog.json"
run_lint "$R" "$S" >/dev/null 2>&1 && malo "acepto JSON mal formado"
out="$(run_lint "$R" "$S" 2>&1 || true)"
printf '%s' "$out" | grep -qi 'mal formado\|JSON' || malo "sin motivo JSON: $out"

# --- mutaciones discriminantes ---
caso "mutacion omit_discovery: el caso sin clasificar deja de atrapar"
R="$SANDBOX/mut-disc"; S="$SANDBOX/mut-disc-skill"
mkdir -p "$R" "$S"; mk_min_repo "$R"; mk_min_skill "$S"
printf '#!/bin/sh\n' > "$R/tools/sneaky.sh"
# without mutation must fail
run_lint "$R" "$S" >/dev/null 2>&1 && malo "baseline sin clasificar debio fallar"
# with omit_discovery the unclassified file is ignored → incorrectly OK
if run_lint "$R" "$S" --mutate omit_discovery >/dev/null 2>&1; then
  :
else
  malo "mutacion omit_discovery debio pasar en falso (protege discovery)"
fi

caso "mutacion accept_orphan: huerfano deja de atrapar"
R="$SANDBOX/mut-orp"; S="$SANDBOX/mut-orp-skill"
mkdir -p "$R" "$S"; mk_min_repo "$R"; mk_min_skill "$S"
mkdir -p "$S/scripts/drivers"
printf '#!/bin/bash\n' > "$S/scripts/drivers/x.sh"
run_lint "$R" "$S" >/dev/null 2>&1 && malo "baseline huerfano debio fallar"
run_lint "$R" "$S" --mutate accept_orphan >/dev/null 2>&1 \
  || malo "mutacion accept_orphan debio pasar en falso"

caso "mutacion accept_orphan NO silencia legacy invalido"
R="$SANDBOX/mut-orp-leg"; S="$SANDBOX/mut-orp-leg-skill"
mkdir -p "$R" "$S"; mk_min_repo "$R"; mk_min_skill "$S"
mkdir -p "$S/scripts/drivers"
printf '#!/bin/bash\n' > "$S/scripts/drivers/x.sh"
python3 - <<PY
import json
from pathlib import Path
p=Path("$S/features/gate-turn.json")
d=json.loads(p.read_text())
d["executor"]={"kind":"legacy","command":"drive-gate-scenario","function":"cmd_no_existe"}
p.write_text(json.dumps(d), encoding="utf-8")
PY
run_lint "$R" "$S" --mutate accept_orphan >/dev/null 2>&1 \
  && malo "accept_orphan no debe ocultar legacy invalido"
out="$(run_lint "$R" "$S" --mutate accept_orphan 2>&1 || true)"
printf '%s' "$out" | grep -qi 'no existe\|legacy' || malo "sin queja legacy bajo accept_orphan: $out"

caso "mutacion skip_legacy_validate: function inventada deja de atrapar"
R="$SANDBOX/mut-leg"; S="$SANDBOX/mut-leg-skill"
mkdir -p "$R" "$S"; mk_min_repo "$R"; mk_min_skill "$S"
# Este caso cambia gate-turn a legacy: su driver copiado quedaria huerfano
# y taparia el flip de skip_legacy_validate.
rm -f "$S/scripts/drivers/gate-turn.sh"
python3 - <<PY
import json
from pathlib import Path
p=Path("$S/features/gate-turn.json")
d=json.loads(p.read_text())
d["executor"]={"kind":"legacy","command":"drive-gate-scenario","function":"cmd_no_existe"}
p.write_text(json.dumps(d), encoding="utf-8")
PY
run_lint "$R" "$S" >/dev/null 2>&1 && malo "baseline legacy debio fallar"
run_lint "$R" "$S" --mutate skip_legacy_validate >/dev/null 2>&1 \
  || malo "mutacion skip_legacy_validate debio pasar en falso"

caso "mutacion skip_h2_order: H2 roto deja de atrapar"
R="$SANDBOX/mut-h2"; S="$SANDBOX/mut-h2-skill"
mkdir -p "$R" "$S"; mk_min_repo "$R"; mk_min_skill "$S"
python3 - <<PY
from pathlib import Path
p=Path("$S/features/audit-ledger.md")
lines=p.read_text(encoding="utf-8").splitlines(True)
out=[]
for ln in lines:
    if ln.startswith("## Sub-features"):
        out.append("## Gotchas\n")
    elif ln.startswith("## Gotchas"):
        out.append("## Sub-features\n")
    else:
        out.append(ln)
p.write_text("".join(out), encoding="utf-8")
PY
run_lint "$R" "$S" >/dev/null 2>&1 && malo "baseline H2 debio fallar"
# skip_h2_order alone may still fail on case id mismatch after H2 swap? H2 swap keeps cases.
# Also filter triples - H2 error is the one we strip.
run_lint "$R" "$S" --mutate skip_h2_order >/dev/null 2>&1 \
  || malo "mutacion skip_h2_order debio pasar en falso"

caso "mutacion skip_triples: ficha sin Case deja de atrapar"
R="$SANDBOX/mut-tr"; S="$SANDBOX/mut-tr-skill"
mkdir -p "$R" "$S"; mk_min_repo "$R"; mk_min_skill "$S"
python3 - <<PY
from pathlib import Path
import re
p=Path("$S/features/check-deploy-log.md")
text=re.sub(r"(?m)^- Case \`.*\n", "", p.read_text(encoding="utf-8"))
p.write_text(text, encoding="utf-8")
PY
run_lint "$R" "$S" >/dev/null 2>&1 && malo "baseline triples debio fallar"
run_lint "$R" "$S" --mutate skip_triples >/dev/null 2>&1 \
  || malo "mutacion skip_triples debio pasar en falso"

caso "mutacion accept_bad_json: JSON roto pasa en falso"
R="$SANDBOX/mut-json"; S="$SANDBOX/mut-json-skill"
mkdir -p "$R" "$S"; mk_min_repo "$R"; mk_min_skill "$S"
printf '{bad' > "$S/features/catalog.json"
run_lint "$R" "$S" >/dev/null 2>&1 && malo "baseline JSON mal formado debio fallar"
run_lint "$R" "$S" --mutate accept_bad_json >/dev/null 2>&1 \
  || malo "mutacion accept_bad_json debio pasar en falso"

if [ "$fail" -ne 0 ]; then
  echo "FAIL: $fail aserciones" >&2
  exit 1
fi
echo "OK: test_feature_map_inventory"
exit 0
