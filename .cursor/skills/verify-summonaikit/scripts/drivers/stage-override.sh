#!/usr/bin/env bash
# stage-override driver — real tools/stage-override.sh on a disposable lab.
# Never installs override or trust on a live operator session.
set -euo pipefail
driver_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_root="$(cd "$driver_dir/../.." && pwd)"
# shellcheck source=../lib/runtime.sh
. "$skill_root/scripts/lib/runtime.sh"
# shellcheck source=../lib/driver.sh
. "$skill_root/scripts/lib/driver.sh"

: "${VERIFY_HOME:?}" "${VERIFY_DEST:?}" "${VERIFY_REPO:?}" "${VERIFY_TMPDIR:?}"
: "${SAIKIT_FM_ATTEMPT_DIR:?}"

TOOL="$VERIFY_REPO/tools/stage-override.sh"
HOOK="$VERIFY_REPO/hooks/summonaikit-harness.sh"
MANIFEST="$VERIFY_REPO/hooks/vendor-manifest.sha256"
SRC_SHA="$(fm_sha "$HOOK")"

CMD_CON_OVERRIDE='SUMMONAIKIT_HOOK_TARGET=claude SUMMONAIKIT_HOOK_PHASE=prompt bash -c '"'"'h="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/.claude/hooks/summonaikit-harness.sh"; [ -f "$h" ] || h="$HOME/.claude/hooks/summonaikit-harness.sh"; bash "$h"'"'"''

write_settings() {
  python3 - "$1" "$2" <<'PY'
import json, sys
json.dump(
    {"hooks": {"UserPromptSubmit": [{"hooks": [{"type": "command", "command": sys.argv[2]}]}]}},
    open(sys.argv[1], "w", encoding="utf-8"),
)
PY
}

make_lab() {
  local dest="$1"
  rm -rf "$dest"
  mkdir -p "$dest"
  git -c init.defaultBranch=master init -q "$dest"
  git -C "$dest" \
    -c user.email='t@example.invalid' -c user.name='t' \
    -c commit.gpgsign=false \
    commit -q --allow-empty -m 'fixture 19.15'
}

run_stage() {
  local work="$1"
  shift
  runtime_exec "$work" bash "$TOOL" "$@"
}

run_hook() {
  local work="$1" hook="$2" payload="$3"
  printf '%s' "$payload" | runtime_exec "$work" env \
    SUMMONAIKIT_HOOK_TARGET=claude \
    SUMMONAIKIT_HOOK_PHASE=prompt \
    bash "$hook"
}

tree_cksum() {
  local root="$1"
  if [ ! -d "$root" ]; then
    printf 'ausente\n'
    return
  fi
  (cd "$root" && find . -type f | sort | while IFS= read -r f; do
    cksum "$f"
  done)
}

NEED_LAB=0
if fm_only stage-prepare || fm_only stage-hook-hash \
  || fm_only stage-state-lab || fm_only stage-profile-intact \
  || fm_only stage-cleanup || fm_only stage-no-live; then
  NEED_LAB=1
fi

LAB=""
SETTINGS=""
DEST=""
NEIGHBOR=""
KEEP=""
PRIOR=""
SENTINEL=""
STAGE_OUT=""
STAGE_RC=0
PRIOR_SHA=""
NEIGH_SHA=""
KEEP_SHA=""
SENT_SHA=""
GLOBAL_SHA=""
PROFILE_STATE_BEFORE=""

