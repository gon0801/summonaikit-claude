#!/usr/bin/env bash
# Task 23.5 — el probe del contrato de Muse reporta version + veredicto por
# punto con el proveedor echo, y cada punto roto a proposito da fail.
#
# Hermetico: todo via tests/fixtures/muse/muse-probe-stub.sh (doble del
# binario con modos rojos por SAIKIT_STUB_MODE). Nada toca el perfil real:
# el probe aisla con cinco variables en una caja mktemp. Lo vivo (binario
# real 1.3.0-R3401.1, cuatro puntos en pass, costo cero) se midio en la
# corrida del stream 2 y va declarado en el PR, no en este test.
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
probe="$repo/tools/probe-muse-contract.sh"
stub="$repo/tests/fixtures/muse/muse-probe-stub.sh"

fail=0
caso() { printf '  caso: %s\n' "$1"; }
malo() { printf '    FAIL: %s\n' "$1" >&2; fail=1; }

correr() { # $1=stub-mode $2=nonce -> stdout en $OF, rc en $RC
  local m="$1" n="$2"
  OF="$(mktemp)"
  if [ "$m" = "SIN-BINARIO" ]; then
    SAIKIT_MUSE_BIN=/no/existe SAIKIT_PROBE_NONCE="$n" bash "$probe" >"$OF" 2>&1; RC=$?
  else
    SAIKIT_MUSE_BIN="$stub" SAIKIT_STUB_MODE="$m" SAIKIT_PROBE_NONCE="$n" bash "$probe" >"$OF" 2>&1; RC=$?
  fi
}

caso "verde: cuatro puntos en pass, exit 0, version del stub"
correr normal verde-1
[ "$RC" -eq 0 ] || malo "verde: exit $RC (esperaba 0)"
grep -q 'punto=version veredicto=pass' "$OF" || malo "verde: sin version pass"
for p in P1 P2 P3 P4; do grep -q "punto=$p veredicto=pass" "$OF" || malo "verde: $p no esta en pass"; done
grep -q 'veredicto=ok' "$OF" || malo "verde: sin veredicto=ok"
grep -q 'punto=despacho veredicto=unknown' "$OF" || malo "verde: falta el unknown del despacho (lo vivo es del lead)"

caso "rojo P1 (no-hooks): fail y exit 1"
correr no-hooks rojo-p1
[ "$RC" -eq 1 ] || malo "rojo P1: exit $RC (esperaba 1)"
grep -q 'punto=P1 veredicto=fail' "$OF" || malo "rojo P1: P1 no esta en fail"

caso "rojo P2 (no-ctx): fail y exit 1"
correr no-ctx rojo-p2
[ "$RC" -eq 1 ] || malo "rojo P2: exit $RC (esperaba 1)"
grep -q 'punto=P2 veredicto=fail' "$OF" || malo "rojo P2: P2 no esta en fail"
grep -q 'punto=P1 veredicto=pass' "$OF" || malo "rojo P2: P1 debio seguir en pass"

caso "rojo P3 (no-continue): fail y exit 1"
correr no-continue rojo-p3
[ "$RC" -eq 1 ] || malo "rojo P3: exit $RC (esperaba 1)"
grep -q 'punto=P3 veredicto=fail' "$OF" || malo "rojo P3: P3 no esta en fail"

caso "rojo P4 (no-catalog): fail y exit 1"
correr no-catalog rojo-p4
[ "$RC" -eq 1 ] || malo "rojo P4: exit $RC (esperaba 1)"
grep -q 'punto=P4 veredicto=fail' "$OF" || malo "rojo P4: P4 no esta en fail"

caso "unknown sin binario: exit 4, sin fail"
correr SIN-BINARIO unk-1
[ "$RC" -eq 4 ] || malo "unknown: exit $RC (esperaba 4)"
grep -q 'veredicto=unknown' "$OF" || malo "unknown: sin linea unknown"
grep -q 'veredicto=fail' "$OF" && malo "unknown: no debe traer fail"

rm -f "$OF"
if [ "$fail" -eq 0 ]; then printf 'test_probe_muse_contract: OK\n'; else printf 'test_probe_muse_contract: FALLO\n' >&2; fi
exit "$fail"
