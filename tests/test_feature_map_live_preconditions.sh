#!/usr/bin/env bash
# tests/test_feature_map_live_preconditions.sh — 19.16: merge vivo inventariado.
#
# DoD: sin autorización/destino → unknown/BLOCKED y ninguna llamada externa;
# dependencias actuales nombradas; dobles no acreditan vivo; no transfiere
# sello hijo-padre; simulación no llena la aserción de merge vivo; medición
# viva sigue Optional (el procedimiento se define, no se ejecuta).
#
# Mutaciones (copia del driver; SAIKIT_FM_DRIVER):
#   perm_as_pass      — permiso faltante se presenta como PASS
#   fake_gh_as_live   — gh script acredita acceso vivo
#   seal_via_mtime    — sello hijo → padre por mtime/verified
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
. "$here/lib/sandbox.sh"; sandbox_init
fail=0
caso() { printf '  caso: %s\n' "$1"; }
malo() { printf '    FAIL: %s\n' "$1" >&2; fail=$((fail + 1)); }

SKILL="$repo/.cursor/skills/verify-summonaikit"
CTRL="$SKILL/scripts/control-summonaikit"
DRV="$SKILL/scripts/drivers/merge-happy-path.sh"
STATE="$SANDBOX/verify-state"
ART="$SANDBOX/verify-artifacts"
ORIG_PATH="$PATH"
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

assert_unknown() {
  local fid="$1" asid="$2" pat="$3"
  local steps
  steps="$(latest_steps "$fid")" || { malo "$fid: sin steps para $asid"; return; }
  python3 - "$steps" "$asid" "$pat" <<'PY' || malo "$fid: $asid no es unknown [$pat]"
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
if found.get("result") != "unknown":
    raise SystemExit(f"{asid} result={found.get('result')} (queríamos unknown) obs={obs!r}")
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

hide_from_path() {
  local name="$1"
  local out="$SANDBOX/path-without-$name"
  local d f base
  rm -rf "$out"
  mkdir -p "$out"
  local IFS=':'
  for d in $ORIG_PATH; do
    [ -d "$d" ] || continue
    for f in "$d"/*; do
      [ -e "$f" ] || [ -L "$f" ] || continue
      base="${f##*/}"
      [ "$base" = "$name" ] && continue
      [ -e "$out/$base" ] && continue
      ln -s "$f" "$out/$base" 2>/dev/null || true
    done
  done
  printf '%s' "$out"
}

install_probe_bin() {
  # $1=bin-dir $2=log-file — gh/curl/ssh que registran argv y no llaman red
  local bindir="$1" log="$2"
  mkdir -p "$bindir"
  cat > "$bindir/gh" <<EOF
#!/bin/sh
printf 'gh %s\\n' "\$*" >> "$log"
printf 'quota-burned %s\\n' "\$*"
exit 0
EOF
  cat > "$bindir/curl" <<EOF
#!/bin/sh
printf 'curl %s\\n' "\$*" >> "$log"
exit 0
EOF
  cat > "$bindir/ssh" <<EOF
#!/bin/sh
printf 'ssh %s\\n' "\$*" >> "$log"
exit 0
EOF
  chmod +x "$bindir/gh" "$bindir/curl" "$bindir/ssh"
}

# ---------------------------------------------------------------------------
# Inventario: solo lo propio + pendings verdaderos (dinámico)
# ---------------------------------------------------------------------------
caso "catalogo activa merge-happy-path blocked con ficha/descriptor/driver"
python3 - "$SKILL" <<'PY' || malo "catalogo/descriptor merge-happy-path incompleto"
import json, sys
from pathlib import Path
skill = Path(sys.argv[1])
cat = json.loads((skill / "features/catalog.json").read_text())
feats = cat.get("features") or {}
meta = feats.get("merge-happy-path") or {}
assert meta.get("status") == "blocked", meta
assert meta.get("card") in (
    "features/merge-happy-path.md",
    "merge-happy-path.md",
), meta
assert not meta.get("owner_task"), ("pending leftover", meta)
assert meta.get("execution_mode") == "live", meta
desc = json.loads((skill / "features/merge-happy-path.json").read_text())
ex = desc.get("executor") or {}
assert ex.get("kind") == "driver", ex
path = ex.get("path") or "scripts/drivers/merge-happy-path.sh"
assert (skill / path).is_file(), path
assert (skill / "features/merge-happy-path.md").is_file()
assert desc.get("execution_mode") == "live", desc
ids = [c.get("id") for c in (desc.get("cases") or [])]
for need in (
    "live-blocked-no-auth",
    "live-current-reasons",
    "live-manual-procedure",
    "live-no-sim-credit",
    "live-no-seal-transfer",
):
    assert need in ids, (need, ids)
