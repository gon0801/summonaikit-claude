#!/usr/bin/env bash
# Deteccion de secretos antes del commit — item "Recommended" de Plans.md
# ("CI + pre-commit con deteccion de secretos en este repo"): el hook de este
# repo corre en CADA turno y nada impedia instalarlo desde una rama con un
# secreto adentro.
#
# Dos motores, primero el estandar si esta disponible:
#
#   1. gitleaks (en PATH, o la ruta exacta en $SAIKIT_GITLEAKS) sobre los
#      archivos recibidos. Config default: medida 2026-08-15 sobre los 179
#      commits del repo da 0 hallazgos (las credenciales FALSAS de los tests
#      de redaccion no matchean sus reglas) y ATRAPA trampas reales
#      (ghp_/AKIA/sk-proj), o sea que el verde no es por inerte.
#   2. Fallback grep best-effort, cero dependencias: los mismos patrones de
#      la familia que el hook ya redacta (redact_secrets, Task 3.5) mas los
#      formatos conocidos de token. Es MAS BRUTO que gitleaks y por eso solo
#      a este motor se le excluyen las rutas que cargan falsos a proposito
#      (tests/, docs/, Plans.md): a gitleaks no se le excluye nada.
#
# Uso: check-secrets.sh <archivo>...
# pre-commit pasa los archivos staged; el test del repo pasa archivos de su
# sandbox. Sin archivo no hay nada que afirmar: exit 2.
#
# El reporte NUNCA imprime la linea encontrada (seria filtrar el secreto que
# viene a impedir): solo archivo y numero de linea.
set -u

GL_BIN="$(command -v gitleaks 2>/dev/null || true)"
if [ -z "$GL_BIN" ] && [ -n "${SAIKIT_GITLEAKS:-}" ] && [ -x "$SAIKIT_GITLEAKS" ]; then
  GL_BIN="$SAIKIT_GITLEAKS"
fi

if [ "$#" -eq 0 ]; then
  echo "check-secrets: falta al menos un archivo" >&2
  exit 2
fi

# Los archivos borrados (staged como deleted) llegan como nombres que ya no
# existen: no hay nada que escanear en ellos.
archivos=()
for a in "$@"; do
  [ -f "$a" ] && archivos+=("$a")
done
if [ "${#archivos[@]}" -eq 0 ]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# Motor 1: gitleaks. --config explicita (la allowlist de tests/ vive junto al
# repo, no al cwd de quien llame); --redact para que ni el stdout de un
# hallazgo filtre el valor; el exit code es el veredicto (--exit-code 1 es el
# default, se declara para que la lectura no dependa de acordarse del default).
#
# UNA INVOCACION POR ARCHIVO, no una con todos: con 2+ fuentes `gitleaks dir`
# escanea el DIRECTORIO de la ultima (medido 2026-08-15 con 8.30.1: paso dos
# archivos limpios y reporto una trampa hermana JAMAS pasada como argumento —
# hallazgo Greptile P1 / CodeRabbit del PR #24). Con una sola fuente escanea
# solo ese archivo (12 bytes medidos junto a una trampa que ignoro).
# ---------------------------------------------------------------------------
if [ -n "$GL_BIN" ]; then
  repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  gl_args=(dir --no-banner --exit-code 1 --redact --report-format json)
  if [ -f "$repo_dir/.gitleaks.toml" ]; then
    gl_args=(dir --config "$repo_dir/.gitleaks.toml" --no-banner --exit-code 1 --redact --report-format json)
  fi
  encontre=""
  for a in "${archivos[@]}"; do
    rep="$(mktemp "${TMPDIR:-/tmp}/saikit-gls-XXXXXX")" || rep=""
    if ! "$GL_BIN" "${gl_args[@]}" --report-path "$rep" "$a" >/dev/null 2>&1; then
      # Del reporte JSON solo se extraen File y StartLine — con --redact el
      # resto viene censurado y no se toca: el reporte de esta herramienta no
      # imprime secretos, es parte de su contrato.
      ubi=""
      if [ -n "$rep" ] && [ -f "$rep" ]; then
        # awk puro, sin grep de por medio: el grep 3.0 de MSYS traga comillas
        # en -cE pero el mismo patron con -oE y [^"]+ no matchea NADA (medido
        # 2026-08-15), y cualquier split por ':' partiria el path en el drive
        # (C:/...). Del reporte solo salen File y StartLine — con --redact el
        # resto viene censurado y no se toca.
        ubi="$(awk '
          match($0, /"File":/) {
            line = $0; gsub(/^.*"File":[[:space:]]*"/, "", line); gsub(/",?$/, "", line); f = line; next
          }
          match($0, /"StartLine":/) {
            line = $0; gsub(/^.*"StartLine":[[:space:]]*/, "", line); gsub(/,?[[:space:]]*$/, "", line)
            if (f != "") { print f ":" line; f = "" }
          }' "$rep" 2>/dev/null | head -n 5)"
      fi
      if [ -n "$ubi" ]; then
        encontre="${encontre}${ubi}
