#!/usr/bin/env bash
# tools/lib/veredicto_contract.sh — contrato/esquema del veredicto sellado
# (D16). Se carga con `. tools/lib/veredicto_contract.sh`. Sin dependencias
# fuera de coreutils+awk (SIN jq: no se puede asumir instalado). Lo usan
# `tests/test_veredicto_contract.sh` y `tools/saikit-merge.sh` (Task 18.4);
# el hook NO lo usa — el hook solo SELLA, no valida (la validacion es del
# merge, que corre tras el veredicto ya sellado; D16/D18).
#
# Esquema del veredicto (`.saikit/veredictos/<sha>.json`):
#   { "sha", "pr", "verifier", "verify_app":{resultado,comando},
#     "blast":{nivel,hecho,comando}|{omitido:"<razon no vacia>"},
#     "adversary":{findings,max_sev}|"n/a", "reviewer", "decisiones" }
# blast es XOR de dos formas (Task 18.17): la triada cuando corrio, o
# {"omitido"} con la razon cuando el turno no lo corrio. El escalar "n/a" NO
# vale para blast (trampa D13: el PR #157 lo sello asi por analogia con
# adversary); una razon vacia, null o "n/a" tampoco.
#
# `veredicto_validar` valida el CONTRATO ESTRUCTURAL: es un objeto JSON
# (parseado con un parser JSON real en awk, no grep — el limite POC de la
# 18.3 se cerro en la 18.4), estan los campos requeridos — las claves
# CONTENEDOR y sus HOJAS en su nivel — y el sha del veredicto coincide con el
# HEAD dado. No juzga los VALORES semantico-sesion (verifier=PASS,
# blast.nivel>=4, ...) — eso es del merge (D18), que los exige ademas del
# contrato. Postura de falla: report + exit 1 (invalido), nunca exit 0 por
# ausencia (un veredicto que no se pudo leer no es "valido" por defecto,
# Core Rule 2).
#
# Ademas del contrato, la lib expone el parser para el resto del flujo del
# merge (gh falso o real, `.saikit/autopilot.json`):
#   saikit_json_valido <texto>   — 0 si es JSON valido (cualquier valor raiz).
#   saikit_json_flat  <texto>    — una linea `ruta\tvalor` por hoja escalar
#                                  (arrays como ruta[0], raiz "" excluida;
#                                  null se emite como el marcador <null>).
#   saikit_json_get   <texto> <ruta> — valor de la hoja en esa ruta (primera
#                                  ocurrencia), rc 1 si la ruta no existe.

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

# Hojas del contrato, expuestas para que tests/test_veredicto_contract.sh acople
# el perfil del reviewer a lo que el validador exige de verdad (18.17).
VEREDICTO_HOJAS_REQUERIDAS='sha pr verifier reviewer decisiones verify_app.resultado verify_app.comando'
VEREDICTO_BLAST_TRIADA='blast.nivel blast.hecho blast.comando'
VEREDICTO_BLAST_OMITIDO='blast.omitido'

# veredicto_tiene_hoja <flat> <ruta> — 0 si la ruta EXACTA existe en el flat.
veredicto_tiene_hoja() {
  printf '%s\n' "$1" | awk -F'\t' -v p="$2" '$1 == p { f = 1 } END { exit f ? 0 : 1 }'
}

# veredicto_tiene_prefijo <flat> <prefijo> — 0 si hay hoja exacta o anidada
# bajo prefijo. (prefijo. o prefijo[). Cierra mezcla omitido+nivel-objeto.
veredicto_tiene_prefijo() {
  printf '%s\n' "$1" | awk -F'\t' -v p="$2" '
    $1 == p || index($1, p ".") == 1 || index($1, p "[") == 1 { f = 1 }
    END { exit f ? 0 : 1 }
  '
}

