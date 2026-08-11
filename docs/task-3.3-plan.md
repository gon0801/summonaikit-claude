# Task 3.3 — A3: `TEST_RUNNER_RE` sin fronteras de palabra (plan corregido)

Revisión aplicada sobre el borrador. El arreglo propuesto era correcto y se
conserva; lo que cambia son dos defectos bloqueantes y cuatro imprecisiones,
todos medidos contra el hook vivo (970 líneas, post-3.2) y no supuestos.

**Qué cambió respecto del borrador**

1. La mutación propuesta **no mutaba** — reproducido. Sed corregido.
2. El `.` de la clase de exclusión **muerde la prosa** del Stop gate: un recibo
   que termina la frase con punto pierde el crédito. Lado derecho refinado.
3. El escenario 13 **no tiene paso 04 ni Stop**: el diff declarado era inventado.
4. Faltaba el caso positivo `./node_modules/.bin/vitest run`, que la DoD nombra.
5. Los límites estaban mal ejemplificados (`tsconfig.json` no falla por el `.`).
6. Conteo de mutaciones: **20**, no 21. Y el caso de la excusa estaba mal
   nombrado.

---

## El defecto, con su huella exacta

`TEST_RUNNER_RE` (`hooks/summonaikit-harness.sh:50`) enumera los runners de
test/lint/typecheck conocidos, pero **sin fronteras de palabra**. Los dos greps
que lo usan hacen match por subcadena:

- `tool_gate` (`:729`): `printf '%s' "$tool_name $command_text" | grep -Eiq "$TEST_RUNNER_RE"` → si matchea, marca `verified=1`.
- `stop_gate` (`:870`): `grep -Eiq "$TEST_RUNNER_RE|not run|..."` → si matchea, suprime el reclamo "Missing verification evidence".

**Medido en el escenario 13 de la línea base**: `cat pytest.log` matchea el
fragmento `pytest` y marca el turno como verificado; `cat tsconfig.json` matchea
`tsc` y añade una segunda entrada `verified:`. Ninguno de los dos corrió nada.

**Las dos superficies no son la misma clase de texto**, y esto es lo que el
borrador pasó por alto: `:729` recibe un **comando**; `:870`, desde la 3.2,
recibe **prosa del asistente** ya decodificada. Un criterio calibrado sólo para
comandos rompe la prosa.

## El arreglo

Una constante wrapper que exige que el runner esté flanqueado por start/end o un
carácter que no forme parte de un nombre de archivo:

```sh
TEST_RUNNER_WORD_RE='(^|[^A-Za-z0-9_.-])('"$TEST_RUNNER_RE"')([^A-Za-z0-9_.-]|\.([^A-Za-z0-9]|$)|$)'
```

Reemplazar `"$TEST_RUNNER_RE"` por `"$TEST_RUNNER_WORD_RE"` en los dos greps
(`:729` y `:870`). `TEST_RUNNER_RE` se mantiene intacto como única fuente de la
lista de runners — el wrapper lo referencia, no lo duplica.

**El lado derecho tiene tres alternativas, y la del medio es la CORRECCIÓN 2**:

| alternativa | qué acepta | por qué |
|---|---|---|
| `[^A-Za-z0-9_.-]` | `pytest -q`, `pytest,` | el caso normal en comando y en prosa |
| `\.([^A-Za-z0-9]|$)` | `pytest.` al final de frase | un punto **no** seguido de alfanumérico no es una extensión |
| `$` | `... npm run test` | fin de línea |

Un punto seguido de alfanumérico (`pytest.log`, `tsconfig.json`) queda fuera de
las tres: es la extensión de un archivo, que es exactamente A3.

**Verificado contra el `TEST_RUNNER_RE` real** (no contra un regex de ejemplo):

```
cat pytest.log                        viejo=SI  nuevo=no
cat pytest.log y listo                viejo=SI  nuevo=no
cat tsconfig.json                     viejo=SI  nuevo=no
pytest -q                             viejo=SI  nuevo=SI
./node_modules/.bin/vitest run        viejo=SI  nuevo=SI
python -m pytest                      viejo=SI  nuevo=SI
Verify: se corrio pytest.             viejo=SI  nuevo=SI
Verify: se corrio pytest. Todo verde  viejo=SI  nuevo=SI
Verify: corri la bateria con vitest.  viejo=SI  nuevo=SI
```

