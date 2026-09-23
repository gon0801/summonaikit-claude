#!/usr/bin/env bash
# tests/test_entrega_contract.sh — Bloque A (entrega sin sello): contrato del
# recibo de entrega saikit-entrega.v1 y lectura del recibo desde el PR.
#
# QUE AFIRMA:
#   entrega_validar <recibo> <repo> <pr> <sha>:
#     0 cumple; 1 falta evidencia o hay bloqueante; 3 no pudo leer la fuente.
#     La razon especifica va a stderr. Comprueba estructura y relaciones, no
#     la veracidad de la prosa ni la autenticidad de los ids (limite declarado
#     en tools/lib/entrega_contract.sh).
#   entrega_recibo_del_pr <repo> <pr> <sha> [lead]:
#     imprime el JSON del ultimo recibo aplicable del PR (comentario
#     APPROVE lead <sha> con bloque ```json saikit-entrega.v1); 0 hallado,
#     1 sin recibo o revocado, 3 API inaccesible.
#
# Casos A1: recibo completo pasa; reviewer ausente falla; verifier FAIL falla;
# identidad reutilizada falla; SHA/repo/PR distintos fallan; bloqueante abierto
# falla; residual no bloqueante pasa; API inaccesible -> 3 (desconocido).
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
LIB="$repo/tools/lib/entrega_contract.sh"

fail=0
CASO_ROJO=0
_mal()      { printf '      FAIL: %s\n' "$1"; CASO_ROJO=1; }
_contiene() { if ! printf '%s' "$2" | grep -Fq -- "$3"; then _mal "$1: no contiene [$3]"; fi; }

SB="$(mktemp -d "${TMPDIR:-/tmp}/saikit-entrega-XXXXXX")" || exit 1
trap 'rm -rf "$SB"' EXIT

# shellcheck disable=SC1090
. "$LIB" 2>/dev/null || {
  printf 'test_entrega_contract: FAIL — falta %s (rojo TDD: la lib no existe)\n' "$LIB" >&2
  exit 1
}

REPO="op/sandbox"
PR="7"
SHA="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

# recibo_ok > archivo: el recibo minimo valido del plan (los artifact: son
# ejemplos de fixture, no evidencia de produccion).
recibo_ok() {
  cat <<JSON
{"schema":"saikit-entrega.v1","repo":"$REPO","pr":7,"sha":"$SHA","clase":"codigo","implementer":{"id":"worker-a","evidencia":"artifact:implementacion"},"verifier":{"id":"worker-b","resultado":"PASS","evidencia":"artifact:verificacion"},"reviewer":{"id":"worker-c","resultado":"APPROVE","evidencia":"artifact:revision"},"ci":{"workflow":"ci","evidencia":"artifact:ci"},"bloqueantes":[],"residuales":[]}
JSON
}

validar() {  # $1=archivo recibo; deja OUT/ERR/RC
  ERR="$(entrega_validar "$1" "$REPO" "$PR" "$SHA" 2>&1 >/dev/null)"
  RC=$?
  OUT="$ERR"
}

caso() { printf '  caso: %s\n' "$1"; CASO_ROJO=0; }
fin_caso() {
  if [ "$CASO_ROJO" -ne 0 ]; then
    printf '    ROJO: %s\n' "$1" >&2
    fail=1
  else
    printf '    ok: %s\n' "$1"
  fi
}

caso "recibo_completo_pasa"
{
  recibo_ok > "$SB/recibo.json"
  entrega_validar "$SB/recibo.json" "$REPO" "$PR" "$SHA" >"$SB/out" 2>"$SB/err"
  RC=$?
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC: $(cat "$SB/err")"
}
fin_caso "recibo_completo_pasa"

caso "reviewer_ausente_falla"
{
  recibo_ok | sed 's/"reviewer":{"id":"worker-c","resultado":"APPROVE","evidencia":"artifact:revision"}/"reviewer":{}/' > "$SB/recibo.json"
  validar "$SB/recibo.json"
  [ "$RC" -eq 1 ] || _mal "rc esperaba 1, dio $RC"
  _contiene "nombra reviewer" "$OUT" "reviewer"
}
fin_caso "reviewer_ausente_falla"

caso "verifier_fail_falla"
{
  recibo_ok | sed 's/"verifier":{"id":"worker-b","resultado":"PASS"/"verifier":{"id":"worker-b","resultado":"FAIL"/' > "$SB/recibo.json"
  validar "$SB/recibo.json"
  [ "$RC" -eq 1 ] || _mal "rc esperaba 1, dio $RC"
  _contiene "nombra verifier" "$OUT" "verifier"
  _contiene "nombra PASS" "$OUT" "PASS"
}
fin_caso "verifier_fail_falla"

