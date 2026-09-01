#!/usr/bin/env bash
# tools/lib/veredicto_contract.sh — contrato/esquema del veredicto sellado
# (D16). Se carga con `. tools/lib/veredicto_contract.sh`. Sin dependencias
# fuera de coreutils (tr/grep/sed). Lo usan `tests/test_veredicto_contract.sh`
# y el futuro `tools/saikit-merge.sh` (Task 18.4); el hook NO lo usa — el hook
# solo SELLA, no valida (la validacion es del merge, que corre tras el
# veredicto ya sellado; D16/D18).
#
# Esquema del veredicto (`.saikit/veredictos/<sha>.json`):
#   { "sha", "pr", "verifier", "verify_app":{resultado,comando},
#     "blast":{nivel,hecho,comando}, "adversary":{findings,max_sev}|"n/a",
#     "reviewer", "decisiones" }
#
# `veredicto_validar` valida el CONTRATO ESTRUCTURAL (es un objeto JSON, estan
# los campos requeridos, y el sha del veredicto coincide con el HEAD dado). No
# juzga los VALORES semantico-sesion (verifier=PASS, blast.nivel>=4, ...) — eso
# es del merge (D18), que los exige ademas del contrato. Postura de falla:
# report + exit 1 (invalido), nunca exit 0 por ausencia (un veredicto que no se
# pudo leer no es "valido" por defecto, Core Rule 2).

VEREDICTO_REQUERIDOS='"sha" "pr" "verifier" "verify_app" "reviewer" "decisiones" "nivel" "hecho" "resultado" "comando"'

# veredicto_validar <archivo> [head]
#   0 => valido (esquema + sha==head si head viene).
#   1 => invalido, con un motivo en stdout.
veredicto_validar() {
  local f="$1" head="${2:-}" txt="" campo sha
  [ -f "$f" ] || { printf 'no existe el veredicto: %s\n' "$f"; return 1; }
  txt="$(tr -d '\r' < "$f")"

  # Debe ser un objeto JSON (primer char no-espacio '{', ultimo '}').
  case "$(printf '%s' "$txt" | tr -d '[:space:]' | head -c1)" in
    '{') ;;
    *) printf 'no es un objeto JSON (no abre con {)\n'; return 1 ;;
  esac
  case "$(printf '%s' "$txt" | tr -d '[:space:]' | tail -c1)" in
    '}') ;;
    *) printf 'no es un objeto JSON (no cierra con })\n'; return 1 ;;
  esac

  # Campos requeridos. Se buscan como substrings de clave (comilla + clave)
  # porque el esquema es conocido y las claves son unicas; un substring suelto
  # (p.ej. "verif" matcheando "verifier") no alcanza porque se exige la clave
  # entrecomillada completa.
  for campo in '"sha"' '"pr"' '"verifier"' '"verify_app"' '"reviewer"' '"decisiones"' '"nivel"' '"hecho"' '"resultado"' '"comando"'; do
    printf '%s' "$txt" | grep -qF "$campo" || { printf 'falta el campo %s\n' "$campo"; return 1; }
  done

  # sha == HEAD (si head viene). El sed toma la clave "sha" de PRIMER nivel: en
  # un JSON de una sola linea el `.*` de la izquierda se queda con la ultima
  # ocurrencia de "sha", y dentro del esquema "sha" solo existe una vez.
  if [ -n "$head" ]; then
    sha="$(printf '%s' "$txt" | sed -n 's/.*"sha"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
    if [ -z "$sha" ]; then
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
