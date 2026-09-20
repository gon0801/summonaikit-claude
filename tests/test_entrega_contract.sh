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
{"schema":"saikit-entrega.v1","repo":"$REPO","pr":7,"sha":"$SHA","clase":"codigo","implementer":{"id":"worker-a","evidencia":"artifact:implementacion"},"verifier":{"id":"worker-b","resultado":"PASS","evidencia":"artifact:verificacion"},"reviewer":{"id":"worker-c","resultado":"APPROVE","evidencia":"artifact:revision"},"bloqueantes":[],"residuales":[]}
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
    printf '{"schema":"saikit-entrega.v1","repo":"%s","pr":7,"sha":"%s","clase":"codigo","implementer":{"id":"a","evidencia":"e1"},"verifier":{"id":"b","resultado":"PASS","evidencia":"e2"},"reviewer":{"id":"c","resultado":"APPROVE","evidencia":"e3"},"bloqueantes":[],"residuales":[]}\n' "$REPO" "$SHA"
    printf '```\n'
  } > "$SB/c2.txt"
  {
    printf 'APPROVE lead %s\n\ncorreccion: evidencia final\n\n```json\n' "$SHA"
    printf '{"schema":"saikit-entrega.v1","repo":"%s","pr":7,"sha":"%s","clase":"codigo","implementer":{"id":"a2","evidencia":"e1"},"verifier":{"id":"b2","resultado":"PASS","evidencia":"e2"},"reviewer":{"id":"c2","resultado":"APPROVE","evidencia":"e3"},"bloqueantes":[],"residuales":[]}\n' "$REPO" "$SHA"
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
    printf '{"schema":"saikit-entrega.v1","repo":"%s","pr":7,"sha":"%s","clase":"codigo","implementer":{"id":"a","evidencia":"e1"},"verifier":{"id":"b","resultado":"PASS","evidencia":"e2"},"reviewer":{"id":"c","resultado":"APPROVE","evidencia":"e3"},"bloqueantes":[],"residuales":[]}\n' "$REPO" "$SHA"
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
    printf '{"schema":"saikit-entrega.v1","repo":"%s","pr":7,"sha":"%s","clase":"codigo","implementer":{"id":"a","evidencia":"e1"},"verifier":{"id":"b","resultado":"PASS","evidencia":"e2"},"reviewer":{"id":"c","resultado":"APPROVE","evidencia":"e3"},"bloqueantes":[],"residuales":[]}\n' "$REPO" "$SHA"
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

if [ "$fail" -ne 0 ]; then
  echo "test_entrega_contract: FAIL" >&2
  exit 1
fi
echo "test_entrega_contract: OK"