caso "identidad_reutilizada_falla"
{
  recibo_ok | sed 's/"reviewer":{"id":"worker-c"/"reviewer":{"id":"worker-b"/' > "$SB/recibo.json"
  validar "$SB/recibo.json"
  [ "$RC" -eq 1 ] || _mal "rc esperaba 1, dio $RC"
  _contiene "nombra identidad reutilizada" "$OUT" "reutilizada"
}
fin_caso "identidad_reutilizada_falla"

caso "spec_entrega_no_depende_del_sentinel_de_sesion"
{
  # La entrega debe poder continuar desde otro host sin recuperar el turno.
  # Este contrato documental evita restaurar la regla que contradice A6.
  spec="$repo/docs/spec/00-project-spec.md"
  if grep -Eq 'El carril lo fija el sentinel, nunca la receta ni el recibo|en full el Stop exige los tres roles|que el líder baje el carril desde el recibo' "$spec"; then
    _mal "la especificacion sigue exigiendo estado de turno para la entrega"
  fi
  grep -Fq 'La clase del recibo describe el cambio real del PR' "$spec" \
    || _mal "falta la autoridad persistente de la clase del cambio"
  grep -Fq 'El lead comprueba la clase contra el diff' "$spec" \
    || _mal "falta declarar quien impide etiquetar codigo como editorial"
}
fin_caso "spec_entrega_no_depende_del_sentinel_de_sesion"

caso "editorial_fast_pasa_sin_verifier_ni_reviewer"
{
  recibo_ok \
    | sed 's/"clase":"codigo"/"clase":"editorial"/' \
    | sed 's/,"verifier":{[^}]*},"reviewer":{[^}]*}//' \
    > "$SB/recibo.json"
  entrega_validar "$SB/recibo.json" "$REPO" "$PR" "$SHA" >"$SB/out" 2>"$SB/err"
  RC=$?
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC: $(cat "$SB/err")"
}
fin_caso "editorial_fast_pasa_sin_verifier_ni_reviewer"

caso "clase_desconocida_falla"
{
  recibo_ok | sed 's/"clase":"codigo"/"clase":"codgio"/' > "$SB/recibo.json"
  validar "$SB/recibo.json"
  [ "$RC" -eq 1 ] || _mal "rc esperaba 1, dio $RC"
  _contiene "nombra clase" "$OUT" "clase"
}
fin_caso "clase_desconocida_falla"

caso "ci_ausente_falla"
{
  recibo_ok | sed 's/,"ci":{[^}]*}//' > "$SB/recibo.json"
  validar "$SB/recibo.json"
  [ "$RC" -eq 1 ] || _mal "rc esperaba 1, dio $RC"
  _contiene "nombra ci" "$OUT" "ci.workflow"
}
fin_caso "ci_ausente_falla"

caso "sha_distinto_falla"
{
  recibo_ok > "$SB/recibo.json"
  ERR="$(entrega_validar "$SB/recibo.json" "$REPO" "$PR" "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" 2>&1 >/dev/null)"
  RC=$?
  [ "$RC" -eq 1 ] || _mal "rc esperaba 1, dio $RC"
  _contiene "nombra sha" "$ERR" "sha"
}
fin_caso "sha_distinto_falla"

caso "repo_distinto_falla"
{
  recibo_ok > "$SB/recibo.json"
  ERR="$(entrega_validar "$SB/recibo.json" "otro/repo" "$PR" "$SHA" 2>&1 >/dev/null)"
  RC=$?
  [ "$RC" -eq 1 ] || _mal "rc esperaba 1, dio $RC"
  _contiene "nombra repo" "$ERR" "repo"
}
fin_caso "repo_distinto_falla"

caso "pr_distinto_falla"
{
  recibo_ok > "$SB/recibo.json"
  ERR="$(entrega_validar "$SB/recibo.json" "$REPO" "9" "$SHA" 2>&1 >/dev/null)"
  RC=$?
  [ "$RC" -eq 1 ] || _mal "rc esperaba 1, dio $RC"
  _contiene "nombra pr" "$ERR" "pr"
}
fin_caso "pr_distinto_falla"