if [ "$NEED_LAB" -eq 1 ]; then
  LAB="$VERIFY_TMPDIR/fm-stage-lab"
  SETTINGS="$VERIFY_TMPDIR/fm-stage-settings.json"
  KEEP="$VERIFY_TMPDIR/fm-stage-foreign-keep"
  make_lab "$LAB"
  write_settings "$SETTINGS" "$CMD_CON_OVERRIDE"
  DEST="$LAB/.claude/hooks/summonaikit-harness.sh"
  mkdir -p "$LAB/.claude/hooks" "$KEEP"
  NEIGHBOR="$LAB/.claude/hooks/neighbor.txt"
  printf 'NEIGHBOR-19.15\n' > "$NEIGHBOR"
  NEIGH_SHA="$(fm_sha "$NEIGHBOR")"
  printf 'KEEP-19.15\n' > "$KEEP/sentinel.txt"
  KEEP_SHA="$(fm_sha "$KEEP/sentinel.txt")"
  proj="$(cd "$LAB" && git rev-parse --show-toplevel)"
  key="$(printf '%s' "$proj" | cksum | cut -d ' ' -f 1)"
  PRIOR="$LAB/.claude/hooks/state/$key"
  mkdir -p "$PRIOR"
  printf 'HARNESS_ARMED=1\nPRIOR=19.15\n' > "$PRIOR/harness-state.env"
  PRIOR_SHA="$(fm_sha "$PRIOR/harness-state.env")"
  mkdir -p "$VERIFY_HOME/.claude/hooks"
  SENTINEL="$VERIFY_HOME/.claude/saikit-synth-profile.txt"
  printf 'SYNTH-PROFILE-19.15\n' > "$SENTINEL"
  SENT_SHA="$(fm_sha "$SENTINEL")"
  GLOBAL_SHA="$(fm_sha "$VERIFY_DEST")"
  PROFILE_STATE_BEFORE="$(tree_cksum "$VERIFY_HOME/.claude/hooks/state")"

  set +e
  STAGE_OUT="$(run_stage "$LAB" "$LAB" \
    --source "$HOOK" --manifest "$MANIFEST" --settings "$SETTINGS" 2>&1)"
  STAGE_RC=$?
  set -e
  fm_action stage-prepare act-stage "$STAGE_RC" "$STAGE_OUT" \
    bash "$TOOL" "$LAB"
fi

if fm_only stage-prepare; then
  if [ "$STAGE_RC" -eq 0 ] && [ -f "$DEST" ] \
    && printf '%s' "$STAGE_OUT" | grep -qi 'MEDIDO'; then
    fm_pass stage-prepare override_installed "MEDIDO dest" \
      "override-installed MEDIDO"
  else
    fm_fail stage-prepare override_installed "MEDIDO dest" \
      "rc=$STAGE_RC dest=$DEST [$STAGE_OUT]"
  fi
  if [ -f "$DEST" ] && [ "$(fm_sha "$DEST")" = "$SRC_SHA" ]; then
    fm_pass stage-prepare dest_matches_source "source sha" \
      "dest-sha=$SRC_SHA"
  else
    got=""
    [ -f "$DEST" ] && got="$(fm_sha "$DEST")"
    fm_fail stage-prepare dest_matches_source "source sha" \
      "want=$SRC_SHA got=$got"
  fi
fi

HOOK_OUT=""
HOOK_RC=0
if fm_only stage-hook-hash || fm_only stage-state-lab \
  || fm_only stage-profile-intact; then
  payload="$(printf '{"session_id":"fm-1915","transcript_path":"","cwd":"%s","hook_event_name":"UserPromptSubmit","permission_mode":"auto","prompt":"medir hash y estado -saikit"}' \
    "$(printf '%s' "$LAB" | sed 's/\\/\\\\/g')")"
  if [ -n "$DEST" ] && [ -f "$DEST" ]; then
    set +e
    HOOK_OUT="$(run_hook "$LAB" "$DEST" "$payload" 2>&1)"
    HOOK_RC=$?
    set -e
  else
    HOOK_RC=2
    HOOK_OUT="dest ausente"
  fi
  fm_action stage-hook-hash act-hook "$HOOK_RC" "hook rc=$HOOK_RC" \
    bash "${DEST:-missing}"
fi

if fm_only stage-hook-hash; then
  ran_sha=""
  [ -f "$DEST" ] && ran_sha="$(fm_sha "$DEST")"
  if [ -n "$ran_sha" ] && [ "$ran_sha" = "$SRC_SHA" ]; then
    fm_pass stage-hook-hash hook_ran_hash "source sha" \
      "hook-hash=$ran_sha"
  else
    fm_fail stage-hook-hash hook_ran_hash "source sha" \
      "want=$SRC_SHA got=$ran_sha rc=$HOOK_RC"
  fi
fi

if fm_only stage-state-lab; then
  lab_session="$(find "$LAB/.claude/hooks/state" -type f -path '*fm-1915*' 2>/dev/null | head -1)"
  # assert:state_in_lab
  if [ -n "$lab_session" ] && [ -f "$lab_session" ]; then
    fm_pass stage-state-lab state_in_lab "state under lab" \
      "state-in-lab $lab_session"
  else
    fm_fail stage-state-lab state_in_lab "state under lab" \
      "no fm-1915 state under $LAB/.claude/hooks/state rc=$HOOK_RC [$HOOK_OUT]"
  fi
  # assert:state_in_lab_end
  after_profile="$(tree_cksum "$VERIFY_HOME/.claude/hooks/state")"
  if [ "$after_profile" = "$PROFILE_STATE_BEFORE" ]; then
    fm_pass stage-state-lab state_not_in_profile "profile state unchanged" \
      "state-not-in-profile"
  else
    fm_fail stage-state-lab state_not_in_profile "profile state unchanged" \
      "profile state changed"
  fi
