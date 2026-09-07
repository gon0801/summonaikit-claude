#!/usr/bin/env bash
# install-guardian driver — real install-hook.sh assertions (not header/exit).
set -euo pipefail
driver_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_root="$(cd "$driver_dir/../.." && pwd)"
# shellcheck source=../lib/runtime.sh
. "$skill_root/scripts/lib/runtime.sh"
# shellcheck source=../lib/driver.sh
. "$skill_root/scripts/lib/driver.sh"

: "${VERIFY_HOME:?}" "${VERIFY_DEST:?}" "${VERIFY_REPO:?}" "${VERIFY_TMPDIR:?}"
: "${SAIKIT_FM_ATTEMPT_DIR:?}"

INSTALLER="$VERIFY_REPO/tools/install-hook.sh"
HOOK_SRC="$VERIFY_REPO/hooks/summonaikit-harness.sh"
MANIFEST="$VERIFY_REPO/hooks/vendor-manifest.sha256"

run_install() {
  runtime_exec "$VERIFY_HOME" bash "$INSTALLER" "$@"
}

# Literal 1 so the write_on_dry_run mutant can flip it with sed.
SAIKIT_FM_DRY_RUN=1

if fm_only install-dry-run; then
  dry_dest="${SAIKIT_FM_DRY_DEST:-$VERIFY_TMPDIR/fm-install-dry-dest.sh}"
  python3 "$skill_root/scripts/lib/state.py" member \
    --path "$dry_dest" \
    --root "$VERIFY_HOME" \
    --root "$VERIFY_TMPDIR" \
    --label SAIKIT_FM_DRY_DEST \
    --mutate "$(runtime_mutate)" || exit 1
  rm -f "$dry_dest"
  args=(--dest "$dry_dest" --source "$HOOK_SRC" --manifest "$MANIFEST")
  if [ "$SAIKIT_FM_DRY_RUN" = 1 ]; then
    args+=(--dry-run)
  fi
  set +e
  out="$(run_install "${args[@]}" 2>&1)"
  rc=$?
  set -e
  fm_action install-dry-run act-dry "$rc" "$out" bash "$INSTALLER" "${args[@]}"
  if [ "$rc" -eq 0 ]; then
    fm_pass install-dry-run exit_0 "0" "exit $rc"
  else
    fm_fail install-dry-run exit_0 "0" "exit $rc: $out"
  fi
  # assert:dry_run_no_write
  if [ -e "$dry_dest" ]; then
    fm_fail install-dry-run dry_run_no_write "ausente (sin delta)" "wrote $dry_dest"
  else
    fm_pass install-dry-run dry_run_no_write "ausente (sin delta)" "ausente (sin delta)"
  fi
  # assert:dry_run_no_write_end
  if printf '%s' "$out" | grep -q 'procedencia: rama='; then
    ident="$(printf '%s' "$out" | grep -m1 'procedencia: rama=' || true)"
    fm_pass install-dry-run source_identity "procedencia: rama=" "$ident"
  else
    fm_fail install-dry-run source_identity "procedencia: rama=" "$out"
  fi
fi

if fm_only install-ownership; then
  if grep -q 'SAIKIT-CLAUDE-OWNED' "$VERIFY_DEST"; then
    fm_pass install-ownership ownership_marker "SAIKIT-CLAUDE-OWNED" "SAIKIT-CLAUDE-OWNED"
  else
    fm_fail install-ownership ownership_marker "SAIKIT-CLAUDE-OWNED" "marker ausente"
  fi
  src_sha="$(fm_sha "$HOOK_SRC")"
  dst_sha="$(fm_sha "$VERIFY_DEST")"
  if [ "$src_sha" = "$dst_sha" ]; then
    fm_pass install-ownership dest_matches_source "$src_sha" "$dst_sha"
  else
    fm_fail install-ownership dest_matches_source "$src_sha" "$dst_sha"
  fi
fi

if fm_only install-noop; then
  before="$(fm_sha "$VERIFY_DEST")"
  set +e
  out="$(run_install --dest "$VERIFY_DEST" --source "$HOOK_SRC" --manifest "$MANIFEST" 2>&1)"
  rc=$?
  set -e
  fm_action install-noop act-noop "$rc" "$out" bash "$INSTALLER" --dest "$VERIFY_DEST"
  after="$(fm_sha "$VERIFY_DEST")"
  if printf '%s' "$out" | grep -q 'YA AL DIA'; then
    fm_pass install-noop ya_al_dia "YA AL DIA" "YA AL DIA"
  else
    fm_fail install-noop ya_al_dia "YA AL DIA" "$out"
  fi
  if [ "$before" = "$after" ]; then
    fm_pass install-noop dest_unchanged "unchanged" "unchanged $after"
  else
    fm_fail install-noop dest_unchanged "unchanged" "changed $before -> $after"
  fi
fi

if fm_only install-foreign; then
  neighbor="$VERIFY_HOME/.claude/hooks/saikit-foreign-neighbor.sh"
  mkdir -p "$(dirname "$neighbor")"
  printf 'FOREIGN-NEIGHBOR-%s\n' "$$" > "$neighbor"
  n_before="$(fm_sha "$neighbor")"
  set +e
  out="$(run_install --dest "$VERIFY_DEST" --source "$HOOK_SRC" --manifest "$MANIFEST" 2>&1)"
  rc=$?
  set -e
  fm_action install-foreign act-foreign "$rc" "$out" bash "$INSTALLER" --dest "$VERIFY_DEST"
  n_after="$(fm_sha "$neighbor")"
  if [ "$n_before" = "$n_after" ]; then
    fm_pass install-foreign foreign_intact "intact" "intact $n_after"
  else
    fm_fail install-foreign foreign_intact "intact" "changed $n_before -> $n_after"
  fi
fi

if fm_only install-restore; then
  vdest="$VERIFY_TMPDIR/vendor-known.sh"
  target="$VERIFY_TMPDIR/restore-target.sh"
  mani="$VERIFY_TMPDIR/mani-vendor.sha256"
  printf '#!/usr/bin/env bash\n# vendor conocido, sin marcador propio\nexit 0\n' > "$vdest"
  vsha="$(fm_sha "$vdest")"
  cat "$MANIFEST" > "$mani"
  printf '%s  vendor sintetico del drive\n' "$vsha" >> "$mani"
  cp "$vdest" "$target"
  set +e
  out1="$(run_install --dest "$target" --source "$HOOK_SRC" --manifest "$mani" 2>&1)"
  rc1=$?
  out2="$(run_install --dest "$target" --manifest "$mani" --restore-vendor 2>&1)"
  rc2=$?
  set -e
  fm_action install-restore act-install "$rc1" "$out1" bash "$INSTALLER" --dest "$target"
  fm_action install-restore act-restore "$rc2" "$out2" bash "$INSTALLER" --restore-vendor
  if [ "$rc1" -eq 0 ] && [ "$rc2" -eq 0 ] && cmp -s "$target" "$vdest"; then
    fm_pass install-restore restore_vendor_bytes "vendor match" "vendor match $(fm_sha "$target")"
  else
    fm_fail install-restore restore_vendor_bytes "vendor match" \
      "rc1=$rc1 rc2=$rc2 dest=$(fm_sha "$target" 2>/dev/null || echo missing)"
  fi
fi

exit 0
