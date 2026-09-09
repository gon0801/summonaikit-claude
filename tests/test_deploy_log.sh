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

# T25-T31 (r4, hallazgos B1/B2 de la cuarta revision del PR #273): el cordon
# HORA_CONTROL bajaba al 09-08 y dejaba FUERA a la tanda reparada del 09-07
# (una hora copiada de mergedAt reintroducida alli pasaba, medido), y la
# evidencia se grepeaba en la seccion CONCATENADA (el .bak o el marcador de
# un bullet hermano acreditaba la hora de otro, medido en cuatro variantes).
# El cordon cubre ahora el 09-07 y la evidencia se valida POR BULLET: la
# fuente (un .bak pegado o el marcador `hora medida en vivo` dentro del MISMO
# parentesis que la hora) debe vivir en las lineas del bullet que cita la
# hora. Las contracaras reales de la tanda (las nueve entradas del 09-07 del
# log real) siguen en 0.

# T25 (B1): la FORMA REAL del error del #272, en el dia 7 — Merge con
# mergedAt a 21:12 y Deploy con la hora COPIADA 21:12 sin evidencia. Con
# HORA_CONTROL=2026-09-08 esta entrada pasaba (medido rc=0): el cordon debe
# cubrir el historico que la rectificacion reparo.
caso "T25: hora copiada del mergedAt en entrada del 09-07 (forma #272) => 1"
cat > "$tmp/t25.md" <<'EOF'
# Deploy log — fixture
## 2026-09-07 — PR #272 (cierre de la tanda Phase 20: 20.1-20.7 + 20.24) — hooks NO-OP

- **Merge (21:12 UTC — mergedAt de GitHub):** `b93e2c61528d6d0c8c0fa2a18efc00f7d5956c20`; gate SUCCESS.
- **Deploy (21:12 PDT / 21:12 UTC):** master sincronizado; `sucio=no`,
  `coincide_origin_master=si`. Instaladores claude/grok/dsh/codex exit 0;
  cuatro copias `YA AL DIA`; sin backup.
EOF
out="$(bash "$tool" --log "$tmp/t25.md" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || malo "hora copiada del dia 7 dio $rc, se esperaba 1: $out"
case "$out" in *'evidencia'*) ;; *) malo "T25 no nombro evidencia: [$out]" ;; esac

# T26: contracara real del 09-07 — la forma honesta `hora no recuperada`
# (siete entradas de la tanda) sigue aceptada DENTRO del cordon.
caso "T26: hora no recuperada en entrada del 09-07 => 0"
cat > "$tmp/t26.md" <<'EOF'
# Deploy log — fixture
## 2026-09-07 — PR #262 (20.3: neutralizar color de gh en postmerge) — hooks NO-OP

- **Merge (08:14 UTC — mergedAt de GitHub):** `8cf91ec25223f24773480ca02709b850c186eec0`; gate SUCCESS.
- **Deploy (hora no recuperada — no-op sin backup; mergedAt acredita el merge, no el deploy):** master sincronizado; cuatro copias
  `YA AL DIA`; sha256 sin cambios.
EOF
out="$(bash "$tool" --log "$tmp/t26.md" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "hora no recuperada del dia 7 dio $rc, se esperaba 0: $out"

# T27: contracara real del 09-07 — hora con .bak citado EN SU PROPIO bullet
# (forma #271/#264: la hora abre el bullet y los backups llegan en lineas de
# continuacion del MISMO bullet) => aceptado.
caso "T27: hora del 09-07 con .bak en su propio bullet (forma #271) => 0"
cat > "$tmp/t27.md" <<'EOF'
# Deploy log — fixture
## 2026-09-07 — PR #271 (20.6: zona de pruebas privada) — deploy REAL de las 4 copias

- **Merge (13:52 UTC — mergedAt de GitHub):** `775228d2278a9c711b0db9c8af8c4ba3a193cba0`; gate SUCCESS.
- **Deploy (13:54 PDT / 20:54 UTC):** master sincronizado; `sucio=no`,
  `coincide_origin_master=si`. Instaladores claude/grok/dsh/codex exit 0,
  cuatro copias `REPARADO`. Backups:
  `summonaikit-harness.sh.nuestro.20260907-135442.bak` (claude) y
  `20260907-135443.bak` (grok/dsh/codex).
- **Verificación:** `install-hook.sh --check` exit 0.
EOF
out="$(bash "$tool" --log "$tmp/t27.md" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "hora con .bak propio del dia 7 dio $rc, se esperaba 0: $out"

# T28 (B2, variante 1 del reviewer): el .bak del bullet Deploy de CLAUDE no
# acredita la hora del bullet de GROK — con la seccion concatenada pasaba
# (medido rc=0): cada host cita su propio respaldo o no cita hora.
caso "T28: .bak de un bullet hermano Deploy no acredita la hora de otro => 1"
cat > "$tmp/t28.md" <<'EOF'
# Deploy log — fixture
## 2026-09-08 — PR #311 / Task X — deploy REAL

- **Merge (13:29 UTC — mergedAt de GitHub):** `abc123def456`, gate SUCCESS.
- **Deploy (13:30 PDT / 20:30 UTC):** claude reusada; backup
  `summonaikit-harness.sh.nuestro.20260908-133000.bak` (claude).
