#!/usr/bin/env bash
# 21.5 — Preflight canónico del recibo: el mismo veredicto y la misma causa
# que el Stop, sin efectos.
#
# Corpus común: cada caso corre el Stop real y el preflight sobre el MISMO
# recibo con el MISMO estado sembrado, y exige el mismo veredicto
# (PASS/FAIL) y la misma causa nombrada. Los requisitos dinámicos no
# observables se NOMBRAN en el reporte, no se dan por PASS. Sin efectos: no
# consume ciclos ni escribe estado o evidencia (snapshot antes/después).
# Ninguna regex/gramática paralela: el preflight ejecuta el MISMO stop_gate
# en un subshell con las rutas de estado redirigidas a un scratch temporal.
# La divergencia preflight/Stop queda roja por comportamiento (costura
# SAIKIT_MUT_PREFLIGHT_DIVERGE + mutantes G9 del catálogo).
#
# Consumen test_preflight_21_5.sh y, como G9, test_gate_behavior.sh /
# test_gate_mutations.sh.

# Compara Stop vs preflight sobre el mismo recibo y el mismo estado.
# $1 = nombre; $2 = verified a sembrar (0/1); $3 = recibo; $4 = causa
# ("" = ambos PASS); $5 = target (defecto claude); $6 = "adv" para sembrar
# violacion adversary (A6: unica via FAIL que queda). El Stop que cierra
# limpio BORRA el estado, asi que se re-siembra antes del preflight.
_pf_compara() {
  _pf_nombre="$1"; _pf_verified="$2"; _pf_recibo="$3"; _pf_causa="$4"; _pf_target="${5:-claude}"
  _pf_roles="implementer,verifier,reviewer"
  if [ "${6:-}" = "adv" ]; then _pf_roles="$_pf_roles,adversary"; fi
  lab_sembrar 123456 0 1 "$_pf_verified" "$_pf_roles"
  if [ "${6:-}" = "adv" ]; then _sem_violation_adversary; fi
  lab_run stop "$_pf_target" "$(lab_payload_stop "$_pf_recibo")"
  _pf_stop_rc="$LAB_RC"; _pf_stop_out="$LAB_OUT"
  lab_sembrar 123456 0 1 "$_pf_verified" "$_pf_roles"
  if [ "${6:-}" = "adv" ]; then _sem_violation_adversary; fi
  lab_run preflight "$_pf_target" "$(lab_payload_stop "$_pf_recibo")"
  _pf_pre_rc="$LAB_RC"; _pf_pre_out="$LAB_OUT"
  if [ "$_pf_stop_rc" = "0" ]; then
    case "$_pf_stop_out" in
      *'"decision":"block"'*|*'"continue":false'*|*'"followup_message"'*) _pf_stop_v="FAIL" ;;
      *) _pf_stop_v="PASS" ;;
    esac
  else
    _pf_stop_v="FAIL"
  fi
  case "$_pf_pre_out" in
    *'SAIKIT PREFLIGHT (21.5): PASS'*) _pf_pre_v="PASS" ;;
    *'SAIKIT PREFLIGHT (21.5): FAIL'*) _pf_pre_v="FAIL" ;;
    *) _pf_pre_v="SIN-REPORTE" ;;
  esac
  if [ "$_pf_stop_v" != "$_pf_pre_v" ]; then
    _mal "$_pf_nombre: veredicto diverge (Stop=$_pf_stop_v rc=$_pf_stop_rc, preflight=$_pf_pre_v rc=$_pf_pre_rc)"
    return 0
  fi
  if [ "$_pf_pre_v" = "PASS" ] && [ "$_pf_pre_rc" != "0" ]; then
    _mal "$_pf_nombre: preflight PASS con exit $_pf_pre_rc, se esperaba 0"
  fi
  if [ "$_pf_pre_v" = "FAIL" ] && [ "$_pf_pre_rc" != "1" ]; then
    _mal "$_pf_nombre: preflight FAIL con exit $_pf_pre_rc, se esperaba 1"
  fi
  if [ -z "$_pf_causa" ]; then
    if [ "$_pf_stop_v" != "PASS" ]; then _mal "$_pf_nombre: se esperaba PASS comun, Stop=$_pf_stop_v"; fi
  else
    case "$_pf_stop_out" in *"$_pf_causa"*) ;; *) _mal "$_pf_nombre: el Stop no nombra la causa [$_pf_causa]";; esac
    case "$_pf_pre_out" in *"$_pf_causa"*) ;; *) _mal "$_pf_nombre: el preflight no nombra la causa [$_pf_causa]";; esac
  fi
}

_pf_base() {
  _recibo_close 'trail at .saikit/decisiones/x.tsv ; blast at .saikit/findings/blast-x.json ; code after reviewer: no.'
}

caso_g9_recibo_valido_cierra_en_ambos() {
  limpiar_saikit
  plantar_trail x
  _pf_compara "recibo valido" 1 "$(_pf_base)" ""
}

