#!/usr/bin/env bash
# tests/test_feature_map_verify_app.sh — 19.14: generación/estado verify-app.
#
# DoD: generar verify/ solo en fixture nuevo; regenerar rechaza y deja
# archivos previos intactos; estado distingue sello vigente vs deriva;
# mutantes rechazo / comparación de sello / comando Drive; verify/ del
# checkout preservado. PASS de la skill no acredita verify/ del producto.
#
# Mutaciones (copia del driver; SAIKIT_FM_DRIVER):
#   omit_reject_existing  — quita reject_existing
#   omit_seal_compare     — quita estado_desactualizado
#   omit_drive_cmd        — quita drive_cmd_runner
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
. "$here/lib/sandbox.sh"; sandbox_init
fail=0
caso() { printf '  caso: %s\n' "$1"; }
malo() { printf '    FAIL: %s\n' "$1" >&2; fail=$((fail + 1)); }

SKILL="$repo/.cursor/skills/verify-summonaikit"
CTRL="$SKILL/scripts/control-summonaikit"
DRV="$SKILL/scripts/drivers/verify-app.sh"
STATE="$SANDBOX/verify-state"
ART="$SANDBOX/verify-artifacts"
mkdir -p "$STATE" "$ART"
. "$here/lib/feature_map_mut.sh"

CHECKOUT_LEEME="$repo/verify/LEEME.md"
CHECKOUT_HASH_BEFORE=""
if [ -f "$CHECKOUT_LEEME" ]; then
  CHECKOUT_HASH_BEFORE="$(cksum "$CHECKOUT_LEEME")"
fi

ctrl() {
  SAIKIT_VERIFY_STATE="$STATE" SAIKIT_VERIFY_ARTIFACTS="$ART" \
    SAIKIT_HOOK_VIVO="$repo/hooks/summonaikit-harness.sh" \
    bash "$CTRL" "$@"
}


latest_summary() {
  local fid="$1"
  find "$ART" -path "*/*/${fid}/*/summary.json" -type f | tail -1
}

latest_steps() {
  local sum
  sum="$(latest_summary "$1")"
  [ -n "$sum" ] || return 1
  printf '%s' "$(dirname "$sum")/steps.jsonl"
}

assert_obs() {
  local fid="$1" asid="$2" pat="$3"
  local steps
  steps="$(latest_steps "$fid")" || { malo "$fid: sin steps para $asid"; return; }
  python3 - "$steps" "$asid" "$pat" <<'PY' || malo "$fid: $asid no observa [$pat]"
import json, re, sys
steps, asid, pat = sys.argv[1], sys.argv[2], sys.argv[3]
found = None
for line in open(steps, encoding="utf-8"):
    if not line.strip():
        continue
    rec = json.loads(line)
    if rec.get("type") == "assertion" and rec.get("assertion_id") == asid:
        found = rec
if found is None:
    raise SystemExit(f"falta aserción {asid}")
obs = str(found.get("observed") or "")
if found.get("result") != "PASS":
    raise SystemExit(f"{asid} result={found.get('result')} obs={obs!r}")
if not re.search(pat, obs):
    raise SystemExit(f"{asid} observed no coincide {pat!r}: {obs!r}")
PY
}


reset_art() { rm -rf "$ART"; mkdir -p "$ART"; }

copy_driver() {
  cp "$DRV" "$1"
  chmod +x "$1"
}


