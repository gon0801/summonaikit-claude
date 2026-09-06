#!/usr/bin/env bash
# tests/test_feature_map_staging.sh — 19.15: staging por override.
#
# DoD: override en fixture; hook ejecutado por su hash; estado en el lab;
# perfil externo sintetico intacto; cleanup acotado; mutantes de destino
# hook/estado y guard de propiedad rojos; sin sesion viva del operador.
# Base: tests/test_stage_override.sh (no se duplica su bateria).
#
# Mutaciones (copia del driver; SAIKIT_FM_DRIVER):
#   omit_dest_state   — quita state_in_lab
#   omit_ownership    — quita ownership_refused
#   omit_cleanup      — quita cleanup_scoped
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
. "$here/lib/sandbox.sh"; sandbox_init
fail=0
caso() { printf '  caso: %s\n' "$1"; }
malo() { printf '    FAIL: %s\n' "$1" >&2; fail=$((fail + 1)); }

SKILL="$repo/.cursor/skills/verify-summonaikit"
CTRL="$SKILL/scripts/control-summonaikit"
DRV="$SKILL/scripts/drivers/stage-override.sh"
STATE="$SANDBOX/verify-state"
ART="$SANDBOX/verify-artifacts"
mkdir -p "$STATE" "$ART"

ctrl() {
  SAIKIT_VERIFY_STATE="$STATE" SAIKIT_VERIFY_ARTIFACTS="$ART" \
    SAIKIT_HOOK_VIVO="$repo/hooks/summonaikit-harness.sh" \
    bash "$CTRL" "$@"
}

