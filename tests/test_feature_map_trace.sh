#!/usr/bin/env bash
# tests/test_feature_map_trace.sh — 19.13: rastro/blast reales en fixture.
#
# DoD: rastro/blast validos y rechazos por contrato observados; redaccion
# comprobada y mutada; output queda en fixture; no se atribuye cumplimiento
# automatico a agentes. No duplica la bateria de carreras de las libs.
#
# Mutaciones (copia del driver; SAIKIT_FM_DRIVER):
#   omit_decision_reject omit_blast_level omit_blast_command
#   omit_decision_redact omit_blast_redact omit_output_location
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
. "$here/lib/sandbox.sh"; sandbox_init
fail=0
caso() { printf '  caso: %s\n' "$1"; }
malo() { printf '    FAIL: %s\n' "$1" >&2; fail=$((fail + 1)); }

SKILL="$repo/.cursor/skills/verify-summonaikit"
CTRL="$SKILL/scripts/control-summonaikit"
DRV="$SKILL/scripts/drivers/decision-blast.sh"
STATE="$SANDBOX/verify-state"
ART="$SANDBOX/verify-artifacts"
mkdir -p "$STATE" "$ART"

ctrl() {
  SAIKIT_VERIFY_STATE="$STATE" SAIKIT_VERIFY_ARTIFACTS="$ART" \
    bash "$CTRL" "$@"
}

ctrl_drv() {
  local drv="$1"; shift
  SAIKIT_FM_DRIVER="$drv" \
    SAIKIT_VERIFY_STATE="$STATE" SAIKIT_VERIFY_ARTIFACTS="$ART" \
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
    malo "$label: sed no cambio el driver (patron obsoleto)"
    return 1
  fi
  bash -n "$dest" || { malo "$label: mutante no parsea"; return 1; }
  return 0
}

# ---------------------------------------------------------------------------
# Inventario: catalogo active + descriptor + ficha
# ---------------------------------------------------------------------------
caso "catalogo activa decision-blast con driver y ficha"
python3 - "$SKILL" <<'PY' || malo "catalogo/descriptor decision-blast incompleto"
import json, sys
from pathlib import Path
skill = Path(sys.argv[1])
cat = json.loads((skill / "features/catalog.json").read_text())
meta = (cat.get("features") or {}).get("decision-blast") or {}
assert meta.get("status") == "active", meta
assert meta.get("card"), meta
assert not meta.get("owner_task"), ("pending leftover", meta)
d = json.loads((skill / "features/decision-blast.json").read_text())
assert d.get("id") == "decision-blast"
ex = d.get("executor") or {}
assert ex.get("kind") == "driver", ex
assert (skill / (ex.get("path") or "scripts/drivers/decision-blast.sh")).is_file()
ids = [c.get("id") for c in (d.get("cases") or [])]
for need in ("decision-valid", "decision-reject", "blast-valid",
             "blast-reject", "redact", "output-location"):
    assert need in ids, (need, ids)
readme = (skill / "features/README.md").read_text(encoding="utf-8")
assert "decision-blast.md" in readme, "README sin linea de decision-blast"
card = (skill / "features/decision-blast.md").read_text(encoding="utf-8")
assert "automatically" in card.lower() or "automatic" in card.lower(), card
assert "agent" in card.lower(), "ficha no nombra agents"
PY
[ -f "$DRV" ] || malo "falta scripts/drivers/decision-blast.sh"
[ -f "$SKILL/features/decision-blast.md" ] || malo "falta ficha decision-blast.md"
if [ -f "$DRV" ]; then
  bash -n "$DRV" || malo "bash -n fallo en decision-blast.sh"
  # No duplicar la bateria de carreras de las libs.
  if grep -E 'SAIKIT_DECISION_TEST|at-hold\.|go-hold\.' "$DRV" >/dev/null; then
    malo "el driver duplica la bateria de carreras de saikit-decision"
  fi
fi

# ---------------------------------------------------------------------------
# Launch + drive
# ---------------------------------------------------------------------------
caso "launch aislado para drive decision-blast"
if ! out="$(ctrl launch 2>&1)"; then
  malo "launch fallo: $out"
  echo "FAIL: $fail aserciones (sin launch no hay drives)" >&2
  exit 1
fi
printf '%s' "$out" | grep -q 'launched run_id=' || malo "launch sin run_id: $out"

