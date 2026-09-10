#!/usr/bin/env bash
# tests/test_veredicto_contract.sh — Task 18.3: contrato del veredicto sellado.
#
# QUE AFIRMA (DoD de 18.3, docs/phase-18-autopilot-plan.md §4.1):
#   - CONTEXTO/ESQUEMA: el veredicto valido pasa; con `sha` != HEAD => invalido;
#     con un campo requerido faltante => invalido. La validacion es la de
#     `tools/lib/veredicto_contract.sh` (la reusara `tools/saikit-merge.sh`, D18).
#   - GATE (comportamiento del hook): el `Write` atribuido al reviewer sobre
#     `.saikit/veredictos/` registra `veredicto_sha256` en el estado; el `Write`
#     de OTRO rol NO lo registra; un `Edit` posterior deja el archivo con hash
#     distinto al registrado (el sello es del archivo escrito).
#
# La mitad mutation-test vive al final: romper el sello (`sello_veredicto_apagado`)
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
caso "contrato_valido_pasa"
{
  vsha="$(git -C "$repo" rev-parse HEAD 2>/dev/null || echo deadbeef)"
  printf '{"sha":"%s","pr":1,"verifier":"PASS","verify_app":{"resultado":"PASS","comando":"npm test -- verify/app.test.cjs"},"blast":{"nivel":4,"hecho":"el drive de la app corre","comando":"npm test -- verify/app.test.cjs"},"adversary":"n/a","reviewer":"clean","decisiones":".saikit/decisiones/18.3.tsv"}\n' "$vsha" > "$tmp/valido.json"
  if ! veredicto_validar "$tmp/valido.json" "$vsha" >/dev/null; then
    _mal "rechazo un veredicto con el esquema valido"
  fi
}
fin_caso "contrato_valido_pasa"

caso "contrato_sha_distinto_de_head_invalido"
{
  printf '{"sha":"no-es-el-head","pr":1,"verifier":"PASS","verify_app":{"resultado":"PASS","comando":"npm test -- verify/app.test.cjs"},"blast":{"nivel":4,"hecho":"h","comando":"npm test -- verify/app.test.cjs"},"adversary":"n/a","reviewer":"clean","decisiones":"d"}\n' > "$tmp/shamal.json"
  if veredicto_validar "$tmp/shamal.json" "$HEAD_SHA" >/dev/null; then
    _mal "acepto un veredicto con sha != HEAD"
  fi
  out="$(veredicto_validar "$tmp/shamal.json" "$HEAD_SHA")"
  _contiene "motivo del sha" "$out" "no coincide con HEAD"
}
fin_caso "contrato_sha_distinto_de_head_invalido"

caso "contrato_campo_faltante_invalido"
{
  printf '{"sha":"abc","pr":1,"verifier":"PASS","blast":{"nivel":4,"hecho":"h","comando":"c"},"adversary":"n/a","decisiones":"d"}\n' > "$tmp/falta.json"
  # falta verify_app, reviewer, comando, resultado, etc.
  if veredicto_validar "$tmp/falta.json" "$HEAD_SHA" >/dev/null; then
    _mal "acepto un veredicto con campos requeridos faltantes"
  fi
  out="$(veredicto_validar "$tmp/falta.json" "$HEAD_SHA")"
  _contiene "motivo del campo faltante" "$out" "falta el campo"
}
fin_caso "contrato_campo_faltante_invalido"

caso "contrato_sin_blast_o_adversary_invalido"
{
  # Regresion dedicada (regla de hierro): el reviewer (rol) encontro que el
  # validador aceptaba un veredicto sin las claves contenedor blast/adversary.
  # Un veredicto con TODAS las hojas pero SIN adversary (o SIN blast) debe ser
  # invalido — y este caso lo atrapa si la lista de requeridos pierde esas dos.
  # El sha va = HEAD (veredicto por lo demas valido): asi lo UNICO que lo
  # invalida es la ausencia del contenedor blast/adversary (r1 H3: con sha="abc"
  # la validacion lo rechazaba por sha antes de aislar el campo).
  printf '{"sha":"%s","pr":1,"verifier":"PASS","verify_app":{"resultado":"PASS","comando":"npm test -- verify/"},"blast":{"nivel":4,"hecho":"h","comando":"npm test -- verify/"},"reviewer":"clean","decisiones":"d"}\n' "$HEAD_SHA" > "$tmp/sin-adversary.json"
  if veredicto_validar "$tmp/sin-adversary.json" "$HEAD_SHA" >/dev/null; then
    _mal "acepto un veredicto SIN adversary"
  fi
  printf '{"sha":"%s","pr":1,"verifier":"PASS","verify_app":{"resultado":"PASS","comando":"npm test -- verify/"},"adversary":"n/a","reviewer":"clean","decisiones":"d","nivel":4,"hecho":"h","comando":"c"}\n' "$HEAD_SHA" > "$tmp/sin-blast.json"
  if veredicto_validar "$tmp/sin-blast.json" "$HEAD_SHA" >/dev/null; then
    _mal "acepto un veredicto SIN blast"
  fi
}
fin_caso "contrato_sin_blast_o_adversary_invalido"

caso "contrato_clave_solo_como_valor_invalido"
{
  # Hallazgo de CodeRabbit en el PR #140 («required-key text inside a string can
  # pass»), adjudicado DISMISS *verificado* — y este caso es lo que lo mantiene
  # cierto. Medido: en JSON VALIDO las comillas de adentro de un string van
  # escapadas (`\"decisiones\"`), asi que la subcadena `"decisiones"` NO aparece
  # y el grep por clave ENTRECOMILLADA ya rechaza el veredicto. El hallazgo no
  # aplica al codigo como esta.
  #
  # Se deja como REGRESION porque el poder discriminante esta medido: mutando el
  # bucle a palabras desnudas (`for campo in sha pr ...` sin comillas) este caso
  # se pone ROJO y NINGUN otro lo atrapa. Es lo que impide que una "simplificacion"
  # del grep vuelva cierto el hallazgo de CodeRabbit.
  #
  # Lo que SI queda abierto de ese hilo, y es de 18.4: un JSON malformado que
  # abra con `{`, cierre con `}` y traiga los textos de clave pasa igual, porque
  # esto no parsea. Declarado en la cabecera de tools/lib/veredicto_contract.sh.
  # El sha va = HEAD para que lo UNICO en juego sea la clave.
  printf '{"sha":"%s","pr":1,"verifier":"PASS","verify_app":{"resultado":"PASS","comando":"npm test -- verify/"},"blast":{"nivel":4,"hecho":"h","comando":"npm test -- verify/"},"adversary":"n/a","reviewer":"clean","nota":"a este veredicto le falta la clave \\"decisiones\\" y hay que agregarla"}\n' "$HEAD_SHA" > "$tmp/clave-en-valor.json"
  if veredicto_validar "$tmp/clave-en-valor.json" "$HEAD_SHA" >/dev/null; then
    _mal "acepto un veredicto donde \"decisiones\" aparece SOLO como texto de un valor, no como clave"
  fi
  out="$(veredicto_validar "$tmp/clave-en-valor.json" "$HEAD_SHA")"
  _contiene "motivo de la clave que solo era valor" "$out" "falta el campo"
}
fin_caso "contrato_clave_solo_como_valor_invalido"