- **Deploy (13:31 PDT / 20:31 UTC):** grok/dsh/codex REPARADO. Sin backup citado.
EOF
out="$(bash "$tool" --log "$tmp/t28.md" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || malo ".bak de bullet hermano dio $rc, se esperaba 1: $out"
case "$out" in *'evidencia'*) ;; *) malo "T28 no nombro evidencia: [$out]" ;; esac

# T29 (B2, variante 2 del reviewer): la NEGACION del marcador en prosa
# («no es una hora medida en vivo») no acredita — con grep -F el marcador
# casaba dentro de la negacion (medido rc=0). Solo cuenta el marcador en su
# forma estructural: dentro del MISMO parentesis que la hora.
caso "T29: negacion del marcador en prosa no acredita => 1"
cat > "$tmp/t29.md" <<'EOF'
# Deploy log — fixture
## 2026-09-08 — PR #312 / Task X — deploy REAL

- **Merge (13:29 UTC — mergedAt de GitHub):** `abc123def456`, gate SUCCESS.
- **Deploy (14:40 PDT / 21:40 UTC):** cuatro copias REPARADO; el operador
  aclara que no es una hora medida en vivo, salio copiada del merge.
EOF
out="$(bash "$tool" --log "$tmp/t29.md" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || malo "negacion del marcador dio $rc, se esperaba 1: $out"

# T30 (B2, variante 3 del reviewer): un bullet hermano Deploy que cita
# `config.bak` (backup de config, no del instalador) no acredita la hora del
# bullet que no trae respaldo (medido rc=0 con la seccion concatenada).
caso "T30: config.bak de un bullet hermano no acredita => 1"
cat > "$tmp/t30.md" <<'EOF'
# Deploy log — fixture
## 2026-09-08 — PR #313 / Task X — deploy REAL

- **Merge (13:29 UTC — mergedAt de GitHub):** `abc123def456`, gate SUCCESS.
- **Deploy (14:50 PDT / 21:50 UTC):** grok REPARADO. Sin backup citado.
- **Deploy (config restaurado de `summonaikit.json.20260908-145000.bak`):** dsh/codex reusados.
EOF
out="$(bash "$tool" --log "$tmp/t30.md" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || malo "config.bak hermano dio $rc, se esperaba 1: $out"

# T31 (B2, variante 4 del reviewer): el marcador `hora medida en vivo` en un
# bullet hermano SIN hora no acredita la hora del bullet que la cita (medido
# rc=0: el grep -F lo hallaba en la seccion).
caso "T31: marcador en bullet hermano sin hora no acredita => 1"
cat > "$tmp/t31.md" <<'EOF'
# Deploy log — fixture
## 2026-09-08 — PR #314 / Task X — deploy REAL

- **Merge (13:29 UTC — mergedAt de GitHub):** `abc123def456`, gate SUCCESS.
- **Deploy (hora medida en vivo, claude):** reusada, sin cambios.
- **Deploy (15:00 PDT / 22:00 UTC):** grok/dsh/codex REPARADO. Sin backup citado.
EOF
out="$(bash "$tool" --log "$tmp/t31.md" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || malo "marcador en bullet hermano dio $rc, se esperaba 1: $out"

# T32 (B2, extra): el marcador PELADO (sin negar) en prosa de continuacion
# del propio bullet tampoco acredita: fuera del parentesis de la hora no es
# forma estructural.
caso "T32: marcador en prosa del propio bullet (sin parentesis) => 1"
cat > "$tmp/t32.md" <<'EOF'
# Deploy log — fixture
## 2026-09-08 — PR #315 / Task X — deploy REAL

- **Merge (13:29 UTC — mergedAt de GitHub):** `abc123def456`, gate SUCCESS.
- **Deploy (14:35 PDT / 21:35 UTC):** cuatro copias REPARADO; fue hora
  medida en vivo, segun el operador. Sin backup citado.
EOF
out="$(bash "$tool" --log "$tmp/t32.md" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || malo "marcador en prosa dio $rc, se esperaba 1: $out"

# T33-T37 (r2d, adversario M1/M2/L1/L3/L4): formas que evadian la regla por
# bullet. Todas medidas en rc=0 contra la regla r2d (arteacto del adversario,
# fixtures f01/f02/f05/f16 + fence).
# T33 (M1): un `## ` falso dentro de un fence NO parte la entrada — el bullet
# Deploy con hora copiada que vive tras el fence sigue JUZGADO por la entrada.
caso "T33: fence con header falso no saca el bullet del cordón => 1"
cat > "$tmp/t33.md" <<'EOF'
# Deploy log — fixture
## 2026-09-07 — PR #316 / Task X — deploy REAL

- **Merge (21:12 UTC — mergedAt de GitHub):** `abc123def456`, gate SUCCESS.
```
## 2026-09-06 — Deploy correctivo fuera de PR: notas viejas pegadas
```
- **Deploy (21:12 UTC / 14:12 PDT, inmediatamente tras el merge):** cuatro
  copias REPARADO. Sin backup citado.
