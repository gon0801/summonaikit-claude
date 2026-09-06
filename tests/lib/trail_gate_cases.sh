#!/usr/bin/env bash
# Casos del Stop trail/blast. Los consume test_trail_gate.sh y, como G8,
# test_gate_behavior.sh / test_gate_mutations.sh.

_RECIBO_SIN_TRAIL='SUMMONAIKIT HARNESS RECEIPT\n- Understand: pediste poder listar las sesiones abiertas.\n- Implement: se agrego el endpoint y su ruta.\n- Verify: se corrio la bateria completa, 12 en verde.\n- Review: sin hallazgos.\n- Close: entregado; no se toco codigo despues de la revision.\n- Retro: none.'

_recibo_close() {
  printf '%s' "SUMMONAIKIT HARNESS RECEIPT\\n- Understand: pediste poder listar las sesiones abiertas.\\n- Implement: se agrego el endpoint y su ruta.\\n- Verify: se corrio la bateria completa, 12 en verde.\\n- Review: sin hallazgos.\\n- Close: ${1}\\n- Retro: none."
}

_recibo_understand() {
  printf '%s' "SUMMONAIKIT HARNESS RECEIPT\\n- Understand: ${1}\\n- Implement: se agrego el endpoint y su ruta.\\n- Verify: se corrio la bateria completa, 12 en verde.\\n- Review: sin hallazgos.\\n- Close: entregado; no se toco codigo despues de la revision.\\n- Retro: none."
}

_recibo_skip_linea() {
  printf '%s\\n%s' "$_RECIBO_SIN_TRAIL" "$1"
}

plantar_trail() {
  mkdir -p "$LAB/proyecto/.saikit/decisiones" "$LAB/proyecto/.saikit/findings"
  : > "$LAB/proyecto/.saikit/decisiones/${1}.tsv"
  : > "$LAB/proyecto/.saikit/findings/blast-${1}.json"
}

limpiar_saikit() {
  rm -rf "$LAB/proyecto/.saikit"
}

_afirma_bloqueo_trail() {
  _igual "$1 exit" "$LAB_RC" "2"
  _contiene "$1 decision" "$LAB_OUT" '"decision":"block"'
  _contiene "$1 missing" "$LAB_OUT" 'Missing trail/blast'
  _contiene "$1 nombra TRAIL SKIP:" "$LAB_OUT" 'TRAIL SKIP:'
  _contiene "$1 nombra Close:" "$LAB_OUT" 'Close:'
}

_afirma_cierre() {
  _igual "$1 exit" "$LAB_RC" "0"
  _vacio "$1 stdout" "$LAB_OUT"
}

full_sin_cita_sin_skip_bloquea() {
  limpiar_saikit
  _sembrar_turno_completo
  lab_run stop claude "$(lab_payload_stop "$_RECIBO_SIN_TRAIL")"
  _afirma_bloqueo_trail "sin cita ni skip"

  _sembrar_turno_completo
  plantar_trail x
  lab_run stop claude "$(lab_payload_stop "$(_recibo_close 'trail at .saikit/decisiones/x.tsv ; blast at .saikit/findings/blast-x.json ; code after reviewer: no.')")"
  _afirma_cierre "flip: citar ambas existentes"

  _sembrar_turno_completo
  limpiar_saikit
  lab_run stop claude "$(lab_payload_stop "$(_recibo_skip_linea 'TRAIL SKIP: docs-only')")"
  _afirma_cierre "flip: TRAIL SKIP con razon y sin archivos"
}

full_cita_ambas_cierra() {
  limpiar_saikit
  _sembrar_turno_completo
  plantar_trail x
  lab_run stop claude "$(lab_payload_stop "$(_recibo_close 'trail at .saikit/decisiones/x.tsv ; blast at .saikit/findings/blast-x.json ; code after reviewer: no.')")"
  _afirma_cierre "cita ambas"
}

full_archivos_sin_cita_bloquea() {
  limpiar_saikit
  _sembrar_turno_completo
  plantar_trail x
  lab_run stop claude "$(lab_payload_stop "$_RECIBO_SIN_TRAIL")"
  _afirma_bloqueo_trail "archivos en disco sin cita"
}

full_cita_glob_bloquea() {
  limpiar_saikit
  _sembrar_turno_completo
  plantar_trail x
  lab_run stop claude "$(lab_payload_stop "$(_recibo_close 'trail at .saikit/decisiones/*.tsv ; blast at .saikit/findings/blast-*.json')")"
  _afirma_bloqueo_trail "cita glob"
}

full_cita_inexistente_bloquea() {
  limpiar_saikit
  _sembrar_turno_completo
  lab_run stop claude "$(lab_payload_stop "$(_recibo_close 'trail at .saikit/decisiones/18.12.tsv ; blast at .saikit/findings/blast-18.12.json')")"
  _afirma_bloqueo_trail "cita inventada"
}