fi

if fm_only stage-profile-intact; then
  sent_after=""
  glob_after=""
  [ -f "$SENTINEL" ] && sent_after="$(fm_sha "$SENTINEL")"
  [ -f "$VERIFY_DEST" ] && glob_after="$(fm_sha "$VERIFY_DEST")"
  if [ "$sent_after" = "$SENT_SHA" ] && [ "$glob_after" = "$GLOBAL_SHA" ]; then
    fm_pass stage-profile-intact profile_intact "sentinel+global" \
      "profile-intact"
  else
    fm_fail stage-profile-intact profile_intact "sentinel+global" \
      "sent $sent_after vs $SENT_SHA global $glob_after vs $GLOBAL_SHA"
  fi
fi

if fm_only stage-ownership; then
  own="$VERIFY_TMPDIR/fm-stage-own"
  make_lab "$own"
  own_dest="$own/.claude/hooks/summonaikit-harness.sh"
  mkdir -p "$own/.claude/hooks"
  printf '#!/bin/sh\necho FOREIGN-OWN\n' > "$own_dest"
  own_before="$(fm_sha "$own_dest")"
  own_settings="$VERIFY_TMPDIR/fm-stage-own-settings.json"
  write_settings "$own_settings" "$CMD_CON_OVERRIDE"
  set +e
  own_out="$(run_stage "$own" "$own" \
    --source "$HOOK" --manifest "$MANIFEST" --settings "$own_settings" 2>&1)"
  own_rc=$?
  set -e
  fm_action stage-ownership act-own "$own_rc" "$own_out" \
    bash "$TOOL" "$own"
  own_after="$(fm_sha "$own_dest")"
  # assert:ownership_refused
  if [ "$own_rc" -ne 0 ]; then
    fm_pass stage-ownership ownership_refused "nonzero refuse" \
      "ownership-refused rc=$own_rc"
  else
    fm_fail stage-ownership ownership_refused "nonzero refuse" \
      "rc=0 overwrote [$own_out]"
  fi
  # assert:ownership_refused_end
  if [ "$own_before" = "$own_after" ]; then
    fm_pass stage-ownership foreign_intact "same dest bytes" \
      "foreign-intact"
  else
    fm_fail stage-ownership foreign_intact "same dest bytes" \
      "before=$own_before after=$own_after"
  fi
fi

if fm_only stage-cleanup; then
  prior_after=""
  [ -f "$PRIOR/harness-state.env" ] && prior_after="$(fm_sha "$PRIOR/harness-state.env")"
  neigh_after=""
  [ -f "$NEIGHBOR" ] && neigh_after="$(fm_sha "$NEIGHBOR")"
  keep_after=""
  [ -f "$KEEP/sentinel.txt" ] && keep_after="$(fm_sha "$KEEP/sentinel.txt")"
  # assert:cleanup_scoped
  if [ "$prior_after" = "$PRIOR_SHA" ] \
    && [ "$neigh_after" = "$NEIGH_SHA" ] \
    && [ "$keep_after" = "$KEEP_SHA" ]; then
    fm_pass stage-cleanup cleanup_scoped "prior+neighbor+keep" \
      "cleanup-scoped"
  else
    fm_fail stage-cleanup cleanup_scoped "prior+neighbor+keep" \
      "prior=$prior_after neigh=$neigh_after keep=$keep_after"
  fi
  # assert:cleanup_scoped_end
fi

if fm_only stage-no-live; then
  live=1
  case "$DEST" in
    "$VERIFY_TMPDIR"/*) live=0 ;;
  esac
  case "$SETTINGS" in
    "$VERIFY_TMPDIR"/*) ;;
    *) live=1 ;;
  esac
  if [ "$DEST" = "$VERIFY_DEST" ]; then
    live=1
  fi
  if [ -e "$VERIFY_HOME/.claude/trusted_folders.toml" ]; then
    live=1
  fi
  if [ "$live" -eq 0 ] && [ "$DEST" != "$VERIFY_DEST" ]; then
    fm_pass stage-no-live no_live_session "fixture temp only" \
      "no-live-session dest-under-tmp"
  else
    fm_fail stage-no-live no_live_session "fixture temp only" \
      "dest=$DEST settings=$SETTINGS verify_dest=$VERIFY_DEST"
  fi
fi

exit 0
