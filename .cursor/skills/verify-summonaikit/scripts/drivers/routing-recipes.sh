#!/usr/bin/env bash
# routing-recipes driver — existing roles + recetario manifest.
# Does not implement Optional 16.7 (--task). Does not credit a live turn
# or a dsh adapter load.
set -euo pipefail
driver_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_root="$(cd "$driver_dir/../.." && pwd)"
# shellcheck source=../lib/runtime.sh
. "$skill_root/scripts/lib/runtime.sh"
# shellcheck source=../lib/driver.sh
. "$skill_root/scripts/lib/driver.sh"

: "${VERIFY_HOME:?}" "${VERIFY_REPO:?}" "${VERIFY_TMPDIR:?}"
: "${SAIKIT_FM_ATTEMPT_DIR:?}"

ROUTER="$VERIFY_REPO/tools/model-routing.sh"
GEN="$VERIFY_REPO/tools/gen-recetas-manifest.sh"

run_router() {
  runtime_exec "$VERIFY_HOME" bash "$ROUTER" "$@"
}

good_recipe() {
  mkdir -p "$(dirname "$1")"
  cat > "$1" <<'EOF'
---
saikit_owned: summonaikit-claude
nombre: bug
titulo: Arreglar algo que no funciona
carril: full
cuando: ["no funciona", "da error"]
adversary: opcional
---
## Pasos
1. Reproducir.
## Qué le dices al usuario
Primero qué cambia para ti.
## Recibo
Understand: … Receta: bug.
EOF
}

if fm_only routing-roles; then
  set +e
  cl_out="$(run_router --host claude --role implementer --field model 2>&1)"
  cl_rc=$?
  gk_out="$(run_router --host grok --role reviewer --field model 2>&1)"
  gk_rc=$?
  set -e
  fm_action routing-roles act-claude "$cl_rc" "$cl_out" bash "$ROUTER" --host claude --role implementer
  fm_action routing-roles act-grok "$gk_rc" "$gk_out" bash "$ROUTER" --host grok --role reviewer
  # assert:claude_implementer
  if [ "$cl_rc" -eq 0 ] && [ "$cl_out" = "claude-sonnet-5" ]; then
    fm_pass routing-roles claude_implementer "claude-sonnet-5" "claude-sonnet-5"
  else
    fm_fail routing-roles claude_implementer "claude-sonnet-5" "rc=$cl_rc [$cl_out]"
  fi
  # assert:claude_implementer_end
  if [ "$gk_rc" -eq 0 ] && [ "$gk_out" = "grok-4.6" ]; then
    fm_pass routing-roles grok_reviewer "grok-4.6" "grok-4.6"
  else
    fm_fail routing-roles grok_reviewer "grok-4.6" "rc=$gk_rc [$gk_out]"
  fi
  empty_ok=1
  empty_obs=''
  for h in zcode kimi dsh; do
    set +e
    e_out="$(run_router --host "$h" --role implementer --field model 2>&1)"
    e_rc=$?
    set -e
    empty_obs="$empty_obs $h:rc=$e_rc:[$e_out]"
    if [ "$e_rc" -ne 0 ] || [ -n "$e_out" ]; then
      empty_ok=0
    fi
  done
  if [ "$empty_ok" -eq 1 ]; then
    fm_pass routing-roles empty_unmeasured "vacio zcode/kimi/dsh" \
      "empty zcode kimi dsh (vacio, heredan)"
  else
    fm_fail routing-roles empty_unmeasured "vacio zcode/kimi/dsh" "$empty_obs"
  fi
fi

if fm_only routing-unknown; then
  set +e
  out="$(run_router --host claude --role astronauta 2>/dev/null)"
  rc=$?
  set -e
  fm_action routing-unknown act-unknown "$rc" "$out" bash "$ROUTER" --role astronauta
  if [ "$rc" -eq 2 ] && [ -z "$out" ]; then
    fm_pass routing-unknown unknown_role_exit_2 "2" "exit 2 stdout vacio"
  else
    fm_fail routing-unknown unknown_role_exit_2 "2" "rc=$rc [$out]"
  fi
