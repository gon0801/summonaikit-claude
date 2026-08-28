# tests/lib/recetas_lint.sh — reglas de forma de una receta (D2). Se carga con
# `. tests/lib/recetas_lint.sh`. Sin dependencias fuera de coreutils/grep/sed.
RECETAS_TERMINOS_PROHIBIDOS='gt |Graphite|Bugbot|AskQuestion|/loop|poteto|Cursor'
RECETAS_TOPE_LINEAS=80

_rl_frontmatter() {  # $1=archivo → stdout: lineas entre el 1er y 2do '---'; rc 1 si falta el cierre
  tr -d '\r' < "$1" | awk 'NR==1 && $0!="---"{exit 1} NR>1 && $0=="---"{c=1; exit} NR>1{print} END{if(NR>1 && !c) exit 1}'
}
_rl_campo() {  # $1=archivo $2=clave → valor (sin comillas) o vacio
  _rl_frontmatter "$1" | sed -n "s/^$2:[[:space:]]*//p" | head -n1 | sed 's/^"\(.*\)"$/\1/'
}

lint_receta() {  # $1=archivo → 0 ok; 1 con motivo(s) en stdout
  local f="$1" rc=0 n tipo nombre carril titulo
  n="$(tr -d '\r' < "$f" | wc -l | tr -d ' ')"
  [ "$n" -le "$RECETAS_TOPE_LINEAS" ] || { echo "supera $RECETAS_TOPE_LINEAS lineas ($n)"; rc=1; }
  _rl_frontmatter "$f" >/dev/null 2>&1 || { echo "sin frontmatter (--- en la linea 1 y cierre)"; return 1; }
  [ "$(_rl_campo "$f" saikit_owned)" = "summonaikit-claude" ] || { echo "falta saikit_owned: summonaikit-claude"; rc=1; }
  tipo="$(_rl_campo "$f" tipo)"; [ -n "$tipo" ] || tipo=receta
  case "$tipo" in receta|lider) ;; *) echo "tipo invalido: $tipo"; rc=1 ;; esac
  nombre="$(_rl_campo "$f" nombre)"
  printf '%s' "$nombre" | grep -Eq '^[a-z][a-z0-9-]*$' || { echo "nombre invalido: [$nombre]"; rc=1; }
  titulo="$(_rl_campo "$f" titulo)"
  [ -n "$titulo" ] || { echo "falta titulo"; rc=1; }
  printf '%s' "$titulo" | grep -q "$(printf '\t')" && { echo "el titulo lleva TAB"; rc=1; }
  case "$titulo" in '>'|'|') echo "el titulo es un indicador plegado/literal"; rc=1 ;; esac
  if [ "$tipo" = receta ]; then
    carril="$(_rl_campo "$f" carril)"
    case "$carril" in full|fast) ;; *) echo "carril invalido: [$carril]"; rc=1 ;; esac
    [ -n "$(_rl_campo "$f" cuando)" ] || { echo "falta cuando"; rc=1; }
    case "$(_rl_campo "$f" adversary)" in opcional|obligatorio) ;; *) echo "adversary invalido"; rc=1 ;; esac
    for sec in '## Pasos' '## Qué le dices al usuario' '## Recibo'; do
      grep -q "^$sec" "$f" || { echo "falta la seccion '$sec'"; rc=1; }
    done
  fi
  if grep -Eiq "$RECETAS_TERMINOS_PROHIBIDOS" "$f"; then
    echo "termino prohibido: $(grep -Eio "$RECETAS_TERMINOS_PROHIBIDOS" "$f" | head -n1)"; rc=1
  fi
  # links relativos [texto](ruta) tienen que resolver desde recetas/
  for l in $(grep -Eo '\]\([^)#]+' "$f" | sed 's/^](//' | grep -Ev '^(https?:|mailto:)'); do
    [ -e "$(dirname "$f")/$l" ] || { echo "link roto: $l"; rc=1; }
  done
  return $rc
}

manifest_linea() {  # $1=archivo → "sha256\ttipo\tnombre\tcarril\ttitulo"
  # El hash se calcula NORMALIZADO a LF (tr -d '\r'): .gitattributes fuerza
  # eol=lf, así que el blob de git y el checkout son siempre LF. Hashear los
  # bytes crudos del working-tree dejaría un hash CRLF si alguien guarda la
  # receta con CRLF, y ese hash no coincidiría con el LF que instala el runtime
  # (D1). Para un archivo LF es un no-op: el hash no cambia.
  local f="$1" sha tipo carril
  sha="$(tr -d '\r' < "$f" | sha256sum | cut -c1-64)"
  tipo="$(_rl_campo "$f" tipo)"; [ -n "$tipo" ] || tipo=receta
  carril="$(_rl_campo "$f" carril)"; [ -n "$carril" ] || carril=-
  printf '%s\t%s\t%s\t%s\t%s\n' "$sha" "$tipo" \
    "$(_rl_campo "$f" nombre)" "$carril" "$(_rl_campo "$f" titulo)"
}

manifest_unicos() {  # $1=TSV → 0 si el campo 3 (nombre) es unico; 1 listando dupes
  local d
  d="$(cut -f3 "$1" | sort | uniq -d)"
  [ -z "$d" ] || { echo "nombres duplicados: $d"; return 1; }
  return 0
}
