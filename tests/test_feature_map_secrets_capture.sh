#!/usr/bin/env bash
# tests/test_feature_map_secrets_capture.sh — 19.12: check-secrets + capture-payloads.
#
# DoD: detector fuerte limpio/trampa (unknown si solo fallback); captura con
# host ficticio, cwd/permisos/ajenos; secreto sintético ausente de evidencia;
# mutantes de redacción/aviso/permisos/cwd/ajeno rojos; CI suite provisiona
# gitleaks con el mismo pin que el job secrets. Sin perfiles vivos ni tokens
# reales de GitHub/Telegram.
#
# Mutaciones (copia del driver en sandbox; SAIKIT_FM_DRIVER):
#   omit_redaction         — quita evidence_no_secret
#   omit_fallback_warning  — quita el aviso de fallback
#   omit_permissions       — quita perms_private
#   omit_cwd               — quita cwd_filtered
#   omit_foreign           — quita foreign_intact
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
DRV_SECRETS="$SKILL/scripts/drivers/check-secrets.sh"
DRV_CAPTURE="$SKILL/scripts/drivers/capture-payloads.sh"
WF="$repo/.github/workflows/quality.yml"
mkdir -p "$STATE" "$ART"

# Secreto sintético armado en runtime: nada contiguo en el blob del test.
# Misma familia ghp_ que check-secrets/gitleaks ya conocen.
_s1='ghp_'; _s2='ABCDEF1234567890abcd'; _s3='efABCDEF1234567890'
SYNTH="${_s1}${_s2}${_s3}"
export SAIKIT_FM_SYNTH_SECRET="$SYNTH"

ctrl() {
  SAIKIT_VERIFY_STATE="$STATE" SAIKIT_VERIFY_ARTIFACTS="$ART" \
    SAIKIT_FM_SYNTH_SECRET="$SYNTH" \
    bash "$CTRL" "$@"
}

