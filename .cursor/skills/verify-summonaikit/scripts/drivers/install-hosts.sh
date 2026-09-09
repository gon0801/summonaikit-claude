#!/usr/bin/env bash
# install-hosts driver — four hook copies, zcode reuse, kimi profiles.
# Registration is judged by diagnostic text/structure, never exit 0.
# Isolated HOME only. Does not credit a live model turn or dsh adapter load.
set -euo pipefail
driver_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_root="$(cd "$driver_dir/../.." && pwd)"
# shellcheck source=../lib/runtime.sh
. "$skill_root/scripts/lib/runtime.sh"
# shellcheck source=../lib/driver.sh
. "$skill_root/scripts/lib/driver.sh"

: "${VERIFY_HOME:?}" "${VERIFY_DEST:?}" "${VERIFY_REPO:?}" "${VERIFY_TMPDIR:?}"
: "${SAIKIT_FM_ATTEMPT_DIR:?}"

INSTALLER="$VERIFY_REPO/tools/install-hook.sh"
REG="$VERIFY_REPO/tools/check-hook-registration.sh"
HOOK_SRC="$VERIFY_REPO/hooks/summonaikit-harness.sh"
MANIFEST="$VERIFY_REPO/hooks/vendor-manifest.sha256"
SRC_SHA="$(fm_sha "$HOOK_SRC")"

fm_unknown() { fm_assert "$1" "$2" unknown "$3" "$4"; }

# Identidad de CONTENIDO y ARBOL de un directorio (20fix H1): toda entrada
# del arbol — archivos con cksum, directorios (incluidos los vacios) y
# symlinks con su destino — listada y ordenada (portable mac/linux). Comparar
# el string completo detecta escrituras, borrados, reescrituras, backups
# nuevos, archivos ajenos y directorios creados o borrados (un dir vacio no
# es invisible) que un conteo de piezas o una lista de nombres no ven.
# 20fix r5 (C4): la clasificacion NO sigue enlaces (primarias de find, no
# `[ -f ]` que SIgue el enlace): reemplazar un archivo por un symlink a bytes
# IDENTICOS conservaba el cksum y el swap pasaba inadvertido (medido). Ahora
# la sustitucion cambia la linea `F <path> <cksum>` por `L <path> -> <destino>`
# y rompe la identidad aunque los bytes sean los mismos.
# r5 (adversario L1): el inodo entra en la linea F — un archivo reemplazado
# por un HARDLINK a bytes identicos conserva el cksum y era invisible (la
# sustitucion cambia el inodo y rompe la identidad; comparable porque el
# snapshot se toma dos veces sobre el MISMO arbol).
# LIMITES declarados: permisos y timestamps quedan fuera del snapshot; los
# enlaces entran con su destino (readlink), no con el contenido apuntado.
snapshot_tree() {
  local tree="$1" f
  find "$tree" -type f | LC_ALL=C sort | while IFS= read -r f; do
    printf 'F %s %s %s\n' "$f" "$(cksum < "$f")" "$(ls -i "$f" | awk '{print $1}')"
  done
  find "$tree" -type d | LC_ALL=C sort | while IFS= read -r f; do
    printf 'D %s\n' "$f"
  done
  find "$tree" -type l | LC_ALL=C sort | while IFS= read -r f; do
    printf 'L %s -> %s\n' "$f" "$(readlink "$f")"
  done
}

hook_path() {
  case "$1" in
    claude) printf '%s' "$VERIFY_DEST" ;;
    grok) printf '%s/.grok/hooks/summonaikit-harness.sh' "$VERIFY_HOME" ;;
    dsh) printf '%s/.dsh/hooks/summonaikit-harness.sh' "$VERIFY_HOME" ;;
    codex) printf '%s/.codex/hooks/summonaikit-harness.sh' "$VERIFY_HOME" ;;
    *) return 1 ;;
  esac
}

run_install() {
  runtime_exec "$VERIFY_HOME" bash "$INSTALLER" \
    --source "$HOOK_SRC" --manifest "$MANIFEST" --no-registration-check "$@"
}

run_reg() {
  runtime_exec "$VERIFY_HOME" bash "$REG" "$@"
}

has_jq() { command -v jq >/dev/null 2>&1; }
has_cygpath() { command -v cygpath >/dev/null 2>&1; }

can_symlink() {
  local t="$VERIFY_TMPDIR/fm-symlink-probe-t" l="$VERIFY_TMPDIR/fm-symlink-probe-l"
  rm -f "$t" "$l"
  printf 'probe\n' > "$t"
  ln -s "$t" "$l" 2>/dev/null && [ -L "$l" ]
}

plant_zcode_cfg() {
  mkdir -p "$VERIFY_HOME/.zcode/cli" "$VERIFY_HOME/.zcode/agents"
  cat > "$VERIFY_HOME/.zcode/cli/config.json" <<'JSON'
{
  "hooks": {
    "enabled": true,
    "events": {
      "SessionStart": [
        { "hooks": [ { "type": "command", "command": "echo arranque-dummy" } ] }
      ],
      "Stop": [
        { "hooks": [ { "type": "command", "command": "echo tokentracker-dummy" } ] }
      ]
    }
  }
}
JSON
}

GROK_INSTALL_OUT=''
FOUR_OBS=''

