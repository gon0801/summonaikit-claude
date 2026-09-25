#!/usr/bin/env bash
# MARCA DE PROPIEDAD: `: <<'...'` es un no-op (no ejecuta, no cuesta fork).
# El instalador mide la propiedad con el PRIMER bloque `---` del archivo
# (zcode_agente_tiene_marca): sin ella, esta lib publicada globalmente
# (~/.claude/saikit-tools/lib) se clasificaba DESCONOCIDO en la segunda
# corrida y el instalador dejaba de tocarla para siempre.
: <<'SAIKIT_MARCA'
---
saikit_owned: summonaikit-claude
---
SAIKIT_MARCA
# tools/lib/entrega_contract.sh — contrato del recibo de entrega (Bloque A,
# entrega sin sello). Se carga con `. tools/lib/entrega_contract.sh`. Sin
# dependencias fuera de coreutils+awk+gh (SIN jq: no se puede asumir
# instalado). Lo usan `tests/test_entrega_contract.sh` y
# `tools/saikit-merge.sh`; el hook NO lo usa.
#
# El recibo vive FUERA del codigo del PR (comentario `APPROVE lead <sha>` con
# un bloque ```json), para no cambiar el SHA al documentar la aprobacion. La
# fuente duradera es GitHub; una copia local puede ayudar a reanudar, pero no
# sustituye la lectura actual del PR.
#
# Recibo minimo (schema saikit-entrega.v1):
#   { "schema", "repo", "pr", "sha", "clase",
#     "implementer": {"id", "evidencia"},
#     "verifier": {"id", "resultado", "evidencia"},
#     "reviewer": {"id", "resultado", "evidencia"},
#     "ci": {"workflow", "evidencia"},
#     "bloqueantes": [], "residuales": [] }
#
#   entrega_validar <recibo|-stdin> <repo> <pr> <sha>
#     0 cumple; 1 falta evidencia o hay bloqueante; 3 no se pudo leer la
#     fuente. Razon especifica en stderr.
#   entrega_recibo_del_pr <repo> <pr> <sha> [lead]
#     Imprime el JSON del ULTIMO recibo aplicable del PR a stdout; 0 hallado,
#     1 sin recibo o revocado, 3 API inaccesible o respuesta inutilizable.
#
# LIMITES DE ATRIBUCION (declarados, no promesas):
#   - El validador comprueba estructura y relaciones (coordenadas, roles
#     distintos, PASS/APPROVE, sin bloqueantes). NO prueba criptograficamente
#     la independencia de los agentes ni la verdad de la prosa: un nombre de
#     rol escrito por el lead no prueba que ocurrio. CI verifica ejecucion y
#     el lead verifica la procedencia de la evidencia enlazada.
#   - Los valores `artifact:` son ejemplos de fixture, no evidencia valida de
#     produccion: alla los enlaces deben resolver a reportes persistentes.
#   - Un comentario ambiguo, invalido o para otro SHA no aprueba nada: se
#     ignora y se sigue buscando. Un REVOKE posterior del mismo autor anula
#     el recibo; un REVOKE sin el sha completo avisa y no tiene efecto
#     (A.R3). Un comentario que trae REVOKE no aprueba nada, aunque tambien
#     traiga un APPROVE con bloque valido: revocar y volver a aprobar exige
#     dos comentarios (A.R4, regla decidida). Hallazgos posteriores en prosa
#     los adjudica el lead, no este parser.
#   - v1: `bloqueantes` con CUALQUIER entrada es bloqueante abierto (un
#     bloqueante cerrado se quita de la lista, no se marca). Las clases de
#     codigo/contrato exigen tres roles; editorial/ledger/progreso usan el
#     carril fast y no inventan verifier/reviewer. `ci.workflow` identifica la
#     bateria que el gate debe observar; `ci.evidencia` enlaza su resultado.
ENTREGA_SCHEMA="saikit-entrega.v1"

