#!/usr/bin/env bash
# tests/test_feature_map_setup.sh — 19.8: setup-autopilot por PTY real.
#
# DoD: transcript con cinco preguntas en orden y respuestas mapeadas a JSON;
# invalido/timeout sin escritura parcial ni lock huerfano; pipe no acredita PTY;
# mutar cada pregunta/mapeo, default, guard del lock y limpieza del timeout
# pone rojo. PTY ausente => unknown en interactivos, nunca un PTY fingido.
#
# Mutaciones (copia del driver / pty_driver en sandbox; SAIKIT_FM_DRIVER,
# SAIKIT_FM_PTY):
#   omit_q1_merge omit_q2_despliega omit_q3_salud omit_q4_sve omit_q5_telegram
#   omit_questions_order omit_defaults_unknown omit_lock_guard
#   omit_timeout_cleanup accept_pipe_as_pty skip_killpg accept_unordered
# 20fix: caso de argv reales del setup-lock-held (H3) y
#   hint_liberar_sin_bash — strip del prefijo bash del hint liberar-lock (H2)
# 20fix r4: hint_flag_inexistente — hint con flag que el tool no acepta (B3):
#   la forma completa de linea es lo afirmado y lo ejecutado
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
DRV="$SKILL/scripts/drivers/setup-autopilot.sh"
STATE="$SANDBOX/verify-state"
ART="$SANDBOX/verify-artifacts"
mkdir -p "$STATE" "$ART"
. "$here/lib/feature_map_mut.sh"

