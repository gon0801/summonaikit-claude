#!/usr/bin/env bash
# tests/test_feature_map_ci_minimo.sh — 19.9: ci-minimo por PTY y flags.
#
# DoD: aceptar/rechazar/preservar ajeno e idempotencia observados; YAML/pins/
# test+verify correctos y comandos corridos en fixture; no afirmar Actions
# vivo; mutantes de omision/sobrescritura rojos. PTY ausente => unknown en
# interactivos, nunca un PTY fingido. No cambia pins.
#
# Mutaciones (copia del driver; SAIKIT_FM_DRIVER):
#   omit_accept_write omit_reject_no_write overwrite_foreign
#   omit_idempotent omit_verify_run omit_test_run pin_as_tag
#   omit_unsupported claim_live_actions
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
. "$here/lib/sandbox.sh"; sandbox_init
fail=0
caso() { printf '  caso: %s\n' "$1"; }
malo() { printf '    FAIL: %s\n' "$1" >&2; fail=$((fail + 1)); }

SKILL="$repo/.cursor/skills/verify-summonaikit"
CTRL="$SKILL/scripts/control-summonaikit"
PTY="$SKILL/scripts/lib/pty_driver.py"
DRV="$SKILL/scripts/drivers/ci-minimo.sh"
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

assert_result() {
  local fid="$1" asid="$2" want="$3"
  local steps
  steps="$(latest_steps "$fid")" || { malo "$fid: sin steps para $asid"; return; }
  python3 - "$steps" "$asid" "$want" <<'PY' || malo "$fid: $asid no quedo $want"
import json, sys
steps, asid, want = sys.argv[1], sys.argv[2], sys.argv[3]
found = None
for line in open(steps, encoding="utf-8"):
    if not line.strip():
        continue
    rec = json.loads(line)
    if rec.get("type") == "assertion" and rec.get("assertion_id") == asid:
        found = rec
if found is None:
    raise SystemExit(f"falta aserción {asid}")
if found.get("result") != want:
    raise SystemExit(f"{asid} result={found.get('result')} want={want}")
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
  return 0
}

# ---------------------------------------------------------------------------
# Inventario: descriptor activo, no legacy, PTY clasificado
# ---------------------------------------------------------------------------
caso "catalogo activa ci-minimo y clasifica pty_driver"
python3 - "$SKILL" <<'PY' || malo "catalogo/descriptor ci-minimo incompleto"
import json, sys
from pathlib import Path
skill = Path(sys.argv[1])
cat = json.loads((skill / "features/catalog.json").read_text())
h = (cat.get("helpers") or {}).get("scripts/lib/pty_driver.py")
assert h and h.get("kind") == "internal", h
meta = (cat.get("features") or {}).get("ci-minimo") or {}
assert meta.get("status") == "active", meta
assert meta.get("card"), meta
d = json.loads((skill / "features/ci-minimo.json").read_text())
ex = d.get("executor") or {}
assert ex.get("kind") == "driver", ex
assert (skill / (ex.get("path") or "scripts/drivers/ci-minimo.sh")).is_file()
ids = [c.get("id") for c in (d.get("cases") or [])]
for need in ("ci-interactive", "ci-flags", "ci-defaults", "ci-reject"):
    assert need in ids, (need, ids)
readme = (skill / "features/README.md").read_text(encoding="utf-8")
assert "ci-minimo.md" in readme, "README sin linea de ci-minimo"
PY
[ -f "$PTY" ] || malo "falta scripts/lib/pty_driver.py"
[ -f "$DRV" ] || malo "falta scripts/drivers/ci-minimo.sh"
[ -f "$SKILL/features/ci-minimo.md" ] || malo "falta ficha ci-minimo.md"
if [ -f "$PTY" ]; then
  PYTHONDONTWRITEBYTECODE=1 python3 -c \
    "import ast,pathlib; ast.parse(pathlib.Path(r'$PTY').read_text(encoding='utf-8'))" \
    || malo "pty_driver.py no parsea"
  bash -n "$DRV" || malo "bash -n fallo en ci-minimo.sh"
fi

# ---------------------------------------------------------------------------
# Launch aislado
# ---------------------------------------------------------------------------
caso "launch aislado para drive ci-minimo"
if ! out="$(ctrl launch 2>&1)"; then
  malo "launch fallo: $out"
  echo "FAIL: $fail aserciones (sin launch no hay drives)" >&2
  exit 1
fi
printf '%s' "$out" | grep -q 'launched run_id=' || malo "launch sin run_id: $out"

