# Task 3.2 — A2 + A8, misma raíz (plan corregido)

Corrige el plan propuesto por GLM. La raíz y el arreglo son correctos y se
conservan; lo que cambia son cinco puntos que, tal como estaban, o dejaban el
agujero medio abierto o ponían la suite en rojo.

---

## El defecto, con su huella exacta (lo medido en 1.2/1.3)

`stop_gate()` (`hooks/summonaikit-harness.sh:669-675`) arma
`text = $INPUT + tail -n 160` del JSONL **crudo**, y sobre ese texto corren
**tres** chequeos, no dos. De ahí salen dos fallas opuestas:

- **A2 (exige de menos)**: `SUMMONAIKIT HARNESS PAUSED` dentro del `content` de
  un `tool_result` (escenario 14: el asistente leyó un archivo que la contenía)
  → el grep crudo la encuentra → `emit_allow` sin pedir nada.
- **A8 (exige de más)**: un recibo correcto en texto corrido llega al JSONL con
  saltos escapados (`...audit.\nUnderstand: ...`). El char antes de `Understand`
  es la `n` de `\n`, que es alfabético, y `has_receipt_label` exige
  `(^|[^[:alpha:]])` → falla las 6 etiquetas → bloquea hasta agotar presupuesto
  (escenario 05).

## El arreglo (uno solo, misma raíz)

Construir `text` en `stop_gate()` extrayendo **sólo texto de mensajes
assistant**, decodificado, de los dos canales que el spec mide:

1. `last_assistant_message` del payload Stop.
2. Los bloques `{"type":"text","text":...}` de `message.content` de cada entrada
   del transcript cuyo mensaje sea `role:"assistant"`.

Mismo idiom que `json_tool_input_string` de la 3.1: char-por-char, `ins`/`esc`/
`depth`, case pre-check barato, cero dependencias nuevas (`awk` es dura).
Diferencia clave con la 3.1, declarada: ésta **decodifica** `\n \" \\ \t`, porque
el caso de uso es texto multilínea y la 3.1 los dejaba crudos a propósito (un rol
escapado no mapea; una etiqueta detrás de `\n` sí debe contar). Decisión de
diseño confirmada: awk puro, sin fallback, una sola política — lo mismo que
resolvió la 3.1, y por la misma razón (un primario-con-fallback son dos políticas
que divergen en silencio).

---

## CORRECCIÓN 1 — la regla de extracción es más estrecha de lo que decía el plan

**No** es "los `text` cuyo ancestro es un `message` con `role:assistant`". Un
`tool_use` vive en `content[]` de un mensaje **assistant**: con esa regla, un
asistente que hace `Write` de un archivo con la línea de pausa, o un `Grep` de
ese patrón, vuelve a meter la cadena en "texto del asistente" y A2 queda medio
abierta — en este mismo repo, el turno que creó el fixture del escenario 14
habría disparado ese vector.

Regla correcta, y es la que hay que implementar:

> Se emite **únicamente** el valor de la clave `text` de un objeto de `content[]`
> cuyo `"type"` sea exactamente `"text"`, dentro de `message` con
> `role:"assistant"`. Todo lo demás del mensaje assistant queda fuera:
> `tool_use.input`, `thinking`, y cualquier otra clave.

Esto necesita **su propio caso de test** (ver caso nuevo D abajo): la pausa
escrita por el asistente dentro del `input` de un `tool_use` no cuenta.

## CORRECCIÓN 2 — el `tail` no se elimina

El plan reemplazaba el `tail -n 160` por un recorrido del transcript. No:

- **Corrección de gate**: el transcript es de **toda la sesión**, no del turno.
  Leerlo entero hace que un recibo escrito hace cinco turnos satisfaga el gate de
  hoy. El `tail` no cierra ese hueco (160 líneas pueden abarcar el turno
  anterior) pero tampoco lo agranda; leer el archivo entero **sí** lo agranda, y
  eso es una regresión que la 3.2 no está autorizada a introducir.
- **Costo**: `awk` char-por-char sobre un transcript de MB, en cada Stop, en
  Windows. Un `tool_result` con un archivo entero adentro son cientos de KB en
  una sola línea.

Se conserva el `tail -n 160` como recorte, **antes** del walker. Se permite
además un pre-filtro barato de líneas (`grep '"type":"assistant"'`) como
acelerador; declarado explícitamente como **acelerador, no autoridad**: la
decisión de qué texto cuenta la toma el walker, no el grep.