# ---------------------------------------------------------------------------
# Inventario: pending→active, resto intacto, README
# ---------------------------------------------------------------------------
caso "catalogo activa verify-app y conserva las demas"
python3 - "$SKILL" <<'PY' || malo "catalogo/descriptor verify-app incompleto"
import json, sys
from pathlib import Path
skill = Path(sys.argv[1])
cat = json.loads((skill / "features/catalog.json").read_text())
feats = cat.get("features") or {}
meta = feats.get("verify-app") or {}
assert meta.get("status") == "active", meta
assert meta.get("card"), meta
assert not meta.get("owner_task"), ("pending leftover", meta)
desc = json.loads((skill / "features/verify-app.json").read_text())
ex = desc.get("executor") or {}
assert ex.get("kind") == "driver", ex
path = ex.get("path") or "scripts/drivers/verify-app.sh"
assert (skill / path).is_file(), path
assert (skill / "features/verify-app.md").is_file()
ids = [c.get("id") for c in (desc.get("cases") or [])]
for need in (
    "verify-generate", "verify-reject-existing", "verify-estado",
    "verify-drive-cmd", "verify-no-product-pass",
):
    assert need in ids, (need, ids)
for c in desc.get("cases") or []:
    assert c.get("required_assertions"), c
# resto: no tocar otras features
# Otras features: no exigir pending de filas ya mergeadas/activadas en serie.
for fid, want in (
    ("check-secrets", "active"),
    ("capture-payloads", "active"),
    ("decision-blast", "active"),
    ("stage-override", "active"),
    ("merge-happy-path", "blocked"),
    ("install-guardian", "active"),
    ("routing-recipes", "active"),
    ("verify-app", "active"),
):
    st = (feats.get(fid) or {}).get("status")
    assert st == want, (fid, st, want)
readme = (skill / "features/README.md").read_text(encoding="utf-8")
assert "verify-app.md" in readme, "README sin linea de verify-app"
PY
[ -f "$DRV" ] || malo "falta drivers/verify-app.sh"
[ -f "$SKILL/features/verify-app.md" ] || malo "falta ficha verify-app.md"
if [ -f "$DRV" ]; then
  bash -n "$DRV" || malo "bash -n fallo en verify-app.sh"
fi

caso "list-features declara verify-app active sandbox"
out="$(ctrl list-features 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 0 ] || malo "list-features fallo: $out"
printf '%s' "$out" | grep -E 'id=verify-app' | grep -q 'status=active' \
  || malo "list-features no activa verify-app: $out"

# ---------------------------------------------------------------------------
# Launch aislado
# ---------------------------------------------------------------------------
caso "launch aislado para drive verify-app"
if ! out="$(ctrl launch 2>&1)"; then
  malo "launch fallo: $out"
  echo "FAIL: $fail aserciones (sin launch no hay drives)" >&2
  exit 1
fi
printf '%s' "$out" | grep -q 'launched run_id=' || malo "launch sin run_id: $out"

# ---------------------------------------------------------------------------
# Drive real
# ---------------------------------------------------------------------------
caso "drive verify-app: generar, rechazo, estado, Drive, no product PASS"
reset_art
out="$(ctrl drive verify-app 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 0 ] || malo "drive verify-app rc=$rc: $out"

sum="$(latest_summary verify-app)"
[ -n "$sum" ] && [ -f "$sum" ] || malo "verify-app sin summary"
if [ -n "$sum" ] && [ -f "$sum" ]; then
python3 - "$sum" <<'PY' || malo "verify-app summary incompleto"
import json, sys
s = json.loads(open(sys.argv[1], encoding="utf-8").read())
assert s.get("result") == "PASS" and s.get("exit_code") == 0, s
cases = s.get("cases") or s.get("cases_requested") or []
text = " ".join(cases) if not isinstance(cases, str) else cases
for need in (
    "verify-generate", "verify-reject-existing", "verify-estado",
    "verify-drive-cmd", "verify-no-product-pass",
):
    assert need in text, (need, cases)
PY
fi

assert_obs verify-app files_present 'LEEME.md'
assert_obs verify-app seal_real_sha 'seal-sha='
assert_obs verify-app reject_existing 'reject-existing'
assert_obs verify-app files_intact 'files-intact'
assert_obs verify-app estado_al_dia 'al_dia'
assert_obs verify-app estado_desactualizado 'desactualizado'
assert_obs verify-app drive_cmd_verify 'verify/'
assert_obs verify-app drive_cmd_runner 'runner-re'
assert_obs verify-app no_product_verify_pass 'skill-pass-not-product-verify'
assert_obs verify-app checkout_verify_intact 'checkout-verify-intact'

