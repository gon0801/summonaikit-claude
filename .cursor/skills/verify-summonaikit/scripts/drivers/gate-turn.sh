#!/usr/bin/env bash
# gate-turn driver — golden-harness assertions reused from verify/test_drive.py.
set -euo pipefail
driver_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_root="$(cd "$driver_dir/../.." && pwd)"
# shellcheck source=../lib/runtime.sh
. "$skill_root/scripts/lib/runtime.sh"
# shellcheck source=../lib/driver.sh
. "$skill_root/scripts/lib/driver.sh"

: "${VERIFY_HOME:?}" "${VERIFY_DEST:?}" "${VERIFY_REPO:?}" "${VERIFY_TMPDIR:?}"
: "${SAIKIT_FM_ATTEMPT_DIR:?}"

fm_unknown() { fm_assert "$1" "$2" unknown "$3" "$4"; }

GOLDEN="$VERIFY_REPO/tools/golden-harness.sh"
FIX="$VERIFY_REPO/tests/fixtures/escenarios"

run_scenario() {
  local scenario="$1"
  local src="$FIX/$scenario"
  [ -d "$src" ] || { printf 'unknown scenario: %s\n' "$scenario"; return 2; }
  local sc_dir
  sc_dir="$(mktemp -d "$VERIFY_TMPDIR/sc-XXXXXX")"
  cp -R "$src" "$sc_dir/"
  run_scenario_parent "$sc_dir"
  local rc=$?
  rm -rf "$sc_dir"
  return "$rc"
}

# r1 (cross-review 20.x): variant that runs golden over an arbitrary parent
# directory of scenario dirs (the driver-owned synthetic grok scenarios are
# built under VERIFY_TMPDIR, not under tests/fixtures).
run_scenario_parent() {
  local sc_dir="$1"
  set +e
  runtime_exec "$VERIFY_HOME" bash "$GOLDEN" \
    --print --hook "$VERIFY_DEST" --scenarios "$sc_dir"
  local rc=$?
  set -e
  return "$rc"
}

parse_block() {
  # $1=scenario $2=path to golden stdout. Prints KEY=value lines.
  python3 - "$1" "$2" <<'PY'
import json, re, shlex, sys
from pathlib import Path
scenario = sys.argv[1]
text = Path(sys.argv[2]).read_text(encoding="utf-8", errors="replace")

def kv(k, v):
    print(f"{k}={shlex.quote(str(v))}")

kv("HAS_HEADER", "1" if f"=== escenario {scenario}" in text else "0")
m = re.search(r"^# hook_sha256: ([0-9a-f]+)$", text, re.M)
kv("HOOK_SHA", m.group(1) if m else "")
blocks = re.split(r"^=== escenario ", text, flags=re.M)[1:]
block = ""
for b in blocks:
    name = b.splitlines()[0].strip()
    if name == scenario:
        block = b
        break
kv("BLOCK_NAME", block.splitlines()[0].strip() if block else "")
pasos = re.split(r"^--- paso ", block, flags=re.M)[1:] if block else []
ids = []
for p in pasos:
    ids.append(p.split()[0] if p.split() else "")
kv("STEPS", " ".join(ids))
kv("SIN_ESTADO", "1" if "(sin estado)" in block else "0")
kv("HAS_CONTRACT", "1" if "SUMMONAIKIT HARNESS REQUIRED" in block else "0")
kv("HAS_HSTATE", "1" if "harness-state.env" in block else "0")
kv("HAS_TASK_HASH", "1" if re.search(r"task_hash=[0-9]+", block) else "0")
stop_exit = ""
for p in pasos:
    header = p.splitlines()[0] if p.splitlines() else ""
    if "phase=stop" in header.split():
        m_stop = re.search(r"^exit (\d+)$", p, re.M)
        stop_exit = m_stop.group(1) if m_stop else ""
        break
kv("STOP_EXIT", stop_exit)
ok_json = "0"
if "SUMMONAIKIT HARNESS REQUIRED" in block:
    try:
        blob = "\n".join(ln[2:] for ln in block.splitlines() if ln.startswith("| "))
        start = blob.find("{")
        contrato = json.loads(blob[start:]) if start >= 0 else {}
        ctx = (contrato or {}).get("hookSpecificOutput") or {}
        extra = ctx.get("additionalContext") or ""
        if ctx.get("hookEventName") == "UserPromptSubmit" and extra.startswith(
            "SUMMONAIKIT HARNESS REQUIRED"
        ):
            ok_json = "1"
    except (json.JSONDecodeError, TypeError, AttributeError):
        ok_json = "0"
kv("CONTRACT_JSON", ok_json)
PY
}

