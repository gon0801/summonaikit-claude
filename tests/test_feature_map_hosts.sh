#!/usr/bin/env bash
# tests/test_feature_map_hosts.sh — 19.11: install-hosts + routing-recipes.
#
# DoD: destinos aislados, identidad/no-op/retirada y ajenos intactos;
# registro juzgado por texto/estructura; mutantes host/fase/hash/symlink
# rojos; diferencias OS explicitas; no acredita turnos vivos ni implementa 16.7.
#
# Mutaciones (copia del driver en sandbox; SAIKIT_FM_DRIVER):
#   omit_dest_host       — quita la asercion de la copia grok
#   omit_fase            — quita la asercion de fases de registro
#   omit_noop            — quita YA AL DIA / dest unchanged
#   omit_foreign         — quita ajeno intacto
#   omit_symlink         — quita rechazo de symlink
#   omit_hash            — quita dest_matches_source
#   omit_routing         — quita claude_implementer
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
CATALOG="$SKILL/features/catalog.json"
DRV_HOSTS="$SKILL/scripts/drivers/install-hosts.sh"
DRV_ROUTING="$SKILL/scripts/drivers/routing-recipes.sh"
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

# ---------------------------------------------------------------------------
# Inventario: ambas features pending→active, drivers, no 16.7
# ---------------------------------------------------------------------------
caso "catalogo activa install-hosts y routing-recipes"
python3 - "$SKILL" <<'PY' || malo "catalogo/descriptores 19.11 incompletos"
import json, sys
from pathlib import Path
skill = Path(sys.argv[1])
cat = json.loads((skill / "features/catalog.json").read_text())
feats = cat.get("features") or {}
for fid in ("install-hosts", "routing-recipes"):
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
PY
[ -f "$DRV_HOSTS" ] || malo "falta drivers/install-hosts.sh"
[ -f "$DRV_ROUTING" ] || malo "falta drivers/routing-recipes.sh"
if [ -f "$DRV_HOSTS" ]; then
  bash -n "$DRV_HOSTS" || malo "bash -n fallo en install-hosts.sh"
fi
if [ -f "$DRV_ROUTING" ]; then
  bash -n "$DRV_ROUTING" || malo "bash -n fallo en routing-recipes.sh"
fi
# 16.7 no se implementa: --task no existe en el router
if grep -E -- '--task' "$repo/tools/model-routing.sh" | grep -vqE '^\s*#'; then
  malo "model-routing.sh implemento --task (Optional 16.7 fuera de alcance)"
fi

caso "list-features declara ambas active sandbox"
out="$(ctrl list-features 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 0 ] || malo "list-features fallo: $out"
printf '%s' "$out" | grep -E 'id=install-hosts' | grep -q 'status=active' \
  || malo "list-features no activa install-hosts: $out"
printf '%s' "$out" | grep -E 'id=routing-recipes' | grep -q 'status=active' \
  || malo "list-features no activa routing-recipes: $out"

# ---------------------------------------------------------------------------
# Launch aislado
# ---------------------------------------------------------------------------
caso "launch aislado para drives 19.11"
if ! out="$(ctrl launch 2>&1)"; then
  malo "launch fallo: $out"
  echo "FAIL: $fail aserciones (sin launch no hay drives)" >&2
  exit 1
fi
printf '%s' "$out" | grep -q 'launched run_id=' || malo "launch sin run_id: $out"

# ---------------------------------------------------------------------------
# Drive install-hosts
# ---------------------------------------------------------------------------
caso "drive install-hosts: cuatro copias, zcode/kimi, registro, OS, no vivo"
reset_art
out="$(ctrl drive install-hosts 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 0 ] || malo "drive install-hosts rc=$rc: $out"
sum="$(latest_summary install-hosts)"
[ -n "$sum" ] && [ -f "$sum" ] || malo "install-hosts sin summary"
if [ -n "$sum" ] && [ -f "$sum" ]; then
python3 - "$sum" <<'PY' || malo "install-hosts summary incompleto"
import json, sys
s = json.loads(open(sys.argv[1], encoding="utf-8").read())
assert s.get("result") == "PASS" and s.get("exit_code") == 0, s
cases = s.get("cases") or s.get("cases_requested") or []
text = " ".join(cases) if not isinstance(cases, str) else cases
for need in (
    "hosts-four-copies", "hosts-zcode-reuses", "hosts-kimi-profiles",
    "hosts-identity", "hosts-noop", "hosts-retirada", "hosts-foreign",
    "hosts-registration", "hosts-os-unavailable", "hosts-symlink",
    "hosts-no-live",
):
    assert need in text, (need, cases)