ctrl_drv() {
  local drv="$1"; shift
  SAIKIT_FM_DRIVER="$drv" \
    SAIKIT_VERIFY_STATE="$STATE" SAIKIT_VERIFY_ARTIFACTS="$ART" \
    SAIKIT_FM_SYNTH_SECRET="$SYNTH" \
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

latest_attempt() {
  local sum
  sum="$(latest_summary "$1")"
  [ -n "$sum" ] || return 1
  dirname "$sum"
}

has_gitleaks() {
  if [ -n "${SAIKIT_GITLEAKS:-}" ] && [ -x "${SAIKIT_GITLEAKS}" ]; then
    return 0
  fi
  command -v gitleaks >/dev/null 2>&1 && return 0
  [ -x /tmp/gitleaks-bin/gitleaks.exe ]
}

can_force_fallback() {
  if [ -x /usr/bin/gitleaks ] || [ -x /bin/gitleaks ]; then
    return 1
  fi
  return 0
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

scan_art_for_synth() {
  python3 - "$ART" "$SYNTH" <<'PY'
import sys
from pathlib import Path
root, needle = Path(sys.argv[1]), sys.argv[2]
hits = []
if not needle:
    raise SystemExit("synth vacio")
for p in root.rglob("*"):
    if not p.is_file():
        continue
    try:
        text = p.read_text(encoding="utf-8", errors="replace")
    except OSError:
        continue
    if needle in text:
        hits.append(str(p))
if hits:
    raise SystemExit("secreto sintetico en evidencia: " + ",".join(hits[:8]))
PY
}

# ---------------------------------------------------------------------------
# Inventario + pin CI
# ---------------------------------------------------------------------------
caso "catalogo activa check-secrets y capture-payloads"
python3 - "$SKILL" <<'PY' || malo "catalogo/descriptores 19.12 incompletos"
import json, sys
from pathlib import Path
skill = Path(sys.argv[1])
cat = json.loads((skill / "features/catalog.json").read_text())
feats = cat.get("features") or {}
for fid in ("check-secrets", "capture-payloads"):
    meta = feats.get(fid) or {}
    assert meta.get("status") == "active", (fid, meta)
    assert meta.get("card"), (fid, meta)
    assert not meta.get("owner_task"), (fid, "pending leftover", meta)
    desc = json.loads((skill / f"features/{fid}.json").read_text())
    ex = desc.get("executor") or {}
    assert ex.get("kind") == "driver", (fid, ex)
    path = ex.get("path") or f"scripts/drivers/{fid}.sh"
    assert (skill / path).is_file(), (fid, path)
    assert (skill / f"features/{fid}.md").is_file(), fid
    ids = [c.get("id") for c in (desc.get("cases") or [])]
    assert ids, fid
    for c in desc.get("cases") or []:
        assert c.get("required_assertions"), (fid, c)
readme = (skill / "features/README.md").read_text(encoding="utf-8")
assert "check-secrets.md" in readme, "README sin check-secrets"
assert "capture-payloads.md" in readme, "README sin capture-payloads"
PY
[ -f "$DRV_SECRETS" ] || malo "falta drivers/check-secrets.sh"
[ -f "$DRV_CAPTURE" ] || malo "falta drivers/capture-payloads.sh"
if [ -f "$DRV_SECRETS" ]; then
  bash -n "$DRV_SECRETS" || malo "bash -n fallo en check-secrets.sh"
fi
if [ -f "$DRV_CAPTURE" ]; then
  bash -n "$DRV_CAPTURE" || malo "bash -n fallo en capture-payloads.sh"
fi

caso "CI suite provisiona gitleaks con el mismo pin que secrets"
python3 - "$WF" <<'PY' || malo "suite no provisiona detector fuerte pinneado"
import re, sys
from pathlib import Path
text = Path(sys.argv[1]).read_text(encoding="utf-8")
pin = "8.30.1"
sha = "551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb"
parts = re.split(r"\n  ([A-Za-z0-9-]+):\n", text)
jobs = {}
i = 1
while i + 1 < len(parts):
    jobs[parts[i]] = parts[i + 1]
    i += 2
for name in ("suite", "secrets"):
    body = jobs.get(name) or ""
    assert pin in body, (name, "sin version 8.30.1")
    assert sha in body, (name, "sin sha256 pinneado")
    assert "gitleaks" in body, (name, "sin gitleaks")
# Tenerlo solo en secrets no cuenta: suite debe descargar/verificar.
suite = jobs.get("suite") or ""
assert "sha256sum" in suite or "sha256sum -c" in suite, "suite no verifica hash"
assert "gitleaks_" + pin in suite or f"v{pin}" in suite, "suite no baja el tarball pinneado"
PY

# ---------------------------------------------------------------------------
# Launch aislado
# ---------------------------------------------------------------------------
caso "launch aislado para drives 19.12"
if ! out="$(ctrl launch 2>&1)"; then
  malo "launch fallo: $out"
  echo "FAIL: $fail aserciones (sin launch no hay drives)" >&2
  exit 1
fi
printf '%s' "$out" | grep -q 'launched run_id=' || malo "launch sin run_id: $out"

# ---------------------------------------------------------------------------
# Drive check-secrets
# ---------------------------------------------------------------------------
caso "drive check-secrets: fuerte/fallback/redaccion"
reset_art
out="$(ctrl drive check-secrets 2>&1)" && rc=0 || rc=$?
if has_gitleaks && can_force_fallback; then
  [ "$rc" -eq 0 ] || malo "drive check-secrets rc=$rc (gitleaks presente): $out"
else
  [ "$rc" -eq 0 ] || [ "$rc" -eq 3 ] \
    || malo "drive check-secrets rc=$rc (esperado 0 o unknown/3): $out"
fi
sum="$(latest_summary check-secrets)"
[ -n "$sum" ] && [ -f "$sum" ] || malo "check-secrets sin summary"
if [ -n "$sum" ] && [ -f "$sum" ]; then
python3 - "$sum" <<'PY' || malo "check-secrets summary incompleto"
import json, sys
s = json.loads(open(sys.argv[1], encoding="utf-8").read())
cases = s.get("cases") or s.get("cases_requested") or []
text = " ".join(cases) if not isinstance(cases, str) else cases
for need in ("secrets-strong", "secrets-fallback", "secrets-redaction"):
    assert need in text, (need, cases)
assert s.get("result") in ("PASS", "unknown"), s
PY
fi

if has_gitleaks; then
  assert_obs check-secrets strong_clean 'limpio|clean|0'
  assert_obs check-secrets strong_trap 'trampa|trap|1'
else
  assert_result check-secrets strong_clean unknown
  assert_result check-secrets strong_trap unknown
fi

if can_force_fallback; then
  assert_obs check-secrets fallback_warning 'AVISO|sin gitleaks|veredicto'
  assert_obs check-secrets fallback_limit 'sin gitleaks|NO es el veredicto|limite|limit'
else
  assert_result check-secrets fallback_warning unknown
  assert_result check-secrets fallback_limit unknown
fi

assert_obs check-secrets report_no_secret 'sin valor|redact|no.leak|ausente'
assert_obs check-secrets evidence_no_secret 'cero|zero|ausente|sin coincidenc'

if ! scan_art_for_synth; then
  malo "secreto sintetico aparecio en evidencia de check-secrets"
fi

# ---------------------------------------------------------------------------
# Drive capture-payloads
# ---------------------------------------------------------------------------
caso "drive capture-payloads: instalar, sintético, cwd/permisos, ajeno"
reset_art
out="$(ctrl drive capture-payloads 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 0 ] || malo "drive capture-payloads rc=$rc: $out"
sum="$(latest_summary capture-payloads)"
[ -n "$sum" ] && [ -f "$sum" ] || malo "capture-payloads sin summary"
if [ -n "$sum" ] && [ -f "$sum" ]; then
python3 - "$sum" <<'PY' || malo "capture-payloads summary incompleto"
import json, sys
s = json.loads(open(sys.argv[1], encoding="utf-8").read())
assert s.get("result") == "PASS" and s.get("exit_code") == 0, s
cases = s.get("cases") or s.get("cases_requested") or []
text = " ".join(cases) if not isinstance(cases, str) else cases
for need in ("capture-lifecycle", "capture-redaction"):
    assert need in text, (need, cases)
PY
fi

assert_obs capture-payloads installed 'settings|marca|owned|gitignore'
assert_obs capture-payloads synthetic_saved 'payload|sintetic|evento|UserPromptSubmit'
assert_obs capture-payloads perms_private '600|privado|umask|owner'
assert_obs capture-payloads cwd_filtered 'cwd|filtro|no escribio|absent'
assert_obs capture-payloads retirada_own 'quitado|retirad|removed'
assert_obs capture-payloads foreign_intact 'intact|igual|unchanged|ajeno'
assert_obs capture-payloads evidence_no_secret 'cero|zero|ausente|sin coincidenc'

if ! scan_art_for_synth; then
  malo "secreto sintetico aparecio en evidencia de capture-payloads"
fi

# No se cargan capturas reales para probar redaccion.
if grep -R --include='*.sh' -E 'tests/fixtures/escenarios|VERIFY_REPO/capturas' \
     "$DRV_CAPTURE" >/dev/null 2>&1; then
  malo "capture driver carga capturas reales para redaccion"
fi

# ---------------------------------------------------------------------------
# Encabezado falso + rc 0 no acredita
# ---------------------------------------------------------------------------
caso "encabezado falso con rc 0 no acredita redaccion ni ajeno"
reset_art
stub="$SANDBOX/header-only-secrets.sh"
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
assert secrets-strong strong_clean "secrets ok"
assert secrets-strong strong_trap "secrets ok"
assert secrets-fallback fallback_warning "secrets ok"
assert secrets-fallback fallback_limit "secrets ok"
assert secrets-redaction report_no_secret "secrets ok"
assert secrets-redaction evidence_no_secret "secrets ok"
exit 0
EOF
chmod +x "$stub"
ctrl_drv "$stub" drive check-secrets >/dev/null 2>&1 || true
steps="$(latest_steps check-secrets)"
if [ -n "$steps" ] && [ -f "$steps" ]; then
python3 - "$steps" <<'PY' || malo "header-only acredito fallback_warning real"
import json, re, sys
for line in open(sys.argv[1], encoding="utf-8"):
    if not line.strip():
        continue
    rec = json.loads(line)
    obs = str(rec.get("observed") or "")
    if (
        rec.get("assertion_id") == "fallback_warning"
        and rec.get("result") == "PASS"
        and re.search(r"AVISO|sin gitleaks|veredicto", obs)
        and "secrets ok" not in obs
    ):
        raise SystemExit("header-only acredito fallback_warning")
raise SystemExit(0)
PY
fi

# ---------------------------------------------------------------------------
# Mutantes
# ---------------------------------------------------------------------------
if [ -f "$DRV_SECRETS" ]; then
  cp "$DRV_SECRETS" "$SANDBOX/secrets.src.sh"
  chmod +x "$SANDBOX/secrets.src.sh"
fi
if [ -f "$DRV_CAPTURE" ]; then
  cp "$DRV_CAPTURE" "$SANDBOX/capture.src.sh"
  chmod +x "$SANDBOX/capture.src.sh"
fi

mut_omit_secrets() {
  local label="$1" asid="$2" signal="$3" expr="$4"
  caso "mutante $label: omitir $asid se pone rojo"
  reset_art
  local mut="$SANDBOX/secrets-$label.sh"
  if [ ! -f "$SANDBOX/secrets.src.sh" ]; then
    malo "$label: sin driver fuente"; return
  fi
  if sed_must_change "$SANDBOX/secrets.src.sh" "$mut" "$expr" "$label"; then
    out="$(ctrl_drv "$mut" drive check-secrets 2>&1)" && rc=0 || rc=$?
    assert_missing_or_fail check-secrets "$asid" "$signal" "$rc"
  fi
}

mut_omit_capture() {
  local label="$1" asid="$2" signal="$3" expr="$4"
  caso "mutante $label: omitir $asid se pone rojo"
  reset_art
  local mut="$SANDBOX/capture-$label.sh"
  if [ ! -f "$SANDBOX/capture.src.sh" ]; then
    malo "$label: sin driver fuente"; return
  fi
  if sed_must_change "$SANDBOX/capture.src.sh" "$mut" "$expr" "$label"; then
    out="$(ctrl_drv "$mut" drive capture-payloads 2>&1)" && rc=0 || rc=$?
    assert_missing_or_fail capture-payloads "$asid" "$signal" "$rc"
  fi
}

mut_omit_secrets omit_redaction evidence_no_secret 'cero|zero|ausente|sin coincidenc' \
  '/assert:evidence_no_secret/,/assert:evidence_no_secret_end/d'
mut_omit_secrets omit_fallback_warning fallback_warning 'AVISO|sin gitleaks|veredicto' \
  '/assert:fallback_warning/,/assert:fallback_warning_end/d'
mut_omit_capture omit_permissions perms_private '600|privado|umask|owner' \
  '/assert:perms_private/,/assert:perms_private_end/d'
mut_omit_capture omit_cwd cwd_filtered 'cwd|filtro|no escribio|absent' \
  '/assert:cwd_filtered/,/assert:cwd_filtered_end/d'
mut_omit_capture omit_foreign foreign_intact 'intact|igual|unchanged|ajeno' \
  '/assert:foreign_intact/,/assert:foreign_intact_end/d'

if [ "$fail" -ne 0 ]; then
  echo "FAIL: $fail aserciones" >&2
  exit 1
fi
echo "OK: test_feature_map_secrets_capture"
exit 0