caso_g9_etiqueta_ausente_cierra_en_ambos() {
  limpiar_saikit
  plantar_trail x
  _pf_compara "etiqueta ausente" 1 "$_RECIBO_SIN_RETRO" ""
}

caso_g9_etiqueta_malformada_cierra_en_ambos() {
  limpiar_saikit
  plantar_trail x
  _pf_mal="$(printf '%s' "$(_pf_base)" | sed 's/- Understand:/- Understand/')"
  _pf_compara "etiqueta mal formada" 1 "$_pf_mal" ""
}

caso_g9_evidencia_invalida_cierra_en_ambos() {
  limpiar_saikit
  plantar_trail x
  _pf_compara "evidencia invalida" 0 "$(_pf_base)" ""
}

caso_g9_trail_inexistente_cierra_en_ambos() {
  limpiar_saikit
  _pf_compara "trail inexistente" 1 "$(_pf_base)" ""
}

caso_g9_raiz_sin_sha_cierra_en_ambos() {
  limpiar_saikit
  _sha="$(_wt_nuevo wt-pf6)"
  _pf_compara "raiz sin sha" 1 "$(_recibo_close 'trail at .saikit/decisiones/21.4.tsv ; blast at .saikit/findings/blast-21.4.json ; raiz: '"$LAB/wt-pf6"' ; code after reviewer: no.')" ""
}

caso_g9_raiz_acreditada_cierra_en_ambos() {
  limpiar_saikit
  _sha="$(_wt_nuevo wt-pf7)"
  _pf_compara "raiz acreditada" 1 "$(_recibo_raiz "$LAB/wt-pf7" "$_sha")" ""
}

caso_g9_skip_con_razon_cierra_en_ambos() {
  limpiar_saikit
  _pf_compara "TRAIL SKIP" 1 "$(_recibo_skip_linea 'TRAIL SKIP: docs-only')" ""
}

caso_g9_dinamicos_nombrados_no_pass() {
  limpiar_saikit
  plantar_trail x
  lab_sembrar 123456 0 1 1 "implementer,verifier,reviewer"
  lab_run preflight claude "$(lab_payload_stop "$(_pf_base)")"
  _igual "dinamicos exit" "$LAB_RC" "0"
  _contiene "dinamicos veredicto" "$LAB_OUT" 'SAIKIT PREFLIGHT (21.5): PASS'
  for _pf_nom in '21.2' 'backgroundTasks' 'transcript' 'ciclo' 'agents_seen' 'snapshot'; do
    _contiene "dinamicos nombra $_pf_nom" "$LAB_OUT" "$_pf_nom"
  done
  _pf_din="$(printf '%s' "$LAB_OUT" | sed -n '/DINAMICOS/,/^$/p')"
  case "$_pf_din" in *': PASS'*) _mal "dinamicos: la seccion DINAMICOS da un PASS";; esac
}

caso_g9_sin_efectos() {
  limpiar_saikit
  plantar_trail x
  lab_sembrar 123456 0 1 1 "implementer,verifier,reviewer"
  _pf_antes_estado="$(cat "$LAB_ESTADO_PATH")"
  _pf_antes_fs="$(cd "$LAB" && find . -type f ! -path "./entrada/*" | LC_ALL=C sort)"
  lab_run preflight claude "$(lab_payload_stop "$(_pf_base)")"
  _igual "sin efectos exit" "$LAB_RC" "0"
  _igual "sin efectos estado intacto" "$(cat "$LAB_ESTADO_PATH")" "$_pf_antes_estado"
  _igual "sin efectos ciclo intacto" "$(lab_estado cycle)" "0"
  _igual "sin efectos fs intacto" "$(cd "$LAB" && find . -type f ! -path "./entrada/*" | LC_ALL=C sort)" "$_pf_antes_fs"
  lab_limpiar_estado
  lab_run preflight claude "$(lab_payload_stop "$(_pf_base)")"
  if lab_hay_estado; then _mal "sin efectos: el preflight creo estado sin haberlo"; fi
  _contiene "sin efectos sin estado hay reporte" "$LAB_OUT" 'SAIKIT PREFLIGHT (21.5):'
}

caso_g9_sin_gramatica_paralela() {
  if [ -z "${HOOK_BAJO_PRUEBA:-}" ] || [ ! -r "$HOOK_BAJO_PRUEBA" ]; then
    _mal "sin gramatica paralela: no hay hook bajo prueba legible"
    return 0
  fi
  _pf_cuerpo="$(sed -n '/^preflight_check()/,/^}/p' "$HOOK_BAJO_PRUEBA")"
  if [ -z "$_pf_cuerpo" ]; then _mal "sin gramatica paralela: preflight_check no existe en el hook bajo prueba"; return 0; fi
  if printf '%s' "$_pf_cuerpo" | grep -Eq 'grep|_RE=|sed -E|awk .*/|RECEIPT|Understand|Missing '; then
    _mal "sin gramatica paralela: el cuerpo del preflight trae motor propio (grep/RE/sed -E/awk/etiquetas)"
  fi
  case "$_pf_cuerpo" in *'stop_gate'*) ;; *) _mal "sin gramatica paralela: el preflight no ejecuta el stop_gate compartido";; esac
}