src_sha="$(fm_sha "$VERIFY_REPO/hooks/summonaikit-harness.sh")"

if fm_only gate-unarmed; then
  outf="$VERIFY_TMPDIR/gate-01.txt"
  set +e
  run_scenario 01-sin-armar >"$outf" 2>&1
  rc=$?
  set -e
  fm_action gate-unarmed act-unarmed "$rc" "golden 01-sin-armar" \
    bash "$GOLDEN" --print --hook "$VERIFY_DEST"
  eval "$(parse_block 01-sin-armar "$outf")"
  if [ "${HOOK_SHA:-}" = "$src_sha" ]; then
    fm_pass gate-unarmed hook_sha "$src_sha" "$HOOK_SHA"
  else
    fm_fail gate-unarmed hook_sha "$src_sha" "${HOOK_SHA:-missing}"
  fi
  if [ "${STEPS:-}" = "01 02 03" ]; then
    fm_pass gate-unarmed scenario_steps "01 02 03" "$STEPS"
  else
    fm_fail gate-unarmed scenario_steps "01 02 03" "${STEPS:-}"
  fi
  # assert:sin_estado
  if [ "${SIN_ESTADO:-0}" = 1 ]; then
    fm_pass gate-unarmed sin_estado "(sin estado)" "(sin estado)"
  else
    fm_fail gate-unarmed sin_estado "(sin estado)" "estado presente o ausente"
  fi
  # assert:sin_estado_end
  if [ "${HAS_CONTRACT:-1}" = 0 ]; then
    fm_pass gate-unarmed sin_contrato "sin contrato" "sin contrato"
  else
    fm_fail gate-unarmed sin_contrato "sin contrato" "contrato presente en 01"
  fi
fi

if fm_only gate-armed; then
  outf="$VERIFY_TMPDIR/gate-02.txt"
  set +e
  run_scenario 02-armado-contrato >"$outf" 2>&1
  rc=$?
  set -e
  fm_action gate-armed act-armed "$rc" "golden 02-armado-contrato" \
    bash "$GOLDEN" --print --hook "$VERIFY_DEST"
  eval "$(parse_block 02-armado-contrato "$outf")"
  if [ "${HOOK_SHA:-}" = "$src_sha" ]; then
    fm_pass gate-armed hook_sha "$src_sha" "$HOOK_SHA"
  else
    fm_fail gate-armed hook_sha "$src_sha" "${HOOK_SHA:-missing}"
  fi
  if [ "${STEPS:-}" = "01" ]; then
    fm_pass gate-armed scenario_steps "01" "$STEPS"
  else
    fm_fail gate-armed scenario_steps "01" "${STEPS:-}"
  fi
  # assert:contract_json
  if [ "${CONTRACT_JSON:-0}" = 1 ] || [ "${HAS_CONTRACT:-0}" = 1 ]; then
    fm_pass gate-armed contract_json "SUMMONAIKIT HARNESS REQUIRED" \
      "SUMMONAIKIT HARNESS REQUIRED"
  else
    fm_fail gate-armed contract_json "SUMMONAIKIT HARNESS REQUIRED" "contrato ausente"
  fi
  # assert:contract_json_end
  # assert:harness_state
  if [ "${HAS_HSTATE:-0}" = 1 ]; then
    extra=""
    [ "${HAS_TASK_HASH:-0}" = 1 ] && extra=" task_hash"
    fm_pass gate-armed harness_state "harness-state.env" "harness-state.env$extra"
  else
    fm_fail gate-armed harness_state "harness-state.env" "sin harness-state.env"
  fi
  # assert:harness_state_end