"
      else
        encontre="${encontre}${a} (ubicacion no legible; a mano: gitleaks dir --redact \"$a\")
"
      fi
    fi
    [ -n "$rep" ] && rm -f -- "$rep"
  done
  if [ -n "$encontre" ]; then
    echo "check-secrets: FAIL — gitleaks encontro secretos (archivo:linea):" >&2
    printf '%s' "$encontre" >&2
    exit 1
  fi
  exit 0
fi

# ---------------------------------------------------------------------------
# Motor 2: fallback grep. Tres patrones, los dos primeros son la familia del
# redact_secrets del hook (3.5), el tercero suma formatos conocidos:
#   a) par clave=valor (o clave: valor, YAML/JSON) con valor de 12+ chars —
#      el umbral baja los falsos positivos sin volverlo ciego;
#   b) userinfo en URL (postgresql://admin:pass@host/db);
#   c) literales de proveedor: ghp_/gho_ de GitHub, AKIA de AWS, sk- de
#      OpenAI/Anthropic, xox- de Slack, private keys PEM.
# ---------------------------------------------------------------------------
re_par='(token|password|passwd|secret|api[_-]?key)["'\''[:space:]]*[=:]["'\''[:space:]]*[A-Za-z0-9_/@.%+-]{12,}'
# {5,} en usuario y clave: los ejemplos DOCUMENTALES del patron ("user:pass@",
# "admin:pass@") son de 4, un secreto real no. Sin el umbral, este mismo
# archivo se auto-acusa por sus comentarios — medido 2026-08-15.
re_url='://[A-Za-z0-9._%-]{5,}:[A-Za-z0-9._%-]{5,}@'
re_fmt='gh[po]_[A-Za-z0-9]{30,}|AKIA[0-9A-Z]{16}|sk-[A-Za-z0-9-]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|BEGIN [A-Z ]*PRIVATE KEY'

# Exclusiones SOLO de este motor: falsos conocidos, medidos sobre el arbol
# versionado (2026-08-15). La forma del path (relativo o absoluto) no se sabe
# de antemano: se mira el sufijo.
#   - tests/, docs/ y Plans.md: cargan credenciales FALSAS a proposito (el
#     arnes de la Task 3.5 prueba la redaccion con ellas y el plan las cita).
#   - hooks/summonaikit-harness.sh: su comentario de la 3.5 documenta los
#     patrones con el literal "://user:pass@", que matchea el patrón de URL
#     por diseño. Se excluye SOLO del fallback: el motor fuerte (gitleaks)
#     si lo escanea — medido, 0 hallazgos sobre los 179 commits — y es el
#     archivo que mas importa vigilar. El fallback sin gitleaks queda ciego
#     para este archivo: declarado, mejor que un candado que grita en falso
#     en cada commit del hook.
excluido() {
  case "$1" in
    */tests/*|tests/*|*/docs/*|docs/*|*/Plans.md|Plans.md) return 0 ;;
    */hooks/summonaikit-harness.sh|hooks/summonaikit-harness.sh) return 0 ;;
    *) return 1 ;;
  esac
}

hallazgos=0
for a in "${archivos[@]}"; do
  if excluido "$a"; then continue; fi
  # -H fuerza el nombre de archivo aunque grep reciba uno solo. El sed recorta
  # del ":<linea>:" final hacia atras — funciona tambien con rutas que traen
  # ':' (C:/...): queda "archivo:linea" SIN el contenido, porque no filtrar lo
  # que se viene a impedir es parte del contrato de esta herramienta.
  mientras="$(grep -HnE "$re_par|$re_url|$re_fmt" -- "$a" 2>/dev/null | sed -E 's/(:[0-9]+):.*$/\1/')"
  if [ -n "$mientras" ]; then
    printf 'check-secrets: posible secreto en %s\n' "$mientras" >&2
    hallazgos=$((hallazgos + 1))
  fi
done

if [ "$hallazgos" -gt 0 ]; then
  echo "check-secrets: FAIL — $hallazgos archivo(s) con posibles secretos (motor grep; instalando gitleaks el escaneo es el estandar)" >&2
  exit 1
fi
exit 0
