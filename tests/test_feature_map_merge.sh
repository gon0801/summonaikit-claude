#!/usr/bin/env bash
# tests/test_feature_map_merge.sh — 19.6: saikit-merge simulado.
# Drive de tools/saikit-merge.sh real sobre Git/origin bare locales y gh
# falso estricto (argv registrado). Modo siempre simulated.
#
# Mutaciones discriminantes (copia del driver; SAIKIT_FM_DRIVER):
#   omit_listo_no_merge     — LISTO sin afirmar que no llamó merge
#   omit_match_head         — confirmado sin --match-head-commit
#   omit_no_admin           — no afirma ausencia de --admin
#   omit_no_delete_branch   — no afirma ausencia de --delete-branch
#   omit_ci_revalidated     — confirmado sin observar gh run list
#   omit_sello_intact       — confirmado sin observar sello intacto
#   omit_ci_rojo            — CI rojo como OK
#   omit_base_movida        — base avanzada como OK
#   omit_sello_ajeno        — veredicto de otro sha como OK
#   omit_head_cambiado      — commits tras el sello como OK
#   omit_revert_trailer     — revert sin trailer como OK
#   omit_revert_punta       — revert que no es la punta como OK
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
. "$here/lib/sandbox.sh"; sandbox_init
fail=0
caso() { printf '  caso: %s\n' "$1"; }
malo() { printf '    FAIL: %s\n' "$1" >&2; fail=$((fail + 1)); }

SKILL="$repo/.cursor/skills/verify-summonaikit"
CTRL="$SKILL/scripts/control-summonaikit"
STATE="$SANDBOX/verify-state"
ART="$SANDBOX/verify-artifacts"
DESC="$SKILL/features/saikit-merge.json"
CARD="$SKILL/features/saikit-merge.md"
DRV="$SKILL/scripts/drivers/saikit-merge.sh"
CATALOG="$SKILL/features/catalog.json"
mkdir -p "$STATE" "$ART"
. "$here/lib/feature_map_mut.sh"

ctrl() {
  SAIKIT_VERIFY_STATE="$STATE" SAIKIT_VERIFY_ARTIFACTS="$ART" \
    bash "$CTRL" "$@"
}


reset_art() { rm -rf "$ART"; mkdir -p "$ART"; }

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


copy_driver() {
  cp "$DRV" "$1"
  chmod +x "$1"
}


# ---------------------------------------------------------------------------
# Inventario activo + descriptor/ficha/driver
# ---------------------------------------------------------------------------
caso "catalogo activo con card; descriptor kind=driver; modo simulated"
python3 - "$CATALOG" "$DESC" "$CARD" "$DRV" <<'PY' || malo "catalogo/descriptor saikit-merge incompleto"
import json, sys
from pathlib import Path
cat_p, desc_p, card_p, drv_p = map(Path, sys.argv[1:])
cat = json.loads(cat_p.read_text(encoding="utf-8"))
meta = (cat.get("features") or {}).get("saikit-merge") or {}
assert meta.get("status") == "active", meta
assert meta.get("card") in ("features/saikit-merge.md", "saikit-merge.md"), meta
assert desc_p.is_file(), "falta descriptor"
assert card_p.is_file(), "falta ficha"
assert drv_p.is_file(), "falta driver"
desc = json.loads(desc_p.read_text(encoding="utf-8"))
assert desc.get("id") == "saikit-merge"
assert desc.get("execution_mode") == "simulated", desc
ex = desc.get("executor") or {}
assert ex.get("kind") == "driver", ex
assert (ex.get("path") or "").endswith("saikit-merge.sh")
cases = {c.get("id"): c for c in (desc.get("cases") or [])}
need = (
    "merge-listo", "merge-confirmado", "merge-ci-rojo", "merge-base-movida",
    "merge-sello-ajeno", "merge-head-cambiado",
    "revert-ok", "revert-sin-trailer", "revert-no-punta",
)
for cid in need:
    assert cid in cases, (cid, sorted(cases))
    assert cases[cid].get("required_assertions"), cid
PY
[ -f "$DRV" ] && bash -n "$DRV" || malo "bash -n fallo en drivers/saikit-merge.sh"

caso "list-features declara saikit-merge active simulated"
out="$(ctrl list-features 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 0 ] || malo "list-features fallo: $out"
printf '%s' "$out" | grep -E 'id=saikit-merge' | grep -q 'status=active' \
  || malo "list-features no declara active: $out"