# ---------------------------------------------------------------------------
# verify/ del checkout intacto (no se refresco el sello)
# ---------------------------------------------------------------------------
caso "verify/ del checkout no se toco"
if [ -n "$CHECKOUT_HASH_BEFORE" ]; then
  after="$(cksum "$CHECKOUT_LEEME")"
  [ "$after" = "$CHECKOUT_HASH_BEFORE" ] \
    || malo "el drive refresco verify/LEEME.md del checkout"
fi
if ! git -C "$repo" diff --quiet -- verify/; then
  malo "git diff detecto cambios en verify/ del checkout"
fi

# ---------------------------------------------------------------------------
# 20.28: un directorio en verify/ no tumba el hash (solo archivos regulares)
# ---------------------------------------------------------------------------
caso "directorio plantado en verify/ no tumba checkout_verify_intact"
PLANT_DIR="$repo/verify/.saikit-planted-dir-20.28"
mkdir -p "$PLANT_DIR"
reset_art
out="$(ctrl drive verify-app 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 0 ] || malo "drive verify-app con dir plantado rc=$rc: $out"
assert_obs verify-app checkout_verify_intact 'checkout-verify-intact'
rmdir "$PLANT_DIR" 2>/dev/null || rm -rf "$PLANT_DIR"

# ---------------------------------------------------------------------------
# Encabezado falso + rc 0 no acredita rechazo/sello/Drive
# ---------------------------------------------------------------------------
caso "encabezado falso con rc 0 no acredita rechazo ni sello ni Drive"
reset_art
stub="$SANDBOX/header-only-verify-app.sh"
cat > "$stub" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
EVID="${SAIKIT_FM_EVIDENCE:?}"
adir="${SAIKIT_FM_ATTEMPT_DIR:?}"
assert() {
  python3 "$EVID" append-step --attempt-dir "$adir" --type assertion \
    --case-id "$1" --step-id "s-$2" --assertion-id "$2" \
    --expected "$2" --observed "$3" --result PASS
}
assert verify-generate files_present "ok"
assert verify-generate seal_real_sha "ok"
assert verify-reject-existing reject_existing "ok"
assert verify-reject-existing files_intact "ok"
assert verify-estado estado_al_dia "ok"
assert verify-estado estado_desactualizado "ok"
assert verify-drive-cmd drive_cmd_verify "ok"
assert verify-drive-cmd drive_cmd_runner "ok"
assert verify-no-product-pass no_product_verify_pass "ok"
assert verify-no-product-pass checkout_verify_intact "ok"
exit 0
EOF
chmod +x "$stub"
ctrl_drv "$stub" drive verify-app >/dev/null 2>&1 || true
steps="$(latest_steps verify-app)"
if [ -n "$steps" ] && [ -f "$steps" ]; then
python3 - "$steps" <<'PY' || malo "header-only acredito reject/sello/Drive"
import json, re, sys
for line in open(sys.argv[1], encoding="utf-8"):
    if not line.strip():
        continue
    rec = json.loads(line)
    asid = rec.get("assertion_id")
    obs = str(rec.get("observed") or "")
    if rec.get("result") != "PASS":
        continue
    if asid == "reject_existing" and "reject-existing" in obs:
        raise SystemExit("header-only acredito reject_existing")
    if asid == "estado_desactualizado" and "desactualizado" in obs:
        raise SystemExit("header-only acredito estado_desactualizado")
    if asid == "drive_cmd_runner" and "runner-re" in obs:
        raise SystemExit("header-only acredito drive_cmd_runner")
raise SystemExit(0)
PY
fi