Los cuatro puntos de la DoD del renglón quedan cubiertos, y la prosa no se rompe.

**Por qué NO alcanza el wrapper simple del borrador**
(`([^A-Za-z0-9_.-]|$)` a secas): con él, `Verify: se corrio pytest.` deja de
contar — medido. Terminar una oración con punto es lo normal, y ese grep es
justo el que decide cuando el evento `PostToolUse` no marcó `verified=1` (el caso
del runner que corrió dentro de un subagente, A9). Reintroduce el mismo tipo de
daño que la 3.2 acaba de cerrar en A8: exigir de más.

**Límites declarados, con los ejemplos que sí ocurren** (medidos, no supuestos):

- (a) Un runner citado como palabra completa en un comando que no lo ejecuta
  (`grep vitest config.ts`) sigue contando. Distinguir "en posición de comando"
  es otra clase de arreglo, no fronteras de palabra.
- (b) Un runner con sufijo pegado por guión pierde el crédito:
  `npm run test-e2e` → no cuenta (medido). Cae al lado estricto: sin crédito
  automático, el gate pide la razón explícita, que es recuperable; lo contrario
  —acreditar `cat pytest-viejo.log`— es el defecto que se está cerrando.
- (c) Un ejecutable con extensión pierde el crédito:
  `.venv/Scripts/pytest.exe -q` → no cuenta (medido). Importa declararlo porque
  el operador trabaja en Windows. Mismo razonamiento que (b).
- (d) `cat tsconfig.json` no matchea porque a `tsc` le sigue la `o` de
  `tsconfig`, **no** por el punto. La conclusión del borrador era correcta; la
  razón, no. Se corrige acá para que nadie derive de ella un criterio falso.

## Confirmado del borrador: la concatenación con las excusas es correcta

En `:870` el wrapper queda como
`"$TEST_RUNNER_WORD_RE|not run|not executed|skipped|non eseguit|saltat"`. En ERE
la `|` tiene la precedencia más baja y `^`/`$` son anclas en cualquier posición,
así que el grupo wrapper y las excusas son alternativas independientes.
Verificado: `Verify: skipped, este repo no tiene bateria propia` sigue
suprimiendo el reclamo.

El caso que lo cubre es **`caso_g2_excusa_declarada_no_reclama`** (usa
`_RECIBO_SIN_RETRO_SALTEADO`), no `caso_g4_falta_una_etiqueta_bloquea` como decía
el borrador.

---

## Cambios

### 1. `hooks/summonaikit-harness.sh`

Después de la línea 50 (`TEST_RUNNER_RE='...'`):

```sh
# Wrapper con fronteras de palabra: el runner debe estar flanqueado por
# start/end o un caracter que NO forme parte de un nombre de archivo. Cierra A3
# (Task 3.3): sin esto, `cat pytest.log` matchea el fragmento `pytest` y cuenta
# como verificacion.
#
# El lado derecho acepta un punto que NO va seguido de alfanumerico. No es
# cosmetico: este regex se aplica a DOS superficies distintas -- el comando de
# un evento (:729) y la PROSA del asistente (:870, texto decodificado desde la
# 3.2). Sin esa alternativa, `Verify: se corrio pytest.` deja de contar y el
# gate exige de mas, que es el daño que la 3.2 acaba de cerrar en A8. Con ella,
# `pytest.log` sigue sin contar: ahi el punto va seguido de `l`.
#
# Limites declarados y medidos: `npm run test-e2e` y `pytest.exe` NO cuentan
# (sufijo pegado por guion / extension). Cae al lado estricto a proposito: sin
# credito el gate pide la razon explicita, que es recuperable; acreditar
# `cat pytest-viejo.log` no lo es.
TEST_RUNNER_WORD_RE='(^|[^A-Za-z0-9_.-])('"$TEST_RUNNER_RE"')([^A-Za-z0-9_.-]|\.([^A-Za-z0-9]|$)|$)'
```

- Línea 729 (`tool_gate`): `"$TEST_RUNNER_RE"` → `"$TEST_RUNNER_WORD_RE"`.
- Línea 870 (`stop_gate`): `"$TEST_RUNNER_RE|not run|..."` →
  `"$TEST_RUNNER_WORD_RE|not run|..."`.

### 2. `tests/lib/gate_cases.sh` — G2 (regla de hierro #2)

