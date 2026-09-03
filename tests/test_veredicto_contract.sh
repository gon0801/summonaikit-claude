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
  for campo in '"sha"' '"pr"' '"verifier"' '"verify_app"' '"blast"' '"adversary"' '"reviewer"' '"decisiones"' '"nivel"' '"hecho"' '"resultado"' '"comando"'; do
    _contiene "el perfil documenta el campo $campo" "$perfil" "$campo"
  done

  # (d) una sola escritura: reescribir el archivo despues deja el hash del
  # estado viejo y el merge de 18.4 lo leeria como veredicto tocado.
  _contiene "el perfil prohibe reescribir el veredicto" "$perfil" 'una sola vez'
}
fin_caso "productor_el_perfil_del_reviewer_pide_el_veredicto"

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

MUTS_VERDICT="sello_apagado|verdict_reviewer_write_registra_hash
rn_noncode_sin_veredictos|verdict_write_no_marca_code_edit
implemented_sin_guardia|verdict_write_no_acredita_implemented
lider_sin_commit_antes|contrato_lider_commitea_antes_de_despachar_al_reviewer
close_sin_cita|contrato_close_cita_sha_y_ruta_del_veredicto_sellado"

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