# ------------------------------------- JSON malformado (endurecimiento 18.4)
# La cabecera de tools/lib/veredicto_contract.sh declaraba el limite POC: la
# validacion era por presencia de clave con grep, no un parser JSON. Un JSON
# malformado que abra con `{`, cierre con `}` y traiga los textos de clave
# pasaba igual. Ese endurecimiento es de la Task 18.4: validacion con un
# parser JSON real (awk, sin jq). Cada caso de esta seccion es un JSON que el
# grep-based aceptaba (o que un parser flojo dejaria pasar) y el parser real
# tiene que rechazar. El `sha` va = HEAD en todos: lo UNICO en juego es que
# sea JSON valido o no (r1 H3).
vjson_valido() {  # fixture base valido, con el sha que venga en $1
  printf '{"sha":"%s","pr":1,"verifier":"PASS","verify_app":{"resultado":"PASS","comando":"npm test -- verify/app.test.cjs"},"blast":{"nivel":4,"hecho":"h","comando":"npm test -- verify/app.test.cjs"},"adversary":"n/a","reviewer":"clean","decisiones":"d"}' "$1"
}

caso "contrato_json_malformado_colado_pasa_por_grep"
{
  # EL caso del limite declarado: abre con {, cierra con }, trae TODAS las
  # claves como texto — pero no es JSON (sin : despues de "sha", valor sin
  # comillas, coma colgante). El grep por clave entrecomillada lo aceptaba.
  printf '{ "sha" "%s" , "verifier": PASS ,"verify_app":{"resultado":"PASS","comando":"npm test -- verify/"},"blast":{"nivel":4,"hecho":"h","comando":"npm test -- verify/"},"adversary":"n/a","reviewer":"clean","decisiones":"d",}\n' "$HEAD_SHA" > "$tmp/mal-colado.json"
  if veredicto_validar "$tmp/mal-colado.json" "$HEAD_SHA" >/dev/null 2>&1; then
    _mal "acepto un JSON malformado que trae los textos de clave (limite POC)"
  fi
  out="$(veredicto_validar "$tmp/mal-colado.json" "$HEAD_SHA" 2>&1)"
  _contiene "motivo" "$out" "JSON"
}
fin_caso "contrato_json_malformado_colado_pasa_por_grep"

caso "contrato_json_malformado_sin_cerrar"
{
  printf '{"sha":"%s","verifier":"PASS"' "$HEAD_SHA" > "$tmp/mal-abierto.json"
  if veredicto_validar "$tmp/mal-abierto.json" "$HEAD_SHA" >/dev/null 2>&1; then
    _mal "acepto un JSON sin cerrar"
  fi
}
fin_caso "contrato_json_malformado_sin_cerrar"

caso "contrato_json_malformado_coma_colgante"
{
  printf '{"sha":"%s","verifier":"PASS",}' "$HEAD_SHA" > "$tmp/mal-coma.json"
  if veredicto_validar "$tmp/mal-coma.json" "$HEAD_SHA" >/dev/null 2>&1; then
    _mal "acepto un JSON con coma colgante"
  fi
}
fin_caso "contrato_json_malformado_coma_colgante"

caso "contrato_json_malformado_clave_sin_comillas"
{
  printf '{sha:"%s","verifier":"PASS"}' "$HEAD_SHA" > "$tmp/mal-clave.json"
  if veredicto_validar "$tmp/mal-clave.json" "$HEAD_SHA" >/dev/null 2>&1; then
    _mal "acepto una clave sin comillas"
  fi
}
fin_caso "contrato_json_malformado_clave_sin_comillas"

caso "contrato_json_malformado_basura_final"
{
  printf '{"sha":"%s"} xx' "$HEAD_SHA" > "$tmp/mal-cola.json"
  if veredicto_validar "$tmp/mal-cola.json" "$HEAD_SHA" >/dev/null 2>&1; then
    _mal "acepto basura tras el cierre del objeto"
  fi
}
fin_caso "contrato_json_malformado_basura_final"

caso "contrato_json_malformado_escape_invalido"
{
  printf '{"sha":"%s","nota":"un \\q no es un escape"}' "$HEAD_SHA" > "$tmp/mal-esc.json"
  if veredicto_validar "$tmp/mal-esc.json" "$HEAD_SHA" >/dev/null 2>&1; then
    _mal "acepto un escape invalido dentro de un string"
  fi
}
fin_caso "contrato_json_malformado_escape_invalido"

caso "contrato_json_malformado_numero_con_cero"
{
  # 04 no es un numero JSON valido (leading zero); un parser de numeros flojo
  # lo deja pasar. La hoja blast.nivel es la que importa en el merge.
  printf '{"sha":"%s","pr":1,"verifier":"PASS","verify_app":{"resultado":"PASS","comando":"npm test -- verify/"},"blast":{"nivel":04,"hecho":"h","comando":"npm test -- verify/"},"adversary":"n/a","reviewer":"clean","decisiones":"d"}' "$HEAD_SHA" > "$tmp/mal-cero.json"
  if veredicto_validar "$tmp/mal-cero.json" "$HEAD_SHA" >/dev/null 2>&1; then
    _mal "acepto un numero con cero inicial"
  fi
}
fin_caso "contrato_json_malformado_numero_con_cero"

caso "contrato_json_clave_con_punto_colisiona_invalida"
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
  if veredicto_validar "$tmp/mal-punto.json" "$HEAD_SHA" >/dev/null 2>&1; then
    _mal "acepto un veredicto con una clave que falsifica una ruta anidada"
  fi
}
fin_caso "contrato_json_clave_con_punto_colisiona_invalida"

caso "contrato_json_clave_duplicada_invalida"
{
  # Hallazgo de codex (cross-review PR #142): JSON con claves duplicadas es
  # ambiguo entre consumidores y el parser elegia la primera en silencio. En
  # un gate fail-closed se rechaza.
  printf '{"sha":"%s","pr":1,"verifier":"PASS","verifier":"FAIL","verify_app":{"resultado":"PASS","comando":"bash verify/"},"blast":{"nivel":4,"hecho":"h","comando":"bash verify/"},"adversary":"n/a","reviewer":"clean","decisiones":"d"}' "$HEAD_SHA" > "$tmp/mal-dup.json"
  if veredicto_validar "$tmp/mal-dup.json" "$HEAD_SHA" >/dev/null 2>&1; then
    _mal "acepto un veredicto con claves duplicadas"
  fi
}
fin_caso "contrato_json_clave_duplicada_invalida"

caso "contrato_json_clave_con_escape_burla_las_guardas_invalida"
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
fin_caso "contrato_json_clave_con_escape_burla_las_guardas_invalida"

caso "contrato_json_control_crudo_en_string_invalido"
{
  # Hallazgo de codex: RFC 8259 prohibe TODOS los U+0000-U+001F crudos en
  # strings; el parser solo rechazaba LF/CR/TAB y aceptaba p.ej. 0x01. El
  # veredicto es por lo demas valido: lo UNICO en juego es el control crudo.
  printf '{"sha":"%s","pr":1,"verifier":"PASS","verify_app":{"resultado":"PASS","comando":"bash verify/"},"blast":{"nivel":4,"hecho":"h","comando":"bash verify/"},"adversary":"n/a","reviewer":"clean","decisiones":"d","nota":"ctrl:' "$HEAD_SHA" > "$tmp/mal-ctrl.json"
  printf '\001aqui"}' >> "$tmp/mal-ctrl.json"
  if veredicto_validar "$tmp/mal-ctrl.json" "$HEAD_SHA" >/dev/null 2>&1; then
    _mal "acepto un control crudo (0x01) dentro de un string"
  fi
}
fin_caso "contrato_json_control_crudo_en_string_invalido"