if fm_only hosts-four-copies; then
  mkdir -p "$VERIFY_HOME/.claude/hooks" "$VERIFY_HOME/.grok/hooks" \
    "$VERIFY_HOME/.dsh/hooks" "$VERIFY_HOME/.codex/hooks"
  # Neighbor planted early so hosts-foreign can measure it after later writes.
  printf 'FOREIGN-NEIGHBOR-%s\n' "$$" > "$VERIFY_HOME/.claude/hooks/saikit-foreign-neighbor.sh"
  printf 'FOREIGN-GROK-%s\n' "$$" > "$VERIFY_HOME/.grok/hooks/saikit-foreign-neighbor.sh"

  if [ -f "$VERIFY_DEST" ] && grep -q 'SAIKIT-CLAUDE-OWNED' "$VERIFY_DEST"; then
    FOUR_OBS="claude=$(fm_sha "$VERIFY_DEST")"
    fm_pass hosts-four-copies claude_hook "claude hook present" "claude $FOUR_OBS"
  else
    fm_fail hosts-four-copies claude_hook "claude hook present" "claude dest missing"
  fi

  set +e
  grok_out="$(run_install --host grok 2>&1)"
  grok_rc=$?
  set -e
  GROK_INSTALL_OUT="$grok_out"
  fm_action hosts-four-copies act-grok "$grok_rc" "$grok_out" bash "$INSTALLER" --host grok
  grok_dest="$(hook_path grok)"
  # assert:grok_hook
  if [ "$grok_rc" -ne 0 ] && ! has_jq; then
    fm_unknown hosts-four-copies grok_hook "grok hook" "jq ausente; grok no observado"
  elif [ "$grok_rc" -eq 0 ] && [ -f "$grok_dest" ] && [ "$(fm_sha "$grok_dest")" = "$SRC_SHA" ]; then
    fm_pass hosts-four-copies grok_hook "grok hook=source" "grok $(fm_sha "$grok_dest")"
  else
    fm_fail hosts-four-copies grok_hook "grok hook=source" "rc=$grok_rc dest=$grok_dest"
  fi
  # assert:grok_hook_end

  set +e
  dsh_out="$(run_install --host dsh 2>&1)"
  dsh_rc=$?
  set -e
  fm_action hosts-four-copies act-dsh "$dsh_rc" "$dsh_out" bash "$INSTALLER" --host dsh
  dsh_dest="$(hook_path dsh)"
  if [ "$dsh_rc" -eq 0 ] && [ -f "$dsh_dest" ] && [ "$(fm_sha "$dsh_dest")" = "$SRC_SHA" ]; then
    fm_pass hosts-four-copies dsh_hook "dsh hook=source" "dsh $(fm_sha "$dsh_dest")"
  else
    fm_fail hosts-four-copies dsh_hook "dsh hook=source" "rc=$dsh_rc dest=$dsh_dest $dsh_out"
  fi

  set +e
  cx_out="$(run_install --host codex 2>&1)"
  cx_rc=$?
  set -e
  fm_action hosts-four-copies act-codex "$cx_rc" "$cx_out" bash "$INSTALLER" --host codex
  cx_dest="$(hook_path codex)"
  if [ "$cx_rc" -eq 0 ] && [ -f "$cx_dest" ] && [ "$(fm_sha "$cx_dest")" = "$SRC_SHA" ]; then
    fm_pass hosts-four-copies codex_hook "codex hook=source" "codex $(fm_sha "$cx_dest")"
  else
    fm_fail hosts-four-copies codex_hook "codex hook=source" "rc=$cx_rc dest=$cx_dest $cx_out"
  fi

  zc_hook="$VERIFY_HOME/.zcode/hooks/summonaikit-harness.sh"
  km_hook="$VERIFY_HOME/.kimi/hooks/summonaikit-harness.sh"
  if [ ! -e "$zc_hook" ]; then
    fm_pass hosts-four-copies zcode_no_hook_copy "sin copia de hook zcode" "zcode sin copia (reusa claude)"
  else
    fm_fail hosts-four-copies zcode_no_hook_copy "sin copia de hook zcode" "invento $zc_hook"
  fi
  if [ ! -e "$km_hook" ]; then
    fm_pass hosts-four-copies kimi_no_hook_copy "sin copia de hook kimi" "kimi sin copia (solo perfiles)"
  else
    fm_fail hosts-four-copies kimi_no_hook_copy "sin copia de hook kimi" "invento $km_hook"
  fi
fi

if fm_only hosts-zcode-reuses; then
  plant_zcode_cfg
  before="$(fm_sha "$VERIFY_DEST")"
  if ! has_jq; then
    fm_unknown hosts-zcode-reuses zcode_reuses_claude "fases zcode" "jq ausente; zcode no observado"
    fm_unknown hosts-zcode-reuses zcode_dest_untouched "unchanged" "jq ausente; zcode no observado"
  else
    set +e
    zc_out="$(run_install --host zcode --dest "$VERIFY_DEST" 2>&1)"
    zc_rc=$?
    set -e
    fm_action hosts-zcode-reuses act-zcode "$zc_rc" "$zc_out" bash "$INSTALLER" --host zcode
    after="$(fm_sha "$VERIFY_DEST")"
    fases="$(python3 - "$VERIFY_HOME/.zcode/cli/config.json" <<'PY'
