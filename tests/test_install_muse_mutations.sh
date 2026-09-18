#!/usr/bin/env bash
# Poder discriminante del instalador muse: sed sobre una copia,
# SAIKIT_INSTALL_TOOL=<mutante>, el driver test_install_muse.sh debe ir rojo.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
. "$here/lib/sandbox.sh"
sandbox_init || exit 1

mkdir -p "$SANDBOX/repo"
for dir in tools hooks agents hosts recetas skills; do
  cp -R "$repo/$dir" "$SANDBOX/repo/$dir" || exit 1
done
source_tool="$repo/tools/install-hook.sh"
mutant="$SANDBOX/repo/tools/install-hook.sh"
run_driver() { SAIKIT_INSTALL_TOOL="$mutant" bash "$here/test_install_muse.sh"; }

cp "$source_tool" "$mutant"
run_driver > "$SANDBOX/control.log" 2>&1 || { cat "$SANDBOX/control.log"; exit 1; }

fail=0
for mutation in \
  omitir_muse_check_host ignorar_marcas omitir_comparacion_avisos omitir_target_muse \
  omitir_schema_muse omitir_dest_meta omitir_settings_dir omitir_git_ceiling \
  omitir_del_mcpservers omitir_true_ajeno omitir_bash_vacio omitir_bash_ge4 \
  omitir_bash_n omitir_bin_inexistente omitir_backup omitir_quitar_agentes \
  omitir_check_token omitir_dry_run_mudo omitir_purga_todos
do
  case "$mutation" in
    omitir_muse_check_host)
      sed 's/ || \[ "$HOST" = "muse" \]; then/; then/' \
        "$source_tool" > "$mutant"
      expected='--check --host muse salio' ;;
    ignorar_marcas)
      sed \
        -e 's/\[ ! -f "$marcas_cand\/SessionStart" \]/[ -f "$marcas_cand\/SessionStart" ]/' \
        -e 's/\[ ! -f "$marcas_cand\/UserPromptSubmit" \]/[ -f "$marcas_cand\/UserPromptSubmit" ]/' \
        -e 's/\[ ! -f "$marcas_cand\/Stop" \]/[ -f "$marcas_cand\/Stop" ]/' \
        "$source_tool" > "$mutant"
      expected='sin marcas debia rechazar' ;;
    omitir_comparacion_avisos)
      sed 's/if ! muse_detalle_subconjunto "$cand_det" "$cur_det" || \[ "$cand_m" -gt "$cur_m" \]; then/if false; then/' \
        "$source_tool" > "$mutant"
      expected='campo desconocido en PreToolUse nuestro debia rechazar' ;;
    omitir_target_muse)
      sed 's/SUMMONAIKIT_HOOK_TARGET=muse /SUMMONAIKIT_HOOK_TARGET=other /g' \
        "$source_tool" > "$mutant"
      expected='cada comando debe setear TARGET=muse' ;;
    omitir_schema_muse)
      sed 's/muse_settings_aceptable "$settings" || exit 2/true/' \
        "$source_tool" > "$mutant"
      expected='debe nombrar schema_version' ;;
    omitir_dest_meta)
      sed 's/muse_dest_sin_meta || {/true || {/' \
        "$source_tool" > "$mutant"
      expected='DEST con $() debia rechazar' ;;
    omitir_settings_dir)
      sed 's/^  muse_abortar_si_settings_dir$/#  muse_abortar_si_settings_dir/' \
        "$source_tool" > "$mutant"
      expected='settings directorio debia rechazar' ;;
    omitir_git_ceiling)
      sed '/saikit-23.3-muse-git-retry/,+10d' \
        "$source_tool" > "$mutant"
      expected='Muse no debe ver git' ;;
    omitir_del_mcpservers)
      sed 's/del(\.mcpServers)/./' \
        "$source_tool" > "$mutant"
      expected='mcpServers.command no debe ejecutarse' ;;
    omitir_true_ajeno)
      sed 's/then .command = "\/usr\/bin\/true"/then .command = .command/' \
        "$source_tool" > "$mutant"
      expected='el hook ajeno no debe ejecutarse' ;;
    omitir_bash_vacio)
      sed 's/if \[ "\${SAIKIT_MUSE_BASH+set}" = "set" \]; then/if [ -n "${SAIKIT_MUSE_BASH:-}" ]; then/' \
        "$source_tool" > "$mutant"
      expected='SAIKIT_MUSE_BASH vacia salio' ;;
    omitir_bash_ge4)
      sed 's/"\$bash_bin" -c '\''\[ "\${BASH_VERSINFO\[0\]}" -ge 4 \]'\'' >\/dev\/null 2>\&1 || {/true || {/' \
        "$source_tool" > "$mutant"
      expected='bash menor a 4 salio' ;;
    omitir_bash_n)
      sed 's/"\$bash_bin" -n "\$DEST" >\/dev\/null 2>\&1 || {/true || {/' \
        "$source_tool" > "$mutant"
      expected='bash -n fallido salio' ;;
    omitir_bin_inexistente)
      sed 's/\[ -n "\$SAIKIT_MUSE_BIN" \] \&\& \[ -f "\$SAIKIT_MUSE_BIN" \]/true/' \
        "$source_tool" > "$mutant"
      expected='BIN inexistente salio' ;;
    omitir_backup)
      sed 's/if ! mkdir -p "$(dirname "$bak")" || ! cp "$settings" "$bak"; then/if false; then/' \
        "$source_tool" > "$mutant"
      expected='no dejo backup del settings' ;;
    omitir_quitar_agentes)
      sed 's/^  muse_quitar_agentes$/  true/' \
        "$source_tool" > "$mutant"
      expected='quitar dejo el perfil' ;;
    omitir_check_token)
      sed "s/_mreg='falta-registro'/_mreg='ok'/" \
        "$source_tool" > "$mutant"
      expected='sin settings, --check debe decir falta-registro' ;;
    omitir_dry_run_mudo)
      sed 's/if \[ ! -f "$marcas_cand\/SessionStart" \] || \[ ! -f "$marcas_cand\/UserPromptSubmit" \] \\/if [ "$DRY_RUN" -eq 1 ]; then false; elif [ ! -f "$marcas_cand\/SessionStart" ] || [ ! -f "$marcas_cand\/UserPromptSubmit" ] \\/' \
        "$source_tool" > "$mutant"
      expected='dry-run mudo debia rechazar' ;;
    omitir_purga_todos)
      sed 's/| purgar_todos$/| ./' \
        "$source_tool" > "$mutant"
      expected='SubagentStart debia quedar en 0' ;;
  esac
  if cmp -s "$source_tool" "$mutant" || ! bash -n "$mutant"; then
    printf 'FAIL: mutacion %s no aplico o no parsea\n' "$mutation"; fail=1; continue
  fi
  run_driver > "$SANDBOX/mutant.log" 2>&1; rc=$?
  if [ "$rc" -ne 1 ] || ! grep -Fq -- "$expected" "$SANDBOX/mutant.log"; then
    printf 'FAIL: %s no fue atrapada por su caso (exit=%s)\n' "$mutation" "$rc"
    cat "$SANDBOX/mutant.log"; fail=1
  else
    printf 'ATRAPADA %s: %s\n' "$mutation" "$expected"
  fi
done
[ "$fail" -eq 0 ] || exit 1
printf 'test_install_muse_mutations: OK (19 mutaciones)\n'
