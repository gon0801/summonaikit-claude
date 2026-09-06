#!/usr/bin/env bash
# tests/test_feature_map_postmerge.sh — 19.7: drive saikit-postmerge simulado.
# Base: tests/test_saikit_postmerge.sh. Invoca tools/saikit-postmerge.sh real
# sobre Git/origin locales y gh/curl/telegram falsos. Un transporte imprevisto
# falla. Rojo avisa revert sin ejecutarlo. unknown se declara. Avisos redactados.
#
# Mutaciones discriminantes (copia del driver en sandbox; SAIKIT_FM_DRIVER):
#   auto_revert        — ejecuta git revert tras el rojo
#   accept_ci_red      — omite la asercion de veredicto ROJO
#   omit_revert_text   — omite el comando PARA REVERTIR / --revert-de
#   omit_redact        — omite la redaccion del secreto sintético
#   inherit_transport  — no antepone los dobles; usa PATH heredado
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
  find "$ART" -path "*/*/${fid}/*/summary.json" -type f \
    | awk -F/ '{print $0}' | tail -1
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
  cp "$SKILL/scripts/drivers/saikit-postmerge.sh" "$1"
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
# Descriptor / catalogo / ficha
# ---------------------------------------------------------------------------
caso "catalogo activo, descriptor driver y ficha con triples"
python3 - "$SKILL" <<'PY' || malo "saikit-postmerge no esta activo con driver"
import json, sys
from pathlib import Path
skill = Path(sys.argv[1])
cat = json.loads((skill / "features" / "catalog.json").read_text())
meta = cat["features"]["saikit-postmerge"]
assert meta.get("status") == "active", meta
assert meta.get("card"), meta
desc = json.loads((skill / "features" / "saikit-postmerge.json").read_text())
assert desc.get("id") == "saikit-postmerge"
assert desc.get("execution_mode") == "simulated", desc
ex = desc.get("executor") or {}
assert ex.get("kind") == "driver", ex
path = skill / (ex.get("path") or "scripts/drivers/saikit-postmerge.sh")
assert path.is_file(), path
cases = [c["id"] for c in desc["cases"]]
for need in ("postmerge-green", "postmerge-red", "postmerge-pending",
             "postmerge-no-run", "postmerge-redacted", "postmerge-transport"):
    assert need in cases, (need, cases)
PY
bash -n "$SKILL/scripts/drivers/saikit-postmerge.sh" \
  || malo "bash -n fallo en drivers/saikit-postmerge.sh"

# ---------------------------------------------------------------------------
# Launch + drive real
# ---------------------------------------------------------------------------
caso "launch aislado para drive postmerge"
if ! out="$(ctrl launch 2>&1)"; then
  malo "launch fallo: $out"
  echo "FAIL: $fail aserciones (sin launch no hay drives)" >&2
  exit 1
fi
printf '%s' "$out" | grep -q 'launched run_id=' || malo "launch sin run_id: $out"

# Sentinelas heredados: si el driver no aisla, el tool los usa y fallan.
INH="$SANDBOX/inherited-bin"
INH_LOG="$SANDBOX/inherited.log"
mkdir -p "$INH"
: > "$INH_LOG"
for name in gh curl telegram-send; do
  cat > "$INH/$name" <<EOF
#!/usr/bin/env bash
printf 'INHERITED %s %s\n' "$name" "\$*" >> "$INH_LOG"
printf 'inherited-sentinel: %s no previsto\n' "$name" >&2
exit 1
EOF
  chmod +x "$INH/$name"
done
PATH="$INH:$PATH"
export PATH

caso "drive saikit-postmerge: verde/rojo/unknown/redactado/transporte"
reset_art
out="$(ctrl drive saikit-postmerge 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 0 ] || malo "drive saikit-postmerge rc=$rc: $out"
sum="$(latest_summary saikit-postmerge)"
[ -n "$sum" ] && [ -f "$sum" ] || malo "saikit-postmerge sin summary"
if [ -n "$sum" ] && [ -f "$sum" ]; then
python3 - "$sum" <<'PY' || malo "summary postmerge incompleto o no simulated"
import json, sys
s = json.loads(open(sys.argv[1], encoding="utf-8").read())
assert s.get("result") == "PASS" and s.get("exit_code") == 0, s
assert s.get("mode") == "simulated", s
cases = s.get("cases") or s.get("cases_requested") or []
text = " ".join(cases) if not isinstance(cases, str) else cases
for need in ("postmerge-green", "postmerge-red", "postmerge-pending",
             "postmerge-no-run", "postmerge-redacted", "postmerge-transport"):
    assert need in text, (need, cases)
PY
fi

