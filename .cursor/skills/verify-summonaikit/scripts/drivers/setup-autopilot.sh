#!/usr/bin/env bash
# setup-autopilot driver — real saikit-setup-autopilot.sh over a stdlib PTY
# (interactive) or without TTY (flags/defaults/pipe). Never fakes a PTY.
set -euo pipefail
driver_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_root="$(cd "$driver_dir/../.." && pwd)"
# shellcheck source=../lib/runtime.sh
. "$skill_root/scripts/lib/runtime.sh"
# shellcheck source=../lib/driver.sh
. "$skill_root/scripts/lib/driver.sh"

: "${VERIFY_HOME:?}" "${VERIFY_REPO:?}" "${VERIFY_TMPDIR:?}"
: "${SAIKIT_FM_ATTEMPT_DIR:?}"

SETUP="$VERIFY_REPO/tools/saikit-setup-autopilot.sh"
PTY="${SAIKIT_FM_PTY:-$skill_root/scripts/lib/pty_driver.py}"
# Literal 0 so accept_pipe_as_pty can flip it with sed.
SAIKIT_FM_PIPE_IS_PTY=0

fm_unknown() { fm_assert "$1" "$2" unknown "$3" "$4"; }

pty_probe() {
  if [ "${SAIKIT_VERIFY_PTY:-}" = "missing" ]; then
    return 1
  fi
  PYTHONDONTWRITEBYTECODE=1 python3 "$PTY" --probe >/dev/null 2>&1
}

json_field() {
  python3 - "$1" "$2" <<'PY'
import json, sys
path, key = sys.argv[1], sys.argv[2]
try:
    data = json.load(open(path, encoding="utf-8"))
except (OSError, json.JSONDecodeError):
    print("<missing>")
    raise SystemExit(0)
val = data.get(key, "<null>")
if val is None:
    print("<null>")
elif isinstance(val, bool):
    print("true" if val else "false")
else:
    print(val)
PY
}

make_repo() {
  local dest="$1" mode="${2:-no_ci}"
  rm -rf "$dest"
  mkdir -p "$dest"
  git -C "$dest" -c init.defaultBranch=master init -q
  git -C "$dest" -c user.email=t@example.invalid -c user.name=t \
    -c commit.gpgsign=false commit --allow-empty -qm 'chore: fixture'
  if [ "$mode" = with_ci ]; then
    mkdir -p "$dest/.github/workflows"
    printf '%s\n' 'name: x' 'on: push' 'jobs:' '  t:' \
      '    runs-on: ubuntu-latest' '    steps:' '      - run: "true"' \
      > "$dest/.github/workflows/x.yml"
  fi
}

run_setup() {
  local work="$1"
  shift
  runtime_exec "$work" bash "$SETUP" "$@" < /dev/null
}

run_pty() {
  local work="$1" timeout="$2" outjson="$3"
  shift 3
  PYTHONDONTWRITEBYTECODE=1 python3 "$PTY" \
    --timeout "$timeout" --cwd "$work" --out "$outjson" \
    "$@" -- bash "$SETUP"
}