fi

if fm_only gate-stop-no-receipt; then
  outf="$VERIFY_TMPDIR/gate-07.txt"
  set +e
  run_scenario 07-evidencia-incompleta >"$outf" 2>&1
  rc=$?
  set -e
  fm_action gate-stop-no-receipt act-stop "$rc" "golden 07-evidencia-incompleta" \
    bash "$GOLDEN" --print --hook "$VERIFY_DEST"
  eval "$(parse_block 07-evidencia-incompleta "$outf")"
  out="$(cat "$outf")"
  # assert:stop_rejected
  if [ "${STOP_EXIT:-}" = "2" ]; then
    fm_pass gate-stop-no-receipt stop_rejected "stop exit 2" \
      "stop exit ${STOP_EXIT}"
  else
    fm_fail gate-stop-no-receipt stop_rejected "stop exit 2" \
      "stop exit ${STOP_EXIT:-missing} ${out}"
  fi
  # assert:stop_rejected_end
  if [ "${BLOCK_NAME:-}" = "07-evidencia-incompleta" ]; then
    fm_pass gate-stop-no-receipt not_scenario_01_02 "07-evidencia-incompleta" \
      "07-evidencia-incompleta"
  else
    fm_fail gate-stop-no-receipt not_scenario_01_02 "07-evidencia-incompleta" \
      "${BLOCK_NAME:-}"
  fi
fi