# ---------------------------------------------------------------------------
# Drive real
# ---------------------------------------------------------------------------
caso "drive ci-minimo: accept/reject, flags, preserve, runners, fixture"
reset_art
out="$(ctrl drive ci-minimo 2>&1)" && rc=0 || rc=$?
if [ "$rc" -eq 3 ]; then
  printf '%s' "$out" | grep -Eqi 'PTY|pty|unknown|MISSING' \
    || malo "drive unknown/3 sin motivo PTY: $out"
  if PYTHONDONTWRITEBYTECODE=1 python3 "$PTY" --probe >/dev/null 2>&1; then
    malo "PTY disponible pero drive salio unknown/3: $out"
  else
    printf '    (PTY ausente: interactivos unknown; flags/defaults se juzgan abajo)\n'
  fi
else
  [ "$rc" -eq 0 ] || malo "drive ci-minimo rc=$rc: $out"
fi

sum="$(latest_summary ci-minimo)"
[ -n "$sum" ] && [ -f "$sum" ] || malo "ci-minimo sin summary"
if [ -n "$sum" ] && [ -f "$sum" ]; then
python3 - "$sum" <<'PY' || malo "ci-minimo summary incompleto"
import json, sys
s = json.loads(open(sys.argv[1], encoding="utf-8").read())
cases = s.get("cases") or s.get("cases_requested") or []
text = " ".join(cases) if not isinstance(cases, str) else cases
for need in ("ci-interactive", "ci-flags", "ci-defaults"):
    assert need in text, (need, cases)
PY
fi

assert_obs ci-minimo flags_write 'escrito'
assert_obs ci-minimo yaml_parses 'parsea'
assert_obs ci-minimo pins_sha40 'sha40'
assert_obs ci-minimo no_secrets 'sin secrets'
assert_obs ci-minimo run_test 'bash tests/run.sh'
assert_obs ci-minimo run_verify 'verify/'
assert_obs ci-minimo defaults_no_write 'ausente'
assert_obs ci-minimo defaults_aviso 'sin CI|no mergea'
assert_obs ci-minimo foreign_intact 'intact'
assert_obs ci-minimo no_our_yml 'ausente'
assert_obs ci-minimo second_same_hash 'same-hash'
assert_obs ci-minimo runner_bash 'bash tests/run.sh'
assert_obs ci-minimo runner_npm 'npm test'
assert_obs ci-minimo runner_yarn 'yarn test'
assert_obs ci-minimo runner_pnpm 'pnpm test'
assert_obs ci-minimo runner_pytest 'pytest'
assert_obs ci-minimo unsupported_exit_2 '2'
assert_obs ci-minimo unsupported_no_write 'ausente'
assert_obs ci-minimo fixture_ran_test 'ran-test'
assert_obs ci-minimo fixture_ran_verify 'ran-verify'
assert_obs ci-minimo not_live_actions 'local-not-live'

if [ "$rc" -eq 0 ]; then
  assert_obs ci-minimo accept_write 'escrito'
  assert_obs ci-minimo accept_offer 'oferta'
  assert_obs ci-minimo reject_no_write 'ausente'
  assert_obs ci-minimo reject_aviso 'sin CI|no mergea'
fi

# ---------------------------------------------------------------------------
# PTY ausente: interactivos unknown; flags/defaults siguen; nunca fingir
# ---------------------------------------------------------------------------
caso "PTY ausente: interactivos unknown, flags observables, sin fingir"
reset_art
out="$(SAIKIT_VERIFY_PTY=missing ctrl drive ci-minimo 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 3 ] || malo "drive sin PTY debio unknown/3 (got $rc): $out"
assert_result ci-minimo accept_write unknown
assert_result ci-minimo reject_no_write unknown
assert_obs ci-minimo flags_write 'escrito'
assert_obs ci-minimo defaults_aviso 'sin CI|no mergea'
assert_obs ci-minimo not_live_actions 'local-not-live'
steps="$(latest_steps ci-minimo)"
if [ -n "$steps" ] && [ -f "$steps" ]; then
python3 - "$steps" <<'PY' || malo "sin PTY se presento simulacion como PTY"
import json, sys
for line in open(sys.argv[1], encoding="utf-8"):
    if not line.strip():
        continue
    rec = json.loads(line)
    if rec.get("type") != "assertion":
        continue
    if rec.get("assertion_id") not in (
        "accept_write", "accept_offer", "reject_no_write", "reject_aviso",
    ):
        continue
    if rec.get("result") == "PASS":
        raise SystemExit(f"{rec.get('assertion_id')} PASS sin PTY")
    blob = json.dumps(rec, ensure_ascii=False).lower()
    if "fake-pty" in blob or "simulated-pty" in blob:
        raise SystemExit(f"PTY fingido: {rec}")
PY
fi

