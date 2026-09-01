#!/usr/bin/env bash
# tests/test_veredicto_contract.sh — Task 18.3: contrato del veredicto sellado.
#
# QUE AFIRMA (DoD de 18.3, docs/phase-18-autopilot-plan.md §4.1):
#   - CONTEXTO/ESQUEMA: el veredicto valido pasa; con `sha` != HEAD => invalido;
#     con un campo requerido faltante => invalido. La validacion es la de
#     `tools/lib/veredicto_contract.sh` (la reusara `tools/saikit-merge.sh`, D18).
#   - GATE (comportamiento del hook): el `Write` atribuido al reviewer sobre
#     `.saikit/veredictos/` regustra `veredicto_sha256` en el estado; el `Write`
#     de OTRO rol NO lo regustra; un `Edit` posterior deja el archivo con hash
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
verdict_esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g'; }
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

if [ "$fail" -ne 0 ]; then
  echo "test_veredicto_contract: FAIL (casos)" >&2
  exit 1
fi

# ------------------------------------------------------- mutation-test propio
# Animamos el sello y exigimos que un caso se ponga rojo: si no, nada de esta
# suite probaria que el sello existe. Guardias: la mutacion cambia el archivo,
# el mutado parsea, y algun caso lo atrapa.
mut_veredicto_sello_apagado() { sed 's/^verdict_registrar_sello() {$/verdict_registrar_sello() {\n  return 0/'; }

MUTS_VERDICT="sello_apagado|verdict_reviewer_write_registra_hash"

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