caso "contrato_json_valido_con_escapes_sigue_valido"
{
  # El endurecimiento no puede romper lo legitimo: strings con escapes
  # comunes y el fixture base siguen validos (regresion del parser).
  printf '{"sha":"%s","pr":1,"verifier":"PASS","verify_app":{"resultado":"PASS","comando":"npm test -- verify/ \\"con comillas\\""},"blast":{"nivel":4,"hecho":"linea1\\nlinea2","comando":"npm test -- verify/"},"adversary":"n/a","reviewer":"clean","decisiones":"d"}' "$HEAD_SHA" > "$tmp/ok-esc.json"
  if ! veredicto_validar "$tmp/ok-esc.json" "$HEAD_SHA" >/dev/null 2>&1; then
    _mal "rechazo un JSON valido con escapes"
  fi
}
fin_caso "contrato_json_valido_con_escapes_sigue_valido"

# ---------------------------------- Task 18.17: blast omitido (la trampa D13)
# El PR #157 sello un veredicto real con `"blast": "n/a"` (escalar, por analogia
# con adversary). El perfil documentaba SOLO la triada, el validador exigia SOLO
# la triada, y un turno sin blast no tenia forma valida de decirlo. Diseno
# cerrado: blast es XOR de dos formas — la triada {nivel,hecho,comando} o
# {"omitido": "<razon no vacia>"}. El escalar "n/a" sigue INVALIDO: un blast
# que no corrio se declara con su razon, no con un placeholder.
vjson_blast() {  # fixture con el sha = HEAD y el blast que venga en $1 (JSON crudo)
  printf '{"sha":"%s","pr":1,"verifier":"PASS","verify_app":{"resultado":"PASS","comando":null},"blast":%s,"adversary":"n/a","reviewer":"clean","decisiones":"d"}' "$HEAD_SHA" "$1"
}

contrato_pr157_blast_na_invalido() {
  # El veredicto REAL del PR #157 (.saikit/veredictos/f5d06916….json), con el
  # sha = HEAD para que lo UNICO en juego sea el blast escalar.
  printf '{\n  "sha": "%s",\n  "pr": 157,\n  "verifier": "PASS",\n  "verify_app": { "resultado": "PASS", "comando": null },\n  "blast": "n/a",\n  "adversary": "n/a",\n  "reviewer": "findings",\n  "decisiones": ".saikit/decisiones/18.16.tsv"\n}\n' "$HEAD_SHA" > "$tmp/pr157.json"
  if veredicto_validar "$tmp/pr157.json" "$HEAD_SHA" >/dev/null; then
    _mal "acepto el veredicto del PR #157 con blast escalar \"n/a\""
  fi
  out="$(veredicto_validar "$tmp/pr157.json" "$HEAD_SHA")"
  _contiene "el motivo nombra el escalar" "$out" "escalar"
  _contiene "el motivo guia a la forma omitido" "$out" "omitido"
}
caso "contrato_pr157_blast_na_invalido"
contrato_pr157_blast_na_invalido
fin_caso "contrato_pr157_blast_na_invalido"

contrato_blast_con_hecho_sigue_valido() {
  vjson_blast '{"nivel":4,"hecho":"el drive de la app corre","comando":"npm test -- verify/app.test.cjs"}' > "$tmp/blast-triada.json"
  if ! veredicto_validar "$tmp/blast-triada.json" "$HEAD_SHA" >/dev/null; then
    _mal "rechazo la triada nivel/hecho/comando: $(veredicto_validar "$tmp/blast-triada.json" "$HEAD_SHA")"
  fi
}
caso "contrato_blast_con_hecho_sigue_valido"
contrato_blast_con_hecho_sigue_valido
fin_caso "contrato_blast_con_hecho_sigue_valido"

contrato_blast_omitido_con_razon_valido() {
  vjson_blast '{"omitido":"turno de solo revision: no hubo cambio de codigo que blastear"}' > "$tmp/blast-omitido.json"
  if ! veredicto_validar "$tmp/blast-omitido.json" "$HEAD_SHA" >/dev/null; then
    _mal "rechazo blast.omitido con razon: $(veredicto_validar "$tmp/blast-omitido.json" "$HEAD_SHA")"
  fi
}
caso "contrato_blast_omitido_con_razon_valido"
contrato_blast_omitido_con_razon_valido
fin_caso "contrato_blast_omitido_con_razon_valido"

contrato_blast_na_sin_razon_invalido() {
  # omitido sin razon real: vacio, espacios, null, placeholders, bool/numero,
  # plantilla, escape \\u (el parser no decodifica). Motivo debe nombrar razon.
  for b in \
    '{"omitido":""}' \
    '{"omitido":"   "}' \
    '{"omitido":null}' \
    '{"omitido":"n/a"}' \
    '{"omitido":" N/A "}' \
    '{"omitido":"0"}' \
    '{"omitido":0}' \
    '{"omitido":"-"}' \
    '{"omitido":"corta"}' \
    '{"omitido":true}' \
    '{"omitido":false}' \
    '{"omitido":"<por que no hubo blast>"}' \
    '{"omitido":"\\u0020\\u0020\\u0020\\u0020\\u0020\\u0020\\u0020\\u0020"}' \
  ; do
    vjson_blast "$b" > "$tmp/blast-sin-razon.json"
    if veredicto_validar "$tmp/blast-sin-razon.json" "$HEAD_SHA" >/dev/null; then
      _mal "acepto blast.omitido sin razon: $b"
    fi
    out="$(veredicto_validar "$tmp/blast-sin-razon.json" "$HEAD_SHA")"
    _contiene "el motivo pide la razon ($b)" "$out" "sin razon"
  done
}
caso "contrato_blast_na_sin_razon_invalido"
contrato_blast_na_sin_razon_invalido
fin_caso "contrato_blast_na_sin_razon_invalido"

contrato_blast_mezcla_omitido_y_hecho_invalido() {
  for b in \
    '{"omitido":"razon larga ok","nivel":4,"hecho":"h","comando":"c"}' \
    '{"omitido":"razon larga ok","hecho":"h"}' \
    '{"omitido":"razon larga ok","nivel":4}' \
    '{"omitido":"razon larga ok","comando":"c"}' \
    '{"omitido":"razon larga ok","nivel":{"x":1}}' \
    '{"omitido":"razon larga ok","nivel":[4]}' \
  ; do
    vjson_blast "$b" > "$tmp/blast-mezcla.json"
    if veredicto_validar "$tmp/blast-mezcla.json" "$HEAD_SHA" >/dev/null; then
      _mal "acepto una mezcla de omitido con la triada: $b"
    fi
    out="$(veredicto_validar "$tmp/blast-mezcla.json" "$HEAD_SHA")"
    _contiene "el motivo nombra la mezcla ($b)" "$out" "mezcla"
  done
  vjson_blast '{}' > "$tmp/blast-vacio.json"
  if veredicto_validar "$tmp/blast-vacio.json" "$HEAD_SHA" >/dev/null; then
    _mal "acepto un blast sin ninguna de las dos formas"
  fi
}
caso "contrato_blast_mezcla_omitido_y_hecho_invalido"
contrato_blast_mezcla_omitido_y_hecho_invalido
fin_caso "contrato_blast_mezcla_omitido_y_hecho_invalido"

# ------------------------------------------- productor: el PERFIL lo tiene que pedir
# Leccion pagada en 17.5 y anotada en la fila 18.12: un perfil puede DESCRIBIR un
# artefacto y no jalarlo nunca (0 invocaciones en 2 turnos vivos). El sello del
# hook no vale nada si NADIE escribe el veredicto, asi que el contrato del
# PRODUCTOR se ata acá, igual que el blast en test_blast_artifact_contract.sh.
# Cada grep de este caso estaba en CERO antes del fix: el perfil no nombraba el
# veredicto en ninguna forma.
REVIEWER_MD="$repo/agents/reviewer.md"

