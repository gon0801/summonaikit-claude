#!/usr/bin/env bash
# 18.20 — el deploy-log exige por maquina lo que era disciplina: entradas con
# norma, en orden, y un registro por PR.
#
# DECISION declarada (la DoD la pide): fecha de CORTE, no normalizar el
# historico. Las dos invariantes YA estan violadas hoy (tres inversiones de
# fecha; 19 de 78 encabezados fuera de norma, medidos): reescribir el historico
# falsificaria el log y moveria bloques de lugar. Lo juzgado es desde
# 2026-09-04 inclusive; lo anterior es abuelo y no se juzga.
#
# La extraccion de PRs NO es un #[0-9]+ ingenuo: solo corre sobre encabezados
# ## con ancla PR (la prosa menciona (#122, hallazgo #3, #72 — falsos positivos
# medidos), expande rangos (#84–#86 son TRES PRs) y namespacea kimi#N (repo
# distinto: kimi#9 no choca con #9).
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
# Costura de mutacion (mismo mecanismo que SAIKIT_INSTALL_TOOL).
tool="${SAIKIT_DEPLOYLOG_TOOL:-$repo/tools/check-deploy-log.sh}"

fail=0
caso() { printf '  caso: %s\n' "$1"; }
malo() { printf '    FAIL: %s\n' "$1" >&2; fail=1; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/saikit-deploy-log-XXXXXX")" || exit 1
trap 'rm -rf "$tmp"' EXIT

if [ ! -f "$tool" ]; then
  echo "    FAIL: no existe la herramienta en $tool" >&2
  echo "test_deploy_log: FAIL" >&2
  exit 1
fi

# T1: el log real pasa (region juzgada: las dos entradas del 2026-09-04).
# Con --log explicito a proposito: una copia mutada vive fuera del repo y su
# default apuntaria a otro lado (exit 2 por razon ajena a la mutacion).
caso "T1: docs/deploy-log.md real => 0"
out="$(bash "$tool" --log "$repo/docs/deploy-log.md" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "el log real dio $rc: $out"

# T2: encabezado juzgado fuera de norma => 1 nombrando la regla.
caso "T2: header juzgado sin norma => 1"
cat > "$tmp/t2.md" <<'EOF'
# Deploy log — fixture
## 2026-09-05 — Deploy a mano sin formato ni PR
cuerpo
EOF
out="$(bash "$tool" --log "$tmp/t2.md" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || malo "header sin norma dio $rc, se esperaba 1: $out"
case "$out" in *'norma'*) ;; *) malo "no nombro la regla de norma: [$out]" ;; esac

# T3: inversion de fecha dentro de lo juzgado => 1. Solo viola orden.
caso "T3: inversion de fecha juzgada => 1"
cat > "$tmp/t3.md" <<'EOF'
# Deploy log — fixture
## 2026-09-05 — PR #201 / Task X — deploy NO-OP
cuerpo
## 2026-09-06 — PR #202 / Task Y — deploy NO-OP
cuerpo
EOF
out="$(bash "$tool" --log "$tmp/t3.md" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || malo "inversion juzgada dio $rc, se esperaba 1: $out"
case "$out" in *'orden'*) ;; *) malo "no nombro la regla de orden: [$out]" ;; esac

# T4: entrada juzgada DEBAJO de una abuela (el error historico de apendar al
# final en vez de anteponer) => 1. Fechas NO-crecientes a proposito (09-06
# arriba, 09-05 abajo): si tambien violaran orden, la mutacion de prefijo
# sobreviviria (el orden la seguiria rechazando) — la trampa de la 18.18.
caso "T4: juzgada debajo de abuela => 1"
cat > "$tmp/t4.md" <<'EOF'
# Deploy log — fixture
## 2026-09-06 — PR #202 / Task Y — deploy NO-OP
cuerpo
## 2026-09-01 — Deploy viejo de abuelo sin norma
cuerpo
## 2026-09-05 — PR #201 / Task X — deploy NO-OP
cuerpo
EOF
out="$(bash "$tool" --log "$tmp/t4.md" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || malo "juzgada bajo abuela dio $rc, se esperaba 1: $out"
case "$out" in *'prefijo'*) ;; *) malo "no nombro la regla de prefijo: [$out]" ;; esac