EOF
out="$(bash "$tool" --log "$tmp/t33.md" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || malo "fence con header falso dio $rc, se esperaba 1: $out"
case "$out" in *'evidencia'*) ;; *) malo "T33 no nombro evidencia: [$out]" ;; esac

# T34 (M2): la hora en un sub-bullet NEGRITA anidado del propio Deploy es
# parte del bullet (la continuacion indentada no corta la seccion) => 1.
caso "T34: hora en sub-bullet anidado del Deploy => 1"
cat > "$tmp/t34.md" <<'EOF'
# Deploy log — fixture
## 2026-09-07 — PR #317 / Task X — deploy REAL

- **Merge (21:12 UTC — mergedAt de GitHub):** `abc123def456`, gate SUCCESS.
- **Deploy:** cuatro copias REPARADO.
  - **detalle:** instalado a las 21:12 UTC, sin backup citado.
EOF
out="$(bash "$tool" --log "$tmp/t34.md" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || malo "hora en sub-bullet anidado dio $rc, se esperaba 1: $out"

# T35 (L1): bullet deploy en minuscula tambien es bullet Deploy => 1.
caso "T35: bullet deploy en minuscula con hora => 1"
cat > "$tmp/t35.md" <<'EOF'
# Deploy log — fixture
## 2026-09-07 — PR #318 / Task X — deploy REAL

- **Merge (21:12 UTC — mergedAt de GitHub):** `abc123def456`, gate SUCCESS.
- **deploy (21:12 UTC / 14:12 PDT):** cuatro copias REPARADO, sin backup.
EOF
out="$(bash "$tool" --log "$tmp/t35.md" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || malo "deploy minuscula dio $rc, se esperaba 1: $out"

# T36 (L3): NBSP dentro de la hora (copy-paste de web) no la vuelve invisible
# => 1 (se normaliza el espacio fino antes de matchear).
caso "T36: hora con NBSP sin evidencia => 1"
printf '# Deploy log — fixture\n## 2026-09-07 — PR #319 / Task X — deploy REAL\n\n- **Merge (21:12 UTC — mergedAt de GitHub):** `abc123def456`, gate SUCCESS.\n- **Deploy (21\xc2\xa0:12 UTC):** cuatro copias REPARADO, sin backup.\n' > "$tmp/t36.md"
out="$(bash "$tool" --log "$tmp/t36.md" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || malo "hora con NBSP dio $rc, se esperaba 1: $out"

# T37 (L4, contracara): el marcador ANTES de la hora dentro del MISMO
# parentesis es evidencia valida (la forma invertida de la honesta) => 0.
caso "T37: marcador antes de la hora en el mismo parentesis => 0"
cat > "$tmp/t37.md" <<'EOF'
# Deploy log — fixture
## 2026-09-08 — PR #320 / Task X — deploy REAL

- **Merge (13:29 UTC — mergedAt de GitHub):** `abc123def456`, gate SUCCESS.
- **Deploy (hora medida en vivo: 14:40 PDT / 21:40 UTC):** cuatro copias
  REPARADO; no-op no deja backup.
EOF
out="$(bash "$tool" --log "$tmp/t37.md" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "marcador antes de la hora dio $rc, se esperaba 0: $out"

# T38/T39 (r5, hallazgos (a)/(b) de la quinta revision del PR #273): el
# limite de la seccion exigia `^-[[:space:]]*\*\*` (un bullet hermano SIN
# negritas quedaba como continuacion y su .bak acreditaba la hora del Deploy,
# rc=0 medido) y la regex del marcador aceptaba una NEGACION dentro del
# parentesis («(21:12 UTC, no es una hora medida en vivo)», rc=0 medido).
# T38 (a): un `- Nota:` hermano SIN negritas con un .bak ajeno NO es
# continuacion del Deploy: cierra la seccion y la hora sin evidencia propia
# se rechaza.
caso "T38: bullet hermano sin negritas con .bak ajeno no acredita => 1"
cat > "$tmp/t38.md" <<'EOF'
# Deploy log — fixture
## 2026-09-08 — PR #330 / Task X — deploy REAL

- **Merge (13:29 UTC — mergedAt de GitHub):** `abc123def456`, gate SUCCESS.
- **Deploy (14:50 PDT / 21:50 UTC):** grok REPARADO. Sin backup citado.
- Nota: backup ajeno config.bak.
EOF
out="$(bash "$tool" --log "$tmp/t38.md" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || malo "bullet hermano sin negritas dio $rc, se esperaba 1: $out"
case "$out" in *'evidencia'*) ;; *) malo "T38 no nombro evidencia: [$out]" ;; esac

# T39 (b): la NEGACION del marcador dentro del parentesis no es etiqueta
# adyacente (pegada al parentesis que abre o inmediatamente tras coma) y no
# acredita la hora que niega.
caso "T39: negacion del marcador dentro del parentesis => 1"
cat > "$tmp/t39.md" <<'EOF'
# Deploy log — fixture
## 2026-09-08 — PR #331 / Task Y — deploy REAL

- **Merge (21:12 UTC — mergedAt de GitHub):** `abc123def456`, gate SUCCESS.
- **Deploy (21:12 PDT / 21:12 UTC, no es una hora medida en vivo):** cuatro
  copias REPARADO, sin backup citado.