for c in desc.get("cases") or []:
    assert c.get("required_assertions"), c
# Solo lo propio + lo que siga pending de verdad (no afirmar pending de activas)
own = feats.get("merge-happy-path") or {}
assert own.get("status") == "blocked", own
for fid, meta_f in feats.items():
    if fid == "merge-happy-path":
        continue
    st = meta_f.get("status")
    if st == "pending":
        assert meta_f.get("owner_task"), (fid, meta_f)
        assert not meta_f.get("card"), (fid, "pending no finge card", meta_f)
    elif st in ("active", "blocked"):
        assert meta_f.get("card"), (fid, meta_f)
readme = (skill / "features/README.md").read_text(encoding="utf-8")
assert "merge-happy-path.md" in readme, "README sin linea de merge-happy-path"
PY
[ -f "$DRV" ] || malo "falta drivers/merge-happy-path.sh"
[ -f "$SKILL/features/merge-happy-path.md" ] || malo "falta ficha merge-happy-path.md"
if [ -f "$DRV" ]; then
  bash -n "$DRV" || malo "bash -n fallo en merge-happy-path.sh"
fi

caso "list-features declara merge-happy-path blocked live"
out="$(ctrl list-features 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 0 ] || malo "list-features fallo: $out"
printf '%s' "$out" | grep -E 'id=merge-happy-path' | grep -q 'status=blocked' \
  || malo "list-features no bloquea merge-happy-path: $out"
printf '%s' "$out" | grep -E 'id=merge-happy-path' | grep -q 'mode=live' \
  || malo "list-features sin mode=live: $out"

# ---------------------------------------------------------------------------
# Drive sin instancia: unknown/BLOCKED, sin llamada externa
# ---------------------------------------------------------------------------
caso "drive sin instancia: unknown/BLOCKED y sonda gh/curl/ssh vacia"
reset_art
PROBELOG="$SANDBOX/ext-probe-noinst.log"
rm -f "$PROBELOG"
PROBEDIR="$SANDBOX/probe-bin-noinst"
install_probe_bin "$PROBEDIR" "$PROBELOG"
PATH="$PROBEDIR:$(hide_from_path gh)"
export PATH
out="$(ctrl drive merge-happy-path 2>&1)" && rc=0 || rc=$?
PATH="$ORIG_PATH"
export PATH
[ "$rc" -eq 3 ] || malo "sin instancia debio unknown/3 (got $rc): $out"
printf '%s' "$out" | grep -Eqi 'BLOCKED|unknown' \
  || malo "sin instancia sin BLOCKED/unknown: $out"
if [ -f "$PROBELOG" ]; then
  if grep -Eq 'gh (pr|api|auth|repo)|curl |ssh ' "$PROBELOG"; then
    malo "sin instancia hizo llamada externa: $(cat "$PROBELOG")"
  fi
fi

# ---------------------------------------------------------------------------
# Launch aislado
# ---------------------------------------------------------------------------
caso "launch aislado para drive merge-happy-path"
PATH="$ORIG_PATH"
export PATH
if ! out="$(ctrl launch 2>&1)"; then
  malo "launch fallo: $out"
  echo "FAIL: $fail aserciones (sin launch no hay drives)" >&2
  exit 1
fi
printf '%s' "$out" | grep -q 'launched run_id=' || malo "launch sin run_id: $out"