## CORRECCIÓN 3 — dos canales, dos funciones (y desaparece la postura de fallo ambigua)

El plan decía: "si el parser no puede recorrer, `text` cae a
`last_assistant_message` crudo → fail-open". Eso no es accionable (awk no "falla"
con JSON malo: devuelve vacío) y además **no es fail-open**: con `text` vacío el
gate reclama las 6 etiquetas y **bloquea**, que es lo contrario.

Diseño corregido, que elimina el fallback:

- `assistant_text_payload()` — extrae `last_assistant_message`, clave de **primer
  nivel** (`depth == 1`), con el idiom de la 3.1, **y decodifica**. No depende del
  walker de transcript.
- `assistant_text_transcript()` — el walker acotado descrito en la CORRECCIÓN 1,
  sobre el `tail`.
- `text` = canal 1 + `\n` + canal 2, y **también un salto entre bloques** del
  canal 2 (el escenario 05 tiene dos mensajes assistant; pegarlos sin salto
  rompería la frontera de la primera etiqueta).

Postura de fallo, ahora sí verificable: si el transcript no existe o no es
legible, el canal 2 queda vacío y se evalúa sólo el canal 1 — **exactamente lo
que hoy pasa con el `tail` vacío**, sin código nuevo ni rama especial. No hay
otro modo de fallo que declarar.

## CORRECCIÓN 4 — el tercer consumidor de `$text` (el que el plan no vio)

El plan afirmaba que sólo cambian los greps de `:680`, `:695` y
`has_receipt_label` (`:595`). Falta **`hooks/summonaikit-harness.sh:716`**:

```sh
if [ "$verified" != "1" ] && ! printf '%s' "$text" | grep -Eiq "$TEST_RUNNER_RE|not run|not executed|skipped|non eseguit|saltat"
```

Ese gate **también cambia de superficie**: hoy un `pytest` que aparece en el
*comando de un `tool_use` del transcript* acredita evidencia; con el arreglo sólo
cuenta si el asistente lo escribió en su texto. Es un endurecimiento coherente
con la intención del gate, pero hay que **declararlo y medirlo**, no descubrirlo.

En consecuencia, la frase "ningún otro escenario debe moverse; si se mueve otro
es regresión" **se reemplaza** por:

> Todo escenario que se mueva debe explicarse por uno de los tres cambios de
> superficie declarados (pausa, recibo/etiquetas, evidencia de verificación).
> Un movimiento que no se explique por ninguno es regresión y se investiga.

Escenarios a mirar sí o sí porque llegan al Stop con `verified=0`: **03, 07, 08**
(ya reclaman evidencia hoy) y **14** (pasará a reclamarla). Se comprueba, no se
supone.

## CORRECCIÓN 5 — `mut_etiqueta_sin_frontera` se queda sin atrapador

El plan decía "sigue válido, mantener". Es falso, y hace fallar
`test_gate_mutations.sh`.

Quien la atrapa **hoy** es justamente `caso_g4_recibo_corrido_bloquea_a8`: con la
frontera laxa `(^|.)`, el `\nUnderstand:` pasa, el recibo satisface las 6, el
turno cierra limpio y el caso —que espera exit 2 con las 6 `Missing`— se pone
rojo. Al **invertir** ese caso a "pasa", ya no se pone rojo con la mutación, y
ningún otro caso de `CASOS_G4` tiene una etiqueta precedida de un carácter
alfabético. Resultado: la batería corta con
`ningún caso detecto que [la etiqueta se acepta con cualquier caracter delante]`.

Arreglo: un caso propio con una etiqueta **pegada a una palabra**, que debe
seguir sin contar (caso C abajo). Afirma **sólo** sobre `Understand`, no sobre las
6, para no robarle la declaración a `mut_retro_no_se_exige`.

---

## Cambios, ya corregidos

### 1. `hooks/summonaikit-harness.sh`

- `assistant_text_payload()` y `assistant_text_transcript()` junto a
  `json_tool_input_string`, con el comentario de por qué esta decodifica y la 3.1
  no.
- `stop_gate()` (`:669-675`): `tail_text` sigue existiendo (`tail -n 160`), pero
  se pasa al walker en vez de concatenarse crudo:

```sh
text="$(assistant_text_payload)
$(printf '%s' "$tail_text" | assistant_text_transcript)"
```

