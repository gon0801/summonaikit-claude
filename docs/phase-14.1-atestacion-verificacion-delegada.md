# Phase 14.1 — Diseño: atestación de verificación delegada en hosts con canal interno ciego

Fecha: 2026-08-25
Estado: diseño para revisión del lead (PR 1). 14.2–14.4 se implementan después.
Hosts afectados: zcode (canal interno ciego MEDIDO — el turno vivo lo confirmó);
kimi es **candidato** con canal interno `unknown` DECLARADO (no medido), ver §5 y
§7. claude/codex/grok observan el canal interno y NO tocan este diseño.

Este documento es intencionalmente **portable**: el port de kimi
(`summonaikit-kimi`) debe poder citarlo sin depender de rutas de este repo. Por
eso el mecanismo se define como contrato (forma exacta + límites), no como un
parche anclado a un archivo concreto.

---

## 1. El problema (rojo documental)

En la ceremonia de este kit, la verificación se acredita de dos maneras:

1. **`verified=1` en el estado** — lo gana un EVENTO de herramienta real que el
   hook ve desde el canal de herramientas (un test runner que corre).
2. **Prosa del recibo** que matchea un runner (`TEST_RUNNER_WORD_RE`) o una
   frase de skip explícito (`VERIFY_SKIP_RE`).

En un host cuyo **canal interno es `unknown`** (zcode, medido; kimi, candidato
declarado) el problema es estructural: los comandos que corre un verifier
**DELEGADO** viajan por ese canal interno, que el hook **no ve**. Entonces:

- el evento real del verifier **no llega** ⇒ `verified` queda en `0`;
- la prosa honesta del lead ("el verifier corrió la batería…
  `python -m py_compile app.py` exit 0") **no matchea runner** (`py_compile`
  no está en la lista) **ni skip** (no es un salto: se corrió) ⇒ tampoco
  acredita;
- el gate bloquea con **`Missing verification evidence`**.

La única salida que encontró el lead fue **re-correr él mismo los comandos**
(entonces sus eventos SÍ llegan al hook y `verified` se enciende). O sea: en los
hosts donde el candado ya es ciego, la ceremonia paga el trabajo **dos veces**.

Evidencia literal (doc del smoke, § zcode — `docs/smoke-adversary-hosts-2026-08-25.md`):

- **Intento 2** (con etiquetas y `ADVERSARY:` en forma válida, sin marcador):
  rechazo `Missing SUMMONAIKIT HARNESS RECEIPT`. (Ya cubierto por otro arreglo.)
- **Intento 3** (marcador + etiquetas): rechazo `Missing verification evidence`.
  El Verify decía la verdad ("El verifier corrió la batería aplicable…
  `python -m py_compile app.py` exit 0"), pero los comandos del verifier
  DELEGADO son invisibles para el hook en zcode (canal interno `unknown`),
  así que `verified` siguió en `0` y la prosa no traía skip-phrase.
- **Intento 4 (aceptado)**: `**Verify:** Corrí yo mismo, contra el archivo
  final, los checks…` — el LEAD re-corrió los comandos, sus eventos SÍ llegaron
  al hook y `verified` se encendió.

**Lo que se preserva a todo costo (regla dura):** ninguna opción puede permitir
acreditar verificación **sin rastro auditable por un humano**. El gate existe
para eso; si una opción hace más fácil mentir, es la equivocada.

---

## 2. Las tres opciones, evaluadas contra el riesgo de aflojar el gate

### (a) Label declarativo nuevo, estilo ROLE FALLBACK

Una línea en el recibo, tipo
`VERIFIED BY SUBAGENT: <comandos y resultado>`.

- **A favor:** es la MISMA disciplina que ya usa `ROLE FALLBACK: <ROL>` (que
  sustituye un despacho cuando el subagente murió) y la línea `ADVERSARY:`
  (label-only). El precedente es real, medido y aceptado con límite declarado.
- **Contra:** es una declaración en el texto del asistente; un lead deshonesto
  podría escribirla sin haber delegado nada. Hay que acotarlo (sección 4).
- **Cómo queda auditable:** el label **nombra los comandos y su resultado**.
  Eso es una afirmación mucho más fuerte y verificable que "el verifier lo
  corrió": un humano puede re-correr el comando nombrado y comprobar el "exit 0".
  El gate no verifica la verdad (es advisory, Non-Goal del spec), pero la
  declaración deja un rastro que la revisión humana puede auditar — que es
  exactamente lo que el lead honesto ya escribía.

### (b) Ampliar `VERIFY_SKIP_RE` a las formas naturales que el modelo escribe

Aceptar prosa tipo "el proyecto no tiene tests", "no hay suite".

- **NO resuelve el caso:** en zcode la verificación NO se saltó — se corrieron
  comandos reales pero invisibles. Un lead con evidencia invisible no escribe
  "no hay suite"; escribe que corrió algo con su resultado. Aceptar "no hay
  suite" cubre un skip legítimo, no el caso que este diseño ataca.
- **Es el camino peligroso:** la constante ya lo dice explícitamente —
  *"NO incluir 'se corrio' suelto: el recibo que afirma que SI corrio la
  bateria debe seguir pidiendo evidencia."* Un skip es **"no verifiqué"**;
  evidencia es **"verifiqué"**. Son opuestos. Ampliar la lista hacia la prosa
  de "corrí la batería" mezcla los dos y convierte cualquier frase en un pase
  libre **sin rastro nombrado**: un lead podría escribir "se corrió pytest,
  todo verde" (mentira) y el gate lo aceptaría sin que nadie pueda re-correr
  nada. Eso es exactamente "hacer más fácil mentir". **Descartada.**
- **La premisa de "ya está cubierto" es FALSA y se corrige:** corrido contra la
  constante real (`VERIFY_SKIP_RE`), las frases "no hay suite" y "no tiene
  tests" NO matchean — la constante solo matchea el literal `sin tests` (y las
  formas `no corri…` / `not run…` / `skipped`). El descarte de (b) se sostiene
  por su razón principal (mezcla skip↔evidencia y no atiende el caso), no por la
  cobertura; ampliar la cobertura de esos skips legítimos queda como mejora menor
  que NO es el objeto de esta fase, no como argumento de descarte.

