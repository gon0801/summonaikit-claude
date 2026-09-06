#!/usr/bin/env bash
# tests/test_feature_map_autopilot.sh — 19.10: contrato autopilot via golden.
#
# DoD: sentinel exacto arma full + autopilot=1; sin el exacto no se hereda;
# parrafo pide confirmacion y no promete merge/revert solo; cada observacion
# tiene mutante rojo. El driver no cambia hook/golden para fabricar verde.
#
# Mutaciones (copia del driver en sandbox; SAIKIT_FM_DRIVER):
#   omit_sentinel omit_estado omit_parrafo omit_persistencia
#   accept_typo accept_merge_solo
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
. "$here/lib/sandbox.sh"; sandbox_init
fail=0
caso() { printf '  caso: %s\n' "$1"; }
malo() { printf '    FAIL: %s\n' "$1" >&2; fail=$((fail + 1)); }

SKILL="$repo/.cursor/skills/verify-summonaikit"
CTRL="$SKILL/scripts/control-summonaikit"
DRV="$SKILL/scripts/drivers/autopilot-contract.sh"
STATE="$SANDBOX/verify-state"
ART="$SANDBOX/verify-artifacts"
mkdir -p "$STATE" "$ART"

ctrl() {
  SAIKIT_VERIFY_STATE="$STATE" SAIKIT_VERIFY_ARTIFACTS="$ART" \
    bash "$CTRL" "$@"
}

ctrl_drv() {
  local drv="$1"; shift
  SAIKIT_FM_DRIVER="$drv" \
    SAIKIT_VERIFY_STATE="$STATE" SAIKIT_VERIFY_ARTIFACTS="$ART" \
    bash "$CTRL" "$@"
}

latest_summary() {
  local fid="$1"
  find "$ART" -path "*/*/${fid}/*/summary.json" -type f | tail -1
}

latest_steps() {
  local sum
  sum="$(latest_summary "$1")"
  [ -n "$sum" ] || return 1
  printf '%s' "$(dirname "$sum")/steps.jsonl"
}

assert_obs() {
  local fid="$1" asid="$2" pat="$3"
  local steps
  steps="$(latest_steps "$fid")" || { malo "$fid: sin steps para $asid"; return; }
  python3 - "$steps" "$asid" "$pat" <<'PY' || malo "$fid: $asid no observa [$pat]"
import json, re, sys
steps, asid, pat = sys.argv[1], sys.argv[2], sys.argv[3]
found = None
for line in open(steps, encoding="utf-8"):
    if not line.strip():
        continue
    rec = json.loads(line)
    if rec.get("type") == "assertion" and rec.get("assertion_id") == asid:
        found = rec
if found is None:
    raise SystemExit(f"falta aserción {asid}")
obs = str(found.get("observed") or "")
if found.get("result") != "PASS":
    raise SystemExit(f"{asid} result={found.get('result')} obs={obs!r}")
if not re.search(pat, obs):
    raise SystemExit(f"{asid} observed no coincide {pat!r}: {obs!r}")
PY
}

assert_missing_or_fail() {
  local fid="$1" asid="$2" signal="$3" rc_drive="$4"
  local sum steps
  sum="$(latest_summary "$fid")"
  steps="$(latest_steps "$fid")"
  python3 - "$sum" "$steps" "$asid" "$signal" "$rc_drive" <<'PY' || malo "$fid: mutante de $asid sobrevivio"
import json, re, sys
sum_p, steps_p, asid, signal, rc = sys.argv[1:6]
summary = json.loads(open(sum_p, encoding="utf-8").read()) if sum_p else {}
found = None
if steps_p:
    for line in open(steps_p, encoding="utf-8"):
        if not line.strip():
            continue
        rec = json.loads(line)
        if rec.get("type") == "assertion" and rec.get("assertion_id") == asid:
            found = rec
result = summary.get("result")
if found is None:
    if result == "PASS" or rc == "0":
        raise SystemExit(f"omitio {asid} pero drive/result siguio verde")
    raise SystemExit(0)
obs = str(found.get("observed") or "")
if found.get("result") == "PASS" and re.search(signal, obs) and result == "PASS":
    raise SystemExit(f"mutante de {asid} sobrevive: result=PASS obs={obs!r}")
PY
}

reset_art() { rm -rf "$ART"; mkdir -p "$ART"; }

copy_driver() {
  cp "$DRV" "$1"
  chmod +x "$1"
}

sed_must_change() {
  local src="$1" dest="$2" expr="$3" label="$4"
  sed "$expr" "$src" > "$dest"
  chmod +x "$dest"
  if cmp -s "$src" "$dest"; then
    malo "$label: sed no cambio el driver (patron obsoleto)"
    return 1
  fi
  bash -n "$dest" || { malo "$label: mutante no parsea"; return 1; }
  return 0
}

# ---------------------------------------------------------------------------
# Inventario: catalogo activo + descriptor + ficha
# ---------------------------------------------------------------------------
caso "catalogo activa autopilot-contract con driver y ficha"
python3 - "$SKILL" <<'PY' || malo "catalogo/descriptor autopilot-contract incompleto"
import json, sys
from pathlib import Path
skill = Path(sys.argv[1])
cat = json.loads((skill / "features/catalog.json").read_text())
meta = (cat.get("features") or {}).get("autopilot-contract") or {}
assert meta.get("status") == "active", meta
assert meta.get("card"), meta
d = json.loads((skill / "features/autopilot-contract.json").read_text())
assert d.get("id") == "autopilot-contract"
ex = d.get("executor") or {}
assert ex.get("kind") == "driver", ex
assert (skill / (ex.get("path") or "scripts/drivers/autopilot-contract.sh")).is_file()
ids = [c.get("id") for c in (d.get("cases") or [])]
for need in ("autopilot-sentinel", "autopilot-no-inherit",
             "autopilot-paragraph", "autopilot-persist"):
    assert need in ids, (need, ids)