ctrl() {
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


reset_art() { rm -rf "$ART"; mkdir -p "$ART"; }

copy_driver() {
  cp "$DRV" "$1"
  chmod +x "$1"
}


# ---------------------------------------------------------------------------
# Inventario: helper clasificado, descriptor activo, no legacy
# ---------------------------------------------------------------------------
caso "catalogo clasifica pty_driver y activa setup-autopilot"
python3 - "$SKILL" <<'PY' || malo "catalogo/descriptor setup-autopilot incompleto"
import json, sys
from pathlib import Path
skill = Path(sys.argv[1])
cat = json.loads((skill / "features/catalog.json").read_text())
h = (cat.get("helpers") or {}).get("scripts/lib/pty_driver.py")
assert h and h.get("kind") == "internal", h
meta = (cat.get("features") or {}).get("setup-autopilot") or {}
assert meta.get("status") == "active", meta
assert meta.get("card"), meta
d = json.loads((skill / "features/setup-autopilot.json").read_text())
ex = d.get("executor") or {}
assert ex.get("kind") == "driver", ex
assert (skill / (ex.get("path") or "scripts/drivers/setup-autopilot.sh")).is_file()
ids = [c.get("id") for c in (d.get("cases") or [])]
for need in ("setup-interactive", "setup-flags", "setup-defaults"):
    assert need in ids, (need, ids)
PY
[ -f "$PTY" ] || malo "falta scripts/lib/pty_driver.py"
[ -f "$DRV" ] || malo "falta scripts/drivers/setup-autopilot.sh"
[ -f "$SKILL/features/setup-autopilot.md" ] || malo "falta ficha setup-autopilot.md"
if [ -f "$PTY" ]; then
  PYTHONDONTWRITEBYTECODE=1 python3 -c \
    "import ast,pathlib; ast.parse(pathlib.Path(r'$PTY').read_text(encoding='utf-8'))" \
    || malo "pty_driver.py no parsea"
  bash -n "$DRV" || malo "bash -n fallo en setup-autopilot.sh"
fi

# ---------------------------------------------------------------------------
# Launch aislado
# ---------------------------------------------------------------------------
caso "launch aislado para drive setup-autopilot"
if ! out="$(ctrl launch 2>&1)"; then
  malo "launch fallo: $out"
  echo "FAIL: $fail aserciones (sin launch no hay drives)" >&2
  exit 1
fi
printf '%s' "$out" | grep -q 'launched run_id=' || malo "launch sin run_id: $out"

# ---------------------------------------------------------------------------
# Drive real
# ---------------------------------------------------------------------------
caso "drive setup-autopilot: cinco preguntas, flags, defaults, lock, pipe"
reset_art
out="$(ctrl drive setup-autopilot 2>&1)" && rc=0 || rc=$?
if [ "$rc" -eq 3 ]; then
  printf '%s' "$out" | grep -Eqi 'PTY|pty|unknown|MISSING' \
    || malo "drive unknown/3 sin motivo PTY: $out"
  # Linux CI debe tener PTY; macOS/MSYS pueden declarar unknown solo si --probe
  # lo dice. Si el probe dice que hay PTY, rc 3 es rojo.
  if PYTHONDONTWRITEBYTECODE=1 python3 "$PTY" --probe >/dev/null 2>&1; then
    malo "PTY disponible pero drive salio unknown/3: $out"
  else
    printf '    (PTY ausente: interactivos unknown; flags/defaults se juzgan abajo)\n'
  fi
else
  [ "$rc" -eq 0 ] || malo "drive setup-autopilot rc=$rc: $out"
fi

sum="$(latest_summary setup-autopilot)"
[ -n "$sum" ] && [ -f "$sum" ] || malo "setup-autopilot sin summary"
if [ -n "$sum" ] && [ -f "$sum" ]; then
python3 - "$sum" <<'PY' || malo "setup-autopilot summary incompleto"
import json, sys
s = json.loads(open(sys.argv[1], encoding="utf-8").read())
cases = s.get("cases") or s.get("cases_requested") or []
text = " ".join(cases) if not isinstance(cases, str) else cases
for need in ("setup-interactive", "setup-flags", "setup-defaults"):
    assert need in text, (need, cases)
PY
fi

# Flags/defaults no dependen de PTY
assert_obs setup-autopilot flags_merge 'false'
assert_obs setup-autopilot flags_salud 'flags.example.test'
assert_obs setup-autopilot defaults_despliega 'unknown'
assert_obs setup-autopilot defaults_merge 'false'
assert_obs setup-autopilot pipe_not_pty 'pipe|not.pty|no.pty|defaults'
assert_obs setup-autopilot lock_blocks '3|LOCK|lock'
assert_obs setup-autopilot lock_no_write 'ausente|intact|no.write|sin.escritura'
assert_obs setup-autopilot lock_held_exit_3 'exit 3|lock'
assert_obs setup-autopilot lock_held_hint_ejecutable 'bash tools/saikit-setup-autopilot.sh --liberar-lock|hint'
# 20fix H3: el hint se EJECUTA inocuamente contra una copia del fixture.
assert_obs setup-autopilot lock_hint_ejecucion_inocua 'copia|original|inocu'
assert_obs setup-autopilot with_ci_no_offer 'ya hay workflows|no se ofrece'
assert_obs setup-autopilot without_ci_aviso 'sin CI|no mergea'
assert_obs setup-autopilot ci_not_q6 'no 6/5|not 6/5|no.es.6'

if [ "$rc" -eq 0 ]; then
  assert_obs setup-autopilot questions_order '1/5'
  assert_obs setup-autopilot questions_order '2/5'
  assert_obs setup-autopilot questions_order '3/5'
  assert_obs setup-autopilot questions_order '4/5'
  assert_obs setup-autopilot questions_order '5/5'
  assert_obs setup-autopilot map_merge 'true'
  assert_obs setup-autopilot map_despliega 'publica'
  assert_obs setup-autopilot map_salud 'pty.example.test'
  assert_obs setup-autopilot map_sve 'false'
  assert_obs setup-autopilot map_telegram 'true'
  assert_obs setup-autopilot invalid_no_write 'ausente|intact|no.write|sin.escritura'
  assert_obs setup-autopilot invalid_no_lock 'sin lock|no lock|ausente|liberado'
  assert_obs setup-autopilot timeout_no_write 'ausente|intact|no.write|sin.escritura'
  assert_obs setup-autopilot timeout_no_lock 'sin lock|no lock|ausente|liberado'
  assert_obs setup-autopilot timeout_reaped 'reap|killed|timeout'
fi

# ---------------------------------------------------------------------------
# PTY ausente: interactivos unknown; flags/defaults siguen; nunca fingir PTY
# ---------------------------------------------------------------------------
caso "PTY ausente: interactivos unknown, flags/defaults observables, sin fingir"
reset_art
out="$(SAIKIT_VERIFY_PTY=missing ctrl drive setup-autopilot 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 3 ] || malo "drive sin PTY debio unknown/3 (got $rc): $out"
assert_result setup-autopilot questions_order unknown
assert_result setup-autopilot map_merge unknown
assert_obs setup-autopilot flags_salud 'flags.example.test'
assert_obs setup-autopilot defaults_despliega 'unknown'
# Ninguna asercion interactiva puede pretender que hubo PTY
steps="$(latest_steps setup-autopilot)"
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
        "questions_order", "map_merge", "map_despliega", "map_salud",
        "map_sve", "map_telegram", "invalid_no_write", "invalid_no_lock",
        "timeout_no_write", "timeout_no_lock", "timeout_reaped",
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
# Encabezado falso + rc 0 no acredita las cinco preguntas
# ---------------------------------------------------------------------------
caso "encabezado falso con rc 0 no acredita preguntas/mapeo"
reset_art
stub="$SANDBOX/header-only-setup.sh"
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
assert setup-interactive questions_order "setup ok"
assert setup-interactive map_merge "setup ok"
assert setup-interactive map_despliega "setup ok"
assert setup-interactive map_salud "setup ok"
assert setup-interactive map_sve "setup ok"
assert setup-interactive map_telegram "setup ok"
assert setup-invalid invalid_no_write "setup ok"
assert setup-invalid invalid_no_lock "setup ok"
assert setup-timeout timeout_no_write "setup ok"
assert setup-timeout timeout_no_lock "setup ok"
assert setup-timeout timeout_reaped "setup ok"
assert setup-flags flags_merge "setup ok"
assert setup-flags flags_salud "setup ok"
assert setup-defaults defaults_despliega "setup ok"
assert setup-defaults defaults_merge "setup ok"
assert setup-pipe-not-pty pipe_not_pty "setup ok"
assert setup-lock lock_blocks "setup ok"
assert setup-lock lock_no_write "setup ok"
assert setup-with-ci with_ci_no_offer "setup ok"
assert setup-without-ci without_ci_aviso "setup ok"
assert setup-without-ci ci_not_q6 "setup ok"
exit 0
EOF
chmod +x "$stub"
ctrl_drv "$stub" drive setup-autopilot >/dev/null 2>&1 || true
steps="$(latest_steps setup-autopilot)"
if [ -n "$steps" ] && [ -f "$steps" ]; then
python3 - "$steps" <<'PY' || malo "header-only acredito 1/5 o mapeo real"
import json, re, sys
for line in open(sys.argv[1], encoding="utf-8"):
    if not line.strip():
        continue
    rec = json.loads(line)
    asid = rec.get("assertion_id")
    obs = str(rec.get("observed") or "")
    if asid == "questions_order" and re.search(r"1/5", obs) and rec.get("result") == "PASS":
        raise SystemExit("header-only acredito questions_order")
    if asid == "map_salud" and "pty.example.test" in obs and rec.get("result") == "PASS":
        raise SystemExit("header-only acredito map_salud")
raise SystemExit(0)
PY
fi

# ---------------------------------------------------------------------------
# Mutantes
# ---------------------------------------------------------------------------
copy_driver "$SANDBOX/setup.src.sh"
fm_mut_check_flat_infra setup-autopilot "$DRV" drive setup-autopilot
fm_mut_require_baseline setup-autopilot "$DRV" drive setup-autopilot

mut_omit() {
  local label="$1" asid="$2" signal="$3" expr="$4"
  caso "mutante $label: omitir $asid se pone rojo"
  reset_art
  local mut="$SANDBOX/setup-$label.sh"
  if sed_must_change "$SANDBOX/setup.src.sh" "$mut" "$expr" "$label"; then
    bash -n "$mut" || { malo "$label: mutante no parsea"; return; }
    out="$(ctrl_drv "$mut" drive setup-autopilot 2>&1)" && rc=0 || rc=$?
    assert_missing_or_fail setup-autopilot "$asid" "$signal" "$rc"
  fi
}

mut_omit omit_q1_merge map_merge 'true' \
  '/assert:map_merge/,/assert:map_merge_end/d'
mut_omit omit_q2_despliega map_despliega 'publica' \
  '/assert:map_despliega/,/assert:map_despliega_end/d'
mut_omit omit_q3_salud map_salud 'pty.example.test' \
  '/assert:map_salud/,/assert:map_salud_end/d'
mut_omit omit_q4_sve map_sve 'false' \
  '/assert:map_sve/,/assert:map_sve_end/d'
mut_omit omit_q5_telegram map_telegram 'true' \
  '/assert:map_telegram/,/assert:map_telegram_end/d'
mut_omit omit_questions_order questions_order '1/5' \
  '/assert:questions_order/,/assert:questions_order_end/d'
mut_omit omit_defaults_unknown defaults_despliega 'unknown' \
  '/assert:defaults_despliega/,/assert:defaults_despliega_end/d'
mut_omit omit_lock_guard lock_blocks '3|LOCK|lock' \
  '/assert:lock_blocks/,/assert:lock_blocks_end/d'
mut_omit omit_timeout_cleanup timeout_no_lock 'sin lock|no lock|ausente|liberado' \
  '/assert:timeout_no_lock/,/assert:timeout_no_lock_end/d'

caso "mutante accept_pipe_as_pty: tratar pipe como PTY se pone rojo"
reset_art
mut="$SANDBOX/setup-accept-pipe.sh"
if sed_must_change "$SANDBOX/setup.src.sh" "$mut" \
  's/SAIKIT_FM_PIPE_IS_PTY=0/SAIKIT_FM_PIPE_IS_PTY=1/' \
  "accept_pipe_as_pty"
then
  bash -n "$mut" || malo "accept_pipe_as_pty: mutante no parsea"
  out="$(ctrl_drv "$mut" drive setup-autopilot 2>&1)" && rc=0 || rc=$?
  assert_missing_or_fail setup-autopilot pipe_not_pty 'pipe|not.pty|no.pty|defaults' "$rc"
fi

caso "mutante accept_unordered: 5/5 antes de 1/5 se pone rojo"
reset_art
mut="$SANDBOX/setup-accept-unordered.sh"
if sed_must_change "$SANDBOX/setup.src.sh" "$mut" \
  's/print("ordered" if all(idx\[i\]>=0 and (i==0 or idx\[i\]>idx\[i\-1\]) for i in range(5)) else "unordered")/print("unordered")/' \
  "accept_unordered"
then
  out="$(ctrl_drv "$mut" drive setup-autopilot 2>&1)" && rc=0 || rc=$?
  assert_missing_or_fail setup-autopilot questions_order '1/5' "$rc"
fi

# ---------------------------------------------------------------------------
# 20fix H3: setup-lock-held registra argv REALES. El flag --lock-held no
# existe en tools/saikit-setup-autopilot.sh — un fm_action con ese argv es
# evidencia inventada. Se exige: act-holder (preparacion, --pr 11 +
# SOSTENER), act-lock-held con el argv exacto de la corrida real (--pr 12,
# sin --lock-held) y act-liberar-inocuo (--liberar-lock).
# ---------------------------------------------------------------------------
caso "setup-lock-held registra argv reales (sin --lock-held inventado)"
reset_art
out="$(ctrl drive setup-autopilot 2>&1)" && drc=0 || drc=$?
steps="$(latest_steps setup-autopilot)"
[ -n "$steps" ] && [ -f "$steps" ] || malo "setup-autopilot sin steps para acciones"
if [ -n "$steps" ] && [ -f "$steps" ]; then
python3 - "$steps" <<'PY' || malo "act-lock-held/act-holder/act-liberar-inocuo no fieles"
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8") if l.strip()]
def cmd_of(rec):
    c = rec.get("command")
    if isinstance(c, list):
        return " ".join(str(x) for x in c)
    return str(c or "")
acts = [r for r in rows if r.get("type") == "action"]
for a in acts:
    cmd = cmd_of(a)
    assert "--lock-held" not in cmd, f"argv inventado --lock-held en {a.get('step_id')}: {cmd}"
holder = [a for a in acts if a.get("step_id") == "act-holder"]
assert holder, "falta action act-holder (preparacion del sostenedor)"
hcmd = cmd_of(holder[-1])
assert "SAIKIT_SETUP_SOSTENER_SEG=8" in hcmd and "--pr 11" in hcmd, hcmd
held = [a for a in acts if a.get("step_id") == "act-lock-held"]
assert held, "falta action act-lock-held"
cmd = cmd_of(held[-1])
assert cmd.startswith("bash "), cmd
for part in ("--merge no", "--despliega no", "--sin-verify-app no",
             "--telegram no", "--ci-minimo no", "--pr 12"):
    assert part in cmd, (part, cmd)
inocuo = [a for a in acts if a.get("step_id") == "act-liberar-inocuo"]
assert inocuo, "falta action act-liberar-inocuo"
icmd = cmd_of(inocuo[-1])
assert icmd.endswith("--liberar-lock"), icmd
PY
fi

# 20fix H2: strip del prefijo bash del hint en la salida capturada, antes de
# la asercion — la forma ejecutable (`bash tools/...`) es lo afirmado.
caso "mutante hint_liberar_sin_bash: hint sin prefijo bash se pone rojo"
reset_art
control_sano_setup() {
  rm -f "$SANDBOX/baseline-ok-setup-autopilot"
  fm_mut_require_baseline setup-autopilot "$DRV" drive setup-autopilot
}
control_sano_setup
mut="$SANDBOX/setup-hint-sin-bash.sh"
if sed_must_change "$SANDBOX/setup.src.sh" "$mut" \
  's@# assert:lock_held_hint_ejecutable@out="$(printf %s "$out" | sed '"'"'s|bash tools/saikit-setup-autopilot.sh|tools/saikit-setup-autopilot.sh|g'"'"')"; &@' \
  "hint_liberar_sin_bash"
then
  bash -n "$mut" || { malo "hint_liberar_sin_bash: mutante no parsea"; }
  if bash -n "$mut" 2>/dev/null; then
    out="$(ctrl_drv "$mut" drive setup-autopilot 2>&1)" && rc=0 || rc=$?
    assert_missing_or_fail setup-autopilot lock_held_hint_ejecutable \
      'bash tools/saikit-setup-autopilot.sh --liberar-lock|hint' "$rc"
  fi
fi

# 20fix B3: hint con un FLAG INEXISTENTE — contiene el comando como
# subcadena pero no ES el comando (de ejecutarlo de verdad, rc=2). La
# asercion debe exigir la forma completa de linea y la ejecucion inocua debe
# correr el argv EXTRAIDO (medido contra el driver pre-B3: drive rc=0 con
# ambas aserciones en PASS).
caso "mutante hint_flag_inexistente: hint con flag raro se pone rojo"
reset_art
control_sano_setup
mut="$SANDBOX/setup-hint-flag.sh"
if sed_must_change "$SANDBOX/setup.src.sh" "$mut" \
  's@# assert:lock_held_hint_ejecutable@out="$(printf %s "$out" | sed '"'"'s|bash tools/saikit-setup-autopilot.sh --liberar-lock|\& --flag-inexistente|'"'"')"; &@' \
  "hint_flag_inexistente"
then
  bash -n "$mut" || { malo "hint_flag_inexistente: mutante no parsea"; }
  if bash -n "$mut" 2>/dev/null; then
    out="$(ctrl_drv "$mut" drive setup-autopilot 2>&1)" && rc=0 || rc=$?
    assert_missing_or_fail setup-autopilot lock_held_hint_ejecutable \
      'bash tools/saikit-setup-autopilot.sh --liberar-lock|hint' "$rc"
  fi
fi

caso "mutante skip_killpg: timeout sin kill/reap se pone rojo"
reset_art
if [ -f "$PTY" ]; then
  mutp="$SANDBOX/pty-skip-kill.py"
  if sed_must_change "$PTY" "$mutp" \
    's/do_killpg = True/do_killpg = False/' \
    "skip_killpg"
  then
    PYTHONDONTWRITEBYTECODE=1 python3 -c \
      "import ast,pathlib; ast.parse(pathlib.Path(r'$mutp').read_text(encoding='utf-8'))" \
      || malo "skip_killpg: mutante no parsea"
    out="$(ctrl_pty "$mutp" drive setup-autopilot 2>&1)" && rc=0 || rc=$?
    assert_missing_or_fail setup-autopilot timeout_reaped 'reap|killed|timeout' "$rc"
    hold="$SANDBOX/f13-hold.py"
    mark="$SANDBOX/f13-gpid"
    cat > "$hold" <<'PY'
import os, signal, sys, time
mark = sys.argv[1]
g = os.fork()
if g == 0:
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    open(mark, "w").write(str(os.getpid()))
    time.sleep(30)
    os._exit(0)
time.sleep(30)
PY
    run_f13() {
      local driver="$1" report="$2"
      rm -f "$mark"
      PYTHONDONTWRITEBYTECODE=1 python3 "$driver" \
        --timeout 1.2 --cwd "$SANDBOX" --out "$report" \
        -- python3 "$hold" "$mark" >/dev/null 2>&1 || true
    }
    run_f13 "$PTY" "$SANDBOX/f13-ok.json"
    gpid="$(cat "$mark" 2>/dev/null || true)"
    if [ -n "$gpid" ] && kill -0 "$gpid" 2>/dev/null; then
      malo "F13: pty sano dejo el nieto $gpid vivo"
      kill -9 "$gpid" 2>/dev/null || true
    fi
    run_f13 "$mutp" "$SANDBOX/f13-mut.json"
    gpid="$(cat "$mark" 2>/dev/null || true)"
    if [ -z "$gpid" ]; then
      malo "F13: skip_killpg no dejo marca de nieto"
    elif ! kill -0 "$gpid" 2>/dev/null; then
      malo "F13: skip_killpg no discrimina (nieto $gpid ya muerto)"
    else
      kill -9 "$gpid" 2>/dev/null || true
    fi

    caso "F13b: EOF del PTY no deja vivo al hijo"
    eof_child="$SANDBOX/f13-eof.py"
    eof_mark="$SANDBOX/f13-eof-pid"
    cat > "$eof_child" <<'PY'
import os, signal, sys, time
child = os.fork()
if child == 0:
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    open(sys.argv[1], "w", encoding="utf-8").write(str(os.getpid()))
for fd in (0, 1, 2):
    try:
        os.close(fd)
    except OSError:
        pass
time.sleep(30)
PY
    PYTHONDONTWRITEBYTECODE=1 python3 "$PTY" \
      --timeout 5 --cwd "$SANDBOX" --out "$SANDBOX/f13-eof.json" \
      -- python3 "$eof_child" "$eof_mark" >/dev/null 2>&1 || true
    eof_pid="$(cat "$eof_mark" 2>/dev/null || true)"
    if [ -z "$eof_pid" ]; then
      malo "F13b: hijo no dejo pid"
    elif kill -0 "$eof_pid" 2>/dev/null; then
      malo "F13b: EOF temprano dejo el hijo $eof_pid vivo"
      kill -9 "$eof_pid" 2>/dev/null || true
    fi
  fi
fi

if [ "$fail" -ne 0 ]; then
  echo "FAIL: $fail aserciones" >&2
  exit 1
fi
echo "OK: test_feature_map_setup"
exit 0