ctrl_drv() {
  local drv="$1"; shift
  SAIKIT_FM_DRIVER="$drv" \
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

assert_missing_or_fail() {
  local fid="$1" asid="$2" signal="$3" rc_drive="$4"
  local sum steps
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

reset_art() { rm -rf "$ART"; mkdir -p "$ART"; }

copy_driver() {
  cp "$DRV" "$1"
  chmod +x "$1"
}

sed_must_change() {
  local src="$1" dest="$2" expr="$3" label="$4"
  sed "$expr" "$src" > "$dest"
  chmod +x "$dest"
  if cmp -s "$src" "$dest"; then
    malo "$label: sed no cambio el archivo (patron obsoleto)"
    return 1
  fi
  bash -n "$dest" || { malo "$label: mutante no parsea"; return 1; }
  return 0
}

# ---------------------------------------------------------------------------
# Inventario: pending→active, resto intacto, README
# ---------------------------------------------------------------------------
caso "catalogo activa stage-override y conserva las demas"
python3 - "$SKILL" <<'PY' || malo "catalogo/descriptor stage-override incompleto"
import json, sys
from pathlib import Path
skill = Path(sys.argv[1])
cat = json.loads((skill / "features/catalog.json").read_text())
feats = cat.get("features") or {}
meta = feats.get("stage-override") or {}
assert meta.get("status") == "active", meta
assert meta.get("card"), meta
assert not meta.get("owner_task"), ("pending leftover", meta)
desc = json.loads((skill / "features/stage-override.json").read_text())
ex = desc.get("executor") or {}
assert ex.get("kind") == "driver", ex
path = ex.get("path") or "scripts/drivers/stage-override.sh"
assert (skill / path).is_file(), path
assert (skill / "features/stage-override.md").is_file()
ids = [c.get("id") for c in (desc.get("cases") or [])]
for need in (
    "stage-prepare", "stage-hook-hash", "stage-state-lab",
    "stage-profile-intact", "stage-ownership", "stage-cleanup",
    "stage-no-live",
):
    assert need in ids, (need, ids)
for c in desc.get("cases") or []:
    assert c.get("required_assertions"), c
# Otras features: no exigir pending de filas ya mergeadas/activadas en serie.
for fid, want in (
    ("check-secrets", "active"),
    ("capture-payloads", "active"),
    ("decision-blast", "active"),
    ("verify-app", "active"),
    ("stage-override", "active"),
    ("merge-happy-path", "pending"),
    ("install-guardian", "active"),
    ("routing-recipes", "active"),
):
    st = (feats.get(fid) or {}).get("status")
    assert st == want, (fid, st, want)
readme = (skill / "features/README.md").read_text(encoding="utf-8")
assert "stage-override.md" in readme, "README sin linea de stage-override"
surfaces = cat.get("surfaces") or {}
assert (surfaces.get("tools/stage-override.sh") or {}).get("feature") == "stage-override"
PY
[ -f "$DRV" ] || malo "falta drivers/stage-override.sh"
[ -f "$SKILL/features/stage-override.md" ] || malo "falta ficha stage-override.md"
if [ -f "$DRV" ]; then
  bash -n "$DRV" || malo "bash -n fallo en stage-override.sh"
fi

caso "list-features declara stage-override active sandbox"
out="$(ctrl list-features 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 0 ] || malo "list-features fallo: $out"
printf '%s' "$out" | grep -E 'id=stage-override' | grep -q 'status=active' \
  || malo "list-features no activa stage-override: $out"

# ---------------------------------------------------------------------------
# Launch aislado
# ---------------------------------------------------------------------------
caso "launch aislado para drive stage-override"
if ! out="$(ctrl launch 2>&1)"; then
  malo "launch fallo: $out"
  echo "FAIL: $fail aserciones (sin launch no hay drives)" >&2
  exit 1
fi
printf '%s' "$out" | grep -q 'launched run_id=' || malo "launch sin run_id: $out"

# ---------------------------------------------------------------------------
# Drive real
# ---------------------------------------------------------------------------
caso "drive stage-override: hash, estado en lab, perfil intacto, cleanup"
reset_art
out="$(ctrl drive stage-override 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 0 ] || malo "drive stage-override rc=$rc: $out"

sum="$(latest_summary stage-override)"
[ -n "$sum" ] && [ -f "$sum" ] || malo "stage-override sin summary"
if [ -n "$sum" ] && [ -f "$sum" ]; then
python3 - "$sum" <<'PY' || malo "stage-override summary incompleto"
import json, sys
s = json.loads(open(sys.argv[1], encoding="utf-8").read())
assert s.get("result") == "PASS" and s.get("exit_code") == 0, s
cases = s.get("cases") or s.get("cases_requested") or []
text = " ".join(cases) if not isinstance(cases, str) else cases
for need in (
    "stage-prepare", "stage-hook-hash", "stage-state-lab",
    "stage-profile-intact", "stage-ownership", "stage-cleanup",
    "stage-no-live",
):
    assert need in text, (need, cases)
PY
fi

assert_obs stage-override override_installed 'override-installed|MEDIDO'
assert_obs stage-override dest_matches_source 'dest-sha='
assert_obs stage-override hook_ran_hash 'hook-hash='
assert_obs stage-override state_in_lab 'state-in-lab'
assert_obs stage-override state_not_in_profile 'state-not-in-profile'
assert_obs stage-override profile_intact 'profile-intact'
assert_obs stage-override ownership_refused 'ownership-refused'
assert_obs stage-override foreign_intact 'foreign-intact'
assert_obs stage-override cleanup_scoped 'cleanup-scoped'
assert_obs stage-override no_live_session 'no-live-session'

# ---------------------------------------------------------------------------
# Encabezado falso + rc 0 no acredita destino/propiedad/cleanup
# ---------------------------------------------------------------------------
caso "encabezado falso con rc 0 no acredita destino ni propiedad ni cleanup"
reset_art
stub="$SANDBOX/header-only-stage-override.sh"
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
assert stage-prepare override_installed "ok"
assert stage-prepare dest_matches_source "ok"
assert stage-hook-hash hook_ran_hash "ok"
assert stage-state-lab state_in_lab "ok"
assert stage-state-lab state_not_in_profile "ok"
assert stage-profile-intact profile_intact "ok"
assert stage-ownership ownership_refused "ok"
assert stage-ownership foreign_intact "ok"
assert stage-cleanup cleanup_scoped "ok"
assert stage-no-live no_live_session "ok"
exit 0
EOF
chmod +x "$stub"
ctrl_drv "$stub" drive stage-override >/dev/null 2>&1 || true
steps="$(latest_steps stage-override)"
if [ -n "$steps" ] && [ -f "$steps" ]; then
python3 - "$steps" <<'PY' || malo "header-only acredito destino/propiedad/cleanup"
import json, sys
for line in open(sys.argv[1], encoding="utf-8"):
    if not line.strip():
        continue
    rec = json.loads(line)
    asid = rec.get("assertion_id")
    obs = str(rec.get("observed") or "")
    if rec.get("result") != "PASS":
        continue
    if asid == "state_in_lab" and "state-in-lab" in obs:
        raise SystemExit("header-only acredito state_in_lab")
    if asid == "ownership_refused" and "ownership-refused" in obs:
        raise SystemExit("header-only acredito ownership_refused")
    if asid == "cleanup_scoped" and "cleanup-scoped" in obs:
        raise SystemExit("header-only acredito cleanup_scoped")
raise SystemExit(0)
PY
fi

# ---------------------------------------------------------------------------
# Mutantes nombrados
# ---------------------------------------------------------------------------
if [ -f "$DRV" ]; then
  copy_driver "$SANDBOX/so.src.sh"

  mut_omit() {
    local label="$1" asid="$2" signal="$3" expr="$4"
    caso "mutante $label: omitir $asid se pone rojo"
    reset_art
    local mut="$SANDBOX/so-$label.sh"
    if sed_must_change "$SANDBOX/so.src.sh" "$mut" "$expr" "$label"; then
      out="$(ctrl_drv "$mut" drive stage-override 2>&1)" && rc=0 || rc=$?
      assert_missing_or_fail stage-override "$asid" "$signal" "$rc"
    fi
  }

  mut_omit omit_dest_state state_in_lab 'state-in-lab' \
    '/assert:state_in_lab/,/assert:state_in_lab_end/d'
  mut_omit omit_ownership ownership_refused 'ownership-refused' \
    '/assert:ownership_refused/,/assert:ownership_refused_end/d'
  mut_omit omit_cleanup cleanup_scoped 'cleanup-scoped' \
    '/assert:cleanup_scoped/,/assert:cleanup_scoped_end/d'
fi

if [ "$fail" -ne 0 ]; then
  echo "FAIL: $fail aserciones" >&2
  exit 1
fi
echo "OK: test_feature_map_staging"
exit 0
