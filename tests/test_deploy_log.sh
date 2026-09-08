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

# 20.27 — evidencia de horas de deploy (cordón propio HORA_CONTROL, declarado
# en la cabecera del checker): desde 2026-09-08, un bullet Deploy con HORA
# exige fuente por tipo (backup `.bak` del instalador O marcador `hora medida
# en vivo`). La region 2026-09-04..2026-09-07 tiene ~10 entradas legitimas con
# horas medidas en vivo sin marcador (medido 2026-09-08) y NO se toca.
#
# T15: (a) deploy RECUPERABLE: hora + .bak citado => aceptado.
caso "T15: hora de deploy con .bak citado => 0"
cat > "$tmp/t15.md" <<'EOF'
# Deploy log — fixture
## 2026-09-08 — PR #301 / Task X — deploy REAL

- **Merge (13:29 UTC — mergedAt de GitHub):** `abc123def456`, gate SUCCESS.
- **Deploy (13:54 PDT / 20:54 UTC):** master sincronizado; cuatro copias
  REPARADO. Backups: `summonaikit-harness.sh.nuestro.20260908-135442.bak` (claude)
  y `20260908-135443.bak` (grok/dsh/codex).
- **Verificación:** `install-hook.sh --check` exit 0.
EOF
out="$(bash "$tool" --log "$tmp/t15.md" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "hora con .bak dio $rc, se esperaba 0: $out"

# T16: (b) NO recuperable: bullet `hora no recuperada` SIN hora => aceptado
# (unknown honesto, no un rechazo).
caso "T16: hora no recuperada (sin hora) => 0"
cat > "$tmp/t16.md" <<'EOF'
# Deploy log — fixture
## 2026-09-08 — PR #302 / Task Y — hooks NO-OP

- **Merge (21:12 UTC — mergedAt de GitHub):** `b93e2c61528`, gate SUCCESS.
- **Deploy (hora no recuperada — no-op sin backup; mergedAt acredita el merge, no el deploy):** master sincronizado.
EOF
out="$(bash "$tool" --log "$tmp/t16.md" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "hora no recuperada dio $rc, se esperaba 0: $out"

# T17: (c) hora de deploy SIN evidencia => 1 nombrando la regla. Este es el
# hueco medido: contra el checker sin la regla este fixture daba verde.
caso "T17: hora de deploy sin evidencia => 1"
cat > "$tmp/t17.md" <<'EOF'
# Deploy log — fixture
## 2026-09-08 — PR #303 / Task X — deploy REAL

- **Merge (13:29 UTC — mergedAt de GitHub):** `abc123def456`, gate SUCCESS.
- **Deploy (13:29 PDT / 20:29 UTC):** master sincronizado; cuatro copias
  REPARADO. Sin backup citado.
- **Verificación:** `install-hook.sh --check` exit 0.
EOF
out="$(bash "$tool" --log "$tmp/t17.md" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || malo "hora sin evidencia dio $rc, se esperaba 1: $out"
case "$out" in
  *'evidencia'*) ;;
  *) malo "no nombro la regla de evidencia: [$out]" ;;
esac
case "$out" in
  *'hora no recuperada'*) ;;
  *) malo "no sugiere la forma honesta (hora no recuperada): [$out]" ;;
esac

# T18: (d) hora IGUAL a la del merge PERO con .bak citado => aceptado. El
# criterio es el TIPO de evidencia, jamas la desigualdad de timestamps.
caso "T18: hora igual a la del merge con .bak => 0"
cat > "$tmp/t18.md" <<'EOF'
# Deploy log — fixture
## 2026-09-08 — PR #304 / Task X — deploy REAL

- **Merge (13:29 UTC — mergedAt de GitHub):** `abc123def456`, gate SUCCESS.
- **Deploy (13:29 PDT / 20:29 UTC):** master sincronizado; cuatro copias
  REPARADO. Backup: `summonaikit-harness.sh.nuestro.20260908-132900.bak`.
EOF
out="$(bash "$tool" --log "$tmp/t18.md" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "hora igual al merge con .bak dio $rc, se esperaba 0: $out"