caso "drive decision-blast: rastro, rechazos, blast, redaccion, fixture"
reset_art
out="$(ctrl drive decision-blast 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 0 ] || malo "drive decision-blast rc=$rc: $out"
sum="$(latest_summary decision-blast)"
[ -n "$sum" ] && [ -f "$sum" ] || malo "decision-blast sin summary"
if [ -n "$sum" ] && [ -f "$sum" ]; then
python3 - "$sum" <<'PY' || malo "summary decision-blast incompleto"
import json, sys
s = json.loads(open(sys.argv[1], encoding="utf-8").read())
assert s.get("result") == "PASS" and s.get("exit_code") == 0, s
cases = s.get("cases") or s.get("cases_requested") or []
text = " ".join(cases) if not isinstance(cases, str) else cases
for need in ("decision-valid", "decision-reject", "blast-valid",
             "blast-reject", "redact", "output-location"):
    assert need in text, (need, cases)
PY
fi

assert_obs decision-blast trail_written 'decisiones/.+\.tsv|fm1913v'
assert_obs decision-blast header_ok 'cuando\|etapa\|decision'
assert_obs decision-blast check_ok 'check.0|exit 0|ok'
assert_obs decision-blast reject_exit_2 'exit 2|rc=2'
assert_obs decision-blast reject_reason 'malformado|linea 2'
assert_obs decision-blast file_untouched 'intact|untouched|identic'
assert_obs decision-blast blast_written 'blast-fm1913b\.json|findings/blast'
assert_obs decision-blast schema_keys '"hecho"|"comando"|"salida"|"nivel"'
assert_obs decision-blast nivel_4 '"nivel":4|nivel 4'
assert_obs decision-blast level_exit_2 'exit 2|rc=2'
assert_obs decision-blast level_no_file 'no file|ausente|not created'
assert_obs decision-blast command_exit_2 'exit 2|rc=2'
assert_obs decision-blast command_untouched 'intact|untouched|identic'
assert_obs decision-blast decision_redacted '\[REDACTED\]'
assert_obs decision-blast decision_no_secret 'sin secreto|no token|redact'
assert_obs decision-blast blast_redacted '\[REDACTED\]'
assert_obs decision-blast blast_no_secret 'sin secreto|no token|redact'
assert_obs decision-blast decision_in_fixture '\.saikit/decisiones/'
assert_obs decision-blast blast_in_fixture '\.saikit/findings/'
assert_obs decision-blast not_on_checkout 'checkout intact|no checkout|ausente en checkout'

# ---------------------------------------------------------------------------
# Mutantes: copia del driver
# ---------------------------------------------------------------------------
if [ -f "$DRV" ]; then
  copy_driver "$SANDBOX/db.src.sh"
fi

run_mut() {
  local label="$1" expr="$2" asid="$3" signal="$4"
  caso "mutante $label: $asid se pone rojo"
  reset_art
  local mut="$SANDBOX/db-$label.sh"
  if [ ! -f "$SANDBOX/db.src.sh" ]; then
    malo "$label: sin driver fuente"
    return
  fi
  if sed_must_change "$SANDBOX/db.src.sh" "$mut" "$expr" "$label"; then
    out="$(ctrl_drv "$mut" drive decision-blast 2>&1)" && rc=0 || rc=$?
    assert_missing_or_fail decision-blast "$asid" "$signal" "$rc"
  fi
}

run_mut omit_decision_reject \
  '/assert:reject_exit_2/,/assert:reject_exit_2_end/d' \
  reject_exit_2 'exit 2|rc=2'

run_mut omit_blast_level \
  '/assert:level_exit_2/,/assert:level_exit_2_end/d' \
  level_exit_2 'exit 2|rc=2'

run_mut omit_blast_command \
  '/assert:command_exit_2/,/assert:command_exit_2_end/d' \
  command_exit_2 'exit 2|rc=2'

run_mut omit_decision_redact \
  '/assert:decision_no_secret/,/assert:decision_no_secret_end/d' \
  decision_no_secret 'sin secreto|no token|redact'

run_mut omit_blast_redact \
  '/assert:blast_no_secret/,/assert:blast_no_secret_end/d' \
  blast_no_secret 'sin secreto|no token|redact'

run_mut omit_output_location \
  '/assert:not_on_checkout/,/assert:not_on_checkout_end/d' \
  not_on_checkout 'checkout intact|no checkout|ausente en checkout'

if [ "$fail" -ne 0 ]; then
  echo "FAIL: $fail aserciones" >&2
  exit 1
fi
echo "OK: test_feature_map_trace"
exit 0
