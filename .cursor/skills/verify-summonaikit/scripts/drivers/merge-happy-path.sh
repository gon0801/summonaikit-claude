#!/usr/bin/env bash
# merge-happy-path driver — live-merge precondition evaluator (19.16).
# Never merges, never calls GitHub APIs, never writes live operator profiles.
set -euo pipefail
driver_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_root="$(cd "$driver_dir/../.." && pwd)"
# shellcheck source=../lib/runtime.sh
. "$skill_root/scripts/lib/runtime.sh"
# shellcheck source=../lib/driver.sh
. "$skill_root/scripts/lib/driver.sh"

: "${VERIFY_HOME:?}" "${VERIFY_REPO:?}" "${VERIFY_TMPDIR:?}"
: "${SAIKIT_FM_ATTEMPT_DIR:?}"

fm_unknown() { fm_assert "$1" "$2" unknown "$3" "$4"; }

# Inspect PATH only. Never exec gh/curl/ssh (no external call).
inspect_gh() {
  local path head
  path="$(command -v gh 2>/dev/null || true)"
  if [ -z "$path" ]; then
    printf '%s' "ausente"
    return
  fi
  head="$(python3 -c "import pathlib,sys; b=pathlib.Path(sys.argv[1]).read_bytes()[:80]; sys.stdout.buffer.write(b)" "$path" 2>/dev/null || true)"
  case "$head" in
    '#!'*) printf '%s' "falso" ;;
    *) printf '%s' "oficial" ;;
  esac
}

# --- authorization / destination: present or not, never a license to merge
# mutate:perm_as_pass
auth_result=unknown
auth_avail=BLOCKED
# mutate:perm_as_pass_end

gh_kind="$(inspect_gh)"
# mutate:fake_gh_as_live
gh_live=no
# mutate:fake_gh_as_live_end

auth="${SAIKIT_LIVE_AUTH:-}"
dest="${SAIKIT_LIVE_DEST:-}"
auth_reason="sin autorización viva"
dest_reason="sin destino concreto"
if [ -n "$auth" ]; then
  auth_reason="autorización presente no ejecuta merge vivo"
fi
if [ -n "$dest" ]; then
  dest_reason="destino presente no ejecuta merge vivo"
fi

case "$gh_kind" in
  ausente) gh_reason="gh ausente — solo afecta modo live" ;;
  falso) gh_reason="gh falso no acredita acceso vivo" ;;
  *) gh_reason="gh oficial presente (sin sondear cuota)" ;;
esac

LAB="$VERIFY_TMPDIR/fm-live-seal"
mkdir -p "$LAB/parent" "$LAB/child"
printf 'lane=full\n' > "$LAB/parent/harness-state.env"
printf 'verified: bash tests/run.sh\n' > "$LAB/parent/harness-evidence.log"
printf 'veredicto_sha256=childsealdeadbeef\n' > "$LAB/child/harness-state.env"
# parent older so a mtime heuristic would pick the child
touch -t 202001010101 "$LAB/parent/harness-state.env" "$LAB/parent/harness-evidence.log" \
  2>/dev/null || true
touch "$LAB/child/harness-state.env"

# mutate:seal_via_mtime
do_transfer=no
# mutate:seal_via_mtime_end
if [ "$do_transfer" = yes ]; then
  if grep -q 'verified: ' "$LAB/parent/harness-evidence.log" \
    || [ "$LAB/child/harness-state.env" -nt "$LAB/parent/harness-state.env" ]; then
    printf 'veredicto_sha256=childsealdeadbeef\n' >> "$LAB/parent/harness-state.env"
  fi
fi

PROCEDURE=$'Manual live measurement (Optional; preparing this does NOT authorize running it):\n'
PROCEDURE+=$'1. Disposable repo (not an operator production profile).\n'
PROCEDURE+=$'2. Identify the run with topic+marker.\n'
PROCEDURE+=$'3. Name the host (claude/grok/dsh/codex).\n'
PROCEDURE+=$'4. Record cost/quota before any live gh call.\n'
PROCEDURE+=$'5. Capture SHA/PR of the sealed verdict.\n'
PROCEDURE+=$'6. Redacted capture only — no tokens in artifacts.\n'
PROCEDURE+=$'Preparing this procedure no-autoriza-ejecutar the live merge.\n'

if fm_only live-blocked-no-auth; then
  fm_action live-blocked-no-auth act-pre 3 \
    "preconditions only; no merge" "merge-happy-path" preconditions
  # assert:blocked_unknown
  if [ "$auth_avail" = BLOCKED ] && [ "$auth_result" = unknown ]; then
    fm_pass live-blocked-no-auth blocked_unknown \
      "BLOCKED unknown" "BLOCKED unknown sin autorización"
  else
    fm_fail live-blocked-no-auth blocked_unknown \
      "BLOCKED unknown" "presented as ${auth_result}/${auth_avail}"
  fi
  # assert:blocked_unknown_end
  # assert:no_external_call
  # inspect_gh only reads PATH bytes; never execs gh/curl/ssh.
  if [ "$auth_avail" = BLOCKED ] && [ "$auth_result" = unknown ] \
    && [ "$gh_live" = no ]; then
    fm_pass live-blocked-no-auth no_external_call \
      "no-external-call" "no-external-call (gh/curl/ssh not exec'd)"
  else
    fm_fail live-blocked-no-auth no_external_call \
      "no-external-call" "estado no garantiza ausencia de llamada externa"
  fi
  # assert:no_external_call_end