EOF
out="$(bash "$tool" --log "$tmp/t39.md" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || malo "negacion dentro del parentesis dio $rc, se esperaba 1: $out"
case "$out" in *'evidencia'*) ;; *) malo "T39 no nombro evidencia: [$out]" ;; esac

# T40-T42 (r5, adversario M1/M3/M2): las tres formas medidas en rojo contra
# el corte r5 (negacion tras etiqueta acreditaba; la raya honesta se
# rechazaba; la hora en un bullet hermano sin negritas escapaba).
caso "T40: negacion DESPUES de la etiqueta no acredita => 1"
cat > "$tmp/t40.md" <<'EOF'
# Deploy log — fixture
## 2026-09-07 — PR #321 / Task X — deploy REAL

- **Merge (21:12 UTC — mergedAt de GitHub):** `abc123def456`, gate SUCCESS.
- **Deploy (14:30, hora medida en vivo no es):** cuatro copias REPARADO, sin backup.
EOF
out="$(bash "$tool" --log "$tmp/t40.md" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || malo "negacion tras etiqueta dio $rc, se esperaba 1: $out"

# T41 (M3): contracara honesta con RAYA — la forma «(14:30 — hora medida en
# vivo)» es etiqueta valida (la raya se normaliza a coma).
caso "T41: etiqueta honesta tras raya => 0"
cat > "$tmp/t41.md" <<'EOF'
# Deploy log — fixture
## 2026-09-07 — PR #322 / Task X — deploy REAL

- **Merge (21:12 UTC — mergedAt de GitHub):** `abc123def456`, gate SUCCESS.
- **Deploy (14:30 — hora medida en vivo):** cuatro copias REPARADO.
EOF
out="$(bash "$tool" --log "$tmp/t41.md" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "etiqueta tras raya dio $rc, se esperaba 0: $out"

# T42 (M2): la hora de un deploy que vive en un bullet hermano SIN negritas
# tambien se juzga (solo el bullet de Merge esta exento).
caso "T42: hora en bullet hermano sin negritas => 1"
cat > "$tmp/t42.md" <<'EOF'
# Deploy log — fixture
## 2026-09-07 — PR #323 / Task X — deploy REAL

- **Merge (21:12 UTC — mergedAt de GitHub):** `abc123def456`, gate SUCCESS.
- **Deploy:** cuatro copias REPARADO.
- hora final del deploy: 21:12 UTC, sin backup.
EOF
out="$(bash "$tool" --log "$tmp/t42.md" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || malo "hora en hermano sin negritas dio $rc, se esperaba 1: $out"

# T43-T45 (r6): tiempos ajenos al Deploy no son una afirmacion de hora de
# deploy. El cordon de 20.27 debe juzgar el bullet Deploy y cortar su seccion
# ante cualquier bullet hermano, sin convertir horas de verificacion,
# duraciones o puertos en deployed_at.
caso "T43: hora de verificacion no es hora de deploy => 0"
cat > "$tmp/t43.md" <<'EOF'
# Deploy log — fixture
## 2026-09-08 — PR #324 / Task X — deploy NO-OP

- **Merge (21:12 UTC — mergedAt de GitHub):** `abc123def456`, gate SUCCESS.
- **Deploy (hora no recuperada — no-op sin backup):** cuatro copias YA AL DIA.
- **Verificacion (21:15 UTC):** gate y registro completados.
EOF
out="$(bash "$tool" --log "$tmp/t43.md" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "hora de verificacion dio $rc, se esperaba 0: $out"

caso "T44: duracion mm:ss no es hora de deploy => 0"
cat > "$tmp/t44.md" <<'EOF'
# Deploy log — fixture
## 2026-09-08 — PR #325 / Task X — deploy NO-OP

- **Merge (21:12 UTC — mergedAt de GitHub):** `abc123def456`, gate SUCCESS.
- **Deploy (hora no recuperada — no-op sin backup):** cuatro copias YA AL DIA.
- **Verificacion:** suite completada en 2:58.
EOF
out="$(bash "$tool" --log "$tmp/t44.md" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "duracion mm:ss dio $rc, se esperaba 0: $out"

caso "T45: puerto de URL no es hora de deploy => 0"
cat > "$tmp/t45.md" <<'EOF'
# Deploy log — fixture
## 2026-09-08 — PR #326 / Task X — deploy NO-OP

- **Merge (21:12 UTC — mergedAt de GitHub):** `abc123def456`, gate SUCCESS.
- **Deploy (hora no recuperada — no-op sin backup):** cuatro copias YA AL DIA.
- **Verificacion:** `curl http://127.0.0.1:3000/health` respondio 200.
EOF
out="$(bash "$tool" --log "$tmp/t45.md" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "puerto de URL dio $rc, se esperaba 0: $out"

caso "T46: rotulo hora de verificacion del deploy no es deployed_at => 0"
cat > "$tmp/t46.md" <<'EOF'
# Deploy log — fixture
## 2026-09-08 — PR #327 / Task X — deploy NO-OP

- **Merge (21:12 UTC — mergedAt de GitHub):** `abc123def456`, gate SUCCESS.
- **Deploy (hora no recuperada — no-op sin backup):** cuatro copias YA AL DIA.
- hora de verificacion del deploy: 21:15 UTC, gate completado.
EOF
out="$(bash "$tool" --log "$tmp/t46.md" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "hora de verificacion del deploy dio $rc, se esperaba 0: $out"

