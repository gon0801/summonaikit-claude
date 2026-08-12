# Task 3.5 — A5: `command_text` crudo persiste en `harness-evidence.log` (plan para revisión)

`[Guardrail]` `[lane:fast]` `[tdd:required]`. Cierra el defecto **A5**: un
comando de verificación que además lleva credenciales en la línea
(`token=`, `password=`, `://user:pass@`) se persiste en claro en
`harness-evidence.log` hasta el cierre limpio — y si el turno no cierra bien,
indefinidamente.

---

## El defecto, con su huella exacta

`mark_evidence` (`hooks/summonaikit-harness.sh:704`) es la única función que
escribe al log de evidencia. Su línea de salida (`:720`):

```sh
printf '%s: %s\n' "$kind" "$detail" >> "$LOG_PATH" 2>/dev/null || true
```

El `$detail` que llega al `verified` es el `command_text` **crudo**, leído del
payload en `:792` (`command_text="$(json_string_field command)"`) y pasado sin
sanear en `:835`:

```sh
mark_evidence "verified" "${command_text:-verification command}"
```

**Reproducción**: un comando de runner con credenciales embebidas —realista en
CI, donde el runner recibe un `--db-url postgresql://admin:s3cret@host/db` o un
`--api-token=sk-xxx`— se acredita como verificación (correcto, el runner
corrió) **y** deja el secreto en claro en disco:

```
verified: pytest --db-url postgresql://admin:s3cret@host/db --api-token=sk-xxx
```

Esa línea vive en `harness-evidence.log` hasta el cierre limpio (que borra el
directorio de estado), y si el turno se abandona o agota presupuesto sin cerrar,
vive indefinidamente.

**Dos llamadas de `mark_evidence`, una sola fuga que importa**:

| línea | kind | `$detail` | ¿lleva credenciales? |
|-------|------|-----------|----------------------|
| `:811` | `implemented` | `${file_path:-file edit}` | raro (una ruta `smb://user:pass@…` es teórica pero posible) |
| `:835` | `verified` | `${command_text:-…}` | **sí** — es la línea de comando entera |

El arreglo cubre las dos desde un solo punto, pero el caso medido es `:835`.

**Por qué `[lane:fast]` y no `[lane:gate]`**: la redacción NO toca la decisión
del gate. `verified`/`implemented` se setean igual (`:717`-`:718` no cambian);
sólo cambia lo que se **escribe al log**. La línea base no debe mover ningún
exit code ni veredicto —sólo, potencialmente, líneas de `evidence.log`, y sólo
en escenarios con credenciales (ninguno hoy).

## El arreglo

Una función `redact_secrets` que sanea `$detail` **dentro de `mark_evidence`**,
antes del `printf` de `:720`. Es el punto de estrangulamiento: el único sitio
que escribe al log. Redactar acá cubre los dos callers (`:811` y `:835`) y
cualquiera que se agregue después.

```sh
# Redacta credenciales que viajan en la linea de comandos antes de
# persistirlas en harness-evidence.log. Cierra A5 (Task 3.5): sin esto, un
# comando con token=/password=/://user:pass@ queda en claro en disco hasta el
# cierre limpio, y si el turno no cierra bien, indefinidamente.
#
# Es BEST-EFFORT contra una lista de tres patrones declarada, NO un scanner de
# secretos: cubre las tres formas que nombra la DoD. Postura de fallo: si un
# patron no matchea, el texto pasa crudo -- el peor caso es que algo no se
# redacte, NUNCA que se altere la decision del gate (esto es lane:fast: no
# toca verified/implemented, solo lo que se escribe al log).
#
# Lo que preserva: el resto del comando intacto, incluido el nombre del runner
# -- es lo que da utilidad diagnostica al log (DoD, clausula 2).
redact_secrets() {
  printf '%s' "$1" | sed -E \
    -e 's/(token|password)=[^[:space:]]*/\1=[REDACTED]/gI' \
    -e 's#://[^[:space:]@]*@#://[REDACTED]@#g'
}
```

Y en `mark_evidence` (`:720`), el `$detail` pasa por la redacción antes de
escribirse:

```sh
printf '%s: %s\n' "$kind" "$(redact_secrets "$detail")" >> "$LOG_PATH" 2>/dev/null || true
```

**Los tres patrones, uno por uno**:

| patrón | qué atrapa | ejemplo | resultado |
|--------|-----------|---------|-----------|
| `(token\|password)=[^[:space:]]*` | una asignación o query-param con valor pegado | `--api-token=sk-xxx` | `--api-token=[REDACTED]` |
| `(token\|password)=[^[:space:]]*` (con `I`) | idem case-insensitive | `API_TOKEN=sk-xxx`, `dbPassword=hunter2` | `API_TOKEN=[REDACTED]` |
| `://[^[:space:]@]*@` | URL con credenciales embebidas | `postgresql://admin:s3cret@host/db` | `postgresql://[REDACTED]@host/db` |

**Detalles que no son cosméticos**:

1. `[^[:space:]]*` (token/password) consume el valor hasta el primer espacio.
   `token="secret"` → `token=[REDACTED]` (las comillas se consumen; en un log
   de una línea eso es correcto: no es ejecutable, es diagnóstico).
   `token=secret;other` → `token=[REDACTED]` (sobraredacta el `;other`; seguro,
   no filtra). **Postura declarada**: se prefiere sobreredactar a filtrar.

2. `[^[:space:]@]*@` (URL) se detiene en el **primer** `@`. Así
   `://admin:s3cret@host/path` → `://[REDACTED]@host/path`: el host se preserva
   (utilidad diagnóstica), sólo las credenciales se borran. Una URL **sin**
   credenciales (`https://host/path`) no tiene `@` entre `://` y el primer
   `/host`, así que no matchea —no hay falso positivo.