# ---------------------------------------------------------------------------
# r1 (cross-review 20.x): la escotilla grok DELEGATED exige un documento JSON
# valido COMPLETO. Cuatro formas rotas siguen BLOQUEANDO (exit 2) y un array
# valido no vacio sigue PERMITIENDO (exit 0). Escenarios sinteticos propios
# (espejo de caso_g4_grok_delegado_bg_doc_roto_bloquea): armar, despachar
# implementer, Stop DELEGATED con backgroundTasks roto de cada forma.
# ---------------------------------------------------------------------------
if fm_only gate-grok-bg-doc-roto; then
  sc_root="$VERIFY_TMPDIR/sc-grok-docroto"
  rm -rf "$sc_root"
  mkdir -p "$sc_root"

  _grok_armar() {  # $1=dir $2=serial
    mkdir -p "$1"
    cat > "$1/01.prompt.grok.json" <<EOF
{"hookEventName":"user_prompt_submit","sessionId":"gk-doc-$2","cwd":"C:\\\\dev\\\\demo","workspaceRoot":"C:/dev/demo/","transcriptPath":"__TRANSCRIPT__","promptId":"p-gk-doc-$2","permissionMode":"bypassPermissions","prompt":"<user_query>\\n-saikit delega con payload roto\\n</user_query>"}
EOF
    cat > "$1/02.tool.grok.json" <<EOF
{"hookEventName":"post_tool_use","sessionId":"gk-doc-$2","cwd":"C:\\\\dev\\\\demo","workspaceRoot":"C:/dev/demo/","transcriptPath":"__TRANSCRIPT__","permissionMode":"bypassPermissions","toolName":"spawn_subagent","toolInput":{"prompt":"hace lo tuyo","description":"paso del harness","subagent_type":"implementer","background":false},"toolResult":{"ok":true},"toolUseId":"tu-gk-03","isBackgrounded":false}
EOF
  }

  _grok_stop_bg() {  # $1=dir $2=serial $3=contenido crudo del array (o vacio)
    cat > "$1/03.stop.grok.json" <<EOF
{"hookEventName":"stop","sessionId":"gk-doc-$2","cwd":"C:\\\\dev\\\\demo","workspaceRoot":"C:/dev/demo/","transcriptPath":"__TRANSCRIPT__","promptId":"p-gk-doc-$2","permissionMode":"bypassPermissions","reason":"end_turn","stopHookActive":false,"lastAssistantMessage":"SUMMONAIKIT HARNESS DELEGATED - awaiting implementer","backgroundTasks":[$3],"sessionCrons":[]}
EOF
  }

  _grok_stop_trailing() {  # $1=dir $2=serial: documento cerrado + basura detras
    cat > "$1/03.stop.grok.json" <<EOF
{"hookEventName":"stop","sessionId":"gk-doc-$2","cwd":"C:\\\\dev\\\\demo","workspaceRoot":"C:/dev/demo/","transcriptPath":"__TRANSCRIPT__","promptId":"p-gk-doc-$2","permissionMode":"bypassPermissions","reason":"end_turn","stopHookActive":false,"lastAssistantMessage":"SUMMONAIKIT HARNESS DELEGATED - awaiting implementer","backgroundTasks":[1],"sessionCrons":[]} "trailing"
EOF
  }

  # Las cuatro formas rotas del producto: literal incompleto, coma colgante,
  # clave ajena con valor invalido y basura tras el cierre del root.
  _grok_armar "$sc_root/59-grok-bg-docroto-nul" nul
  _grok_stop_bg "$sc_root/59-grok-bg-docroto-nul" nul 'nul'
  _grok_armar "$sc_root/60-grok-bg-docroto-coma" coma
  _grok_stop_bg "$sc_root/60-grok-bg-docroto-coma" coma '1,'
  _grok_armar "$sc_root/61-grok-bg-docroto-clave" clave
  cat > "$sc_root/61-grok-bg-docroto-clave/03.stop.grok.json" <<'EOF'
{"hookEventName":"stop","sessionId":"gk-doc-clave","cwd":"C:\\dev\\demo","workspaceRoot":"C:/dev/demo/","transcriptPath":"__TRANSCRIPT__","promptId":"p-gk-doc-clave","permissionMode":"bypassPermissions","reason":"end_turn","stopHookActive":false,"lastAssistantMessage":"SUMMONAIKIT HARNESS DELEGATED - awaiting implementer","backgroundTasks":[1],"bad":oops,"sessionCrons":[]}
EOF
  _grok_armar "$sc_root/62-grok-bg-docroto-trailing" trailing
  _grok_stop_trailing "$sc_root/62-grok-bg-docroto-trailing" trailing
  # Control: array valido y poblado -> la escotilla sigue permitiendo.
  _grok_armar "$sc_root/63-grok-bg-valido-permite" ok
  _grok_stop_bg "$sc_root/63-grok-bg-valido-permite" ok '1'

  outf="$VERIFY_TMPDIR/gate-grok-docroto.txt"
  set +e
  run_scenario_parent "$sc_root" >"$outf" 2>&1
  rc=$?
  set -e
  fm_action gate-grok-bg-doc-roto act-docroto "$rc" "golden sintetico grok x5" \
    bash "$GOLDEN" --print --hook "$VERIFY_DEST"
  # Grok Stop: el hook emite la decision en stdout y el host la interpreta
  # (7.2: exit 0 + {"decision":"block"}); el veredicto es la DECISION, no rc.
  grok_stop_decision() {  # $1=scenario $2=file → block|allow
    python3 - "$1" "$2" <<'PYDEC'
import re, sys
from pathlib import Path
scenario, path = sys.argv[1], sys.argv[2]
text = Path(path).read_text(encoding="utf-8", errors="replace")
pasos = {}  # "scenario/paso NN" -> texto del paso
for b in re.split(r"^=== escenario ", text, flags=re.M)[1:]:
    name = b.splitlines()[0].strip()
    for p in re.split(r"^--- paso ", b, flags=re.M)[1:]:
        pasos[f"{name}/paso {p.split()[0]}"] = p

def stop_paso(name):
    for key, p in pasos.items():
        if key.startswith(name + "/paso ") and "phase=stop" in p.splitlines()[0].split():
            return p
    return ""

# golden deduplica streams identicos como «identico a <sc>/paso NN»: hay que
# SEGUIR la referencia hasta el paso que si trae el contenido.
def has_block(p, seen=None):
    if not p:
        return False
    seen = set() if seen is None else seen
    if '"decision":"block"' in p:
        return True
    m = re.search(r"identico a ([^/\s]+/paso \d+)", p)
    if m and m.group(1) not in seen:
        seen.add(m.group(1))
        return has_block(pasos.get(m.group(1), ""), seen)
    return False

print("block" if has_block(stop_paso(scenario)) else "allow")
PYDEC
  }
  rotos=""
  for sc in 59-grok-bg-docroto-nul 60-grok-bg-docroto-coma \
    61-grok-bg-docroto-clave 62-grok-bg-docroto-trailing; do
    dec="$(grok_stop_decision "$sc" "$outf")"
    [ "$dec" = "block" ] || rotos="$rotos $sc:$dec"
  done
  permitia="$(grok_stop_decision 63-grok-bg-valido-permite "$outf")"
  eval "$(parse_block 63-grok-bg-valido-permite "$outf")"
  # assert:grok_doc_roto_bloquea
  if [ -z "$rotos" ]; then
    fm_pass gate-grok-bg-doc-roto grok_doc_roto_bloquea 'decision "block"' \
      "las 4 formas rotas bloquean (nul, coma, clave ajena, trailing)"
  else
    fm_fail gate-grok-bg-doc-roto grok_doc_roto_bloquea 'decision "block"' \
      "$rotos $(cat "$outf")"
  fi
  # assert:grok_bg_valido_permite
  if [ "$permitia" = "allow" ] && [ "${STOP_EXIT:-}" = "0" ]; then
    fm_pass gate-grok-bg-doc-roto grok_bg_valido_permite \
      "sin decision block + exit 0" \
      "backgroundTasks valido y poblado permite la espera"
  else
    fm_fail gate-grok-bg-doc-roto grok_bg_valido_permite \
      "sin decision block + exit 0" \
      "decision=$permitia exit=${STOP_EXIT:-missing} $(cat "$outf")"
  fi
  rm -rf "$sc_root"
