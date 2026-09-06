#!/usr/bin/env bash
# autopilot-contract driver — observe -saikit:autopilot via current golden fixtures.
# Does not rewrite hook or baseline. Derived scenarios live under VERIFY_TMPDIR.
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
SRC02="$FIX/02-armado-contrato/01.prompt.claude.json"
SRC01="$FIX/01-sin-armar/01.prompt.claude.json"
SRC_TOOL="$FIX/58-full-close-cita-paths-cierra/04.tool.claude.json"

run_scenarios() {
  local parent="$1"
  [ -d "$parent" ] || { printf 'unknown scenarios: %s\n' "$parent"; return 2; }
  set +e
  runtime_exec "$VERIFY_HOME" bash "$GOLDEN" \
    --print --hook "$VERIFY_DEST" --scenarios "$parent"
  local rc=$?
  set -e
  return "$rc"
}

# Copy one existing fixture dir so golden-harness sees a single scenario.
copy_fixture() {
  local name="$1" dest_parent="$2"
  mkdir -p "$dest_parent"
  cp -R "$FIX/$name" "$dest_parent/"
}

# Rewrite a captured prompt JSON (same keys/shape as the fixture).
write_prompt() {
  local src="$1" dest="$2" prompt="$3"
  python3 - "$src" "$dest" "$prompt" <<'PY'
import json, sys
src, dest, prompt = sys.argv[1], sys.argv[2], sys.argv[3]
data = json.loads(open(src, encoding="utf-8").read())
data["prompt"] = prompt
open(dest, "w", encoding="utf-8").write(json.dumps(data, ensure_ascii=False))
PY
}

# Copy a later fixture step onto the same session_id as the prompt.
write_step_same_session() {
  local prompt_src="$1" step_src="$2" dest="$3"
  python3 - "$prompt_src" "$step_src" "$dest" <<'PY'
import json, sys
prompt_src, step_src, dest = sys.argv[1], sys.argv[2], sys.argv[3]
prompt = json.loads(open(prompt_src, encoding="utf-8").read())
step = json.loads(open(step_src, encoding="utf-8").read())
sid = prompt.get("session_id")
if sid:
    if "session_id" in step:
        step["session_id"] = sid
    if "sessionId" in step:
        step["sessionId"] = sid
open(dest, "w", encoding="utf-8").write(json.dumps(step, ensure_ascii=False))
PY
}

parse_block() {
  python3 - "$1" "$2" <<'PY'
import json, re, shlex, sys
from pathlib import Path
scenario = sys.argv[1]
text = Path(sys.argv[2]).read_text(encoding="utf-8", errors="replace")

def kv(k, v):
    print(f"{k}={shlex.quote(str(v))}")

kv("HAS_HEADER", "1" if f"=== escenario {scenario}" in text else "0")
blocks = re.split(r"^=== escenario ", text, flags=re.M)[1:]
block = ""
for b in blocks:
    name = b.splitlines()[0].strip()
    if name == scenario:
        block = b
        break
kv("BLOCK_NAME", block.splitlines()[0].strip() if block else "")
kv("SIN_ESTADO", "1" if "(sin estado)" in block else "0")
kv("HAS_AUTOPILOT", "1" if re.search(r"(?m)^\| autopilot=1$", block) else "0")
kv("HAS_LANE_FULL", "1" if re.search(r"(?m)^\| lane=full$", block) else "0")
kv("HAS_PARAGRAPH", "1" if "Autopilot lane (-saikit:autopilot)" in block else "0")
kv("HAS_STOP_ASK", "1" if "STOP AND ASK before publishing" in block else "0")
kv("HAS_EXPLICIT_YES", "1" if "operator's explicit yes" in block else "0")
kv("HAS_NEVER_OWN", "1" if "never on your own" in block else "0")
forbidden = (
    r"merges? on its own|merge automatically|revert automatically|"
    r"revierte solo|mergea solo|without asking|desatendid"
)
kv("HAS_UNATTENDED", "1" if re.search(forbidden, block, re.I) else "0")
# Last estado snapshot: after the last step (persist / follow-up).
estados = re.split(r"^--- estado tras el paso ", block, flags=re.M)
last = estados[-1] if len(estados) > 1 else block
kv("LAST_SIN_ESTADO", "1" if "(sin estado)" in last else "0")
kv("LAST_AUTOPILOT", "1" if re.search(r"(?m)^\| autopilot=1$", last) else "0")
PY
}

EXACT_PROMPT="-saikit:autopilot cierra la task"
TYPO_PROMPT="-saikit:autopiloto corrige el typo"