# veredicto_validar <archivo> [head]
#   0 => valido (esquema + sha==head si head viene).
#   1 => invalido, con un motivo en stdout.
veredicto_validar() {
  local f="$1" head="${2:-}" txt="" flat="" campo sha razon
  local IFS=' '
  [ -f "$f" ] || { printf 'no existe el veredicto: %s\n' "$f"; return 1; }
  # Listas vacias = fail-open (Core Rule 2): un mutante o source raro no
  # puede dejar el contrato sin dientes.
  if [ -z "${VEREDICTO_HOJAS_REQUERIDAS:-}" ] || [ -z "${VEREDICTO_BLAST_TRIADA:-}" ] || [ -z "${VEREDICTO_BLAST_OMITIDO:-}" ]; then
    printf 'contrato incompleto: faltan las listas VEREDICTO_*\n'
    return 1
  fi
  txt="$(sed 's/\r$//' "$f")"   # CR de fin de linea (CRLF); un CR a media string lo rechaza el parser

  # Parser JSON real: un veredicto que no parsea ES invalido, aunque traiga
  # los textos de todas las claves (el limite POC por grep, cerrado en 18.4).
  if ! flat="$(printf '%s' "$txt" | awk -v MODE=flat "$SAIKIT_JSON_AWK" 2>&1 >/dev/null)"; then
    printf 'no es un JSON valido: %s\n' "$flat"
    return 1
  fi
  flat="$(saikit_json_flat "$txt")"

  # Hojas requeridas por ruta EXACTA (verify_app queda cubierto por sus hojas;
  # verify_app.comando puede valer <null>, la RUTA tiene que existir). El
  # contenedor adversary se exige aparte, abajo: puede ser "n/a" (hoja) u
  # objeto (prefijo de hojas). blast va aparte tambien: XOR de dos formas.
  for campo in $VEREDICTO_HOJAS_REQUERIDAS; do
    if ! veredicto_tiene_hoja "$flat" "$campo"; then
      printf 'falta el campo %s\n' "$campo"
      return 1
    fi
  done

  # blast: escalar => invalido con guia; omitido => sin triada y con razon;
  # si no, la triada completa.
  if veredicto_tiene_hoja "$flat" blast; then
    printf 'blast es un escalar, no un objeto: si el turno no corrio blast, escribe {"omitido": "<razon>"}\n'
    return 1
  elif veredicto_tiene_hoja "$flat" "$VEREDICTO_BLAST_OMITIDO"; then
    for campo in $VEREDICTO_BLAST_TRIADA; do
      if veredicto_tiene_prefijo "$flat" "$campo"; then
        printf 'blast mezcla omitido con %s: es la triada nivel/hecho/comando O solo omitido\n' "$campo"
        return 1
      fi
    done
    # Los escapes del flat (\t \n \r) cuentan como blanco. Placeholders
    # (bool/numero/n-a/template) y backslash (\\uXXXX no se decodifica) no
    # son rastro. Piso de longitud >= 8.
    razon="$(printf '%s\n' "$flat" | awk -F'\t' -v p="$VEREDICTO_BLAST_OMITIDO" '$1 == p { print $2; exit }' \
      | sed 's/\\[tnr]/ /g; s/^[[:space:]]*//; s/[[:space:]]*$//' | tr '[:upper:]' '[:lower:]')"
    case "$razon" in
      ''|'<null>'|'n/a'|'-'|'na'|'none'|'omitido'|'skip'|'true'|'false'|'.'|'tbd')
        printf 'blast.omitido sin razon (vacio, null o placeholder): di por que no corrio el blast\n'
        return 1 ;;
    esac
    case "$razon" in
      '<'*'>')
        printf 'blast.omitido sin razon (placeholder de plantilla): di por que no corrio el blast\n'
        return 1 ;;
    esac
    case "$razon" in
      *'\\'*)
        printf 'blast.omitido sin razon (escape en el valor): di por que no corrio el blast\n'
        return 1 ;;
    esac
    if [ "${#razon}" -lt 8 ]; then
      printf 'blast.omitido sin razon (demasiado corta): di por que no corrio el blast\n'
      return 1
    fi
  else
    for campo in $VEREDICTO_BLAST_TRIADA; do
      if ! veredicto_tiene_hoja "$flat" "$campo"; then
        printf 'falta el campo %s (o blast.omitido con la razon, si el turno no corrio blast)\n' "$campo"
        return 1
      fi
    done
  fi
  if ! printf '%s\n' "$flat" | awk -F'\t' '$1 == "adversary" || index($1, "adversary.") == 1 || index($1, "adversary[") == 1 { f = 1 } END { exit f ? 0 : 1 }'; then
    printf 'falta el campo adversary\n'
    return 1
  fi

  # sha == HEAD (si head viene). La ruta exacta `sha` (primer nivel) es la
  # que manda: un sha anidado en otro objeto no cuenta.
  if [ -n "$head" ]; then
    sha="$(printf '%s\n' "$flat" | awk -F'\t' '$1 == "sha" { print $2; exit }')"
    if [ -z "$sha" ] || [ "$sha" = "<null>" ]; then
      printf 'el veredicto no trae un sha legible\n'
      return 1
    fi
    if [ "$sha" != "$head" ]; then
      printf 'el sha del veredicto (%s) no coincide con HEAD (%s)\n' "$sha" "$head"
      return 1
    fi
  fi
  return 0
}