**Nuevo** `caso_g2_runner_en_path_no_marca` — el caso que habría atrapado A3:

```sh
caso_g2_runner_en_path_no_marca() {
  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_bash 'cat pytest.log')"
  _igual "exit code" "$LAB_RC" "0"
  _igual "verified con cat pytest.log (A3)" "$(lab_estado verified)" "0"
  lab_run tool claude "$(lab_payload_bash 'cat tsconfig.json')"
  _igual "verified con cat tsconfig.json (A3)" "$(lab_estado verified)" "0"
}
```

**Nuevo** `caso_g2_runner_con_ruta_marca` — la vía legítima que el wrapper NO
debe romper. La DoD del renglón lo nombra explícitamente y el borrador lo
omitía; es el que prueba que el `.` de la clase no muerde `./node_modules/.bin/`:

```sh
caso_g2_runner_con_ruta_marca() {
  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_bash './node_modules/.bin/vitest run')"
  _igual "verified con el runner invocado por ruta" "$(lab_estado verified)" "1"
}
```

**Nuevo** `caso_g2_excusa_con_punto_final_no_reclama` — la CORRECCIÓN 2, atada
como test. Sin él, el wrapper simple del borrador pasaría toda la batería y el
daño en prosa saldría recién en producción:

```sh
caso_g2_excusa_con_punto_final_no_reclama() {
  lab_sembrar 123456 0 1 0 "implementer,verifier,reviewer"
  lab_run stop claude "$(lab_payload_stop "$_RECIBO_SIN_RETRO_PYTEST_PUNTO")"
  _contiene "motivo" "$LAB_OUT" 'Missing Retro gate summary'
  _no_contiene "motivo" "$LAB_OUT" 'Missing verification evidence'
}
```

Necesita un fixture nuevo junto a los otros recibos, con la línea
`Verify: se corrio pytest.` (punto final, sin nada después).

**Mantener**: `caso_g2_runner_marca_verificado` (`pytest -q` sigue marcando) y
`caso_g2_sin_runner_no_marca` (`cat README.md`) — este último no prueba nada
sobre fronteras (no contiene ningún fragmento de runner), por eso no alcanzaba
con mantenerlo, como el borrador ya había detectado.

**Orden en `CASOS_G2`** (load-bearing: la batería corta en el primer rojo y la
declaración nombra ese caso). Los tres nuevos van **al final**, después de
`caso_g2_excusa_declarada_no_reclama`, para no robarle la declaración a
`mut_runner_sin_pytest` (que sigue siendo atrapada por
`caso_g2_runner_marca_verificado`, el primero de la lista).

### 3. `tests/test_gate_mutations.sh`

**Nueva mutación** — el sed del borrador **no mutaba**, reproducido:

```sh
# INCORRECTO (borrador): sed 's/TEST_RUNNER_WORD_RE/TEST_RUNNER_RE/g'
# Toca tambien la linea de definicion y la deja como
#   TEST_RUNNER_RE='(^|[^...])('"$TEST_RUNNER_RE"')(...)'
# La expansion ocurre al asignar, asi que el wrapper SOBREVIVE intacto y solo
# cambia el nombre de la variable. El archivo cambia y parsea (las guardias 2 y
# 3 pasan), pero el hook mutado se comporta igual que el sano: ningun caso se
# pone rojo y la bateria corta con "ningun caso detecto que [...]".
mut_runner_sin_frontera() { sed 's/^TEST_RUNNER_WORD_RE=.*/TEST_RUNNER_WORD_RE="$TEST_RUNNER_RE"/'; }
```

Así el wrapper pasa a ser la lista pelada en **los dos** greps, y la atrapa
`caso_g2_runner_en_path_no_marca` (`cat pytest.log` vuelve a marcar
`verified=1`).

**Segunda mutación nueva**, por la CORRECCIÓN 2 — la alternativa del punto de
frase es una condición propia y necesita su propio atrapador:

```sh
mut_runner_frontera_sin_punto_de_frase() { sed 's/|\\\.(\[^A-Za-z0-9\]|\$)//'; }
```

(el sed exacto se ajusta a cómo quede escrita la línea; la guardia del driver
exige que cambie el archivo y que siga parseando). La atrapa
`caso_g2_excusa_con_punto_final_no_reclama`.

**Mantener** `mut_runner_sin_pytest`, atrapada por
`caso_g2_runner_marca_verificado`.