assert_obs saikit-postmerge tool_exit_0 '^exit 0$'
assert_obs saikit-postmerge verdict_verde 'VERDE'
assert_obs saikit-postmerge no_revert_offered 'sin PARA REVERTIR'
assert_obs saikit-postmerge tool_exit_1 '^exit 1$'
assert_obs saikit-postmerge verdict_rojo 'ROJO'
assert_obs saikit-postmerge revert_cmd 'PARA REVERTIR'
assert_obs saikit-postmerge revert_cmd '--revert-de'
assert_obs saikit-postmerge tree_intact 'HEAD/worktree intactos'
assert_obs saikit-postmerge tool_exit_3 '^exit 3$'
assert_obs saikit-postmerge verdict_unknown 'UNKNOWN'
assert_obs saikit-postmerge unknown_pendiente 'pendiente'
assert_obs saikit-postmerge unknown_sin_run 'sin run'
assert_obs saikit-postmerge secret_redacted '\[REDACTED\]'
assert_obs saikit-postmerge raw_secret_absent 'ausente'
assert_obs saikit-postmerge unexpected_gh_fails 'gh imprevisto fallo'
assert_obs saikit-postmerge unexpected_curl_fails 'curl imprevisto fallo'
assert_obs saikit-postmerge unexpected_tg_fails 'telegram imprevisto fallo'
assert_obs saikit-postmerge only_expected_calls 'solo llamadas previstas'

# El secreto sintetico no viaja a artefactos conservados.
if grep -R -F -q 'synthetic-redact-probe' "$ART" 2>/dev/null; then
  malo "secreto sintetico synthetic-redact-probe aparecio en artifacts"
fi
if [ -s "$INH_LOG" ]; then
  malo "el drive honesto uso transporte heredado: $(cat "$INH_LOG")"
fi

# ---------------------------------------------------------------------------
# Mutantes
# ---------------------------------------------------------------------------
copy_driver "$SANDBOX/postmerge.src.sh"

caso "mutante auto_revert: revert automatico pone rojo tree_intact"
reset_art
mut="$SANDBOX/postmerge-auto-revert.sh"
if sed_must_change "$SANDBOX/postmerge.src.sh" "$mut" \
  's/SAIKIT_FM_AUTO_REVERT=0/SAIKIT_FM_AUTO_REVERT=1/' \
  "auto_revert"
then
  out="$(ctrl_drv "$mut" drive saikit-postmerge 2>&1)" && rc=0 || rc=$?
  assert_missing_or_fail saikit-postmerge tree_intact 'HEAD/worktree intactos' "$rc"
fi

caso "mutante accept_ci_red: CI rojo acreditado como OK se pone rojo"
reset_art
mut="$SANDBOX/postmerge-accept-red.sh"
if sed_must_change "$SANDBOX/postmerge.src.sh" "$mut" \
  '/assert:verdict_rojo/,/assert:verdict_rojo_end/d' \
  "accept_ci_red"
then
  out="$(ctrl_drv "$mut" drive saikit-postmerge 2>&1)" && rc=0 || rc=$?
  assert_missing_or_fail saikit-postmerge verdict_rojo 'ROJO' "$rc"
fi

caso "mutante omit_revert_text: sin comando de revert se pone rojo"
reset_art
mut="$SANDBOX/postmerge-omit-revert.sh"
if sed_must_change "$SANDBOX/postmerge.src.sh" "$mut" \
  '/assert:revert_cmd/,/assert:revert_cmd_end/d' \
  "omit_revert_text"
then
  out="$(ctrl_drv "$mut" drive saikit-postmerge 2>&1)" && rc=0 || rc=$?
  assert_missing_or_fail saikit-postmerge revert_cmd 'PARA REVERTIR' "$rc"
fi

caso "mutante omit_redact: sin redaccion se pone rojo"
reset_art
mut="$SANDBOX/postmerge-omit-redact.sh"
if sed_must_change "$SANDBOX/postmerge.src.sh" "$mut" \
  '/assert:secret_redacted/,/assert:raw_secret_absent_end/d' \
  "omit_redact"
then
  out="$(ctrl_drv "$mut" drive saikit-postmerge 2>&1)" && rc=0 || rc=$?
  assert_missing_or_fail saikit-postmerge secret_redacted '\[REDACTED\]' "$rc"
fi

caso "mutante inherit_transport: PATH heredado se pone rojo"
reset_art
: > "$INH_LOG"
mut="$SANDBOX/postmerge-inherit.sh"
if sed_must_change "$SANDBOX/postmerge.src.sh" "$mut" \
  's/SAIKIT_FM_ISOLATE_TRANSPORT=1/SAIKIT_FM_ISOLATE_TRANSPORT=0/' \
  "inherit_transport"
then
  out="$(ctrl_drv "$mut" drive saikit-postmerge 2>&1)" && rc=0 || rc=$?
  # Sin dobles del caso, el transporte heredado (stub fail-closed) impide VERDE.
  assert_missing_or_fail saikit-postmerge tool_exit_0 '^exit 0$' "$rc"
fi

if [ "$fail" -ne 0 ]; then
  echo "FAIL: $fail aserciones" >&2
  exit 1
fi
echo "OK: test_feature_map_postmerge"
exit 0