# ---------------------------------------------------------------------------
# Drive real de precondiciones (nunca merge vivo)
# ---------------------------------------------------------------------------
caso "drive merge-happy-path: BLOCKED, razones actuales, procedimiento, sin vivo"
reset_art
PROBELOG="$SANDBOX/ext-probe-drive.log"
rm -f "$PROBELOG"
PROBEDIR="$SANDBOX/probe-bin-drive"
install_probe_bin "$PROBEDIR" "$PROBELOG"
PATH="$PROBEDIR:$(hide_from_path gh)"
export PATH
out="$(ctrl drive merge-happy-path 2>&1)" && rc=0 || rc=$?
PATH="$ORIG_PATH"
export PATH
[ "$rc" -eq 3 ] || malo "drive precondiciones debio unknown/3 (got $rc): $out"
[ "$rc" -eq 0 ] && malo "drive no debe PASS/0 sin autorización viva: $out"

sum="$(latest_summary merge-happy-path)"
[ -n "$sum" ] && [ -f "$sum" ] || malo "merge-happy-path sin summary"
if [ -n "$sum" ] && [ -f "$sum" ]; then
python3 - "$sum" <<'PY' || malo "summary no es unknown/live o acredita merge vivo"
import json, sys
s = json.loads(open(sys.argv[1], encoding="utf-8").read())
assert s.get("result") == "unknown", s
assert s.get("exit_code") == 3, s
assert s.get("mode") == "live", s
assert s.get("result") != "PASS"
cases = s.get("cases") or s.get("cases_requested") or []
text = " ".join(cases) if not isinstance(cases, str) else cases
for need in (
    "live-blocked-no-auth",
    "live-current-reasons",
    "live-manual-procedure",
    "live-no-sim-credit",
    "live-no-seal-transfer",
):
    assert need in text, (need, cases)
PY
fi

assert_obs merge-happy-path blocked_unknown 'BLOCKED'
assert_obs merge-happy-path no_external_call 'no-external-call'
assert_obs merge-happy-path reason_auth_dest 'autoriz'
assert_obs merge-happy-path reason_gh 'gh'
assert_obs merge-happy-path procedure_defined 'topic'
assert_obs merge-happy-path procedure_not_run 'no-autoriza-ejecutar'
assert_obs merge-happy-path sim_not_live 'simulated'
assert_unknown merge-happy-path live_merge 'live-merge-not-run'
assert_obs merge-happy-path parent_seal_untouched 'parent-untouched'
assert_obs merge-happy-path no_mtime_transfer 'no-mtime-transfer'
assert_obs merge-happy-path no_verified_transfer 'no-verified-transfer'

if [ -f "$PROBELOG" ]; then
  if grep -Eq 'gh (pr|api|auth|repo|run)|curl |ssh ' "$PROBELOG"; then
    malo "drive hizo llamada externa: $(cat "$PROBELOG")"
  fi
fi

# Doctor scoped: unknown/BLOCKED, razones actuales, sin PASS
caso "doctor --feature-id merge-happy-path: unknown/BLOCKED razones actuales"
PATH="$PROBEDIR:$(hide_from_path gh)"
export PATH
out="$(ctrl doctor merge-happy-path 2>&1)" && drc=0 || drc=$?
PATH="$ORIG_PATH"
export PATH
[ "$drc" -eq 3 ] || malo "doctor scoped debio 3 (got $drc): $out"
[ "$drc" -eq 0 ] && malo "doctor scoped no debe PASS: $out"
python3 - "$ART/doctor.json" <<'PY' || malo "doctor scoped no BLOCKED/razones"
import json, sys
from pathlib import Path
d = json.loads(Path(sys.argv[1]).read_text())
mh = d["features"]["merge-happy-path"]
assert mh["result"] == "unknown", mh
assert mh["availability"] in ("MISSING", "BLOCKED"), mh
assert mh["result"] != "PASS"
blob = json.dumps(mh, ensure_ascii=False).lower()
assert "autoriz" in blob, mh
assert "gh" in blob, mh
PY

