#!/usr/bin/env bash
# Regression for cross-review findings (duplicate _feature_mode, synthetic
# without allow, SAIKIT_FM_DRIVER path escape).
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
. "$here/lib/sandbox.sh"; sandbox_init
fail=0
caso() { printf '  caso: %s\n' "$1"; }
malo() { printf '    FAIL: %s\n' "$1" >&2; fail=1; }

SKILL="$repo/.cursor/skills/verify-summonaikit"
CTRL="$SKILL/scripts/control-summonaikit"
STATE="$SANDBOX/verify-state"
ART="$SANDBOX/verify-artifacts"
mkdir -p "$STATE" "$ART"

caso "una sola _feature_mode (sin sombra post-merge)"
n="$(grep -c '^_feature_mode()' "$CTRL" || true)"
[ "$n" = 1 ] || malo "esperaba 1 _feature_mode(), hay $n"

caso "helper _feature_mode usa fallback de catalog (live)"
tmp=$(mktemp -d "$TMPDIR/fm-mode-XXXXXX")
# Build a mini bash that sources only the kept helper by extracting via sed.
# After the fix, control has one def; before, count fails above.
python3 - "$CTRL" "$SKILL" "$tmp" <<'PY' || malo "catalog fallback via control probe fallo"
import json, re, subprocess, sys, textwrap
from pathlib import Path
ctrl_path, skill, tmp = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
text = ctrl_path.read_text(encoding="utf-8")
m = re.search(r"^_feature_mode\(\) \{.*?\n\}$", text, re.M | re.S)
if not m:
    raise SystemExit("no _feature_mode body")
# Prefer the catalog-aware body if multiple (pre-fix): last wins in bash, so
# for the probe we take the FIRST match that mentions CATALOG.
bodies = list(re.finditer(r"^_feature_mode\(\) \{.*?\n\}$", text, re.M | re.S))
body = bodies[0].group(0)
if "CATALOG" not in body and len(bodies) > 1:
    for b in bodies:
        if "CATALOG" in b.group(0):
            body = b.group(0)
            break
feat = json.loads((skill / "features/setup-autopilot.json").read_text())
feat.pop("execution_mode", None)
(tmp / "setup-autopilot.json").write_text(json.dumps(feat, indent=2) + "\n")
cat = json.loads((skill / "features/catalog.json").read_text())
cat["features"]["setup-autopilot"]["execution_mode"] = "live"
(tmp / "catalog.json").write_text(json.dumps(cat) + "\n")
probe = tmp / "probe.sh"
probe.write_text(
    "#!/usr/bin/env bash\nset -euo pipefail\n"
    f"skill_root={tmp}\nCATALOG={tmp / 'catalog.json'}\n"
    f"{body}\n"
    "_feature_mode setup-autopilot\n"
)
out = subprocess.check_output(["bash", str(probe)], text=True).strip()
if out != "live":
    raise SystemExit(f"got {out!r} want live")
PY

caso "synthetic sin ALLOW se rechaza"
out="$(
  SAIKIT_VERIFY_SYNTHETIC_EXECUTOR=PASS \
  SAIKIT_VERIFY_STATE="$STATE" SAIKIT_VERIFY_ARTIFACTS="$ART" \
    bash "$CTRL" drive setup-autopilot 2>&1
)" && rc=0 || rc=$?
[ "$rc" -ne 0 ] || malo "synthetic sin ALLOW debio fallar, rc=0 out=$out"
printf '%s' "$out" | grep -qiE 'ALLOW_SYNTHETIC|synthetic.*refus|rechaz' \
  || malo "mensaje de rechazo synthetic ausente: $out"

caso "synthetic con ALLOW=PASS sigue en verde"
rm -rf "$ART"; mkdir -p "$ART"
out="$(
  SAIKIT_VERIFY_ALLOW_SYNTHETIC=1 \
  SAIKIT_VERIFY_SYNTHETIC_EXECUTOR=PASS \
  SAIKIT_VERIFY_STATE="$STATE" SAIKIT_VERIFY_ARTIFACTS="$ART" \
    bash "$CTRL" drive install-guardian 2>&1
)" && rc=0 || rc=$?
[ "$rc" -eq 0 ] || malo "ALLOW+PASS debio exit 0: $out"
n="$(find "$ART" -name summary.json | wc -l | tr -d ' ')"
[ "$n" -ge 1 ] || malo "ALLOW+PASS no escribio summary"

caso "SAIKIT_FM_DRIVER fuera de allowlist se bloquea"
evil="$(mktemp /tmp/evil-fm-XXXXXX.sh)"
printf '#!/bin/bash\necho EVIL\nexit 0\n' >"$evil"
chmod +x "$evil"
case "$evil" in
  "$SANDBOX"/*) malo "temp under sandbox; test invalid"; evil="" ;;
esac
if [ -n "$evil" ]; then
  # launch so we do not confuse "sin instancia" with allowlist
  ctrl() {
    SAIKIT_VERIFY_STATE="$STATE" SAIKIT_VERIFY_ARTIFACTS="$ART" \
      bash "$CTRL" "$@"
  }
  ctrl launch >/dev/null 2>&1 || true
  out="$(
    SAIKIT_FM_DRIVER="$evil" \
    SAIKIT_VERIFY_STATE="$STATE" SAIKIT_VERIFY_ARTIFACTS="$ART" \
      bash "$CTRL" drive autopilot-contract 2>&1
  )" && rc=0 || rc=$?
  [ "$rc" -ne 0 ] || malo "driver externo debio bloquearse: $out"
  printf '%s' "$out" | grep -qiE 'allowlist|fuera de allowlist' \
    || malo "sin senal de rechazo FM_DRIVER: $out"
  rm -f "$evil"
fi

if [ "$fail" -ne 0 ]; then
  echo "FAIL: $fail aserciones" >&2
  exit 1
fi
echo "OK: test_feature_map_xr_fixes"
exit 0