# Parser JSON compartido (tools/lib/veredicto_contract.sh). Esta lib es un
# consumidor mas: mientras tenga consumidores, el parser se conserva.
if [ -z "${SAIKIT_JSON_AWK:-}" ]; then
  # shellcheck disable=SC1091
  . "$(cd "$(dirname "${BASH_SOURCE[0]:-.}")" && pwd)/veredicto_contract.sh"
fi

# entrega_flat_hoja <flat> <ruta> — valor de la hoja exacta (rc 1 si ausente).
entrega_flat_hoja() {
  printf '%s\n' "$1" | awk -F'\t' -v p="$2" '$1 == p { print $2; found = 1; exit } END { exit found ? 0 : 1 }'
}

# entrega_flat_prefijo <flat> <prefijo> — 0 si hay hoja bajo prefijo. o prefijo[.
entrega_flat_prefijo() {
  printf '%s\n' "$1" | awk -F'\t' -v p="$2" '
    index($1, p ".") == 1 || index($1, p "[") == 1 { f = 1 }
    END { exit f ? 0 : 1 }
  '
}

# entrega_bloqueantes_no_vacio <json> — 0 si el campo de primer nivel
# "bloqueantes" existe y no es exactamente [] ni {} (ignorando blancos).
# El flat solo emite hojas escalares: [{}], [[]] o {"x":[]} no dejan hojas
# y pasarían como vacíos. Por eso se inspecciona el JSON original, sin jq:
# scanner awk consciente de strings/escapes. Solo vale la clave literal de
# primer nivel (la anidada o dentro de un string no cuenta). Sobre claves
# duplicadas no hay precedencia que documentar: el parser las RECHAZA
# (veredicto_contract.sh, "clave duplicada"), igual que rechaza '.'/'['/']'
# en las claves; el escaneo aqui no ve nunca un duplicado (A.R10).
entrega_bloqueantes_no_vacio() {
  printf '%s' "$1" | awk '
    function esp(c) { return c == " " || c == "\t" || c == "\n" || c == "\r" }
    { if (NR > 1) texto = texto "\n"; texto = texto $0 }
    END {
      n = length(texto); prof = 0; en_str = 0; esc = 0; i = 1
      while (i <= n) {
        c = substr(texto, i, 1)
        if (en_str) {
          if (esc) { esc = 0 }
          else if (c == "\\") { esc = 1 }
          else if (c == "\"") {
            en_str = 0
            if (prof == 1 && substr(texto, ini + 1, i - ini - 1) == "bloqueantes") {
              j = i + 1
              while (j <= n && esp(substr(texto, j, 1))) j++
              if (j <= n && substr(texto, j, 1) == ":") {
                k = j + 1
                while (k <= n && esp(substr(texto, k, 1))) k++
                vc = substr(texto, k, 1)
                if (vc == "{" || vc == "[") {
                  fin = k; p2 = 0; s2 = 0; e2 = 0
                  while (fin <= n) {
                    d = substr(texto, fin, 1)
                    if (s2) {
                      if (e2) { e2 = 0 }
                      else if (d == "\\") { e2 = 1 }
                      else if (d == "\"") { s2 = 0 }
                    } else {
                      if (d == "\"") { s2 = 1 }
                      else if (d == "{" || d == "[") { p2++ }
                      else if (d == "}" || d == "]") {
                        p2--
                        if (p2 == 0) break
                      }
                    }
                    fin++
                  }
                  v = substr(texto, k, fin - k + 1)
                } else {
                  fin = k; s2 = 0; e2 = 0
                  while (fin <= n) {
                    d = substr(texto, fin, 1)
                    if (s2) {
                      if (e2) { e2 = 0 }
                      else if (d == "\\") { e2 = 1 }
                      else if (d == "\"") { s2 = 0 }
                    } else if (d == "\"") { s2 = 1 }
                    else if (d == "," || d == "}" || d == "]") { break }
                    fin++
                  }
                  v = substr(texto, k, fin - k)
                }
                gsub(/[ \t\n\r]/, "", v)
                if (v == "[]" || v == "{}") exit 1
                exit 0
              }
            }
          }
        } else {
          if (c == "\"") { en_str = 1; ini = i }
          else if (c == "{" || c == "[") { prof++ }
          else if (c == "}" || c == "]") { prof-- }
        }
        i++
      }
      exit 1
    }
  '
}