caso "bloqueante_abierto_falla"
{
  recibo_ok | sed 's/"bloqueantes":\[\]/"bloqueantes":[{"id":"B1","titulo":"caida en prod"}]/' > "$SB/recibo.json"
  validar "$SB/recibo.json"
  [ "$RC" -eq 1 ] || _mal "rc esperaba 1, dio $RC"
  _contiene "nombra bloqueante" "$OUT" "bloqueante"
}
fin_caso "bloqueante_abierto_falla"

caso "bloqueantes_vacio_y_ausente_pasa"
{
  recibo_ok | sed 's/"bloqueantes":\[\]/"bloqueantes":{}/' > "$SB/recibo.json"
  entrega_validar "$SB/recibo.json" "$REPO" "$PR" "$SHA" >"$SB/out" 2>"$SB/err"
  RC=$?
  [ "$RC" -eq 0 ] || _mal "objeto vacio: rc esperaba 0, dio $RC: $(cat "$SB/err")"
  recibo_ok | sed 's/,"bloqueantes":\[\]//' > "$SB/recibo.json"
  entrega_validar "$SB/recibo.json" "$REPO" "$PR" "$SHA" >"$SB/out" 2>"$SB/err"
  RC=$?
  [ "$RC" -eq 0 ] || _mal "ausente: rc esperaba 0, dio $RC: $(cat "$SB/err")"
}
fin_caso "bloqueantes_vacio_y_ausente_pasa"

caso "bloqueantes_contenedor_sin_hojas_falla"
{
  for variante in '[{}]' '[[]]' '{"x":[]}' '{"x":{}}'; do
    recibo_ok | sed "s/\"bloqueantes\":\[\]/\"bloqueantes\":$variante/" > "$SB/recibo.json"
    validar "$SB/recibo.json"
    [ "$RC" -eq 1 ] || _mal "$variante: rc esperaba 1, dio $RC"
    _contiene "$variante nombra bloqueante" "$OUT" "bloqueante"
  done
}
fin_caso "bloqueantes_contenedor_sin_hojas_falla"

caso "bloqueantes_escalar_falla"
{
  recibo_ok | sed 's/"bloqueantes":\[\]/"bloqueantes":"urgente"/' > "$SB/recibo.json"
  validar "$SB/recibo.json"
  [ "$RC" -eq 1 ] || _mal "rc esperaba 1, dio $RC"
  _contiene "nombra bloqueante" "$OUT" "bloqueante"
}
fin_caso "bloqueantes_escalar_falla"

caso "residual_no_bloqueante_pasa"
{
  recibo_ok | sed 's/"residuales":\[\]/"residuales":[{"id":"R1","nota":"deuda menor"}]/' > "$SB/recibo.json"
  entrega_validar "$SB/recibo.json" "$REPO" "$PR" "$SHA" >"$SB/out" 2>"$SB/err"
  RC=$?
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC: $(cat "$SB/err")"
}
fin_caso "residual_no_bloqueante_pasa"

caso "json_invalido_falla"
{
  printf '{"schema":"saikit-entrega.v1", roto' > "$SB/recibo.json"
  validar "$SB/recibo.json"
  [ "$RC" -eq 1 ] || _mal "rc esperaba 1, dio $RC"
  _contiene "nombra JSON" "$OUT" "JSON"
}
fin_caso "json_invalido_falla"

caso "schema_distinto_falla"
{
  recibo_ok | sed 's/"schema":"saikit-entrega.v1"/"schema":"otro.v9"/' > "$SB/recibo.json"
  validar "$SB/recibo.json"
  [ "$RC" -eq 1 ] || _mal "rc esperaba 1, dio $RC"
  _contiene "nombra schema" "$OUT" "schema"
}
fin_caso "schema_distinto_falla"

caso "recibo_ilegible_es_desconocido"
{
  ERR="$(entrega_validar "$SB/no-existe.json" "$REPO" "$PR" "$SHA" 2>&1 >/dev/null)"
  RC=$?
  [ "$RC" -eq 3 ] || _mal "rc esperaba 3, dio $RC"
}
fin_caso "recibo_ilegible_es_desconocido"

