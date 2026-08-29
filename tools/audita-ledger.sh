#!/usr/bin/env bash
# audita-ledger.sh — busca filas de Plans.md que dicen `cc:TODO` cuando su
# trabajo YA esta en master.
#
# Por que existe. El 2026-08-29, al cerrar 16.4 y 16.6, aparecio que la fila
# 16.3 seguia en `cc:TODO` desde el dia anterior: el PR #100 estaba mergeado,
# los cuatro perfiles de `agents/` existian, y el ledger — que es lo que
# cualquier sesion futura lee para saber donde esta parada la fase — decia que
# la tarea no habia empezado. La causa es mecanica y se repite: el lider cierra
# las filas del PR que acaba de mergear y no vuelve a mirar las de antes.
#
# `tests/test_plans_ledger.sh` no lo puede atrapar: mira la FORMA de la fila
# (que no este partida, que tenga 5 celdas), no si su estado corresponde a la
# realidad. Esto mira la realidad, y la realidad mas barata que hay es el
# alcance de los commits: en este repo cada task se mergea en un PR propio con
# Conventional Commits `tipo(N.M):`.
#
# POR QUE NO ES UN JOB DE CI, dicho para que nadie lo mueva ahi sin pensarlo:
# durante el PR de una task, los commits de ESA task ya estan en la rama y su
# fila todavia dice `cc:TODO` — correcto, todavia no se mergeo. En CI eso daria
# rojo en cada PR, y un candado que grita siempre se apaga. Por eso compara
# contra `origin/master` (lo YA mergeado) y se corre como paso del cierre: ver
# AGENTS.md § "Deploy tras merge".
#
# Contrato de salida (igual que check-hook-registration.sh): SIEMPRE exit 0 si
# pudo mirar; el resultado se dice por texto. Exit 3 si NO pudo mirar
# (`not_observed != absent`): sin `origin/master`, o en un clon shallow, no se
# afirma que el ledger este bien — se dice que no se pudo verificar.
set -u

repo="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
ledger="${SAIKIT_LEDGER:-$repo/Plans.md}"
ref="${SAIKIT_LEDGER_REF:-origin/master}"

if [ ! -r "$ledger" ]; then
  echo "[saikit] AUDITORIA DEL LEDGER: unknown — no se pudo leer $ledger" >&2
  exit 3
fi
if [ "$(git -C "$repo" rev-parse --is-shallow-repository 2>/dev/null)" = "true" ]; then
  echo "[saikit] AUDITORIA DEL LEDGER: unknown — el clon es shallow, el historial no alcanza para decidir" >&2
  exit 3
fi
if ! git -C "$repo" rev-parse --verify --quiet "$ref" >/dev/null 2>&1; then
  echo "[saikit] AUDITORIA DEL LEDGER: unknown — no existe la referencia $ref; nada que comparar" >&2
  exit 3
fi

# Alcances ya mergeados: de cada subject `tipo(a,b): ...` se sacan a y b.
alcances="$(git -C "$repo" log --format='%h%x09%s' "$ref" \
  | awk -F'\t' '
      {
        sha = $1; sub(/^[^\t]*\t/, "", $0); subj = $0
        if (match(subj, /^[a-z]+\([^)]*\)/) == 0) next
        scope = substr(subj, RSTART, RLENGTH)
        sub(/^[a-z]+\(/, "", scope); sub(/\)$/, "", scope)
        n = split(scope, partes, ",")
        for (i = 1; i <= n; i++) {
          gsub(/^[ \t]+|[ \t]+$/, "", partes[i])
          if (partes[i] ~ /^[0-9]+\.[0-9]+$/ && !(partes[i] in visto)) {
            visto[partes[i]] = sha "\t" subj
          }
        }
      }
      END { for (t in visto) print t "\t" visto[t] }
  ')"

# Filas en cc:TODO cuyo alcance ya aparece en un commit mergeado.
hallazgos="$(printf '%s\n' "$alcances" | awk -F'\t' -v L="$ledger" '
    NF >= 3 { sha[$1] = $2; subj[$1] = $3 }
    # El marcador se lee del PRINCIPIO de la celda de estado (la ultima), no de
    # la linea ni de la celda entera. Dos falsos positivos medidos al escribir
    # esto, ambos sobre la fila 16.3 ya cerrada: (1) la linea entera menciona
    # `cc:TODO` en el texto que explica el incidente; (2) esa mencion vive
    # DENTRO de la propia celda de estado, asi que mirar la celda completa
    # tampoco alcanza. La convencion del ledger es que la celda ARRANCA con el
    # marcador y despues viene la prosa del cierre. Es la misma trampa que
    # infla el contador TODO del banner de sesion: cuenta menciones, no estados.
    function celda_estado(linea,   fila, tmp, i, p) {
      fila = linea
      sub(/[[:space:]]*\|[[:space:]]*$/, "", fila)   # quita el | de cierre
      tmp = fila
      gsub(/\\\|/, "\001\002", tmp)                  # protege los | escapados
      p = 0                                          # (2 chars por 2: no corre las posiciones)
      for (i = length(tmp); i >= 1; i--) if (substr(tmp, i, 1) == "|") { p = i; break }
      if (p == 0) return ""
      return substr(fila, p + 1)
    }
    END {
      while ((getline linea < L) > 0) {
        if (linea !~ /^\| *[0-9]+\.[0-9]+ /) continue
        t = linea; sub(/^\| */, "", t); sub(/ .*$/, "", t)
        if (celda_estado(linea) !~ /^[[:space:]]*cc:TODO/) continue
        if (t in sha) printf "%s\t%s\t%s\n", t, sha[t], subj[t]
      }
    }
')"

if [ -z "$hallazgos" ]; then
  echo "[saikit] AUDITORIA DEL LEDGER: OK — ninguna fila en cc:TODO tiene trabajo ya mergeado en $ref"
  exit 0
fi

echo "[saikit] LEDGER DESACTUALIZADO — estas filas dicen cc:TODO pero su trabajo ya esta en $ref:"
printf '%s\n' "$hallazgos" | while IFS="$(printf '\t')" read -r t sha subj; do
  printf '              fila %s  <-  %s %s\n' "$t" "$sha" "$subj"
done
echo "              Cerralas con su PR, su merge y su run de CI, o explica en la fila por que sigue abierta."
exit 0
