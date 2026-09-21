#!/usr/bin/env bash
# tools/lib/veredicto_contract.sh — parser JSON compartido (sin jq).
#
# El esquema sellado quedo RETIRADO (Bloque A: la entrega se valida con el
# recibo del PR, tools/lib/entrega_contract.sh). Lo que queda es el parser
# JSON real en awk (RFC 8259 estricto, sin dependencias fuera de coreutils),
# que se CONSERVA porque sigue teniendo consumidores: entrega_contract.sh,
# saikit-merge.sh, saikit-setup-autopilot.sh, saikit-postmerge.sh y sus tests.
#   saikit_json_valido <texto>   — 0 si es JSON valido (cualquier valor raiz).
#   saikit_json_flat  <texto>    — una linea `ruta\tvalor` por hoja escalar
#                                  (arrays como ruta[0], raiz "" excluida;
#                                  null se emite como el marcador <null>).
#   saikit_json_get   <texto> <ruta> — valor de la hoja en esa ruta (primera
#                                  ocurrencia), rc 1 si la ruta no existe.
#
# ---------------------------------------------------------------------------
# Parser JSON (awk). Recursivo por tabla: parseValue/parseObject/parseArray se
# llaman entre si; awk soporta recursion mutua cuando las funciones estan
# definidas en el mismo programa. Estricto segun RFC 8259:
#   - claves y strings entre comillas dobles, escapes \" \\ \/ \b \f \n \r \t
#     y \uXXXX (4 hex); control char crudo dentro de un string => error;
#   - numeros sin cero inicial, con fraccion/exponente completos;
#   - true/false/null literales; sin coma colgante; sin basura al final;
#   - rechaza claves duplicadas y claves con '.'/'['/']' (el namespace del
#     flat; hallazgos de codex en el cross-review del PR #142), y rechaza toda
#     clave que traiga un ESCAPE: sin decodificar, "\u002e" y "\u0061" burlaban
#     esas dos guardas (CodeRabbit, PR #142). En un VALOR el escape es legitimo.
# Los \uXXXX se VALIDAN pero no se decodifican (el contenido de veredicto
# medido es ASCII; decodificar Unicode en awk no es portable).
# ---------------------------------------------------------------------------
SAIKIT_JSON_AWK="$(cat <<'AWK'
function ws() { while (i <= n) { c = substr(s, i, 1); if (c == " " || c == "\t" || c == "\r" || c == "\n") i++; else break } }
function hex4(h,   k) { if (length(h) != 4) return 0; for (k = 1; k <= 4; k++) if (substr(h, k, 1) !~ /^[0-9A-Fa-f]$/) return 0; return 1 }
function parseString(   c, e, out) {
  i++; out = ""
  while (i <= n) {
    c = substr(s, i, 1)
    if (c == "\"") { i++; return out }
    if (c == "\\") {
      e = substr(s, i + 1, 1)
      if (e == "\"") { out = out "\""; i += 2 }
      else if (e == "\\") { out = out "\\"; i += 2 }
      else if (e == "/") { out = out "/"; i += 2 }
      else if (e == "b") { out = out "\b"; i += 2 }
      else if (e == "f") { out = out "\f"; i += 2 }
      else if (e == "n") { out = out "\n"; i += 2 }
      else if (e == "r") { out = out "\r"; i += 2 }
      else if (e == "t") { out = out "\t"; i += 2 }
      else if (e == "u") { if (!hex4(substr(s, i + 2, 4))) { err = "escape \\uXXXX invalido en " i; return "" }; out = out substr(s, i, 6); i += 6 }
      else { err = "escape invalido en " i; return "" }
    } else if (c < " ") {
      # RFC 8259: TODO U+0000-U+001F crudo esta prohibido en strings, no
      # solo LF/CR/TAB (hallazgo de codex, cross-review PR #142).
      err = "control char crudo en string en " i; return ""
    } else { out = out c; i++ }
  }
  err = "string sin cerrar en " i; return ""
}
function parseNumber(   j) {
  j = i
  if (substr(s, i, 1) == "-") i++
  if (substr(s, i, 1) == "0") i++
  else if (substr(s, i, 1) ~ /^[1-9]$/) { while (substr(s, i, 1) ~ /^[0-9]$/) i++ }
  else { err = "numero invalido en " j; return "" }
  if (substr(s, i, 1) == ".") { i++; if (substr(s, i, 1) !~ /^[0-9]$/) { err = "fraccion invalida en " i; return "" }; while (substr(s, i, 1) ~ /^[0-9]$/) i++ }
  if (substr(s, i, 1) ~ /^[eE]$/) { i++; if (substr(s, i, 1) ~ /^[+-]$/) i++; if (substr(s, i, 1) !~ /^[0-9]$/) { err = "exponente invalido en " i; return "" }; while (substr(s, i, 1) ~ /^[0-9]$/) i++ }
  return substr(s, j, i - j)
}
function parseLiteral(lit) { if (substr(s, i, length(lit)) == lit) { i += length(lit); return lit }; err = "literal invalido en " i; return "" }
function emit(p, v) {
  # El valor se re-escapa (\\, tab, LF, CR): un tab/newline crudo partiria la
  # linea `ruta\tvalor` y saikit_json_get devolveria el valor truncado
  # (hallazgo de qwen, cross-review PR #142). Los consumidores del gate
  # comparan enums/shas/comandos ASCII: el re-escape es inocuo y el formato
  # queda inambiguo.
  gsub(/\\/, "\\\\", v); gsub(/\t/, "\\t", v); gsub(/\n/, "\\n", v); gsub(/\r/, "\\r", v)
  if (MODE == "flat" && p != "") print p "\t" v
}
function parseValue(p,   c, v) {
  ws(); c = substr(s, i, 1)
  if (c == "{") { parseObject(p); return }
  if (c == "[") { parseArray(p); return }
  if (c == "\"") { v = parseString(); if (err) return; emit(p, v); return }
  if (c == "-" || c ~ /^[0-9]$/) { v = parseNumber(); if (err) return; emit(p, v); return }
  if (c == "t") { v = parseLiteral("true"); if (!err) emit(p, v); return }
  if (c == "f") { v = parseLiteral("false"); if (!err) emit(p, v); return }
  if (c == "n") { v = parseLiteral("null"); if (!err) emit(p, "<null>"); return }
  err = "valor inesperado en " i
}
function parseObject(p,   seen, k, kp, c2) {
  i++
  ws()
  if (substr(s, i, 1) == "}") { i++; return }
  seen = "\n"
  while (1) {
    ws()
    if (substr(s, i, 1) != "\"") { err = "clave sin comillas en " i; return }
    k = parseString(); if (err) return
    # El aplanado arma rutas con '.' y '[]': una clave que los contenga
    # falsifica rutas anidadas ("verify_app.resultado" pasando por hoja).
    # Y una clave DUPLICADA es ambigua entre consumidores — en un gate
    # fail-closed se rechaza en vez de elegir una en silencio (codex #1/#2).
    # Un escape en la CLAVE burla las DOS guardas de abajo, porque parseString
    # NO decodifica: "\u002e" no lleva un '.' literal y "\u0061" no colisiona
    # con "a" en `seen`. En un gate fail-closed una clave escapada no se
    # interpreta: se RECHAZA (CodeRabbit, PR #142). Las claves del esquema son
    # ASCII planas; el escape en un VALOR sigue siendo legitimo.
    if (index(k, "\\")) { err = "clave con escape (no se interpreta en un gate): " k; return }
    if (index(k, ".") || index(k, "[") || index(k, "]")) { err = "clave con . o corchetes en " i; return }
    if (index(seen, "\n" k "\n")) { err = "clave duplicada: " k; return }
    seen = seen k "\n"
    ws()
    if (substr(s, i, 1) != ":") { err = "falta : en " i; return }
    i++
    kp = (p == "" ? k : p "." k)
    parseValue(kp); if (err) return
    ws()
    c2 = substr(s, i, 1)
    if (c2 == ",") { i++; continue }
    if (c2 == "}") { i++; return }
    err = "se esperaba , o } en " i; return
  }
}
function parseArray(p,   idx, c2) {
  i++
  ws()
  if (substr(s, i, 1) == "]") { i++; return }
  idx = 0
  while (1) {
    parseValue(p "[" idx "]"); if (err) return
    ws()
    c2 = substr(s, i, 1)
    if (c2 == ",") { i++; idx++; continue }
    if (c2 == "]") { i++; return }
    err = "se esperaba , o ] en " i; return
  }
}
BEGIN { s = ""; err = "" }
{ s = s $0 "\n" }
END {
  n = length(s); i = 1
  parseValue("")
  if (!err) { ws(); if (i <= n && substr(s, i, 1) != "") err = "basura tras el JSON en " i }
  if (err) { print "JSON-INVALIDO: " err > "/dev/stderr"; exit 1 }
}
AWK
)"

# saikit_json_valido <texto> — 0 si el texto completo es un JSON valido.
saikit_json_valido() {
  printf '%s' "$1" | awk -v MODE=validate "$SAIKIT_JSON_AWK" 2>/dev/null
}

# saikit_json_flat <texto> — lineas `ruta\tvalor` por hoja escalar.
saikit_json_flat() {
  printf '%s' "$1" | awk -v MODE=flat "$SAIKIT_JSON_AWK" 2>/dev/null
}

# saikit_json_get <texto> <ruta> — valor de la hoja (rc 1 si no existe).
saikit_json_get() {
  saikit_json_flat "$1" | awk -F'\t' -v p="$2" '$1 == p { print $2; found = 1; exit } END { exit found ? 0 : 1 }'
}