printf '%s' "$out" | grep -E 'id=saikit-merge' | grep -q 'mode=simulated' \
  || malo "list-features no declara simulated: $out"
printf '%s' "$out" | grep -E 'id=saikit-merge' | grep -q 'saikit-merge.md' \
  || malo "list-features sin card: $out"

# ---------------------------------------------------------------------------
# Launch + drive real
# ---------------------------------------------------------------------------
caso "launch aislado para drive saikit-merge"
if ! out="$(ctrl launch 2>&1)"; then
  malo "launch fallo: $out"
  echo "FAIL: $fail aserciones (sin launch no hay drive)" >&2
  exit 1
fi
printf '%s' "$out" | grep -q 'launched run_id=' || malo "launch sin run_id: $out"

caso "doctor saikit-merge: gh simulado no exige binario vivo"
out="$(ctrl doctor saikit-merge 2>&1)" && rc=0 || rc=$?
[ -f "$ART/doctor.json" ] || malo "doctor no escribio doctor.json: $out"
if [ -f "$ART/doctor.json" ]; then
python3 - "$ART/doctor.json" <<'PY' || malo "doctor saikit-merge no queda ready-simulado"
import json, sys
d = json.loads(open(sys.argv[1], encoding="utf-8").read())
sm = d["features"]["saikit-merge"]
assert sm.get("mode") == "simulated", sm
assert sm.get("result") != "FAIL", sm
reasons = json.dumps(sm, ensure_ascii=False).lower()
assert "gh ausente" not in reasons, sm
assert sm.get("availability") != "failed", sm
blob = json.dumps(sm.get("requirements") or [], ensure_ascii=False)
assert "simulated" in blob or sm.get("mode") == "simulated", sm
PY
fi

caso "drive saikit-merge: LISTO/confirmado/rechazos/revert + mode simulated"
reset_art
out="$(ctrl drive saikit-merge 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 0 ] || malo "drive saikit-merge rc=$rc: $out"
sum="$(latest_summary saikit-merge)"
[ -n "$sum" ] && [ -f "$sum" ] || malo "saikit-merge sin summary"
if [ -n "$sum" ] && [ -f "$sum" ]; then
python3 - "$sum" <<'PY' || malo "summary saikit-merge incompleto o no simulated"
import json, sys
s = json.loads(open(sys.argv[1], encoding="utf-8").read())
assert s.get("result") == "PASS" and s.get("exit_code") == 0, s
assert s.get("mode") == "simulated", s
cases = s.get("cases") or s.get("cases_requested") or []
text = " ".join(cases) if not isinstance(cases, str) else cases
for need in (
    "merge-listo", "merge-confirmado", "merge-ci-rojo", "merge-base-movida",
    "merge-sello-ajeno", "merge-head-cambiado",
    "revert-ok", "revert-sin-trailer", "revert-no-punta",
):
    assert need in text, (need, cases)
PY
fi

assert_obs saikit-merge listo_line 'LISTO:'
assert_obs saikit-merge no_merge_on_listo 'no merge|sin merge|no_merge|gh pr merge ausente'
assert_obs saikit-merge merge_ok 'MERGE-OK:'
assert_obs saikit-merge match_head '--match-head-commit [0-9a-f]{7,}'
assert_obs saikit-merge no_admin 'sin --admin|no --admin|--admin ausente'
assert_obs saikit-merge no_delete_branch 'sin --delete-branch|no --delete-branch|--delete-branch ausente'
assert_obs saikit-merge ci_revalidated 'gh run list'
assert_obs saikit-merge sello_intact 'intact|igual|unchanged|byte'
assert_obs saikit-merge reject_ci_rojo 'NO-MERGE: CI rojo'
assert_obs saikit-merge no_merge_on_ci_rojo 'no merge|sin merge|ausente'
assert_obs saikit-merge reject_base_avanzada 'NO-MERGE: base avanzada'
assert_obs saikit-merge no_merge_on_base 'no merge|sin merge|ausente'
assert_obs saikit-merge reject_sello_ajeno 'NO-MERGE: veredicto de otro sha'
assert_obs saikit-merge no_merge_on_sello 'no merge|sin merge|ausente'
assert_obs saikit-merge reject_head_cambiado 'NO-MERGE: commits despues del veredicto'
assert_obs saikit-merge no_merge_on_head 'no merge|sin merge|ausente'
assert_obs saikit-merge revert_merge_ok 'MERGE-OK:'
assert_obs saikit-merge revert_match_head '--match-head-commit [0-9a-f]{7,}'
assert_obs saikit-merge reject_sin_trailer 'NO-MERGE: sin trailer'
assert_obs saikit-merge no_merge_on_trailer 'no merge|sin merge|ausente'
assert_obs saikit-merge reject_no_punta 'NO-MERGE: no es la punta'
assert_obs saikit-merge no_merge_on_punta 'no merge|sin merge|ausente'

