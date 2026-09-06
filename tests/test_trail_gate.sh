#!/usr/bin/env bash
# tests/test_trail_gate.sh — Stop full-lane exige cita de trail/blast o TRAIL SKIP.
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
. "$here/lib/hook_lab.sh"
. "$here/lib/gate_cases.sh"

if [ ! -r "$here/lib/hook_bajo_prueba.sh" ]; then
  echo "test_trail_gate: unknown — falta tests/lib/hook_bajo_prueba.sh; no se pudo resolver que archivo probar." >&2
  exit 3
fi
. "$here/lib/hook_bajo_prueba.sh"
vivo="$(resolver_hook_bajo_prueba "$here/.." "test_trail_gate")" \
  || exit "$SAIKIT_EXIT_UNKNOWN"

if [ -z "${TMPDIR:-}" ] || [ -z "${HOME:-}" ]; then
  _box="$(mktemp -d "${TMPDIR:-/tmp}/saikit-trail-box-XXXXXX")" || exit 1
  mkdir -p "$_box/home" "$_box/tmp"
  export HOME="$_box/home" USERPROFILE="$_box/home" TMPDIR="$_box/tmp"
fi

fail=0

_recibo_close() {
  printf '%s' "SUMMONAIKIT HARNESS RECEIPT\\n- Understand: pediste poder listar las sesiones abiertas.\\n- Implement: se agrego el endpoint y su ruta.\\n- Verify: se corrio la bateria completa, 12 en verde.\\n- Review: sin hallazgos.\\n- Close: ${1}\\n- Retro: none."
}

_recibo_understand() {
  printf '%s' "SUMMONAIKIT HARNESS RECEIPT\\n- Understand: ${1}\\n- Implement: se agrego el endpoint y su ruta.\\n- Verify: se corrio la bateria completa, 12 en verde.\\n- Review: sin hallazgos.\\n- Close: entregado; no se toco codigo despues de la revision.\\n- Retro: none."
}