# ---------------------------------------------------------------------------
# Encabezado falso + rc 0 no acredita YAML/pins/fixture
# ---------------------------------------------------------------------------
caso "encabezado falso con rc 0 no acredita pins ni fixture"
reset_art
stub="$SANDBOX/header-only-ci.sh"
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
assert ci-interactive accept_write "ci ok"
assert ci-interactive accept_offer "ci ok"
assert ci-reject reject_no_write "ci ok"
assert ci-reject reject_aviso "ci ok"
assert ci-flags flags_write "ci ok"
assert ci-flags yaml_parses "ci ok"
assert ci-flags pins_sha40 "ci ok"
assert ci-flags no_secrets "ci ok"
assert ci-flags run_test "ci ok"
assert ci-flags run_verify "ci ok"
assert ci-defaults defaults_no_write "ci ok"
assert ci-defaults defaults_aviso "ci ok"
assert ci-preserve-foreign foreign_intact "ci ok"
assert ci-preserve-foreign no_our_yml "ci ok"
assert ci-idempotent second_same_hash "ci ok"
assert ci-runners runner_bash "ci ok"
assert ci-runners runner_npm "ci ok"
assert ci-runners runner_yarn "ci ok"
assert ci-runners runner_pnpm "ci ok"
assert ci-runners runner_pytest "ci ok"
assert ci-unsupported unsupported_exit_2 "ci ok"
assert ci-unsupported unsupported_no_write "ci ok"
assert ci-run-fixture fixture_ran_test "ci ok"
assert ci-run-fixture fixture_ran_verify "ci ok"
assert ci-run-fixture not_live_actions "ci ok"
exit 0
EOF
chmod +x "$stub"
ctrl_drv "$stub" drive ci-minimo >/dev/null 2>&1 || true
steps="$(latest_steps ci-minimo)"
if [ -n "$steps" ] && [ -f "$steps" ]; then
python3 - "$steps" <<'PY' || malo "header-only acredito sha40 o local-not-live"
import json, re, sys
for line in open(sys.argv[1], encoding="utf-8"):
    if not line.strip():
        continue
    rec = json.loads(line)
    asid = rec.get("assertion_id")
    obs = str(rec.get("observed") or "")
    if asid == "pins_sha40" and re.search(r"sha40", obs) and rec.get("result") == "PASS":
        raise SystemExit("header-only acredito pins_sha40")
    if asid == "not_live_actions" and "local-not-live" in obs and rec.get("result") == "PASS":
        raise SystemExit("header-only acredito not_live_actions")
raise SystemExit(0)
PY
fi

# ---------------------------------------------------------------------------
# Mutantes
# ---------------------------------------------------------------------------
copy_driver "$SANDBOX/ci.src.sh"

mut_omit() {
  local label="$1" asid="$2" signal="$3" expr="$4"
  caso "mutante $label: omitir $asid se pone rojo"
  reset_art
  local mut="$SANDBOX/ci-$label.sh"
  if sed_must_change "$SANDBOX/ci.src.sh" "$mut" "$expr" "$label"; then
    bash -n "$mut" || { malo "$label: mutante no parsea"; return; }
    out="$(ctrl_drv "$mut" drive ci-minimo 2>&1)" && rc=0 || rc=$?
    assert_missing_or_fail ci-minimo "$asid" "$signal" "$rc"
  fi
}

mut_omit omit_accept_write accept_write 'escrito' \
  '/assert:accept_write/,/assert:accept_write_end/d'
mut_omit omit_reject_no_write reject_no_write 'ausente' \
  '/assert:reject_no_write/,/assert:reject_no_write_end/d'
mut_omit overwrite_foreign foreign_intact 'intact' \
  '/assert:foreign_intact/,/assert:foreign_intact_end/d'
mut_omit omit_idempotent second_same_hash 'same-hash' \
  '/assert:second_same_hash/,/assert:second_same_hash_end/d'
mut_omit omit_verify_run run_verify 'verify/' \
  '/assert:run_verify/,/assert:run_verify_end/d'
mut_omit omit_test_run run_test 'bash tests/run.sh' \
  '/assert:run_test/,/assert:run_test_end/d'
mut_omit pin_as_tag pins_sha40 'sha40' \
  '/assert:pins_sha40/,/assert:pins_sha40_end/d'
mut_omit omit_unsupported unsupported_exit_2 '2' \
  '/assert:unsupported_exit_2/,/assert:unsupported_exit_2_end/d'

mut_omit claim_live_actions not_live_actions 'local-not-live' \
  '/assert:not_live_actions/,/assert:not_live_actions_end/d'

if [ "$fail" -ne 0 ]; then
  echo "FAIL: $fail aserciones" >&2
  exit 1
fi
echo "OK: test_feature_map_ci_minimo"
exit 0
