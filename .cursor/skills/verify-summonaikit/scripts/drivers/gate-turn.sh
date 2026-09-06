#!/usr/bin/env bash
# gate-turn driver — golden-harness assertions reused from verify/test_drive.py.
set -euo pipefail
driver_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_root="$(cd "$driver_dir/../.." && pwd)"
# shellcheck source=../lib/runtime.sh
. "$skill_root/scripts/lib/runtime.sh"
# shellcheck source=../lib/driver.sh
. "$skill_root/scripts/lib/driver.sh"

: "${VERIFY_HOME:?}" "${VERIFY_DEST:?}" "${VERIFY_REPO:?}" "${VERIFY_TMPDIR:?}"
: "${SAIKIT_FM_ATTEMPT_DIR:?}"

GOLDEN="$VERIFY_REPO/tools/golden-harness.sh"
FIX="$VERIFY_REPO/tests/fixtures/escenarios"

run_scenario() {
  local scenario="$1"
  local src="$FIX/$scenario"
  [ -d "$src" ] || { printf 'unknown scenario: %s\n' "$scenario"; return 2; }
  local sc_dir
  sc_dir="$(mktemp -d "$VERIFY_TMPDIR/sc-XXXXXX")"
  cp -R "$src" "$sc_dir/"
  set +e
  runtime_exec "$VERIFY_HOME" bash "$GOLDEN" \
    --print --hook "$VERIFY_DEST" --scenarios "$sc_dir"
  local rc=$?
  set -e
  rm -rf "$sc_dir"
  return "$rc"
}

parse_block() {
  # $1=scenario $2=path to golden stdout. Prints KEY=value lines.
  python3 - "$1" "$2" <<'PY'
import json, re, shlex, sys
from pathlib import Path
scenario = sys.argv[1]
text = Path(sys.argv[2]).read_text(encoding="utf-8", errors="replace")

def kv(k, v):
    print(f"{k}={shlex.quote(str(v))}")

kv("HAS_HEADER", "1" if f"=== escenario {scenario}" in text else "0")
m = re.search(r"^# hook_sha256: ([0-9a-f]+)$", text, re.M)
kv("HOOK_SHA", m.group(1) if m else "")
blocks = re.split(r"^=== escenario ", text, flags=re.M)[1:]
block = ""
for b in blocks:
    name = b.splitlines()[0].strip()
    if name == scenario:
        block = b
        break
kv("BLOCK_NAME", block.splitlines()[0].strip() if block else "")
pasos = re.split(r"^--- paso ", block, flags=re.M)[1:] if block else []
ids = []
for p in pasos:
    ids.append(p.split()[0] if p.split() else "")
kv("STEPS", " ".join(ids))
kv("SIN_ESTADO", "1" if "(sin estado)" in block else "0")
kv("HAS_CONTRACT", "1" if "SUMMONAIKIT HARNESS REQUIRED" in block else "0")
kv("HAS_HSTATE", "1" if "harness-state.env" in block else "0")
kv("HAS_TASK_HASH", "1" if re.search(r"task_hash=[0-9]+", block) else "0")
kv("HAS_EXIT2", "1" if re.search(r"^exit 2$", block, re.M) else "0")
kv("HAS_GATE", "1" if re.search(r"recibo|evidencia|bloque|deny|gate", block, re.I) else "0")
ok_json = "0"
if "SUMMONAIKIT HARNESS REQUIRED" in block:
    try:
        blob = "\n".join(ln[2:] for ln in block.splitlines() if ln.startswith("| "))
        start = blob.find("{")
        contrato = json.loads(blob[start:]) if start >= 0 else {}
        ctx = (contrato or {}).get("hookSpecificOutput") or {}
        extra = ctx.get("additionalContext") or ""
        if ctx.get("hookEventName") == "UserPromptSubmit" and extra.startswith(
            "SUMMONAIKIT HARNESS REQUIRED"
        ):
            ok_json = "1"
    except (json.JSONDecodeError, TypeError, AttributeError):
        ok_json = "0"
kv("CONTRACT_JSON", ok_json)
PY
}

src_sha="$(fm_sha "$VERIFY_REPO/hooks/summonaikit-harness.sh")"