# ------------------------------------------------- lectura del recibo del PR
# gh falso minimo: solo la forma que usa entrega_recibo_del_pr. SAIKIT_GH_COMMENTS
# apunta al fixture; SAIKIT_GH_API_FALLA=1 simula la API caida. Van con
# export, NO como prefijo inline: `VAR=x OUT=$(...)` no exporta a los nietos
# (el gh falso las veria UNSET) y el caso de API caida pasaria por la razon
# equivocada.
montar_gh() {
  mkdir -p "$SB/bin"
  cat > "$SB/bin/gh" <<'GHEOF'
#!/usr/bin/env bash
set -u
if [ "${SAIKIT_GH_API_FALLA:-0}" = 1 ]; then
  printf 'gh-falso: API inaccesible\n' >&2
  exit 1
fi
case "$1 $2" in
  "api repos/"*)
    cat "${SAIKIT_GH_COMMENTS:?}"
    exit 0 ;;
esac
printf 'gh-falso: forma no soportada: %s\n' "$*" >&2
exit 1
GHEOF
  chmod +x "$SB/bin/gh"
  PATH="$SB/bin:$PATH"
}

# comentario_json <login> <body-archivo> — un elemento del array de comments.
comentario_json() {
  body_esc="$(python3 -c 'import json,sys; print(json.dumps(open(sys.argv[1], encoding="utf-8").read()))' "$2")"
  printf '{"user":{"login":"%s"},"body":%s}' "$1" "$body_esc"
}

montar_gh

caso "loader_toma_ultimo_recibo_aplicable"
{
  {
    printf 'APROBADO a mano sin formato\n'
  } > "$SB/c1.txt"
  {
    printf 'APPROVE lead %s\n\n```json\n' "$SHA"
    printf '{"schema":"saikit-entrega.v1","repo":"%s","pr":7,"sha":"%s","clase":"codigo","implementer":{"id":"a","evidencia":"e1"},"verifier":{"id":"b","resultado":"PASS","evidencia":"e2"},"reviewer":{"id":"c","resultado":"APPROVE","evidencia":"e3"},"ci":{"workflow":"ci","evidencia":"e4"},"bloqueantes":[],"residuales":[]}\n' "$REPO" "$SHA"
    printf '```\n'
  } > "$SB/c2.txt"
  {
    printf 'APPROVE lead %s\n\ncorreccion: evidencia final\n\n```json\n' "$SHA"
    printf '{"schema":"saikit-entrega.v1","repo":"%s","pr":7,"sha":"%s","clase":"codigo","implementer":{"id":"a2","evidencia":"e1"},"verifier":{"id":"b2","resultado":"PASS","evidencia":"e2"},"reviewer":{"id":"c2","resultado":"APPROVE","evidencia":"e3"},"ci":{"workflow":"ci","evidencia":"e4"},"bloqueantes":[],"residuales":[]}\n' "$REPO" "$SHA"
    printf '```\n'
  } > "$SB/c3.txt"
  {
    printf '['; comentario_json "op" "$SB/c1.txt"; printf ','
    comentario_json "op" "$SB/c2.txt"; printf ','
    comentario_json "op" "$SB/c3.txt"; printf ']'
  } > "$SB/comments.json"
  export SAIKIT_GH_COMMENTS="$SB/comments.json" SAIKIT_GH_API_FALLA=0
  OUT="$(entrega_recibo_del_pr "$REPO" "$PR" "$SHA" "op" 2>"$SB/err")"
  RC=$?
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC: $(cat "$SB/err")"
  _contiene "toma el ultimo" "$OUT" '"id":"a2"'
  printf '%s' "$OUT" | entrega_validar - "$REPO" "$PR" "$SHA" 2>"$SB/err" \
    || _mal "el recibo extraido no valida: $(cat "$SB/err")"
}
fin_caso "loader_toma_ultimo_recibo_aplicable"

caso "loader_ignora_otro_sha_y_otro_lead"
{
  {
    printf 'APPROVE lead bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n\n```json\n{"schema":"saikit-entrega.v1"}\n```\n'
  } > "$SB/c1.txt"
  {
    printf 'APPROVE lead %s\n\n```json\n{"schema":"saikit-entrega.v1"}\n```\n' "$SHA"
  } > "$SB/c2.txt"
  {
    printf '['; comentario_json "op" "$SB/c1.txt"; printf ','
    comentario_json "ajeno" "$SB/c2.txt"; printf ']'
  } > "$SB/comments.json"
  export SAIKIT_GH_COMMENTS="$SB/comments.json" SAIKIT_GH_API_FALLA=0
  OUT="$(entrega_recibo_del_pr "$REPO" "$PR" "$SHA" "op" 2>"$SB/err")"
  RC=$?
  [ "$RC" -eq 1 ] || _mal "rc esperaba 1, dio $RC: $OUT"
  _contiene "nombra sin recibo" "$(cat "$SB/err")" "sin recibo"
}
fin_caso "loader_ignora_otro_sha_y_otro_lead"

