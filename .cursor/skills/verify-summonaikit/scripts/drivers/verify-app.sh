#!/usr/bin/env bash
# verify-app driver — real verificar.sh on a disposable fixture.
# Never writes the checkout verify/. Skill PASS is not product verify PASS.
set -euo pipefail
driver_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_root="$(cd "$driver_dir/../.." && pwd)"
# shellcheck source=../lib/runtime.sh
. "$skill_root/scripts/lib/runtime.sh"
# shellcheck source=../lib/driver.sh
. "$skill_root/scripts/lib/driver.sh"

: "${VERIFY_HOME:?}" "${VERIFY_REPO:?}" "${VERIFY_TMPDIR:?}"
: "${SAIKIT_FM_ATTEMPT_DIR:?}"

SCRIPT="$VERIFY_REPO/skills/saikit-verificar-app/verificar.sh"
HOOK="$VERIFY_REPO/hooks/summonaikit-harness.sh"
CHECKOUT_VERIFY="$VERIFY_REPO/verify"

checkout_tree() {
  (cd "$CHECKOUT_VERIFY" && cksum *)
}

CHECKOUT_BEFORE="$(checkout_tree)"

run_verificar() {
  local work="$1"
  shift
  runtime_exec "$work" env \
    SAIKIT_HOOK_VIVO="$HOOK" \
    bash "$SCRIPT" "$@"
}

make_node_fixture() {
  local dest="$1"
  rm -rf "$dest"
  mkdir -p "$dest"
  printf 'console.log("Entraste. Bienvenido.");\n' > "$dest/app.js"
  cat > "$dest/package.json" <<'EOF'
{ "name": "app-node", "scripts": { "test": "node --test" } }
EOF
  git -C "$dest" init -q
  git -C "$dest" config user.email "test@local.example"
  git -C "$dest" config user.name "test"
  git -C "$dest" add -A
  git -C "$dest" commit -qm "fixture"
  git -C "$dest" rev-parse HEAD
}

NEED_FIXTURE=0
if fm_only verify-generate || fm_only verify-reject-existing \
  || fm_only verify-estado || fm_only verify-drive-cmd; then
  NEED_FIXTURE=1
fi

WORK=""
SHA=""
GEN_OUT=""
GEN_RC=0
if [ "$NEED_FIXTURE" -eq 1 ]; then
  WORK="$VERIFY_TMPDIR/fm-verify-app"
  SHA="$(make_node_fixture "$WORK")"
  set +e
  GEN_OUT="$(run_verificar "$WORK" generar "$WORK" 2>&1)"
  GEN_RC=$?
  set -e
  fm_action verify-generate act-generar "$GEN_RC" "$GEN_OUT" \
    bash "$SCRIPT" generar "$WORK"
fi