# entrega_validar <recibo|-stdin> <repo> <pr> <sha>
entrega_validar() {
  if [ "$#" -ne 4 ]; then
    printf 'recibo: uso: entrega_validar <recibo-json|-> <repo> <pr> <sha>\n' >&2
    return 3
  fi
  local origen="$1" repo="$2" pr="$3" sha="$4"
  # A.R9(c): sin coordenadas no hay comparacion posible (un sha vacio haria
  # matchear cualquier recibo o ninguno con la misma frase ambigua).
  [ -n "$repo" ] && [ -n "$pr" ] && [ -n "$sha" ] \
    || { printf 'recibo: coordenadas vacias: repo, pr y sha son obligatorios\n' >&2; return 3; }
  local txt flat val motivo
  if [ "$origen" = "-" ]; then
    txt="$(cat)" || { printf 'recibo: no se pudo leer el recibo de stdin\n' >&2; return 3; }
  else
    [ -f "$origen" ] || { printf 'recibo: no se pudo leer el recibo (%s no existe o no es legible)\n' "$origen" >&2; return 3; }
    txt="$(cat "$origen")" || { printf 'recibo: no se pudo leer el recibo (%s)\n' "$origen" >&2; return 3; }
  fi
  if ! motivo="$(printf '%s' "$txt" | awk -v MODE=validate "$SAIKIT_JSON_AWK" 2>&1 >/dev/null)"; then
    printf 'recibo: JSON invalido: %s\n' "$motivo" >&2
    return 1
  fi
  flat="$(saikit_json_flat "$txt")"

  val="$(entrega_flat_hoja "$flat" "schema")" \
    || { printf 'recibo: falta el campo schema\n' >&2; return 1; }
  [ "$val" = "$ENTREGA_SCHEMA" ] \
    || { printf 'recibo: schema distinto (dio %s, se exige %s)\n' "$val" "$ENTREGA_SCHEMA" >&2; return 1; }

  val="$(entrega_flat_hoja "$flat" "repo")" \
    || { printf 'recibo: falta el campo repo\n' >&2; return 1; }
  [ "$val" = "$repo" ] \
    || { printf 'recibo: repo distinto (dio %s, se exige %s)\n' "$val" "$repo" >&2; return 1; }

  val="$(entrega_flat_hoja "$flat" "pr")" \
    || { printf 'recibo: falta el campo pr\n' >&2; return 1; }
  [ "$val" = "$pr" ] \
    || { printf 'recibo: pr distinto (dio %s, se exige %s)\n' "$val" "$pr" >&2; return 1; }

  val="$(entrega_flat_hoja "$flat" "sha")" \
    || { printf 'recibo: falta el campo sha\n' >&2; return 1; }
  [ "$val" = "$sha" ] \
    || { printf 'recibo: sha distinto (dio %s, se exige %s)\n' "$val" "$sha" >&2; return 1; }

  val="$(entrega_flat_hoja "$flat" "clase")" \
    || { printf 'recibo: falta el campo clase\n' >&2; return 1; }
  [ -n "$val" ] && [ "$val" != "<null>" ] \
    || { printf 'recibo: clase vacia\n' >&2; return 1; }
  local requiere_roles
  case "$val" in
    codigo|configuracion|bug|runbook|documentacion) requiere_roles=1 ;;
    editorial|ledger|progreso) requiere_roles=0 ;;
    *) printf 'recibo: clase desconocida (%s)\n' "$val" >&2; return 1 ;;
  esac

  local id_impl id_ver="" id_rev=""
  id_impl="$(entrega_flat_hoja "$flat" "implementer.id")" \
    || { printf 'recibo: falta implementer.id\n' >&2; return 1; }
  [ -n "$id_impl" ] && [ "$id_impl" != "<null>" ] \
    || { printf 'recibo: implementer.id vacio\n' >&2; return 1; }
  val="$(entrega_flat_hoja "$flat" "implementer.evidencia")" \
    || { printf 'recibo: falta implementer.evidencia\n' >&2; return 1; }
  [ -n "$val" ] && [ "$val" != "<null>" ] \
    || { printf 'recibo: implementer.evidencia vacia\n' >&2; return 1; }

  if [ "$requiere_roles" = 1 ]; then
    id_ver="$(entrega_flat_hoja "$flat" "verifier.id")" \
      || { printf 'recibo: falta verifier.id\n' >&2; return 1; }
    [ -n "$id_ver" ] && [ "$id_ver" != "<null>" ] \
      || { printf 'recibo: verifier.id vacio\n' >&2; return 1; }
    val="$(entrega_flat_hoja "$flat" "verifier.resultado")" \
      || { printf 'recibo: falta verifier.resultado\n' >&2; return 1; }
    [ "$val" = "PASS" ] \
      || { printf 'recibo: verifier.resultado distinto de PASS (dio %s)\n' "$val" >&2; return 1; }
    val="$(entrega_flat_hoja "$flat" "verifier.evidencia")" \
      || { printf 'recibo: falta verifier.evidencia\n' >&2; return 1; }
    [ -n "$val" ] && [ "$val" != "<null>" ] \
      || { printf 'recibo: verifier.evidencia vacia\n' >&2; return 1; }

    id_rev="$(entrega_flat_hoja "$flat" "reviewer.id")" \
      || { printf 'recibo: falta reviewer.id (sin revision independiente no hay entrega)\n' >&2; return 1; }
    [ -n "$id_rev" ] && [ "$id_rev" != "<null>" ] \
      || { printf 'recibo: reviewer.id vacio (sin revision independiente no hay entrega)\n' >&2; return 1; }
    val="$(entrega_flat_hoja "$flat" "reviewer.resultado")" \
      || { printf 'recibo: falta reviewer.resultado\n' >&2; return 1; }
    [ "$val" = "APPROVE" ] \
      || { printf 'recibo: reviewer.resultado distinto de APPROVE (dio %s)\n' "$val" >&2; return 1; }
    val="$(entrega_flat_hoja "$flat" "reviewer.evidencia")" \
      || { printf 'recibo: falta reviewer.evidencia\n' >&2; return 1; }
    [ -n "$val" ] && [ "$val" != "<null>" ] \
      || { printf 'recibo: reviewer.evidencia vacia\n' >&2; return 1; }

    if [ "$id_impl" = "$id_ver" ] || [ "$id_impl" = "$id_rev" ] || [ "$id_ver" = "$id_rev" ]; then
      printf 'recibo: identidad reutilizada en roles independientes (implementer=%s verifier=%s reviewer=%s)\n' "$id_impl" "$id_ver" "$id_rev" >&2
      return 1
    fi
  fi

  val="$(entrega_flat_hoja "$flat" "ci.workflow")" \
    || { printf 'recibo: falta ci.workflow\n' >&2; return 1; }
  [ -n "$val" ] && [ "$val" != "<null>" ] \
    || { printf 'recibo: ci.workflow vacio\n' >&2; return 1; }
  val="$(entrega_flat_hoja "$flat" "ci.evidencia")" \
    || { printf 'recibo: falta ci.evidencia\n' >&2; return 1; }
  [ -n "$val" ] && [ "$val" != "<null>" ] \
    || { printf 'recibo: ci.evidencia vacia\n' >&2; return 1; }

  # bloqueantes: CUALQUIER entrada (escalar u objeto/array) es un bloqueante
  # abierto. Ausente o vacio pasa; el flat no distingue ambos y la relacion
  # que importa es "no hay bloqueantes declarados". Los contenedores sin
  # hojas ([{}], [[]], {"x":[]}) no dejan rastro en el flat y se juzgan
  # por estructura mas abajo.
  if entrega_flat_hoja "$flat" "bloqueantes" >/dev/null 2>&1 || entrega_flat_prefijo "$flat" "bloqueantes"; then
    local primero n
    primero="$(printf '%s\n' "$flat" | awk -F'\t' '$1 == "bloqueantes" || index($1, "bloqueantes.") == 1 || index($1, "bloqueantes[") == 1 { print substr($2, 1, 120); exit }')"
    # A.R2: el indice empieza detras de "bloqueantes[" (12 caracteres); el
    # substr viejo (14) se comia el digito de los indices <10 y el mensaje
    # decia "0 en la lista" habiendo entradas.
    n="$(printf '%s\n' "$flat" | awk -F'\t' '
      $1 == "bloqueantes" { c++; next }
      index($1, "bloqueantes[") == 1 {
        rest = substr($1, 13); idx = ""
        while (substr(rest, 1, 1) ~ /^[0-9]$/) { idx = idx substr(rest, 1, 1); rest = substr(rest, 2) }
        if (idx != "" && !(idx in v)) { v[idx] = 1; c++ }
      }
      END { print c + 0 }')"
    printf 'recibo: bloqueante abierto (%s en la lista; primero: %s)\n' "$n" "$primero" >&2
    return 1
  fi
  if entrega_bloqueantes_no_vacio "$txt"; then
    printf 'recibo: bloqueante abierto (bloqueantes trae entradas)\n' >&2
    return 1
  fi
  # residuales: no bloquean nunca; se aceptan en cualquier forma.
  return 0
}