fi

# ---------------------------------------------------------------------------
# r1 (cross-review 20.x): teardown de la zona adversarial seguro contra
# enlaces de ANCESTROS y limpieza en la salida unknown honesto. Banco propio
# (copia del hook bajo VERIFY_TMPDIR; espejo minimo del hook_lab del
# producto): el estado vive junto a la copia y la zona bajo el proyecto.
# ---------------------------------------------------------------------------
ADVLAB=""
ADV_SES="d0a10000-aaaa-4bbb-8ccc-ddddeeeeffff"

adv_lab_init() {
  ADVLAB="$VERIFY_TMPDIR/gate-advlab"
  rm -rf "$ADVLAB"
  mkdir -p "$ADVLAB/hooks/state" "$ADVLAB/proyecto" "$ADVLAB/home"
  cp "$VERIFY_REPO/hooks/summonaikit-harness.sh" \
    "$ADVLAB/hooks/summonaikit-harness.sh"
}

adv_run() {  # $1=fase $2=target $3=payload → ADV_RC/ADV_OUT/ADV_ERR
  local fase="$1" target="$2" payload="$3"
  local entrada="$ADVLAB/entrada.json"
  printf '%s' "$payload" \
    | sed "s|__TRANSCRIPT__|$ADVLAB/transcript-inexistente.jsonl|g; s|__SESSION_ID__|$ADV_SES|g" \
    > "$entrada"
  local cmd
  cmd=(env -u SUMMONAIKIT_INTERNAL_GENERATION -u SUMMONAIKIT_HOOK_PHASE \
    -u SUMMONAIKIT_HOOK_TARGET -u CLAUDECODE -u ZCODE_SESSION_ID \
    -u ZCODE_PROJECT_DIR -u GROK_HOOK_EVENT -u GROK_SESSION_ID \
    -u GROK_WORKSPACE_ROOT HOME="$ADVLAB/home" USERPROFILE="$ADVLAB/home"
    SUMMONAIKIT_HOOK_PHASE="$fase" SUMMONAIKIT_HOOK_TARGET="$target")
  set +e
  ( cd "$ADVLAB/proyecto" && "${cmd[@]}" \
    bash "$ADVLAB/hooks/summonaikit-harness.sh" ) \
    < "$entrada" >"$ADVLAB/.out" 2>"$ADVLAB/.err"
  ADV_RC=$?
  set -e
  ADV_OUT="$(cat "$ADVLAB/.out")"
  ADV_ERR="$(cat "$ADVLAB/.err")"
}