caso "T47: rotulo negrita cerrado antes de dos puntos sigue siendo Deploy => 1"
cat > "$tmp/t47.md" <<'EOF'
# Deploy log — fixture
## 2026-09-08 — PR #328 / Task X — deploy REAL

- **Merge (21:12 UTC — mergedAt de GitHub):** `abc123def456`, gate SUCCESS.
- **Deploy**: cuatro copias REPARADO a las 21:12 UTC, sin backup.
EOF
out="$(bash "$tool" --log "$tmp/t47.md" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || malo "rotulo **Deploy** dio $rc, se esperaba 1: $out"

caso "T48: Deploy explicito anidado tambien se juzga => 1"
cat > "$tmp/t48.md" <<'EOF'
# Deploy log — fixture
## 2026-09-08 — PR #329 / Task X — deploy REAL

- **Merge (21:12 UTC — mergedAt de GitHub):** `abc123def456`, gate SUCCESS.
- Notas de la corrida:
  - **Deploy (21:12 UTC):** cuatro copias REPARADO, sin backup.
EOF
out="$(bash "$tool" --log "$tmp/t48.md" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || malo "Deploy anidado dio $rc, se esperaba 1: $out"

caso "T49: hora del deploy llana tambien se juzga => 1"
cat > "$tmp/t49.md" <<'EOF'
# Deploy log — fixture
## 2026-09-08 — PR #332 / Task X — deploy REAL

- **Merge (21:12 UTC — mergedAt de GitHub):** `abc123def456`, gate SUCCESS.
- hora del deploy: 21:12 UTC, sin backup.
EOF
out="$(bash "$tool" --log "$tmp/t49.md" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || malo "hora del deploy dio $rc, se esperaba 1: $out"

caso "T50: rotulo Deploy llano tambien se juzga => 1"
cat > "$tmp/t50.md" <<'EOF'
# Deploy log — fixture
## 2026-09-08 — PR #333 / Task X — deploy REAL

- **Merge (21:12 UTC — mergedAt de GitHub):** `abc123def456`, gate SUCCESS.
- Deploy: cuatro copias REPARADO a las 21:12 UTC, sin backup.
EOF
out="$(bash "$tool" --log "$tmp/t50.md" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || malo "Deploy llano dio $rc, se esperaba 1: $out"

caso "T51: hora final del deploy en negritas tambien se juzga => 1"
cat > "$tmp/t51.md" <<'EOF'
# Deploy log — fixture
## 2026-09-08 — PR #334 / Task X — deploy REAL

- **Merge (21:12 UTC — mergedAt de GitHub):** `abc123def456`, gate SUCCESS.
- **hora final del deploy:** 21:12 UTC, sin backup.
EOF
out="$(bash "$tool" --log "$tmp/t51.md" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || malo "hora final del deploy en negritas dio $rc, se esperaba 1: $out"

caso "T52: Deploy anidado con evidencia propia => 0"
cat > "$tmp/t52.md" <<'EOF'
# Deploy log — fixture
## 2026-09-08 — PR #335 / Task X — deploy REAL

- **Merge (21:12 UTC — mergedAt de GitHub):** `abc123def456`, gate SUCCESS.
- Notas de la corrida:
  - **Deploy (21:12 UTC):** backup propio `summonaikit-harness.sh.bak`.
EOF
out="$(bash "$tool" --log "$tmp/t52.md" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "Deploy anidado con evidencia dio $rc, se esperaba 0: $out"

caso "T53: hermano anidado no presta evidencia al Deploy => 1"
cat > "$tmp/t53.md" <<'EOF'
# Deploy log — fixture
## 2026-09-08 — PR #336 / Task X — deploy REAL

- **Merge (21:12 UTC — mergedAt de GitHub):** `abc123def456`, gate SUCCESS.
- Notas de la corrida:
  - **Deploy (21:12 UTC):** cuatro copias REPARADO, sin backup.
  - Nota: backup ajeno `summonaikit-harness.sh.bak`.
EOF
out="$(bash "$tool" --log "$tmp/t53.md" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || malo "hermano anidado presto evidencia: rc=$rc, se esperaba 1: $out"

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

# r4 (hallazgo B1): devolver el cordon al 09-08 reabre el hueco del historico
# reparado — con el mutante, T25 (la forma real del #272 del dia 7) vuelve a
# pasar. Control sano inmediatamente antes: T25 en rojo con el checker vivo.
caso "mutacion: cordon HORA_CONTROL devuelto al 09-08 => T25 la atrapa"
out="$(bash "$tool" --log "$tmp/t25.md" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || malo "control sano T25 dio $rc, se esperaba 1 (cordon vivo)"
mut_hc_base="$tmp/mut-base-hc.sh"; mut_hc="$tmp/mut-hc.sh"
cp "$tool" "$mut_hc_base"
sed "s/HORA_CONTROL='2026-09-07'/HORA_CONTROL='2026-09-08'/" "$mut_hc_base" > "$mut_hc"
if cmp -s "$mut_hc_base" "$mut_hc"; then
  malo "mutacion cordon-09-08 no cambio nada — el sed quedo obsoleto"