# Doctor global sigue PASS (blocked live no tumba el agregado local)
caso "doctor global: activas locales PASS; merge-happy-path en blocked"
out="$(ctrl doctor 2>&1)" && grc=0 || grc=$?
[ "$grc" -eq 0 ] || malo "doctor global debio 0 con live blocked (got $grc): $out"
printf '%s' "$out" | grep -q 'doctor: PASS' \
  || malo "doctor global no dijo PASS: $out"
python3 - "$ART/doctor.json" <<'PY' || malo "agregado global tumbo por live blocked"
import json, sys
from pathlib import Path
d = json.loads(Path(sys.argv[1]).read_text())
assert d["result"] == "PASS" and d["exit_code"] == 0, d
mh = d["features"]["merge-happy-path"]
assert mh["result"] != "PASS", mh
assert "merge-happy-path" in d["blocked"], d["blocked"]
assert "merge-happy-path" not in d["ready"], d["ready"]
PY

# ---------------------------------------------------------------------------
# Mutantes nombrados
# ---------------------------------------------------------------------------
if [ -f "$DRV" ]; then
  copy_driver "$SANDBOX/mhp.src.sh"

  caso "mutante perm_as_pass: permiso faltante como PASS se pone rojo"
  reset_art
  mut="$SANDBOX/mhp-perm_as_pass.sh"
  if sed_must_change "$SANDBOX/mhp.src.sh" "$mut" \
    '/mutate:perm_as_pass$/,/mutate:perm_as_pass_end$/s/auth_result=unknown/auth_result=PASS/; /mutate:perm_as_pass$/,/mutate:perm_as_pass_end$/s/auth_avail=BLOCKED/auth_avail=ready/' \
    perm_as_pass
  then
    out="$(ctrl_drv "$mut" drive merge-happy-path 2>&1)" && mrc=0 || mrc=$?
    assert_missing_or_fail merge-happy-path blocked_unknown 'BLOCKED' "$mrc"
    [ "$mrc" -eq 0 ] && malo "perm_as_pass no debio dejar drive en PASS/0"
  fi

  caso "mutante fake_gh_as_live: gh script como vivo se pone rojo"
  reset_art
  mut="$SANDBOX/mhp-fake_gh_as_live.sh"
  if sed_must_change "$SANDBOX/mhp.src.sh" "$mut" \
    '/mutate:fake_gh_as_live$/,/mutate:fake_gh_as_live_end$/s/gh_live=no/gh_live=yes/' \
    fake_gh_as_live
  then
    PATH="$PROBEDIR:$(hide_from_path gh)"
    export PATH
    out="$(ctrl_drv "$mut" drive merge-happy-path 2>&1)" && mrc=0 || mrc=$?
    PATH="$ORIG_PATH"
    export PATH
    assert_missing_or_fail merge-happy-path reason_gh 'falso' "$mrc"
    [ "$mrc" -eq 0 ] && malo "fake_gh_as_live no debio dejar drive en PASS/0"
  fi

  caso "mutante seal_via_mtime: sello hijo a padre se pone rojo"
  reset_art
  mut="$SANDBOX/mhp-seal_via_mtime.sh"
  if sed_must_change "$SANDBOX/mhp.src.sh" "$mut" \
    '/mutate:seal_via_mtime$/,/mutate:seal_via_mtime_end$/s/do_transfer=no/do_transfer=yes/' \
    seal_via_mtime
  then
    out="$(ctrl_drv "$mut" drive merge-happy-path 2>&1)" && mrc=0 || mrc=$?
    assert_missing_or_fail merge-happy-path parent_seal_untouched 'parent-untouched' "$mrc"
    [ "$mrc" -eq 0 ] && malo "seal_via_mtime no debio dejar drive en PASS/0"
  fi
fi

if [ "$fail" -ne 0 ]; then
  echo "FAIL: $fail aserciones" >&2
  exit 1
fi
echo "OK: test_feature_map_live_preconditions"
exit 0