if fm_only gate-unarmed; then
  outf="$VERIFY_TMPDIR/gate-01.txt"
  set +e
  run_scenario 01-sin-armar >"$outf" 2>&1
  rc=$?
  set -e
  fm_action gate-unarmed act-unarmed "$rc" "golden 01-sin-armar" \
    bash "$GOLDEN" --print --hook "$VERIFY_DEST"
  eval "$(parse_block 01-sin-armar "$outf")"
  if [ "${HOOK_SHA:-}" = "$src_sha" ]; then
    fm_pass gate-unarmed hook_sha "$src_sha" "$HOOK_SHA"
  else
    fm_fail gate-unarmed hook_sha "$src_sha" "${HOOK_SHA:-missing}"
  fi
  if [ "${STEPS:-}" = "01 02 03" ]; then
    fm_pass gate-unarmed scenario_steps "01 02 03" "$STEPS"
  else
    fm_fail gate-unarmed scenario_steps "01 02 03" "${STEPS:-}"
  fi
  # assert:sin_estado
  if [ "${SIN_ESTADO:-0}" = 1 ]; then
    fm_pass gate-unarmed sin_estado "(sin estado)" "(sin estado)"
  else
    fm_fail gate-unarmed sin_estado "(sin estado)" "estado presente o ausente"
  fi
  # assert:sin_estado_end
  if [ "${HAS_CONTRACT:-1}" = 0 ]; then
    fm_pass gate-unarmed sin_contrato "sin contrato" "sin contrato"
  else
    fm_fail gate-unarmed sin_contrato "sin contrato" "contrato presente en 01"
  fi
fi

if fm_only gate-armed; then
  outf="$VERIFY_TMPDIR/gate-02.txt"
  set +e
  run_scenario 02-armado-contrato >"$outf" 2>&1
  rc=$?
  set -e
  fm_action gate-armed act-armed "$rc" "golden 02-armado-contrato" \
    bash "$GOLDEN" --print --hook "$VERIFY_DEST"
  eval "$(parse_block 02-armado-contrato "$outf")"
  if [ "${HOOK_SHA:-}" = "$src_sha" ]; then
    fm_pass gate-armed hook_sha "$src_sha" "$HOOK_SHA"
  else
    fm_fail gate-armed hook_sha "$src_sha" "${HOOK_SHA:-missing}"
  fi
  if [ "${STEPS:-}" = "01" ]; then
    fm_pass gate-armed scenario_steps "01" "$STEPS"
  else
    fm_fail gate-armed scenario_steps "01" "${STEPS:-}"
  fi
  # assert:contract_json
  if [ "${CONTRACT_JSON:-0}" = 1 ] || [ "${HAS_CONTRACT:-0}" = 1 ]; then
    fm_pass gate-armed contract_json "SUMMONAIKIT HARNESS REQUIRED" \
      "SUMMONAIKIT HARNESS REQUIRED"
  else
    fm_fail gate-armed contract_json "SUMMONAIKIT HARNESS REQUIRED" "contrato ausente"
  fi
  # assert:contract_json_end
  # assert:harness_state
  if [ "${HAS_HSTATE:-0}" = 1 ]; then
    extra=""
    [ "${HAS_TASK_HASH:-0}" = 1 ] && extra=" task_hash"
    fm_pass gate-armed harness_state "harness-state.env" "harness-state.env$extra"
  else
    fm_fail gate-armed harness_state "harness-state.env" "sin harness-state.env"
  fi
  # assert:harness_state_end
fi

if fm_only gate-stop-no-receipt; then
  outf="$VERIFY_TMPDIR/gate-07.txt"
  set +e
  run_scenario 07-evidencia-incompleta >"$outf" 2>&1
  rc=$?
  set -e
  fm_action gate-stop-no-receipt act-stop "$rc" "golden 07-evidencia-incompleta" \
    bash "$GOLDEN" --print --hook "$VERIFY_DEST"
  eval "$(parse_block 07-evidencia-incompleta "$outf")"
  out="$(cat "$outf")"
  if [ "${HAS_EXIT2:-0}" = 1 ] || [ "${HAS_GATE:-0}" = 1 ]; then
    fm_pass gate-stop-no-receipt stop_rejected "exit 2 / gate" \
      "exit 2=${HAS_EXIT2:-0} gate=${HAS_GATE:-0}"
  else
    fm_fail gate-stop-no-receipt stop_rejected "exit 2 / gate" "$out"
  fi
  if [ "${BLOCK_NAME:-}" = "07-evidencia-incompleta" ]; then
    fm_pass gate-stop-no-receipt not_scenario_01_02 "07-evidencia-incompleta" \
      "07-evidencia-incompleta"
  else
    fm_fail gate-stop-no-receipt not_scenario_01_02 "07-evidencia-incompleta" \
      "${BLOCK_NAME:-}"
  fi
fi

exit 0