# T5: el mismo PR en dos encabezados juzgados => 1 nombrando ambos.
caso "T5: PR duplicado en dos headers => 1"
cat > "$tmp/t5.md" <<'EOF'
# Deploy log — fixture
## 2026-09-06 — PR #203 / Task X — deploy NO-OP
cuerpo
## 2026-09-05 — PR #203 / Task X (reintento) — deploy REAL
cuerpo
EOF
out="$(bash "$tool" --log "$tmp/t5.md" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || malo "PR duplicado dio $rc, se esperaba 1: $out"
case "$out" in *'#203'*) ;; *) malo "no nombro el PR duplicado: [$out]" ;; esac

# T6: la prosa NO cuenta: menciones en cuerpo, aunque repitan, no registran.
caso "T6: # en prosa no registra ni duplica => 0"
cat > "$tmp/t6.md" <<'EOF'
# Deploy log — fixture
## 2026-09-05 — PR #204 / Task X — deploy NO-OP
Se mergeo (#204) tras el hallazgo #3; ver (#122) y el #72 viejo.
Otro renglon con #204 repetido en prosa.
EOF
out="$(bash "$tool" --log "$tmp/t6.md" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "prosa con # dio $rc, se esperaba 0: $out"

# T7: el rango #84–#86 registra 84, 85 y 86: #85 suelto en otro header choca.
caso "T7: rango expande (84-86) y #85 duplica => 1"
cat > "$tmp/t7.md" <<'EOF'
# Deploy log — fixture
## 2026-09-06 — PRs #84–#86 + #91 — deploy NUEVO
cuerpo
## 2026-09-05 — PR #85 / Task X — deploy NO-OP
cuerpo
EOF
out="$(bash "$tool" --log "$tmp/t7.md" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || malo "rango sin expandir dio $rc, se esperaba 1: $out"
case "$out" in *'#85'*) ;; *) malo "no nombro el #85 duplicado: [$out]" ;; esac

# T8: kimi#9 es otro repo: no choca con #9.
caso "T8: kimi#N namespaced => 0"
cat > "$tmp/t8.md" <<'EOF'
# Deploy log — fixture
## 2026-09-06 — PR #9 / Task X — deploy NO-OP
cuerpo
## 2026-09-05 — PR kimi#9 / espejo — deploy NO-OP
cuerpo
EOF
out="$(bash "$tool" --log "$tmp/t8.md" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "kimi#9 vs #9 dio $rc, se esperaba 0: $out"

# T9: bajo el corte todo se ignora (sin norma, invertido, duplicado) => 0.
caso "T9: region abuela no se juzga => 0"
cat > "$tmp/t9.md" <<'EOF'
# Deploy log — fixture
## 2026-09-05 — PR #205 / Task X — deploy NO-OP
cuerpo
## 2026-09-03 — basura vieja sin norma
cuerpo
## 2026-08-12 — PR #2 / Task vieja
cuerpo
## 2026-08-14 — PR #2 / Task vieja repetida
cuerpo
EOF
out="$(bash "$tool" --log "$tmp/t9.md" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "abuela con todo roto dio $rc, se esperaba 0: $out"

# T10: un header con VARIOS PRs registra cada uno.
caso "T10: PRs #160 y #163, #163 repetido => 1"
cat > "$tmp/t10.md" <<'EOF'
# Deploy log — fixture
## 2026-09-06 — PRs #160 y #163 — deploy REPARA
cuerpo
## 2026-09-05 — PR #163 / Task X — deploy NO-OP
cuerpo
EOF
out="$(bash "$tool" --log "$tmp/t10.md" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || malo "multi-PR duplicado dio $rc, se esperaba 1: $out"