import json, sys
ev = json.load(open(sys.argv[1], encoding="utf-8"))["hooks"]["events"]
need = ("UserPromptSubmit", "PostToolUse", "Stop", "SessionStart")
print(" ".join(n for n in need if n in ev))
print("dummy" if any("arranque-dummy" in str(ev.get("SessionStart")) for _ in [0]) else "dummy-lost")
PY
)"
    if [ "$zc_rc" -eq 0 ] && printf '%s' "$fases" | grep -q 'UserPromptSubmit' \
      && printf '%s' "$fases" | grep -q 'PostToolUse' \
      && [ ! -e "$VERIFY_HOME/.zcode/hooks/summonaikit-harness.sh" ]; then
      fm_pass hosts-zcode-reuses zcode_reuses_claude "reusa claude + 4 fases" "zcode reusa claude fases=$fases"
    else
      fm_fail hosts-zcode-reuses zcode_reuses_claude "reusa claude + 4 fases" "rc=$zc_rc $fases $zc_out"
    fi
    if [ "$before" = "$after" ]; then
      fm_pass hosts-zcode-reuses zcode_dest_untouched "unchanged" "unchanged $after"
    else
      fm_fail hosts-zcode-reuses zcode_dest_untouched "unchanged" "changed $before -> $after"
    fi
  fi
fi

if fm_only hosts-kimi-profiles; then
  before="$(fm_sha "$VERIFY_DEST")"
  set +e
  km_out="$(run_install --host kimi --dest "$VERIFY_DEST" 2>&1)"
  km_rc=$?
  set -e
  fm_action hosts-kimi-profiles act-kimi "$km_rc" "$km_out" bash "$INSTALLER" --host kimi
  kdir="$VERIFY_HOME/.agents/agents"
  have=''
  for rol in implementer verifier reviewer adversary; do
    [ -f "$kdir/$rol.md" ] && have="$have $rol"
  done
  if [ "$km_rc" -eq 0 ] && printf '%s' "$have" | grep -q implementer \
    && printf '%s' "$have" | grep -q reviewer \
    && printf '%s' "$have" | grep -q adversary \
    && [ ! -e "$VERIFY_HOME/.kimi/hooks/summonaikit-harness.sh" ]; then
    fm_pass hosts-kimi-profiles kimi_profiles "perfiles kimi" "kimi perfiles:$have"
  else
    fm_fail hosts-kimi-profiles kimi_profiles "perfiles kimi" "rc=$km_rc have=$have $km_out"
  fi
  if [ -f "$kdir/reviewer.md" ] && ! grep -q '^model:' "$kdir/reviewer.md" \
    && ! grep -q '^effort:' "$kdir/reviewer.md"; then
    fm_pass hosts-kimi-profiles kimi_no_model "sin model/effort" "kimi sin ruteo (sin model:)"
  else
    fm_fail hosts-kimi-profiles kimi_no_model "sin model/effort" "reviewer lleva model/effort"
  fi
  after="$(fm_sha "$VERIFY_DEST")"
  if [ "$before" = "$after" ]; then
    fm_pass hosts-kimi-profiles kimi_dest_untouched "unchanged" "unchanged $after"
  else
    fm_fail hosts-kimi-profiles kimi_dest_untouched "unchanged" "changed $before -> $after"
  fi
fi

if fm_only hosts-identity; then
  marked=0
  matched=0
  for h in claude grok dsh codex; do
    p="$(hook_path "$h")"
    [ -f "$p" ] || continue
    grep -q 'SAIKIT-CLAUDE-OWNED' "$p" && marked=$((marked + 1))
    [ "$(fm_sha "$p")" = "$SRC_SHA" ] && matched=$((matched + 1))
  done
  if [ "$marked" -eq 4 ]; then
    fm_pass hosts-identity ownership_marker "SAIKIT-CLAUDE-OWNED" "SAIKIT-CLAUDE-OWNED x$marked"
  else
    fm_fail hosts-identity ownership_marker "SAIKIT-CLAUDE-OWNED x4" "marked=$marked"
  fi
  # assert:dest_matches_source
  if [ "$matched" -eq 4 ]; then
    fm_pass hosts-identity dest_matches_source "$SRC_SHA" "matched=4 sha=$SRC_SHA"
  else
    fm_fail hosts-identity dest_matches_source "$SRC_SHA x4" "matched=$matched"
  fi
  # assert:dest_matches_source_end
  ident="$GROK_INSTALL_OUT"
  if [ -z "$ident" ]; then
    set +e
    ident="$(run_install --host grok --dry-run 2>&1)"
    set -e
  fi
  if printf '%s' "$ident" | grep -q 'procedencia: rama='; then
    line="$(printf '%s' "$ident" | grep -m1 'procedencia: rama=' || true)"
    fm_pass hosts-identity procedencia "procedencia: rama=" "$line"
  else
    fm_fail hosts-identity procedencia "procedencia: rama=" "$ident"
  fi
fi