elif ! bash -n "$mut_hc" 2>/dev/null; then
  malo "mutacion cordon-09-08 no parsea; asi no prueba nada"
else
  out="$(bash "$mut_hc" --log "$tmp/t25.md" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then
    printf '    mutacion cordon-09-08 atrapada (T25 en rojo)\n'
  elif [ "$rc" -eq 1 ]; then
    malo "mutacion cordon-09-08 SOBREVIVIO: la tanda del dia 7 volvio a quedar fuera"
  else
    malo "mutacion cordon-09-08 invalida (rc=$rc, se esperaba el flip 1->0)"
  fi
fi

# r4 (hallazgo B2): anular el separador de bullets re-arma la seccion
# concatenada (la evidencia de un bullet hermano vuelve a acreditar la hora
# de otro) — con el mutante, T28 pasa. Control sano antes: T28 en rojo.
caso "mutacion: separador de bullets anulado => T28 la atrapa"
out="$(bash "$tool" --log "$tmp/t28.md" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || malo "control sano T28 dio $rc, se esperaba 1 (regla viva)"
mut_sep_base="$tmp/mut-base-sep.sh"; mut_sep="$tmp/mut-sep.sh"
cp "$tool" "$mut_sep_base"
sed 's/if (n++) print sep/if (0) print sep/' "$mut_sep_base" > "$mut_sep"
if cmp -s "$mut_sep_base" "$mut_sep"; then
  malo "mutacion separador-anulado no cambio nada — el sed quedo obsoleto"
elif ! bash -n "$mut_sep" 2>/dev/null; then
  malo "mutacion separador-anulado no parsea; asi no prueba nada"
else
  out="$(bash "$mut_sep" --log "$tmp/t28.md" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then
    printf '    mutacion separador-anulado atrapada (T28 en rojo)\n'
  elif [ "$rc" -eq 1 ]; then
    malo "mutacion separador-anulado SOBREVIVIO: la seccion volvio a concatenarse"
  else
    malo "mutacion separador-anulado invalida (rc=$rc, se esperaba el flip 1->0)"
  fi
fi

# r5: mutaciones propias de los DOS cambios del checker (limite de bullet sin
# negritas; etiqueta del marcador). La discriminancia la habia probado el
# verificador con copias revertidas; la bateria la posee ahora.
caso "mutacion: solo bullets Deploy abren seccion => T42 la atrapa"
out="$(bash "$tool" --log "$tmp/t42.md" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || malo "control sano T42 dio $rc, se esperaba 1 (regla viva)"
mut_lb_base="$tmp/mut-base-lb.sh"; mut_lb="$tmp/mut-lb.sh"
cp "$tool" "$mut_lb_base"
python3 - "$mut_lb_base" "$mut_lb" <<'PY_LB'
import sys
src = open(sys.argv[1], encoding="utf-8").read()
viejo = "    /^-/ { if (n++) print sep; dentro = 1; print; next }\n"
nuevo = ("    /^-[[:space:]]*\\*\\*[Dd]eploy/ { if (n++) print sep; dentro = 1; print; next }\n"
         "    /^-/                           { dentro = 0 }\n")
assert src.count(viejo) == 1, src.count(viejo)
open(sys.argv[2], "w", encoding="utf-8").write(src.replace(viejo, nuevo))
PY_LB
if cmp -s "$mut_lb_base" "$mut_lb"; then
  malo "mutacion solo-deploy no cambio nada — el sed quedo obsoleto"
elif ! bash -n "$mut_lb" 2>/dev/null; then
  malo "mutacion solo-deploy no parsea; asi no prueba nada"
else
  out="$(bash "$mut_lb" --log "$tmp/t42.md" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then
    printf '    mutacion solo-deploy atrapada (T42 en rojo)\n'
  elif [ "$rc" -eq 1 ]; then
    malo "mutacion solo-deploy SOBREVIVIO: la hora del hermano sin negritas vuelve a escapar"
  else
    malo "mutacion solo-deploy invalida (rc=$rc, se esperaba el flip 1->0)"
  fi
fi

# r6: volver a juzgar todos los bullets SALVO Merge reproduce fielmente el
# falso positivo que confundia una hora de Verificacion con deployed_at.
caso "mutacion: todos salvo Merge vuelven a ser juzgables => T43 la atrapa"
out="$(bash "$tool" --log "$tmp/t43.md" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "control sano T43 dio $rc, se esperaba 0 (scope vivo)"
mut_scope_base="$tmp/mut-base-scope.sh"; mut_scope="$tmp/mut-scope.sh"
cp "$tool" "$mut_scope_base"
python3 - "$mut_scope_base" "$mut_scope" <<'PY_SCOPE'
import sys
src = open(sys.argv[1], encoding="utf-8").read()
viejo = "      return etiqueta ~ /^(deploy|hora[[:space:]]+(final[[:space:]]+)?del[[:space:]]+deploy)([[:space:](]|:|$)/\n"
nuevo = "      return etiqueta !~ /^merge([[:space:](]|:|$)/\n"
assert src.count(viejo) == 1, src.count(viejo)
open(sys.argv[2], "w", encoding="utf-8").write(src.replace(viejo, nuevo))
PY_SCOPE
if cmp -s "$mut_scope_base" "$mut_scope"; then
  malo "mutacion scope-todos no cambio nada — el reemplazo quedo obsoleto"
