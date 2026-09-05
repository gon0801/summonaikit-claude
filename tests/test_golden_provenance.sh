#!/usr/bin/env bash
# 18.20 — regrabar la golden ya no exige desplegar la rama al perfil real.
#
# El default de --record era el hook VIVO, asi que regrabar pedia que el vivo
# YA fuera el hook nuevo — y la via mas corta era desplegar la rama al perfil
# REAL, que el protocolo de entrega prohibe. Las dos reglas se pisaban. Ahora
# --record usa por defecto la FUENTE del repo; --hook explicito y
# SAIKIT_HOOK_VIVO siguen ganando (precedencia documentada, no magia).
#
# Lo que NO cambia: el trato de identidad del --check de la golden
# (golden-harness.sh decision 2: comparar identidad daria rojo justo en el
# caso para el que --check existe). Y el cambio de default es no-op para el
# --check de CI porque test_golden_baseline.sh pasa --hook explicito.
#
# Core Rule 4: --record escribe la base en un tmpdir, jamas en el repo.
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
# Costura de mutacion (mismo mecanismo que SAIKIT_INSTALL_TOOL): permite correr
# esta bateria contra una copia MUTADA del arnes y exigir que se de cuenta.
arnes="${SAIKIT_GOLDEN_TOOL:-$repo/tools/golden-harness.sh}"
fuente="$repo/hooks/summonaikit-harness.sh"
base_real="$repo/tests/golden/baseline.txt"
esc_falsos="$repo/tests/fixtures/arnes-falso/escenarios"

fail=0
caso() { printf '  caso: %s\n' "$1"; }
malo() { printf '    FAIL: %s\n' "$1" >&2; fail=1; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/saikit-golden-prov-XXXXXX")" || exit 1
trap 'rm -rf "$tmp"' EXIT

sha_de_archivo() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum < "$1" | cut -d' ' -f1
  else shasum -a 256 < "$1" | cut -d' ' -f1; fi
}

# G1: --record sin --hook y sin SAIKIT_HOOK_VIVO graba la FUENTE del repo,
# aunque no haya vivo (HOME vacio). Es EL caso: con el default viejo salia 2
# (unknown, sin hook que ejercitar) y empujaba a desplegar la rama.
# Escenarios falsos a proposito: lo que se afirma es QUE hook se grabo (el
# sha de la cabecera), no su comportamiento; la corrida completa es lenta.
caso "G1: --record por defecto graba la fuente del repo (sin vivo)"
casa="$tmp/casa-g1"
mkdir -p "$casa"
out="$(env -u SAIKIT_HOOK_VIVO HOME="$casa" bash "$arnes" --scenarios "$esc_falsos" --baseline "$tmp/base-g1.txt" --record 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "--record por defecto salio $rc: $out"
[ -s "$tmp/base-g1.txt" ] || malo "--record no escribio la base"
grabado="$(grep -m1 '^# hook_sha256: ' "$tmp/base-g1.txt" 2>/dev/null | sed 's/^# hook_sha256: //')"
esperado="$(sha_de_archivo "$fuente")"
[ -n "$grabado" ] || malo "la base grabada no trae # hook_sha256:"
[ "$grabado" = "$esperado" ] || malo "la base grabada no es de la fuente: [$grabado] vs [$esperado]"

# G2: la linea base committed esta atada a la fuente committed. Nacio VERDE
# (medido: los sha coinciden hoy) — es candado, no fix: si un futuro --record
# volviera a grabar el vivo atrasado, este caso lo grita.
caso "G2: # hook_sha256: de la baseline committed == sha de la fuente"
grabado="$(grep -m1 '^# hook_sha256: ' "$base_real" 2>/dev/null | sed 's/^# hook_sha256: //')"
esperado="$(sha_de_archivo "$fuente")"
[ -n "$grabado" ] || malo "la baseline committed no trae # hook_sha256:"
[ "$grabado" = "$esperado" ] || malo "la baseline committed no es de la fuente: [$grabado] vs [$esperado]"

# G3: --hook explicito a un archivo inexistente => 2 (se honra el explicito,
# no se cae al default). Candado de precedencia, nacido verde.
caso "G3: --hook explicito inexistente => 2 (no cae al default)"
out="$(env -u SAIKIT_HOOK_VIVO HOME="$tmp/casa-g3" bash "$arnes" --hook "$tmp/no-existe.sh" --scenarios "$esc_falsos" --baseline "$tmp/base-g3.txt" --record 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || malo "--record con --hook malo salio $rc, se esperaba 2: $out"

# G4: SAIKIT_HOOK_VIVO inexistente y sin --hook => 2 (el env gana al default).
# Candado de precedencia, nacido verde. Es tambien la trampa del G1: como
# run.sh y el CI exportan SAIKIT_HOOK_VIVO, un G1 sin `env -u` ejercitaria el
# env y no el default — la mutacion sobreviviria.
caso "G4: SAIKIT_HOOK_VIVO inexistente => 2 (el env gana al default)"
out="$(SAIKIT_HOOK_VIVO="$tmp/no-existe.sh" HOME="$tmp/casa-g4" bash "$arnes" --scenarios "$esc_falsos" --baseline "$tmp/base-g4.txt" --record 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || malo "--record con env malo salio $rc, se esperaba 2: $out"

# ------------------------------------------------------- bloque de mutaciones
# Guarda anti-sed-obsoleto, patron de test_autopilot_config.sh: si el sed no
# cambia bytes o el mutante no parsea, FAIL (ya no prueba nada).
caso "mutacion: --record al vivo => G1 la atrapa"
mut_base="$tmp/mut-base-golden.sh"; mutado="$tmp/mut-mutado-golden.sh"
cp "$arnes" "$mut_base"
sed 's|HOOK="[$]repo/hooks/summonaikit-harness.sh"|HOOK="[$]HOME/.claude/hooks/summonaikit-harness.sh"|' "$mut_base" > "$mutado"
if cmp -s "$mut_base" "$mutado"; then
  malo "mutacion record-al-vivo no cambio nada — el sed quedo obsoleto"
elif ! bash -n "$mutado" 2>/dev/null; then
  malo "mutacion record-al-vivo no parsea; asi no prueba nada"
else
  casa="$tmp/casa-mut8"; mkdir -p "$casa"
  out="$(env -u SAIKIT_HOOK_VIVO HOME="$casa" bash "$mutado" --scenarios "$esc_falsos" --baseline "$tmp/base-mut8.txt" --record 2>&1)"; rc=$?
  if [ "$rc" -eq 2 ]; then
    printf '    mutacion record-al-vivo atrapada (G1 en rojo)\n'
  elif [ "$rc" -eq 0 ]; then
    malo "mutacion record-al-vivo SOBREVIVIO: G1 dio verde con el default al vivo"
  else
    malo "mutacion record-al-vivo invalida (rc=$rc, se esperaba el flip 0->2)"
  fi
fi

if [ "$fail" -ne 0 ]; then
  echo "test_golden_provenance: FAIL" >&2
  exit 1
fi
echo "test_golden_provenance: OK"