# ---------------------------------------------------------------------------
# Mutantes nombrados
# ---------------------------------------------------------------------------
if [ -f "$DRV" ]; then
  copy_driver "$SANDBOX/va.src.sh"
  fm_mut_check_flat_infra verify-app "$DRV" drive verify-app
  fm_mut_require_baseline verify-app "$DRV" drive verify-app

  mut_omit() {
    local label="$1" asid="$2" signal="$3" expr="$4"
    caso "mutante $label: omitir $asid se pone rojo"
    reset_art
    local mut="$SANDBOX/va-$label.sh"
    if sed_must_change "$SANDBOX/va.src.sh" "$mut" "$expr" "$label"; then
      out="$(ctrl_drv "$mut" drive verify-app 2>&1)" && rc=0 || rc=$?
      assert_missing_or_fail verify-app "$asid" "$signal" "$rc"
    fi
  }

  mut_omit omit_reject_existing reject_existing 'reject-existing' \
    '/assert:reject_existing/,/assert:reject_existing_end/d'
  mut_omit omit_seal_compare estado_desactualizado 'desactualizado' \
    '/assert:estado_desactualizado/,/assert:estado_desactualizado_end/d'
  mut_omit omit_drive_cmd drive_cmd_runner 'runner-re' \
    '/assert:drive_cmd_runner/,/assert:drive_cmd_runner_end/d'

  caso "mutante cksum glob con directorios se pone rojo"
  reset_art
  PLANT_DIR="$repo/verify/.saikit-planted-dir-20.28-mut"
  mkdir -p "$PLANT_DIR"
  mut="$SANDBOX/va-cksum-star.sh"
  # Restaura cksum * (incluye directorios) — debe morir con dir plantado.
  if sed_must_change "$SANDBOX/va.src.sh" "$mut" \
    's#find \. -type d \\( -name __pycache__ -o -name .pytest_cache \\) -prune -o -type f ! -name .DS_Store -print0 2>/dev/null | sort -z | xargs -0 -r cksum 2>/dev/null#cksum *#' \
    "cksum_star"; then
    out="$(ctrl_drv "$mut" drive verify-app 2>&1)" && rc=0 || rc=$?
    if [ "$rc" -eq 0 ]; then
      malo "mutante cksum * sobrevivio en verde con directorio plantado"
    fi
  fi
  rmdir "$PLANT_DIR" 2>/dev/null || rm -rf "$PLANT_DIR"

  caso "mutante checkout_tree sin podar caches se pone rojo"
  reset_art
  mut="$SANDBOX/va-no-prune-cache.sh"
  # Quita el prune: el sello vuelve a ver __pycache__/*.pyc.
  if sed_must_change "$SANDBOX/va.src.sh" "$mut" \
    's#-type d \\( -name __pycache__ -o -name .pytest_cache \\) -prune -o ##' \
    "no_prune_cache"; then
    PLANT_PYC="$repo/verify/__pycache__"
    mkdir -p "$PLANT_PYC"
    probe="$PLANT_PYC/saikit-planted-20.28.pyc"
    printf 'planted\n' > "$probe"
    # Extrae y evalua el cuerpo de checkout_tree sano vs mutado.
    tree_hash() {
      local script="$1"
      CHECKOUT_VERIFY="$repo/verify" bash -c '
        eval "$(sed -n "/^checkout_tree()/,/^}/p" "$1")"
        checkout_tree
      ' bash "$script"
    }
    h_sana="$(tree_hash "$SANDBOX/va.src.sh")"
    h_mut="$(tree_hash "$mut")"
    if [ "$h_sana" = "$h_mut" ]; then
      malo "mutante sin prune sobrevivio: sello igual al podado con .pyc plantado"
    fi
    rm -f "$probe"
    rmdir "$PLANT_PYC" 2>/dev/null || true
  fi
fi

if [ "$fail" -ne 0 ]; then
  echo "FAIL: $fail aserciones" >&2
  exit 1
fi
echo "OK: test_feature_map_verify_app"
exit 0