3. La flag `I` (case-insensitive de GNU sed) cubre `TOKEN=`, `Token=`,
   `apiToken=`, `dbPassword=`. El toolchain del hook ya es GNU sed (Git Bash /
   MSYS2 en Windows, `sed -E` ya se usa en `SESSION_KEY` `:150` y en
   `json_escape`). Si la flag `I` no funcionara en algún entorno, el fallback es
   la forma explícita por brackets `[Tt][Oo][Kk][Ee][Nn]` — se declara y se
   decide en TDD.

**Crítico — lo que NO se redacta**: `command_text` y `combined` (`:792`,
`:794`). El grep de señales de falla (`:834`) lee `$combined` y NO debe ver
credenciales enmascaradas —si se redactara `combined`, un `token=secret` dejaría
de ser visible para el guardia de fallas y el comportamiento del gate cambiaría
(sin querer se metería en `lane:gate`). La redacción vive **sólo** en
`mark_evidence`, que escribe al log. El gate decide con el texto crudo; el log
recibe el texto saneado.

## Cambios

### 1. `hooks/summonaikit-harness.sh`

**(a)** Función `redact_secrets` nueva, ubicada justo antes de `mark_evidence`
(hoy `:704`), con el comentario de cabecera de arriba.

**(b)** En `mark_evidence` (`:720`), envolver `$detail`:

```sh
# antes:
printf '%s: %s\n' "$kind" "$detail" >> "$LOG_PATH" 2>/dev/null || true
# despues:
printf '%s: %s\n' "$kind" "$(redact_secrets "$detail")" >> "$LOG_PATH" 2>/dev/null || true
```

No se toca `:717`-`:719` (la lógica de `implemented`/`verified`/`write_state`)
ni ninguna otra línea. El cambio es de **una línea** en el cuerpo existente más
la función nueva.

### 2. `tests/lib/gate_cases.sh` — G2 (regla de hierro #2)

**Nuevo** `caso_g2_credenciales_en_comando_se_redactan` — el caso que habría
atrapado A5. Un comando de runner que además lleva las tres formas de
credencial: se acredita `verified` (el runner corrió), pero el log no contiene
los secretos y sí contiene el runner + el marcador `[REDACTED]`:

```sh
# DEFECTO A5, el caso que lo habria atrapado. Un comando de test runner que
# ademas lleva credenciales en la linea (token=, password=, ://user:pass@) se
# persistia crudo en harness-evidence.log hasta el cierre limpio -- y si el
# turno no cierra, indefinidamente. El arreglo redacta las tres formas en
# mark_evidence (el unico punto que escribe al log), preservando el resto del
# comando, incluido el nombre del runner.
caso_g2_credenciales_en_comando_se_redactan() {
  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_bash 'pytest --db-url postgresql://admin:s3cret@host/db --api-token=sk-12345 --db-password=p4ss')"
  _igual "verified (el runner pytest sigue contando)" "$(lab_estado verified)" "1"
  _no_contiene "secreto URL user:pass@ no en log" "$(lab_log)" 'admin:s3cret'
  _no_contiene "secreto token= no en log" "$(lab_log)" 'sk-12345'
  _no_contiene "secreto password= no en log" "$(lab_log)" 'p4ss'
  _contiene "runner preservado en log (utilidad diagnostica)" "$(lab_log)" 'pytest'
  _contiene "marcador REDACTED presente en log" "$(lab_log)" '[REDACTED]'
}
```

Las seis aserciones cubren las dos cláusulas de la DoD: (1) los tres secretos
**no** aparecen y el marcador **sí**; (2) el runner **sí** aparece —el log sigue
siendo diagnóstico.

**Nuevo** `caso_g2_comando_sin_credenciales_no_se_altera` — la redacción es
transparente para comandos limpios. Sin él, un wrapper demasiado agresivo (que
redacte todo) pasaría la aserción del runner y rompería la utilidad del log en
silencio:

```sh
# La redaccion es transparente para comandos sin credenciales: el log los
# conserva tal cual. Sin este caso, un redact_secrets que vaciara todo pasaria
# la primera asercion (el runner sigue presente) y romperia el log en silencio.
caso_g2_comando_sin_credenciales_no_se_altera() {
  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_bash 'python -m pytest -q')"
  _contiene "comando sin credenciales, intacto en log" "$(lab_log)" 'python -m pytest -q'
  _no_contiene "sin marcador REDACTED cuando no hay credenciales" "$(lab_log)" '[REDACTED]'
}
```

**Mantener**: `caso_g2_runner_marca_verificado` (`pytest -q` → `verified=1`) y
`caso_g2_runner_con_ruta_marca` — son los que confirman que el cambio no rompe
la acreditación.

**Orden en `CASOS_G2`**: los dos nuevos van **al final**, después de
`caso_g2_excusa_con_punto_final_no_reclama`, para no robarle la declaración a
los casos que ya están (la batería corta en el primer rojo).

### 3. `tests/test_gate_mutations.sh`

**Nueva mutación** — revierte la redacción en el call site de `mark_evidence`,
de modo que `$detail` vuelve a escribirse crudo:

```sh
mut_redaccion_quitada() { sed 's/"$(redact_secrets "$detail")"/"$detail"/'; }
```

Así `mark_evidence` escribe `$detail` sin saneamiento y el caso
`caso_g2_credenciales_en_comando_se_redactan` se pone rojo (el secreto
`admin:s3cret` vuelve a aparecer en el log). La guardia del driver exige que el
archivo cambie y siga parseando (`bash -n`): el sed sólo sustituye un substring
de la línea `:720`, no rompe la sintaxis.

Si el sed no mutara (caso análogo al de la 3.3 con `TEST_RUNNER_WORD_RE`), el
fallback es neutralizar `redact_secrets` desde adentro —convertir su cuerpo en
`printf '%s' "$1"` (passthrough). Se decide en TDD con el caso en rojo.