caso "loader_revocado_falla"
{
  {
    printf 'APPROVE lead %s\n\n```json\n' "$SHA"
    printf '{"schema":"saikit-entrega.v1","repo":"%s","pr":7,"sha":"%s","clase":"codigo","implementer":{"id":"a","evidencia":"e1"},"verifier":{"id":"b","resultado":"PASS","evidencia":"e2"},"reviewer":{"id":"c","resultado":"APPROVE","evidencia":"e3"},"ci":{"workflow":"ci","evidencia":"e4"},"bloqueantes":[],"residuales":[]}\n' "$REPO" "$SHA"
    printf '```\n'
  } > "$SB/c1.txt"
  printf 'REVOKE lead %s: aparecio un bloqueante\n' "$SHA" > "$SB/c2.txt"
  {
    printf '['; comentario_json "op" "$SB/c1.txt"; printf ','
    comentario_json "op" "$SB/c2.txt"; printf ']'
  } > "$SB/comments.json"
  export SAIKIT_GH_COMMENTS="$SB/comments.json" SAIKIT_GH_API_FALLA=0
  OUT="$(entrega_recibo_del_pr "$REPO" "$PR" "$SHA" "op" 2>"$SB/err")"
  RC=$?
  [ "$RC" -eq 1 ] || _mal "rc esperaba 1, dio $RC: $OUT"
  _contiene "nombra revocado" "$(cat "$SB/err")" "revocado"
}
fin_caso "loader_revocado_falla"

caso "loader_api_inaccesible_es_desconocido"
{
  : > "$SB/comments.json"
  export SAIKIT_GH_COMMENTS="$SB/comments.json" SAIKIT_GH_API_FALLA=1
  OUT="$(entrega_recibo_del_pr "$REPO" "$PR" "$SHA" "op" 2>"$SB/err")"
  RC=$?
  [ "$RC" -eq 3 ] || _mal "rc esperaba 3, dio $RC: $OUT"
}
fin_caso "loader_api_inaccesible_es_desconocido"

caso "loader_respuesta_vacia_es_desconocido"
{
  # gh sale 0 pero sin nada: desconocido, no "sin recibo".
  : > "$SB/comments.json"
  export SAIKIT_GH_COMMENTS="$SB/comments.json" SAIKIT_GH_API_FALLA=0
  OUT="$(entrega_recibo_del_pr "$REPO" "$PR" "$SHA" "op" 2>"$SB/err")"
  RC=$?
  [ "$RC" -eq 3 ] || _mal "rc esperaba 3, dio $RC: $OUT"
}
fin_caso "loader_respuesta_vacia_es_desconocido"

caso "loader_comentario_sin_body_no_oculta"
{
  {
    printf 'APPROVE lead %s\n\n```json\n' "$SHA"
    printf '{"schema":"saikit-entrega.v1","repo":"%s","pr":7,"sha":"%s","clase":"codigo","implementer":{"id":"a","evidencia":"e1"},"verifier":{"id":"b","resultado":"PASS","evidencia":"e2"},"reviewer":{"id":"c","resultado":"APPROVE","evidencia":"e3"},"ci":{"workflow":"ci","evidencia":"e4"},"bloqueantes":[],"residuales":[]}\n' "$REPO" "$SHA"
    printf '```\n'
  } > "$SB/c-apr.txt"
  {
    printf '[{"user":{"login":"op"}},'
    comentario_json "op" "$SB/c-apr.txt"
    printf ']'
  } > "$SB/comments.json"
  export SAIKIT_GH_COMMENTS="$SB/comments.json" SAIKIT_GH_API_FALLA=0
  OUT="$(entrega_recibo_del_pr "$REPO" "$PR" "$SHA" "op" 2>"$SB/err")"
  RC=$?
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC: $(cat "$SB/err")"
  _contiene "halla el recibo tras el sin-body" "$OUT" '"id":"a"'
}
fin_caso "loader_comentario_sin_body_no_oculta"