fi

if fm_only live-current-reasons; then
  fm_action live-current-reasons act-reasons 3 \
    "${auth_reason}; ${dest_reason}; ${gh_reason}" "merge-happy-path" reasons
  # assert:reason_auth_dest
  if [ -n "$auth_reason" ] && [ -n "$dest_reason" ]; then
    fm_pass live-current-reasons reason_auth_dest \
      "autoriz+destino actuales" "${auth_reason}; ${dest_reason}"
  else
    fm_fail live-current-reasons reason_auth_dest \
      "autoriz+destino actuales" "razones vacias"
  fi
  # assert:reason_auth_dest_end
  # assert:reason_gh
  if [ "$gh_live" = yes ]; then
    fm_fail live-current-reasons reason_gh \
      "gh falso no acredita" "gh-vivo-acreditado (${gh_kind})"
  elif [ -n "$gh_reason" ]; then
    fm_pass live-current-reasons reason_gh \
      "gh actual nombrado" "$gh_reason"
  else
    fm_fail live-current-reasons reason_gh \
      "gh actual nombrado" "razon gh vacia"
  fi
  # assert:reason_gh_end
fi

if fm_only live-manual-procedure; then
  fm_action live-manual-procedure act-proc 3 \
    "procedure defined, not executed" "merge-happy-path" procedure
  # assert:procedure_defined
  if printf '%s' "$PROCEDURE" | grep -q 'topic+marker' \
    && printf '%s' "$PROCEDURE" | grep -q 'Name the host' \
    && printf '%s' "$PROCEDURE" | grep -q 'SHA/PR'; then
    fm_pass live-manual-procedure procedure_defined \
      "topic+marker host cuota SHA/PR" "$PROCEDURE"
  else
    fm_fail live-manual-procedure procedure_defined \
      "topic+marker host cuota SHA/PR" "procedure incompleto"
  fi
  # assert:procedure_defined_end
  # assert:procedure_not_run
  if printf '%s' "$PROCEDURE" | grep -q 'no-autoriza-ejecutar' \
    && [ "${do_transfer:-no}" = no ]; then
    fm_pass live-manual-procedure procedure_not_run \
      "no-autoriza-ejecutar" "no-autoriza-ejecutar (Optional, not run)"
  else
    fm_fail live-manual-procedure procedure_not_run \
      "no-autoriza-ejecutar" "procedure ausente o transfer activo"
  fi
  # assert:procedure_not_run_end
fi

if fm_only live-no-sim-credit; then
  sim_mode="$(python3 - "$skill_root/features/saikit-merge.json" <<'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
d = json.loads(p.read_text(encoding="utf-8")) if p.is_file() else {}
print(d.get("execution_mode") or "")
PY
)"
  fm_action live-no-sim-credit act-sim 3 \
    "simulated=${sim_mode} is not live merge" "merge-happy-path" sim
  # assert:sim_not_live
  if [ "$sim_mode" = simulated ]; then
    fm_pass live-no-sim-credit sim_not_live \
      "simulated not live" "simulated-not-live"
  else
    fm_fail live-no-sim-credit sim_not_live \
      "simulated not live" "saikit-merge mode=${sim_mode}"
  fi
  # assert:sim_not_live_end
  # assert:live_merge
  fm_unknown live-no-sim-credit live_merge \
    "live-merge-not-run" "unknown: live-merge-not-run (sin autorización)"
  # assert:live_merge_end
fi

if fm_only live-no-seal-transfer; then
  fm_action live-no-seal-transfer act-seal 3 \
    "child seal must not move to parent" "merge-happy-path" seal
  parent_blob="$(cat "$LAB/parent/harness-state.env")"
  # assert:parent_seal_untouched
  if printf '%s' "$parent_blob" | grep -q 'veredicto_sha256='; then
    fm_fail live-no-seal-transfer parent_seal_untouched \
      "parent-untouched" "parent received child seal"
  else
    fm_pass live-no-seal-transfer parent_seal_untouched \
      "parent-untouched" "parent-untouched"
  fi
  # assert:parent_seal_untouched_end
  # assert:no_mtime_transfer
  if [ "$do_transfer" = yes ]; then
    fm_fail live-no-seal-transfer no_mtime_transfer \
      "no-mtime-transfer" "transferred by mtime/verified"
  else
    fm_pass live-no-seal-transfer no_mtime_transfer \
      "no-mtime-transfer" "no-mtime-transfer"
  fi
  # assert:no_mtime_transfer_end
  # assert:no_verified_transfer
  if [ "$do_transfer" = yes ]; then
    fm_fail live-no-seal-transfer no_verified_transfer \
      "no-verified-transfer" "transferred because verified: present"
  else
    fm_pass live-no-seal-transfer no_verified_transfer \
      "no-verified-transfer" "no-verified-transfer"
  fi
  # assert:no_verified_transfer_end
fi