elif ! bash -n "$mut_scope" 2>/dev/null; then
  malo "mutacion scope-todos no parsea; asi no prueba nada"
else
  out="$(bash "$mut_scope" --log "$tmp/t43.md" 2>&1)"; rc=$?
  if [ "$rc" -eq 1 ]; then
    printf '    mutacion scope-todos atrapada (T43 en rojo)\n'
  elif [ "$rc" -eq 0 ]; then
    malo "mutacion scope-todos SOBREVIVIO: hora de Verificacion aceptada como deploy"
  else
    malo "mutacion scope-todos invalida (rc=$rc, se esperaba el flip 0->1)"
  fi
fi

# El cierre Markdown `**` tambien forma parte del rotulo; dejarlo pegado al
# texto debe reabrir el bypass de T47.
caso "mutacion: cierre negrita de Deploy ignorado => T47 la atrapa"
out="$(bash "$tool" --log "$tmp/t47.md" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || malo "control sano T47 dio $rc, se esperaba 1 (rotulo vivo)"
mut_bold_base="$tmp/mut-base-bold.sh"; mut_bold="$tmp/mut-bold.sh"
cp "$tool" "$mut_bold_base"
python3 - "$mut_bold_base" "$mut_bold" <<'PY_BOLD'
import sys
src = open(sys.argv[1], encoding="utf-8").read()
viejo = '        sub(/\\*\\*.*/, "", etiqueta)\n'
nuevo = '        sub(/\\*\\*.*/, "**", etiqueta)\n'
assert src.count(viejo) == 1, src.count(viejo)
open(sys.argv[2], "w", encoding="utf-8").write(src.replace(viejo, nuevo))
PY_BOLD
if cmp -s "$mut_bold_base" "$mut_bold"; then
  malo "mutacion cierre-negrita no cambio nada — el reemplazo quedo obsoleto"
elif ! bash -n "$mut_bold" 2>/dev/null; then
  malo "mutacion cierre-negrita no parsea; asi no prueba nada"
else
  out="$(bash "$mut_bold" --log "$tmp/t47.md" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then
    printf '    mutacion cierre-negrita atrapada (T47 en verde indebido)\n'
  elif [ "$rc" -eq 1 ]; then
    malo "mutacion cierre-negrita SOBREVIVIO: **Deploy** siguio juzgado"
  else
    malo "mutacion cierre-negrita invalida (rc=$rc, se esperaba el flip 1->0)"
  fi
fi

# Un Deploy anidado bajo un padre no-Deploy sigue siendo una afirmacion
# propia. Volver a reconocer solo bullets en columna cero reabre A1.
caso "mutacion: Deploy anidado ignorado => T48 la atrapa"
out="$(bash "$tool" --log "$tmp/t48.md" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || malo "control sano T48 dio $rc, se esperaba 1 (anidado vivo)"
mut_nested_base="$tmp/mut-base-nested.sh"; mut_nested="$tmp/mut-nested.sh"
cp "$tool" "$mut_nested_base"
python3 - "$mut_nested_base" "$mut_nested" <<'PY_NESTED'
import sys
src = open(sys.argv[1], encoding="utf-8").read()
viejo = "    /^[[:space:]]*-/ {\n"
nuevo = "    /^-/ {\n"
assert src.count(viejo) == 1, src.count(viejo)
open(sys.argv[2], "w", encoding="utf-8").write(src.replace(viejo, nuevo))
PY_NESTED
if cmp -s "$mut_nested_base" "$mut_nested"; then
  malo "mutacion anidado no cambio nada — el reemplazo quedo obsoleto"
elif ! bash -n "$mut_nested" 2>/dev/null; then
  malo "mutacion anidado no parsea; asi no prueba nada"
else
  out="$(bash "$mut_nested" --log "$tmp/t48.md" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then
    printf '    mutacion anidado atrapada (T48 en verde indebido)\n'
  elif [ "$rc" -eq 1 ]; then
    malo "mutacion anidado SOBREVIVIO: Deploy anidado siguio juzgado"
  else
    malo "mutacion anidado invalida (rc=$rc, se esperaba el flip 1->0)"
  fi
fi

# Las dos ramas del rotulo llano son parte del contrato y deben tener poder
# discriminante propio: `hora del deploy` y `Deploy:`.
caso "mutacion: hora del deploy exige final => T49 la atrapa"
mut_hora_base="$tmp/mut-base-hora.sh"; mut_hora="$tmp/mut-hora.sh"
cp "$tool" "$mut_hora_base"
sed 's/(final\[\[:space:\]\]+)?/final[[:space:]]+/' "$mut_hora_base" > "$mut_hora"
if cmp -s "$mut_hora_base" "$mut_hora"; then
  malo "mutacion hora-del no cambio nada — el sed quedo obsoleto"
elif ! bash -n "$mut_hora" 2>/dev/null; then
  malo "mutacion hora-del no parsea; asi no prueba nada"