- Los greps de `:680`, `:695`, `:716` y `has_receipt_label` (`:595`) **no
  cambian**: ahora operan sobre texto decodificado y acotado al asistente, que es
  justo lo que su regex `(^|[^[:alpha:]])` supone.
- Nota anotada, no arreglada: `has_receipt_label` hace `text="$3"` (`:594`) y
  pisa la global `text` de `stop_gate` — no hay `local` en sh. Hoy es inocuo
  porque recibe el mismo valor; queda un comentario para que nadie meta una
  llamada intermedia con otro argumento.

### 2. `tests/lib/gate_cases.sh` — casos G4 (regla de hierro #2)

**A. Invertir** `caso_g4_recibo_corrido_bloquea_a8` → `caso_g4_recibo_corrido_pasa_a8`:
exit 0, stdout vacío, estado borrado. El comentario explica que el caso grababa
el defecto y la 3.2 lo invierte.

**B. Nuevo** `caso_g4_pausa_en_resultado_bloquea` (mitad mala de A2): payload con
`last_assistant_message` inocente + transcript cuyo `tool_result` trae la pausa →
exit 2, `_contiene "Missing SUMMONAIKIT HARNESS RECEIPT"`, y **estado no borrado**
(el turno sigue abierto).

**C. Nuevo** `caso_g4_etiqueta_pegada_no_cuenta` (repone el atrapador de
`mut_etiqueta_sin_frontera`): texto llano que contenga `hubo un misunderstand:
aclarar con el usuario` → exit 2 y `_contiene "Missing Understand gate summary"`.
Con el hook sano la `s` alfabética delante impide el match; con la frontera rota
la etiqueta cuenta y el caso se pone rojo. **No** afirma sobre las otras 5.

**D. Nuevo** `caso_g4_pausa_en_tool_use_no_cuenta` (CORRECCIÓN 1): transcript con
un mensaje **assistant** cuyo `content[]` trae un `tool_use` con la cadena de
pausa dentro de `input` → exit 2. Es el caso que separa "lo escribió el
asistente" de "lo escribió el asistente **como respuesta**".

**E. Nuevo** `caso_g4_recibo_corrido_solo_en_transcript_pasa`: el cruce que
faltaba (canal 2 × A8). Con dos decodificadores hay que probar cada uno; el plan
original probaba corrido-en-payload y viñetas-en-transcript, dejando esta
combinación sin cubrir.

**Mantener intactos**: `caso_g4_pausa_permite`, `caso_g4_recibo_en_vinetas_pasa`,
`caso_g4_recibo_solo_en_transcript_pasa` (la mitad legítima; la DoD lo exige).

**Orden en `CASOS_G4`** (load-bearing: la batería corta en el primer rojo y la
declaración nombra ese caso):

```
caso_g4_pausa_permite
caso_g4_pausa_en_resultado_bloquea
caso_g4_pausa_en_tool_use_no_cuenta
caso_g4_etiqueta_pegada_no_cuenta
caso_g4_recibo_corrido_pasa_a8
caso_g4_falta_una_etiqueta_bloquea
caso_g4_sin_recibo_bloquea
caso_g4_recibo_en_vinetas_pasa
caso_g4_recibo_corrido_solo_en_transcript_pasa
caso_g4_recibo_solo_en_transcript_pasa
```

### 3. `tests/lib/hook_lab.sh` — constructores nuevos

- `lab_transcript_pausa_en_resultado()`: transcript de 3 líneas (assistant con
  `tool_use` Read → user con `tool_result` que contiene la pausa → assistant con
  texto llano). Calca el fixture del escenario 14.
- `lab_transcript_tool_use_con_texto()`: una entrada **assistant** cuyo
  `content[]` es un `tool_use` con la cadena dentro de `input` (caso D).
- `lab_payload_stop` con transcript ya está soportado por `lab_run` (4º arg).

### 4. `tests/test_gate_mutations.sh` — catálogo

- `mut_etiqueta_sin_frontera`: se mantiene, **ahora atrapada por el caso C**
  (antes por el caso A8, que se invierte).