caso "bloqueantes_conteo_exacto_en_el_mensaje"
{
  # A.R2 (ADV-A-02): el contador del mensaje usa el indice detras de
  # "bloqueantes[" (12 caracteres). Con el substr viejo (14) un indice <10
  # nunca contaba y el mensaje decia "0 en la lista" habiendo entradas.
  uno='[{"id":"B1","titulo":"caida en prod"}]'
  doce='[{"id":"B1"},{"id":"B2"},{"id":"B3"},{"id":"B4"},{"id":"B5"},{"id":"B6"},{"id":"B7"},{"id":"B8"},{"id":"B9"},{"id":"B10"},{"id":"B11"},{"id":"B12"}]'
  recibo_ok | sed "s/\"bloqueantes\":\[\]/\"bloqueantes\":$uno/" > "$SB/recibo.json"
  validar "$SB/recibo.json"
  [ "$RC" -eq 1 ] || _mal "un bloqueante debe rechazar (rc 1), dio $RC"
  _contiene "con 1 entrada dice 1" "$OUT" "1 en la lista"
  recibo_ok | sed "s/\"bloqueantes\":\[\]/\"bloqueantes\":$doce/" > "$SB/recibo.json"
  validar "$SB/recibo.json"
  [ "$RC" -eq 1 ] || _mal "doce bloqueantes deben rechazar (rc 1), dio $RC"
  _contiene "con 12 entradas dice 12" "$OUT" "12 en la lista"
  _contiene "el primero sigue nombrado" "$OUT" "B1"
}
fin_caso "bloqueantes_conteo_exacto_en_el_mensaje"

caso "revoke_sin_sha_avisa_y_no_hace_nada"
{
  # A.R3 (ADV-A-03): intencion de revocar sin el sha completo no puede caer
  # en silencio: el operador creeria haber revocado y un --confirmado
  # posterior mergea igual. El recibo sigue vivo (rc 0) y el aviso sale.
  {
    printf 'APPROVE lead %s\n\n```json\n' "$SHA"
    printf '{"schema":"saikit-entrega.v1","repo":"%s","pr":7,"sha":"%s","clase":"codigo","implementer":{"id":"a","evidencia":"e1"},"verifier":{"id":"b","resultado":"PASS","evidencia":"e2"},"reviewer":{"id":"c","resultado":"APPROVE","evidencia":"e3"},"ci":{"workflow":"ci","evidencia":"e4"},"bloqueantes":[],"residuales":[]}\n' "$REPO" "$SHA"
    printf '```\n'
  } > "$SB/c1.txt"
  printf 'REVOKE lead: aparecio un problema, revoco lo anterior\n' > "$SB/c2.txt"
  {
    printf '['; comentario_json "op" "$SB/c1.txt"; printf ','
    comentario_json "op" "$SB/c2.txt"; printf ']'
  } > "$SB/comments.json"
  export SAIKIT_GH_COMMENTS="$SB/comments.json" SAIKIT_GH_API_FALLA=0
  OUT="$(entrega_recibo_del_pr "$REPO" "$PR" "$SHA" "op" 2>"$SB/err")"
  RC=$?
  [ "$RC" -eq 0 ] || _mal "sin el sha el REVOKE no tiene efecto: rc esperaba 0, dio $RC"
  _contiene "el recibo sigue vivo" "$OUT" '"id":"a"'
  _contiene "avisa el REVOKE sin efecto" "$(cat "$SB/err")" "REVOKE visto sin efecto"
}
fin_caso "revoke_sin_sha_avisa_y_no_hace_nada"

caso "revoke_y_approve_mismo_comentario_no_aprueba"
{
  # A.R4 (ADV-A-04), lado 1: como PRIMER comentario, REVOKE y APPROVE juntos
  # son ambiguos y NO aprueban nada (el texto viejo prometia que gana el
  # APPROVE; la regla decidida es fail-closed: revocar y volver a aprobar
  # exige dos comentarios).
  {
    printf 'REVOKE lead %s: anulo lo anterior\n\n' "$SHA"
    printf 'APPROVE lead %s\n\n```json\n' "$SHA"
    printf '{"schema":"saikit-entrega.v1","repo":"%s","pr":7,"sha":"%s","clase":"codigo","implementer":{"id":"a","evidencia":"e1"},"verifier":{"id":"b","resultado":"PASS","evidencia":"e2"},"reviewer":{"id":"c","resultado":"APPROVE","evidencia":"e3"},"ci":{"workflow":"ci","evidencia":"e4"},"bloqueantes":[],"residuales":[]}\n' "$REPO" "$SHA"
    printf '```\n'
  } > "$SB/c1.txt"
  {
    printf '['; comentario_json "op" "$SB/c1.txt"; printf ']'
  } > "$SB/comments.json"
  export SAIKIT_GH_COMMENTS="$SB/comments.json" SAIKIT_GH_API_FALLA=0
  OUT="$(entrega_recibo_del_pr "$REPO" "$PR" "$SHA" "op" 2>"$SB/err")"
  RC=$?
  [ "$RC" -eq 1 ] || _mal "un comentario mixto no puede aprobar; rc esperaba 1, dio $RC"
  _contiene "declara sin recibo" "$(cat "$SB/err")" "sin recibo"
}
fin_caso "revoke_y_approve_mismo_comentario_no_aprueba"

