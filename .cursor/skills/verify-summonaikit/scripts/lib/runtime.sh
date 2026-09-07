#!/usr/bin/env bash
# runtime.sh — aislamiento del verify-summonaikit.
# Se sourcea como biblioteca. Nunca hace source/eval del estado del run.
# Mutaciones (SAIKIT_VERIFY_MUTATE): skip_physical_path, skip_env_sanitize,
# skip_cwd_isolation, skip_cleanup_ownership.

runtime_mutate() { printf '%s' "${SAIKIT_VERIFY_MUTATE:-}"; }

iso_fail() {
  printf 'control-summonaikit: %s\n' "$*" >&2
  exit 1
}

runtime_json_get() {
  printf '%s' "${_STATE_JSON:-}" | python3 -c \
    'import json,sys; print(json.load(sys.stdin)[sys.argv[1]])' "$1"
}

runtime_json_get_opt() {
  printf '%s' "${_STATE_JSON:-}" | python3 -c \
    'import json,sys; print(json.load(sys.stdin).get(sys.argv[1]) or "")' "$1"
}

runtime_preflight_launch() {
  python3 "$STATEPY" preflight \
    --state-dir "$STATE_DIR" \
    --artifacts "$ARTIFACTS" \
    --mutate "$(runtime_mutate)" \
    || exit 1
}

runtime_load() {
  local mode="${1:-drive}"
  local err
  err="$(mktemp "${TMPDIR:-/tmp}/saikit-state-err-XXXXXX")"
  if ! _STATE_JSON="$(
    python3 "$STATEPY" load \
      --state-dir "$STATE_DIR" \
      --artifacts "$ARTIFACTS" \
      --repo "$repo" \
      --mode "$mode" \
      --mutate "$(runtime_mutate)" 2>"$err"
  )"; then
    cat "$err" >&2
    rm -f "$err"
    exit 1
  fi
  rm -f "$err"
  VERIFY_HOME="$(runtime_json_get verify_home)"
  VERIFY_DEST="$(runtime_json_get dest)"
  VERIFY_RUN_ID="$(runtime_json_get run_id)"
  VERIFY_REPO="$(runtime_json_get repo)"
  VERIFY_TMPDIR="$(runtime_json_get tmpdir)"
  VERIFY_TOKEN="$(runtime_json_get token)"
  VERIFY_DISPOSABLE="$(runtime_json_get_opt disposable_repo)"
  export VERIFY_HOME VERIFY_DEST VERIFY_RUN_ID VERIFY_REPO VERIFY_TMPDIR
}

# Subproceso con entorno construido. cwd ($1) + comando.
runtime_exec() {
  local cwd="$1"; shift
  local tmp="${VERIFY_TMPDIR:-${VERIFY_HOME}/tmp}"
  mkdir -p "$tmp" 2>/dev/null || true
  if [ "$(runtime_mutate)" = skip_env_sanitize ]; then
    export HOME="$VERIFY_HOME"
    export USERPROFILE="$VERIFY_HOME"
    export TMPDIR="$tmp"
    export TMP="$tmp"
    export TEMP="$tmp"
    ( cd "$cwd" && "$@" )
    return $?
  fi
  (
    cd "$cwd" || exit 1
    env -i \
      HOME="$VERIFY_HOME" \
      USERPROFILE="$VERIFY_HOME" \
      PATH="$PATH" \
      TMPDIR="$tmp" \
      TMP="$tmp" \
      TEMP="$tmp" \
      XDG_CONFIG_HOME="$VERIFY_HOME/.config" \
      XDG_DATA_HOME="$VERIFY_HOME/.local/share" \
      XDG_CACHE_HOME="$VERIFY_HOME/.cache" \
      XDG_STATE_HOME="$VERIFY_HOME/.local/state" \
      LANG="${LANG:-C}" \
      LC_ALL="${LC_ALL:-}" \
      LC_CTYPE="${LC_CTYPE:-}" \
      USER="${USER:-}" \
      LOGNAME="${LOGNAME:-}" \
      TERM="${TERM:-dumb}" \
      TZ="${TZ:-}" \
      "$@"
  )
}

runtime_write_marker() {
  local dir="$1" run_id="$2" token="$3"
  printf 'run_id=%s\ntoken=%s\n' "$run_id" "$token" > "$dir/.saikit-run"
  chmod 600 "$dir/.saikit-run"
}

runtime_save_state() {
  local payload="$1"
  python3 "$STATEPY" save --state-dir "$STATE_DIR" --payload "$payload" \
    || iso_fail "no se pudo persistir state.json"
}

runtime_cli_ok() {
  python3 "$STATEPY" cli-ok \
    --catalog "$CATALOG" \
    --repo "$VERIFY_REPO" \
    --cwd "$PWD" \
    --disposable "${VERIFY_DISPOSABLE:-}" \
    --home "${VERIFY_HOME:-}" \
    --owned-temp "${VERIFY_HOME:-}" \
    --owned-temp "${VERIFY_TMPDIR:-}" \
    --mutate "$(runtime_mutate)" \
    -- "$@"
}

runtime_cleanup_home() {
  local home="$1"
  if [ "$(runtime_mutate)" = skip_cleanup_ownership ]; then
    case "$home" in
      /tmp/*|"${TMPDIR:-/tmp}"/*)
        rm -rf "$home"
        printf 'cleanup: removed VERIFY_HOME=%s\n' "$home"
        return 0
        ;;
      *)
        iso_fail "temporal no es propio de este run (prefijo tmp)"
        ;;
    esac
  fi
  if [ ! -d "$home" ]; then
    printf 'cleanup: VERIFY_HOME already gone\n'
    return 0
  fi
  # load ya exigió marker; borrar solo ese árbol.
  rm -rf "$home"
  printf 'cleanup: removed VERIFY_HOME=%s\n' "$home"
}

runtime_clear_state_files() {
  python3 "$STATEPY" member \
    --path "$STATE_DIR" \
    --label STATE \
    --mutate "$(runtime_mutate)" \
    >/dev/null 2>&1 || return 1
  rm -f "$STATE_DIR/state.json" "$STATE_DIR/state.json.tmp"
  rmdir "$STATE_DIR/.active" 2>/dev/null || true
  rmdir "$STATE_DIR" 2>/dev/null || true
}