full_cita_solo_tsv_bloquea() {
  limpiar_saikit
  _sembrar_turno_completo
  mkdir -p "$LAB/proyecto/.saikit/decisiones"
  : > "$LAB/proyecto/.saikit/decisiones/x.tsv"
  lab_run stop claude "$(lab_payload_stop "$(_recibo_close 'trail at .saikit/decisiones/x.tsv ; blast at .saikit/findings/blast-x.json')")"
  _afirma_bloqueo_trail "solo tsv"
}

full_cita_solo_blast_bloquea() {
  limpiar_saikit
  _sembrar_turno_completo
  mkdir -p "$LAB/proyecto/.saikit/findings"
  : > "$LAB/proyecto/.saikit/findings/blast-x.json"
  lab_run stop claude "$(lab_payload_stop "$(_recibo_close 'trail at .saikit/decisiones/x.tsv ; blast at .saikit/findings/blast-x.json')")"
  _afirma_bloqueo_trail "solo blast"
}

full_cita_fuera_de_close_bloquea() {
  limpiar_saikit
  _sembrar_turno_completo
  plantar_trail x
  lab_run stop claude "$(lab_payload_stop "$(_recibo_understand 'ves .saikit/decisiones/x.tsv y .saikit/findings/blast-x.json')")"
  _afirma_bloqueo_trail "cita fuera de Close"
}

full_skip_con_razon_cierra() {
  limpiar_saikit
  _sembrar_turno_completo
  lab_run stop claude "$(lab_payload_stop "$(_recibo_skip_linea 'TRAIL SKIP: docs-only')")"
  _afirma_cierre "skip con razon"
}

full_skip_sin_razon_bloquea() {
  limpiar_saikit
  _sembrar_turno_completo
  lab_run stop claude "$(lab_payload_stop "$(_recibo_skip_linea 'TRAIL SKIP:')")"
  _afirma_bloqueo_trail "skip sin razon"
}

full_skip_en_prosa_bloquea() {
  limpiar_saikit
  _sembrar_turno_completo
  lab_run stop claude "$(lab_payload_stop "$(_recibo_close "el feedback pedia 'TRAIL SKIP: x' y no lo declare")")"
  _afirma_bloqueo_trail "skip citado en prosa"
}

full_skip_en_tail_no_cuenta() {
  limpiar_saikit
  _sembrar_turno_completo
  lab_run stop claude "$(lab_payload_stop "$_RECIBO_SIN_TRAIL")" \
    "$(lab_transcript_asistente "$(_recibo_skip_linea 'TRAIL SKIP: docs-only')")"
  _afirma_bloqueo_trail "skip solo en tail"
}

full_cita_en_tail_no_cuenta() {
  limpiar_saikit
  _sembrar_turno_completo
  plantar_trail x
  lab_run stop claude "$(lab_payload_stop "$_RECIBO_SIN_TRAIL")" \
    "$(lab_transcript_asistente "$(_recibo_close 'trail at .saikit/decisiones/x.tsv ; blast at .saikit/findings/blast-x.json')")"
  _afirma_bloqueo_trail "cita solo en tail"
}

fast_sin_cita_sin_skip_cierra() {
  limpiar_saikit
  lab_run prompt claude "$(lab_payload_prompt '-saikit:fast corrige el typo')"
  lab_run tool claude "$(lab_payload_edit '/proyecto/src/header.ts')"
  lab_run tool claude "$(lab_payload_bash 'pytest -q')"
  lab_run stop claude "$(lab_payload_stop "$_RECIBO_SIN_TRAIL")"
  _afirma_cierre "fast exento"
}

full_residual_citado_cierra() {
  limpiar_saikit
  _sembrar_turno_completo
  plantar_trail old
  lab_run stop claude "$(lab_payload_stop "$(_recibo_close 'trail at .saikit/decisiones/old.tsv ; blast at .saikit/findings/blast-old.json')")"
  _afirma_cierre "residual citado a proposito"
}

paused_sin_cita_permite() {
  limpiar_saikit
  _sembrar_turno_completo
  lab_run stop claude "$(lab_payload_stop "$_TEXTO_PAUSA")"
  _afirma_cierre "PAUSED sin trail"
}

full_otro_gate_recuerda_trail() {
  limpiar_saikit
  _sembrar_turno_completo
  lab_run stop claude "$(lab_payload_stop "${_RECIBO_SIN_RETRO}\\nTRAIL SKIP: golden fixture")"
  _igual "exit por Retro faltante" "$LAB_RC" "2"
  _contiene "otro gate sigue nombrando TRAIL SKIP:" "$LAB_OUT" 'TRAIL SKIP:'
}

CASOS_G8="full_sin_cita_sin_skip_bloquea full_archivos_sin_cita_bloquea full_cita_glob_bloquea full_cita_inexistente_bloquea full_cita_solo_tsv_bloquea full_cita_solo_blast_bloquea full_cita_fuera_de_close_bloquea full_skip_en_prosa_bloquea full_skip_sin_razon_bloquea full_skip_en_tail_no_cuenta full_cita_en_tail_no_cuenta full_cita_ambas_cierra full_skip_con_razon_cierra fast_sin_cita_sin_skip_cierra full_residual_citado_cierra paused_sin_cita_permite full_otro_gate_recuerda_trail"
