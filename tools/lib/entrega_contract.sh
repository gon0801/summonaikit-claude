#!/usr/bin/env bash
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
#     el recibo. Hallazgos posteriores en prosa los adjudica el lead, no este
#     parser.
#   - v1: `bloqueantes` con CUALQUIER entrada es bloqueante abierto (un
#     bloqueante cerrado se quita de la lista, no se marca); `clase` solo se
#     exige presente y no vacia, y los tres roles se exigen siempre.
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

# entrega_validar <recibo|-stdin> <repo> <pr> <sha>
entrega_validar() {
  if [ "$#" -ne 4 ]; then
    printf 'recibo: uso: entrega_validar <recibo-json|-> <repo> <pr> <sha>\n' >&2
    return 3
  fi
  local origen="$1" repo="$2" pr="$3" sha="$4"
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

  local id_impl id_ver id_rev
  id_impl="$(entrega_flat_hoja "$flat" "implementer.id")" \
    || { printf 'recibo: falta implementer.id\n' >&2; return 1; }
  [ -n "$id_impl" ] && [ "$id_impl" != "<null>" ] \
    || { printf 'recibo: implementer.id vacio\n' >&2; return 1; }
  val="$(entrega_flat_hoja "$flat" "implementer.evidencia")" \
    || { printf 'recibo: falta implementer.evidencia\n' >&2; return 1; }
  [ -n "$val" ] && [ "$val" != "<null>" ] \
    || { printf 'recibo: implementer.evidencia vacia\n' >&2; return 1; }

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

  # bloqueantes: CUALQUIER entrada (escalar u objeto/array) es un bloqueante
  # abierto. Ausente o vacio pasa; el flat no distingue ambos y la relacion
  # que importa es "no hay bloqueantes declarados".
  if entrega_flat_hoja "$flat" "bloqueantes" >/dev/null 2>&1 || entrega_flat_prefijo "$flat" "bloqueantes"; then
    local primero n
    primero="$(printf '%s\n' "$flat" | awk -F'\t' '$1 == "bloqueantes" || index($1, "bloqueantes.") == 1 || index($1, "bloqueantes[") == 1 { print substr($2, 1, 120); exit }')"
    n="$(printf '%s\n' "$flat" | awk -F'\t' '
      $1 == "bloqueantes" { c++; next }
      index($1, "bloqueantes[") == 1 {
        rest = substr($1, 14); idx = ""
        while (substr(rest, 1, 1) ~ /^[0-9]$/) { idx = idx substr(rest, 1, 1); rest = substr(rest, 2) }
        if (idx != "" && !(idx in v)) { v[idx] = 1; c++ }
      }
      END { print c + 0 }')"
    printf 'recibo: bloqueante abierto (%s en la lista; primero: %s)\n' "$n" "$primero" >&2
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

# entrega_recibo_del_pr <repo> <pr> <sha> [lead]
entrega_recibo_del_pr() {
  if [ "$#" -lt 3 ] || [ "$#" -gt 4 ]; then
    printf 'recibo: uso: entrega_recibo_del_pr <repo> <pr> <sha> [lead]\n' >&2
    return 3
  fi
  local repo="$1" pr="$2" sha="$3" lead="${4:-}"
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
      # REVOKE posterior del mismo autor anula el candidato (fail-closed: un
      # REVOKE huerfano sin candidato no hace nada).
      if [ -n "$candidato" ] && [ "$login" = "$autor_candidato" ] \
         && printf '%s' "$body" | grep -Fq "REVOKE" \
         && printf '%s' "$body" | grep -Fq "$sha"; then
        revocado=1
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