# entrega_bloque_json <texto> <n> — imprime el n-esimo bloque ```json del texto.
entrega_bloque_json() {  # $1=texto $2=indice(1-based) -> stdout el bloque
  printf '%s' "$1" | awk -v want="$2" '
    /^```json/ { cap++; buf = ""; next }
    cap == want && /^```/ { printf "%s", buf; exit }
    cap == want { buf = buf $0 "\n" }
  '
}

# entrega_body_trae_revoke <body> — 0 si el comentario lleva intencion de
# revocar. Escotilla SOLO de prueba: la mutacion de A.R4 la anula para
# comprobar que el caso de rechazo es el que atrapa la regla.
entrega_body_trae_revoke() {
  printf '%s' "$1" | grep -Fq "REVOKE"
}

# entrega_recibo_del_pr <repo> <pr> <sha> [lead]
entrega_recibo_del_pr() {
  if [ "$#" -lt 3 ] || [ "$#" -gt 4 ]; then
    printf 'recibo: uso: entrega_recibo_del_pr <repo> <pr> <sha> [lead]\n' >&2
    return 3
  fi
  local repo="$1" pr="$2" sha="$3" lead="${4:-}"
  # A.R9(c): con sha vacio, grep -Fq "" matchea cualquier cuerpo y un
  # "APPROVE lead " sin sha podria aprobar cualquier comentario.
  [ -n "$repo" ] && [ -n "$pr" ] && [ -n "$sha" ] \
    || { printf 'recibo: coordenadas vacias: repo, pr y sha son obligatorios\n' >&2; return 3; }
  local raw rc
  raw="$(gh api "repos/$repo/issues/$pr/comments" --paginate 2>/dev/null)" && rc=0 || rc=$?
  if [ "$rc" -ne 0 ]; then
    printf 'recibo: no se pudo consultar los comentarios del PR %s#%s (gh api fallo)\n' "$repo" "$pr" >&2
    return 3
  fi
  # Vacio o solo blanco: la API respondio algo inutilizable — desconocido, no
  # "sin recibo" (una respuesta truncada no puede leerse como ausencia).
  case "$raw" in
    *[![:space:]]*) ;;
    *) printf 'recibo: no se pudo consultar los comentarios del PR %s#%s (respuesta vacia)\n' "$repo" "$pr" >&2; return 3 ;;
  esac
  # --paginate concatena una pagina JSON por linea (compacto, una linea por
  # pagina con el color neutralizado). Cada pagina se juzga aparte, en orden.
  local candidato="" autor_candidato="" revocado=0
  local pagina flat n i login body bloque nb schema
  while IFS= read -r pagina || [ -n "$pagina" ]; do
    case "$pagina" in *[![:space:]]*) ;; *) continue ;; esac
    saikit_json_valido "$pagina" \
      || { printf 'recibo: no se pudo consultar los comentarios del PR %s#%s (pagina no-JSON)\n' "$repo" "$pr" >&2; return 3; }
    # A.R5: la pagina tiene que ser una LISTA de comentarios. Un objeto
    # JSON-valido (por ejemplo un error de la API) aplanaria a cero hojas [i]
    # y se leeria como "sin comentarios": una respuesta inutilizable no puede
    # leerse como ausencia.
    primer_char="$(printf '%s' "$pagina" | awk '{ for (j = 1; j <= length($0); j++) { c = substr($0, j, 1); if (c != " " && c != "\t" && c != "\r") { print c; exit } } }')"
    [ "$primer_char" = "[" ] \
      || { printf 'recibo: no se pudo consultar los comentarios del PR %s#%s (la pagina no es una lista de comentarios)\n' "$repo" "$pr" >&2; return 3; }
    flat="$(saikit_json_flat "$pagina")"
    # Cuenta por el mayor indice [i] del flat, no por .body presente: un
    # comentario sin body no debe ocultar a los siguientes. [] aplana a nada.
    n="$(printf '%s\n' "$flat" | awk -F'\t' '
      index($1, "[") == 1 {
        r = substr($1, 2); idx = ""
        while (substr(r, 1, 1) ~ /^[0-9]$/) { idx = idx substr(r, 1, 1); r = substr(r, 2) }
        if (idx != "" && substr(r, 1, 1) == "]") { found = 1; if (idx + 0 > max + 0) max = idx }
      }
      END { if (found) print max + 1; else print 0 }')"
    i=0
    while [ "$i" -lt "$n" ]; do
      login="$(entrega_flat_hoja "$flat" "[$i].user.login" 2>/dev/null)" || login=""
      body="$(entrega_flat_hoja "$flat" "[$i].body" 2>/dev/null)" || body=""
      # El aplanador re-escapa (\\, \t, \n, \r): printf %b lo revierte exacto.
      # shellcheck disable=SC2059
      body="$(printf '%b' "$body")"
      if [ -n "$lead" ] && [ "$login" != "$lead" ]; then i=$((i + 1)); continue; fi
      # A.R3 + A.R4: un comentario que trae REVOKE se juzga entero y no
      # aprueba nada. Con el sha completo anula el recibo vigente del mismo
      # autor (como siempre); SIN el sha completo no tiene efecto y se avisa,
      # para que el operador no crea haber revocado. En cualquier caso el
      # comentario es ambiguo para su propio APPROVE: revocar y volver a
      # aprobar exige dos comentarios.
      if entrega_body_trae_revoke "$body"; then
        if [ -n "$candidato" ] && [ "$login" = "$autor_candidato" ]; then
          if printf '%s' "$body" | grep -Fq "$sha"; then
            revocado=1
          else
            printf 'recibo: aviso: REVOKE visto sin efecto: el comentario de %s no trae el sha completo (%s); el recibo sigue vivo\n' "$login" "$sha" >&2
          fi
        fi
        i=$((i + 1)); continue
      fi
      if printf '%s' "$body" | grep -Fq "APPROVE lead $sha"; then
        nb=1
        while bloque="$(entrega_bloque_json "$body" "$nb")" && [ -n "$bloque" ]; do
          if saikit_json_valido "$bloque" \
             && schema="$(saikit_json_get "$bloque" "schema" 2>/dev/null)" \
             && [ "$schema" = "$ENTREGA_SCHEMA" ]; then
            candidato="$bloque"; autor_candidato="$login"; revocado=0
            break
          fi
          nb=$((nb + 1))
        done
      fi
      i=$((i + 1))
    done
  done <<PAGINAS
$raw
PAGINAS
  if [ -z "$candidato" ]; then
    printf 'recibo: sin recibo: el PR %s#%s no trae un comentario APPROVE lead %s con entrega %s\n' "$repo" "$pr" "$sha" "$ENTREGA_SCHEMA" >&2
    return 1
  fi
  if [ "$revocado" = 1 ]; then
    printf 'recibo: revocado: el recibo de %s quedo anulado por un REVOKE posterior del mismo autor\n' "$sha" >&2
    return 1
  fi
  printf '%s' "$candidato"
  return 0
}