### (c) Declararlo límite y que el lead re-corra

Documentar la fricción como límite conocido; el remedio queda en que el lead
re-corra los comandos.

- **A favor:** honesto y seguro — no afloja el gate en absoluto.
- **Contra:** deja la fricción intacta: la ceremonia sigue pagando el trabajo
  dos veces, justo en los hosts más ciegos. Es la opción "no hacer nada", y la
  Phase 14 existe para resolverla. Queda como fallback declarado si (a) no
  pudiera hacerse auditable de forma segura, pero no es la elección.

---

## 3. Decisión: (a), con el label como vía adicional de crédito

Se adopta **la opción (a)**, y con ella **no se afloja nada de lo que ya
endurece el gate**: el label es una vía ADICIONAL de crédito de verificación,
no un reemplazo de ninguna otra condición. El chequeo de secuencia de roles, la
línea `ADVERSARY:` (cuando corrió), el `verify` de la batería bash propia
(`TEST_RUNNER_CMD_RE`), el skip explícito y el `verified=1` real siguen
exactamente como hoy.

### Forma exacta del contrato (portable, sin rutas de este repo)

El recibo lleva una declaración con este prefijo literal y su contenido:

```
VERIFIED BY SUBAGENT: <comandos y resultado>
```

Reglas del label:

1. **Prefijo exacto** `VERIFIED BY SUBAGENT:` (en el recibo del asistente; el
   label es una frase que puede vivir en cualquier parte del recibo, como
   `ROLE FALLBACK`, no una etiqueta obligatoria).
2. **Contenido obligatorio con rastro**: la declaración debe nombrar **al menos
   un comando de verificación concreto Y su resultado observable** (p. ej.
   `python -m py_compile app.py exit 0`, `pytest -q … 12 passed`). Un label
   vacío, o que solo diga "el verifier corrió la batería" sin nombrar comando
   ni resultado, **no cuenta** — es justo el "sin rastro" que se prohíbe.
3. **Host con canal interno ciego (señal `$HOST`, JAMÁS `$TARGET`)**: solo cuenta
   en hosts donde el hook NO observa el canal interno. Se evalúa sobre `$HOST` —
   `$TARGET` NO sirve: en zcode el fallback 5.4 deja `TARGET=claude` y, si se
   evaluara sobre `$TARGET`, el label se prendería también en Claude. En este
   repo el único host con canal interno ciego MEDIDO es `$HOST=zcode` (el turno
   vivo lo confirmó: los eventos del verifier delegado no llegaron). `kimi` es
   **candidato** con canal interno `unknown` declarado (los tool-events internos
   quedaron `not_observed` en la captura del port) — el label ahí se prende SOLO
   si el port mide primero que el canal no entrega esos eventos (ver §7). En
   claude/codex/grok la evidencia real ES observable, así que el label no aplica
   y el sistema espera el camino normal (evento real o runner en la prosa).