PY
fi

assert_obs install-hosts claude_hook 'claude'
assert_obs install-hosts grok_hook 'grok'
assert_obs install-hosts dsh_hook 'dsh'
assert_obs install-hosts codex_hook 'codex'
assert_obs install-hosts zcode_no_hook_copy 'sin copia|no.hook|reusa|absent'
assert_obs install-hosts kimi_no_hook_copy 'sin copia|no.hook|absent|perfiles'
assert_obs install-hosts zcode_reuses_claude 'reusa|claude|fases|UserPromptSubmit'
assert_obs install-hosts zcode_dest_untouched 'unchanged|intact|igual'
assert_obs install-hosts kimi_profiles 'implementer|reviewer|adversary'
assert_obs install-hosts kimi_no_model 'sin model|no model|sin ruteo'
assert_obs install-hosts kimi_dest_untouched 'unchanged|intact|igual'
assert_obs install-hosts ownership_marker 'SAIKIT-CLAUDE-OWNED'
assert_obs install-hosts dest_matches_source '[a-f0-9]{12,}'
assert_obs install-hosts procedencia 'procedencia: rama='
assert_obs install-hosts ya_al_dia 'YA AL DIA'
assert_obs install-hosts dest_unchanged 'unchanged|igual|intact'
assert_obs install-hosts retirada_preserva 'quitado|retirad|backup|intact'
assert_obs install-hosts neighbor_intact_after_retirada 'intact|igual|unchanged'
assert_obs install-hosts foreign_intact 'intact|igual|unchanged'
assert_obs install-hosts registro_por_texto 'REGISTRO|INCOMPLETO|completo|fases|UserPromptSubmit|GROK|DSH'
assert_obs install-hosts registro_no_solo_exit 'texto|estructura|no.exit.0|diagnostico'
assert_obs install-hosts fases_estructura 'UserPromptSubmit|PostToolUse|SessionStart|Stop'
assert_obs install-hosts other_hosts_observed 'claude|grok|dsh|codex'
assert_obs install-hosts no_live_turn 'no acredita|sin turno vivo|no live'
assert_obs install-hosts no_dsh_adapter_load 'sin carga|no adapter|no acredita'

# OS: la rama ausente se declara en el texto y no tumba a los otros hosts
if command -v cygpath >/dev/null 2>&1; then
  assert_obs install-hosts posix_wrap 'unknown|no observada|POSIX'
  assert_obs install-hosts windows_wrap 'ps1|cygpath|Windows|&|unknown|host-unavailable'
else
  assert_obs install-hosts windows_wrap 'unknown|sin cygpath|no observada'
  assert_obs install-hosts posix_wrap 'wrap|POSIX|summonaikit-harness-codex-wrap'
fi

# Symlink: PASS si el host crea enlaces reales; unknown si no
steps="$(latest_steps install-hosts)"
if [ -n "$steps" ] && [ -f "$steps" ]; then
python3 - "$steps" <<'PY' || malo "hosts-symlink no declaro PASS ni unknown"
import json, sys
found = None
for line in open(sys.argv[1], encoding="utf-8"):
    if not line.strip():
        continue
    rec = json.loads(line)
    if rec.get("type") == "assertion" and rec.get("assertion_id") == "symlink_refused":
        found = rec
if found is None:
    raise SystemExit("falta symlink_refused")
if found.get("result") not in ("PASS", "unknown"):
    raise SystemExit(f"symlink_refused result={found.get('result')}")
obs = str(found.get("observed") or "")
if found.get("result") == "PASS" and not (
    "enlace" in obs or "symlink" in obs or "intact" in obs
):
    raise SystemExit(f"PASS sin señal de symlink: {obs!r}")
if found.get("result") == "unknown" and "symlink" not in obs.lower() and "enlace" not in obs.lower():
    raise SystemExit(f"unknown sin motivo de symlink: {obs!r}")
PY
fi

# ---------------------------------------------------------------------------
# Drive routing-recipes
# ---------------------------------------------------------------------------
caso "drive routing-recipes: roles, manifiesto, consumo, no 16.7"
reset_art
out="$(ctrl drive routing-recipes 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 0 ] || malo "drive routing-recipes rc=$rc: $out"
sum="$(latest_summary routing-recipes)"
[ -n "$sum" ] && [ -f "$sum" ] || malo "routing-recipes sin summary"
if [ -n "$sum" ] && [ -f "$sum" ]; then
python3 - "$sum" <<'PY' || malo "routing-recipes summary incompleto"
import json, sys
s = json.loads(open(sys.argv[1], encoding="utf-8").read())
assert s.get("result") == "PASS" and s.get("exit_code") == 0, s
cases = s.get("cases") or s.get("cases_requested") or []
text = " ".join(cases) if not isinstance(cases, str) else cases
for need in (
    "routing-roles", "routing-unknown", "recipes-manifest-ok",
    "recipes-manifest-altered", "recipes-consume",
    "routing-no-16.7", "routing-no-live",
):
    assert need in text, (need, cases)
