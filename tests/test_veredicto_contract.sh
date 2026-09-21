#!/usr/bin/env bash
# tests/test_veredicto_contract.sh — Task 18.3 + Bloque A.
#
# QUE AFIRMA:
#   - PARSER: el parser JSON compartido (tools/lib/veredicto_contract.sh)
#     rechaza JSON malformado, claves con punto, duplicadas, con escapes y
#     controles crudos; lo legitimo con escapes sigue pasando. El esquema
#     sellado quedo retirado (Bloque A: la entrega se valida con el recibo
#     del PR, tests/test_entrega_contract.sh).
#   - IGNORADO (A7 retiro el sello): el `Write` sobre `.saikit/veredictos/`
#     ya NO registra `veredicto_sha256`, no hay vinculos linked_* y los
#     restos viejos (JSON de sellos, lineas de estado) se ignoran sin
#     borrarse: la entrega valida el recibo del PR.
#
# La mitad mutation-test vive al final: romper la exclusion noncode o la guia
# tiene que poner rojo a algun caso — la acreditacion que pide la DoD.
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
. "$here/lib/hook_lab.sh"
. "$repo/tools/lib/veredicto_contract.sh"

if [ ! -r "$here/lib/hook_bajo_prueba.sh" ]; then
  echo "test_veredicto_contract: unknown — falta tests/lib/hook_bajo_prueba.sh; no se pudo resolver que archivo probar." >&2
  exit 3
fi
. "$here/lib/hook_bajo_prueba.sh"
vivo="$(resolver_hook_bajo_prueba "$here/.." "test_veredicto_contract")" \
  || exit "$SAIKIT_EXIT_UNKNOWN"