if fm_only verify-generate; then
  missing=""
  for f in LEEME.md Launch.md Doctor.md Drive.md Evidence.txt Cleanup.md \
    drive.test.cjs; do
    if [ ! -f "$WORK/verify/$f" ]; then
      missing="$missing $f"
    fi
  done
  if [ -z "$missing" ] && [ "$GEN_RC" -eq 0 ]; then
    fm_pass verify-generate files_present "LEEME.md + map files" \
      "LEEME.md Launch.md Doctor.md Drive.md Evidence.txt Cleanup.md drive.test.cjs"
  else
    fm_fail verify-generate files_present "LEEME.md + map files" \
      "rc=$GEN_RC missing=[$missing] [$GEN_OUT]"
  fi
  sello="$(sed -n 's/^generado:[[:space:]]*//p' "$WORK/verify/LEEME.md" 2>/dev/null | head -n 1)"
  sello_sha="$(printf '%s' "${sello##*·}" | sed 's/[[:space:]]//g')"
  if [ -n "$sello_sha" ] && [ "$sello_sha" = "$SHA" ]; then
    fm_pass verify-generate seal_real_sha "fixture HEAD" "seal-sha=$sello_sha"
  else
    fm_fail verify-generate seal_real_sha "fixture HEAD" \
      "want=$SHA got=$sello_sha sello=[$sello]"
  fi
fi

if fm_only verify-reject-existing; then
  leeme="$WORK/verify/LEEME.md"
  before=""
  [ -f "$leeme" ] && before="$(fm_sha "$leeme")"
  set +e
  rej_out="$(run_verificar "$WORK" generar "$WORK" 2>&1)"
  rej_rc=$?
  set -e
  fm_action verify-reject-existing act-regen "$rej_rc" "$rej_out" \
    bash "$SCRIPT" generar "$WORK"
  # assert:reject_existing
  if [ "$rej_rc" -ne 0 ]; then
    fm_pass verify-reject-existing reject_existing "nonzero reject" \
      "reject-existing rc=$rej_rc"
  else
    fm_fail verify-reject-existing reject_existing "nonzero reject" \
      "rc=0 overwrote [$rej_out]"
  fi
  # assert:reject_existing_end
  after=""
  [ -f "$leeme" ] && after="$(fm_sha "$leeme")"
  if [ -n "$before" ] && [ "$before" = "$after" ]; then
    fm_pass verify-reject-existing files_intact "same LEEME bytes" \
      "files-intact"
  else
    fm_fail verify-reject-existing files_intact "same LEEME bytes" \
      "before=$before after=$after"
  fi
fi

if fm_only verify-estado; then
  set +e
  est_ok="$(run_verificar "$WORK" estado "$WORK" 2>&1)"
  est_ok_rc=$?
  set -e
  fm_action verify-estado act-al-dia "$est_ok_rc" "$est_ok" \
    bash "$SCRIPT" estado "$WORK"
  if [ "$est_ok" = "al_dia" ]; then
    fm_pass verify-estado estado_al_dia "al_dia" "al_dia"
  else
    fm_fail verify-estado estado_al_dia "al_dia" "got=[$est_ok] rc=$est_ok_rc"
  fi
  printf '// drift no medido\n' >> "$WORK/app.js"
  git -C "$WORK" add -A
  git -C "$WORK" commit -qm "drift"
  set +e
  est_drift="$(run_verificar "$WORK" estado "$WORK" 2>&1)"
  est_drift_rc=$?
  set -e
  fm_action verify-estado act-drift "$est_drift_rc" "$est_drift" \
    bash "$SCRIPT" estado "$WORK"
  # assert:estado_desactualizado
  if [ "$est_drift" = "desactualizado" ]; then
    fm_pass verify-estado estado_desactualizado "desactualizado" \
      "desactualizado"
  else
    fm_fail verify-estado estado_desactualizado "desactualizado" \
      "got=[$est_drift] rc=$est_drift_rc"
  fi
  # assert:estado_desactualizado_end
fi

if fm_only verify-drive-cmd; then
  cmd="$(sed -n 's/^COMANDO_DRIVE:[[:space:]]*//p' "$WORK/verify/Drive.md" 2>/dev/null | head -n 1)"
  re="$(sed -n "s/^TEST_RUNNER_RE='//p" "$HOOK" | sed "s/'$//")"
  fm_action verify-drive-cmd act-cmd 0 "$cmd" bash "$SCRIPT" generar
  if printf '%s' "$cmd" | grep -q 'verify/'; then
    fm_pass verify-drive-cmd drive_cmd_verify "includes verify/" \
      "verify/ cmd=[$cmd]"
  else
    fm_fail verify-drive-cmd drive_cmd_verify "includes verify/" \
      "cmd=[$cmd]"
  fi
  # assert:drive_cmd_runner
  if [ -n "$re" ] && [ -n "$cmd" ] \
    && printf '%s' "$cmd" | grep -Eo "$re" >/dev/null; then
    fm_pass verify-drive-cmd drive_cmd_runner "TEST_RUNNER_RE" \
      "runner-re cmd=[$cmd]"
  else
    fm_fail verify-drive-cmd drive_cmd_runner "TEST_RUNNER_RE" \
      "re=[$re] cmd=[$cmd]"
  fi
  # assert:drive_cmd_runner_end
fi

if fm_only verify-no-product-pass; then
  fm_pass verify-no-product-pass no_product_verify_pass \
    "skill PASS != product verify PASS" \
    "skill-pass-not-product-verify"
  after="$(checkout_tree)"
  if [ "$after" = "$CHECKOUT_BEFORE" ]; then
    fm_pass verify-no-product-pass checkout_verify_intact \
      "checkout verify/ bytes" "checkout-verify-intact"
  else
    fm_fail verify-no-product-pass checkout_verify_intact \
      "checkout verify/ bytes" "checkout verify/ changed"
  fi
fi

exit 0