# T12: log sin NADA juzgado => 1: un OK sin cobertura es silencio, no verde.
caso "T12: sin entradas juzgadas => 1"
cat > "$tmp/t12.md" <<'EOF'
# Deploy log — fixture
## 2026-09-03 — PR #199 / Task vieja — deploy NO-OP
cuerpo
EOF
out="$(bash "$tool" --log "$tmp/t12.md" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || malo "sin juzgadas dio $rc, se esperaba 1: $out"
case "$out" in *'vacio'*) ;; *) malo "no nombro la regla de vacio: [$out]" ;; esac

# T13: un #N en un header SIN ancla PR no registra (es mencion, no registro).
# Sin este caso, romper el ancla sobreviviria: nada lo ejercita.
caso "T13: # en header sin ancla no registra => 0"
cat > "$tmp/t13.md" <<'EOF'
# Deploy log — fixture
## 2026-09-06 — Deploy correctivo fuera de PR: reintento del deploy #206
cuerpo
## 2026-09-05 — PR #206 / Task X — deploy NO-OP
cuerpo
EOF
out="$(bash "$tool" --log "$tmp/t13.md" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "mencion en correctivo dio $rc, se esperaba 0: $out"

# T11: log ilegible => 2 (error, no silencio ni verde).
caso "T11: log inexistente => 2"
out="$(bash "$tool" --log "$tmp/no-existe.md" 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || malo "log inexistente dio $rc, se esperaba 2: $out"

# Clase Task 0.4 (`shift 2` con un solo argumento gira para siempre), like
# flag_sin_valor_sale_2_no_gira: 124 es bucle, 2 es fix. Discrimina porque el
# cuelgue es el comportamiento real pre-fix (medido: 124).
caso "T14: --log sin valor sale 2, no gira"
out="$(timeout 5 bash "$tool" --log 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || malo "--log sin valor dio $rc, se esperaba 2 (124=cuelgue)"
case "$out" in
  *'exige un valor'*) ;;
  *) malo "--log sin valor no nombro la falta: [$out]" ;;
esac

# ------------------------------------------------------- bloque de mutaciones
# Guarda anti-sed-obsoleto, patron de test_autopilot_config.sh: si el sed no
# cambia bytes o el mutante no parsea, FAIL (ya no prueba nada).
caso "mutacion: unicidad anulada => T5 la atrapa"
mut_base="$tmp/mut-base-dl.sh"; mutado="$tmp/mut-mutado-dl.sh"
cp "$tool" "$mut_base"
sed 's/mal "duplicado:/: "duplicado:/' "$mut_base" > "$mutado"
if cmp -s "$mut_base" "$mutado"; then
  malo "mutacion unicidad-anulada no cambio nada — el sed quedo obsoleto"
elif ! bash -n "$mutado" 2>/dev/null; then
  malo "mutacion unicidad-anulada no parsea; asi no prueba nada"
else
  cat > "$tmp/tmut.md" <<'EOF'
# Deploy log — fixture
## 2026-09-06 — PR #203 / Task X — deploy NO-OP
cuerpo
## 2026-09-05 — PR #203 / Task X (reintento) — deploy REAL
cuerpo
EOF
  out="$(bash "$mutado" --log "$tmp/tmut.md" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then
    printf '    mutacion unicidad-anulada atrapada (T5 en rojo)\n'
  elif [ "$rc" -eq 1 ]; then
    malo "mutacion unicidad-anulada SOBREVIVIO: T5 dio verde sin la guarda"
  else
    malo "mutacion unicidad-anulada invalida (rc=$rc, se esperaba el flip 1->0)"
  fi
fi

if [ "$fail" -ne 0 ]; then
  echo "test_deploy_log: FAIL" >&2
  exit 1
fi
echo "test_deploy_log: OK"