else
  out="$(bash "$mut_hora" --log "$tmp/t49.md" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then
    printf '    mutacion hora-del atrapada (T49 en verde indebido)\n'
  else
    malo "mutacion hora-del no produjo flip 1->0 (rc=$rc)"
  fi
fi

caso "mutacion: Deploy llano ignorado => T50 la atrapa"
mut_plain_base="$tmp/mut-base-plain.sh"; mut_plain="$tmp/mut-plain.sh"
cp "$tool" "$mut_plain_base"
python3 - "$mut_plain_base" "$mut_plain" <<'PY_PLAIN'
import sys
src = open(sys.argv[1], encoding="utf-8").read()
viejo = '      } else {\n        sub(/:[[:space:]].*$/, "", etiqueta)\n'
nuevo = '      } else {\n        if (etiqueta ~ /^deploy/) etiqueta = "otro"\n        sub(/:[[:space:]].*$/, "", etiqueta)\n'
assert src.count(viejo) == 1, src.count(viejo)
open(sys.argv[2], "w", encoding="utf-8").write(src.replace(viejo, nuevo))
PY_PLAIN
if cmp -s "$mut_plain_base" "$mut_plain"; then
  malo "mutacion Deploy-llano no cambio nada — el reemplazo quedo obsoleto"
elif ! bash -n "$mut_plain" 2>/dev/null; then
  malo "mutacion Deploy-llano no parsea; asi no prueba nada"
else
  out="$(bash "$mut_plain" --log "$tmp/t50.md" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then
    printf '    mutacion Deploy-llano atrapada (T50 en verde indebido)\n'
  else
    malo "mutacion Deploy-llano no produjo flip 1->0 (rc=$rc)"
  fi
fi

# La variante en negritas de `hora final del deploy` usa la misma gramatica,
# pero una mutacion exclusiva garantiza que no dependa solo de las formas
# `**Deploy**`.
caso "mutacion: hora del deploy en negritas ignorada => T51 la atrapa"
mut_bhora_base="$tmp/mut-base-bhora.sh"; mut_bhora="$tmp/mut-bhora.sh"
cp "$tool" "$mut_bhora_base"
python3 - "$mut_bhora_base" "$mut_bhora" <<'PY_BHORA'
import sys
src = open(sys.argv[1], encoding="utf-8").read()
viejo = '        sub(/^\\*\\*/, "", etiqueta)\n'
nuevo = '        sub(/^\\*\\*hora/, "horaXXX", etiqueta)\n        sub(/^\\*\\*/, "", etiqueta)\n'
assert src.count(viejo) == 1, src.count(viejo)
open(sys.argv[2], "w", encoding="utf-8").write(src.replace(viejo, nuevo))
PY_BHORA
if cmp -s "$mut_bhora_base" "$mut_bhora"; then
  malo "mutacion hora-negrita no cambio nada — el reemplazo quedo obsoleto"
elif ! bash -n "$mut_bhora" 2>/dev/null; then
  malo "mutacion hora-negrita no parsea; asi no prueba nada"
else
  out="$(bash "$mut_bhora" --log "$tmp/t51.md" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then
    printf '    mutacion hora-negrita atrapada (T51 en verde indebido)\n'
  else
    malo "mutacion hora-negrita no produjo flip 1->0 (rc=$rc)"
  fi
fi

caso "mutacion: terminador de la etiqueta anulado => T40 la atrapa"
out="$(bash "$tool" --log "$tmp/t40.md" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || malo "control sano T40 dio $rc, se esperaba 1 (regla viva)"
mut_et_base="$tmp/mut-base-et.sh"; mut_et="$tmp/mut-et.sh"
cp "$tool" "$mut_et_base"
python3 - "$mut_et_base" "$mut_et" <<'PY_ET'
import sys
src = open(sys.argv[1], encoding="utf-8").read()
pares = [
  (",[[:space:]]*hora medida en vivo[)]", "[^)]*hora medida en vivo[^)]*[)]"),
  ("hora medida en vivo:[^)]*", "hora medida en vivo[^)]*"),
]
for viejo, nuevo in pares:
    assert src.count(viejo) == 1, (viejo, src.count(viejo))
    src = src.replace(viejo, nuevo)
open(sys.argv[2], "w", encoding="utf-8").write(src)
PY_ET
if cmp -s "$mut_et_base" "$mut_et"; then
  malo "mutacion etiqueta-laxa no cambio nada — el reemplazo quedo obsoleto"
elif ! bash -n "$mut_et" 2>/dev/null; then
  malo "mutacion etiqueta-laxa no parsea; asi no prueba nada"
else
  out="$(bash "$mut_et" --log "$tmp/t40.md" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then
    printf '    mutacion terminador-anulado atrapada (T40 en rojo)\n'
  elif [ "$rc" -eq 1 ]; then
    malo "mutacion terminador-anulado SOBREVIVIO: la negacion tras la etiqueta vuelve a acreditar"
  else
    malo "mutacion etiqueta-laxa invalida (rc=$rc, se esperaba el flip 1->0)"
  fi
fi

if [ "$fail" -ne 0 ]; then
  echo "test_deploy_log: FAIL" >&2
  exit 1
fi
echo "test_deploy_log: OK"
