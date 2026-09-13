#!/usr/bin/env bash
# check-secrets driver — real tools/check-secrets.sh on disposable fixtures.
# Strong detector when gitleaks is present; otherwise unknown (never a fake PASS).
# Fallback warning/limit are asserted only when that engine can be forced.
set -euo pipefail
driver_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_root="$(cd "$driver_dir/../.." && pwd)"
# shellcheck source=../lib/runtime.sh
. "$skill_root/scripts/lib/runtime.sh"
# shellcheck source=../lib/driver.sh
. "$skill_root/scripts/lib/driver.sh"

: "${VERIFY_HOME:?}" "${VERIFY_REPO:?}" "${VERIFY_TMPDIR:?}"
: "${SAIKIT_FM_ATTEMPT_DIR:?}"

TOOL="$VERIFY_REPO/tools/check-secrets.sh"
fm_unknown() { fm_assert "$1" "$2" unknown "$3" "$4"; }

synth_secret() {
  if [ -n "${SAIKIT_FM_SYNTH_SECRET:-}" ]; then
    printf '%s' "$SAIKIT_FM_SYNTH_SECRET"
    return
  fi
  printf '%s%s%s' 'ghp_' 'ABCDEF1234567890abcd' 'efABCDEF1234567890'
}

find_gitleaks() {
  if [ -n "${SAIKIT_GITLEAKS:-}" ] && [ -x "$SAIKIT_GITLEAKS" ]; then
    printf '%s' "$SAIKIT_GITLEAKS"
    return 0
  fi
  if command -v gitleaks >/dev/null 2>&1; then
    command -v gitleaks
    return 0
  fi
  if [ -x /tmp/gitleaks-bin/gitleaks.exe ]; then
    printf '%s' /tmp/gitleaks-bin/gitleaks.exe
    return 0
  fi
  return 1
}

can_force_fallback() {
  if [ -x /usr/bin/gitleaks ] || [ -x /bin/gitleaks ]; then
    return 1
  fi
  return 0
}

run_tool() {
  local extra=()
  if [ -n "${SAIKIT_GITLEAKS:-}" ] && [ -x "${SAIKIT_GITLEAKS}" ]; then
    extra+=(env "SAIKIT_GITLEAKS=$SAIKIT_GITLEAKS")
  fi
  runtime_exec "$VERIFY_HOME" ${extra[@]+"${extra[@]}"} bash "$TOOL" "$@"
}

run_fallback() {
  runtime_exec "$VERIFY_HOME" env -u SAIKIT_GITLEAKS PATH="/usr/bin:/bin" \
    bash "$TOOL" "$@"
}

contains_synth() {
  local hay="$1"
  case "$hay" in
    *"$SYNTH"*) return 0 ;;
    *) return 1 ;;
  esac
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

SYNTH="$(synth_secret)"
WORKDIR="$VERIFY_TMPDIR/fm-secrets"
mkdir -p "$WORKDIR"
CLEAN="$WORKDIR/limpio.sh"
TRAPF="$WORKDIR/trampa.txt"
COMMENT="$WORKDIR/comentario_clave.txt"
printf 'echo "listo"\ncp a b\n' > "$CLEAN"
printf 'GITHUB_TOKEN=%s\n' "$SYNTH" > "$TRAPF"
kw="$(printf 'access_%s' 'key')"
v1='z9y8x7w6v5u4t3s2'
v2='r1q0'
printf '# la %s se roto: %s\n' "$kw" "${v1}${v2}" > "$COMMENT"

if fm_only secrets-strong; then
  gl=""
  if find_gitleaks >/dev/null; then
    gl="$(find_gitleaks)"
  fi
  if [ -n "$gl" ]; then
    set +e
    clean_out="$(SAIKIT_GITLEAKS="$gl" run_tool "$CLEAN" 2>&1)"
    clean_rc=$?
    trap_out="$(SAIKIT_GITLEAKS="$gl" run_tool "$TRAPF" 2>&1)"
    trap_rc=$?
    set -e
    fm_action secrets-strong act-clean "$clean_rc" "clean rc=$clean_rc" bash "$TOOL" "$CLEAN"
    fm_action secrets-strong act-trap "$trap_rc" "trap rc=$trap_rc file:line" bash "$TOOL" "$TRAPF"
    # assert:strong_clean
    if [ "$clean_rc" -eq 0 ]; then
      fm_pass secrets-strong strong_clean "limpio exit 0" "limpio clean exit 0"
    else
      fm_fail secrets-strong strong_clean "limpio exit 0" "exit $clean_rc"
    fi
    # assert:strong_clean_end
    # assert:strong_trap
    if [ "$trap_rc" -eq 1 ]; then
      fm_pass secrets-strong strong_trap "trampa exit 1" "trampa trap exit 1"
    else
      fm_fail secrets-strong strong_trap "trampa exit 1" "exit $trap_rc"
    fi
    # assert:strong_trap_end
    STRONG_TRAP_OUT="$trap_out"
  else
    fm_action secrets-strong act-missing 3 "sin gitleaks" bash "$TOOL"
    fm_unknown secrets-strong strong_clean "gitleaks limpio" \
      "unknown: sin detector fuerte (fallback no acredita motor fuerte)"
    fm_unknown secrets-strong strong_trap "gitleaks trampa" \
      "unknown: sin detector fuerte (fallback no acredita motor fuerte)"
    STRONG_TRAP_OUT=""
  fi