adv_payload_prompt() {
  printf '{"session_id":"__SESSION_ID__","transcript_path":"__TRANSCRIPT__","cwd":"/proyecto","prompt_id":"c1a70000-1111-4222-8333-444455556666","permission_mode":"auto","hook_event_name":"UserPromptSubmit","prompt":"%s"}' "$1"
}

adv_payload_agent() {
  printf '{"session_id":"__SESSION_ID__","transcript_path":"__TRANSCRIPT__","cwd":"/proyecto","prompt_id":"c1a70000-1111-4222-8333-777788889999","permission_mode":"auto","effort":{"level":"xhigh"},"hook_event_name":"PostToolUse","tool_name":"Agent","tool_input":{"description":"paso del harness","prompt":"hace lo tuyo","subagent_type":"%s","run_in_background":false},"tool_response":{"status":"completed","agentType":"%s","content":"listo","resolvedModel":"claude-opus-5"},"tool_use_id":"toolu_01a1b2c3d4e5f60718293a4b","duration_ms":4200}' "$1" "$1"
}

adv_payload_stop_sin_mensaje() {
  printf '{"session_id":"__SESSION_ID__","transcript_path":"__TRANSCRIPT__","cwd":"/proyecto","prompt_id":"c1a70000-1111-4222-8333-444455556666","permission_mode":"auto","effort":{"level":"xhigh"},"hook_event_name":"Stop","stop_hook_active":false,"background_tasks":[],"session_crons":[]}'
}

if fm_only gate-advzona-teardown-seguro; then
  adv_lab_init
  adv_run prompt claude "$(adv_payload_prompt '-saikit ataca el cambio con adversary')"
  adv_run tool claude "$(adv_payload_agent 'adversary')"
  zona="$ADVLAB/proyecto/.saikit/scratch/adversary/$ADV_SES"
  afuera="$ADVLAB/afuera"
  rm -rf "$afuera"
  mkdir -p "$afuera/scratch/adversary/$ADV_SES"
  printf 'centinela-ajeno\n' > "$afuera/scratch/adversary/$ADV_SES/centinela.txt"
  rm -rf "$ADVLAB/proyecto/.saikit"
  ln -s "$afuera" "$ADVLAB/proyecto/.saikit" 2>/dev/null || true
  if [ -L "$ADVLAB/proyecto/.saikit" ]; then
    adv_run prompt claude \
      "$(adv_payload_prompt 'seguimos con otra cosa sin sentinel')"
    fm_action gate-advzona-teardown-seguro act-teardown "$ADV_RC" "$ADV_ERR" \
      bash "$ADVLAB/hooks/summonaikit-harness.sh" -- desarme
    # assert:teardown_fail_open
    if [ "$ADV_RC" -eq 0 ]; then
      fm_pass gate-advzona-teardown-seguro teardown_fail_open "exit 0" \
        "el desarme no bloquea el turno (fail-open)"
    else
      fm_fail gate-advzona-teardown-seguro teardown_fail_open "exit 0" \
        "rc=$ADV_RC $ADV_ERR"
    fi
    # assert:teardown_diagnostico
    if printf '%s' "$ADV_ERR" | grep -q 'limpieza de zona OMITIDA' \
      && printf '%s' "$ADV_ERR" | grep -q 'es symlink'; then
      fm_pass gate-advzona-teardown-seguro teardown_diagnostico \
        "OMITIDA + es symlink" "la omision se declara y nombra el enlace"
    else
      fm_fail gate-advzona-teardown-seguro teardown_diagnostico \
        "OMITIDA + es symlink" "$ADV_ERR"
    fi
    # assert:centinela_ajeno_intacto
    if [ -f "$afuera/scratch/adversary/$ADV_SES/centinela.txt" ]; then
      fm_pass gate-advzona-teardown-seguro centinela_ajeno_intacto \
        "centinela vivo" "no borro a traves del enlace de ancestro"
    else
      fm_fail gate-advzona-teardown-seguro centinela_ajeno_intacto \
        "centinela vivo" "el teardown borro contenido ajeno al proyecto"
    fi
  else
    fm_action gate-advzona-teardown-seguro act-teardown "" "" \
      bash "$ADVLAB/hooks/summonaikit-harness.sh" -- desarme
    razon="sin symlinks reales en este entorno (ln -s copia); el CI de Linux lo ejercita"
    fm_unknown gate-advzona-teardown-seguro teardown_fail_open "exit 0" "$razon"
    fm_unknown gate-advzona-teardown-seguro teardown_diagnostico \
      "OMITIDA + es symlink" "$razon"
    fm_unknown gate-advzona-teardown-seguro centinela_ajeno_intacto \
      "centinela vivo" "$razon"
  fi