PY
fi

assert_obs routing-recipes claude_implementer 'claude-sonnet-5'
assert_obs routing-recipes grok_reviewer 'grok-4.6'
assert_obs routing-recipes empty_unmeasured 'vacio|empty|zcode|kimi|dsh'
assert_obs routing-recipes unknown_role_exit_2 '2'
assert_obs routing-recipes manifest_check_ok '0|al dia|ok'
assert_obs routing-recipes manifest_check_stale '1|stale|alterado|difiere'
assert_obs routing-recipes recetario_consumido 'MANIFEST|bug|receta'
assert_obs routing-recipes no_task_flag 'desconocido|no implement|16.7|sin --task'
assert_obs routing-recipes no_live_turn 'no acredita|sin turno vivo|no live'
assert_obs routing-recipes no_dsh_adapter_load 'sin carga|no adapter|no acredita'

# ---------------------------------------------------------------------------
# Encabezado falso + rc 0 no acredita copias ni ruteo
# ---------------------------------------------------------------------------
caso "encabezado falso con rc 0 no acredita hosts/ruteo"
reset_art
stub="$SANDBOX/header-only-hosts.sh"
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
assert hosts-four-copies claude_hook "hosts ok"
assert hosts-four-copies grok_hook "hosts ok"
assert hosts-four-copies dsh_hook "hosts ok"
assert hosts-four-copies codex_hook "hosts ok"
assert hosts-four-copies zcode_no_hook_copy "hosts ok"
assert hosts-four-copies kimi_no_hook_copy "hosts ok"
assert hosts-zcode-reuses zcode_reuses_claude "hosts ok"
assert hosts-zcode-reuses zcode_dest_untouched "hosts ok"
assert hosts-kimi-profiles kimi_profiles "hosts ok"
assert hosts-kimi-profiles kimi_no_model "hosts ok"
assert hosts-kimi-profiles kimi_dest_untouched "hosts ok"
assert hosts-identity ownership_marker "hosts ok"
assert hosts-identity dest_matches_source "hosts ok"
assert hosts-identity procedencia "hosts ok"
assert hosts-noop ya_al_dia "hosts ok"
assert hosts-noop dest_unchanged "hosts ok"
assert hosts-retirada retirada_preserva "hosts ok"
assert hosts-retirada neighbor_intact_after_retirada "hosts ok"
assert hosts-foreign foreign_intact "hosts ok"
assert hosts-registration registro_por_texto "hosts ok"
assert hosts-registration registro_no_solo_exit "hosts ok"
assert hosts-registration fases_estructura "hosts ok"
assert hosts-os-unavailable windows_wrap "hosts ok"
assert hosts-os-unavailable posix_wrap "hosts ok"
assert hosts-os-unavailable other_hosts_observed "hosts ok"
assert hosts-symlink symlink_refused "hosts ok"
assert hosts-no-live no_live_turn "hosts ok"
assert hosts-no-live no_dsh_adapter_load "hosts ok"
exit 0
EOF
chmod +x "$stub"
ctrl_drv "$stub" drive install-hosts >/dev/null 2>&1 || true
steps="$(latest_steps install-hosts)"
if [ -n "$steps" ] && [ -f "$steps" ]; then
python3 - "$steps" <<'PY' || malo "header-only acredito grok_hook o procedencia real"
import json, re, sys
for line in open(sys.argv[1], encoding="utf-8"):
    if not line.strip():
        continue
    rec = json.loads(line)
    asid = rec.get("assertion_id")
    obs = str(rec.get("observed") or "")
    if asid == "grok_hook" and "grok" in obs.lower() and rec.get("result") == "PASS" and "hosts ok" not in obs:
        raise SystemExit("header-only acredito grok_hook real")
    if asid == "procedencia" and "procedencia: rama=" in obs and rec.get("result") == "PASS":
        raise SystemExit("header-only acredito procedencia")
raise SystemExit(0)
PY
fi