caso "revoke_con_sha_tras_recibo_sigue_revocando"
{
  # A.R4, lado 2: un REVOKE con sha completo despues de un recibo valido lo
  # anula, aunque el mismo comentario intente volver a aprobar con un bloque
  # NUEVO: el recibo queda revocado, no reemplazado.
  {
    printf 'APPROVE lead %s\n\n```json\n' "$SHA"
    printf '{"schema":"saikit-entrega.v1","repo":"%s","pr":7,"sha":"%s","clase":"codigo","implementer":{"id":"a","evidencia":"e1"},"verifier":{"id":"b","resultado":"PASS","evidencia":"e2"},"reviewer":{"id":"c","resultado":"APPROVE","evidencia":"e3"},"ci":{"workflow":"ci","evidencia":"e4"},"bloqueantes":[],"residuales":[]}\n' "$REPO" "$SHA"
    printf '```\n'
  } > "$SB/c1.txt"
  {
    printf 'REVOKE lead %s: anulo lo anterior\n\n' "$SHA"
    printf 'APPROVE lead %s\n\n```json\n' "$SHA"
    printf '{"schema":"saikit-entrega.v1","repo":"%s","pr":7,"sha":"%s","clase":"codigo","implementer":{"id":"z","evidencia":"e1"},"verifier":{"id":"b","resultado":"PASS","evidencia":"e2"},"reviewer":{"id":"c","resultado":"APPROVE","evidencia":"e3"},"ci":{"workflow":"ci","evidencia":"e4"},"bloqueantes":[],"residuales":[]}\n' "$REPO" "$SHA"
    printf '```\n'
  } > "$SB/c2.txt"
  {
    printf '['; comentario_json "op" "$SB/c1.txt"; printf ','
    comentario_json "op" "$SB/c2.txt"; printf ']'
  } > "$SB/comments.json"
  export SAIKIT_GH_COMMENTS="$SB/comments.json" SAIKIT_GH_API_FALLA=0
  OUT="$(entrega_recibo_del_pr "$REPO" "$PR" "$SHA" "op" 2>"$SB/err")"
  RC=$?
  [ "$RC" -eq 1 ] || _mal "el recibo debe quedar revocado; rc esperaba 1, dio $RC"
  _contiene "declara revocado" "$(cat "$SB/err")" "revocado"
}
fin_caso "revoke_con_sha_tras_recibo_sigue_revocando"

caso "pagina_no_array_es_desconocido"
{
  # A.R5 (ADV-A-05): una pagina JSON-valida que no es una LISTA de comentarios
  # (por ejemplo un error de la API) aplana a cero comentarios y se leeria
  # como "sin recibo". Es una respuesta inutilizable: rc 3. Las paginas
  # validas de lista no cambian: los casos de loader de arriba siguen verdes.
  printf '{"message":"Not Found","documentation_url":"https://docs.github.com"}' > "$SB/comments.json"
  export SAIKIT_GH_COMMENTS="$SB/comments.json" SAIKIT_GH_API_FALLA=0
  OUT="$(entrega_recibo_del_pr "$REPO" "$PR" "$SHA" "op" 2>"$SB/err")"
  RC=$?
  [ "$RC" -eq 3 ] || _mal "una pagina no-array es unknown; rc esperaba 3, dio $RC"
  _contiene "nombra la pagina" "$(cat "$SB/err")" "no es una lista"
}
fin_caso "pagina_no_array_es_desconocido"