caso "productor_el_perfil_del_reviewer_pide_el_veredicto"
{
  [ -r "$REVIEWER_MD" ] || _mal "no se puede leer agents/reviewer.md"
  perfil="$(cat "$REVIEWER_MD" 2>/dev/null || printf '')"

  # (a) nombra el artefacto y de donde sale el sha.
  _contiene "el perfil nombra el directorio del veredicto" "$perfil" '.saikit/veredictos/'
  _contiene "el perfil dice de donde sale el sha" "$perfil" 'git rev-parse HEAD'

  # (b) EXIGE la tool Write. El sello del hook dispara SOLO en un Write
  # (`grep -Eiq '^(write)$'` sobre tool_name): si el perfil deja que el
  # veredicto se escriba con Edit o con Bash, el archivo existe y el sello NO,
  # que es la falla silenciosa que este caso impide.
  # La frase completa, no el token suelto: `Write` ya aparece en el frontmatter
  # (`tools: Read, Edit, Write, ...`), asi que grepear 'Write' pasaria sin que el
  # perfil pida nada. Se exige la instruccion.
  _contiene "el perfil exige la tool Write" "$perfil" 'la tool `Write`'
  _contiene "el perfil advierte que Edit/Bash no sellan" "$perfil" 'no sella'

  # (c) el esquema completo (D16) — las claves contenedor y las hojas, las
  # mismas que veredicto_validar exige mas arriba.
  for campo in '"sha"' '"pr"' '"verifier"' '"verify_app"' '"blast"' '"adversary"' '"reviewer"' '"decisiones"' '"nivel"' '"hecho"' '"resultado"' '"comando"' '"omitido"'; do
    _contiene "el perfil documenta el campo $campo" "$perfil" "$campo"
  done

  # (d) una sola escritura: reescribir el archivo despues deja el hash del
  # estado viejo y el merge de 18.4 lo leeria como veredicto tocado.
  _contiene "el perfil prohibe reescribir el veredicto" "$perfil" 'una sola vez'
}
fin_caso "productor_el_perfil_del_reviewer_pide_el_veredicto"