4. **Verifier realmente despachado**: la sesión debe registrar el rol verifier
   (que el turno delegó un subagente de verificación). Sin un verifier
   despachado, el label no sustituye nada.
5. **Solo cuando `verified != 1`**: si la evidencia real ya se observó, el
   label es redundante y no cambia el veredicto.

En el gate, la condición de la evidencia queda:

```
si verified != 1  Y NO (prosa matchea runner|skip) Y NO (runner en posición de comando)
   Y NO (HOST ciego Y verifier en agents_seen Y label VERIFIED BY SUBAGENT con comando+resultado):
      -> agregar "Missing verification evidence"
```

("con comando+resultado" = el predicado concreto de la §4.3: label presente +
comando reconocido + resultado de ÉXITO + sin señal de FALLO. Un label que
declara un fallo NO sustituye nada — ver §4.3.)

### Los dos casos que fijarán la decisión (se implementan en 14.2)

- **Caso que ACREDITA:** host `zcode`, `verified=0`, `agents_seen` con
  `implementer,verifier,reviewer`, y un recibo cuya línea Verify es, p. ej.
  `VERIFIED BY SUBAGENT: python -m py_compile app.py exit 0`. El gate debe
  **cerrar limpio** (sin `Missing verification evidence`).
- **Caso que SIGUE BLOQUEANDO:** el lead que **afirma verificación sin rastro**,
  p. ej. una prosa `Verify: el verifier corrió la batería completa, 12 en
  verde` (verbo + resultado, pero **sin el label**), `verified=0`. El gate debe
  **seguir bloqueando** con `Missing verification evidence`. También bloquea:
  el label **sin** comando+resultado, o el label en un host donde el canal NO
  es ciego, o el label **sin** verifier despachado.

### Caso golden que fija la decisión

**El turno vivo de zcode del 2026-08-25, intento 3, pero con la declaración.**
Si el lead, en vez de re-correr él mismo los checks (intento 4), hubiera
reportado la verdad con el label — `VERIFIED BY SUBAGENT: python -m py_compile
app.py exit 0`, con `verifier` ya en `agents_seen` — el gate lo habría aceptado.
Sin esa declaración, el intento 3 sigue bloqueando exactamente igual. Ese es el
caso golden: **convierte el "pago doble" en una sola declaración auditable, sin
crear un pase libre para una afirmación sin rastro.**

---

## 4. El riesgo del label y cómo se acota (lo que la regla dura pide evaluar)

Riesgo: **un lead escribe `VERIFIED BY SUBAGENT: <comando+resultado>` sin haber
delegado nada** (o sin que la verificación realmente haya pasado).

Cómo se acota, sin aflojar en dónde sí se ve:

1. **Host ciego (condición 3):** el label solo cuenta donde el hook NO puede ver
   la verdad. En ese host, la declaración no reemplaza NADA que sí se observe;
   reemplaza exactamente lo que el hook por diseño no ve. En los hosts donde la
   evidencia es observable, la declaración no tiene efecto — ahí se exige el
   camino normal, que ya endura.
2. **Verifier despachado (condición 4):** el label exige que la sesión haya
   registrado un subagente de verificación. Un turno que no delegó verificación
   (por ejemplo un carril `fast` puro) no puede usarlo: no hay verifier en
   `agents_seen`, así que el label no aplica.