# T19-T24 (r2c, hallazgos M1/M2/M3/L1 del adversario): el primer corte de la
# regla miraba SOLO el primer bullet Deploy con grep -m1, grepeaba la
# evidencia en el cuerpo entero y exibia dos digitos de hora. Las cuatro
# formas siguientes PASABAN en verde (medido contra la regla original).
# T19 (M1): SEGUNDO bullet Deploy con hora sin evidencia => 1. La convencion
# real del log trae mas de un bullet Deploy por entrada (un bullet por host).
caso "T19: segundo bullet Deploy con hora sin evidencia => 1"
cat > "$tmp/t19.md" <<'EOF'
# Deploy log — fixture
## 2026-09-08 — PR #305 / Task X — deploy REAL

- **Merge (13:29 UTC — mergedAt de GitHub):** `abc123def456`, gate SUCCESS.
- **Deploy (hora no recuperada — no-op sin backup):** claude reusada, sin cambios.
- **Deploy (14:02 PDT / 21:02 UTC):** grok/dsh/codex REPARADO. Sin backup citado.
EOF
out="$(bash "$tool" --log "$tmp/t19.md" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || malo "segundo bullet con hora dio $rc, se esperaba 1: $out"
case "$out" in *'evidencia'*) ;; *) malo "T19 no nombro evidencia: [$out]" ;; esac

# T20 (M2): hora en linea de CONTINUACION del bullet Deploy => 1 (markdown
# natural al envolver; la primera linea del bullet no trae la hora).
caso "T20: hora en continuacion del bullet Deploy => 1"
cat > "$tmp/t20.md" <<'EOF'
# Deploy log — fixture
## 2026-09-08 — PR #306 / Task X — deploy REAL

- **Merge (13:29 UTC — mergedAt de GitHub):** `abc123def456`, gate SUCCESS.
- **Deploy:** cuatro copias REPARADO; instalado
  a las 14:05 PDT, sin backup citado.
EOF
out="$(bash "$tool" --log "$tmp/t20.md" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || malo "hora en continuacion dio $rc, se esperaba 1: $out"

# T21 (M3a): .bak NEGADO en prosa ajena no acredita => 1. La cita valida es
# un NOMBRE DE ARCHIVO pegado a .bak en la seccion Deploy, no la subcadena
# pelada en cualquier parte del cuerpo.
caso "T21: .bak negado en prosa ajena => 1"
cat > "$tmp/t21.md" <<'EOF'
# Deploy log — fixture
## 2026-09-08 — PR #307 / Task X — deploy REAL

- **Merge (13:29 UTC — mergedAt de GitHub):** `abc123def456`, gate SUCCESS.
- **Deploy (14:11 PDT / 21:11 UTC):** cuatro copias REPARADO.
- **Nota:** revisado el perfil: no quedo ningun .bak de esta corrida.
EOF
out="$(bash "$tool" --log "$tmp/t21.md" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || malo "prosa con .bak negado dio $rc, se esperaba 1: $out"

# T22 (M3b): el marcador 'hora medida en vivo' en clave AJENA no acredita => 1.
caso "T22: marcador en clave ajena => 1"
cat > "$tmp/t22.md" <<'EOF'
# Deploy log — fixture
## 2026-09-08 — PR #308 / Task X — deploy REAL

- **Merge (13:29 UTC — mergedAt de GitHub):** `abc123def456`, gate SUCCESS.
- **Deploy (14:20 PDT / 21:20 UTC):** cuatro copias REPARADO, sin backup.
- **Verificación:** fue una hora medida en vivo, segun el operador.
EOF
out="$(bash "$tool" --log "$tmp/t22.md" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || malo "marcador en clave ajena dio $rc, se esperaba 1: $out"

# T23: contracara del marcador: 'hora medida en vivo' EN la seccion Deploy
# (la fuente explicita acompana a la hora que respalda) => aceptado.
caso "T23: marcador en la seccion Deploy => 0"
cat > "$tmp/t23.md" <<'EOF'
# Deploy log — fixture
## 2026-09-08 — PR #309 / Task X — deploy REAL