caso_g9_divergencia_queda_roja() {
  limpiar_saikit
  plantar_trail x
  # A6: la divergencia se demuestra por la via adversary (unica FAIL que queda).
  lab_sembrar 123456 0 1 0 "implementer,verifier,reviewer,adversary"
  _sem_violation_adversary
  lab_run stop claude "$(lab_payload_stop "$(_pf_base)")"
  _pf_div_stop_rc="$LAB_RC"
  lab_sembrar 123456 0 1 0 "implementer,verifier,reviewer,adversary"
  _sem_violation_adversary
  SAIKIT_MUT_PREFLIGHT_DIVERGE=1 lab_run preflight claude "$(lab_payload_stop "$(_pf_base)")"
  _pf_div_pre_rc="$LAB_RC"; _pf_div_pre_out="$LAB_OUT"
  if [ "$_pf_div_stop_rc" = "0" ]; then _mal "divergencia: el Stop debia bloquear (violacion adversary)"; fi
  case "$_pf_div_pre_out" in
    *'SAIKIT PREFLIGHT (21.5): FAIL'*) _mal "divergencia: la costura no diverge (preflight FAIL igual que el Stop)" ;;
    *'SAIKIT PREFLIGHT (21.5): PASS'*) ;;
    *) _mal "divergencia: el preflight mutado no reporta veredicto" ;;
  esac
  if [ "$_pf_div_pre_rc" = "$_pf_div_stop_rc" ]; then _mal "divergencia: mutante indistinguible del Stop"; fi
}

caso_g9_cursor_recibo_valido_cierra_en_ambos() {
  limpiar_saikit
  plantar_trail x
  _pf_compara "recibo valido (cursor)" 1 "$(_pf_base)" "" "cursor"
}

caso_g9_cursor_etiqueta_ausente_cierra_en_ambos() {
  limpiar_saikit
  plantar_trail x
  _pf_compara "etiqueta ausente (cursor)" 1 "$_RECIBO_SIN_RETRO" "" "cursor"
}

# A6: con estado ilegible el Stop es fail-open (permite: no puede leer ni
# siquiera la via adversary) mientras el preflight sigue siendo error de
# instrumento (se niega a evaluar sin foto del estado).
caso_g9_estado_ilegible_permite_stop_error_preflight() {
  limpiar_saikit
  plantar_trail x
  lab_sembrar 123456 0 1 1 "implementer,verifier,reviewer"
  chmod 000 "$LAB_ESTADO_PATH"
  lab_run stop claude "$(lab_payload_stop "$(_pf_base)")"
  _pf_ei_stop_rc="$LAB_RC"; _pf_ei_stop_out="$LAB_OUT"
  _igual "estado ilegible: el Stop permite (fail-open)" "$_pf_ei_stop_rc" "0"
  case "$_pf_ei_stop_out" in
    *'"decision":"block"'*|*'"continue":false'*|*'"followup_message"'*) _mal "estado ilegible: el Stop no debio bloquear" ;;
  esac
  chmod 644 "$LAB_ESTADO_PATH"
  lab_sembrar 123456 0 1 1 "implementer,verifier,reviewer"
  chmod 000 "$LAB_ESTADO_PATH"
  lab_run preflight claude "$(lab_payload_stop "$(_pf_base)")"
  chmod 644 "$LAB_ESTADO_PATH"
  _igual "estado ilegible exit" "$LAB_RC" "2"
  _contiene "estado ilegible error" "$LAB_ERR" 'SAIKIT PREFLIGHT (21.5): ERROR'
}

# A6: la unica comparacion FAIL que queda (via adversary), en claude y en
# cursor — mantiene viva la cobertura FAIL del preflight y su causa comun.
caso_g9_adversary_bloquea_en_ambos() {
  limpiar_saikit
  plantar_trail x
  _pf_compara "violacion adversary" 1 "$(_pf_base)" "adversary subagent wrote outside" "claude" "adv"
  _pf_compara "violacion adversary (cursor)" 1 "$(_pf_base)" "adversary subagent wrote outside" "cursor" "adv"
}

CASOS_G9="caso_g9_recibo_valido_cierra_en_ambos caso_g9_etiqueta_ausente_cierra_en_ambos caso_g9_etiqueta_malformada_cierra_en_ambos caso_g9_evidencia_invalida_cierra_en_ambos caso_g9_trail_inexistente_cierra_en_ambos caso_g9_raiz_sin_sha_cierra_en_ambos caso_g9_raiz_acreditada_cierra_en_ambos caso_g9_skip_con_razon_cierra_en_ambos caso_g9_dinamicos_nombrados_no_pass caso_g9_sin_efectos caso_g9_sin_gramatica_paralela caso_g9_divergencia_queda_roja caso_g9_cursor_recibo_valido_cierra_en_ambos caso_g9_cursor_etiqueta_ausente_cierra_en_ambos caso_g9_estado_ilegible_permite_stop_error_preflight caso_g9_adversary_bloquea_en_ambos"