if fm_only hosts-noop; then
  gdest="$(hook_path grok)"
  if [ ! -f "$gdest" ] && ! has_jq; then
    fm_unknown hosts-noop ya_al_dia "YA AL DIA" "jq ausente; grok no-op no observado"
    fm_unknown hosts-noop dest_unchanged "unchanged" "jq ausente; grok no-op no observado"
  else
    before="$(fm_sha "$gdest")"
    set +e
    out="$(run_install --host grok 2>&1)"
    rc=$?
    set -e
    fm_action hosts-noop act-noop "$rc" "$out" bash "$INSTALLER" --host grok
    after="$(fm_sha "$gdest")"
    # assert:ya_al_dia
    if printf '%s' "$out" | grep -q 'YA AL DIA'; then
      fm_pass hosts-noop ya_al_dia "YA AL DIA" "YA AL DIA"
    else
      fm_fail hosts-noop ya_al_dia "YA AL DIA" "$out"
    fi
    # assert:ya_al_dia_end
    if [ "$before" = "$after" ]; then
      fm_pass hosts-noop dest_unchanged "unchanged" "unchanged $after"
    else
      fm_fail hosts-noop dest_unchanged "unchanged" "changed $before -> $after"
    fi
  fi
fi

if fm_only hosts-foreign; then
  neighbor="$VERIFY_HOME/.claude/hooks/saikit-foreign-neighbor.sh"
  if [ ! -f "$neighbor" ]; then
    printf 'FOREIGN-NEIGHBOR-%s\n' "$$" > "$neighbor"
  fi
  n_before="$(fm_sha "$neighbor")"
  set +e
  out="$(run_install --dest "$VERIFY_DEST" 2>&1)"
  rc=$?
  set -e
  fm_action hosts-foreign act-foreign "$rc" "$out" bash "$INSTALLER" --dest "$VERIFY_DEST"
  n_after="$(fm_sha "$neighbor")"
  # assert:foreign_intact
  if [ "$n_before" = "$n_after" ]; then
    fm_pass hosts-foreign foreign_intact "intact" "intact $n_after"
  else
    fm_fail hosts-foreign foreign_intact "intact" "changed $n_before -> $n_after"
  fi
  # assert:foreign_intact_end
fi