fi

if fm_only gate-advzona-unknown-limpia; then
  adv_lab_init
  adv_run prompt claude "$(adv_payload_prompt '-saikit ataca el cambio con adversary')"
  adv_run tool claude "$(adv_payload_agent 'adversary')"
  zona="$ADVLAB/proyecto/.saikit/scratch/adversary/$ADV_SES"
  mkdir -p "$zona"
  printf 'fixture\n' > "$zona/fixture.json"
  ajena="$ADVLAB/proyecto/.saikit/scratch/adversary/otrasesion-7777"
  mkdir -p "$ajena"
  printf 'ajeno\n' > "$ajena/su-fixture.txt"
  printf 'suelto\n' > "$ADVLAB/proyecto/.saikit/scratch/suelto.txt"
  adv_run stop claude "$(adv_payload_stop_sin_mensaje)"
  fm_action gate-advzona-unknown-limpia act-unknown "$ADV_RC" "$ADV_ERR" \
    bash "$ADVLAB/hooks/summonaikit-harness.sh" -- stop
  estado_sobra="$(find "$ADVLAB/hooks/state" -type f -name harness-state.env 2>/dev/null | head -n 1)"
  # assert:unknown_exit0_estado_limpio
  if [ "$ADV_RC" -eq 0 ] && [ -z "$estado_sobra" ] \
    && printf '%s' "$ADV_ERR" | grep -q 'unknown honesto'; then
    fm_pass gate-advzona-unknown-limpia unknown_exit0_estado_limpio \
      "exit 0 sin estado" "declara unknown honesto y retira el estado"
  else
    fm_fail gate-advzona-unknown-limpia unknown_exit0_estado_limpio \
      "exit 0 sin estado" "rc=$ADV_RC estado=${estado_sobra:-none} $ADV_ERR"
  fi
  # assert:unknown_limpia_zona
  if [ ! -e "$zona" ]; then
    fm_pass gate-advzona-unknown-limpia unknown_limpia_zona "zona retirada" \
      "la salida unknown limpia la zona de la ejecucion"
  else
    fm_fail gate-advzona-unknown-limpia unknown_limpia_zona "zona retirada" \
      "la zona sobrevivio al cierre unknown"
  fi
  # assert:scratch_ajeno_intacto
  if [ -f "$ajena/su-fixture.txt" ] && [ -f "$ADVLAB/proyecto/.saikit/scratch/suelto.txt" ]; then
    fm_pass gate-advzona-unknown-limpia scratch_ajeno_intacto "ajeno intacto" \
      "ni la zona de otra sesion ni el scratch suelto se tocan"
  else
    fm_fail gate-advzona-unknown-limpia scratch_ajeno_intacto "ajeno intacto" \
      "la limpieza toco contenido ajeno del scratch"
  fi
fi

exit 0