# --- derived fixtures (consume 01/02/58 shape, never the live hook) ----------
AP_PARENT="$VERIFY_TMPDIR/ap-sc"
rm -rf "$AP_PARENT"
mkdir -p "$AP_PARENT/ap-exact" "$AP_PARENT/ap-typo" \
  "$AP_PARENT/ap-follow" "$AP_PARENT/ap-persist"

write_prompt "$SRC02" "$AP_PARENT/ap-exact/01.prompt.claude.json" "$EXACT_PROMPT"
write_prompt "$SRC02" "$AP_PARENT/ap-typo/01.prompt.claude.json" "$TYPO_PROMPT"

write_prompt "$SRC02" "$AP_PARENT/ap-follow/01.prompt.claude.json" "$EXACT_PROMPT"
write_step_same_session \
  "$AP_PARENT/ap-follow/01.prompt.claude.json" \
  "$SRC01" \
  "$AP_PARENT/ap-follow/02.prompt.claude.json"

write_prompt "$SRC02" "$AP_PARENT/ap-persist/01.prompt.claude.json" "$EXACT_PROMPT"
write_step_same_session \
  "$AP_PARENT/ap-persist/01.prompt.claude.json" \
  "$SRC_TOOL" \
  "$AP_PARENT/ap-persist/02.tool.claude.json"

# One parent per derived name so golden-harness prints `=== escenario ap-exact`.
split_one() {
  local name="$1"
  local p="$VERIFY_TMPDIR/one-$name"
  rm -rf "$p"
  mkdir -p "$p"
  cp -R "$AP_PARENT/$name" "$p/"
  printf '%s' "$p"
}

# ---------------------------------------------------------------------------
# autopilot-sentinel
# ---------------------------------------------------------------------------
if fm_only autopilot-sentinel; then
  parent="$(split_one ap-exact)"
  outf="$VERIFY_TMPDIR/ap-exact.txt"
  set +e
  run_scenarios "$parent" >"$outf" 2>&1
  rc=$?
  set -e
  fm_action autopilot-sentinel act-exact "$rc" "golden derived ap-exact" \
    bash "$GOLDEN" --print --hook "$VERIFY_DEST"
  eval "$(parse_block ap-exact "$outf")"
  # assert:sentinel_exact
  if [ "${HAS_HEADER:-0}" = 1 ] && [ "${HAS_PARAGRAPH:-0}" = 1 ]; then
    fm_pass autopilot-sentinel sentinel_exact "exact -saikit:autopilot" \
      "exact -saikit:autopilot"
  else
    fm_fail autopilot-sentinel sentinel_exact "exact -saikit:autopilot" \
      "header=${HAS_HEADER:-0} paragraph=${HAS_PARAGRAPH:-0}"
  fi
  # assert:sentinel_exact_end
  if [ "${HAS_LANE_FULL:-0}" = 1 ]; then
    fm_pass autopilot-sentinel lane_full "lane=full" "lane=full"
  else
    fm_fail autopilot-sentinel lane_full "lane=full" "lane ausente"
  fi
  # assert:autopilot_1
  if [ "${HAS_AUTOPILOT:-0}" = 1 ]; then
    fm_pass autopilot-sentinel autopilot_1 "autopilot=1" "autopilot=1"
  else
    fm_fail autopilot-sentinel autopilot_1 "autopilot=1" "flag ausente"
  fi
  # assert:autopilot_1_end
fi