fail=0
CASO_ROJO=0
_mal()      { printf '      FAIL: %s\n' "$1"; CASO_ROJO=1; }
_igual()    { if [ "$2" != "$3" ]; then _mal "$1: esperaba [$3], dio [$2]"; fi; }
_no_igual() { if [ "$2" = "$3" ]; then _mal "$1: NO deberia ser igual a [$3]"; fi; }
_vacio()    { if [ -n "$2" ]; then _mal "$1: esperaba vacio, dio [$(printf '%s' "$2" | head -c 200)]"; fi; }
_no_vacio() { if [ -z "$2" ]; then _mal "$1: esperaba algo, quedo vacio"; fi; }
_contiene() { if ! printf '%s' "$2" | grep -Fq "$3"; then _mal "$1: no contiene [$3]"; fi; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/saikit-verdict-XXXXXX")" || exit 1
if ! lab_init "$vivo"; then
  echo "test_veredicto_contract: FAIL — no se pudo montar el banco de pruebas" >&2
  rm -rf "$tmp"
  exit 1
fi
trap 'lab_fin; rm -rf "$tmp"' EXIT

verdict_reset() {
  lab_limpiar_estado
  rm -rf "$LAB/proyecto" 2>/dev/null || true
  mkdir -p "$LAB/proyecto" || true
}

caso() { printf '  caso: %s\n' "$1"; CASO_ROJO=0; verdict_reset; }
fin_caso() {
  if [ "$CASO_ROJO" -ne 0 ]; then
    printf '    ROJO: %s\n' "$1" >&2
    fail=1
  else
    printf '    ok: %s\n' "$1"
  fi
}

# HEAD real del repo (para el caso de contrato sha==HEAD). El veredicto se sella
# contra el HEAD del turno; el test usa el HEAD actual del repo bajo prueba.
HEAD_SHA="$(git -C "$repo" rev-parse HEAD 2>/dev/null || echo 'c56586f')"

# ------------------------------------------------------------------- fixtures
# Un Write atribuido a un rol sobre un file_path, con un CONTENIDO. El sello
# del hook hashea el contenido DECODIFICADO de tool_input.content (lo que el
# Write materializa), asi que el contenido del payload tiene que ser igual al
# que el caso escribe en el archivo (garantiza sha256(decodificado) ==
# sha256(archivo), que es lo que el merge de D18 compara).
verdict_esc() { printf '%s' "$1" | perl -0pe 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\r/\\r/g; s/\n/\\n/g'; }
verdict_payload_write() {  # $1=rol, $2=file_path, $3=contenido
  printf '{"session_id":"__SESSION_ID__","transcript_path":"__TRANSCRIPT__","cwd":"/proyecto","prompt_id":"vd000000-0000-4000-8000-000000000001","permission_mode":"auto","agent_id":"a00000001vdreview","agent_type":"%s","effort":{"level":"xhigh"},"hook_event_name":"PostToolUse","tool_name":"Write","tool_input":{"file_path":"%s","content":"%s"},"tool_response":{"filePath":"%s"},"tool_use_id":"toolu_01vd0e1f2a3b4c5d6e7f8091a","duration_ms":1200}' "$1" "$2" "$(verdict_esc "$3")" "$2"
}

verdict_armar() {
  lab_run prompt claude "$(lab_payload_prompt '-saikit sellar el veredicto')"
}

# ---------------------------------------------------- contrato / esquema (D16)





# ------------------------------------- Parser JSON estricto (endurecimiento 18.4)
# El esquema sellado quedo retirado (Bloque A): estos casos ahora ejercitan
# el parser compartido directamente (saikit_json_valido), que es lo que el
# contrato de entrega y los tools consumen. Cada caso es un JSON que un
# parser flojo dejaria pasar y el real tiene que rechazar; el ultimo es la
# regresion de que lo legitimo sigue pasando.
caso "parser_json_malformado_colado_pasa_por_grep"
{
  # EL caso del limite declarado: abre con {, cierra con }, trae TODAS las
  # claves como texto — pero no es JSON (sin : despues de "sha", valor sin
  # comillas, coma colgante). El grep por clave entrecomillada lo aceptaba.
  printf '{ "sha" "%s" , "verifier": PASS ,"verify_app":{"resultado":"PASS","comando":"npm test -- verify/"},"blast":{"nivel":4,"hecho":"h","comando":"npm test -- verify/"},"adversary":"n/a","reviewer":"clean","decisiones":"d",}\n' "$HEAD_SHA" > "$tmp/mal-colado.json"
  if saikit_json_valido "$(cat "$tmp/mal-colado.json")" >/dev/null 2>&1; then
    _mal "acepto un JSON malformado que trae los textos de clave (limite POC)"
  fi
}
fin_caso "parser_json_malformado_colado_pasa_por_grep"

caso "parser_json_malformado_sin_cerrar"
{
  printf '{"sha":"%s","verifier":"PASS"' "$HEAD_SHA" > "$tmp/mal-abierto.json"
  if saikit_json_valido "$(cat "$tmp/mal-abierto.json")" >/dev/null 2>&1; then
    _mal "acepto un JSON sin cerrar"
  fi
}
fin_caso "parser_json_malformado_sin_cerrar"

caso "parser_json_malformado_coma_colgante"
{
  printf '{"sha":"%s","verifier":"PASS",}' "$HEAD_SHA" > "$tmp/mal-coma.json"
  if saikit_json_valido "$(cat "$tmp/mal-coma.json")" >/dev/null 2>&1; then
    _mal "acepto un JSON con coma colgante"
  fi
}
fin_caso "parser_json_malformado_coma_colgante"

caso "parser_json_malformado_clave_sin_comillas"
{
  printf '{sha:"%s","verifier":"PASS"}' "$HEAD_SHA" > "$tmp/mal-clave.json"
  if saikit_json_valido "$(cat "$tmp/mal-clave.json")" >/dev/null 2>&1; then
    _mal "acepto una clave sin comillas"
  fi
}
fin_caso "parser_json_malformado_clave_sin_comillas"

caso "parser_json_malformado_basura_final"
{
  printf '{"sha":"%s"} xx' "$HEAD_SHA" > "$tmp/mal-cola.json"
  if saikit_json_valido "$(cat "$tmp/mal-cola.json")" >/dev/null 2>&1; then
    _mal "acepto basura tras el cierre del objeto"
  fi
}
fin_caso "parser_json_malformado_basura_final"

caso "parser_json_malformado_escape_invalido"
{
  printf '{"sha":"%s","nota":"un \\q no es un escape"}' "$HEAD_SHA" > "$tmp/mal-esc.json"
  if saikit_json_valido "$(cat "$tmp/mal-esc.json")" >/dev/null 2>&1; then
    _mal "acepto un escape invalido dentro de un string"
  fi
}
fin_caso "parser_json_malformado_escape_invalido"

caso "parser_json_malformado_numero_con_cero"
{
  # 04 no es un numero JSON valido (leading zero); un parser de numeros flojo
  # lo deja pasar. La hoja blast.nivel es la que importa en el merge.
  printf '{"sha":"%s","pr":1,"verifier":"PASS","verify_app":{"resultado":"PASS","comando":"npm test -- verify/"},"blast":{"nivel":04,"hecho":"h","comando":"npm test -- verify/"},"adversary":"n/a","reviewer":"clean","decisiones":"d"}' "$HEAD_SHA" > "$tmp/mal-cero.json"
  if saikit_json_valido "$(cat "$tmp/mal-cero.json")" >/dev/null 2>&1; then
    _mal "acepto un numero con cero inicial"
  fi
}
fin_caso "parser_json_malformado_numero_con_cero"

caso "parser_json_clave_con_punto_colisiona_invalida"
{
  # Hallazgo de codex (cross-review PR #142), MEDIDO: una clave de primer
  # nivel "verify_app.resultado" colisiona en el aplanado con la hoja anidada
  # y saikit_json_get devolvia la PRIMERA — un veredicto podia poner
  # "verify_app.resultado":"PASS" arriba y el FAIL real adentro. El parser
  # ahora rechaza claves con '.' o corchetes (el namespace del flat).
  if saikit_json_get '{"verify_app.resultado":"PASS","verify_app":{"resultado":"FAIL"}}' verify_app.resultado | grep -q PASS; then
    _mal "la clave con punto colisiona con la ruta anidada y gana"
  fi
  printf '{"sha":"%s","pr":1,"verify_app.resultado":"PASS","verifier":"PASS","verify_app":{"resultado":"FAIL","comando":"bash verify/"},"blast":{"nivel":4,"hecho":"h","comando":"bash verify/"},"adversary":"n/a","reviewer":"clean","decisiones":"d"}' "$HEAD_SHA" > "$tmp/mal-punto.json"
  if saikit_json_valido "$(cat "$tmp/mal-punto.json")" >/dev/null 2>&1; then
    _mal "acepto una clave que falsifica una ruta anidada"
  fi
}
fin_caso "parser_json_clave_con_punto_colisiona_invalida"

caso "parser_json_clave_duplicada_invalida"
{
  # Hallazgo de codex (cross-review PR #142): JSON con claves duplicadas es
  # ambiguo entre consumidores y el parser elegia la primera en silencio. En
  # un gate fail-closed se rechaza.
  printf '{"sha":"%s","pr":1,"verifier":"PASS","verifier":"FAIL","verify_app":{"resultado":"PASS","comando":"bash verify/"},"blast":{"nivel":4,"hecho":"h","comando":"bash verify/"},"adversary":"n/a","reviewer":"clean","decisiones":"d"}' "$HEAD_SHA" > "$tmp/mal-dup.json"
  if saikit_json_valido "$(cat "$tmp/mal-dup.json")" >/dev/null 2>&1; then
    _mal "acepto claves duplicadas"
  fi
}
fin_caso "parser_json_clave_duplicada_invalida"

caso "parser_json_clave_con_escape_burla_las_guardas_invalida"
{
  # Hallazgo de CodeRabbit en el PR #142, adjudicado FIX y CONFIRMADO midiendo.
  # `parseString` NO decodifica escapes, asi que las dos guardas de la clave se
  # burlaban con \uXXXX: "a" no colisiona con "a" en `seen` (duplicada que
  # pasa) y "." no contiene un '.' literal (delimitador del flat que pasa).
  # La cabecera del archivo AFIRMABA rechazar ambas cosas, asi que la afirmacion
  # era falsa para la forma escapada.
  #
  # Postura elegida, fail-closed y coherente con el limite ya declarado (los
  # \uXXXX se validan pero NO se decodifican): una clave con CUALQUIER escape no
  # se interpreta, se RECHAZA. Las claves del esquema son ASCII planas.
  for j in \
    '{"a":1,"\u0061":2}' \
    '{"\u002e":1}' \
    '{"a\u002eb":1}' \
    '{"\u005b0\u005d":1}' \
  ; do
    if saikit_json_valido "$j" >/dev/null 2>&1; then
      _mal "acepto una clave con escape que burla las guardas: $j"
    fi
  done
  # Control: el mismo escape en un VALOR sigue siendo valido (solo la CLAVE se
  # restringe; si no, este caso pasaria por prohibir \u en todos lados).
  if ! saikit_json_valido '{"a":"\u0061 y \u002e"}' >/dev/null 2>&1; then
    _mal "rechazo un escape en un VALOR, que si es legitimo"
  fi
}
fin_caso "parser_json_clave_con_escape_burla_las_guardas_invalida"

caso "parser_json_control_crudo_en_string_invalido"
{
  # Hallazgo de codex: RFC 8259 prohibe TODOS los U+0000-U+001F crudos en
  # strings; el parser solo rechazaba LF/CR/TAB y aceptaba p.ej. 0x01. El
  # JSON es por lo demas valido: lo UNICO en juego es el control crudo.
  printf '{"sha":"%s","pr":1,"verifier":"PASS","verify_app":{"resultado":"PASS","comando":"bash verify/"},"blast":{"nivel":4,"hecho":"h","comando":"bash verify/"},"adversary":"n/a","reviewer":"clean","decisiones":"d","nota":"ctrl:' "$HEAD_SHA" > "$tmp/mal-ctrl.json"
  printf '\001aqui"}' >> "$tmp/mal-ctrl.json"
  if saikit_json_valido "$(cat "$tmp/mal-ctrl.json")" >/dev/null 2>&1; then
    _mal "acepto un control crudo (0x01) dentro de un string"
  fi
}
fin_caso "parser_json_control_crudo_en_string_invalido"

caso "parser_json_valido_con_escapes_sigue_valido"
{
  # El endurecimiento no puede romper lo legitimo: strings con escapes
  # comunes y el fixture base siguen validos (regresion del parser).
  printf '{"sha":"%s","pr":1,"verifier":"PASS","verify_app":{"resultado":"PASS","comando":"npm test -- verify/ \\"con comillas\\""},"blast":{"nivel":4,"hecho":"linea1\\nlinea2","comando":"npm test -- verify/"},"adversary":"n/a","reviewer":"clean","decisiones":"d"}' "$HEAD_SHA" > "$tmp/ok-esc.json"
  if ! saikit_json_valido "$(cat "$tmp/ok-esc.json")" >/dev/null 2>&1; then
    _mal "rechazo un JSON valido con escapes"
  fi
}
fin_caso "parser_json_valido_con_escapes_sigue_valido"



# --------------------------------------------------------- gate: sello retirado
# A7: el Write del reviewer ya NO registra veredicto_sha256 ni crea
# gitignore — los restos viejos se ignoran y la entrega valida el recibo.
verdict_reviewer_write_no_registra_hash() {
  mkdir -p "$LAB/proyecto/.saikit/veredictos"
  vsha="abc123abc123abc123"
  V="{\"sha\":\"$vsha\",\"pr\":1,\"verifier\":\"PASS\",\"verify_app\":{\"resultado\":\"PASS\",\"comando\":\"npm test -- verify/\"},\"blast\":{\"nivel\":4,\"hecho\":\"h\",\"comando\":\"npm test -- verify/\"},\"adversary\":\"n/a\",\"reviewer\":\"clean\",\"decisiones\":\"d\"}"
  printf '%s' "$V" > "$LAB/proyecto/.saikit/veredictos/$vsha.json"
  verdict_armar
  lab_run tool claude "$(verdict_payload_write reviewer ".saikit/veredictos/$vsha.json" "$V")"
  _vacio "hash NO registrado (A7: sin sello)" "$(lab_estado veredicto_sha256)"
  _vacio "sin gitignore del sello" "$(cat "$LAB/proyecto/.saikit/veredictos/.gitignore" 2>/dev/null)"
}
caso "verdict_reviewer_write_no_registra_hash"
verdict_reviewer_write_no_registra_hash
fin_caso "verdict_reviewer_write_no_registra_hash"


verdict_otro_rol_no_registra_hash() {
  mkdir -p "$LAB/proyecto/.saikit/veredictos"
  vsha="def456def456def456"
  V="{\"sha\":\"$vsha\",\"verifier\":\"PASS\"}"
  printf '%s' "$V" > "$LAB/proyecto/.saikit/veredictos/$vsha.json"
  verdict_armar
  lab_run tool claude "$(verdict_payload_write implementer ".saikit/veredictos/$vsha.json" "$V")"
  _vacio "hash NO registrado para otro rol" "$(lab_estado veredicto_sha256)"
  # El Edit tampoco sella (el sello es solo del Write del reviewer, D16).
  lab_run tool claude "$(lab_payload_edit ".saikit/veredictos/$vsha.json")"
  _vacio "hash NO registrado para un Edit" "$(lab_estado veredicto_sha256)"
}
caso "verdict_otro_rol_no_registra_hash"
verdict_otro_rol_no_registra_hash
fin_caso "verdict_otro_rol_no_registra_hash"



# H1 (lead r1): una ruta absoluta FUERA de veredictos/ NO sella (atrapa un fix que matchee de mas).
verdict_ruta_absoluta_fuera_no_sella() {
  mkdir -p "$LAB/proyecto/.saikit/findings"
  vsha="stu901stu901stu901"
  V="{\"sha\":\"$vsha\",\"verifier\":\"PASS\"}"
  printf '%s' "$V" > "$LAB/proyecto/.saikit/findings/$vsha.json"
  if command -v cygpath >/dev/null 2>&1; then
    fp="$(cygpath -w "$LAB/proyecto")\.saikit\findings\\$vsha.json"
    fp="$(printf '%s' "$fp" | sed 's/\\/\\\\/g')"   # escapa los backslashes para el JSON
  else
    fp="$LAB/proyecto/.saikit/findings/$vsha.json"
  fi
  verdict_armar
  lab_run tool claude "$(verdict_payload_write reviewer "$fp" "$V")"
  _vacio "hash NO registrado para ruta fuera de veredictos/" "$(lab_estado veredicto_sha256)"
}
caso "verdict_ruta_absoluta_fuera_no_sella"
verdict_ruta_absoluta_fuera_no_sella
fin_caso "verdict_ruta_absoluta_fuera_no_sella"



# ---------------------- Task 18.13 (c), invertida por A7: sin sellos, un
# Write es trabajo venga del rol que venga (implemented=1 como cualquier
# edicion); pero NO es codigo (veredictos/ sigue excluido de last_code_edit
# por rn_is_noncode_path). Las DOS senales van en casos separados porque
# nacen de caminos distintos: `implemented` del grep laxo del PostToolUse,
# `last_code_edit` de rn_mark_code_edit.
verdict_payload_revision() {  # $1=vsha — contenido minimo de veredicto valido
  printf '{"sha":"%s","pr":1,"verifier":"PASS","verify_app":{"resultado":"n/a","comando":null},"blast":{"nivel":4,"hecho":"h","comando":"c"},"adversary":"n/a","reviewer":"clean","decisiones":".saikit/decisiones/t.tsv"}' "$1"
}

verdict_write_acredita_implemented() {
  mkdir -p "$LAB/proyecto/.saikit/veredictos"
  vsha="notrab01notrab01"
  V="$(verdict_payload_revision "$vsha")"
  printf '%s' "$V" > "$LAB/proyecto/.saikit/veredictos/$vsha.json"
  verdict_armar
  lab_run tool claude "$(verdict_payload_write reviewer ".saikit/veredictos/$vsha.json" "$V")"
  _igual "implemented queda en 1 (A7: el Write es trabajo)" "$(lab_estado implemented)" "1"
  _no_vacio "el log acredita implemented con el Write" "$(lab_log | grep '^implemented:')"
}
caso "verdict_write_acredita_implemented"
verdict_write_acredita_implemented
fin_caso "verdict_write_acredita_implemented"

verdict_write_no_marca_code_edit() {
  mkdir -p "$LAB/proyecto/.saikit/veredictos"
  vsha="notrab02notrab02"
  V="$(verdict_payload_revision "$vsha")"
  printf '%s' "$V" > "$LAB/proyecto/.saikit/veredictos/$vsha.json"
  verdict_armar
  lab_run tool claude "$(verdict_payload_write reviewer ".saikit/veredictos/$vsha.json" "$V")"
  rn_file="$(dirname "$LAB_ESTADO_PATH")/harness-state-review-notice.env"
  _no_vacio "el evento del reviewer SI deja last_review" "$(grep '^last_review=.' "$rn_file" 2>/dev/null)"
  _vacio "el Write del veredicto NO marca last_code_edit" "$(grep '^last_code_edit=.' "$rn_file" 2>/dev/null)"
}
caso "verdict_write_no_marca_code_edit"
verdict_write_no_marca_code_edit
fin_caso "verdict_write_no_marca_code_edit"

# El detalle que la fila 18.13 pide DECLARAR y atar: un turno de solo
# revision NO dispara la falsa alarma de "codigo tocado despues del review"
# (el Write del veredicto no marca last_code_edit). A6/A7: el cierre es
# limpio y sin sello.
verdict_turno_solo_revision_sin_falso_aviso() {
  mkdir -p "$LAB/proyecto/.saikit/veredictos"
  vsha="notrab03notrab03"
  V="$(verdict_payload_revision "$vsha")"
  printf '%s' "$V" > "$LAB/proyecto/.saikit/veredictos/$vsha.json"
  verdict_armar
  lab_run tool claude "$(verdict_payload_write reviewer ".saikit/veredictos/$vsha.json" "$V")"
  lab_run stop claude "$(lab_payload_stop 'Revision terminada: sin hallazgos.')"
  _igual "el Stop cierra limpio" "$LAB_RC" "0"
  _vacio "sin aviso pendiente de review-notice para el turno siguiente" "$(find "$LAB/hooks/state" -name 'review-notice-pending.log' 2>/dev/null)"
}
caso "verdict_turno_solo_revision_sin_falso_aviso"
verdict_turno_solo_revision_sin_falso_aviso
fin_caso "verdict_turno_solo_revision_sin_falso_aviso"

# ---------------------- Task 18.26, invertida por A7: sin sello unarmed
# Forma medida en docs/evidence/18.26-grok-reviewer-write/write.post_tool_use.json:
# hookEventName=post_tool_use, toolName=write, toolInput.file_path+content,
# subagentType top-level. Sin agent_type. Sesion sin -saikit (sin STATE_PATH):
# el Write pasa sin crear estado ni registrar nada.
verdict_payload_grok_write() {
  _vd_role_json=""
  if [ -n "$1" ]; then
    _vd_role_json="$(printf ',"subagentType":"%s"' "$1")"
  fi
  printf '{"sessionId":"__SESSION_ID__","transcriptPath":"__TRANSCRIPT__","cwd":"/proyecto","workspaceRoot":"/proyecto","permissionMode":"auto","hookEventName":"post_tool_use","toolName":"write","toolInput":{"file_path":"%s","content":"%s"},"toolResult":{"type":"SearchReplace"},"isBackgrounded":false%s}' "$2" "$(verdict_esc "$3")" "$_vd_role_json"
}

verdict_unarmed_grok_reviewer_write_no_sella() {
  mkdir -p "$LAB/proyecto/.saikit/veredictos"
  vsha="deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
  V="{\"sha\":\"$vsha\",\"pr\":0,\"verifier\":\"PASS\",\"verify_app\":{\"resultado\":\"n/a\",\"comando\":null},\"blast\":{\"omitido\":\"medicion 18.26\"},\"adversary\":\"n/a\",\"reviewer\":\"clean\",\"decisiones\":\"n/a\"}"
  printf '%s' "$V" > "$LAB/proyecto/.saikit/veredictos/$vsha.json"
  _vacio "sesion sin armar (sin STATE_PATH)" "$(lab_estado task_hash)"
  lab_run tool claude "$(verdict_payload_grok_write reviewer ".saikit/veredictos/$vsha.json" "$V")"
  _igual "Write unarmed permite" "$LAB_RC" "0"
  _vacio "sin sello unarmed (A7)" "$(lab_estado veredicto_sha256)"
  if lab_hay_estado; then
    _mal "write unarmed no debe crear estado"
  fi
}

caso "verdict_unarmed_grok_reviewer_write_no_sella"
verdict_unarmed_grok_reviewer_write_no_sella
fin_caso "verdict_unarmed_grok_reviewer_write_no_sella"

verdict_unarmed_write_sin_rol_no_sella() {
  mkdir -p "$LAB/proyecto/.saikit/veredictos"
  vsha="reviewer-only-from-path"
  V="{\"sha\":\"$vsha\",\"reviewer\":\"clean\"}"
  printf '%s' "$V" > "$LAB/proyecto/.saikit/veredictos/$vsha.json"
  lab_run tool claude "$(verdict_payload_grok_write "" ".saikit/veredictos/$vsha.json" "$V")"
  _vacio "sin rol medido no hay sello" "$(lab_estado veredicto_sha256)"
  if lab_hay_estado; then
    _mal "write sin atribucion no debe crear estado"
  fi
}

caso "verdict_unarmed_write_sin_rol_no_sella"
verdict_unarmed_write_sin_rol_no_sella
fin_caso "verdict_unarmed_write_sin_rol_no_sella"

verdict_unarmed_implementer_no_sella() {
  mkdir -p "$LAB/proyecto/.saikit/veredictos"
  vsha="impl000impl000impl000"
  V="{\"sha\":\"$vsha\",\"reviewer\":\"clean\"}"
  printf '%s' "$V" > "$LAB/proyecto/.saikit/veredictos/$vsha.json"
  lab_run tool claude "$(verdict_payload_grok_write implementer ".saikit/veredictos/$vsha.json" "$V")"
  _vacio "implementer unarmed no sella" "$(lab_estado veredicto_sha256)"
}

caso "verdict_unarmed_implementer_no_sella"
verdict_unarmed_implementer_no_sella
fin_caso "verdict_unarmed_implementer_no_sella"

# Unarmed: role from toolInput is agent-controlled, not a measured host channel.
verdict_payload_grok_write_rol_en_toolinput() {
  printf '{"sessionId":"__SESSION_ID__","transcriptPath":"__TRANSCRIPT__","cwd":"/proyecto","workspaceRoot":"/proyecto","permissionMode":"auto","hookEventName":"post_tool_use","toolName":"write","toolInput":{"file_path":"%s","content":"%s","subagent_type":"reviewer"},"toolResult":{"type":"SearchReplace"},"isBackgrounded":false}' "$1" "$(verdict_esc "$2")"
}

verdict_unarmed_rol_en_toolinput_no_sella() {
  mkdir -p "$LAB/proyecto/.saikit/veredictos"
  vsha="toolinput-role-only"
  V="{\"sha\":\"$vsha\",\"reviewer\":\"clean\"}"
  printf '%s' "$V" > "$LAB/proyecto/.saikit/veredictos/$vsha.json"
  lab_run tool claude "$(verdict_payload_grok_write_rol_en_toolinput ".saikit/veredictos/$vsha.json" "$V")"
  _vacio "rol solo en toolInput no sella" "$(lab_estado veredicto_sha256)"
  if lab_hay_estado; then
    _mal "rol solo en toolInput no debe crear estado"
  fi
}

caso "verdict_unarmed_rol_en_toolinput_no_sella"
verdict_unarmed_rol_en_toolinput_no_sella
fin_caso "verdict_unarmed_rol_en_toolinput_no_sella"

# The measured payload identifies the reviewer, NOT its parent session.
# Reintroducing sibling selection (with or without verified:) must fail here.
verdict_unarmed_aislamiento() {
  LAB_GROK_HOOK_EVENT=post_tool_use
  LAB_SESSION_ID=unrelated-session-A
  mkdir -p "$LAB/proyecto/.saikit/veredictos"
  vsha="deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
  V="{\"sha\":\"$vsha\",\"pr\":0,\"verifier\":\"PASS\",\"verify_app\":{\"resultado\":\"n/a\",\"comando\":null},\"blast\":{\"omitido\":\"medicion 18.26\"},\"adversary\":\"n/a\",\"reviewer\":\"clean\",\"decisiones\":\"n/a\"}"
  printf '%s' "$V" > "$LAB/proyecto/.saikit/veredictos/$vsha.json"
  want="$(printf '%s' "$V" | sha256sum | cut -c1-64)"
  lab_run prompt grok "$(lab_payload_prompt '-saikit trabajo A independiente')"
  if [ "$1" = verified ]; then
    lab_run tool grok "$(lab_payload_bash 'npm test -- verify/')"
  fi
  ruta_A="$(find "$LAB/hooks/state/grok" -path '*/unrelated-session-A/harness-state.env')"
  if [ ! -f "$ruta_A" ]; then
    _mal "no se pudo observar la sesion Grok A"
    LAB_SESSION_ID=""; LAB_GROK_HOOK_EVENT=""
    return
  fi
  log_A="$(dirname "$ruta_A")/harness-evidence.log"
  cp "$ruta_A" "$tmp/state-A.before"
  cp "$log_A" "$tmp/log-A.before"
  if [ "$1" = verified ]; then
    _contiene "A tiene evidencia real del runner" "$(cat "$log_A")" "verified: "
  fi

  LAB_SESSION_ID=independent-reviewer-B
  lab_run tool grok "$(verdict_payload_grok_write reviewer ".saikit/veredictos/$vsha.json" "$V")"
  _igual "Write Grok permite" "$LAB_RC" "0"
  ruta_B="$(find "$LAB/hooks/state/grok" -path '*/independent-reviewer-B/harness-state.env')"
  if [ -f "$ruta_B" ]; then
    _mal "A7: B no debe crear estado (sin sello unarmed)"
  fi
  cmp -s "$ruta_A" "$tmp/state-A.before" || _mal "Write B altero estado de A sin vinculo padre-hijo"
  cmp -s "$log_A" "$tmp/log-A.before" || _mal "Write B acredito reviewer en log de A sin vinculo"
  lab_run stop grok "$(lab_payload_grok_stop 'Reviewer: clean.' end_turn)"
  _igual "Stop Grok permite" "$LAB_RC" "0"
  cmp -s "$ruta_A" "$tmp/state-A.before" || _mal "Stop B altero estado de A"
  cmp -s "$log_A" "$tmp/log-A.before" || _mal "Stop B altero log de A"
  LAB_SESSION_ID=""
  LAB_GROK_HOOK_EVENT=""
}

verdict_unarmed_no_toca_sesion_verificada() { verdict_unarmed_aislamiento verified; }
verdict_unarmed_no_toca_sesion_armada() { verdict_unarmed_aislamiento armed; }
caso "verdict_unarmed_no_toca_sesion_verificada"
verdict_unarmed_no_toca_sesion_verificada
fin_caso "verdict_unarmed_no_toca_sesion_verificada"
caso "verdict_unarmed_no_toca_sesion_armada"
verdict_unarmed_no_toca_sesion_armada
fin_caso "verdict_unarmed_no_toca_sesion_armada"

verdict_armed_implementer_no_sella() {
  mkdir -p "$LAB/proyecto/.saikit/veredictos"
  vsha="implarm0implarm0"
  V="{\"sha\":\"$vsha\",\"reviewer\":\"clean\"}"
  printf '%s' "$V" > "$LAB/proyecto/.saikit/veredictos/$vsha.json"
  verdict_armar
  lab_run tool claude "$(verdict_payload_grok_write implementer ".saikit/veredictos/$vsha.json" "$V")"
  _vacio "implementer armed no sella" "$(lab_estado veredicto_sha256)"
}

caso "verdict_armed_implementer_no_sella"
verdict_armed_implementer_no_sella
fin_caso "verdict_armed_implementer_no_sella"

# A7: restos viejos de sello (estado seal_boot + JSON en disco, de antes del
# Bloque A) se ignoran — el Stop cierra limpio, borra el estado como siempre
# y NO toca el archivo viejo.
verdict_unarmed_stop_prosa_limpia_estado_viejo() {
  LAB_SESSION_ID=sesion-con-restos-viejos
  mkdir -p "$LAB/proyecto/.saikit/veredictos"
  vsha="viejo000viejo000viejo000viejo000viejo000"
  V="{\"sha\":\"$vsha\",\"pr\":0,\"verifier\":\"PASS\",\"reviewer\":\"clean\"}"
  printf '%s' "$V" > "$LAB/proyecto/.saikit/veredictos/$vsha.json"
  h_antes="$(sha256sum "$LAB/proyecto/.saikit/veredictos/$vsha.json" | cut -c1-64)"
  LAB_GROK_HOOK_EVENT=user_prompt_submit
  lab_run prompt grok "$(lab_payload_prompt '-saikit trabajo con restos')"
  ruta_vieja="$(find "$LAB/hooks/state/grok" -path '*/sesion-con-restos-viejos/harness-state.env')"
  [ -f "$ruta_vieja" ] || { _mal "no se pudo armar la sesion"; LAB_SESSION_ID=""; LAB_GROK_HOOK_EVENT=""; return; }
  # Sobreescribe con forma vieja (la que dejaba el sello unarmed pre-A7).
  printf 'task_hash=unknown\ncycle=0\nimplemented=0\nverified=0\nagents_seen=reviewer\nlane=seal_boot\nveredicto_sha256=%s\n' \
    "$(printf '%s' "$V" | sha256sum | cut -c1-64)" > "$ruta_vieja"
  LAB_GROK_HOOK_EVENT=stop
  lab_run stop grok "$(lab_payload_grok_stop 'Reviewer: clean. El veredicto quedo de antes.' end_turn)"
  _igual "Stop con restos viejos cierra" "$LAB_RC" "0"
  if printf '%s' "$LAB_OUT" | grep -Fq '"decision":"block"'; then
    _mal "Stop con restos viejos exigio ceremonia"
  fi
  if [ -f "$ruta_vieja" ]; then
    _mal "el cierre limpio debe borrar el estado viejo"
  fi
  _igual "el JSON viejo queda intacto" "$(sha256sum "$LAB/proyecto/.saikit/veredictos/$vsha.json" | cut -c1-64)" "$h_antes"
  LAB_SESSION_ID=""; LAB_GROK_HOOK_EVENT=""
}

caso "verdict_unarmed_stop_prosa_limpia_estado_viejo"
verdict_unarmed_stop_prosa_limpia_estado_viejo
fin_caso "verdict_unarmed_stop_prosa_limpia_estado_viejo"



# ---------------------- 20.13, retirado por A7: sin vinculos linked_*
# Padre armado + SubagentStart + Write del hijo + spawn done: nada se
# anuncia, nada se sella y nada se consume — el recibo de entrega vive en
# el PR, no en el estado de sesion.
verdict_link_padre_no_anuncia_ni_consume() {
  LAB_GROK_HOOK_EVENT=post_tool_use
  mkdir -p "$LAB/proyecto/.saikit/veredictos"
  vsha="deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
  V="{\"sha\":\"$vsha\",\"pr\":0,\"verifier\":\"PASS\",\"verify_app\":{\"resultado\":\"n/a\",\"comando\":null},\"blast\":{\"omitido\":\"20.13\"},\"adversary\":\"n/a\",\"reviewer\":\"clean\",\"decisiones\":\"n/a\"}"
  printf '%s' "$V" > "$LAB/proyecto/.saikit/veredictos/$vsha.json"

  LAB_SESSION_ID=parent-A-2013
  lab_run prompt grok "$(lab_payload_prompt '-saikit trabajo padre A')"
  ruta_A="$(find "$LAB/hooks/state/grok" -path '*/parent-A-2013/harness-state.env')"
  [ -f "$ruta_A" ] || { _mal "falta estado padre A"; LAB_SESSION_ID=""; LAB_GROK_HOOK_EVENT=""; return; }
  lab_run tool grok "$(lab_payload_grok_subagent_start reviewer child-B-2013 'review A')"
  _vacio "padre NO anuncia hijo" "$(sed -n 's/^linked_children=//p' "$ruta_A")"

  LAB_SESSION_ID=child-B-2013
  lab_run tool grok "$(verdict_payload_grok_write reviewer ".saikit/veredictos/$vsha.json" "$V")"
  ruta_B="$(find "$LAB/hooks/state/grok" -path '*/child-B-2013/harness-state.env' 2>/dev/null)"
  _vacio "hijo NO crea estado (sin sello unarmed)" "$ruta_B"

  LAB_SESSION_ID=parent-A-2013
  lab_run tool grok "$(lab_payload_grok_spawn_done reviewer child-B-2013)"
  _vacio "padre sin sello tras spawn done" "$(sed -n 's/^veredicto_sha256=//p' "$ruta_A")"
  _vacio "padre sin linked_seal_session" "$(sed -n 's/^linked_seal_session=//p' "$ruta_A")"
  LAB_SESSION_ID=""; LAB_GROK_HOOK_EVENT=""
}
caso "verdict_link_padre_no_anuncia_ni_consume"
verdict_link_padre_no_anuncia_ni_consume
fin_caso "verdict_link_padre_no_anuncia_ni_consume"


# ---------------------- Task 18.13 (b): el lider commitea ANTES del reviewer
# agents/reviewer.md lo DA POR HECHO («el lider ya commiteo antes de
# despacharte, asi que git rev-parse HEAD es el sha del arbol que estas
# revisando») y NADIE instruye al lider a hacerlo (medido en la fila: 0
# menciones en recetas/00-lider.md). El sello cita el sha del HEAD al momento
# del review (docs/phase-18-autopilot-plan.md §4.1); sin commit previo, el
# veredicto apuntaria a un arbol que no incluye el trabajo del turno y el
# cruce del merge (D18) nunca cerraria.
contrato_lider_commitea_antes_de_despachar_al_reviewer() {
  verdict_armar
  _contiene "el contrato instruye commitear antes de despachar al reviewer" "$LAB_OUT" 'Commit BEFORE dispatching the reviewer'
  _contiene "el contrato nombra el rastro (.saikit/decisiones/)" "$LAB_OUT" '.saikit/decisiones/'
}
caso "contrato_lider_commitea_antes_de_despachar_al_reviewer"
contrato_lider_commitea_antes_de_despachar_al_reviewer
fin_caso "contrato_lider_commitea_antes_de_despachar_al_reviewer"

# ---------------------- Task 18.13 (a): Close cita el sha y la ruta del veredicto
# Alcance original de la 18.3, documentado en §4.1 del plan de la fase y nunca
# entregado: «Contrato: la linea Close: del recibo cita sha y ruta». Decision
# sobre los DOS bloques de recibo del hook (declarada en el PR): la instruccion
# va en el Close: SUSTANTIVO de harness_context («Final receipt required before
# stopping»); los shapes bare (el ejemplo «Bare, the six lines are» y el
# «Required receipt shape» de build_gate_feedback) quedan bare — el gate solo
# chequea label+colon, y el contrato sustantivo ya se inyecta en el armado.
contrato_close_cita_sha_y_ruta_del_veredicto_sellado() {
  verdict_armar
  _contiene "Close cita el sha y la ruta del veredicto sellado" "$LAB_OUT" 'cite the sha and path of the sealed verdict'
  _contiene "Close nombra la ruta donde vive el veredicto" "$LAB_OUT" '.saikit/veredictos/<sha>.json'
}
caso "contrato_close_cita_sha_y_ruta_del_veredicto_sellado"
contrato_close_cita_sha_y_ruta_del_veredicto_sellado
fin_caso "contrato_close_cita_sha_y_ruta_del_veredicto_sellado"

if [ "$fail" -ne 0 ]; then
  echo "test_veredicto_contract: FAIL (casos)" >&2
  exit 1
fi

# ------------------------------------------------------- mutation-test propio
# A7: se animan la exclusion noncode, la guia y la ausencia del sello, y se
# exige que un caso se ponga rojo. Guardias: la mutacion cambia el archivo,
# el mutado parsea, y algun caso la atrapa.
# Task 18.13 (c): quita la exclusion de .saikit/veredictos/ en
# rn_is_noncode_path (vuelve last_code_edit) — la atrapa
# verdict_write_no_marca_code_edit.
mut_veredicto_rn_noncode_sin_veredictos() { sed '/\.saikit\/veredictos\/\*|\.saikit\/veredictos\/\*) return 0 ;;/d'; }

# Task 18.13 (b): el contrato pierde la instruccion de commitear ANTES del
# reviewer — la atrapa contrato_lider_commitea_antes_de_despachar_al_reviewer.
mut_veredicto_lider_sin_commit_antes() { sed 's/Commit BEFORE dispatching the reviewer/Commit once the reviewer has already run/'; }
# Task 18.13 (a): el Close: pierde la clausula que cita el sha y la ruta del
# veredicto sellado — la atrapa contrato_close_cita_sha_y_ruta_del_veredicto_sellado.
mut_veredicto_close_sin_cita() { sed 's/; if a verdict was sealed this turn, cite the sha and path of the sealed verdict (\.saikit\/veredictos\/<sha>\.json)//'; }

# A7: reintroducir el sello (cada escritura de estado emite un hash falso) —
# la atrapa verdict_reviewer_write_no_registra_hash.
mut_veredicto_sello_reintroducido() { sed "s|then printf 'autopilot=%s\\\\n' \"\$autopilot\"; fi|&; printf 'veredicto_sha256=falso\\\\n'|"; }

MUTS_VERDICT="rn_noncode_sin_veredictos|verdict_write_no_marca_code_edit
lider_sin_commit_antes|contrato_lider_commitea_antes_de_despachar_al_reviewer
close_sin_cita|contrato_close_cita_sha_y_ruta_del_veredicto_sellado
sello_reintroducido|verdict_reviewer_write_no_registra_hash"

while IFS='|' read -r nombre caso_atrapa; do
  [ -n "$nombre" ] || continue
  mutado="$tmp/hook-$nombre.sh"
  "mut_veredicto_$nombre" < "$vivo" > "$mutado"
  if cmp -s "$vivo" "$mutado"; then
    printf '    FAIL: %s no cambio nada — el sed quedo obsoleto\n' "$nombre" >&2
    fail=1
    continue
  fi
  if ! bash -n "$mutado" 2>/dev/null; then
    printf '    FAIL: %s no parsea; asi no prueba nada\n' "$nombre" >&2
    fail=1
    continue
  fi
  lab_hook_swap "$mutado"
  CASO_ROJO=0
  verdict_reset
  "$caso_atrapa"
  if [ "$CASO_ROJO" -ne 0 ]; then
    printf '    mutacion %s atrapada por %s\n' "$nombre" "$caso_atrapa"
  else
    printf '    FAIL: ningun caso detecto la mutacion [%s]\n' "$nombre" >&2
    fail=1
  fi
  lab_hook_swap "$vivo"
done <<EOF
$MUTS_VERDICT
EOF


if [ "$fail" -ne 0 ]; then
  echo "test_veredicto_contract: FAIL" >&2
  exit 1
fi
echo "test_veredicto_contract: OK"