fi

if fm_only secrets-fallback; then
  if can_force_fallback; then
    set +e
    fb_trap="$(run_fallback "$TRAPF" 2>&1)"
    fb_trap_rc=$?
    fb_lim="$(run_fallback "$COMMENT" 2>&1)"
    fb_lim_rc=$?
    set -e
    fm_action secrets-fallback act-fb-trap "$fb_trap_rc" "fallback trap rc=$fb_trap_rc" \
      bash "$TOOL" fallback-trap
    fm_action secrets-fallback act-fb-lim "$fb_lim_rc" "fallback limit rc=$fb_lim_rc" \
      bash "$TOOL" fallback-limit
    # assert:fallback_warning
    if printf '%s' "$fb_trap$fb_lim" | grep -q 'AVISO' \
      && printf '%s' "$fb_trap$fb_lim" | grep -q 'sin gitleaks' \
      && printf '%s' "$fb_trap$fb_lim" | grep -qi 'veredicto'; then
      fm_pass secrets-fallback fallback_warning "AVISO sin gitleaks veredicto" \
        "AVISO sin gitleaks NO es el veredicto"
    else
      fm_fail secrets-fallback fallback_warning "AVISO sin gitleaks veredicto" \
        "aviso ausente"
    fi
    # assert:fallback_warning_end
    if [ "$fb_lim_rc" -eq 0 ] \
      && printf '%s' "$fb_lim" | grep -q 'sin gitleaks' \
      && printf '%s' "$fb_lim" | grep -qi 'veredicto'; then
      fm_pass secrets-fallback fallback_limit "limite declarado" \
        "sin gitleaks NO es el veredicto (limite)"
    else
      fm_fail secrets-fallback fallback_limit "limite declarado" \
        "rc=$fb_lim_rc"
    fi
    FALLBACK_TRAP_OUT="$fb_trap"
  else
    fm_action secrets-fallback act-unforced 3 "gitleaks en /usr/bin|/bin" bash "$TOOL"
    fm_unknown secrets-fallback fallback_warning "AVISO fallback" \
      "unknown: no se pudo forzar fallback (gitleaks en /usr/bin o /bin)"
    fm_unknown secrets-fallback fallback_limit "limite fallback" \
      "unknown: no se pudo forzar fallback (gitleaks en /usr/bin o /bin)"
    FALLBACK_TRAP_OUT=""
  fi
fi

if fm_only secrets-redaction; then
  report=""
  if [ -n "${STRONG_TRAP_OUT:-}" ]; then
    report="$STRONG_TRAP_OUT"
  elif [ -n "${FALLBACK_TRAP_OUT:-}" ]; then
    report="$FALLBACK_TRAP_OUT"
  else
    set +e
    if find_gitleaks >/dev/null; then
      report="$(SAIKIT_GITLEAKS="$(find_gitleaks)" run_tool "$TRAPF" 2>&1)"
    elif can_force_fallback; then
      report="$(run_fallback "$TRAPF" 2>&1)"
    else
      report="$(run_tool "$TRAPF" 2>&1)"
    fi
    set -e
  fi
  fm_action secrets-redaction act-report 1 "reporte file:line" bash "$TOOL" trap
  if contains_synth "$report"; then
    fm_fail secrets-redaction report_no_secret "sin valor en reporte" \
      "valor sintetico en salida"
  else
    fm_pass secrets-redaction report_no_secret "sin valor en reporte" \
      "sin valor redact ausente"
  fi
  # assert:evidence_no_secret
  set +e
  scan_obs="$(scan_attempt 2>&1)"
  scan_rc=$?
  set -e
  if [ "$scan_rc" -eq 0 ]; then
    fm_pass secrets-redaction evidence_no_secret "cero coincidencias" \
      "cero coincidencias ausente"
  else
    fm_fail secrets-redaction evidence_no_secret "cero coincidencias" \
      "secreto en evidencia"
  fi
  # assert:evidence_no_secret_end
fi

exit 0