# ---------------------------------------------------------------------------
# autopilot-no-inherit
# ---------------------------------------------------------------------------
if fm_only autopilot-no-inherit; then
  # Fixture 02: -saikit without suffix. Control: full, no flag.
  p02="$VERIFY_TMPDIR/one-02"
  rm -rf "$p02"
  copy_fixture 02-armado-contrato "$p02"
  out02="$VERIFY_TMPDIR/ap-02.txt"
  set +e
  run_scenarios "$p02" >"$out02" 2>&1
  rc02=$?
  set -e
  fm_action autopilot-no-inherit act-plain "$rc02" "golden 02-armado-contrato" \
    bash "$GOLDEN" --print --hook "$VERIFY_DEST"
  eval "$(parse_block 02-armado-contrato "$out02")"
  if [ "${HAS_AUTOPILOT:-1}" = 0 ]; then
    fm_pass autopilot-no-inherit plain_no_flag "sin flag" "ausente"
  else
    fm_fail autopilot-no-inherit plain_no_flag "sin flag" "autopilot=1 en 02"
  fi

  parent="$(split_one ap-typo)"
  outt="$VERIFY_TMPDIR/ap-typo.txt"
  set +e
  run_scenarios "$parent" >"$outt" 2>&1
  rct=$?
  set -e
  fm_action autopilot-no-inherit act-typo "$rct" "golden derived ap-typo" \
    bash "$GOLDEN" --print --hook "$VERIFY_DEST"
  eval "$(parse_block ap-typo "$outt")"
  # assert:typo_no_flag
  if [ "${HAS_AUTOPILOT:-1}" = 0 ]; then
    fm_pass autopilot-no-inherit typo_no_flag "sin flag" "ausente"
  else
    fm_fail autopilot-no-inherit typo_no_flag "sin flag" "typo heredo flag"
  fi
  # assert:typo_no_flag_end

  parent="$(split_one ap-follow)"
  outf="$VERIFY_TMPDIR/ap-follow.txt"
  set +e
  run_scenarios "$parent" >"$outf" 2>&1
  rcf=$?
  set -e
  fm_action autopilot-no-inherit act-follow "$rcf" "golden derived ap-follow" \
    bash "$GOLDEN" --print --hook "$VERIFY_DEST"
  eval "$(parse_block ap-follow "$outf")"
  if [ "${LAST_SIN_ESTADO:-0}" = 1 ] || [ "${LAST_AUTOPILOT:-1}" = 0 ]; then
    fm_pass autopilot-no-inherit followup_no_inherit "no inherit" \
      "sin estado/ausente"
  else
    fm_fail autopilot-no-inherit followup_no_inherit "no inherit" \
      "follow-up conservo autopilot=1"
  fi
fi

# ---------------------------------------------------------------------------
# autopilot-paragraph
# ---------------------------------------------------------------------------
if fm_only autopilot-paragraph; then
  parent="$(split_one ap-exact)"
  outf="$VERIFY_TMPDIR/ap-para.txt"
  set +e
  run_scenarios "$parent" >"$outf" 2>&1
  rc=$?
  set -e
  fm_action autopilot-paragraph act-para "$rc" "golden derived ap-exact" \
    bash "$GOLDEN" --print --hook "$VERIFY_DEST"
  eval "$(parse_block ap-exact "$outf")"
  # assert:paragraph_present
  if [ "${HAS_PARAGRAPH:-0}" = 1 ]; then
    fm_pass autopilot-paragraph paragraph_present "Autopilot lane" \
      "Autopilot lane"
  else
    fm_fail autopilot-paragraph paragraph_present "Autopilot lane" "ausente"
  fi
  # assert:paragraph_present_end
  if [ "${HAS_STOP_ASK:-0}" = 1 ]; then
    fm_pass autopilot-paragraph asks_confirm "STOP AND ASK" "STOP AND ASK"
  else
    fm_fail autopilot-paragraph asks_confirm "STOP AND ASK" "sin pedido"
  fi
  # assert:no_unattended
  if [ "${HAS_UNATTENDED:-1}" = 0 ] && { [ "${HAS_EXPLICIT_YES:-0}" = 1 ] \
       || [ "${HAS_NEVER_OWN:-0}" = 1 ]; }; then
    fm_pass autopilot-paragraph no_unattended "sin promesa" \
      "never on your own / explicit yes"
  else
    fm_fail autopilot-paragraph no_unattended "sin promesa" \
      "unattended=${HAS_UNATTENDED:-?} yes=${HAS_EXPLICIT_YES:-?} own=${HAS_NEVER_OWN:-?}"
  fi
  # assert:no_unattended_end
fi

# ---------------------------------------------------------------------------
# autopilot-persist
# ---------------------------------------------------------------------------
if fm_only autopilot-persist; then
  parent="$(split_one ap-persist)"
  outf="$VERIFY_TMPDIR/ap-persist.txt"
  set +e
  run_scenarios "$parent" >"$outf" 2>&1
  rc=$?
  set -e
  fm_action autopilot-persist act-persist "$rc" "golden derived ap-persist" \
    bash "$GOLDEN" --print --hook "$VERIFY_DEST"
  eval "$(parse_block ap-persist "$outf")"
  # assert:flag_after_tool
  if [ "${LAST_AUTOPILOT:-0}" = 1 ]; then
    fm_pass autopilot-persist flag_after_tool "autopilot=1" "autopilot=1"
  else
    fm_fail autopilot-persist flag_after_tool "autopilot=1" \
      "flag perdido tras tool last=${LAST_AUTOPILOT:-missing}"
  fi
  # assert:flag_after_tool_end
fi

exit 0