cfg_of() { printf '%s/.saikit/autopilot.json' "$1"; }
lock_of() {
  local common
  common="$(git -C "$1" rev-parse --git-common-dir 2>/dev/null || true)"
  case "$common" in
    /*) printf '%s/saikit-autopilot.lock' "$common" ;;
    "") printf '%s/.git/saikit-autopilot.lock' "$1" ;;
    *) printf '%s/%s/saikit-autopilot.lock' "$1" "$common" ;;
  esac
}

# ---------------------------------------------------------------------------
# Interactive: five questions on a repo WITH CI (no CI offer mixed in)
# ---------------------------------------------------------------------------
if fm_only setup-interactive; then
  work="$VERIFY_TMPDIR/setup-interactive"
  make_repo "$work" with_ci
  if ! pty_probe; then
    fm_unknown setup-interactive questions_order "1/5 < 2/5 < 3/5 < 4/5 < 5/5" "PTY ausente"
    fm_unknown setup-interactive map_merge "true" "PTY ausente"
    fm_unknown setup-interactive map_despliega "publica" "PTY ausente"
    fm_unknown setup-interactive map_salud "pty.example.test" "PTY ausente"
    fm_unknown setup-interactive map_sve "false" "PTY ausente"
    fm_unknown setup-interactive map_telegram "true" "PTY ausente"
  else
    report="$VERIFY_TMPDIR/pty-interactive.json"
    set +e
    run_pty "$work" 12 "$report" \
      --answer si \
      --answer si-publica \
      --answer https://pty.example.test/salud \
      --answer no \
      --answer si
    prc=$?
    set -e
    transcript="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("transcript",""))' "$report" 2>/dev/null || true)"
    fm_action setup-interactive act-pty "$prc" "$transcript" python3 "$PTY" -- interactive
    cfg="$(cfg_of "$work")"
    order="$(python3 -c 'import sys; t=sys.stdin.read();
idx=[t.find(m) for m in ("1/5","2/5","3/5","4/5","5/5")]
print(" ".join("%s@%s"%(m,i) for m,i in zip(("1/5","2/5","3/5","4/5","5/5"),idx)))
print("ordered" if all(idx[i]>=0 and (i==0 or idx[i]>idx[i-1]) for i in range(5)) else "unordered")
' <<<"$transcript")"
    # assert:questions_order
    if printf '%s' "$order" | grep -qx 'ordered'; then
      fm_pass setup-interactive questions_order "1/5 < 2/5 < 3/5 < 4/5 < 5/5" "$order"
    else
      fm_fail setup-interactive questions_order "1/5 < 2/5 < 3/5 < 4/5 < 5/5" "$order"
    fi
    # assert:questions_order_end
    merge_v="$(json_field "$cfg" merge)"
    desp_v="$(json_field "$cfg" merge_despliega)"
    salud_v="$(json_field "$cfg" salud_url)"
    sve_v="$(json_field "$cfg" sin_verify_app)"
    tel_v="$(json_field "$cfg" telegram)"
    # assert:map_merge
    if [ "$merge_v" = "true" ]; then
      fm_pass setup-interactive map_merge "true" "merge=true"
    else
      fm_fail setup-interactive map_merge "true" "merge=$merge_v"
    fi
    # assert:map_merge_end
    # assert:map_despliega
    if [ "$desp_v" = "publica" ]; then
      fm_pass setup-interactive map_despliega "publica" "merge_despliega=publica"
    else
      fm_fail setup-interactive map_despliega "publica" "merge_despliega=$desp_v"
    fi
    # assert:map_despliega_end
    # assert:map_salud
    if printf '%s' "$salud_v" | grep -q 'pty.example.test'; then
      fm_pass setup-interactive map_salud "pty.example.test" "$salud_v"
    else
      fm_fail setup-interactive map_salud "pty.example.test" "$salud_v"
    fi
    # assert:map_salud_end
    # assert:map_sve
    if [ "$sve_v" = "false" ]; then
      fm_pass setup-interactive map_sve "false" "sin_verify_app=false"
    else
      fm_fail setup-interactive map_sve "false" "sin_verify_app=$sve_v"
    fi
    # assert:map_sve_end
    # assert:map_telegram
    if [ "$tel_v" = "true" ]; then
      fm_pass setup-interactive map_telegram "true" "telegram=true"
    else
      fm_fail setup-interactive map_telegram "true" "telegram=$tel_v"
    fi
    # assert:map_telegram_end
  fi
fi

# ---------------------------------------------------------------------------
# Invalid answer: no partial JSON, no leftover lock
# ---------------------------------------------------------------------------
if fm_only setup-invalid; then
  work="$VERIFY_TMPDIR/setup-invalid"
  make_repo "$work" with_ci
  if ! pty_probe; then
    fm_unknown setup-invalid invalid_no_write "ausente" "PTY ausente"
    fm_unknown setup-invalid invalid_no_lock "sin lock" "PTY ausente"
  else
    report="$VERIFY_TMPDIR/pty-invalid.json"
    set +e
    run_pty "$work" 8 "$report" --answer talvez
    prc=$?
    set -e
    cfg="$(cfg_of "$work")"
    lock="$(lock_of "$work")"
    fm_action setup-invalid act-invalid "$prc" "invalid" python3 "$PTY" -- invalid
    if [ ! -e "$cfg" ]; then
      fm_pass setup-invalid invalid_no_write "ausente" "ausente (sin escritura)"
    else
      fm_fail setup-invalid invalid_no_write "ausente" "escribio $cfg"
    fi
    if [ ! -e "$lock" ]; then
      fm_pass setup-invalid invalid_no_lock "sin lock" "sin lock (liberado)"
    else
      fm_fail setup-invalid invalid_no_lock "sin lock" "lock huerfano $lock"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Timeout: kill/reap group; no JSON; no leftover lock
# ---------------------------------------------------------------------------
if fm_only setup-timeout; then
  work="$VERIFY_TMPDIR/setup-timeout"
  make_repo "$work" with_ci
  if ! pty_probe; then
    fm_unknown setup-timeout timeout_no_write "ausente" "PTY ausente"
    fm_unknown setup-timeout timeout_no_lock "sin lock" "PTY ausente"
    fm_unknown setup-timeout timeout_reaped "reaped" "PTY ausente"
  else
    report="$VERIFY_TMPDIR/pty-timeout.json"
    set +e
    run_pty "$work" 2 "$report"
    prc=$?
    set -e
    timed="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print("1" if d.get("timed_out") else "0")' "$report")"
    killed="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print("1" if d.get("killed") else "0")' "$report")"
    reaped="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print("1" if d.get("reaped") else "0")' "$report")"
    cfg="$(cfg_of "$work")"
    lock="$(lock_of "$work")"
    fm_action setup-timeout act-timeout "$prc" "timed_out=$timed" python3 "$PTY" -- timeout
    if [ ! -e "$cfg" ]; then
      fm_pass setup-timeout timeout_no_write "ausente" "ausente (sin escritura)"
    else
      fm_fail setup-timeout timeout_no_write "ausente" "escribio $cfg"
    fi
    # assert:timeout_no_lock
    if [ ! -e "$lock" ]; then
      fm_pass setup-timeout timeout_no_lock "sin lock" "sin lock (liberado)"
    else
      fm_fail setup-timeout timeout_no_lock "sin lock" "lock huerfano $lock"
    fi
    # assert:timeout_no_lock_end
    if [ "$timed" = 1 ] && [ "$killed" = 1 ] && [ "$reaped" = 1 ]; then
      fm_pass setup-timeout timeout_reaped "reaped" "reaped killed=1 timed_out=1"
    else
      fm_fail setup-timeout timeout_reaped "reaped" "timed=$timed killed=$killed reaped=$reaped"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Flags without TTY
# ---------------------------------------------------------------------------
if fm_only setup-flags; then
  work="$VERIFY_TMPDIR/setup-flags"
  make_repo "$work" with_ci
  set +e
  out="$(run_setup "$work" --merge no --despliega no \
    --salud-url https://flags.example.test/ok \
    --sin-verify-app si --telegram no --rama master --pr 7 --ci-minimo no 2>&1)"
  rc=$?
  set -e
  cfg="$(cfg_of "$work")"
  fm_action setup-flags act-flags "$rc" "$out" bash "$SETUP" --flags
  merge_v="$(json_field "$cfg" merge)"
  salud_v="$(json_field "$cfg" salud_url)"
  if [ "$merge_v" = "false" ]; then
    fm_pass setup-flags flags_merge "false" "merge=false"
  else
    fm_fail setup-flags flags_merge "false" "merge=$merge_v"
  fi
  if printf '%s' "$salud_v" | grep -q 'flags.example.test'; then
    fm_pass setup-flags flags_salud "flags.example.test" "$salud_v"
  else
    fm_fail setup-flags flags_salud "flags.example.test" "$salud_v"
  fi
fi

# ---------------------------------------------------------------------------
# Defaults without TTY
# ---------------------------------------------------------------------------
if fm_only setup-defaults; then
  work="$VERIFY_TMPDIR/setup-defaults"
  make_repo "$work" with_ci
  set +e
  out="$(run_setup "$work" --pr 1 --ci-minimo no 2>&1)"
  rc=$?
  set -e
  cfg="$(cfg_of "$work")"
  fm_action setup-defaults act-defaults "$rc" "$out" bash "$SETUP" --defaults
  merge_v="$(json_field "$cfg" merge)"
  desp_v="$(json_field "$cfg" merge_despliega)"
  if [ "$merge_v" = "false" ]; then
    fm_pass setup-defaults defaults_merge "false" "merge=false"
  else
    fm_fail setup-defaults defaults_merge "false" "merge=$merge_v"
  fi
  # assert:defaults_despliega
  if [ "$desp_v" = "unknown" ]; then
    fm_pass setup-defaults defaults_despliega "unknown" "merge_despliega=unknown"
  else
    fm_fail setup-defaults defaults_despliega "unknown" "merge_despliega=$desp_v"
  fi
  # assert:defaults_despliega_end
fi

# ---------------------------------------------------------------------------
# Pipe is not a PTY: piped answers are ignored ([ -t 0 ] is false)
# ---------------------------------------------------------------------------
if fm_only setup-pipe-not-pty; then
  work="$VERIFY_TMPDIR/setup-pipe"
  make_repo "$work" with_ci
  set +e
  out="$(printf '%s\n' si si-publica https://pipe.example.test/x si si \
    | runtime_exec "$work" bash "$SETUP" --pr 1 --ci-minimo no 2>&1)"
  rc=$?
  set -e
  cfg="$(cfg_of "$work")"
  merge_v="$(json_field "$cfg" merge)"
  desp_v="$(json_field "$cfg" merge_despliega)"
  fm_action setup-pipe-not-pty act-pipe "$rc" "$out" bash "$SETUP" --pipe
  if [ "$SAIKIT_FM_PIPE_IS_PTY" = 1 ]; then
    fm_fail setup-pipe-not-pty pipe_not_pty "pipe-not-pty" \
      "mutation accepted pipe as PTY"
  elif [ "$merge_v" = "false" ] && [ "$desp_v" = "unknown" ]; then
    fm_pass setup-pipe-not-pty pipe_not_pty "pipe-not-pty" \
      "pipe-not-pty defaults-used merge=$merge_v despliega=$desp_v"
  else
    fm_fail setup-pipe-not-pty pipe_not_pty "pipe-not-pty" \
      "pipe acredito respuestas merge=$merge_v despliega=$desp_v"
  fi
fi

# ---------------------------------------------------------------------------
# Stale lock blocks; no write
# ---------------------------------------------------------------------------
if fm_only setup-lock; then
  work="$VERIFY_TMPDIR/setup-lock"
  make_repo "$work" with_ci
  lock="$(lock_of "$work")"
  mkdir -p "$lock"
  printf '99999999' > "$lock/pid"
  printf 'host-viejo' > "$lock/host"
  set +e
  out="$(run_setup "$work" --merge no --despliega no --sin-verify-app no \
    --telegram no --ci-minimo no --pr 9 2>&1)"
  rc=$?
  set -e
  cfg="$(cfg_of "$work")"
  fm_action setup-lock act-lock "$rc" "$out" bash "$SETUP" --lock
  # assert:lock_blocks
  if [ "$rc" -eq 3 ] && printf '%s' "$out" | grep -Eq 'LOCK|lock'; then
    fm_pass setup-lock lock_blocks "3" "exit 3 LOCK ocupado"
  else
    fm_fail setup-lock lock_blocks "3" "rc=$rc $out"
  fi
  # assert:lock_blocks_end
  if [ ! -e "$cfg" ]; then
    fm_pass setup-lock lock_no_write "ausente" "ausente (sin escritura)"
  else
    fm_fail setup-lock lock_no_write "ausente" "escribio pese al lock"
  fi
fi

# ---------------------------------------------------------------------------
# Repo WITH CI: flags, no CI offer
# ---------------------------------------------------------------------------
if fm_only setup-with-ci; then
  work="$VERIFY_TMPDIR/setup-with-ci"
  make_repo "$work" with_ci
  set +e
  out="$(run_setup "$work" --merge no --despliega no --sin-verify-app no \
    --telegram no --ci-minimo no --pr 1 2>&1)"
  rc=$?
  set -e
  fm_action setup-with-ci act-ci "$rc" "$out" bash "$SETUP" --with-ci
  if printf '%s' "$out" | grep -Eq 'ya hay workflows|no se ofrece'; then
    fm_pass setup-with-ci with_ci_no_offer "ya hay workflows" "ya hay workflows, no se ofrece"
  else
    fm_fail setup-with-ci with_ci_no_offer "ya hay workflows" "$out"
  fi
fi

# ---------------------------------------------------------------------------
# Repo WITHOUT CI: aviso is not question 6/5
# ---------------------------------------------------------------------------
if fm_only setup-without-ci; then
  work="$VERIFY_TMPDIR/setup-without-ci"
  make_repo "$work" no_ci
  set +e
  out="$(run_setup "$work" --merge no --despliega no --sin-verify-app no \
    --telegram no --pr 1 2>&1)"
  rc=$?
  set -e
  fm_action setup-without-ci act-noci "$rc" "$out" bash "$SETUP" --without-ci
  if printf '%s' "$out" | grep -Eq 'sin CI|no mergea'; then
    fm_pass setup-without-ci without_ci_aviso "sin CI" "sin CI el autopilot no mergea"
  else
    fm_fail setup-without-ci without_ci_aviso "sin CI" "$out"
  fi
  if printf '%s' "$out" | grep -q '6/5'; then
    fm_fail setup-without-ci ci_not_q6 "no 6/5" "CI se presento como 6/5"
  else
    fm_pass setup-without-ci ci_not_q6 "no 6/5" "ci offer is not 6/5"
  fi
fi

exit 0
