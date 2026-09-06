#!/usr/bin/env bash
# capture-payloads driver — fictional host config, synthetic payload only.
# Raw captures stay in VERIFY_TMPDIR. Retained evidence must not hold the synth.
set -euo pipefail
driver_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_root="$(cd "$driver_dir/../.." && pwd)"
# shellcheck source=../lib/runtime.sh
. "$skill_root/scripts/lib/runtime.sh"
# shellcheck source=../lib/driver.sh
. "$skill_root/scripts/lib/driver.sh"

: "${VERIFY_HOME:?}" "${VERIFY_REPO:?}" "${VERIFY_TMPDIR:?}"
: "${SAIKIT_FM_ATTEMPT_DIR:?}"

TOOL="$VERIFY_REPO/tools/capture-payloads.sh"
fm_unknown() { fm_assert "$1" "$2" unknown "$3" "$4"; }

synth_secret() {
  if [ -n "${SAIKIT_FM_SYNTH_SECRET:-}" ]; then
    printf '%s' "$SAIKIT_FM_SYNTH_SECRET"
    return
  fi
  printf '%s%s%s' 'ghp_' 'ABCDEF1234567890abcd' 'efABCDEF1234567890'
}

run_cap() {
  runtime_exec "$VERIFY_HOME" bash "$TOOL" "$@"
}

file_mode() {
  python3 - "$1" <<'PY'
import os, sys
print(oct(os.stat(sys.argv[1]).st_mode & 0o777))
PY
}

is_owner_only() {
  python3 - "$1" <<'PY'
import os, sys
mode = os.stat(sys.argv[1]).st_mode & 0o077
raise SystemExit(0 if mode == 0 else 1)
PY
}

scan_attempt() {
  python3 - "$SAIKIT_FM_ATTEMPT_DIR" "$SYNTH" <<'PY'
import sys
from pathlib import Path
root, needle = Path(sys.argv[1]), sys.argv[2]
hits = []
for p in root.rglob("*"):
    if not p.is_file():
        continue
    try:
        text = p.read_text(encoding="utf-8", errors="replace")
    except OSError:
        continue
    if needle and needle in text:
        hits.append(p.name)
if hits:
    print("hits=" + ",".join(hits[:8]))
    raise SystemExit(1)
print("cero coincidencias")
raise SystemExit(0)
PY
}

contains_synth() {
  case "$1" in
    *"$SYNTH"*) return 0 ;;
    *) return 1 ;;
  esac
}

SYNTH="$(synth_secret)"
# Payload armado sin interpolar el secreto en observaciones posteriores.
PAYLOAD="$(printf '{"hook_event_name":"UserPromptSubmit","prompt":"token=%s"}' "$SYNTH")"
DEST="$VERIFY_TMPDIR/fm-cap-repo"
FOREIGN="$VERIFY_TMPDIR/fm-cap-foreign"
OTHER="$VERIFY_TMPDIR/fm-cap-other"
CAP="$VERIFY_TMPDIR/fm-cap-private"
CAP_CWD="$VERIFY_TMPDIR/fm-cap-cwd"
mkdir -p "$DEST" "$FOREIGN/.claude" "$OTHER" "$CAP" "$CAP_CWD"