PY
[ -f "$DRV" ] || malo "falta scripts/drivers/autopilot-contract.sh"
[ -f "$SKILL/features/autopilot-contract.md" ] || malo "falta ficha autopilot-contract.md"
if [ -f "$DRV" ]; then
  bash -n "$DRV" || malo "bash -n fallo en autopilot-contract.sh"
fi

# El driver no toca hook/golden para fabricar verde.
caso "el cambio no toca hook ni golden"
if git -C "$repo" diff --quiet HEAD -- hooks/summonaikit-harness.sh \
     tests/golden/baseline.txt 2>/dev/null; then
  :
else
  malo "19.10 no debe cambiar hook/golden para fabricar conformidad"
fi

# ---------------------------------------------------------------------------
# Launch + drive
# ---------------------------------------------------------------------------
caso "launch aislado para drive autopilot-contract"
if ! out="$(ctrl launch 2>&1)"; then
  malo "launch fallo: $out"
  echo "FAIL: $fail aserciones (sin launch no hay drives)" >&2
  exit 1
fi
printf '%s' "$out" | grep -q 'launched run_id=' || malo "launch sin run_id: $out"

caso "drive autopilot-contract: sentinel, estado, parrafo, persistencia"
reset_art
out="$(ctrl drive autopilot-contract 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 0 ] || malo "drive autopilot-contract rc=$rc: $out"
sum="$(latest_summary autopilot-contract)"
[ -n "$sum" ] && [ -f "$sum" ] || malo "autopilot-contract sin summary"
if [ -n "$sum" ] && [ -f "$sum" ]; then
python3 - "$sum" <<'PY' || malo "summary autopilot-contract incompleto"
import json, sys
s = json.loads(open(sys.argv[1], encoding="utf-8").read())
assert s.get("result") == "PASS" and s.get("exit_code") == 0, s
cases = s.get("cases") or s.get("cases_requested") or []
text = " ".join(cases) if not isinstance(cases, str) else cases
for need in ("autopilot-sentinel", "autopilot-no-inherit",
             "autopilot-paragraph", "autopilot-persist"):
    assert need in text, (need, cases)
PY
fi

assert_obs autopilot-contract sentinel_exact '-saikit:autopilot'
assert_obs autopilot-contract lane_full 'lane=full'
assert_obs autopilot-contract autopilot_1 'autopilot=1'
assert_obs autopilot-contract plain_no_flag 'sin flag|ausente|no.inherit|no flag'
assert_obs autopilot-contract typo_no_flag 'sin flag|ausente|no.inherit|no flag'
assert_obs autopilot-contract followup_no_inherit 'sin estado|desarm|no.inherit|ausente'
assert_obs autopilot-contract paragraph_present 'Autopilot lane'
assert_obs autopilot-contract asks_confirm 'STOP AND ASK'
assert_obs autopilot-contract no_unattended 'sin promesa|never on your own|explicit yes'
assert_obs autopilot-contract flag_after_tool 'autopilot=1'

# ---------------------------------------------------------------------------
# Mutantes: copia del driver
# ---------------------------------------------------------------------------
copy_driver "$SANDBOX/ap.src.sh"

run_mut() {
  local label="$1" expr="$2" asid="$3" signal="$4"
  caso "mutante $label: $asid se pone rojo"
  reset_art
  local mut="$SANDBOX/ap-$label.sh"
  if sed_must_change "$SANDBOX/ap.src.sh" "$mut" "$expr" "$label"; then
    out="$(ctrl_drv "$mut" drive autopilot-contract 2>&1)" && rc=0 || rc=$?
    assert_missing_or_fail autopilot-contract "$asid" "$signal" "$rc"
  fi
}

run_mut omit_sentinel \
  '/assert:sentinel_exact/,/assert:sentinel_exact_end/d' \
  sentinel_exact '-saikit:autopilot'

run_mut omit_estado \
  '/assert:autopilot_1/,/assert:autopilot_1_end/d' \
  autopilot_1 'autopilot=1'

run_mut omit_parrafo \
  '/assert:paragraph_present/,/assert:paragraph_present_end/d' \
  paragraph_present 'Autopilot lane'

run_mut omit_persistencia \
  '/assert:flag_after_tool/,/assert:flag_after_tool_end/d' \
  flag_after_tool 'autopilot=1'

run_mut accept_typo \
  '/assert:typo_no_flag/,/assert:typo_no_flag_end/d' \
  typo_no_flag 'sin flag|ausente|no.inherit|no flag'

run_mut accept_merge_solo \
  '/assert:no_unattended/,/assert:no_unattended_end/d' \
  no_unattended 'sin promesa|never on your own|explicit yes'

if [ "$fail" -ne 0 ]; then
  echo "FAIL: $fail aserciones" >&2
  exit 1
fi
echo "OK: test_feature_map_autopilot"
exit 0