caso "contrato_perfil_vs_validador_campos_blast"
{
  # Candado anti-deriva futura perfil↔validador (las hojas de blast del perfil
  # tienen que ser EXACTAMENTE VEREDICTO_BLAST_TRIADA + VEREDICTO_BLAST_OMITIDO).
  # El bug del PR #157 NO era divergencia entre capas: las tres coincidian en
  # exigir solo la triada. Ese hueco lo atrapa contrato_pr157_blast_na_invalido.
  _no_vacio "la lib expone VEREDICTO_HOJAS_REQUERIDAS" "${VEREDICTO_HOJAS_REQUERIDAS:-}"
  _no_vacio "la lib expone VEREDICTO_BLAST_TRIADA" "${VEREDICTO_BLAST_TRIADA:-}"
  _no_vacio "la lib expone VEREDICTO_BLAST_OMITIDO" "${VEREDICTO_BLAST_OMITIDO:-}"

  seccion="$(sed -n '/^## El veredicto sellado/,/^## Context Policy/p' "$REVIEWER_MD" 2>/dev/null || printf '')"
  _no_vacio "el perfil tiene la seccion del veredicto sellado" "$seccion"

  perfil_blast="$(printf '%s\n' "$seccion" | grep -o '"blast": *{[^}]*}' | sed 's/^"blast": *{//' | grep -o '"[a-z_]*":' | tr -d '":' | sort -u | tr '\n' ' ')"
  validador_blast="$(for h in ${VEREDICTO_BLAST_TRIADA:-} ${VEREDICTO_BLAST_OMITIDO:-}; do printf '%s\n' "${h#blast.}"; done | sort -u | tr '\n' ' ')"
  _igual "las hojas de blast del perfil son las del validador" "$perfil_blast" "$validador_blast"
  _contiene "el perfil documenta la forma omitido" "$perfil_blast" "omitido"
  _contiene "el perfil documenta la triada" "$perfil_blast" "hecho"
  _contiene "el perfil declara INVALIDO el escalar (D13)" "$seccion" '"blast": "n/a"'
  _contiene "el perfil declara que omitido no mergea" "$seccion" 'no mergea'

  for h in ${VEREDICTO_HOJAS_REQUERIDAS:-}; do
    _contiene "el perfil documenta la hoja requerida $h" "$seccion" "\"${h##*.}\""
  done

  # Las listas expuestas son las que el validador USA: un veredicto armado solo
  # con la triada expuesta pasa, y otro armado solo con la hoja omitido expuesta
  # pasa. Si la lib renombra una hoja sin tocar la lista, uno de los dos cae.
  triada_json="$(for h in ${VEREDICTO_BLAST_TRIADA:-}; do printf '"%s":"x",' "${h#blast.}"; done)"
  vjson_blast "{${triada_json%,}}" > "$tmp/acople-triada.json"
  if ! veredicto_validar "$tmp/acople-triada.json" "$HEAD_SHA" >/dev/null; then
    _mal "la triada que expone la lib no es la que el validador exige: $(veredicto_validar "$tmp/acople-triada.json" "$HEAD_SHA")"
  fi
  omitido_json="$(for h in ${VEREDICTO_BLAST_OMITIDO:-}; do printf '"%s":"razon real de omision",' "${h#blast.}"; done)"
  vjson_blast "{${omitido_json%,}}" > "$tmp/acople-omitido.json"
  if ! veredicto_validar "$tmp/acople-omitido.json" "$HEAD_SHA" >/dev/null; then
    _mal "la hoja omitido que expone la lib no es la que el validador acepta: $(veredicto_validar "$tmp/acople-omitido.json" "$HEAD_SHA")"
  fi
}
fin_caso "contrato_perfil_vs_validador_campos_blast"

# --------------------------------------------------------- gate: sello del hook
verdict_reviewer_write_registra_hash() {
  mkdir -p "$LAB/proyecto/.saikit/veredictos"
  vsha="abc123abc123abc123"
  V="{\"sha\":\"$vsha\",\"pr\":1,\"verifier\":\"PASS\",\"verify_app\":{\"resultado\":\"PASS\",\"comando\":\"npm test -- verify/\"},\"blast\":{\"nivel\":4,\"hecho\":\"h\",\"comando\":\"npm test -- verify/\"},\"adversary\":\"n/a\",\"reviewer\":\"clean\",\"decisiones\":\"d\"}"
  printf '%s' "$V" > "$LAB/proyecto/.saikit/veredictos/$vsha.json"
  verdict_armar
  lab_run tool claude "$(verdict_payload_write reviewer ".saikit/veredictos/$vsha.json" "$V")"
  _igual "hash registrado" "$(lab_estado veredicto_sha256)" "$(printf '%s' "$V" | sha256sum | cut -c1-64)"
  _contiene "gitignore creado" "$(cat "$LAB/proyecto/.saikit/veredictos/.gitignore" 2>/dev/null)" '*'
}
caso "verdict_reviewer_write_registra_hash"
verdict_reviewer_write_registra_hash
fin_caso "verdict_reviewer_write_registra_hash"

caso "verdict_repo_fresco_sin_saikit_sella_igual"
{
  # Hallazgo de codex (cross-review del PR #140), adjudicado con MEDICION: «en
  # un repo nuevo .saikit/veredictos/ no existe y el hook solo lo crea despues
  # del Write; el test los precrea y no cubre el primer uso real».
  #
  # Medido con la tool real sobre un arbol SIN `.saikit`: el `Write` crea los
  # directorios padre que faltan y deja el archivo con su contenido exacto. Asi
  # que el primer uso real NO falla. Este caso es esa medicion convertida en
  # regresion: `verdict_reset` deja `proyecto/` vacio, y aca se crean SOLO los
  # padres del archivo (lo que hace el Write), nunca el arbol de antemano.
  #
  # El hash se compara contra el sha256 del ARCHIVO EN DISCO, no contra el
  # contenido que el caso conoce: es la comparacion exacta que hara el merge de
  # 18.4 (estado vs archivo actual).
  [ -e "$LAB/proyecto/.saikit" ] && _mal "el caso arranca con .saikit ya existente; no prueba un repo fresco"
  vsha="fresco00fresco00"
  Vf="{\"sha\":\"$vsha\",\"pr\":1,\"verifier\":\"PASS\",\"verify_app\":{\"resultado\":\"PASS\",\"comando\":\"npm test -- verify/\"},\"blast\":{\"nivel\":4,\"hecho\":\"h\",\"comando\":\"npm test -- verify/\"},\"adversary\":\"n/a\",\"reviewer\":\"clean\",\"decisiones\":\"d\"}"
  fpf="$LAB/proyecto/.saikit/veredictos/$vsha.json"
  mkdir -p "$(dirname "$fpf")"
  printf '%s' "$Vf" > "$fpf"
  verdict_armar
  lab_run tool claude "$(verdict_payload_write reviewer ".saikit/veredictos/$vsha.json" "$Vf")"
  _igual "hash en repo fresco (contra el ARCHIVO)" "$(lab_estado veredicto_sha256)" "$(sha256sum "$fpf" | cut -c1-64)"
  _contiene "gitignore creado en repo fresco" "$(cat "$LAB/proyecto/.saikit/veredictos/.gitignore" 2>/dev/null)" '*'
}
fin_caso "verdict_repo_fresco_sin_saikit_sella_igual"

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

verdict_edit_posterior_deja_hash_distinto() {
  mkdir -p "$LAB/proyecto/.saikit/veredictos"
  vsha="ghi789ghi789ghi789"
  V="{\"sha\":\"$vsha\",\"verifier\":\"PASS\",\"reviewer\":\"clean\"}"
  printf '%s' "$V" > "$LAB/proyecto/.saikit/veredictos/$vsha.json"
  verdict_armar
  lab_run tool claude "$(verdict_payload_write reviewer ".saikit/veredictos/$vsha.json" "$V")"
  h1="$(lab_estado veredicto_sha256)"
  _no_vacio "hash registrado" "$h1"
  # Un Edit posterior (observado como tool) NO re-sella (el sello es solo del
  # Write del reviewer, D16): el hash registrado queda igual.
  lab_run tool claude "$(lab_payload_edit ".saikit/veredictos/$vsha.json")"
  _igual "el Edit no re-sella (hash registrado intacto)" "$(lab_estado veredicto_sha256)" "$h1"
  # Y una edicion REAL del archivo (contenido distinto) deja el hash del archivo
  # distinto al registrado (el sello detecta la manipulacion).
  V2="{\"sha\":\"$vsha\",\"verifier\":\"PASS\",\"reviewer\":\"clean\",\"tampered\":true}"
  printf '%s' "$V2" > "$LAB/proyecto/.saikit/veredictos/$vsha.json"
  h2="$(printf '%s' "$V2" | sha256sum | cut -c1-64)"
  _no_igual "hash del archivo tras el Edit" "$h2" "$h1"
}
caso "verdict_edit_posterior_deja_hash_distinto"
verdict_edit_posterior_deja_hash_distinto
fin_caso "verdict_edit_posterior_deja_hash_distinto"

# H1 (lead r1): la ruta ABSOLUTA del Write sella (en Windows C:\...; la forma
# medida del Write de Claude Code). En Windows se arma con cygpath -w.
verdict_ruta_absoluta_sella() {
  mkdir -p "$LAB/proyecto/.saikit/veredictos"
  vsha="pqr678pqr678pqr678"
  V="{\"sha\":\"$vsha\",\"verifier\":\"PASS\",\"reviewer\":\"clean\"}"
  printf '%s' "$V" > "$LAB/proyecto/.saikit/veredictos/$vsha.json"
  if command -v cygpath >/dev/null 2>&1; then
    fp="$(cygpath -w "$LAB/proyecto")\.saikit\veredictos\\$vsha.json"
    fp="$(printf '%s' "$fp" | sed 's/\\/\\\\/g')"   # escapa los backslashes para el JSON
  else
    fp="$LAB/proyecto/.saikit/veredictos/$vsha.json"
  fi
  verdict_armar
  lab_run tool claude "$(verdict_payload_write reviewer "$fp" "$V")"
  _igual "hash con ruta absoluta" "$(lab_estado veredicto_sha256)" "$(printf '%s' "$V" | sha256sum | cut -c1-64)"
}
caso "verdict_ruta_absoluta_sella"
verdict_ruta_absoluta_sella
fin_caso "verdict_ruta_absoluta_sella"

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

# H2 (lead r1): el sello NO recorta el salto de linea final del contenido.
verdict_contenido_con_salto_final_coincide() {
  mkdir -p "$LAB/proyecto/.saikit/veredictos"
  vsha="vwx234vwx234vwx234"
  V=$'{\n\t"sha": "'$vsha'",\n\t"verifier": "PASS",\n\t"reviewer": "clean"\n}\n'
  printf '%s' "$V" > "$LAB/proyecto/.saikit/veredictos/$vsha.json"
  verdict_armar
  lab_run tool claude "$(verdict_payload_write reviewer ".saikit/veredictos/$vsha.json" "$V")"
  _igual "hash con salto final (contra el ARCHIVO)" "$(lab_estado veredicto_sha256)" "$(sha256sum "$LAB/proyecto/.saikit/veredictos/$vsha.json" | cut -c1-64)"
}
caso "verdict_contenido_con_salto_final_coincide"
verdict_contenido_con_salto_final_coincide
fin_caso "verdict_contenido_con_salto_final_coincide"

# H4 (lead r1): el \r SI se decodifica (contenido CRLF).
verdict_contenido_crlf_coincide() {
  mkdir -p "$LAB/proyecto/.saikit/veredictos"
  vsha="yza567yza567yza567"
  V=$'{\r\n\t"sha": "'$vsha'",\r\n\t"verifier": "PASS"\r\n}\r\n'
  printf '%s' "$V" > "$LAB/proyecto/.saikit/veredictos/$vsha.json"
  verdict_armar
  lab_run tool claude "$(verdict_payload_write reviewer ".saikit/veredictos/$vsha.json" "$V")"
  _igual "hash CRLF (contra el ARCHIVO)" "$(lab_estado veredicto_sha256)" "$(sha256sum "$LAB/proyecto/.saikit/veredictos/$vsha.json" | cut -c1-64)"
}
caso "verdict_contenido_crlf_coincide"
verdict_contenido_crlf_coincide
fin_caso "verdict_contenido_crlf_coincide"

# ---------------------- Task 18.13 (c): el Write del veredicto NO es trabajo
# Un turno de SOLO revision escribe una sola cosa: el veredicto. Si ese Write
# se acredita como trabajo, el estado reporta implementacion y edicion de
# codigo que no existieron — la golden del escenario 56 lo mostraba
# (implemented=1 y last_code_edit=1). Las DOS senales van en casos separados
# porque nacen de caminos distintos y un caso que solo mire una no discrimina:
# `implemented` viene del grep laxo del PostToolUse; `last_code_edit` de
# rn_mark_code_edit via rn_is_noncode_path.
verdict_payload_revision() {  # $1=vsha — contenido minimo de veredicto valido
  printf '{"sha":"%s","pr":1,"verifier":"PASS","verify_app":{"resultado":"n/a","comando":null},"blast":{"nivel":4,"hecho":"h","comando":"c"},"adversary":"n/a","reviewer":"clean","decisiones":".saikit/decisiones/t.tsv"}' "$1"
}

verdict_write_no_acredita_implemented() {
  mkdir -p "$LAB/proyecto/.saikit/veredictos"
  vsha="notrab01notrab01"
  V="$(verdict_payload_revision "$vsha")"
  printf '%s' "$V" > "$LAB/proyecto/.saikit/veredictos/$vsha.json"
  verdict_armar
  lab_run tool claude "$(verdict_payload_write reviewer ".saikit/veredictos/$vsha.json" "$V")"
  _no_vacio "el sello disparo (era el Write del reviewer sobre veredictos/)" "$(lab_estado veredicto_sha256)"
  _igual "implemented queda en 0 (el veredicto no es trabajo)" "$(lab_estado implemented)" "0"
  _vacio "el log no acredita implemented con el veredicto" "$(lab_log | grep '^implemented:')"
}
caso "verdict_write_no_acredita_implemented"
verdict_write_no_acredita_implemented
fin_caso "verdict_write_no_acredita_implemented"

verdict_write_no_marca_code_edit() {
  mkdir -p "$LAB/proyecto/.saikit/veredictos"
  vsha="notrab02notrab02"
  V="$(verdict_payload_revision "$vsha")"
  printf '%s' "$V" > "$LAB/proyecto/.saikit/veredictos/$vsha.json"
  verdict_armar
  lab_run tool claude "$(verdict_payload_write reviewer ".saikit/veredictos/$vsha.json" "$V")"
  _no_vacio "el sello disparo (era el Write del reviewer sobre veredictos/)" "$(lab_estado veredicto_sha256)"
  rn_file="$(dirname "$LAB_ESTADO_PATH")/harness-state-review-notice.env"
  _no_vacio "el evento del reviewer SI deja last_review" "$(grep '^last_review=.' "$rn_file" 2>/dev/null)"
  _vacio "el Write del veredicto NO marca last_code_edit" "$(grep '^last_code_edit=.' "$rn_file" 2>/dev/null)"
}
caso "verdict_write_no_marca_code_edit"
verdict_write_no_marca_code_edit
fin_caso "verdict_write_no_marca_code_edit"

# El detalle que la fila 18.13 pide DECLARAR y atar: un turno de solo
# revision NO dispara la falsa alarma de "codigo tocado despues del review".
# Pre-fix no disparaba porque rn_mark_review y rn_mark_code_edit caen en el
# MISMO contador y el Stop compara con -gt; post-fix el Write del veredicto
# ya no marca last_code_edit en absoluto. El caso ata el observable por
# cualquiera de los dos mecanismos.
verdict_turno_solo_revision_sin_falso_aviso() {
  mkdir -p "$LAB/proyecto/.saikit/veredictos"
  vsha="notrab03notrab03"
  V="$(verdict_payload_revision "$vsha")"
  printf '%s' "$V" > "$LAB/proyecto/.saikit/veredictos/$vsha.json"
  verdict_armar
  lab_run tool claude "$(verdict_payload_write reviewer ".saikit/veredictos/$vsha.json" "$V")"
  lab_run stop claude "$(lab_payload_stop)"
  _no_vacio "el sello disparo (era el Write del reviewer sobre veredictos/)" "$(lab_estado veredicto_sha256)"
  _vacio "sin aviso pendiente de review-notice para el turno siguiente" "$(find "$LAB/hooks/state" -name 'review-notice-pending.log' 2>/dev/null)"
  _vacio "el log no registra el aviso de codigo tras el review" "$(lab_log | grep 'review-notice:')"
}
caso "verdict_turno_solo_revision_sin_falso_aviso"
verdict_turno_solo_revision_sin_falso_aviso
fin_caso "verdict_turno_solo_revision_sin_falso_aviso"

# ---------------------- Task 18.26: sello unarmed (hijo Grok)
# Forma medida en docs/evidence/18.26-grok-reviewer-write/write.post_tool_use.json:
# hookEventName=post_tool_use, toolName=write, toolInput.file_path+content,
# subagentType top-level. Sin agent_type. Sesion sin -saikit (sin STATE_PATH).
verdict_payload_grok_write() {
  _vd_role_json=""
  if [ -n "$1" ]; then
    _vd_role_json="$(printf ',"subagentType":"%s"' "$1")"
  fi
  printf '{"sessionId":"__SESSION_ID__","transcriptPath":"__TRANSCRIPT__","cwd":"/proyecto","workspaceRoot":"/proyecto","permissionMode":"auto","hookEventName":"post_tool_use","toolName":"write","toolInput":{"file_path":"%s","content":"%s"},"toolResult":{"type":"SearchReplace"},"isBackgrounded":false%s}' "$2" "$(verdict_esc "$3")" "$_vd_role_json"
}

verdict_unarmed_grok_reviewer_write_sella() {
  mkdir -p "$LAB/proyecto/.saikit/veredictos"
  vsha="deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
  V="{\"sha\":\"$vsha\",\"pr\":0,\"verifier\":\"PASS\",\"verify_app\":{\"resultado\":\"n/a\",\"comando\":null},\"blast\":{\"omitido\":\"medicion 18.26\"},\"adversary\":\"n/a\",\"reviewer\":\"clean\",\"decisiones\":\"n/a\"}"
  printf '%s' "$V" > "$LAB/proyecto/.saikit/veredictos/$vsha.json"
  _vacio "sesion sin armar (sin STATE_PATH)" "$(lab_estado task_hash)"
  lab_run tool claude "$(verdict_payload_grok_write reviewer ".saikit/veredictos/$vsha.json" "$V")"
  _igual "hash unarmed grok-shaped" "$(lab_estado veredicto_sha256)" "$(printf '%s' "$V" | sha256sum | cut -c1-64)"
  _igual "hash unarmed contra el archivo" "$(lab_estado veredicto_sha256)" "$(sha256sum "$LAB/proyecto/.saikit/veredictos/$vsha.json" | cut -c1-64)"
  _contiene "agents_seen lleva reviewer (cruce del merge)" "$(lab_estado agents_seen)" "reviewer"
}

caso "verdict_unarmed_grok_reviewer_write_sella"
verdict_unarmed_grok_reviewer_write_sella
fin_caso "verdict_unarmed_grok_reviewer_write_sella"

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
    _igual "sello solo en B" "$(sed -n 's/^veredicto_sha256=//p' "$ruta_B")" "$want"
    _igual "B no se arma" "$(sed -n 's/^lane=//p' "$ruta_B")" "seal_boot"
  else
    _mal "falta sello local en la sesion B"
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

# Stop con prosa (sin recibo) sobre estado seal_boot: ALLOW y el sello vive.
# Sin el early-exit, el Stop trata task_hash=unknown como armado, exige recibo
# y en unknown-honesto / presupuesto / close limpio borra el estado.
verdict_unarmed_stop_prosa_conserva_sello() {
  verdict_unarmed_grok_reviewer_write_sella
  sello="$(lab_estado veredicto_sha256)"
  _no_vacio "sello previo al Stop" "$sello"
  _igual "lane del boot unarmed" "$(lab_estado lane)" "seal_boot"
  lab_run stop grok "$(lab_payload_grok_stop 'Reviewer: clean. El veredicto esta sellado.' end_turn)"
  _igual "Stop seal_boot no bloquea" "$LAB_RC" "0"
  if printf '%s' "$LAB_OUT" | grep -Fq '"decision":"block"'; then
    _mal "Stop seal_boot exigio recibo"
  fi
  if ! lab_hay_estado; then
    _mal "Stop no debe borrar STATE_PATH del sello"
  fi
  _igual "sello sobrevive Stop" "$(lab_estado veredicto_sha256)" "$sello"
  _contiene "agents_seen sigue reviewer" "$(lab_estado agents_seen)" "reviewer"
}

caso "verdict_unarmed_stop_prosa_conserva_sello"
verdict_unarmed_stop_prosa_conserva_sello
fin_caso "verdict_unarmed_stop_prosa_conserva_sello"

# Write de codigo en la misma sesion unarmed: no cae a mark_evidence.
verdict_unarmed_write_codigo_no_implementa() {
  verdict_unarmed_grok_reviewer_write_sella
  sello="$(lab_estado veredicto_sha256)"
  _no_vacio "sello previo al Write" "$sello"
  lab_run tool claude "$(verdict_payload_grok_write "" "src/foo.py" "print(1)")"
  _igual "write de codigo no marca implemented" "$(lab_estado implemented)" "0"
  _igual "sello sobrevive write de codigo" "$(lab_estado veredicto_sha256)" "$sello"
  if ! lab_hay_estado; then
    _mal "write de codigo no debe borrar el estado del sello"
  fi
}

caso "verdict_unarmed_write_codigo_no_implementa"
verdict_unarmed_write_codigo_no_implementa
fin_caso "verdict_unarmed_write_codigo_no_implementa"

# ---------------------- 20.13: consumo vinculado Grok (anuncio host)
# Positivo: padre armado anuncia hijo → hijo sella → spawn done consume en padre.
# Negativo: otro padre no recibe el sello; sin vínculo el hijo seal_boot no basta.
verdict_link_positivo_padre_consume_sello_hijo() {
  LAB_GROK_HOOK_EVENT=post_tool_use
  mkdir -p "$LAB/proyecto/.saikit/veredictos"
  vsha="deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
  V="{\"sha\":\"$vsha\",\"pr\":0,\"verifier\":\"PASS\",\"verify_app\":{\"resultado\":\"n/a\",\"comando\":null},\"blast\":{\"omitido\":\"20.13\"},\"adversary\":\"n/a\",\"reviewer\":\"clean\",\"decisiones\":\"n/a\"}"
  printf '%s' "$V" > "$LAB/proyecto/.saikit/veredictos/$vsha.json"
  want="$(printf '%s' "$V" | sha256sum | cut -c1-64)"

  LAB_SESSION_ID=parent-A-2013
  lab_run prompt grok "$(lab_payload_prompt '-saikit trabajo padre A')"
  ruta_A="$(find "$LAB/hooks/state/grok" -path '*/parent-A-2013/harness-state.env')"
  [ -f "$ruta_A" ] || { _mal "falta estado padre A"; LAB_SESSION_ID=""; LAB_GROK_HOOK_EVENT=""; return; }
  lab_run tool grok "$(lab_payload_grok_subagent_start reviewer child-B-2013 'review A')"
  _igual "padre anuncia hijo" "$(sed -n 's/^linked_children=//p' "$ruta_A")" "child-B-2013"

  LAB_SESSION_ID=child-B-2013
  lab_run tool grok "$(verdict_payload_grok_write reviewer ".saikit/veredictos/$vsha.json" "$V")"
  ruta_B="$(find "$LAB/hooks/state/grok" -path '*/child-B-2013/harness-state.env')"
  [ -f "$ruta_B" ] || { _mal "falta sello hijo B"; LAB_SESSION_ID=""; LAB_GROK_HOOK_EVENT=""; return; }
  _igual "sello en hijo" "$(sed -n 's/^veredicto_sha256=//p' "$ruta_B")" "$want"
  _igual "hijo seal_boot" "$(sed -n 's/^lane=//p' "$ruta_B")" "seal_boot"
  _vacio "padre aun sin sello antes del consume" "$(sed -n 's/^veredicto_sha256=//p' "$ruta_A")"

  LAB_SESSION_ID=parent-A-2013
  lab_run tool grok "$(lab_payload_grok_spawn_done reviewer child-B-2013)"
  _igual "padre consume sello" "$(sed -n 's/^veredicto_sha256=//p' "$ruta_A")" "$want"
  _igual "padre nombra linked_seal_session" "$(sed -n 's/^linked_seal_session=//p' "$ruta_A")" "child-B-2013"
  _contiene "padre agents_seen reviewer" "$(sed -n 's/^agents_seen=//p' "$ruta_A")" "reviewer"
  _igual "hijo conserva sello" "$(sed -n 's/^veredicto_sha256=//p' "$ruta_B")" "$want"
  LAB_SESSION_ID=""; LAB_GROK_HOOK_EVENT=""
}
caso "verdict_link_positivo_padre_consume_sello_hijo"
verdict_link_positivo_padre_consume_sello_hijo
fin_caso "verdict_link_positivo_padre_consume_sello_hijo"

verdict_link_otro_padre_no_consume() {
  LAB_GROK_HOOK_EVENT=post_tool_use
  mkdir -p "$LAB/proyecto/.saikit/veredictos"
  vsha="deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
  V="{\"sha\":\"$vsha\",\"pr\":0,\"verifier\":\"PASS\",\"verify_app\":{\"resultado\":\"n/a\",\"comando\":null},\"blast\":{\"omitido\":\"20.13\"},\"adversary\":\"n/a\",\"reviewer\":\"clean\",\"decisiones\":\"n/a\"}"
  printf '%s' "$V" > "$LAB/proyecto/.saikit/veredictos/$vsha.json"
  want="$(printf '%s' "$V" | sha256sum | cut -c1-64)"

  LAB_SESSION_ID=parent-A-2013b
  lab_run prompt grok "$(lab_payload_prompt '-saikit padre A')"
  lab_run tool grok "$(lab_payload_grok_subagent_start reviewer child-B-2013b 'rev')"
  LAB_SESSION_ID=child-B-2013b
  lab_run tool grok "$(verdict_payload_grok_write reviewer ".saikit/veredictos/$vsha.json" "$V")"
  ruta_B="$(find "$LAB/hooks/state/grok" -path '*/child-B-2013b/harness-state.env')"
  _igual "sello en B" "$(sed -n 's/^veredicto_sha256=//p' "$ruta_B")" "$want"

  # Padre C: spawn_done SIN SubagentStart previo → no enrolla ni consume.
  # Mutacion consume_sin_vinculo salta la guarda de linked_children y sella C.
  LAB_SESSION_ID=parent-C-ajeno
  lab_run prompt grok "$(lab_payload_prompt '-saikit padre C ajeno')"
  ruta_C="$(find "$LAB/hooks/state/grok" -path '*/parent-C-ajeno/harness-state.env')"
  [ -f "$ruta_C" ] || { _mal "falta padre C"; LAB_SESSION_ID=""; LAB_GROK_HOOK_EVENT=""; return; }
  lab_run tool grok "$(lab_payload_grok_spawn_done reviewer child-B-2013b)"
  _vacio "C sin linked_children del hijo ajeno" "$(sed -n 's/^linked_children=//p' "$ruta_C")"
  _vacio "C sin sello sin anuncio previo" "$(sed -n 's/^veredicto_sha256=//p' "$ruta_C")"
  _vacio "C sin linked_seal_session" "$(sed -n 's/^linked_seal_session=//p' "$ruta_C")"
  LAB_SESSION_ID=""; LAB_GROK_HOOK_EVENT=""
}
caso "verdict_link_otro_padre_no_consume"
verdict_link_otro_padre_no_consume
fin_caso "verdict_link_otro_padre_no_consume"

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
# Animamos el sello y exigimos que un caso se ponga rojo: si no, nada de esta
# suite probaria que el sello existe. Guardias: la mutacion cambia el archivo,
# el mutado parsea, y algun caso lo atrapa.
mut_veredicto_sello_apagado() { sed 's/^verdict_registrar_sello() {$/verdict_registrar_sello() {\n  return 0/'; }

# Task 18.13 (c): las dos mitades del fix, cada una atrapada por SU caso — un
# caso que solo mire `implemented` no veria el contador del review-notice, y
# viceversa. La primera quita la exclusion de .saikit/veredictos/ en
# rn_is_noncode_path (vuelve last_code_edit); la segunda quita la guardia del
# grep laxo (vuelve implemented).
mut_veredicto_rn_noncode_sin_veredictos() { sed '/\.saikit\/veredictos\/\*|\.saikit\/veredictos\/\*) return 0 ;;/d'; }
mut_veredicto_implemented_sin_guardia() { sed 's/\[ -z "$vd_write_reviewer" \] && //'; }

# Task 18.13 (b): el contrato pierde la instruccion de commitear ANTES del
# reviewer — la atrapa contrato_lider_commitea_antes_de_despachar_al_reviewer.
mut_veredicto_lider_sin_commit_antes() { sed 's/Commit BEFORE dispatching the reviewer/Commit once the reviewer has already run/'; }
# Task 18.13 (a): el Close: pierde la clausula que cita el sha y la ruta del
# veredicto sellado — la atrapa contrato_close_cita_sha_y_ruta_del_veredicto_sellado.
mut_veredicto_close_sin_cita() { sed 's/; if a verdict was sealed this turn, cite the sha and path of the sealed verdict (\.saikit\/veredictos\/<sha>\.json)//'; }
mut_veredicto_sello_unarmed_apagado() { sed 's/^verdict_try_seal_unarmed() {$/verdict_try_seal_unarmed() {\n  return 1/'; }
mut_veredicto_seal_boot_stop_apagado() { sed 's/read_state_value lane)" = "seal_boot"/read_state_value lane)" = ""/'; }
# Simulate the removed cross-session write, without requiring dead production
# helpers to survive solely for mutation tests. The target is a real sibling.
mut_veredicto_sello_cruza_sesion() {
  awk '
    { print }
    /^verdict_boot_and_seal\(\) \{$/ {
      print "  for vd_other in \"$PROJECT_DIR\"/*/harness-state.env; do"
      print "    [ -f \"$vd_other\" ] || continue"
      print "    [ \"$vd_other\" = \"$STATE_PATH\" ] && continue"
      print "    STATE_PATH=\"$vd_other\""
      print "    STATE_DIR=\"$(dirname \"$STATE_PATH\")\""
      print "    LOG_PATH=\"$STATE_DIR/harness-evidence.log\""
      print "    break"
      print "  done"
    }
  '
}

# 20.13: consumir sello de cualquier hijo sin exigir linked_children.
mut_veredicto_consume_sin_vinculo() {
  sed '/case ",\$cur," in \*",\$child,"\*) ;; \*) return 0 ;; esac/d'
}

MUTS_VERDICT="sello_apagado|verdict_reviewer_write_registra_hash
rn_noncode_sin_veredictos|verdict_write_no_marca_code_edit
implemented_sin_guardia|verdict_write_no_acredita_implemented
lider_sin_commit_antes|contrato_lider_commitea_antes_de_despachar_al_reviewer
close_sin_cita|contrato_close_cita_sha_y_ruta_del_veredicto_sellado
sello_unarmed_apagado|verdict_unarmed_grok_reviewer_write_sella
seal_boot_stop_apagado|verdict_unarmed_stop_prosa_conserva_sello
sello_cruza_sesion|verdict_unarmed_no_toca_sesion_verificada
consume_sin_vinculo|verdict_link_otro_padre_no_consume"

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

# ------------------------------------- mutation-test de la LIB (Task 18.17)
# La lib no es el hook: se muta el archivo, se RE-CARGA en este shell y se corre
# el caso que lo atrapa; despues se recarga la lib original. La mutacion quita
# la exigencia de razon no vacia en blast.omitido: {"omitido":""} y
# {"omitido":"n/a"} pasarian, que es exactamente el placeholder que la 18.17
# prohibe.
LIB_VERDICT="$repo/tools/lib/veredicto_contract.sh"
# Quita el case de placeholders, plantillas, escapes y el piso de longitud.
mut_lib_omitido_sin_razon() {
  awk '
    /case "\$razon" in/ { skip=1; print "    : # mutacion: sin exigencia de razon"; next }
    skip && /^    esac$/ { skip=0; next }
    skip { next }
    /\[ "\$\{#razon\}" -lt 8 \]/ { skip2=1; next }
    skip2 && /^    fi$/ { skip2=0; next }
    skip2 { next }
    { print }
  '
}
# Acepta el escalar blast (deja el if pero sin return 1: cae al fi y sigue).
mut_lib_blast_escalar_aceptado() {
  sed '/if veredicto_tiene_hoja "\$flat" blast; then/,/return 1/{
    /return 1/d
  }'
}
# Acepta mezcla omitido+triada (quita el bloque del for de prefijos).
mut_lib_blast_mezcla_aceptada() {
  awk '
    /for campo in \$VEREDICTO_BLAST_TRIADA; do/ && !seen++ { skip=1; next }
    skip && /^    done$/ { skip=0; next }
    skip { next }
    { print }
  '
}

MUTS_LIB="omitido_sin_razon|contrato_blast_na_sin_razon_invalido
blast_escalar_aceptado|contrato_pr157_blast_na_invalido
blast_mezcla_aceptada|contrato_blast_mezcla_omitido_y_hecho_invalido"

while IFS='|' read -r nombre caso_atrapa; do
  [ -n "$nombre" ] || continue
  mutado="$tmp/lib-$nombre.sh"
  "mut_lib_$nombre" < "$LIB_VERDICT" > "$mutado"
  if cmp -s "$LIB_VERDICT" "$mutado"; then
    printf '    FAIL: lib %s no cambio nada — el sed quedo obsoleto\n' "$nombre" >&2
    fail=1
    continue
  fi
  if ! bash -n "$mutado" 2>/dev/null; then
    printf '    FAIL: lib %s no parsea; asi no prueba nada\n' "$nombre" >&2
    fail=1
    continue
  fi
  . "$mutado"
  CASO_ROJO=0
  "$caso_atrapa" 2>/dev/null
  . "$LIB_VERDICT"
  if [ "$CASO_ROJO" -ne 0 ]; then
    printf '    mutacion lib %s atrapada por %s\n' "$nombre" "$caso_atrapa"
  else
    printf '    FAIL: ningun caso detecto la mutacion de la lib [%s]\n' "$nombre" >&2
    fail=1
  fi
done <<EOF
$MUTS_LIB
EOF

if [ "$fail" -ne 0 ]; then
  echo "test_veredicto_contract: FAIL" >&2
  exit 1
fi
echo "test_veredicto_contract: OK"