if fm_only capture-lifecycle; then
  set +e
  inst_out="$(run_cap --instalar "$DEST" 2>&1)"
  inst_rc=$?
  set -e
  fm_action capture-lifecycle act-install "$inst_rc" "install rc=$inst_rc" \
    bash "$TOOL" --instalar
  settings="$DEST/.claude/settings.json"
  marker="$DEST/.claude/.capture-payloads-owned"
  ignore="$DEST/capturas/.gitignore"
  if [ "$inst_rc" -eq 0 ] && [ -f "$settings" ] && [ -f "$marker" ] && [ -f "$ignore" ] \
    && grep -q 'capture-payloads.sh' "$settings"; then
    fm_pass capture-lifecycle installed "settings marca gitignore" \
      "settings marca owned gitignore"
  else
    fm_fail capture-lifecycle installed "settings marca gitignore" \
      "rc=$inst_rc"
  fi

  set +e
  printf '%s' "$PAYLOAD" | runtime_exec "$DEST" \
    env SAIKIT_CAPTURE_DIR="$CAP" bash "$TOOL"
  feed_rc=$?
  set -e
  saved="$(find "$CAP" -name '*UserPromptSubmit*.json' -type f 2>/dev/null | head -1)"
  fm_action capture-lifecycle act-feed "$feed_rc" "feed rc=$feed_rc evento=UserPromptSubmit" \
    bash "$TOOL" hook-mode
  if [ "$feed_rc" -eq 0 ] && [ -n "$saved" ] && [ -f "$saved" ]; then
    fm_pass capture-lifecycle synthetic_saved "payload sintetico evento" \
      "payload sintetico evento UserPromptSubmit"
  else
    fm_fail capture-lifecycle synthetic_saved "payload sintetico evento" \
      "rc=$feed_rc saved_empty"
  fi

  # assert:perms_private
  perms_ok=1
  perms_obs="privado umask"
  if [ -n "$saved" ] && [ -f "$saved" ]; then
    mode="$(file_mode "$saved")"
    perms_obs="privado umask owner $mode"
    if is_owner_only "$saved" && [ "$mode" = "0o600" -o "$mode" = "0600" ]; then
      perms_ok=0
    elif is_owner_only "$saved"; then
      perms_ok=0
      perms_obs="privado umask owner $mode"
    fi
  fi
  if [ "$perms_ok" -eq 0 ]; then
    fm_pass capture-lifecycle perms_private "600 privado umask owner" "$perms_obs"
  else
    fm_fail capture-lifecycle perms_private "600 privado umask owner" "$perms_obs"
  fi
  # assert:perms_private_end

  set +e
  printf '%s' "$PAYLOAD" | runtime_exec "$OTHER" \
    bash "$TOOL" --only-cwd "$DEST" --capture-dir "$CAP_CWD"
  cwd_rc=$?
  set -e
  cwd_json="$(find "$CAP_CWD" -name '*.json' -type f 2>/dev/null | head -1)"
  fm_action capture-lifecycle act-cwd "$cwd_rc" "cwd filter rc=$cwd_rc" \
    bash "$TOOL" --only-cwd
  # assert:cwd_filtered
  if [ "$cwd_rc" -eq 0 ] && [ -z "$cwd_json" ]; then
    fm_pass capture-lifecycle cwd_filtered "cwd filtro no escribio" \
      "cwd filtro no escribio absent"
  else
    fm_fail capture-lifecycle cwd_filtered "cwd filtro no escribio" \
      "rc=$cwd_rc wrote=$cwd_json"
  fi
  # assert:cwd_filtered_end

  printf 'AJENO-NEIGHBOR\n' > "$DEST/.claude/neighbor.txt"
  neigh_before="$(cksum < "$DEST/.claude/neighbor.txt")"
  set +e
  quit_out="$(run_cap --quitar "$DEST" 2>&1)"
  quit_rc=$?
  set -e
  fm_action capture-lifecycle act-quitar "$quit_rc" "quitar rc=$quit_rc" \
    bash "$TOOL" --quitar
  if [ "$quit_rc" -eq 0 ] && [ ! -f "$settings" ] && [ ! -f "$marker" ]; then
    fm_pass capture-lifecycle retirada_own "quitado retirad" "quitado retirad removed"
  else
    fm_fail capture-lifecycle retirada_own "quitado retirad" "rc=$quit_rc"
  fi

  printf '{"mio":true}\n' > "$FOREIGN/.claude/settings.json"
  foreign_before="$(cksum < "$FOREIGN/.claude/settings.json")"
  set +e
  for_out="$(run_cap --instalar "$FOREIGN" 2>&1)"
  for_rc=$?
  set -e
  foreign_after="$(cksum < "$FOREIGN/.claude/settings.json")"
  neigh_after="$(cksum < "$DEST/.claude/neighbor.txt" 2>/dev/null || true)"
  fm_action capture-lifecycle act-foreign "$for_rc" "foreign install refused" \
    bash "$TOOL" --instalar foreign
  # assert:foreign_intact
  if [ "$for_rc" -ne 0 ] && [ "$foreign_before" = "$foreign_after" ] \
    && grep -q '"mio"' "$FOREIGN/.claude/settings.json" \
    && [ "$neigh_before" = "$neigh_after" ]; then
    fm_pass capture-lifecycle foreign_intact "ajeno intact unchanged" \
      "ajeno intact igual unchanged"
  else
    fm_fail capture-lifecycle foreign_intact "ajeno intact unchanged" \
      "rc=$for_rc overwritten"
  fi
  # assert:foreign_intact_end
fi

if fm_only capture-redaction; then
  if [ -z "${inst_out:-}${quit_out:-}${for_out:-}" ]; then
    fm_fail capture-redaction evidence_no_secret "cero coincidencias" \
      "sin salidas de lifecycle para redactar"
  else
  leak=0
  if contains_synth "${inst_out:-}${quit_out:-}${for_out:-}"; then
    leak=1
  fi
  # assert:evidence_no_secret
  set +e
  scan_obs="$(scan_attempt 2>&1)"
  scan_rc=$?
  set -e
  if [ "$scan_rc" -eq 0 ] && [ "$leak" -eq 0 ]; then
    fm_pass capture-redaction evidence_no_secret "cero coincidencias" \
      "cero coincidencias ausente"
  else
    fm_fail capture-redaction evidence_no_secret "cero coincidencias" \
      "secreto en evidencia"
  fi
  fi
  # assert:evidence_no_secret_end
fi

exit 0