caso "coordenadas_vacias_rechazadas"
{
  # A.R9(c): con sha vacio, grep -Fq "" matchea cualquier cuerpo; las
  # coordenadas son obligatorias y su ausencia es un rechazo propio (rc 3),
  # no una comparacion ambigua.
  recibo_ok > "$SB/recibo.json"
  ERR="$(entrega_validar "$SB/recibo.json" "$REPO" "$PR" "" 2>&1 >/dev/null)"; RC=$?
  [ "$RC" -eq 3 ] || _mal "entrega_validar con sha vacio debe salir 3, dio $RC"
  _contiene "nombra coordenadas vacias" "$ERR" "coordenadas vacias"
  ERR="$(entrega_recibo_del_pr "$REPO" "$PR" "" "op" 2>&1 >/dev/null)"; RC=$?
  [ "$RC" -eq 3 ] || _mal "entrega_recibo_del_pr con sha vacio debe salir 3, dio $RC"
  _contiene "nombra coordenadas vacias" "$ERR" "coordenadas vacias"
}
fin_caso "coordenadas_vacias_rechazadas"

caso "mutacion_revoke_dejado_de_bloquear_atrapada"
{
  # Mutante de A.R4: si el comentario mixto dejara de bloquearse (la escotilla
  # entrega_body_trae_revoke anulada), el mutante aprueba lo que el gate debe
  # rechazar: eso prueba que la asercion rc 1 del caso lado-1 es la que
  # atrapa la regla. Va al final a proposito, como su hermano de bloqueantes.
  (
    . "$LIB"
    entrega_body_trae_revoke() { return 1; }
    printf 'APPROVE lead %s\n\n```json\n{"schema":"saikit-entrega.v1","repo":"%s","pr":7,"sha":"%s","clase":"codigo","implementer":{"id":"a","evidencia":"e1"},"verifier":{"id":"b","resultado":"PASS","evidencia":"e2"},"reviewer":{"id":"c","resultado":"APPROVE","evidencia":"e3"},"ci":{"workflow":"ci","evidencia":"e4"},"bloqueantes":[],"residuales":[]}\n```\n' "$SHA" "$REPO" "$SHA" > "$SB/mut-c1.txt"
    printf '[%s]' "$(comentario_json "op" "$SB/mut-c1.txt")" > "$SB/mut-comments.json"
    export SAIKIT_GH_COMMENTS="$SB/mut-comments.json" SAIKIT_GH_API_FALLA=0
    if entrega_recibo_del_pr "$REPO" "$PR" "$SHA" "op" >/dev/null 2>&1; then
      printf 'MUTANTE-APRUEBA\n'
    else
      printf 'MUTANTE-RECHAZA\n'
    fi
  ) > "$SB/mut.out" 2>&1
  grep -q 'MUTANTE-APRUEBA' "$SB/mut.out" \
    || _mal "el mutante sigue rechazando: el caso no discrimina (ver arriba)"
}
fin_caso "mutacion_revoke_dejado_de_bloquear_atrapada"

caso "mutacion_sin_chequeo_bloqueantes_atrapada"
{
  # Si la comprobacion estructural se inutiliza, las regresiones de
  # contenedor-sin-hojas deben ponerse rojas (el mutante acepta lo que
  # el gate debe rechazar). El override vive en un subshell: no afecta
  # a otros casos. Al final va ultimo a proposito.
  (
    . "$LIB"
    entrega_bloqueantes_no_vacio() { return 1; }
    for variante in '[{}]' '[[]]' '{"x":[]}' '{"x":{}}'; do
      recibo_ok | sed "s/\"bloqueantes\":\[\]/\"bloqueantes\":$variante/" > "$SB/mut.json"
      if entrega_validar "$SB/mut.json" "$REPO" "$PR" "$SHA" >/dev/null 2>&1; then
        printf 'MUTANTE-ACEPTA %s\n' "$variante"
      else
        printf 'MUTANTE-SOBREVIVE %s\n' "$variante"
      fi
    done
    recibo_ok > "$SB/mut-ok.json"
    entrega_validar "$SB/mut-ok.json" "$REPO" "$PR" "$SHA" >/dev/null 2>&1 \
      || printf 'MUTANTE-ROTO recibo-valido\n'
  ) > "$SB/mut.out" 2>&1
  grep -q 'MUTANTE-SOBREVIVE\|MUTANTE-ROTO' "$SB/mut.out" \
    && _mal "mutacion no atrapada: $(tr '\n' ';' < "$SB/mut.out")"
  [ "$(grep -c 'MUTANTE-ACEPTA' "$SB/mut.out")" -eq 4 ] \
    || _mal "mutacion vacua (no acepto los 4): $(tr '\n' ';' < "$SB/mut.out")"
}
fin_caso "mutacion_sin_chequeo_bloqueantes_atrapada"

if [ "$fail" -ne 0 ]; then
  echo "test_entrega_contract: FAIL" >&2
  exit 1
fi
echo "test_entrega_contract: OK"