3. **Comando + resultado — el predicado concreto que el hook evalúa.** Es el único
   freno del mecanismo: sin forma detectable, el caso que debe BLOQUEAR no se
   puede escribir y la implementación mínima colapsa en un pase libre. Se define
   así — **sobre el SPAN del label**, es decir el fragmento desde
   `VERIFIED BY SUBAGENT:` hasta el fin de ESA línea (NO sobre el recibo
   entero). Esto cierra dos defectos que el predicado sobre `$text` completo
   tenía: (a) **crédito por piezas dispersas** — un label vacío + un `pytest`
   mencionado en otra línea + un `ok` suelto en otra NO satisfacen el
   predicado; (b) **falso positivo del veto** — un `TypeError:` mencionado en
   la línea `Understand` NO veta la atestación legítima del label:

   **Qué cuenta como COMANDO (predicado `SAIKIT_VERIFIED_CMD_RE`).** La
   declaración debe nombrar al menos un comando de verificación reconocido. El
   vocabulario es la UNIÓN del vocabulario de runners (`TEST_RUNNER_RE`: pytest,
   unittest, tox, npm/pnpm/yarn/bun test, dotnet test, go test, cargo test, make
   test/check, tsc, …) más un conjunto corto y explícito de comandos de
   compilación/type-check/sintaxis que hoy NO están en la lista de runners pero
   son verificaciones legítimas y re-corribles: `python -m py_compile`,
   `compileall`, `dotnet build`, `bash -n`, `sh -n`, `node --check`,
   `git diff --check`. Un nombre genérico ("batería", "checks", "lo de siempre")
   NO cuenta — no es re-corrible.

   **Qué cuenta como RESULTADO (predicado `SAIKIT_VERIFIED_RESULT_RE`).** La
   declaración debe nombrar un resultado de ÉXITO: `exit 0`, `N passed`,
   `N passing`, `ok`/`okay`, `N ok`, `en verde`, `todo verde`, `sin errores`,
   `0 failed` (o formas equivalentes de "cero fallos").

   **Señal de FALLO (VETO) — REUSA las constantes del hook, NO inventa lista.**
   Cualquier indicador de fallo DESCALIFICA el label aunque también aparezca un
   "passed". El veto se evalúa con las constantes que el hook YA define para el
   raíl del EVENTO: `FAILURE_SIGNAL_RE_CI` (hook:247) y `FAILURE_SIGNAL_RE_CS`
   (hook:261), con DOS greps en la MISMA forma que usa el hook en :1930-1935 —
   variables EXPANDIDAS y la CS case-SENSITIVE — **MÁS una forma propia del
   label**: `exit[[:space:]]+[1-9]`:
   `{ grep -Eiq "$FAILURE_SIGNAL_RE_CI" || grep -Eq "$FAILURE_SIGNAL_RE_CS" || grep -Eiq 'exit[[:space:]]+[1-9]'; }`
   (sobre el SPAN). **Responsabilidad del lead (declarado):** el diseño ORIGINAL
   tenía `exit [1-9]` en el veto; al reusar `FAILURE_SIGNAL_RE_CI/CS` (que NO
   cubre `exit 1`, forma que el raíl de evento recibe por otro canal) se perdió
   esa cobertura, y la corrección NO es volver atrás sino SUMAR el `exit [1-9]`
   como extra propio del label. NOTA de notación (las dos cosas importan,
   verificado por el
   lead): NO escribir `grep -Eiq 'FAILURE_SIGNAL_RE_CI|FAILURE_SIGNAL_RE_CS'` —
   las comillas simples harían a grep buscar el TEXTO literal
   "FAILURE_SIGNAL_RE_CI", no la regex, y el veto nunca dispararía (peor que no
   tener veto: parece que funciona); y fusionarlas bajo un solo `-Ei` rompería la
   paridad con el raíl, porque el hook corre la CS case-SENSITIVE a propósito
   (con `-Eq`). NO se define una lista propia: una lista propia se quedó corta —
   cubría `[1-9] failed` (número antes) y `FAILED` mayúscula, pero NO
   `failed: 1` (número después, minúscula), con lo que
   `VERIFIED BY SUBAGENT: pytest -q, 12 passed, failed: 1` habría acreditado un
   fallo. La constante del hook SÍ lo atrapa (su alternancia
   `(failures?|errors?|failed)[=:][[:space:]]*[1-9]`): verificado MATCH, y
   hereda también `FAILED`, `FAILURES!`, `FAILURE: Build failed`, `BUILD FAILED`,
   `test result: FAILED`, `FAIL[^a-zA-Z]` (go), `Traceback (...)`,
   `AssertionError:` y `error TS[0-9]`.

   **Beneficio estructural (declarado):** reusar esas constantes garantiza por
   CONSTRUCCIÓN que el label jamás sea MÁS LAXO que el raíl del evento — que es
   exactamente lo que este diseño promete en la §4.3 y en la §3 — y hereda
   cualquier mejora futura de esas regex sin drift (una sola fuente, como ya hace
   `TEST_RUNNER_RE`).

   **Predicado final (todo a la vez, sobre el SPAN del label):** `span presente`
   Y `SAIKIT_VERIFIED_CMD_RE` matchea Y `SAIKIT_VERIFIED_RESULT_RE` matchea Y
   `{ grep -Eiq "$FAILURE_SIGNAL_RE_CI" || grep -Eq "$FAILURE_SIGNAL_RE_CS" || grep -Eiq 'exit[[:space:]]+[1-9]'; }`
   NO matchea. Cualquiera
   de las cuatro que falle ⇒ acreditación NO se da y el gate sigue pidiendo
   evidencia. (Sin el veto, "12 passed, 3 failed" y "12 passed, failed: 1"
   acreditarían: el raíl del evento NO los deja — veto en hook:1930-1935 — y el
   label quedaría por debajo de ese raíl, que es lo contrario de lo que este
   diseño promete.)

   **Implementación (PR #72, Greptile P1 / CodeRabbit):** con VARIOS labels en
   el recibo el predicado corre en dos pasos sobre TODOS los spans — (1) veto:
   cualquier span con señal de fallo (`FAILURE_SIGNAL_RE_CI`/`_CS`, `exit [1-9]`,
   o conteo cero `SAIKIT_VERIFIED_CERO_RE`: "0 passed"/"0 passing") descalifica
   el turno entero; (2) crédito: algún span trae `SAIKIT_VERIFIED_CMD_RE` Y
   `SAIKIT_VERIFIED_RESULT_RE` en la MISMA línea. "Cualquier fallo declarado
   veta", no "el último manda". El contrato vivo es el spec § vía adicional.

   **Por qué así (auditabilidad):** una mentira sobre "corrí `python -m
   py_compile app.py`, exit 0" es detectable en la revisión — un humano puede
   re-correr el comando nombrado. Una mentira sobre "el verifier corrió la
   batería, 12 en verde" **no** es verificable — no hay comando que re-correr. El
   label obliga, para mentir, a fabricar un comando y un resultado específicos y
   reproducibles, que es mucho más frágil que una vaguedad. La parte de
   "vocabulario" (comando reconocido) es deliberada: el label acredita SOLO
   verificaciones que se pueden re-correr con un comando conocido; un comando
   legítimo fuera del vocabulario cae al camino normal (evento real o runner en
   la prosa), que es recuperable, mientras que un pase libre no lo es.

   **Postura sobre resultados FALLIDOS: semántica de falla aplicada (decisión
   tomada).** El label queda a la par del raíl del EVENTO (que veta fallos) y más
   estricto que la PROSA (hook:2399, que hoy acredita un fallo si hay runner en
   la prosa). `VERIFIED BY SUBAGENT: pytest, 12 failed` NO cierra el turno: el
   veto (las mismas `FAILURE_SIGNAL_RE_CI`/`FAILURE_SIGNAL_RE_CS` del raíl +
   `exit [1-9]`; no existe una `SAIKIT_VERIFIED_FAIL_RE` propia) lo descalifica. Consecuencia declarada: el
   label NO introduce una vía nueva para acreditar un fallo (esa brecha seguiría
   siendo la del fallback de prosa, ajena a este cambio).
4. **El gate es advisory, no un control de seguridad (Non-Goal del spec):** un
   lead que controla el texto del turno YA puede influir el gate hoy, con o sin
   este label. El label no crea una capacidad nueva; lo que hace es **nombrar
   explícitamente** un evento no observable para que un humano lo audite. Su
   límite es el **mismo trade-off ya aceptado** de `ROLE FALLBACK` y de la
   escotilla `DELEGATED`: un match por subcadena sin anclar sobre texto del
   asistente, aceptado a propósito porque el gate es advisory/fail-open por
   diseño (documentado en el README y en el spec).
5. **Label-only para el gate + texto completo en el recibo — función de matcheo
   NOMBRADA.** El label `VERIFIED BY SUBAGENT:` se matchea como **subcadena libre
   sobre `$text`** (igual que `ROLE FALLBACK: *<ROL>`, que usa
   `grep -Eiq 'ROLE FALLBACK: *VERIFIER'` sobre `$text`), NO con
   `has_receipt_label` (que es la función de la línea `ADVERSARY:`/`ADVERSARIO`:
   etiqueta + `:` dentro del recibo, con frontera de palabra y bold opcional). El
   label puede vivir en cualquier parte del recibo, sin exigir que esté al inicio
   de una etiqueta con `:`. Para 14.2: no deducir el matcheo de `ADVERSARY` — es
   una subcadena, una sola. El resto del mecanismo es igual que antes: presencia +
   forma (el predicado de la §4.3) para el gate; el contenido (comandos y
   resultados) viaja en el recibo para la revisión humana.

---

## 5. Límites declarados (los que este diseño no pretende cerrar)

- **El label es texto del asistente, match por subcadena.** Un mensaje que cite
  la frase "VERIFIED BY SUBAGENT:" sin un recibo real, o un lead que la use en
  un contexto distinto, podría disparar la vía de crédito. Es el mismo trade-off
  ya declarado para `ROLE FALLBACK` y `DELEGATED` (advisory).
- **El hook NO valida que el comando haya corrido de verdad**: en el host ciego
  no puede (por definición). Confía en la declaración, como confía en
  `ROLE FALLBACK`. La verificación humana es la que cierra ese hueco.
- **Vocabulario distinto de canal ciego:** en un host con canal observable, un
  comando no reconocido como runner (`python -m py_compile`) sigue sin acreditar
  por la vía normal. Ese es un problema de **vocabulario**, no de canal ciego, y
  queda fuera del alcance de esta fase (no se toca la lista de runners).
- **El label NO es un "todo verde" general:** no reemplaza el `ROLE FALLBACK`, la
  línea `ADVERSARY`, el chequeo de orden ni ninguna otra condición del gate.
  Solo añade una vía de crédito de verificación, y solo en hosts ciegos.
- **kimi NO es un host ciego medido — es candidato con canal interno `unknown`
  DECLARADO (no medido).** La captura cruzada del port (kimi-code 0.34.0) mostró
  el DESPACHO con `tool_input.subagent_type`, pero los tool-events de adentro del
  subagente NO aparecieron en la captura y quedan `not_observed`. Tratarlo como
  ciego de hecho sería `not_observed → absent` (Core Rule 2) y encima ordenar al
  port a hardcodear `HOST=kimi` como ciego. El port MIDE que el canal interno no
  entrega esos eventos antes de prender el label para `HOST=kimi`; hasta esa
  medición queda `unknown` declarado.
- **kimi no corre este hook:** este repo solo le instala perfiles (12.7).

---

## 6. Qué NO se toca (fuera de alcance, declarado)

- El marcador `SUMMONAIKIT HARNESS RECEIPT` en el primer recibo del turno: se
  corrige en la instrucción global del operador, no en el hook (ver
  `Plans.md` § Phase 14, "Fuera de alcance").
- El candado de escrituras del adversary, el ruteo de modelo, los perfiles de
  los otros roles, la lista de runners y la secuencia de roles.

---

## 7. Comentario sobre la portabilidad (para el port de kimi)

Para implementar esto en otro repo que corra un hook hermano:

1. **Mecanismo:** una declaración en el recibo que sustituye, en hosts con canal
   interno ciego MEDIDO, la evidencia de verificación que el hook no puede ver.
2. **Forma exacta:** `VERIFIED BY SUBAGENT: <comandos y resultado>` (label por
   subcadena libre sobre `$text`, ver §4.5), que acredita SOLO si cumple el
   predicado concreto de la §4.3 (label + comando reconocido + resultado de
   éxito + sin señal de fallo). Solo en hosts ciegos, con verifier despachado y
   `verified=0`.
3. **Decisión para kimi — CANDIDATO, no ciego medido.** En el port, `HOST=kimi`
   NO se asume ciego: la medición pendiente es si el canal interno de kimi
   entrega los tool-events del verifier delegado (en la captura del port
   quedaron `not_observed`). **El port MIDE primero; si mide que el canal no los
   entrega, recién ahí se prende el label para `HOST=kimi`** con los mismos
   límites. Hasta esa medición, el label en kimi queda `unknown` declarado — no
   se hardcodea ni se asume. Se evalúa con `$HOST`, jamás `$TARGET` (mismo
   criterio de la §3.3).
4. **Caso golden de referencia:** el turno de zcode 2026-08-25 (intento 3 →
   bloqueo, intento 4 → lead re-corrió). El port debe heredar esta decisión de
   la Phase 14 de `summonaikit-claude`, no rediseñarla.

---

## 8. Notas guardadas para 14.2 y 14.4 (del lead; NO implementar aún)

- **14.2 — usar `$HOST`, JAMÁS `$TARGET`:** en zcode el fallback 5.4 deja
  `TARGET=claude`; si el predicado evaluara sobre `$TARGET`, el label se prendería
  también en Claude. La condición de host ciego se evalúa sobre `$HOST`.
- **14.4 — reconciliar `Plans.md`:58:** conserva la premisa refutada de que el
  intento 2 del turno zcode murió por `verified=0` + prosa sin skip-phrase. En
  realidad el intento 2 murió por `Missing SUMMONAIKIT HARNESS RECEIPT` (sin
  línea marcador), no por la evidencia. Ajustar esa fila al cierre.
