#!/usr/bin/env bash
# Shared mutation bank for feature-map drivers.
# Drivers set skill_root from dirname/../.. . A flat sandbox copy therefore
# loads the wrong tree and dies with 0 assertions. That death is TEST FAIL,
# not "mutant detected". Place driven copies under scripts/drivers/ so the
# header resolves, and refuse to score until an unmutated copy produced steps.

fm_mut_init() {
  : "${SKILL:?}" "${SANDBOX:?}"
  FM_MUT_TREE="${FM_MUT_TREE:-$SANDBOX/skill}"
  mkdir -p "$FM_MUT_TREE/scripts/drivers"
  if [ ! -e "$FM_MUT_TREE/scripts/lib" ]; then
    ln -s "$SKILL/scripts/lib" "$FM_MUT_TREE/scripts/lib"
  fi
  if [ ! -e "$FM_MUT_TREE/features" ]; then
    ln -s "$SKILL/features" "$FM_MUT_TREE/features"
  fi
}

fm_mut_in_layout() {
  case "$1" in
    */scripts/drivers/*) return 0 ;;
    *) return 1 ;;
  esac
}

fm_mut_place() {
  local src="$1" dest
  fm_mut_init
  if fm_mut_in_layout "$src"; then
    printf '%s' "$src"
    return 0
  fi
  dest="$FM_MUT_TREE/scripts/drivers/$(basename "$src")"
  if [ -e "$dest" ] && [ "$src" -ef "$dest" ]; then
    printf '%s' "$dest"
    return 0
  fi
  cp "$src" "$dest"
  chmod +x "$dest"
  printf '%s' "$dest"
}

fm_mut_last_log() {
  printf '%s' "${SANDBOX:?}/fm-mut-last.out"
}

fm_mut_run_ctrl() {
  local log ec
  log="$(fm_mut_last_log)"
  SAIKIT_VERIFY_STATE="$STATE" SAIKIT_VERIFY_ARTIFACTS="$ART" \
    bash "$CTRL" "$@" >"$log" 2>&1
  ec=$?
  cat "$log"
  return "$ec"
}

ctrl_drv() {
  local drv="$1" placed
  shift
  placed="$(fm_mut_place "$drv")"
  SAIKIT_FM_DRIVER="$placed" fm_mut_run_ctrl "$@"
}

ctrl_drv_raw() {
  local drv="$1"
  shift
  SAIKIT_FM_DRIVER="$drv" fm_mut_run_ctrl "$@"
}

ctrl_pty() {
  local pty="$1"
  shift
  SAIKIT_FM_PTY="$pty" fm_mut_run_ctrl "$@"
}

sed_must_change() {
  local src="$1" dest="$2" expr="$3" label="$4"
  sed "$expr" "$src" > "$dest"
  chmod +x "$dest"
  if cmp -s "$src" "$dest"; then
    malo "$label: sed no cambio el archivo (patron obsoleto)"
    return 1
  fi
  case "$dest" in
    *.py)
      PYTHONDONTWRITEBYTECODE=1 python3 -c \
        "import ast,pathlib; ast.parse(pathlib.Path(r'''$dest''').read_text(encoding='utf-8'))" \
        || { malo "$label: mutante no parsea"; return 1; }
      ;;
    *)
      bash -n "$dest" || { malo "$label: mutante no parsea"; return 1; }
      ;;
  esac
  return 0
}

fm_mut_step_count() {
  local fid="$1" steps
  steps="$(latest_steps "$fid" 2>/dev/null || true)"
  if [ -z "$steps" ] || [ ! -f "$steps" ]; then
    printf '0'
    return 0
  fi
  python3 - "$steps" <<'PY'
import json, sys
n = 0
for line in open(sys.argv[1], encoding="utf-8"):
    if not line.strip():
        continue
    rec = json.loads(line)
    if rec.get("type") in ("assertion", "action"):
        n += 1
print(n)
PY
}

fm_mut_is_infra() {
  local fid="$1" blob="" log n
  log="$(fm_mut_last_log)"
  [ -f "$log" ] && blob="$(cat "$log")"
  case "$blob" in
    *'runtime.sh: No such file'*|*'runtime.sh: No such file or directory'*)
      return 0 ;;
    *'driver.sh: No such file'*)
      return 0 ;;
  esac
  n="$(fm_mut_step_count "$fid")"
  [ "$n" -eq 0 ]
}

fm_mut_require_baseline() {
  local fid="$1" src="$2" stamp art_save placed rc copy
  shift 2
  stamp="$SANDBOX/baseline-ok-$fid"
  [ -f "$stamp" ] && return 0
  if [ ! -f "$src" ]; then
    malo "$fid: sin driver fuente para baseline"
    return 1
  fi
  art_save="$ART"
  ART="$SANDBOX/baseline-art-$fid"
  rm -rf "$ART"
  mkdir -p "$ART"
  copy="$SANDBOX/unmutated-$fid.sh"
  cp "$src" "$copy"
  chmod +x "$copy"
  placed="$(fm_mut_place "$copy")"
  rc=0
  SAIKIT_FM_DRIVER="$placed" fm_mut_run_ctrl "$@" >/dev/null || rc=$?
  if fm_mut_is_infra "$fid"; then
    ART="$art_save"
    malo "$fid: baseline de copia sana no cargo (0 pasos / runtime.sh) rc=$rc"
    return 1
  fi
  : > "$stamp"
  ART="$art_save"
  return 0
}

fm_mut_check_flat_infra() {
  local fid="$1" src="$2" art_save flat rc ok
  shift 2
  caso "F9: copia plana sin mutar de $fid es muerte de carga"
  if [ ! -f "$src" ]; then
    malo "$fid: sin driver para repro F9"
    return 1
  fi
  art_save="$ART"
  ART="$SANDBOX/flat-art-$fid"
  rm -rf "$ART"
  mkdir -p "$ART"
  flat="$SANDBOX/flat-$fid.sh"
  cp "$src" "$flat"
  chmod +x "$flat"
  rc=0
  ctrl_drv_raw "$flat" "$@" >/dev/null || rc=$?
  ok=0
  fm_mut_is_infra "$fid" && ok=1
  ART="$art_save"
  if [ "$ok" -eq 1 ]; then
    return 0
  fi
  malo "$fid: copia plana no mutada no se trato como infra (falso verde F9) rc=$rc"
  return 1
}

assert_missing_or_fail() {
  local fid="$1" asid="$2" signal="$3" rc_drive="$4" sum steps
  if fm_mut_is_infra "$fid"; then
    malo "$fid: muerte de carga (runtime.sh / 0 aserciones) no es mutante de $asid"
    return 1
  fi
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