- **Merge (13:29 UTC — mergedAt de GitHub):** `abc123def456`, gate SUCCESS.
- **Deploy (14:30 PDT / 21:30 UTC, hora medida en vivo):** cuatro copias
  REPARADO; no-op no deja backup.
EOF
out="$(bash "$tool" --log "$tmp/t23.md" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "marcador en seccion Deploy dio $rc, se esperaba 0: $out"

# T24 (L1): hora de UN digito (1:05 PDT) sin evidencia => 1.
caso "T24: hora de un digito sin evidencia => 1"
cat > "$tmp/t24.md" <<'EOF'
# Deploy log — fixture
## 2026-09-08 — PR #310 / Task X — deploy REAL

- **Merge (13:29 UTC — mergedAt de GitHub):** `abc123def456`, gate SUCCESS.
- **Deploy (1:05 PDT):** cuatro copias REPARADO, sin backup citado.
EOF
out="$(bash "$tool" --log "$tmp/t24.md" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || malo "hora de un digito dio $rc, se esperaba 1: $out"

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

# 20.27: anular la regla de evidencia (el mal -> no-op ':') => T17 pasa a
# verde con el mutante; el control sano inmediatamente antes exige rojo.
caso "mutacion: evidencia anulada => T17 la atrapa"
mut_ev_base="$tmp/mut-base-ev.sh"; mut_ev="$tmp/mut-ev.sh"
cp "$tool" "$mut_ev_base"
sed 's/mal "evidencia:/: "evidencia:/' "$mut_ev_base" > "$mut_ev"
out="$(bash "$tool" --log "$tmp/t17.md" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || malo "control sano T17 dio $rc, se esperaba 1 (regla viva)"
if cmp -s "$mut_ev_base" "$mut_ev"; then
  malo "mutacion evidencia-anulada no cambio nada — el sed quedo obsoleto"
elif ! bash -n "$mut_ev" 2>/dev/null; then
  malo "mutacion evidencia-anulada no parsea; asi no prueba nada"
else
  out="$(bash "$mut_ev" --log "$tmp/t17.md" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then
    printf '    mutacion evidencia-anulada atrapada (T17 en rojo)\n'
  elif [ "$rc" -eq 1 ]; then
    malo "mutacion evidencia-anulada SOBREVIVIO: T17 dio verde sin la regla"
  else
    malo "mutacion evidencia-anulada invalida (rc=$rc, se esperaba el flip 1->0)"
  fi
fi

# 20.27: mutante de FIXTURE — copiar la hora del bullet de merge al Deploy sin
# evidencia (el error historico) => el checker sano lo rechaza. El control
# sano antes: la forma honesta (`hora no recuperada`) sigue en verde.
caso "mutacion: fixture copia hora del merge al Deploy sin evidencia => 1"
t16m="$tmp/t16-copia-hora.md"
sed 's|\*\*Deploy (hora no recuperada — no-op sin backup; mergedAt acredita el merge, no el deploy):*|**Deploy (21:12 PDT / 21:12 UTC):|' "$tmp/t16.md" > "$t16m"
out="$(bash "$tool" --log "$tmp/t16.md" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "control sano T16 dio $rc, se esperaba 0 (forma honesta)"
if cmp -s "$tmp/t16.md" "$t16m"; then
  malo "mutacion fixture-copia-hora no cambio nada — el sed quedo obsoleto"
else
  out="$(bash "$tool" --log "$t16m" 2>&1)"; rc=$?
  if [ "$rc" -eq 1 ]; then
    printf '    mutacion fixture-copia-hora atrapada (rechazada)\n'
  else
    malo "mutacion fixture-copia-hora SOBREVIVIO: hora copiada del merge aceptada (rc=$rc)"
  fi
fi

if [ "$fail" -ne 0 ]; then
  echo "test_deploy_log: FAIL" >&2
  exit 1
fi
echo "test_deploy_log: OK"