- `mut_pausa_no_se_reconoce`: se mantiene, atrapada por `caso_g4_pausa_permite`.
- **Nuevas, una por condición cerrada** — con los canales separados hacen falta
  dos mutaciones de decodificación, no una:
  - `mut_canal_payload_sin_decodificar` → la atrapa `caso_g4_recibo_corrido_pasa_a8`.
  - `mut_canal_transcript_sin_decodificar` → la atrapa
    `caso_g4_recibo_corrido_solo_en_transcript_pasa`.
  - `mut_texto_incluye_tool_result` (el walker deja de exigir `role:"assistant"`)
    → la atrapa `caso_g4_pausa_en_resultado_bloquea`.
  - `mut_texto_incluye_tool_use` (el walker deja de exigir `"type":"text"`) → la
    atrapa `caso_g4_pausa_en_tool_use_no_cuenta`.
- Requisito de implementación derivado: cada una de esas cuatro condiciones tiene
  que ser **mutable por línea** con un `sed`, porque las guardias del driver
  exigen que la mutación cambie el archivo y que el resultado siga parseando.
- Reporte esperado: **19 mutaciones, 19 atrapadas** (15 actuales + 4 nuevas). El
  número se declara con lo que emita la corrida, no con esta estimación.

### 5. `tests/golden/baseline.txt` — re-grabar

`bash tools/golden-harness.sh --record`, y declarar el diff:

- **Escenario 05** (paso 07): exit 2 + 6 etiquetas missing + `cycle=1` → exit 0,
  stdout vacío, estado borrado. Es el arreglo de A8.
- **Escenario 14** (paso 02): exit 0 + "estado sin cambios" → exit 2 con los
  motivos del gate (falta el recibo, faltan las 6 etiquetas, falta evidencia,
  faltan los 3 subagentes) y `cycle=1`. Es el arreglo de A2.
- **Verificar explícitamente 03, 07, 08** por el cambio de superficie de `:716`
  (CORRECCIÓN 4). Si alguno se mueve, se explica por ese cambio y se declara; si
  se mueve algo que no se explica por los tres cambios declarados, es regresión.

---

## Verificación (antes de dar por cerrada)

1. `pre-commit run --all-files` — sin `--no-verify`, regla de hierro #1.
2. `bash tests/run.sh` → todos PASS, 0 FAIL, 0 UNKNOWN. En particular
   `test_gate_behavior.sh`, `test_gate_mutations.sh`,
   `test_gate_mutations_guards.sh`, `test_golden_baseline.sh`,
   `test_fixtures_json.sh`.
3. **Medición de costo, nueva y obligatoria** (CORRECCIÓN 2): tiempo del Stop
   gate con un transcript real grande (≥1 MB, con un `tool_result` de cientos de
   KB en una línea) antes y después. Si el walker agrega más de ~1 s por Stop en
   Windows, se ajusta el recorte y se declara el número.
4. Declaración del diff de la línea base escrita en el cierre de la tarea.

## No entra en esta tarea (límites declarados)

- **A6** (`transcript_path` fuera del dir de transcripts del host) es la Task 3.6,
  con su propia DoD fail-open. La 3.2 no acota la ruta; sólo cambia qué hace con
  lo que lee. Efecto colateral que sí conviene declarar: al exigir estructura de
  transcript, un archivo arbitrario deja de producir texto útil, lo que **reduce**
  el impacto de A6 sin cerrarlo.
- El gate sigue **advisory** (Non-Goals del spec): quien controla el `tool_input`
  del evento de delegación sigue pudiendo nombrar el rol. Lo que la 3.2 cierra es
  que la pausa y el recibo se evalúen sobre texto que el asistente no escribió
  **como respuesta**.
- Un recibo de un turno anterior dentro de las últimas 160 líneas sigue contando.
  Límite conocido, **no** ampliado por esta tarea (CORRECCIÓN 2).

## Orden de ejecución (corregido — el renglón es `[tdd:required]`)

1. **Tests primero**: casos G4 (A–E) + constructores del banco, en **rojo** contra
   el hook vivo sin tocar. Confirmar que cada uno discrimina.
2. Escribir `assistant_text_payload()` / `assistant_text_transcript()` y cambiar
   `stop_gate()`.
3. `bash tests/run.sh` iterando hasta verde.
4. Medir el costo con un transcript grande (verificación 3).
5. Re-grabar la línea base y declarar el diff, incluidos 03/07/08.
6. Reescribir el catálogo de mutaciones y verificar N-de-N.
7. `pre-commit run --all-files`.
8. Revisión cruzada (**tope 1 ronda**, `C:\Users\ehven\quality-kit\cross-review.ps1`)
   + declaración de residuales.
9. Cierre de Task 3.2 en `Plans.md` con la DoD verificada punto por punto.