Catálogo: **N actuales + 1 nueva** mutación. El número se declara con lo que
emita la corrida.

```
G2|redaccion_quitada|la redaccion de credenciales se desactiva y el secreto vuelve al log
```

### 4. `tests/golden/baseline.txt` — sin re-grabar

**Ningún escenario de la línea base lleva credenciales en el comando** (medido:
los evidence.log de la baseline registran `npm test`, `python -m pytest -q`,
`cat pytest.log`, `cat tsconfig.json` y rutas `C:\\dev\\demo\\…`). La redacción
es no-op para todos ellos, así que el contenido del log es byte-idéntico.

**Declaración**: la línea base **no cambia**. Se comprueba corriendo la
re-grabación y confirmando diff vacío, no se asume. Si algo se mueve y no se
explica por la redacción, es regresión y se investiga.

No se agrega un escenario nuevo para A5: la línea base graba **veredictos del
gate** (exit codes, state, gate messages), y A5 es `lane:fast` —no cambia
ningún veredicto. La redacción se prueba en la suite (`caso_g2_credenciales…`),
que es donde corresponde.

## Verificación

1. `pre-commit run --all-files` (sin `--no-verify`, regla de hierro #1).
2. `bash tests/run.sh` → 0 FAIL, 0 UNKNOWN.
3. Cross-review con codex **sobre staged antes de commit** (lección de la 3.2),
   tope 1 ronda.
4. Install del hook (es lo que lleva el arreglo al archivo que gatea cada turno):
   `tools/install-hook.sh`.
5. Declaración del diff de la línea base (esperado: vacío) en el cierre.

## Orden (TDD)

1. Los dos casos G2 nuevos + la mutación, en **rojo** contra el hook vivo sin
   tocar. Confirmar que cada uno discrimina:
   - `caso_g2_credenciales_en_comando_se_redactan` → los secretos **sí**
     aparecen en el log (rojo, porque el arreglo aún no existe).
   - `caso_g2_comando_sin_credenciales_no_se_altera` → debería pasar ya en
     verde aún sin el arreglo (el comando limpio se loguea crudo hoy, que es
     justo lo que este caso afirma). Es un **guardia de regresión** para que un
     arreglo futuro no sobreredacte.
2. Arreglo en el hook (`redact_secrets` + envolver `$detail` en `:720`).
3. `bash tests/run.sh` → verde.
4. Re-grabar la línea base y declarar el diff (esperado: vacío).
5. Cross-review (codex, staged).
6. Commit: `feat(3.5): A5 cerrado — redacción de credenciales en evidence.log`.
7. Cierre en `Plans.md` con la DoD verificada punto por punto:
   `chore(3.5): cerrar Task 3.5 — DoD verificada punto por punto`.

## No entra en esta tarea (límites declarados)

- **Es best-effort, no un scanner de secretos.** La lista cubre las tres formas
  que nombra la DoD (`token=`, `password=`, `://user:pass@`). Un secreto en otro
  formato (`Authorization: Bearer sk-…`, `AWS_SECRET_ACCESS_KEY=…` sin `token=`/
  `password=` en la línea, un `.env` cargado por el comando) **no se redacta**.
  Ampliar la lista es otra tarea; lo que se cierra acá es la fuga de las tres
  formas declaradas, que son las más comunes en una línea de comando de runner.
- **El gate sigue `advisory`.** Quien escribe el recibo puede nombrar un runner y
  el gate lo acepta. Lo que A5 cierra es que el comando **ya acreditado** deje
  su secreto en disco.
- **No se redacta el payload en memoria** (`command_text`, `combined`). El grep
  de señales de falla (`:834`) sigue viendo el texto crudo —es necesario para no
  enmascarar un `exitCode` o `command not found`. La redacción es sólo en la
  persistencia al log.
- **No se redactan secretos en el transcript.** Si el transcript del host guarda
  el comando crudo, sigue ahí —el hook no lo controla. A5 cierra sólo el archivo
  que el hook **escribe** (`harness-evidence.log`).
- **A6** (`transcript_path` arbitrario) sigue abierto y es la Task 3.6.

---

# Revisión (Claude, 2026-08-11)

> 13 correcciones. Las **5 bloqueantes** son la 1, 2, 3, 4 y 11: rompen una
> cláusula de la DoD, invalidan una declaración de cierre, o impiden que el orden
> TDD dé verde. Las otras 8 son de registro: el plan afirma cosas que no son
> ciertas, no mide lo que dice cubrir, o se contradice consigo mismo.
>
> **Procedencia**: 1-8 de Claude; **9-10 de la revisión cruzada con kimi**;
> **11-13 de la revisión cruzada con codex** (dos rondas,
> `cross-review.ps1 -Con kimi|codex -Excluir claude`, sobre este documento en
> stage; la segunda ronda la pidió Gon explícitamente por encima del tope de 1
> del quality-kit).
>
> Kimi verificó contra el repo todas las afirmaciones comprobables de las
> correcciones 1-8 y las reprodujo —números de línea, `sed -E` = 0, los 4 sitios
> de `$LOG_PATH`, el catálogo de 25, los 11 casos de `CASOS_G2`, el sha256
> idéntico entre vivo y fuente, 0 ocurrencias de `://` en la línea base—, sin
> hallazgos sobre las bloqueantes. Codex atacó los **regex** en vez del papeleo y
> encontró dos agujeros que ni kimi ni yo vimos, uno de ellos en el arreglo que
> yo mismo había propuesto como corrección.
>
> **La forma final de `redact_secrets` está en el PLAN CANÓNICO del cierre**, no
> en "El arreglo" ni en la CORRECCIÓN 2 — las dos quedaron superadas.
>
> Todo lo verificado se cita con su línea, y cada regex se **corrió** — GNU sed
> 4.9 sobre Git Bash, la misma que corre el banco. Lo que dice "medido" es salida
> real, no lectura.
>
> Lo que queda en pie del plan sin tocar: el punto de estrangulamiento elegido
> (`mark_evidence`), el argumento de **no** redactar `combined` (es lo que
> mantiene la tarea en `lane:fast` y está bien razonado), el análisis de la línea
> base por contenido en vez de por suposición, y la decisión de no agregarle un
> escenario nuevo.

## CORRECCIÓN 1 — la regla de URL borra el host, que es justo lo que la DoD pide preservar (BLOQUEANTE)

El detalle 2 ("el host se preserva, sólo las credenciales se borran") **no se
sostiene**: `[^[:space:]@]*` no excluye `/`, así que la clase cruza el path
entero y come hasta la **última** `@` que aparezca antes de un espacio. Medido:

```
IN   : pytest --report https://ci.example.com/runs/owner@corp.com/log
PLAN : pytest --report https://[REDACTED]@corp.com/log
```

No había ningún secreto ahí y se perdió el host, el path y el runner sigue
visible de casualidad. Eso incumple la cláusula 2 de la DoD (*"el log conserva
utilidad diagnóstica"*) en un comando **sin** credenciales, que es el caso
mayoritario.

Arreglo: excluir `/` de la clase, con lo que la regla queda acotada a la sección
de autoridad de la URL, que es donde viven las credenciales:

```sh
-e 's#://[^[:space:]@/]*@#://[REDACTED]@#g'
```

Medido con ese cambio: el caso de arriba pasa **intacto**, y
`postgresql://admin:s3cret@host/db` y `smb://admin:s3cret@share/src/x.ts` se
siguen redactando igual. Conviene que la sobre-redacción tenga su propio caso
(ver CORRECCIÓN 6).

## CORRECCIÓN 2 — `sed -E` no se usa hoy en el hook, y la flag `I` no se puede "decidir en TDD" (BLOQUEANTE)

El plan justifica la flag `I` así: *"el toolchain del hook ya es GNU sed …
`sed -E` ya se usa en `SESSION_KEY` `:150` y en `json_escape`"*. **Falso, medido**:
`grep -c 'sed -E' hooks/summonaikit-harness.sh` da **0**. `:150` es
`sed 's/[^A-Za-z0-9_-]/_/g'` (BRE) y `json_escape` (`:370`) es
`sed 's/\\/\\\\/g; s/"/\\"/g'` + awk. Lo que el hook sí usa en todos lados es
`grep -E`, que no dice nada de sed. `sed -E` con `/gI` sería la **primera**
dependencia de ese tipo en el archivo.

Y el fallback declarado —*"si la flag `I` no funcionara en algún entorno … se
decide en TDD"*— **no es decidible ahí**: el banco corre GNU sed 4.9, así que
ningún caso puede ponerse rojo por esto. Es un riesgo que el TDD no ve por
construcción.

Peor: **la postura de fallo declarada no cubre el modo de falla real.** El plan
dice *"si un patrón no matchea, el texto pasa crudo"*, pero un sed que **rechaza
la flag** no pasa el texto crudo — sale con error y no imprime nada. Medido:

```
$ sed -E 's/x/y/gQ' <<< hola
sed: -e expression #1, char 8: unknown option to `s'   (stdout vacío)
```

O sea, en esa máquina: la línea del log queda `verified: ` (detalle perdido, DoD
cláusula 2 rota en silencio) **y** el mensaje de sed sale por stderr del hook en
cada evento acreditado. El `2>/dev/null` del `printf` no lo tapa: POSIX expande
las sustituciones **antes** de aplicar las redirecciones del comando simple.
Medido:

```
$ bash -c 'printf "%s\n" "$(bash -c "echo BOOM >&2")" >/dev/null 2>/dev/null' 2>err
$ cat err
BOOM
```

Y la línea base graba `stderr` por paso, así que eso además sería un cambio de
comportamiento observable.

**Arreglo recomendado**: forma BRE portable, sin `-E` y sin `I`. Cero
dependencias nuevas de toolchain (sed pelado ya corre incondicionalmente en
`:150`: si faltara, el hook estaría roto mucho antes de `mark_evidence`), y
conserva la capitalización original de la clave vía `\1`:

```sh
redact_secrets() {
  printf '%s' "$1" | sed \
    -e 's/\([Tt][Oo][Kk][Ee][Nn]\)=[^[:space:]]*/\1=[REDACTED]/g' \
    -e 's/\([Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd]\)=[^[:space:]]*/\1=[REDACTED]/g' \
    -e 's#://[^[:space:]@/]*@#://[REDACTED]@#g'
}
```

Medido, salida idéntica a la versión del plan en las tres formas de la DoD y en
`API_TOKEN=sk-xxx dbPassword=hunter2`; y **mejor** en el caso de la CORRECCIÓN 1.
Bordes que el plan ya declaraba, verificados con esta forma:
`token="secret" other` → `token=[REDACTED] other`;
`dbPassword=hunter2;otro` → `dbPassword=[REDACTED]`.

Si en cambio se prefiere conservar `sed -E … /gI`, entonces hay que **declararlo
como dependencia** (GNU/BSD sed, no POSIX) y decidir la postura de fallo para
"sed falló", no sólo para "el patrón no matcheó" — y la postura correcta ahí no
es pasar el texto crudo, porque eso es exactamente A5.

## CORRECCIÓN 3 — la línea base no da diff vacío (BLOQUEANTE: es una declaración de cierre)

La sección 4 declara *"la línea base **no cambia** … diff vacío"* y agrega que
cualquier movimiento *"es regresión y se investiga"*. Con eso escrito así, la
re-grabación va a producir un diff y no va a haber forma de saber si es benigno.

`--record` regraba el encabezado con la identidad del hook **vivo**
(`tools/golden-harness.sh:194-196`: `hook_sha256`, `hook_bytes`, `hook_lineas`),
y el hook cambia sí o sí. El diff esperado es **exactamente esas tres líneas**, y
**cero** de `=== escenario` en adelante.

Además, re-grabar es opcional: `--check` empieza a comparar en la primera línea
`=== escenario` (`tools/golden-harness.sh:27`) y la diferencia de identidad sale
como `[nota]` informativa que **no** decide el veredicto
(`tools/golden-harness.sh:311-318`, y `tests/test_golden_baseline.sh:16-18` dice
lo mismo). La evidencia que vale es "0 escenarios divergen".

Reescribir la declaración así: *el contenido de comportamiento no cambia (0
escenarios divergen en `--check`); la re-grabación mueve únicamente las 3 líneas
de identidad del encabezado.* La conclusión sobre los evidence.log de la baseline
(`npm test`, `python -m pytest -q`, `cat pytest.log`, rutas `C:\dev\demo\…`) la
verifiqué y es correcta: **0 ocurrencias de `://`** en toda la línea base, y las
rutas con `\` pasan intactas por los tres regex (medido).

El manifiesto `hooks/vendor-manifest.sha256` **no** hay que tocarlo: describe
estados *vendor*, y este archivo lleva el marcador de propiedad de la línea 2.

## CORRECCIÓN 4 — `tests/run.sh` mide el hook VIVO, no la fuente del repo (BLOQUEANTE para el orden TDD)

El paso 2 del orden TDD arregla `hooks/summonaikit-harness.sh` (repo) y el paso 3
espera `bash tests/run.sh` → verde. No va a dar verde:
`resolver_hook_bajo_prueba` (`tests/lib/hook_bajo_prueba.sh:32-38`) prefiere
`$HOME/.claude/hooks/summonaikit-harness.sh` y sólo cae a la fuente del repo si
el vivo **no existe**. Hoy el vivo existe y es byte a byte la fuente (mismo
sha256 `2f34cba6…`, medido), así que tras el paso 2 la suite seguiría midiendo el
hook **sin** el arreglo y los casos nuevos quedarían rojos sin motivo real.

La costura ya existe para esto: `SAIKIT_HOOK_VIVO`. Los pasos 1 y 3 quedan:

```sh
# paso 1 — rojo contra el hook SIN tocar (vivo == fuente, da igual cuál)
bash tests/run.sh
# paso 3 — verde contra la FUENTE ya arreglada, sin instalar todavía
SAIKIT_HOOK_VIVO="$PWD/hooks/summonaikit-harness.sh" bash tests/run.sh
```

El install sigue yendo **después** del commit, como en la 3.4 (su orden TDD,
paso 7). Ojo con el guard de fugas: la suite tarda ~10 min y no hay que tocar el
repo mientras corre.

## CORRECCIÓN 5 — `mark_evidence` no es la única función que escribe al log

*"`mark_evidence` … es la única función que escribe al log de evidencia"* es
falso. Hay **cuatro** sitios que escriben a `$LOG_PATH`:

| línea | qué escribe | ¿texto del payload? |
|-------|-------------|---------------------|
| `:676` | `prompt task started: <task_hash>` (`>` trunca) | no — `cksum` del prompt |
| `:720` | `mark_evidence` | **sí** |
| `:780` | `agent: <rol>` | no — salida de `canonical_agent_role`, un set fijo de 5 |
| `:1020` | aviso de review-notice + timestamp | no — texto fijo |

La conclusión del plan no cambia, pero el argumento sí, y hay que escribirlo
bien porque es lo que alguien va a re-verificar cuando aparezca un quinto sitio:
**`mark_evidence` es el único que escribe texto derivado del payload; los otros
tres escriben valores acotados.** Redactar ahí cubre la superficie completa de
texto no controlado.

## CORRECCIÓN 6 — el segundo caller (`:811`) no tiene ningún caso

El plan argumenta que el arreglo *"cubre los dos callers (`:811` y `:835`)"* y
después no mide ninguno de los dos más que `:835`. Con eso, un arreglo futuro que
mueva la redacción del cuerpo de `mark_evidence` al call site de `:835` pasaría
la suite entera con `:811` filtrando — que es la regla de hierro #2 al revés.
Cuesta un caso:

```sh
# La redaccion vive en mark_evidence, no en el call site de la verificacion: el
# OTRO caller (`:811`, la evidencia de implementacion) tiene que quedar cubierto
# por el mismo punto. Sin este caso, mover la redaccion al call site de :835
# dejaria :811 filtrando y la suite no se enteraria.
caso_g2_credenciales_en_ruta_de_edicion_se_redactan() {
  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_edit 'smb://admin:s3cret@share/src/x.ts')"
  _igual "implemented (la edicion sigue contando)" "$(lab_estado implemented)" "1"
  _no_contiene "secreto de la ruta no en log" "$(lab_log)" 'admin:s3cret'
  _contiene "ruta preservada salvo credenciales" "$(lab_log)" '@share/src/x.ts'
}
```

Medido con la forma de la CORRECCIÓN 2: `smb://admin:s3cret@share/src/x.ts` →
`smb://[REDACTED]@share/src/x.ts`.

Y para cerrar la CORRECCIÓN 1 con su propio guardia, una aserción más en
`caso_g2_comando_sin_credenciales_no_se_altera` (o un caso aparte): un comando
limpio **con una `@` después del path** tiene que salir intacto —

```sh
  lab_run tool claude "$(lab_payload_bash 'pytest --report https://ci.example.com/runs/owner@corp.com/log')"
  _contiene "host y path intactos" "$(lab_log)" 'https://ci.example.com/runs/owner@corp.com/log'
```

Ese es el caso que la versión original del regex reprueba.

Con esto, `CASOS_G2` pasa de 11 a 14 casos. El orden que propone el plan (los
nuevos **al final**) es correcto y hay que mantenerlo: el driver de mutación
corta en el primer rojo (`tests/test_gate_mutations.sh:198-203`) y el crédito se
lo lleva ese caso.

## CORRECCIÓN 7 — la mutación funciona como está escrita, y además fija la ubicación

Verificado contra la línea real: `sed 's/"$(redact_secrets "$detail")"/"$detail"/'`
sustituye bien. En BRE `$`, `(` y `)` a mitad de patrón son literales, así que
**no** hay que escaparlos — y de hecho no conviene, por la lección ya escrita en
`tests/test_gate_mutations.sh:128-131` (MSYS2/Git Bash corrompe los backslashes
en literales de sed). El fallback de "neutralizar `redact_secrets` desde adentro"
no hace falta; se puede borrar del plan o dejarlo declarado como no usado.

Vale la pena declarar una propiedad que el plan no nombra y que sale gratis: esta
mutación también **fija la ubicación** del arreglo. Si alguien mueve la redacción
al call site, el `sed` deja de matchear y salta la guardia 2 del driver ("la
mutación no cambió nada del hook"), que es un FAIL explícito
(`tests/test_gate_mutations.sh:186-189`).

## CORRECCIÓN 8 — números y precisiones

1. **Catálogo**: no hace falta el "N actuales". Son **25** hoy (G1 5, G2 5, G3 5,
   G4 7, G5 2, G6 1) → **26**, y G2 pasa de 5 a 6. Ningún test hardcodea el
   número (lo verifiqué en `test_gate_mutations_guards.sh` y `run.sh`).
2. **`lane:fast`**: la etiqueta no es una decisión del plan, viene del renglón
   3.5 de `Plans.md:65`. La sección "Por qué `[lane:fast]` y no `[lane:gate]`"
   conviene reformularla como lo que realmente es —*qué implica* la etiqueta ya
   asignada, o sea el compromiso de no mover ningún veredicto—, que es como se
   va a verificar en el cierre.
3. **Ventana de exposición**: "vive hasta el cierre limpio" es incompleto. El log
   también se trunca al armar el turno siguiente de la **misma** sesión (`:676`
   escribe con `>`), y se borra en el desarme (`:659`) y al agotarse el
   presupuesto (`:1054`). Lo que sí vive indefinidamente es el log de una sesión
   **abandonada** — y eso es más fuerte de lo que el plan dice, porque desde el
   keying por sesión de la 3.4 esos directorios no se recolectan (declarado en la
   CORRECCIÓN 6 de la 3.4). Conviene escribirlo así: es lo que sostiene la
   severidad de A5.
4. El comentario de cabecera dice "una lista de **tres** patrones": son 2 reglas
   (o 3 con la forma BRE) que cubren las 3 formas de la DoD. Cosmético, pero el
   comentario es lo que va a quedar en el archivo.

## CORRECCIÓN 9 (kimi) — la enumeración de borrados omite el cierre limpio, y "borra el directorio" es falso

La CORRECCIÓN 8 punto 3 lista dónde desaparece el log (`:659` desarme, `:1054`
presupuesto) y **se saltea `:1045`** — que es justamente el cierre limpio del
Stop gate, o sea el camino principal y el único que el plan original nombraba.
Verificado: `:1045` está dentro del `if [ -z "$missing" ]` que abre en `:1028`,
después del canal inmediato del review-notice.

Y las dos versiones del texto —el plan (*"el cierre limpio, que borra el
directorio de estado"*) y mi CORRECCIÓN 8— dicen **directorio** cuando lo que
pasa es otra cosa: los tres sitios hacen `rm -f` sobre **archivos**
(`STATE_PATH`, `LOG_PATH`, y en dos de ellos `RN_ORDER_PATH`), sin `-r` y sin
tocar `STATE_DIR`. El directorio por sesión **queda**, que es exactamente la
basura sin recolección que declaró la CORRECCIÓN 6 de la 3.4.

La lista correcta, para que quede bien en el documento de cierre:

| línea | camino | qué borra |
|-------|--------|-----------|
| `:676` | armado del turno siguiente (misma sesión) | trunca `LOG_PATH` (`>`) |
| `:659` | desarme (prompt sin sentinel, A4-c2) | `STATE_PATH`, `LOG_PATH`, `RN_ORDER_PATH` |
| `:1045` | **cierre limpio del Stop gate** | `STATE_PATH`, `LOG_PATH` |
| `:1054` | presupuesto agotado (A4-c4) | `STATE_PATH`, `LOG_PATH`, `RN_ORDER_PATH` |

Ninguno borra `STATE_DIR`. La conclusión no se mueve —una sesión abandonada
conserva el secreto indefinidamente y eso es lo que sostiene la severidad de
A5—, pero el argumento hay que escribirlo con estos cuatro caminos y sin la
palabra "directorio".

## CORRECCIÓN 10 (kimi) — el documento se contradice sobre cuándo instalar el hook

La sección "Verificación" (texto original, pre-revisión) pone el install como
**paso 4**, antes del cross-review y del commit. La CORRECCIÓN 4 declara que el
install va **después** del commit, como en la 3.4. Las dos frases quedaron vivas
en el mismo documento y el ejecutor no tiene cómo saber cuál manda.

Manda la CORRECCIÓN 4, y la razón es la misma que la motivó: si se instala antes
del commit, el hook vivo queda con el arreglo y cualquier re-corrida de
`tests/run.sh` **sin** `SAIKIT_HOOK_VIVO` mide el archivo instalado en vez de la
fuente que se está por commitear — el mismo problema, con los papeles cambiados.

Kimi verificó además que la 3.4 tenía la misma tensión textual (su "Verificación"
lo lista como paso 4 y su orden TDD como paso 7), así que esto se arrastra del
molde. Arreglo: en "Verificación", el punto 4 deja de ser un paso y pasa a ser
una nota — *"el install del hook no es parte de la verificación: va después del
commit (orden TDD, paso 7)"*— y el orden TDD queda como la única fuente del
cuándo.

## CORRECCIÓN 11 (codex) — un valor entrecomillado con espacios filtra su cola (BLOQUEANTE)

`[^[:space:]]*` corta en el primer espacio, y el valor de un `password=` **no
termina necesariamente en un espacio**: la shell lo delimita con comillas.
Medido, contra la forma que yo mismo había propuesto en la CORRECCIÓN 2:

```
IN : pytest --db-password='hunter two' -q
OUT: pytest --db-password=[REDACTED] two' -q
```

El secreto queda partido y su segunda mitad persiste en el log. Es la misma
cláusula de la DoD que la tarea viene a cerrar (`password=` se registra
redactado), así que esto es bloqueante: con esa forma, A5 queda cerrado sólo
para valores sin espacios.

**Un matiz que codex no podía ver desde el diff, y que acota el alcance**: la
variante con comillas **dobles** no es alcanzable como fuga. `json_string_field`
(`:69`) captura con `\([^\"]*\)`, o sea que se detiene en la primera `"`; y una
comilla doble dentro del comando viaja como `\"` en el JSON. Medido:

```
comillas DOBLES  -> command_text = [pytest --db-password=\]        <- truncado antes del secreto
comillas SIMPLES -> command_text = [pytest --db-password='hunter two' -q]   <- intacto
```

O sea que la fuga real es la de comillas simples. El arreglo cubre las dos
igual, porque no cuesta nada y porque no conviene depender de una truncadura
accidental del extractor.

**Arreglo**: el valor deja de ser "hasta el espacio" y pasa a ser una
alternativa —entrecomillado simple, entrecomillado doble, o pelado hasta el
espacio—. Eso exige alternación, o sea `-E`. Y acá hay que **corregir la
CORRECCIÓN 2, que mezcló dos cosas**: lo que no es portable es la **flag `I`**
(extensión de GNU/BSD al comando `s`), no `-E`, que lo soportan GNU, BSD/macOS y
busybox y que POSIX incorporó en Issue 8. Volver a `-E` **sin** `I` no
reintroduce el riesgo que motivó esa corrección. La forma final está en el PLAN
CANÓNICO.

**Residual declarado** (no se persigue, se escribe): una comilla **sin cerrar**
(`--db-password='sin cerrar -q` → `--db-password=[REDACTED] cerrar -q`) y un
espacio escapado con backslash (`password=a\ b`) siguen filtrando la cola. Es la
frontera real de esta técnica: redactar con regex no es parsear la shell. Queda
en los límites declarados, junto con "no es un scanner de secretos".

## CORRECCIÓN 12 (codex) — la autoridad de la URL tampoco termina sólo en `/`

La CORRECCIÓN 1 acotó la clase con `/` y se quedó corta: la sección de autoridad
de una URI termina en `/`, **`?` o `#`** (RFC 3986). Medido, contra mi propio
arreglo:

```
IN : pytest --report https://host?owner=a@corp.com
OUT: pytest --report https://[REDACTED]@corp.com
```

Sin credenciales de por medio, y se pierde el host. Es exactamente el defecto que
la CORRECCIÓN 1 vino a arreglar, un carácter más allá. Arreglo:
`[^[:space:]@/?#]*`. Medido: ese caso pasa intacto y los tres de la DoD siguen
redactándose igual.

**Nota de forma**: con `?` y `#` dentro de la clase, el delimitador `#` del `s`
deja de ser buena idea (GNU sed lo resuelve, BSD no está declarado). El PLAN
CANÓNICO usa `,`, que no aparece ni en el patrón ni en el reemplazo.

## CORRECCIÓN 13 (codex) — no hay un plan canónico ejecutable

El documento conserva el texto original **junto con** las correcciones que lo
anulan, y ya van tres formas distintas de `redact_secrets` en la misma página.
Un ejecutor tiene que reconstruir a mano qué manda. Eso es una manera concreta de
que el arreglo entre mal.

No se borra el original —el rastro de qué se corrigió es lo que hace auditable la
revisión, que es el criterio de este repo—, pero se agrega abajo una sección
**PLAN CANÓNICO** que fija la forma final de cada punto en disputa. Ante
cualquier contradicción con el cuerpo del documento, manda el PLAN CANÓNICO.

---

# PLAN CANÓNICO (lo que se ejecuta)

Todo lo de arriba es el rastro de cómo se llegó acá. Esto es lo que se hace.

## 1. `hooks/summonaikit-harness.sh`

Función nueva `redact_secrets`, justo antes de `mark_evidence` (`:704`):

```sh
# Redacta credenciales que viajan en la linea de comandos antes de persistirlas
# en harness-evidence.log. Cierra A5 (Task 3.5): sin esto, un comando con
# token=/password=/://user:pass@ queda en claro en disco hasta que el turno
# cierre -- y una sesion abandonada lo conserva indefinidamente.
#
# BEST-EFFORT contra las tres formas que nombra la DoD, NO un scanner de
# secretos. Postura de fallo: si un patron no matchea, el texto pasa crudo -- el
# peor caso es que algo no se redacte, NUNCA que se altere la decision del gate
# (lane:fast: no toca verified/implemented, solo lo que se escribe al log).
#
# El valor puede venir entrecomillado: sin la alternativa de comillas, un
# `password='hunter two'` filtraba su segunda mitad (hallazgo de la revision
# cruzada con codex). La autoridad de una URI termina en / ? o # (RFC 3986):
# acotar la clase a eso es lo que preserva el host, que es la clausula 2 de la
# DoD. `-E` es POSIX Issue 8 y lo soportan GNU/BSD/busybox; la flag `I` NO se
# usa a proposito (es extension y su fallo es silencioso: sed sale con error y
# la linea del log queda sin detalle).
redact_secrets() {
  printf '%s' "$1" | sed -E \
    -e "s/([Tt][Oo][Kk][Ee][Nn]|[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd])=('[^']*'|\"[^\"]*\"|[^[:space:]]*)/\1=[REDACTED]/g" \
    -e 's,://[^[:space:]@/?#]*@,://[REDACTED]@,g'
}
```

Y en `mark_evidence` (`:720`), una línea:

```sh
printf '%s: %s\n' "$kind" "$(redact_secrets "$detail")" >> "$LOG_PATH" 2>/dev/null || true
```

Nada más se toca. Comportamiento medido de la forma final:

| entrada | salida |
|---------|--------|
| `pytest --db-url postgresql://admin:s3cret@host/db --api-token=sk-12345 --db-password=p4ss` | `pytest --db-url postgresql://[REDACTED]@host/db --api-token=[REDACTED] --db-password=[REDACTED]` |
| `pytest --db-password='hunter two' -q` | `pytest --db-password=[REDACTED] -q` |
| `API_TOKEN=sk-xxx dbPassword=hunter2` | `API_TOKEN=[REDACTED] dbPassword=[REDACTED]` |
| `smb://admin:s3cret@share/src/x.ts` | `smb://[REDACTED]@share/src/x.ts` |
| `python -m pytest -q` | *(sin cambios)* |
| `pytest --report https://ci.example.com/runs/owner@corp.com/log` | *(sin cambios)* |
| `pytest --report https://host?owner=a@corp.com` | *(sin cambios)* |

## 2. `tests/lib/gate_cases.sh` — 4 casos nuevos al final de `CASOS_G2` (11 → 15)

1. `caso_g2_credenciales_en_comando_se_redactan` — las tres formas de la DoD
   (cuerpo tal cual la sección 2 de arriba).
2. `caso_g2_comando_sin_credenciales_no_se_altera` — transparencia, **más** la
   aserción de la CORRECCIÓN 6: `https://ci.example.com/runs/owner@corp.com/log`
   intacto, y `https://host?owner=a@corp.com` intacto (CORRECCIÓN 12).
3. `caso_g2_credenciales_en_ruta_de_edicion_se_redactan` — el caller `:811`
   (cuerpo en la CORRECCIÓN 6).
4. `caso_g2_credencial_entrecomillada_se_redacta_entera` — el hallazgo de la
   CORRECCIÓN 11:

```sh
# La cola de un valor entrecomillado tambien es el secreto. Sin la alternativa
# de comillas en redact_secrets, `password='hunter dos-palabras'` deja
# `dos-palabras'` en el log (medido). Hallazgo de la revision cruzada con codex.
# La cola se elige DISTINTIVA a proposito: un needle corto como `two` es
# subcadena de palabras comunes (`network`) y daria rojo falso.
caso_g2_credencial_entrecomillada_se_redacta_entera() {
  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_bash "pytest --db-password='hunter dos-palabras' -q")"
  _igual "verified (el runner sigue contando)" "$(lab_estado verified)" "1"
  _no_contiene "la cola del secreto no queda en el log" "$(lab_log)" 'dos-palabras'
  _contiene "runner preservado" "$(lab_log)" 'pytest'
}
```

Los cuatro van **al final**, después de `caso_g2_excusa_con_punto_final_no_reclama`.

## 3. `tests/test_gate_mutations.sh` — 25 → 26 (G2: 5 → 6)

```sh
mut_redaccion_quitada() { sed 's/"$(redact_secrets "$detail")"/"$detail"/'; }
```

```
G2|redaccion_quitada|la redaccion de credenciales se desactiva y el secreto vuelve al log
```

Sin escapar el `$` (BRE: literal a mitad de patrón; y backslashes en literales de
sed son la trampa de MSYS2 documentada en `:128-131`). La mutación además fija la
**ubicación** del arreglo: movida al call site, el `sed` no matchea y salta la
guardia 2 del driver.

## 4. `tests/golden/baseline.txt`

El comportamiento **no cambia**: `--check` tiene que dar **0 escenarios
divergentes**. Esa es la evidencia. Re-grabar es opcional y mueve **sólo** las 3
líneas de identidad del encabezado (`hook_sha256`, `hook_bytes`, `hook_lineas`).
Cualquier movimiento de `=== escenario` en adelante es regresión. No se agrega
escenario nuevo.

## 5. Orden

1. Los 4 casos + la mutación, en **rojo** contra el hook sin tocar
   (`bash tests/run.sh`). El caso 2 (transparencia) debe salir **verde** ya:
   es guardia de regresión, no de defecto.
2. Arreglo en el hook.
3. `SAIKIT_HOOK_VIVO="$PWD/hooks/summonaikit-harness.sh" bash tests/run.sh` → verde.
4. `--check` de la línea base y declaración del diff.
5. `pre-commit run --all-files` (sin `--no-verify`).
6. Commit: `feat(3.5): A5 cerrado — redacción de credenciales en evidence.log`.
7. `tools/install-hook.sh` — **después** del commit, no antes.
8. Cierre en `Plans.md`, DoD punto por punto (`cc:TODO` → `cc:完了 [sha]`).

La revisión cruzada ya se hizo (kimi + codex, sobre este documento); no se repite
sobre el diff del código salvo que el arreglo se desvíe de este plan canónico.