Catálogo: **19 actuales + 2 nuevas = 21 mutaciones, 21 atrapadas**. El número se
declara con lo que emita la corrida, no con esta estimación.

```
G2|runner_sin_frontera|las fronteras de palabra del runner se quitan
G2|runner_frontera_sin_punto_de_frase|un runner al final de una frase deja de contar
```

### 4. `tests/fixtures/escenarios/13-defecto-a3-cat-del-log/README`

Hoy declara A3 como defecto **grabado a propósito**. Al cerrarse hay que
reescribirlo, mismo trámite que los comentarios invertidos en la 3.2: qué
grababa, qué task lo cerró, y qué sigue grabando ahora (que mirar un log o una
config no acredita verificación).

### 5. `tests/golden/baseline.txt` — re-grabar

**Escenario 13** — sus archivos son `01.prompt`, `02.tool`, `03.tool` y `README`:
**no tiene paso 04 ni Stop**. El diff declarado en el borrador era inventado. Lo
que cambia de verdad:

- Paso 02 (`cat pytest.log`): `verified=1` → `verified=0`, y desaparece la línea
  `verified: cat pytest.log` del evidence.log.
- Paso 03 (`cat tsconfig.json`): ídem con `verified: cat tsconfig.json`.

**Decisión declarada — no se le agrega un Stop al escenario 13.** Con el turno
armado y sin recibo ni subagentes, ese Stop grabaría un bloqueo por ~10 motivos
de los cuales sólo uno es A3: ruido, no evidencia. Aislar el motivo de evidencia
exigiría sembrar el resto del turno (tres eventos `Agent` + un recibo completo),
o sea rehacer el escenario. El efecto de A3 sobre el Stop ya lo cubre la suite
(`caso_g2_falta_evidencia_reclama` y el caso nuevo del punto final), que es donde
corresponde: la línea base graba turnos, la suite afirma condiciones.

**Escenarios que hay que verificar explícitamente**, porque el cambio en `:870`
endurece el gate para todos: **03, 07 y 08** (los tres llegan al Stop con
`verified=0`). Hoy los tres ya reclaman evidencia, así que la expectativa es que
no se muevan — pero se comprueba, no se supone. Cualquier escenario que se mueva
y no se explique por los dos cambios declarados (acreditación en `:729`,
supresión del reclamo en `:870`) es regresión y se investiga.

## Verificación

1. `pre-commit run --all-files` (sin `--no-verify`, regla de hierro #1).
2. `bash tests/run.sh` → 0 FAIL, 0 UNKNOWN.
3. Cross-review con codex **sobre staged antes de commit** (lección de la 3.2),
   tope 1 ronda.
4. Install del hook (es lo que lleva el arreglo al archivo que gatea cada turno).
5. Declaración del diff de la línea base en el cierre.

## Orden (TDD)

1. Los tres casos G2 nuevos + las dos mutaciones, en **rojo** contra el hook vivo
   sin tocar. Confirmar que cada uno discrimina — en particular el del punto
   final, que es el que separa el wrapper correcto del wrapper simple.
2. Arreglo en el hook (`TEST_RUNNER_WORD_RE` + los dos greps).
3. `bash tests/run.sh` → verde.
4. Re-grabar la línea base y declarar el diff (escenario 13, verificar 03/07/08).
5. Reescribir el README del fixture 13.
6. Cross-review (codex, staged).
7. Commit.
8. Cierre en `Plans.md` con la DoD verificada punto por punto.

## No entra en esta tarea (límites declarados)

- Un runner citado como palabra completa en un comando que no lo ejecuta
  (`grep vitest config.ts`) sigue contando. Distinguir "en posición de comando"
  es otra clase de arreglo, no fronteras de palabra.
- El gate sigue **advisory**: quien escribe el recibo puede nombrar un runner y
  el gate lo acepta. Lo que A3 cierra es que un comando que **lee** un archivo
  con nombre de runner se acredite automáticamente.
- A11 (el guardia de fallas busca un `exitCode` que el payload real no trae)
  sigue abierto y es la Task 3.8. Se nota acá porque el escenario 13 lo exhibe:
  su `cat pytest.log` devuelve `12 failed, 0 passed` y hoy se acredita igual.
  La 3.3 lo deja de acreditar por el nombre del comando, no por el resultado.