reset_art
stub="$SANDBOX/header-only-routing.sh"
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
assert routing-roles claude_implementer "routing ok"
assert routing-roles grok_reviewer "routing ok"
assert routing-roles empty_unmeasured "routing ok"
assert routing-unknown unknown_role_exit_2 "routing ok"
assert recipes-manifest-ok manifest_check_ok "routing ok"
assert recipes-manifest-altered manifest_check_stale "routing ok"
assert recipes-consume recetario_consumido "routing ok"
assert routing-no-16.7 no_task_flag "routing ok"
assert routing-no-live no_live_turn "routing ok"
assert routing-no-live no_dsh_adapter_load "routing ok"
exit 0
EOF
chmod +x "$stub"
ctrl_drv "$stub" drive routing-recipes >/dev/null 2>&1 || true
steps="$(latest_steps routing-recipes)"
if [ -n "$steps" ] && [ -f "$steps" ]; then
python3 - "$steps" <<'PY' || malo "header-only acredito claude-sonnet-5"
import json, sys
for line in open(sys.argv[1], encoding="utf-8"):
    if not line.strip():
        continue
    rec = json.loads(line)
    obs = str(rec.get("observed") or "")
    if rec.get("assertion_id") == "claude_implementer" and "claude-sonnet-5" in obs and rec.get("result") == "PASS":
        raise SystemExit("header-only acredito claude_implementer")
raise SystemExit(0)
PY
fi

# ---------------------------------------------------------------------------
# Mutantes
# ---------------------------------------------------------------------------
if [ -f "$DRV_HOSTS" ]; then
  cp "$DRV_HOSTS" "$SANDBOX/hosts.src.sh"
  chmod +x "$SANDBOX/hosts.src.sh"
fi
if [ -f "$DRV_ROUTING" ]; then
  cp "$DRV_ROUTING" "$SANDBOX/routing.src.sh"
  chmod +x "$SANDBOX/routing.src.sh"
fi

mut_omit_hosts() {
  local label="$1" asid="$2" signal="$3" expr="$4"
  caso "mutante $label: omitir $asid se pone rojo"
  reset_art
  local mut="$SANDBOX/hosts-$label.sh"
  if [ ! -f "$SANDBOX/hosts.src.sh" ]; then
    malo "$label: sin driver fuente"; return
  fi
  if sed_must_change "$SANDBOX/hosts.src.sh" "$mut" "$expr" "$label"; then
    out="$(ctrl_drv "$mut" drive install-hosts 2>&1)" && rc=0 || rc=$?
    assert_missing_or_fail install-hosts "$asid" "$signal" "$rc"
  fi
}

mut_omit_routing() {
  local label="$1" asid="$2" signal="$3" expr="$4"
  caso "mutante $label: omitir $asid se pone rojo"
  reset_art
  local mut="$SANDBOX/routing-$label.sh"
  if [ ! -f "$SANDBOX/routing.src.sh" ]; then
    malo "$label: sin driver fuente"; return
  fi
  if sed_must_change "$SANDBOX/routing.src.sh" "$mut" "$expr" "$label"; then
    out="$(ctrl_drv "$mut" drive routing-recipes 2>&1)" && rc=0 || rc=$?
    assert_missing_or_fail routing-recipes "$asid" "$signal" "$rc"
  fi
}

mut_omit_hosts omit_dest_host grok_hook 'grok' \
  '/assert:grok_hook/,/assert:grok_hook_end/d'
mut_omit_hosts omit_fase fases_estructura 'UserPromptSubmit|PostToolUse|SessionStart|Stop' \
  '/assert:fases_estructura/,/assert:fases_estructura_end/d'
mut_omit_hosts omit_noop ya_al_dia 'YA AL DIA' \
  '/assert:ya_al_dia/,/assert:ya_al_dia_end/d'
mut_omit_hosts omit_foreign foreign_intact 'intact|igual|unchanged' \
  '/assert:foreign_intact/,/assert:foreign_intact_end/d'
mut_omit_hosts omit_symlink symlink_refused 'enlace|symlink|intact' \
  '/assert:symlink_refused/,/assert:symlink_refused_end/d'
mut_omit_hosts omit_hash dest_matches_source '[a-f0-9]{12,}' \
  '/assert:dest_matches_source/,/assert:dest_matches_source_end/d'
mut_omit_routing omit_routing claude_implementer 'claude-sonnet-5' \
  '/assert:claude_implementer/,/assert:claude_implementer_end/d'

if [ "$fail" -ne 0 ]; then
  echo "FAIL: $fail aserciones" >&2
  exit 1
fi
echo "OK: test_feature_map_hosts"
exit 0