if fm_only hosts-registration; then
  set +e
  grok_reg="$(run_reg --grok-hooks-dir "$VERIFY_HOME/.grok/hooks" 2>&1)"
  grok_reg_rc=$?
  set -e
  fm_action hosts-registration act-reg-grok "$grok_reg_rc" "$grok_reg" bash "$REG" --grok-hooks-dir
  incomplete="$VERIFY_TMPDIR/fm-reg-incomplete.json"
  cat > "$incomplete" <<'JSON'
{"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"echo x"}]}],"Stop":[{"hooks":[{"type":"command","command":"echo y"}]}]}}
JSON
  set +e
  cl_reg="$(run_reg --settings "$incomplete" 2>&1)"
  cl_reg_rc=$?
  set -e
  fm_action hosts-registration act-reg-incompleto "$cl_reg_rc" "$cl_reg" bash "$REG" --settings
  cl_reg_one="$(printf '%s' "$cl_reg" | tr '\n' ' ' | cut -c1-200)"
  # assert:registro_por_texto
  if printf '%s' "$cl_reg" | grep -F -q 'REGISTRO DEL HOOK INCOMPLETO' \
    && printf '%s' "$cl_reg" | grep -F -q 'el gate NO corre'; then
    fm_pass hosts-registration registro_por_texto \
      "INCOMPLETO — el gate NO corre" "$cl_reg_one"
  else
    fm_fail hosts-registration registro_por_texto \
      "INCOMPLETO — el gate NO corre" "$cl_reg_one"
  fi
  # assert:registro_por_texto_end
  if [ "$grok_reg_rc" -eq 0 ] && [ "$cl_reg_rc" -eq 0 ]; then
    fm_pass hosts-registration registro_no_solo_exit \
      "texto/estructura; no.exit.0" \
      "diagnostico por texto/estructura; no.exit.0 (advisory rc=0)"
  else
    fm_fail hosts-registration registro_no_solo_exit \
      "advisory exit 0 + texto" "rc grok=$grok_reg_rc claude=$cl_reg_rc"
  fi
  # assert:fases_estructura
  if printf '%s' "$cl_reg" | grep -F -q 'INCOMPLETO' \
    && printf '%s' "$cl_reg" | grep -q 'PostToolUse' \
    && printf '%s' "$cl_reg" | grep -q 'SessionStart'; then
    fm_pass hosts-registration fases_estructura \
      "INCOMPLETO PostToolUse SessionStart" "$cl_reg_one"
  else
    fm_fail hosts-registration fases_estructura \
      "INCOMPLETO PostToolUse SessionStart" "$cl_reg_one"
  fi
  # assert:fases_estructura_end
fi

if fm_only hosts-os-unavailable; then
  observed=''
  for h in claude grok dsh codex; do
    p="$(hook_path "$h")"
    [ -f "$p" ] && observed="$observed $h"
  done
  if printf '%s' "$observed" | grep -Eq 'claude|grok|dsh|codex'; then
    fm_pass hosts-os-unavailable other_hosts_observed "otros hosts observados" \
      "observados:$observed"
  else
    fm_fail hosts-os-unavailable other_hosts_observed "otros hosts observados" \
      "ninguno$observed"
  fi
  wrap="$VERIFY_HOME/.codex/hooks/summonaikit-harness-codex-wrap.sh"
  ps1="$VERIFY_HOME/.codex/hooks/summonaikit-harness.ps1"
  if has_cygpath; then
    fm_pass hosts-os-unavailable posix_wrap "POSIX wrap o no observada" \
      "unknown: cygpath presente; rama POSIX no observada"
    if [ -f "$ps1" ] || printf '%s' "${GROK_INSTALL_OUT}" | grep -q '&'; then
      fm_pass hosts-os-unavailable windows_wrap "Windows .ps1 / cygpath" \
        "windows wrap/ps1/cygpath observado"
    else
      fm_pass hosts-os-unavailable windows_wrap "Windows .ps1 o no observada" \
        "unknown: cygpath presente; .ps1 no entregado por el kit (OS/host-unavailable)"
    fi
  else
    fm_pass hosts-os-unavailable windows_wrap "Windows .ps1 o no observada" \
      "unknown: sin cygpath; rama Windows no observada"
    if [ -f "$wrap" ] && grep -q 'summonaikit-harness.sh' "$wrap"; then
      fm_pass hosts-os-unavailable posix_wrap "POSIX wrap" \
        "POSIX wrap $wrap"
    else
      fm_fail hosts-os-unavailable posix_wrap "POSIX wrap" "ausente $wrap"
    fi
  fi
fi

if fm_only hosts-symlink; then
  if ! can_symlink; then
    fm_unknown hosts-symlink symlink_refused "enlace no seguido" \
      "este host no crea symlinks reales; unknown"
  else
    ext="$VERIFY_TMPDIR/fm-recetas-externas"
    rec="$VERIFY_HOME/.claude/hooks/recetas"
    rm -rf "$ext" "$rec"
    mkdir -p "$ext"
    printf -- '---\nsaikit_owned: summonaikit-claude\nnombre: bug\ntitulo: X\ncarril: full\ncuando: ["x"]\nadversary: opcional\n---\n## Pasos\n1. a\n## Qué le dices al usuario\nb\n## Recibo\nc\n' > "$ext/bug.md"
    ln -s "$ext" "$rec"
    antes="$(fm_sha "$ext/bug.md")"
    set +e
    out="$(run_install --host claude --dest "$VERIFY_DEST" 2>&1)"
    rc=$?
    set -e
    fm_action hosts-symlink act-symlink "$rc" "$out" bash "$INSTALLER" --host claude
    despues="$(fm_sha "$ext/bug.md")"
    # assert:symlink_refused
    if [ "$antes" = "$despues" ] && [ -L "$rec" ] \
      && printf '%s' "$out" | grep -qi 'enlace'; then
      fm_pass hosts-symlink symlink_refused "enlace intacto" \
        "enlace, no se publica; externo intact"
    else
      fm_fail hosts-symlink symlink_refused "enlace intacto" \
        "rc=$rc L=$( [ -L "$rec" ] && echo 1 || echo 0 ) $out"
    fi
    # assert:symlink_refused_end
  fi
fi

if fm_only hosts-retirada; then
  neighbor="$VERIFY_HOME/.grok/hooks/saikit-foreign-neighbor.sh"
  if [ ! -f "$neighbor" ]; then
    printf 'FOREIGN-GROK-%s\n' "$$" > "$neighbor"
  fi
  n_before="$(fm_sha "$neighbor")"
  if ! has_jq; then
    fm_unknown hosts-retirada retirada_preserva "quitado" "jq ausente; grok retirada no observada"
    fm_unknown hosts-retirada neighbor_intact_after_retirada "intact" "jq ausente"
  else
    set +e
    out="$(run_install --host grok --quitar-grok 2>&1)"
    rc=$?
    set -e
    fm_action hosts-retirada act-quitar "$rc" "$out" bash "$INSTALLER" --host grok --quitar-grok
    n_after="$(fm_sha "$neighbor")"
    if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -Eqi 'QUITADO|quitado|backup'; then
      fm_pass hosts-retirada retirada_preserva "quitado + vecinos" \
        "retirada grok: quitado/backup observado"
    else
      fm_fail hosts-retirada retirada_preserva "quitado + vecinos" "rc=$rc $out"
    fi
    if [ "$n_before" = "$n_after" ]; then
      fm_pass hosts-retirada neighbor_intact_after_retirada "intact" "intact $n_after"
    else
      fm_fail hosts-retirada neighbor_intact_after_retirada "intact" \
        "changed $n_before -> $n_after"
    fi
  fi
fi

# 20.24: la retirada zcode respeta DRY_RUN — reporta y clasifica sin tocar
# las piezas. 20fix H1 endurece el caso: se planta un agente DESCONOCIDO (sin
# marca saikit_owned) para observar la clasificacion en AMBAS direcciones, un
# archivo AJENO en el arbol, y se exige identidad de CONTENIDO y ARBOL del
# arbol completo (find+cksum con dirs incluidos: config, agentes,
# saikit-backups, vacios y ajenos) antes == despues.
# La linea fm_action de abajo es la costura de los mutantes de escritura del
# banco (tests/test_feature_map_hosts.sh): nada legitimo escribe entre el
# dry-run y el snapshot de despues.
if fm_only hosts-quitar-zcode-dry; then
  plant_zcode_cfg
  if ! has_jq; then
    fm_unknown hosts-quitar-zcode-dry quitar_zcode_dry_reporta \
      "dry-run: --quitar-zcode no ejecuta la retirada" "jq ausente; zcode retirada no observada"
    fm_unknown hosts-quitar-zcode-dry quitar_zcode_dry_clasifica \
      "quitaria N entrada(s) 5.4" "jq ausente; zcode retirada no observada"
    fm_unknown hosts-quitar-zcode-dry quitar_zcode_dry_clasifica_agente \
      "AGENTE ZCODE nuestro — se quitaria" "jq ausente; zcode retirada no observada"
    fm_unknown hosts-quitar-zcode-dry quitar_zcode_dry_clasifica_desconocido \
      "DESCONOCIDO — no se quitaria" "jq ausente; zcode retirada no observada"
    fm_unknown hosts-quitar-zcode-dry quitar_zcode_dry_snapshot_igual \
      "snapshot antes == despues" "jq ausente; zcode retirada no observada"
    fm_unknown hosts-quitar-zcode-dry quitar_zcode_dry_preserva \
      "piezas presentes" "jq ausente; zcode retirada no observada"
  else
    set +e
    ins_out="$(run_install --host zcode --dest "$VERIFY_DEST" 2>&1)"
    ins_rc=$?
    set -e
    user_cfg="$VERIFY_HOME/.zcode/cli/config.json"
    zc_agents="$VERIFY_HOME/.zcode/agents"
    zc_tree="$VERIFY_HOME/.zcode"
    # AJENO: el snapshot debe probar que el dry-run ni lo toco.
    printf 'AJENO-ZCODE-%s\n' "$$" > "$zc_tree/ajeno.txt"
    # DESCONOCIDO: reviewer SIN marca saikit_owned — el clasificador debe
    # decir de este rol "no se quitaria" y de los otros "se quitaria".
    printf -- '---\nnombre: revisor ajeno\n---\ncuerpo ajeno sin marca saikit_owned\n' \
      > "$zc_agents/reviewer.md"
    # backups pre-creados: entran al snapshot aunque vayan vacios.
    mkdir -p "$(dirname "$user_cfg")/saikit-backups"
    zc_antes="$(snapshot_tree "$zc_tree")"
    set +e
    out="$(run_install --host zcode --quitar-zcode --dry-run 2>&1)"
    rc=$?
    set -e
    fm_action hosts-quitar-zcode-dry act-quitar-zcode-dry "$rc" "$out" \
      bash "$INSTALLER" --host zcode --quitar-zcode --dry-run
    # assert:quitar_zcode_dry_reporta
    if [ "$rc" -eq 0 ] \
      && printf '%s' "$out" | grep -q 'dry-run: --quitar-zcode no ejecuta la retirada'; then
      fm_pass hosts-quitar-zcode-dry quitar_zcode_dry_reporta \
        "dry-run: --quitar-zcode no ejecuta la retirada" "reporta sin ejecutar (install rc=$ins_rc)"
    else
      fm_fail hosts-quitar-zcode-dry quitar_zcode_dry_reporta \
        "dry-run: --quitar-zcode no ejecuta la retirada" "rc=$rc $out"
    fi
    # assert:quitar_zcode_dry_reporta_end
    # assert:quitar_zcode_dry_clasifica
    # Ancla por pieza: `quitaria N entrada(s) saikit-harness-id 5.4` con N>=1
    # es la linea del user-config (la N real cuenta las 4 fases 5.4).
    if printf '%s' "$out" \
      | grep -Eq 'quitaria [1-9][0-9]* entrada\(s\) saikit-harness-id 5[.]4'; then
      fm_pass hosts-quitar-zcode-dry quitar_zcode_dry_clasifica \
        "quitaria N entrada(s) 5.4" "linea de config 5.4 clasificada"
    else
      fm_fail hosts-quitar-zcode-dry quitar_zcode_dry_clasifica \
        "quitaria N entrada(s) 5.4" "$out"
    fi
    # assert:quitar_zcode_dry_clasifica_end
    # assert:quitar_zcode_dry_clasifica_agente
    # Ancla con guion largo: `— se quitaria` NO es subcadena de `— no se
    # quitaria` (la subcadena pelada 'se quitaria' si lo era — hueco 20fix H1).
    zc_nuestras=0
    zc_vistas=''
    for rol in implementer verifier adversary; do
      if printf '%s' "$out" | grep -F -q "AGENTE ZCODE nuestro: $rol — se quitaria"; then
        zc_nuestras=$((zc_nuestras + 1))
        zc_vistas="$zc_vistas $rol"
      fi
    done
    if [ "$zc_nuestras" -eq 3 ]; then
      fm_pass hosts-quitar-zcode-dry quitar_zcode_dry_clasifica_agente \
        "AGENTE ZCODE nuestro — se quitaria" "por pieza:$zc_vistas"
    else
      fm_fail hosts-quitar-zcode-dry quitar_zcode_dry_clasifica_agente \
        "AGENTE ZCODE nuestro — se quitaria" "vistas$zc_vistas ($zc_nuestras/3)"
    fi
    # assert:quitar_zcode_dry_clasifica_agente_end
    # assert:quitar_zcode_dry_clasifica_desconocido
    if printf '%s' "$out" \
      | grep -F -q "AGENTE ZCODE DESCONOCIDO: reviewer — no se quitaria"; then
      fm_pass hosts-quitar-zcode-dry quitar_zcode_dry_clasifica_desconocido \
        "DESCONOCIDO — no se quitaria" "reviewer ajeno clasificado no-se-quita"
    else
      fm_fail hosts-quitar-zcode-dry quitar_zcode_dry_clasifica_desconocido \
        "DESCONOCIDO — no se quitaria" "$out"
    fi
    # assert:quitar_zcode_dry_clasifica_desconocido_end
    zc_despues="$(snapshot_tree "$zc_tree")"
    # assert:quitar_zcode_dry_snapshot_igual
    if [ "$zc_antes" = "$zc_despues" ]; then
      fm_pass hosts-quitar-zcode-dry quitar_zcode_dry_snapshot_igual \
        "snapshot antes == despues" "identidad de contenido y arbol .zcode (find+cksum, dirs incluidos)"
    else
      fm_fail hosts-quitar-zcode-dry quitar_zcode_dry_snapshot_igual \
        "snapshot antes == despues" "el arbol .zcode cambio tras el dry-run"
    fi
    # assert:quitar_zcode_dry_snapshot_igual_end
    entradas_despues="$(jq '[(.hooks.events // {})[] | .[] | (.hooks // [])[]
                 | select(((.command // "") | test("saikit-harness-id 5[.]4")))] | length' \
              "$user_cfg" 2>/dev/null || printf '?')"
    agentes_despues=''
    for r in implementer verifier reviewer adversary; do
      if [ -f "$zc_agents/$r.md" ]; then
        agentes_despues="$agentes_despues $r"
      fi
    done
    # assert:quitar_zcode_dry_preserva
    if [ "$entradas_despues" != "?" ] && [ "$entradas_despues" -gt 0 ] \
      && [ "${#agentes_despues}" -gt 0 ] \
      && printf '%s' "$agentes_despues" | grep -q implementer \
      && printf '%s' "$agentes_despues" | grep -q verifier \
      && printf '%s' "$agentes_despues" | grep -q reviewer \
      && printf '%s' "$agentes_despues" | grep -q adversary; then
      fm_pass hosts-quitar-zcode-dry quitar_zcode_dry_preserva \
        "piezas presentes" "entradas 5.4=$entradas_despues agentes=[$agentes_despues ]"
    else
      fm_fail hosts-quitar-zcode-dry quitar_zcode_dry_preserva \
        "piezas presentes" \
        "entradas=$entradas_despues agentes=[$agentes_despues ]"
    fi
    # assert:quitar_zcode_dry_preserva_end
  fi
fi

# 20.24: la retirada grok respeta DRY_RUN — reporta y clasifica JSON/hook/
# agentes sin archivar ni borrar nada. 20fix H1 endurece el caso: exige los
# CUATRO perfiles presentes (no "al menos uno"), clasificacion por pieza con
# ancla de guion largo, un agente DESCONOCIDO para la direccion negativa, un
# archivo AJENO y snapshot de contenido y arbol (find+cksum con dirs
# incluidos) del arbol .grok completo (hook, json, agentes y sus dirs de
# backups). La linea fm_action de abajo es
# la costura de los mutantes de escritura del banco.
if fm_only hosts-quitar-grok-dry; then
  if ! has_jq; then
    fm_unknown hosts-quitar-grok-dry quitar_grok_dry_reporta \
      "dry-run: --quitar-grok no ejecuta la retirada" "jq ausente; grok retirada no observada"
    fm_unknown hosts-quitar-grok-dry quitar_grok_dry_clasifica \
      "JSON/HOOK nuestro — se quitaria" "jq ausente; grok retirada no observada"
    fm_unknown hosts-quitar-grok-dry quitar_grok_dry_clasifica_agente \
      "AGENTE GROK nuestro — se quitaria" "jq ausente; grok retirada no observada"
    fm_unknown hosts-quitar-grok-dry quitar_grok_dry_clasifica_desconocido \
      "DESCONOCIDO — no se quitaria" "jq ausente; grok retirada no observada"
    fm_unknown hosts-quitar-grok-dry quitar_grok_dry_snapshot_igual \
      "snapshot antes == despues" "jq ausente; grok retirada no observada"
    fm_unknown hosts-quitar-grok-dry quitar_grok_dry_preserva \
      "piezas presentes" "jq ausente; grok retirada no observada"
  else
    set +e
    ins_out="$(run_install --host grok 2>&1)"
    ins_rc=$?
    set -e
    gdest="$(hook_path grok)"
    gjson="$(dirname "$gdest")/summonaikit.json"
    gagents="$VERIFY_HOME/.grok/agents"
    gtree="$VERIFY_HOME/.grok"
    # AJENO + DESCONOCIDO (reviewer sin marca) + backups pre-creados: todo
    # entra al snapshot y a la clasificacion en ambas direcciones.
    printf 'AJENO-GROK-%s\n' "$$" > "$gtree/ajeno.txt"
    printf -- '---\nnombre: revisor ajeno\n---\ncuerpo ajeno sin marca saikit_owned\n' \
      > "$gagents/reviewer.md"
    mkdir -p "$(dirname "$gdest")/saikit-backups" "$gagents/saikit-backups"
    g_antes="$(snapshot_tree "$gtree")"
    set +e
    out="$(run_install --host grok --quitar-grok --dry-run 2>&1)"
    rc=$?
    set -e
    fm_action hosts-quitar-grok-dry act-quitar-grok-dry "$rc" "$out" \
      bash "$INSTALLER" --host grok --quitar-grok --dry-run
    # assert:quitar_grok_dry_reporta
    if [ "$rc" -eq 0 ] \
      && printf '%s' "$out" | grep -q 'dry-run: --quitar-grok no ejecuta la retirada'; then
      fm_pass hosts-quitar-grok-dry quitar_grok_dry_reporta \
        "dry-run: --quitar-grok no ejecuta la retirada" "reporta sin ejecutar (install rc=$ins_rc)"
    else
      fm_fail hosts-quitar-grok-dry quitar_grok_dry_reporta \
        "dry-run: --quitar-grok no ejecuta la retirada" "rc=$rc $out"
    fi
    # assert:quitar_grok_dry_reporta_end
    # assert:quitar_grok_dry_clasifica
    # Ancla por pieza con guion largo: `— se quitaria` NO es subcadena de
    # `— no se quitaria`; la subcadena pelada casaba ambas (hueco 20fix H1).
    if printf '%s' "$out" | grep -F -q 'JSON DE GROK nuestro — se quitaria' \
      && printf '%s' "$out" | grep -F -q 'HOOK DE GROK nuestro — se quitaria'; then
      fm_pass hosts-quitar-grok-dry quitar_grok_dry_clasifica \
        "JSON/HOOK nuestro — se quitaria" "JSON y HOOK clasificados por pieza"
    else
      fm_fail hosts-quitar-grok-dry quitar_grok_dry_clasifica \
        "JSON/HOOK nuestro — se quitaria" "$out"
    fi
    # assert:quitar_grok_dry_clasifica_end
    # assert:quitar_grok_dry_clasifica_agente
    gk_nuestras=0
    gk_vistas=''
    for rol in implementer verifier adversary; do
      if printf '%s' "$out" | grep -F -q "AGENTE GROK nuestro: $rol — se quitaria"; then
        gk_nuestras=$((gk_nuestras + 1))
        gk_vistas="$gk_vistas $rol"
      fi
    done
    if [ "$gk_nuestras" -eq 3 ]; then
      fm_pass hosts-quitar-grok-dry quitar_grok_dry_clasifica_agente \
        "AGENTE GROK nuestro — se quitaria" "por pieza:$gk_vistas"
    else
      fm_fail hosts-quitar-grok-dry quitar_grok_dry_clasifica_agente \
        "AGENTE GROK nuestro — se quitaria" "vistas$gk_vistas ($gk_nuestras/3)"
    fi
    # assert:quitar_grok_dry_clasifica_agente_end
    # assert:quitar_grok_dry_clasifica_desconocido
    if printf '%s' "$out" \
      | grep -F -q "AGENTE GROK DESCONOCIDO: reviewer — no se quitaria"; then
      fm_pass hosts-quitar-grok-dry quitar_grok_dry_clasifica_desconocido \
        "DESCONOCIDO — no se quitaria" "reviewer ajeno clasificado no-se-quita"
    else
      fm_fail hosts-quitar-grok-dry quitar_grok_dry_clasifica_desconocido \
        "DESCONOCIDO — no se quitaria" "$out"
    fi
    # assert:quitar_grok_dry_clasifica_desconocido_end
    g_despues="$(snapshot_tree "$gtree")"
    # assert:quitar_grok_dry_snapshot_igual
    if [ "$g_antes" = "$g_despues" ]; then
      fm_pass hosts-quitar-grok-dry quitar_grok_dry_snapshot_igual \
        "snapshot antes == despues" "identidad de contenido y arbol .grok (find+cksum, dirs incluidos)"
    else
      fm_fail hosts-quitar-grok-dry quitar_grok_dry_snapshot_igual \
        "snapshot antes == despues" "el arbol .grok cambio tras el dry-run"
    fi
    # assert:quitar_grok_dry_snapshot_igual_end
    agentes_despues=''
    for r in implementer verifier reviewer adversary; do
      if [ -f "$gagents/$r.md" ]; then
        agentes_despues="$agentes_despues $r"
      fi
    done
    # assert:quitar_grok_dry_preserva
    if [ -f "$gdest" ] && [ -f "$gjson" ] \
      && printf '%s' "$agentes_despues" | grep -q implementer \
      && printf '%s' "$agentes_despues" | grep -q verifier \
      && printf '%s' "$agentes_despues" | grep -q reviewer \
      && printf '%s' "$agentes_despues" | grep -q adversary; then
      fm_pass hosts-quitar-grok-dry quitar_grok_dry_preserva \
        "piezas presentes" "hook+json presentes, 4 perfiles:[$agentes_despues ]"
    else
      fm_fail hosts-quitar-grok-dry quitar_grok_dry_preserva \
        "piezas presentes" \
        "hook=$([ -f "$gdest" ] && echo si || echo no) json=$([ -f "$gjson" ] && echo si || echo no) perfiles=[$agentes_despues ]"
    fi
    # assert:quitar_grok_dry_preserva_end
  fi
fi

if fm_only hosts-no-live; then
  fm_pass hosts-no-live no_live_turn \
    "install != live turn" \
    "no acredita turno vivo del modelo"
  fm_pass hosts-no-live no_dsh_adapter_load \
    "install != dsh adapter load" \
    "sin carga del adaptador dsh; no acredita que el host lo cargara"
fi

exit 0