_recibo_skip_linea() {
  printf '%s\\n%s' "$_RECIBO_VINETAS" "$1"
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

caso() { printf '  caso: %s\n' "$1"; CASO_ROJO=0; lab_limpiar_estado; limpiar_saikit; }
fin_caso() {
  if [ "$CASO_ROJO" -ne 0 ]; then
    printf '    ROJO: %s\n' "$1" >&2
    fail=1
  else
    printf '    ok: %s\n' "$1"
  fi
}

if ! lab_init "$vivo"; then
  echo "test_trail_gate: FAIL — no se pudo montar el banco de pruebas" >&2
  exit 1
fi
trap 'lab_fin' EXIT

full_sin_cita_sin_skip_bloquea() {
  _sembrar_turno_completo
  lab_run stop claude "$(lab_payload_stop "$_RECIBO_VINETAS")"
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
  _sembrar_turno_completo
  plantar_trail x
  lab_run stop claude "$(lab_payload_stop "$(_recibo_close 'trail at .saikit/decisiones/x.tsv ; blast at .saikit/findings/blast-x.json ; code after reviewer: no.')")"
  _afirma_cierre "cita ambas"
}

full_archivos_sin_cita_bloquea() {
  _sembrar_turno_completo
  plantar_trail x
  lab_run stop claude "$(lab_payload_stop "$_RECIBO_VINETAS")"
  _afirma_bloqueo_trail "archivos en disco sin cita"
}

full_cita_glob_bloquea() {
  _sembrar_turno_completo
  plantar_trail x
  lab_run stop claude "$(lab_payload_stop "$(_recibo_close 'trail at .saikit/decisiones/*.tsv ; blast at .saikit/findings/blast-*.json')")"
  _afirma_bloqueo_trail "cita glob"
}

full_cita_inexistente_bloquea() {
  _sembrar_turno_completo
  lab_run stop claude "$(lab_payload_stop "$(_recibo_close 'trail at .saikit/decisiones/18.12.tsv ; blast at .saikit/findings/blast-18.12.json')")"
  _afirma_bloqueo_trail "cita inventada"
}

full_cita_solo_tsv_bloquea() {
  _sembrar_turno_completo
  mkdir -p "$LAB/proyecto/.saikit/decisiones"
  : > "$LAB/proyecto/.saikit/decisiones/x.tsv"
  lab_run stop claude "$(lab_payload_stop "$(_recibo_close 'trail at .saikit/decisiones/x.tsv ; blast at .saikit/findings/blast-x.json')")"
  _afirma_bloqueo_trail "solo tsv"
}

full_cita_solo_blast_bloquea() {
  _sembrar_turno_completo
  mkdir -p "$LAB/proyecto/.saikit/findings"
  : > "$LAB/proyecto/.saikit/findings/blast-x.json"
  lab_run stop claude "$(lab_payload_stop "$(_recibo_close 'trail at .saikit/decisiones/x.tsv ; blast at .saikit/findings/blast-x.json')")"
  _afirma_bloqueo_trail "solo blast"
}

full_cita_fuera_de_close_bloquea() {
  _sembrar_turno_completo
  plantar_trail x
  lab_run stop claude "$(lab_payload_stop "$(_recibo_understand 'ves .saikit/decisiones/x.tsv y .saikit/findings/blast-x.json')")"
  _afirma_bloqueo_trail "cita fuera de Close"
}

full_skip_con_razon_cierra() {
  _sembrar_turno_completo
  lab_run stop claude "$(lab_payload_stop "$(_recibo_skip_linea 'TRAIL SKIP: docs-only')")"
  _afirma_cierre "skip con razon"
}

full_skip_sin_razon_bloquea() {
  _sembrar_turno_completo
  lab_run stop claude "$(lab_payload_stop "$(_recibo_skip_linea 'TRAIL SKIP:')")"
  _afirma_bloqueo_trail "skip sin razon"
}

full_skip_en_prosa_bloquea() {
  _sembrar_turno_completo
  lab_run stop claude "$(lab_payload_stop "$(_recibo_close "el feedback pedia 'TRAIL SKIP: x' y no lo declare")")"
  _afirma_bloqueo_trail "skip citado en prosa"
}

full_skip_en_tail_no_cuenta() {
  _sembrar_turno_completo
  lab_run stop claude "$(lab_payload_stop "$_RECIBO_VINETAS")" \
    "$(lab_transcript_asistente "$(_recibo_skip_linea 'TRAIL SKIP: docs-only')")"
  _afirma_bloqueo_trail "skip solo en tail"
}

full_cita_en_tail_no_cuenta() {
  _sembrar_turno_completo
  plantar_trail x
  lab_run stop claude "$(lab_payload_stop "$_RECIBO_VINETAS")" \
    "$(lab_transcript_asistente "$(_recibo_close 'trail at .saikit/decisiones/x.tsv ; blast at .saikit/findings/blast-x.json')")"
  _afirma_bloqueo_trail "cita solo en tail"
}

fast_sin_cita_sin_skip_cierra() {
  lab_run prompt claude "$(lab_payload_prompt '-saikit:fast corrige el typo')"
  lab_run tool claude "$(lab_payload_edit '/proyecto/src/header.ts')"
  lab_run tool claude "$(lab_payload_bash 'pytest -q')"
  lab_run stop claude "$(lab_payload_stop "$_RECIBO_VINETAS")"
  _afirma_cierre "fast exento"
}

full_residual_citado_cierra() {
  _sembrar_turno_completo
  plantar_trail old
  lab_run stop claude "$(lab_payload_stop "$(_recibo_close 'trail at .saikit/decisiones/old.tsv ; blast at .saikit/findings/blast-old.json')")"
  _afirma_cierre "residual citado a proposito"
}

paused_sin_cita_permite() {
  _sembrar_turno_completo
  lab_run stop claude "$(lab_payload_stop "$_TEXTO_PAUSA")"
  _afirma_cierre "PAUSED sin trail"
}

CASOS="
full_sin_cita_sin_skip_bloquea
full_cita_ambas_cierra
full_archivos_sin_cita_bloquea
full_cita_glob_bloquea
full_cita_inexistente_bloquea
full_cita_solo_tsv_bloquea
full_cita_solo_blast_bloquea
full_cita_fuera_de_close_bloquea
full_skip_con_razon_cierra
full_skip_sin_razon_bloquea
full_skip_en_prosa_bloquea
full_skip_en_tail_no_cuenta
full_cita_en_tail_no_cuenta
fast_sin_cita_sin_skip_cierra
full_residual_citado_cierra
paused_sin_cita_permite
"

for c in $CASOS; do
  caso "$c"
  "$c"
  fin_caso "$c"
done

if [ "$fail" -ne 0 ]; then
  echo "test_trail_gate: FAIL" >&2
  exit 1
fi
echo "test_trail_gate: OK"