fi

REC_DIR="$VERIFY_TMPDIR/fm-recetas"
if fm_only recipes-manifest-ok || fm_only recipes-manifest-altered || fm_only recipes-consume; then
  rm -rf "$REC_DIR"
  good_recipe "$REC_DIR/bug.md"
  set +e
  gen_out="$(runtime_exec "$VERIFY_HOME" bash "$GEN" --dir "$REC_DIR" 2>&1)"
  gen_rc=$?
  set -e
  fm_action recipes-manifest-ok act-gen "$gen_rc" "$gen_out" bash "$GEN" --dir
fi

if fm_only recipes-manifest-ok; then
  set +e
  runtime_exec "$VERIFY_HOME" bash "$GEN" --dir "$REC_DIR" --check >/dev/null 2>&1
  ck=$?
  set -e
  fm_action recipes-manifest-ok act-check "$ck" "check rc=$ck" bash "$GEN" --check
  if [ "$ck" -eq 0 ]; then
    fm_pass recipes-manifest-ok manifest_check_ok "0 al dia" "0 al dia"
  else
    fm_fail recipes-manifest-ok manifest_check_ok "0 al dia" "rc=$ck"
  fi
fi

if fm_only recipes-manifest-altered; then
  if [ -f "$REC_DIR/bug.md" ]; then
    python3 - "$REC_DIR/bug.md" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
text = p.read_text(encoding="utf-8")
p.write_text(text.replace("titulo: Arreglar algo que no funciona", "titulo: Otro titulo"), encoding="utf-8")
PY
  fi
  set +e
  runtime_exec "$VERIFY_HOME" bash "$GEN" --dir "$REC_DIR" --check >/dev/null 2>&1
  ck=$?
  set -e
  fm_action recipes-manifest-altered act-stale "$ck" "stale rc=$ck" bash "$GEN" --check
  if [ "$ck" -eq 1 ]; then
    fm_pass recipes-manifest-altered manifest_check_stale "1 stale/alterado" "1 stale alterado"
  else
    fm_fail recipes-manifest-altered manifest_check_stale "1 stale/alterado" "rc=$ck"
  fi
fi

if fm_only recipes-consume; then
  # Restore a valid pair so consume does not depend on the altered case.
  good_recipe "$REC_DIR/bug.md"
  runtime_exec "$VERIFY_HOME" bash "$GEN" --dir "$REC_DIR" >/dev/null 2>&1 || true
  man="$REC_DIR/MANIFEST.sha256"
  if [ -f "$man" ] && grep -q $'\tbug\t' "$man"; then
    line="$(grep $'\tbug\t' "$man" | head -1)"
    fm_pass recipes-consume recetario_consumido "MANIFEST bug" "MANIFEST receta bug $line"
  else
    fm_fail recipes-consume recetario_consumido "MANIFEST bug" "sin linea bug en $man"
  fi
fi

if fm_only routing-no-16.7; then
  set +e
  out="$(run_router --host claude --task bug 2>&1)"
  rc=$?
  set -e
  fm_action routing-no-16.7 act-task "$rc" "$out" bash "$ROUTER" --task
  if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -Eqi 'desconocido|unknown'; then
    fm_pass routing-no-16.7 no_task_flag "sin --task / 16.7" \
      "argumento desconocido; Optional 16.7 no implementado"
  else
    fm_fail routing-no-16.7 no_task_flag "sin --task / 16.7" "rc=$rc $out"
  fi
fi

if fm_only routing-no-live; then
  fm_pass routing-no-live no_live_turn \
    "routing != live turn" \
    "no acredita turno vivo del modelo"
  fm_pass routing-no-live no_dsh_adapter_load \
    "routing != dsh adapter load" \
    "sin carga del adaptador dsh; no acredita que el host lo cargara"
fi

exit 0