# gh falso estricto: el driver no debe haber aceptado formas no previstas
# (queda en observed de alguna acción o en que el drive fue PASS).
steps="$(latest_steps saikit-merge)"
if [ -n "$steps" ] && [ -f "$steps" ]; then
python3 - "$steps" <<'PY' || malo "alguna accion mostro forma gh no soportada"
import json, sys
for line in open(sys.argv[1], encoding="utf-8"):
    if not line.strip():
        continue
    rec = json.loads(line)
    blob = json.dumps(rec, ensure_ascii=False)
    if "forma no soportada" in blob:
        raise SystemExit(blob[:400])
PY
fi

# ---------------------------------------------------------------------------
# Mutantes
# ---------------------------------------------------------------------------
[ -f "$DRV" ] || { echo "FAIL: $fail aserciones (sin driver no hay mutantes)" >&2; exit 1; }
copy_driver "$SANDBOX/merge.src.sh"
fm_mut_check_flat_infra saikit-merge "$DRV" drive saikit-merge
fm_mut_require_baseline saikit-merge "$DRV" drive saikit-merge

run_mut() {
  local label="$1" expr="$2" asid="$3" signal="$4"
  caso "mutante $label"
  reset_art
  local mut="$SANDBOX/merge-$label.sh"
  if sed_must_change "$SANDBOX/merge.src.sh" "$mut" "$expr" "$label"; then
    out="$(ctrl_drv "$mut" drive saikit-merge 2>&1)" && rc=0 || rc=$?
    assert_missing_or_fail saikit-merge "$asid" "$signal" "$rc"
  fi
}

run_mut omit_listo_no_merge \
  '/assert:no_merge_on_listo/,/assert:no_merge_on_listo_end/d' \
  no_merge_on_listo 'no merge|sin merge|ausente'

run_mut omit_match_head \
  '/assert:match_head/,/assert:match_head_end/d' \
  match_head '--match-head-commit'

run_mut omit_no_admin \
  '/assert:no_admin/,/assert:no_admin_end/d' \
  no_admin '--admin'

run_mut omit_no_delete_branch \
  '/assert:no_delete_branch/,/assert:no_delete_branch_end/d' \
  no_delete_branch '--delete-branch'

run_mut omit_ci_revalidated \
  '/assert:ci_revalidated/,/assert:ci_revalidated_end/d' \
  ci_revalidated 'gh run list'

run_mut omit_sello_intact \
  '/assert:sello_intact/,/assert:sello_intact_end/d' \
  sello_intact 'intact|igual|unchanged|byte'

run_mut omit_ci_rojo \
  '/assert:reject_ci_rojo/,/assert:reject_ci_rojo_end/d' \
  reject_ci_rojo 'CI rojo'

run_mut omit_base_movida \
  '/assert:reject_base_avanzada/,/assert:reject_base_avanzada_end/d' \
  reject_base_avanzada 'base avanzada'

run_mut omit_sello_ajeno \
  '/assert:reject_sello_ajeno/,/assert:reject_sello_ajeno_end/d' \
  reject_sello_ajeno 'veredicto de otro sha'

run_mut omit_head_cambiado \
  '/assert:reject_head_cambiado/,/assert:reject_head_cambiado_end/d' \
  reject_head_cambiado 'commits despues del veredicto'

run_mut omit_revert_trailer \
  '/assert:reject_sin_trailer/,/assert:reject_sin_trailer_end/d' \
  reject_sin_trailer 'sin trailer'

run_mut omit_revert_punta \
  '/assert:reject_no_punta/,/assert:reject_no_punta_end/d' \
  reject_no_punta 'no es la punta'

if [ "$fail" -ne 0 ]; then
  echo "FAIL: $fail aserciones" >&2
  exit 1
fi
echo "OK: test_feature_map_merge"
exit 0
