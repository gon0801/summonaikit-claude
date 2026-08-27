# summonaikit-claude — Especificación de producto

Fecha: 2026-08-08

## Purpose

Hacerse cargo del hook que gatea cada turno de Claude Code: ponerlo bajo control
propio, con pruebas de comportamiento, y cerrar los agujeros que hoy lo vuelven
un control decorativo.

**NO es una migración para escapar del vendor.** Esa premisa se verificó y es
falsa (ver § Premisas verificadas). Es hacerse cargo de un archivo que en la
práctica ya es del usuario.

## Premisas verificadas (2026-08-08, no supuestas)

Estas mediciones son la base del alcance. Si alguna cambia, el plan se revisa.

1. **La versión actual del vendor no aporta nada.** Se descargó el kit v5 en un
   directorio desechable y se comparó contra el archivo vivo:
   - sigue siendo bash (520 líneas), no el launcher Python;
   - `is_engineering_task()` mantiene el MISMO regex sin fronteras de palabra:
     medido, se arma con "cual**qui**er" y "se**gui**r" por el fragmento `ui`.
     Ese es exactamente el bug que el parche del sentinel existe para tapar;
   - `json_string_field()` es idéntico byte a byte (mismo `sed` greedy);
   - el contrato son las MISMAS 71 líneas.
   ⇒ Actualizar no arregla nada y pierde los parches. **Rechazado.**
2. **El launcher Python de los snapshots era el runtime propio del usuario**
   (`summonaikit_core`, repo `gon0801/summonaikit-core`), desactivado 2026-08-03
   y borrado 2026-08-07 — no una evolución del vendor. El archivo bash vivo es
   aquello a lo que el usuario **volvió**, no un olvido.
3. **El vendor no reescribe el archivo hoy** (kit en estado `pre-uninstall`), así
   que la fragilidad de los parches por anclas dejó de ser el riesgo principal.
4. **El hook tiene CERO pruebas de comportamiento.** Las 416 verificaciones de
   `quality-kit` prueban el *parcheador*, no el hook.

## Users And Workflows

Un operador, en Windows. El hook corre en CADA `UserPromptSubmit`, `PostToolUse`
y `Stop` de Claude Code, con el payload del turno por stdin. El usuario arma el
harness escribiendo `-saikit` en el prompt; sin ese sentinel el hook no debe
crear estado ni bloquear nada.

## Core Rules

1. **Fail-open ante lo desconocido.** El hook corre en cada turno: si no puede
   medir algo, reporta y deja pasar. Un gate que bloquea sin evidencia es peor
   que ninguno. Única excepción declarada: el instalador (§ Instalación).
2. **`not_observed != absent`.** No poder mirar no es lo mismo que haber visto
   ausencia. Se reporta `unknown`, no fallo.
3. **El sentinel `-saikit` es la ÚNICA condición de armado.** El regex del vendor
   busca sus palabras clave como SUBCADENA y en español se arma solo. Esta regla
   no se re-litiga; se vuelve código propio en vez de parche por anclas.
4. **Nunca se prueba contra el estado real.** Todo test corre contra un `HOME`
   y un directorio de hooks aislados.
5. **La identidad del archivo se declara en el archivo.** Un marcador propio
   permite distinguir "esto es nuestro" de "esto es del vendor" sin depender del
   hash del archivo entero, que cambia con cada edición legítima.

**Postura del Stop gate ante canales de texto no observados (Task 11.4,
2026-08-16).** El `stop_gate` juzga el recibo por dos canales de texto:
`last_assistant_message` (o su alias camel) en el payload y el tail del
transcript dentro del perfil (A6). La Core Rule 2 aplica también DENTRO del
gate, no solo a sus herramientas: si AMBOS canales están no observados — campo
ausente del payload y transcript ausente, ilegible o fuera del perfil —
exigir el recibo afirma ausencia desde la no-observación y cada bloqueo
consume ciclo de revisión. Postura: **fail-open declarado** — el gate emite un
diagnóstico fuerte (`unknown honesto`, por stderr — sin log de sesión: el
cierre lo borra una línea después y el presupuesto agotado tampoco loguea),
cierra con exit 0 SIN consumir ciclo y limpia el estado de la sesión (mismo
desenlace que el presupuesto agotado, A4). La distinción que preserva los
dientes del gate: campo PRESENTE sin recibo es ausencia OBSERVADA y sigue
bloqueando como siempre (claude/codex medidos 1.4/6.2; glm hereda el payload
de claude; grok sale antes por `reason` o trae `lastAssistantMessage`). Cursor
es el único host sin Stop medido: si careciera del campo y de transcript en
perfil, entra al mismo desenlace unknown — misma clase de medición pendiente
que la Task 11.6.

**Alcance MEDIDO (Task 11.6, captura real 2026-08-17,
`docs/task-11.6-captura.md`): esta rama NO alcanza a zcode.** El Stop real de
zcode trae `last_assistant_message` COMPLETO (4522 chars, con el recibo adentro;
el truncado es `responsePreview`, que el hook no lee) y el gate lo extrae y
cierra limpio. Probado por falsificación sobre el mismo payload: hay que BORRAR
la clave para que la rama dispare (exit 0 + diagnóstico), y con la clave y el
recibo mutado el gate bloquea (exit 2, `cycle=1`). O sea que la postura es
correcta como guarda de Core Rule 2 para la clase de host/turno donde el campo
falte de verdad, y no es lo que cierra el fallo de campo que la motivó.
**Residual declarado:** ese fallo (turno de zcode que agotó el presupuesto con
recibo válido) queda SIN explicación medida — el canal no estaba ciego. Si
reaparece, se captura el Stop del turno que falla; no se afirma una causa desde
la no-observación.

Extender la contención A6 al tmpdir de
zcode (camino 1 del datapoint) NO se hace aquí: queda gateado por la medición
de la Task 11.6 (`%TEMP%` es el vector A7-bis, Task 0.2).

## Data And Contracts

### Qué se hereda y qué se corrige

El archivo vivo (746 líneas) es la fuente inicial: el bash del vendor más dos
parches locales (`SAIKIT-SENTINEL-GATE v1`, `SAIKIT-REVIEW-NOTICE v1`). Al
adoptarlo, sus defectos pasan a ser responsabilidad propia. Los conocidos:

| # | Defecto | Efecto | Fase |
|---|---|---|---|
| A1 | `json_string_field` es greedy (`.*` inicial) y lee el payload CRUDO, que incluye `tool_response` | Cualquier `subagent_type` que aparezca como **clave JSON** fuera de `tool_input` registra el rol sin que corra ningún subagente; con varias ocurrencias gana la ÚLTIMA. **El efecto como estaba escrito acá —"un archivo del repo que contenga ese texto"— NO reproduce**: ver § Mediciones de la línea base | 3 — **CERRADO** (Task 3.1) |
| A2 | El recibo y la pausa se buscan en el tail del transcript entero | Un archivo con `SUMMONAIKIT HARNESS PAUSED`, o con las 6 etiquetas, deja pasar cualquier turno | 3 |
| A3 | `TEST_RUNNER_RE` sin fronteras de palabra | `cat pytest.log` cuenta como verificación (mismo hallazgo 6 ya corregido en el port de Kimi) | 3 |
| A4 | Estado llaveado por proyecto y sin revalidar el sentinel | Un turno `-saikit` abandonado sigue cobrando recibo a turnos que no lo pidieron (reproducido en vivo el 2026-08-08) | 3 |
| A5 | `command_text` crudo persiste en `harness-evidence.log` | Un comando con credenciales en la línea queda en claro en disco hasta el cierre limpio | 3 |
| A6 | `transcript_path` sale del payload y se hace `tail` sin acotar | Primitiva de lectura de archivo arbitrario controlada por payload | 3 |
| A7 | ACL: `CodexSandboxUsers` tiene `Modify` sobre el hook y su directorio de estado | Una identidad *aislada* puede reescribir el script que corre SIN sandbox en cada turno, o plantar `agents_seen` y anular el gate | 0 |
| A8 | `has_receipt_label` exige un carácter no alfabético antes de la etiqueta, y en un transcript real el que hay es la `n` del salto de línea escapado | Un recibo correcto escrito como texto corrido no satisface NINGUNA de las 6 etiquetas: el turno se bloquea hasta agotar el presupuesto. El mismo recibo en viñetas sí pasa | 3 (con A2: misma raíz, un solo arreglo) |
| A9 | La herramienta que invoca subagentes se llama **`Agent`**, y el matcher registrado nombra `Task`; los eventos de adentro del subagente sí llegan, pero llevan el rol en **`agent_type`** y el hook busca `subagent_type` | **El gate de secuencia no se puede satisfacer.** Los tres subagentes corren, el hook recibe sus eventos, y `agents_seen` queda vacío | 3 — **CERRADO** (Task 3.7) |
| A10 | El hook no ve `SUMMONAIKIT_HOOK_TARGET=claude` en la corrida real, pese a estar en el comando registrado. Mecanismo **`unknown`**: medido el efecto, no la causa | La rama exclusiva de Claude (toda la exigencia de secuencia) no corre nunca. Enmascara a A9: por eso hoy los turnos cierran limpios en vez de bloquear | 3 — **CERRADO** (Task 3.7): el host no propaga el prefijo `VAR=val` del comando (medido); el hook ahora detecta Claude por `CLAUDECODE=1` (fallback, medido) |
| A11 | El guardia de fallas busca `exitCode` en el payload, y el `tool_response` real de `Bash` **no tiene ese campo** (medido 59 de 59) | Una batería que falla se acredita como verificación, salvo que su salida diga literalmente `command not found`, `permission_denied` o `failure_type` | 3 — **CERRADO** (Task 3.8): se retiró la rama `exitCode` (código muerto) y el hook grepea dos regex de señales reales de fracaso del runner en stdout/stderr (`FAILURE_SIGNAL_RE_CI` case-insensitive con `[1-9] failed`/`Failures: N`/`AssertionError`/`error TS`/`Traceback`; `FAILURE_SIGNAL_RE_CS` case-sensitive con `test result: FAILED`/`FAIL`/`FAILURES!`/`--- FAIL:`). Postura fail-open conservada; **tsc exitoso silencioso sigue acreditando** (límite declarado); el gate sigue advisory |

A7 es anterior e independiente del plan: se corrige primero porque es el único
que no depende de ninguna decisión de diseño.

**Medición de A7 al corregirlo (2026-08-08, Task 0.1).** El otorgamiento no
estaba en `hooks/`: está **explícito en `~/.claude`** con herencia `(OI)(CI)`, y
el árbol de hooks lo heredaba entero — 16 ACE de escritura sobre 8 objetos.
Consecuencias medidas, más amplias que como estaba redactado A7:

- **El alcance real es todo `~/.claude`**, no el hook. `settings.json` sigue
  siendo escribible por esas identidades: quien puede reescribirlo puede
  *desregistrar* el hook, que es exactamente el modo de falla silencioso que la
  Task 0.2 existe para detectar. Fuera del 事前確認 de la Task 0.1; pendiente.
- **Es un patrón, no un incidente.** El fixture aislado en `%TEMP%` mostró el
  mismo `CodexSandboxUsers:Modify` más **cinco** SID huérfanos adicionales. El
  instalador del sandbox de Codex parece re-otorgar en cada corrida y dejar un
  ACE muerto por cada cuenta reciclada. Es reversible por el mismo instalador:
  por eso la corrección corta la herencia y el modo auditoría queda como
  detector permanente de la reaparición.
- **Origen del otorgamiento (log del sandbox, 2026-06-30T05:07:15):** no fue
  dirigido a `.claude`. El instalador otorgó `write` sobre ~90 rutas del perfil
  de una pasada — `.claude`, `.claude.json`, `.cursor`, `.kimi`, `AppData`,
  `Documents`, `NTUSER.DAT`. `.claude` cayó en una barrida.
- **El sandbox nunca escribió en `~/.claude`:** ningún objeto de los ~21k es
  propiedad de `CodexSandboxOnline`/`Offline`, y sus logs solo lo muestran
  leyendo (`plugins\cache`). Por eso bajarlo a `ReadAndExecute` es seguro.

### A7-bis: `%TEMP%` re-contamina por *move*, y eso invalida "corregir la raíz alcanza"

Medido 2026-08-08 durante la Task 0.2. Corregir `~/.claude` limpió los ~21k
objetos por re-propagación — la auditoría posterior dio 0. Minutos después,
`state/tooling-policy.json` volvió a tener `Modify` para el sandbox y **cinco**
SID huérfanos, marcados como heredados aunque su directorio padre ya estaba
limpio.

Mecanismo: un `move`/`rename` dentro del mismo volumen **conserva la ACL del
origen**. Los procesos que escriben a un temporal y lo mueven al destino traen
consigo la ACL de `%TEMP%`. La evidencia es exacta: `%TEMP%` otorga
`(M,DC)` — `DeleteSubdirectoriesAndFiles`, un derecho que ninguna otra ruta
concede — al SID `…448487282`, y el archivo re-contaminado apareció con ese
mismo `(M,DC)`. Explica además los 4112 objetos afectados en `plugins\cache` y
los de `projects\`: llegan por descarga a temporal y move.

Consecuencias para el alcance:

1. **Ninguna limpieza de `~/.claude` es durable por sí sola.** El modo auditoría
   deja de ser una red de seguridad opcional y pasa a ser el control.
2. **`%TEMP%` NO admite la misma receta.** Ahí el sandbox sí escribe
   legítimamente (`granting write ACE to …\AppData\Local\Temp`, 2026-03-10);
   bajarlo a `ReadAndExecute` rompe Codex. Lo que sí es removible sin
   consecuencia son los cinco SID huérfanos: cuentas borradas, sin consumidor
   posible.
3. Queda un vector residual aceptado: los archivos que lleguen desde `%TEMP%`
   traerán `CodexSandboxUsers:Modify`. Se detecta, no se previene.

### Mediciones de la línea base (2026-08-09, Task 1.2)

Grabar el comportamiento del archivo vivo contra 15 escenarios corrigió tres
cosas que estaban escritas de otra manera. Cada una vive grabada en el escenario
que la mide (`tests/golden/baseline.txt`), no solo acá.

1. **A8 es nuevo y no estaba en la tabla.** `has_receipt_label` busca
   `(^|[^[:alpha:]])(Etiqueta)[[:space:]]*:`. En un transcript real el texto del
   asistente va en una línea JSON con los saltos escapados, así que antes de
   `Understand:` el carácter que hay es la `n` de esa secuencia — alfabético.
   Medido: un recibo completo y correcto, escrito como texto corrido, falla las
   6 etiquetas (escenario 05); el mismo recibo en viñetas las satisface
   (escenario 06). O sea que hoy el veredicto del gate depende de cómo el
   asistente formateó el recibo, no de si lo escribió. **Asignado a la Task
   3.2**, no a una tarea propia: comparte raíz exacta con A2 — los dos salen de
   grepear el JSON crudo en vez de decodificarlo y mirar el texto del
   asistente, y un solo arreglo cierra los dos. Ojo con el orden: A8 hace que
   el gate exija de más y A2 que exija de menos, así que el arreglo tiene que
   probar las dos direcciones o corregir una puede tapar la otra.
2. **A1 reproduce por otra vía que la escrita.** El contenido de un archivo
   llega al payload con las comillas escapadas (`\"subagent_type\"`), y el `sed`
   pide una comilla literal: leer un archivo del repo que mencione el campo
   **no** registra el rol. Lo que sí lo registra es `subagent_type` como clave
   JSON real en cualquier nivel del payload fuera de `tool_input` (escenario 12,
   los dos pasos son la medición).
3. **Marcar `implemented` es laxo pero hoy inerte.** Cualquier payload con
   `file_path` — un `Read` de documentación, por ejemplo — deja `implemented=1`.
   No cambia ningún veredicto: `stop_gate` lee el campo y lo reescribe, pero
   nunca lo mete en `$missing`. Queda anotado para no "arreglarlo" creyendo que
   cierra un agujero que no existe, y para que se note si algún día empieza a
   pesar.

### La captura real (2026-08-09, Task 1.4): el gate de ceremonia es inerte

Se capturaron **308 payloads crudos** de un turno `-saikit` real en un repo
descartable (3 `UserPromptSubmit`, 303 `PostToolUse`, 2 `Stop`). La 1.2 había
grabado el comportamiento contra payloads *reconstruidos*; esta es la medición
contra los que el host manda de verdad. Cambió menos de lo temido en la forma y
mucho más de lo esperado en el fondo.

**Lo que la forma corrigió** (ningún veredicto de la línea base se movió):

- Los 54 fixtures **no eran JSON válido**: escapaban `C:\dev\demo` con barra
  simple. El real escapa `C:\\dev\\demo`. El hook grepea texto crudo, así que
  eso cambia lo que ven todos sus greps (se nota en el log de evidencia).
- Faltaban campos que el payload real siempre trae: `prompt_id`, `effort`,
  `tool_use_id`, `duration_ms`, y en el `Stop` **`last_assistant_message`** —
  o sea que el texto final del asistente viaja en el propio payload, no solo en
  el transcript. El recibo y la pausa tienen **dos canales**, y el gate mira los
  dos.
- `permission_mode` real es `auto` / `dontAsk`, nunca `default`.

**Lo que la captura destapó** — tres defectos, dos de ellos suficientes por sí
solos para volver decorativo el gate de secuencia:

1. **A9.** Los 8 payloads con `subagent_type` son todos `tool_name: "Agent"`, y
   el matcher registrado es `Bash|Edit|Write|apply_patch|Task`: **no llegan
   nunca**. Los que sí llegan son los 281 eventos de adentro de los subagentes,
   que traen el rol en `agent_type` de primer nivel — un campo que el hook no
   mira. Escenario 16 de la línea base: tres subagentes corren, el hook recibe
   sus eventos, `agents_seen` queda vacío y el Stop reclama los tres roles.
2. **A10.** El turno real **cerró limpio**. Con `TARGET=claude` eso es
   imposible: replicando los payloads capturados con la variable puesta, el Stop
   bloquea; sin la variable, cierra limpio — exactamente lo observado (estado
   borrado, cero `SUMMONAIKIT HARNESS GATE` en el transcript, hook ejecutado
   según el `stop_hook_summary`). El comando registrado sí lleva el prefijo
   `SUMMONAIKIT_HOOK_TARGET=claude`. Se declara el **efecto** medido; la
   **causa** queda `unknown` (Core Rule 2). El experimento que la resolvería:
   un hook que imprima su entorno, en una sesión nueva.
3. **A11.** El `tool_response` de `Bash` no trae `exitCode` en ninguna forma
   (59 de 59). De las cuatro señales de falla que busca el hook, tres son texto
   y una es ese campo: una batería que falla con un assert normal no dice
   ninguna, y queda acreditada como verificación.

**Cierre (2026-08-12, Task 3.8) — lo de arriba es historia, no estado vigente.**
A11 está CERRADO. La rama `exitCode[^0-9]*[1-9]` era código muerto (medido 59/59)
y se retiró. El guardia ahora grepea DOS regex de señales reales de fracaso del
runner sobre `combined` (command + file_path + tool_response): `FAILURE_SIGNAL_RE_CI`
case-insensitive (`failure_type`/`permission_denied`/`command not found` originales
+ `AssertionError`/`AssertionFailedError`/`Traceback`/`SyntaxError`/`TypeError`/
`error TS[0-9]` + `[1-9] failed`/`failing`/`failures?`/`errors?` con frontera de
dígito no-cero + `Failures: N`/`failures=N`), y `FAILURE_SIGNAL_RE_CS` case-sensitive
(`test result: FAILED`/`FAIL[^a-zA-Z]`/`FAILURES!`/`--- FAIL:`). Dos greps porque
`-i` es global y case-sensitive iría mezclado con falsos positivos en prosa
(`0 failures!`, `failed to connect`). Cross-review del plan con codex (1 ronda,
4 hallazgos aceptados) detectó que el primer draft usaba `[[:<:]]FAILED[[:>:]]`
(invlido en GNU grep 3.0, rc=2) y `\bFAILED\b` con `-i` (matcheaba `0 failed`).
**Postura: sigue fail-open** (no fail-closed) porque **tsc exitoso no imprime nada**
y exigir señal positiva rompería la DoD "un runner que pasa sigue acreditando".
**Límites declarados que siguen**: vitest `×`/jest `✕`/mocha `✗` (iconos sin
palabra) no se cubren; `test_FAIL.py` en un comando que pasa sería falso positivo
de la rama `FAIL[^a-zA-Z]` (raro); el gate sigue **advisory**.

**Cross-review del CÓDIGO con codex (1 ronda, 3 hallazgos, 2026-08-12):**
- **H2 (fix aplicado, `AssertionError:` con `:`)**: el primer arreglo usaba
  `AssertionError`/`SyntaxError`/`TypeError`/etc. sin `:`, y como `$combined`
  incluye `command_text`, un runner EXITOSO cuyo comando menciona la excepción
  (`pytest tests/test_typeerror.py`) matcheaba como si hubiera fracasado →
  falso positivo. Solución: exigir `:` (los tracebacks reales siempre lo traen;
  los nombres de archivo no). Verificado: `test_typeerror.py` deja de matchear,
  `TypeError: cannot read...` sigue. Caso nuevo
  `caso_g2_runner_pasa_typeerror_en_comando_sigue_acreditado` + mutación
  `mut_falla_excepciones_sin_dospuntos`.
- **H3 (fix aplicado, `mut_falla_go_quitada`)**: la mutación `mut_falla_cs_quitada`
  rompía cargo Y go (ambos CS), el driver cortaba en cargo y go quedaba sin
  mutación propia. Solución: agregar `mut_falla_go_quitada` que neutraliza SÓLO
  `FAIL[^a-zA-Z]` (rama de go), dejando `test result: FAILED` (cargo) intacta.
- **H1 (declarado, NO arreglado)**: ctest (`N tests failed`), make (`*** Error`),
  cargo-compile (`error[E0XXX]`, `error: could not compile`), gradle/mvn
  (`BUILD FAILURE` sin tests-summary) son runners reconocidos por `TEST_RUNNER_RE`
  cuyas señales de fracaso NO matchean las regex — incumplimiento parcial de la
  DoD universal, declarado como límite best-effort (no parser de runners). dotnet
  SÍ cubierto vía `[FAIL]`, y gradle/mvn CON tests-summary cubiertos vía
  `Failures: N`.

**Orden de corrección, que importa:** A10 enmascara a A9. Arreglar A9 solo no
cambia nada mientras el `TARGET` no llegue; arreglar A10 solo hace que *todos*
los turnos empiecen a bloquear, porque A9 sigue vaciando `agents_seen`. Van
juntos o el gate pasa de inerte a inservible.

**Cierre (2026-08-12, Task 3.7) — lo de arriba es historia, no estado vigente.**
A9 y A10 están CERRADOS. La re-medición de 3.7 (captura de payloads + env, no el
transcript que miró 2.4) confirmó ambas: el rol llega al gate por los eventos
INTERNOS en `agent_type` top-level (A9), y el host no propaga el prefijo
`VAR=val` del comando registrado — `PHASE` sobrevive por fallback al payload,
`TARGET` no tenía fallback y la rama `claude` nunca corría (A10). Arreglo:
`agent_type` como fallback (`:831`) y detección de Claude por `CLAUDECODE=1`
(`:23`). La conclusión de 2.4 ("el rol viaja en `subagent_type`") era una
atribución errónea del transcript; no se reconstruyó qué pobló `agents_seen`
allí y no hace falta (el arreglo es fallback). **Hueco declarado que sigue**: un
subagente read-only (Read/Grep/Glob) no genera eventos para el gate; el matcher
real no cubre `Agent` y `check-hook-registration.sh` lo reporta. Cursor/zcode
quedan sin detector (`CLAUDECODE` es Claude-only).

**Lo que sigue reconstruido, declarado:** la fase `SessionStart` (el capturador
registra las 3 fases que nombra la DoD de la 1.4) y todos los payloads de
`cursor`, que no salen de una sesión de Claude.

### Semántica atada por la suite de comportamiento (2026-08-09, Task 1.3)

La línea base de la 1.2 **detecta** que el hook cambió; no dice **qué**. La suite
de la 1.3 lo dice: `tests/lib/gate_cases.sh` afirma la semántica ACTUAL de cada
gate, con un caso que deja pasar y uno que bloquea por gate.

| Gate | Deja pasar | Bloquea / no arma |
|---|---|---|
| Armado por sentinel | `g1_arma_con_sentinel` | `g1_no_arma_sin_sentinel`, `g1_sentinel_con_frontera` |
| Evidencia de verificación | `g2_runner_marca_verificado`, `g2_excusa_declarada_no_reclama` | `g2_runner_fallido_no_marca`, `g2_falta_evidencia_reclama` |
| Secuencia de roles | `g3_turno_completo_por_eventos_permite` | `g3_falta_reviewer_bloquea`, `g3_fuera_de_orden_bloquea` |
| Recibo | `g4_recibo_en_vinetas_pasa`, `g4_pausa_permite` | `g4_sin_recibo_bloquea`, `g4_falta_una_etiqueta_bloquea` |
| Presupuesto de 2 ciclos | `g5_ciclo_consumido_no_impide_cerrar` | `g5_ciclos_cuentan_y_bloquean`, `g5_presupuesto_agotado` |
| Salidas por target | `g6_permiso_por_target`, `g6_armado_por_target` | `g6_bloqueo_por_target` |

**El mutation-test no es una promesa escrita: es una batería.** Una suite entera
en verde describe igual de bien a una que no prueba nada. Por eso
`tests/test_gate_mutations.sh` rompe *la condición* de cada gate en una copia del
hook y exige que algún caso se dé cuenta; su corrida imprime la declaración de
qué condición se rompió y qué caso la atrapó. Y como esa batería también diría
"OK" si fuera incapaz de ponerse en rojo,
`tests/test_gate_mutations_guards.sh` le pone las cuatro situaciones que debe
rechazar — mutación inexistente, `sed` obsoleto, hook mutado que no parsea, y una
mutación real que ningún caso del gate detecta.

**Dos casos graban comportamiento que ya sabemos defectuoso**, con el número al
lado: `g4_recibo_corrido_bloquea_a8` (A8) y `g4_pausa_permite` (la mitad buena de
A2). La Task 3.2 los invierte a propósito y ese diff es la declaración de qué
cambió. No se los escribe ya "corregidos": una suite que espera el arreglo no
detecta nada el día que se arregla.

**Fuera de alcance, declarado:** A1 y A3 (los cierran la 3.1 y la 3.3, cada una
con su propio test de reversión) y el aviso post-revisión, que es advisory. Los
tres quedan cubiertos por la línea base de la 1.2 (escenarios 12, 13 y 10):
cualquier cambio ahí da divergencia aunque no haya un caso que lo afirme.

**Medición nueva.** Bajo el parche del sentinel quedó código muerto en el archivo
vivo: `is_engineering_task`, `is_trivial_task` (y por lo tanto `SUBSTANTIVE_RE` y
`TRIVIAL_RE`, que solo usa la segunda) y `json_number_field` están definidos y
**nunca se llaman** — el sentinel reemplazó la condición de armado y el vendor
nunca usó el lector de números. Son ~25 líneas que la Task 2.1 se lleva puestas
al adoptar el archivo byte a byte. Se anota acá para que su remoción sea una
decisión declarada y no un descubrimiento a mitad de la Phase 3.

### La adopción (2026-08-09, Task 2.1): la fuente vive en el repo

`hooks/summonaikit-harness.sh` es el archivo vivo **byte a byte** más una sola
línea: el marcador de identidad, en la **línea 2** — la 1 es el shebang, y un
marcador antes de él rompería la ejecución.

```
# SAIKIT-CLAUDE-OWNED summonaikit-claude 1.0.0
```

Posición fija y una sola ocurrencia, por dos consumidores concretos: el
instalador de la 2.2 elige entre sus tres estados leyendo esa línea, y el skip
de quality-kit (2.3) tiene que poder mirarla sin parsear el archivo. Dos
marcadores volverían ambigua la versión que el archivo declara.

**Cómo quedó verificada la equivalencia**, en dos mitades que se necesitan:

- `sed '2d'` sobre la fuente devuelve el archivo vivo byte a byte (`cmp`). Es la
  afirmación más fuerte posible: mismos bytes, ningún margen para que el
  comportamiento difiera.
- El arnés de la 1.2 con `--check` da la salida grabada en los 16 escenarios y
  además **avisa del cambio de identidad**. Ese aviso es parte de lo afirmado:
  confirma que el marcador está y que el veredicto se dio por comportamiento, no
  por hash (decisión 2 del arnés, escrita en la 1.2 justo para este caso).

La transitividad hacia el vivo la cierra `test_golden_baseline.sh`, que ya
compara la línea base contra el archivo vivo. Correr el arnés dos veces —una por
hook— costaría 1.6 min más y no agregaría ninguna afirmación que el `cmp` no dé
ya, más fuerte.

**El código muerto se adoptó; no se removió.** Las ~25 líneas medidas en la 1.3
(`is_engineering_task`, `is_trivial_task`, `SUBSTANTIVE_RE`, `TRIVIAL_RE`,
`json_number_field`) siguen en la fuente. Es deliberado, y es la decisión
declarada que esa medición pedía: borrarlas en esta misma tarea destruiría la
propiedad byte a byte que vuelve verificable la adopción entera. Su remoción es
un cambio de bytes real con comportamiento nulo, así que le corresponde su
propia tarea y su propia declaración, con el arnés probando la inercia.

**Removido después:** la Task 10.1 [e1f6582, PR #16] retiró
`is_engineering_task`/`is_trivial_task`/`SUBSTANTIVE_RE`/`TRIVIAL_RE` (grep de
cero call sites antes de borrar). `json_number_field` sigue en la fuente: hoy
tiene definición sin call sites (muerto también), y su retiro le toca a la
tarea de limpieza que lo nombre. Este párrafo queda como registro histórico de
la decisión de adopción.

**Dato para el instalador (2.2):** el archivo vivo es **LF puro** (medido, no
supuesto: 40333 bytes con y sin `\r`), y `.gitattributes` ya fuerza
`*.sh text eol=lf`. El instalador tiene que escribir LF; con CRLF rompería la
igualdad byte a byte en la primera corrida.

### El contrato inyectado

Las 71 líneas de `HARNESS_CONTEXT` son el producto del vendor. **Consecuencia de
la premisa 1:** como su versión actual trae el mismo texto, seguirlo "en vivo" no
sigue ninguna mejora. El contrato pasa a ser propio, en el repo, con una
herramienta explícita para importar el del vendor si algún día cambia.

**Acoplamiento a declarar:** el hook de Kimi extrae su contrato de
`$HOME/.claude/hooks/summonaikit-harness.sh` — o sea de este archivo. Al
adoptarlo, este repo pasa a ser la fuente de verdad del contrato **para los dos
hosts**. Es coherente y deliberado, pero deja de ser cierto que Kimi "sigue al
vendor": sigue a este repo.

### Instalación

Por REEMPLAZO, no por anclas. Requisitos, cada uno por un modo de falla real:

- **Tres estados, no dos.** *Nuestro* (marcador presente) ⇒ verificar/reparar.
  *Vendor conocido* (hash en un manifiesto) ⇒ archivar y reemplazar. *Desconocido*
  ⇒ NO tocar, reportar fuerte. "No es nuestro ⇒ sobrescribir" es cómo se
  destruye en silencio un cambio legítimo.
- **Escritura atómica**: validar `bash -n` sobre un temporal y recién ahí `mv`.
  `cp` no es atómico; un archivo truncado rompe TODOS los turnos siguientes.
- **Backup fechado** antes de reemplazar.
- **Verificar el REGISTRO, no solo el contenido.** Si `settings.json` deja de
  apuntar al hook, el archivo puede estar perfecto y el gate no existir. Ese es
  el modo de falla más silencioso del sistema y hoy nada lo detecta.

### El instalador (2026-08-09, Task 2.2): `tools/install-hook.sh`

Los tres estados se deciden por **dos preguntas baratas y en ese orden**, no por
una heurística: ¿la línea 2 es el marcador declarado? Si sí, es *nuestro* y
`cmp` contra la fuente dice si hay que reparar. Si no, ¿su sha256 figura en
`hooks/vendor-manifest.sha256`? Si sí es *vendor conocido*; si no, *desconocido*
y no se toca. Un archivo que lleve el marcador **fuera** de la línea 2 cuenta
como desconocido: puede ser una versión futura u otra herramienta, y ninguna de
las dos habilita a pisarlo.

**El manifiesto es una decisión, no un trámite.** Cada línea afirma "este
contenido exacto ya lo miramos y archivarlo no destruye nada". Hoy tiene una
sola entrada, el archivo vivo medido (`0ec5dc04…6130`, 40333 bytes), y una
corrida `--dry-run` contra el destino real confirma que clasifica como *vendor
conocido* — o sea que el manifiesto describe la máquina, no una suposición.

**Falla CERRADO, y es la excepción declarada a la Core Rule 1.** Exit `3`
destino desconocido, `4` no observable, `5` la escritura no se pudo completar,
`2` invocación o fuente inválida. Cualquier código != 0 significa lo mismo para
el operador: *el destino quedó intacto*. Y `unknown` no se confunde con
"desconocido": no haber podido leer el manifiesto no es haber visto que el hash
falta (Core Rule 2), así que ese caso reporta `unknown` y no acusa al destino.

**Lo que el instalador se niega a hacer**, cada cosa por un modo de falla real:

- No reescribe un destino ya idéntico. Un `mv` gratis cambia el mtime, que es la
  única señal barata de cuándo cambió de verdad el archivo que gatea cada turno.
- No instala una fuente sin marcador: lo que se instale hoy sin identidad se
  clasifica *desconocido* mañana y el próximo install se planta.
- No valida la fuente sino **el temporal**, que es el archivo que va a quedar:
  `bash -n` más `cmp` byte a byte contra la fuente. El temporal se crea en el
  mismo directorio del destino a propósito — `mv` solo es atómico dentro del
  mismo sistema de archivos.

**Backups**: `<destdir>/saikit-backups/<nombre>.<vendor|nuestro>.<YYYYmmdd-HHMMSS>.bak`,
con desempate numérico si dos corridas caen en el mismo segundo. Es el contrato
que consume el `--restore-vendor` de la Task 2.4.

**Lo que la suite NO puede falsificar, declarado.** La batería de mutación
(9 mutaciones, 7 atrapadas) dejó dos guardias en pie que ningún caso mata, y el
del CRLF es un tercero de la misma clase:

1. El `cmp` del temporal contra la fuente. Para que falle habría que lograr que
   la copia transforme bytes, y `cat` no lo hace por pedido: el guardia existe
   por el CRLF que el spec advierte, no porque un test lo pueda inducir.
2. La atomicidad del `mv`. Mover el temporal fuera del directorio del destino no
   rompe ningún caso: la pérdida solo se observa con una interrupción a mitad de
   escritura, que la suite no inyecta.
3. El `sub(/\r$/, "")` con que el manifiesto tolera CRLF. El caso que lo
   ejercita pasa **con y sin** el arreglo: el gawk 5.4 de esta máquina ya
   descarta el `\r` al partir campos (medido). El guardia es portabilidad hacia
   los awk que no lo hacen; el caso afirma el requisito, no el guardia. La
   protección que sí es efectiva acá es `*.sha256 text eol=lf` en
   `.gitattributes`, que evita que el archivo llegue con CRLF.

Las tres son afirmaciones del código sostenidas por lectura, no por medición. Se
escriben acá para que nadie las cuente entre lo que la batería demostró.

### Revisión cruzada de las Phases 0 y 1 (Codex, 2026-08-10)

Una ronda por fase, con el repo como directorio de trabajo en solo lectura.
**16 hallazgos; 8 confirmados, 1 descartado, 7 sin verificar a fondo.** Ninguno
se tomó al pie de la letra: lo que sigue es lo que quedó tras comprobarlo.

**Confirmado midiendo:**

- `check-hook-registration.sh` **se cuelga** con un flag sin valor (`shift 2`
  falla y el `while` gira): `rc=124` con `timeout`. Corre en cada
  `SessionStart` desde la Task 2.3.
- **5 fixtures no son JSON válido** (los 4 del escenario 16 y una línea del
  transcript del 14): `"cwd": "C:\dev\demo"` — `\d` no es escape válido. La
  Task 1.4 declaró haber corregido exactamente esto. Hoy pasan porque el hook
  trata el payload como texto opaco; las Tasks 3.1 y 3.2 lo cambian por un
  parser real y ahí dejan de parsear.
- **`run.sh` publica `PASS` sobre `unknown`.** Los tests declaran bien
  `unknown — no se pudo mirar`; el runner colapsa eso en `PASS` y `OK`, así que
  una máquina sin el hook vivo queda entera en verde. El defecto está en el
  reporte, no en los tests.

**Confirmado leyendo el código** (`tools/hook-acl.ps1`, el único código
destructivo del repo): `Test-SidResolvable` devuelve `false` ante *cualquier*
excepción y eso borra el ACE —Core Rule 2 violada donde más caro sale—;
`-OrphansOnly` filtra la raíz pero no los descendientes; y un principal
resoluble se *degrada* en la raíz pero se *elimina* en los hijos.

**Descartado:** que `python3` resolviera al alias de WindowsApps y volviera todo
`unknown`. Ejecuta bien, y el verificador da silencio contra el `settings.json`
real.

Los confirmados son las Tasks **0.4**, **0.5** y **1.5**; los siete sin
verificar quedan escritos dentro de esas tareas, marcados como tales, para que
nadie los cuente entre lo demostrado.

#### Lo corregido en la Task 0.4 (`check-hook-registration.sh`)

- **El cuelgue sale `unknown` con exit 0, no con error.** Podría haber salido
  `!= 0`, pero el contrato de este archivo es salir 0 *siempre* y comunicar por
  texto, y sus dos llamadores —el instalador y el heal— lo asumen. Una
  invocación que no se pudo atender *es* `unknown`: no se miró nada.
- **Mencionar el hook ya no es ejecutarlo**: se descarta el comando cuyo
  programa sólo imprime (`echo`, `printf`, …), saltando las asignaciones de
  entorno que el registro real lleva por delante. **Límite declarado**: esto no
  parsea shell. Lo que se verifica es el *registro* —que el settings nombre el
  hook—, no que el comando vaya a ejecutarlo; un comando suficientemente
  retorcido puede seguir contando. Cubrir eso pedía interpretar shell, más
  riesgo del que evita.
- **Sólo se afirma ausencia cuando se leyó todo.** Con un settings ilegible
  presente, las fases que faltan se reportan `unknown`: podrían estar
  registradas justo en el archivo que no se pudo abrir.

**Medido**: 3 mutaciones, 3 atrapadas (2 asertos cada una); contra el
`settings.json` real el verificador sigue en silencio, así que el arreglo no
convirtió un registro válido en alarma.

#### Lo corregido en la Task 0.5 (`hook-acl.ps1`)

- **`Test-SidResolvable` pasa a tres estados**: `$true` la cuenta existe,
  `$false` se miró y no existe (`IdentityNotMappedException`), `$null` **no se
  pudo determinar**. Sólo el `$false` habilita a borrar. Antes cualquier
  excepción —un controlador de dominio que no contesta— devolvía `$false`, y ese
  `$false` borra el ACE: la Core Rule 2 violada donde más caro sale, porque este
  es el único código destructivo del repo.
- **Una sola política de reparación** (`Get-AclRepairAction`) y **un solo
  filtro** (`Select-RepairableFinding`), compartidos por la raíz y los
  descendientes. Las dos copias que había divergieron: `-OrphansOnly` acotaba la
  raíz pero no los hijos, y un principal vivo se *degradaba* arriba pero se
  *eliminaba* abajo.
- **Corrección: el tri-estado también en el REPORTE.** La primera pasada lo
  implementó en la decisión pero dejó `if ($f.Resolvable)` en las dos líneas que
  imprimen, y con `$null` eso cae en el `else`: un SID que **no se pudo
  evaluar** salía como `[SID huerfano]`. Como esta tarea declara la auditoría
  sin `-Fix` como *su* evidencia, la superficie que el operador lee para decidir
  era justo la que confundía "se miró y no existe" con "no se pudo mirar" — la
  misma Core Rule 2, un piso más arriba. No borraba de más (`Get-AclRepairAction`
  ya decía `no-tocar`); era de reporte. Ahora hay tres etiquetas, con su caso.

**Se pudo hacer con TDD, contra lo que la tarea asumía.** Estaba marcada
`[tdd:skip:system-acl-not-unit-testable]`, y escribir ACLs efectivamente no lo
es — pero *clasificar cuál se borra* es lógica pura. Un modo biblioteca
(`SAIKIT_HOOKACL_LIB_ONLY=1`, un `return` antes del cuerpo ejecutable) permite
cargar las funciones sin tocar una sola ACL, así que los tres defectos tienen
caso propio en `tests/test_hook_acl.sh`: **3 mutaciones, 3 atrapadas**.

**Evidencia sobre el perfil real** (auditoría sin `-Fix`, que no escribe): los
7 ACE que quedan son de `Gon\CodexSandboxUsers`, una cuenta **viva**, y
`-OrphansOnly` no selecciona ninguno — que es justo la distinción que antes no
se hacía en los descendientes.

**Sigue sin verificar** el punto que la tarea listaba como tal: el backup
excluye los objetos que `Repair-StaleInherited` modifica después, así que el
comando anunciado como restauración podría no revertir todo. No se tocó.

#### Lo corregido en la Task 1.5 (la red de seguridad)

**Los 5 fixtures**, con su guardia: `tests/test_fixtures_json.sh` exige que los
62 `.json` y los 15 `.jsonl` parseen con un parser real. Es el test que habría
atrapado esto en la 1.4 —y el que impide que vuelva—, y por eso incluye un caso
que falla si el árbol de fixtures desaparece: "0 archivos, 0 malos" no es lo
mismo que "todos válidos".

**Corrección: la primera pasada cerró 4 de 5, y el guardia no podía verlo.** La
revisión de esta misma tarea encontró que el fixture del escenario 14 pasó de
*inválido ruidoso* a **válido y silenciosamente falso**: al escapar
`C:\dev\demo\notas.txt`, el `\d` se dobló bien pero `\n` **ya era un escape JSON
legal**, así que sobrevivió y el valor decodificaba a `C:\dev\demo` + un salto de
línea + `otas.txt`. Ningún host emite eso. Es el mismo error que la 1.4 declaró
cerrado, un nivel más adentro — y el guardia recién escrito era **ciego por
construcción**, porque sólo comprobaba parseabilidad.

Por eso el guardia ahora exige además **fidelidad**: ningún campo de ruta
(`file_path`, `cwd`, `transcript_path`, …) puede decodificar a un carácter de
control. Se limita a esas claves a propósito — un `\n` dentro de un campo de
texto es legítimo. Verificado que el caso se pone rojo con el fixture viejo, y
que la línea base **no se movió** con la corrección.

**El diff de la línea base, declarado**: cambió **un solo escenario**
(`16-eventos-dentro-de-subagente`), **4 líneas**, todas la misma ruta en el log
de evidencia — `C:\dev\demo\src\sesiones.ts` pasa a `C:\\dev\\demo\\src\\sesiones.ts`
porque el payload ya es JSON válido y el hook de hoy registra el texto crudo sin
decodificar escapes. **Ningún veredicto se movió**: la línea base anterior
describía un payload que el host nunca emite.

**`unknown` deja de publicarse como `PASS`.** Los tests que no pueden verificar
salen `3`; `run.sh` los cuenta aparte, los nombra `UNKNOWN`, dice cuántos hubo
en el resumen, y **no cierra `OK` si todos lo fueron** — verde entero sin haber
probado nada es la afirmación más falsa que ese runner puede emitir. Un fallo
real sigue mandando sobre un `unknown`.

**Y antes de rendirse, se prueba lo que hay.** Desde la Task 2.1 la fuente vive
en el repo y es el archivo vivo byte a byte más el marcador, así que cuando el
hook vivo no está las baterías de semántica caen a ella y lo dicen;
`unknown` queda para cuando no hay ninguno de los dos. Resolverlo en un solo
lugar (`tests/lib/hook_bajo_prueba.sh`) es lo que evita que las cuatro copias
vuelvan a divergir.

**Error propio en el camino, declarado**: el primer intento de escapar los
fixtures usó un regex que también duplicó los `\\` ya válidos —al no coincidir
en la primera barra, el motor probaba en la segunda— y dejó *más* archivos
inválidos que al empezar. Lo atrapó el test recién escrito, en la corrida
siguiente. Se revirtió con `git checkout` y se rehizo consumiendo el par
completo de cada escape.

**Sin verificar y sin tocar**, tal como la tarea los listaba: el guard de fugas
sólo inventaría archivos regulares (ciego a symlinks y directorios vacíos);
`mktemp`/`mkdir` sin comprobar en `run.sh`; el driver de mutación no exige las
13 mutaciones únicas; y `capture-payloads.sh` no reserva su nombre de archivo de
forma atómica.

### Convivencia con quality-kit

`saikit-gate-heal.ps1` aplica los dos parches a 4 perfiles (`.claude`, `.codex`,
`.cursor`, `.agents`). Dos escritores en `SessionStart` sobre la misma ruta con
modelos distintos (parche-por-ancla vs reemplazo) pueden producir un archivo
doblemente parcheado o truncado.

La costura es **por host**: quality-kit saltea cualquier archivo que lleve el
marcador de propiedad. Un condicional. `.codex`/`.cursor`/`.agents` no cambian.
Ese cambio se mergea ANTES de instalar lo nuestro.

### La costura (2026-08-10, Task 2.3): vive en `saikit-gate-heal.ps1`

**El criterio del skip es a propósito más ancho que el del instalador.** El
instalador exige el marcador en la **línea 2 exacta** y trata cualquier otra
posición como *desconocido*; el heal saltea ante el marcador en **cualquier
línea**. No es una inconsistencia: los dos convergen en *no escribir*, que es lo
único que hace falta para que no se pisen. Para el escritor por anclas, una
señal de propiedad ambigua no habilita a parchear — abstenerse es la única
opción segura, y es la que el fixture del marcador fuera de la línea 2 fija.

**El skip corta antes de evaluar anclas.** Un archivo nuestro no tiene por qué
traer las anclas del vendor: evaluarlas primero reportaría `ANCLAS-CAMBIARON`
en cada arranque sobre un archivo que jamás se va a parchear ahí — una alarma
falsa perpetua, que es exactamente cómo se entrena a un operador a ignorar los
avisos.

**El salto se dice, y con `-Quiet` no.** Es una decisión declarada: la línea del
marcador es el dato diagnóstico y `Format-Table` la recortaría, así que va como
línea propia; pero una vez instalado lo nuestro el salto es el estado NORMAL de
cada arranque, y repetirlo en cada `SessionStart` (que corre con `-Quiet`) sería
ruido perpetuo. Lo que **no** depende de `-Quiet` es un parche sin aplicar: eso
sigue gritando como hoy.

**No se pierde gate al saltear**: la fuente de este repo trae el sentinel y el
aviso de revisión ya adentro, byte a byte (Task 2.1).

**Cuándo entra en efecto.** Medido hoy: el hook vivo **todavía no lleva el
marcador** (0 ocurrencias), así que el heal sigue parcheando exactamente como
siempre. La costura empieza a actuar recién cuando la Task 2.4 instale — que es
justo el orden que esta tarea pedía: mergear el skip *antes* de instalar.

### El registro, cableado al heal (Task 0.3 + 2.3)

`tools/check-hook-registration.sh` se conecta al final de `saikit-gate-heal.ps1`,
el único script propio que ya corre en cada `SessionStart`. Advisory puro: nunca
mueve el exit code, que sigue siendo 0 siempre.

- **Se corre sólo si hay `settings.json` o `settings.local.json`** en el perfil.
  Sin ninguno de los dos no hay registro que verificar: no es un perfil con el
  gate desregistrado, es un perfil que no existe.
- **Su salida se imprime tal cual, también con `-Quiet`.** El verificador ya
  trae su propia política de ruido —calla cuando el registro está completo— así
  que cuando habla es porque el gate no corre en alguna fase, y eso no es ruido
  de éxito.
- **Todo lo que no se pudo mirar ⇒ `unknown`**, nunca "el registro falta"
  (Core Rule 2): sin verificador, sin `bash`, si no se lo pudo lanzar, si no
  respondió en 15 s, o si salió con código ≠ 0. **Ningún `unknown` se calla bajo
  `-Quiet`** — ver abajo.
- **Tope de 15 s sobre el verificador.** Es el único proceso externo que el heal
  lanza, y corre en cada `SessionStart` (cuyo propio timeout son 30 s). Los
  parches ya están escritos cuando se llega ahí, así que cortar no pierde
  trabajo.
- La ruta sale de `-RegistrationCheck`, o del primer candidato que exista entre
  `~/.claude/hooks/` y el repo (`SAIKIT_CLAUDE_REPO`, por defecto
  `C:\dev\summonaikit-claude`).

Medido contra el `settings.json` real: el registro está completo en las 3 fases,
así que el cableado **no agrega una sola línea** al arranque de verdad.

### Cómo quedó cubierto, y qué no

La batería de `quality-kit` pasa de 416 a **443 asertos** (grupos `3n` y `3o`).
Del lado de este repo, `tests/test_quality_kit_skip.sh` mira los **dos
artefactos reales a la vez** —nuestra fuente y el heal— porque el marcador es de
acá: si un día cambia su prefijo, la batería del kit seguiría verde con su
propio literal y la costura se rompería en silencio.

**Lo que la medición demostró**, en este orden:

1. **Rojo previo**: sin la implementación caen **17 asertos** de los nuevos, con
   los 416 preexistentes intactos.
2. **Mutación del criterio** (`cualquier línea` ⇒ `sólo la línea 2`): mata los 3
   asertos del marcador fuera de posición.
3. **Mutación de la guarda de settings** (correr el verificador siempre): mata
   el caso "sin settings no hay registro que verificar".

**Defecto propio, encontrado por la mutación 2 y corregido.** El fixture del
marcador fuera de la línea 2 lo insertaba **adentro del ancla B**, así que
sobrevivía a esa mutación por el motivo equivocado —el ancla rota, no el skip—.
Movido a la línea en blanco entre las anclas A y B, el caso mata la mutación. Es
la razón por la que la batería de mutación existe: un caso verde no dice por qué
está verde.

**Lo que NO está sostenido por medición, declarado.** Que el skip se evalúe
*antes* del chequeo de anclas es una afirmación sostenida por lectura: mover el
bloque después no cambia la salida observable, porque en ambos órdenes el estado
que se reporta para ese hook es el del skip. Lo que sí está medido es su
consecuencia —un archivo salteado nunca aparece como `ANCLAS-CAMBIARON`—, y esa
la mata la mutación del criterio.

### Revisión cruzada (Codex, 2026-08-10): una política aplicada donde no iba

Una ronda con Codex sobre el commit de `quality-kit`. Tres hallazgos, **los tres
aceptados**, y los tres con la misma raíz: el cableado del registro podía fallar
en silencio **justo en el modo con el que corre de verdad**.

La regla "no repetir avisos en cada arranque" es correcta para el **skip por
propiedad** —que ocurre en cada arranque *sano*— y equivocada para los `unknown`
del verificador, que sólo aparecen cuando algo *ya se rompió*. Silenciarlos bajo
`-Quiet` volvía "no se pudo mirar" indistinguible de "todo bien": la Core Rule 2
violada en el único modo que importa. Se aplicó la misma política a dos casos de
frecuencia opuesta.

Lo corregido:

1. Ningún `unknown` del verificador se calla bajo `-Quiet`. El skip por
   propiedad sí sigue callado, y ahora por una razón que distingue los casos.
2. **Tope de tiempo.** Antes de este cambio el heal no lanzaba ningún proceso
   externo; ahora lanza `bash`, que lanza `python`. Un cuelgue se comía el
   arranque. Mismo motivo por el que `cross-review.ps1` tiene `-TimeoutSec`
   desde un cuelgue real de 2026-07-05. **Lo que el tope alcanza, medido:** el
   heal deja de esperar, lo dice y sale. **Lo que no alcanza, también medido:**
   un `sleep` lanzado por el `bash` de Git for Windows queda *huérfano* —su
   padre ya no existe cuando llega el kill, porque MSYS2 interpone su propia
   capa— así que ningún barrido por parentesco lo alcanza, y sigue reteniendo el
   handle de stdout que heredó: quien *lee* esa salida puede esperar igual. Eso
   queda acotado por el timeout del propio `SessionStart` (30 s). Cerrarlo del
   todo pedía Job Objects vía P/Invoke, y ese costo no se paga en un script que
   corre en cada arranque para cubrir el cuelgue de un chequeo que tarda menos
   de un segundo.
3. **Exit code.** Un `!= 0` de un ejecutable nativo no lanza excepción en
   PowerShell: con `&` y `try/catch`, un verificador que moría sin decir nada se
   perdía entero. Ahora se mira, y es `unknown`.

Cada uno tiene su caso en la batería (`TEST GROUP 3p`), incluido el del
verificador colgado —que se mata y se reporta— y el del `unknown` bajo `-Quiet`.

### La puesta en producción (2026-08-10, Task 2.4): el staging, y la vuelta atrás

**El override de proyecto no es una preferencia del host.** Es el propio comando
registrado en `settings.json` el que lo hace, y esto se midió, no se supuso:

```
h="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/.claude/hooks/summonaikit-harness.sh"
[ -f "$h" ] || h="$HOME/.claude/hooks/summonaikit-harness.sh"
```

Tres consecuencias que fijan el diseño del staging:

1. **Corre UN solo hook por turno**, no dos. No es que el del proyecto se sume
   al del perfil: el comando elige uno.
2. **El estado también queda aislado.** El hook deriva `STATE_ROOT` de su propia
   ubicación (`$(dirname "$0")/state`), así que el staging escribe en
   `<repo>/.claude/hooks/state/` y no toca el estado del perfil.
3. **Hace falta un repo git.** La ruta la resuelve `git rev-parse
   --show-toplevel`; en un directorio suelto el archivo quedaría puesto y no
   correría nunca — un staging que miente. `tools/stage-override.sh` lo rechaza.

**La herramienta no lee el registro para creerle: lo ejecuta.** Un `settings.json`
al que le sacaron el fallback al proyecto se ve igual de bien en una lectura
superficial y convierte el staging en una ilusión (el archivo puesto, el turno
gateado por el global). La medición corre el comando registrado con el repo como
cwd y un **`HOME` desechable**, donde el fallback del perfil apunta a un archivo
que no existe: si algo corrió, fue el override. De paso ningún estado puede caer
en el perfil real. Lo que la medición dejó se borra: el turno real tiene que
arrancar con el estado en cero.

**`--restore-vendor` vive en el instalador y no en un script aparte**, porque la
vuelta atrás tiene los mismos modos de falla que la ida. Lo que se le exige:

- **Elige por el sello del nombre, no por orden alfabético.** El desempate `-N`
  del mismo segundo cae *antes* que el que no lo lleva (`-` es 0x2D y `.` es
  0x2E), así que un `sort` a secas restaura el más VIEJO de los dos en silencio.
  Medido con una mutación: restaura `MEDIO` donde correspondía `NUEVO`.
- **Archiva el destino antes de pisarlo.** Si no, deshacer es un camino de una
  sola dirección y el que se arrepiente no tiene a qué volver.
- **No pisa un destino DESCONOCIDO.** Que el comando se llame "restaurar" no lo
  habilita a destruir el cambio de otro.
- **Exit 6 ≠ exit 4.** "Se miró y no hay backup" es un hecho observado; "no se
  pudo listar el directorio" es `unknown` (Core Rule 2). Confundirlos deja al
  operador sin saber si buscar el archivo o arreglar permisos.
- **Idempotente, y la comparación va antes de clasificar**: si el destino ya es
  byte a byte el backup, no hay nada que decidir. Sin ese orden, una segunda
  restauración clasificaría como DESCONOCIDO el vendor que ella misma dejó (no
  lleva marcador y su hash no tiene por qué estar en el manifiesto) y abortaría
  acusando a su propio resultado.

La ida y la vuelta comparten `preparar_temporal` / `archivar_destino` /
`publicar_temporal`. No es estilo: dos copias de la misma política divergen en
silencio, que es exactamente lo que la Task 0.5 encontró en `hook-acl.ps1`.

**El ensayo, sobre los archivos reales y ANTES de tocar el global** (repo
descartable `C:\dev\saikit-staging`): se puso ahí una copia del hook vivo, el
instalador lo clasificó *vendor conocido* y lo reemplazó archivándolo, y
`--restore-vendor` lo devolvió **byte a byte** (`cmp` contra el vivo). O sea que
la vuelta atrás se probó con el mismo archivo, el mismo manifiesto y el mismo
código que iban a correr sobre el perfil.

**Lo que el staging midió del gate** (comando registrado real, `HOME` desechable):
un prompt sin sentinel **no crea estado**; uno con `-saikit` arma; y el `Stop` de
ese turno armado **bloquea** (`decision: block`) con y sin `SUMMONAIKIT_HOOK_TARGET`.

**El install global, verificado punto por punto.** El destino clasificó *vendor
conocido* y quedó archivado en
`~/.claude/hooks/saikit-backups/summonaikit-harness.sh.vendor.20260810-161037.bak`.
La afirmación fuerte: `sed '2d'` del archivo vivo reproduce ese backup byte a
byte — o sea que **el único cambio en el archivo que gatea cada turno es la línea
del marcador**. Una segunda corrida dice `YA AL DIA` y no reescribe; el
verificador del registro calla (las 3 fases siguen registradas); y
`--restore-vendor --dry-run` confirma que la vuelta atrás está disponible sin
ejecutarla.

**La costura de la Task 2.3 entró en efecto, y se midió el día que correspondía.**
Aquella tarea dejó declarado que el heal seguiría parcheando hasta que la 2.4
instalara. Corrido después del install, `saikit-gate-heal.ps1 -Check` reporta
`saltado-propiedad` en los dos parches sobre `~\.claude\hooks\...` y
`ya-parchado` en los otros tres perfiles: la convivencia funciona en la máquina
real, no sólo en fixtures.

**Un test de la Task 2.1 se puso rojo por haber cumplido su propósito**, y el
arreglo es parte de esta tarea. `test_hook_source.sh` afirmaba que `sed '2d'` de
la fuente devuelve el archivo vivo — cierto mientras el vivo fuera el del vendor,
falso desde el install. El archivo vivo tiene ahora **dos estados sanos** y el
test distingue cuál corresponde: sin marcador ⇒ la resta del marcador lo
reproduce (la afirmación original de la 2.1); con marcador ⇒ es la fuente entera,
sin restar nada. Lo que sigue siendo FAIL, y no una nota, es un vivo que se
declare nuestro y difiera de la fuente: ahí el perfil quedó desincronizado y hay
que correr el instalador. Las tres ramas se verificaron por separado (vivo real,
backup del vendor, y un archivo con marcador pero distinto).

**Lo que NO se puede medir sin una sesión nueva, declarado.** Claude Code
fotografía los hooks al arrancar, así que "gatea turnos reales" en vivo es un
paso con persona adelante, igual que la captura de la Task 1.4.
`tools/stage-override.sh` imprime el procedimiento al terminar.

#### Revisión cruzada de la Task 2.4 (Codex, 2026-08-10): 5 hallazgos, 4 aceptados y 1 a medias

Una ronda. La cadena `auto` empezó por kimi, que **se colgó a los 600 s** —
intentó correr la suite entera, que tarda ~18 min — y siguió con Codex. Ninguno
se tomó al pie de la letra.

1. **`--restore-vendor` no comprobaba el backup contra el manifiesto.** Aceptado,
   con la severidad matizada: no agrega superficie de escritura (quien pueda
   plantar un backup en `saikit-backups/` ya puede escribir el hook), pero es una
   **incoherencia real** — el instalador se niega a tocar un destino desconocido
   y su vuelta atrás instalaba en la ruta que gatea cada turno cualquier archivo
   que llevara el nombre correcto y parseara. Por construcción todo backup
   `.vendor.` legítimo tiene su hash en el manifiesto (sólo se etiqueta así lo
   que el instalador ya clasificó como vendor conocido), así que exigirlo no
   rompe ningún flujo. De paso, la consulta al manifiesto quedó en **una sola
   función** que comparten la ida y la vuelta.
2. **La medición del staging pisaba el CONTENIDO del estado preexistente.**
   Aceptado, y era el peor: el turno de prueba *arma* el harness, así que
   reescribía `harness-state.env` y el log del estado que encontrara. Conservar
   los archivos y no su contenido dejaba el siguiente turno REAL de ese repo
   armado por una medición — **A4 reproducido a mano** por la herramienta que
   venía a ayudar. El caso que lo tapaba era propio y comprobaba que el archivo
   existiera, no que no hubiera cambiado. Arreglo: el estado se **aparta entero**
   antes de medir y se devuelve después; la medición corre sobre un directorio
   vacío, así que "apareció algo" es una señal limpia en vez de una diferencia de
   huellas que interpretar.
3. **`MEDIDO` ignoraba el exit code del comando.** Aceptado a medias: lo que se
   afirma es que corrió el hook del proyecto, y eso queda demostrado aunque el
   comando termine mal — mezclarlos confundiría dos afirmaciones distintas. Pero
   callarlo escondía un dato del turno, así que ahora se dice como nota, sin
   mover el veredicto.
4. **`rc=$?` dentro de `if ! bash …` siempre vale 0.** Aceptado: todo fallo del
   instalador se anunciaba como "exit 0", un código que nunca pasó.
5. **Cualquier fallo del lector del settings distinto de rc 1 se reportaba como
   "no está registrado".** Aceptado, y es lo más grave de los tres bajos:
   afirmar la ausencia del registro porque el intérprete murió es la Core Rule 2
   al revés. Ahora los tres desenlaces se mapean explícitamente y el catch-all es
   `unknown`.

**Lo que la corrección de estos hallazgos dejó, además de los arreglos**: dos
defectos propios que aparecieron al implementarlos y que ningún revisor había
visto — `limpiar_medicion` no era idempotente (corre explícita y por trap, y la
segunda pasada borraba el estado que la primera acababa de devolver), y el
borrado de lo que crea la medición necesitaba una bandera propia
(`medicion_corrida`), porque sin ella una salida temprana con el trap ya
instalado habría borrado el estado del operador — el trap que existe para
protegerlo. Los dos los encontró la propia batería.

**Costura nueva y declarada**: `SAIKIT_PYTHON` permite inyectar un intérprete que
muera con un código cualquiera. Sin ella el hallazgo 5 no se podía poner en rojo
desde la suite, y un guardia que ningún caso mata es una promesa escrita, no una
batería.

**Total tras la ronda: 17 mutaciones dirigidas, 17 atrapadas.** Una sola ronda,
como manda la política; no quedaron hallazgos residuales sin cerrar.

#### El turno real (2026-08-10, operador adelante): pasó, y corrigió una conclusión propia

El paso manual se ejecutó el mismo día, en `C:\dev\saikit-staging`. Las dos
mitades de la DoD quedaron medidas en vivo:

- **El staging gatea turnos reales.** Un prompt con `-saikit` armó el harness y
  dejó estado en `<staging>/.claude/hooks/state/2257410127/`; uno sin sentinel no
  creó nada.
- **Sin tocar el archivo global.** El hook del perfil siguió byte a byte igual a
  la fuente y en `~/.claude/hooks/state/` no apareció ninguna clave nueva.

**Y el estado que dejó ese turno contradice el efecto medido de A9:**

```
task_hash=2939555692
cycle=0
implemented=1
verified=0
agents_seen=implementer,verifier,reviewer
```

A9 afirma que `agents_seen` **queda vacío**. Acá tiene los tres roles, en orden,
y el log de evidencia los registra uno por uno (`agent: implementer`,
`agent: verifier`, `agent: reviewer`). El transcript de esa sesión explica por
qué: la herramienta de subagentes efectivamente se llama **`Agent`** (3
invocaciones, ninguna `Task` — esa mitad de A9 sigue en pie), pero el rol viajó
en **`subagent_type`** (3 ocurrencias) y `agent_type` no aparece ni una vez — o
sea en el campo que el hook SÍ lee.

**Lo que esto cambia, y lo que no:**

1. **La conclusión "el gate de ceremonia es inerte" no reproduce hoy.** El turno
   no bloqueó, pero no por falta de gate: bloqueó nada porque **se cumplieron
   todos** — los tres roles en orden y el recibo con sus 6 etiquetas.
2. **La Task 3.7 tiene que RE-MEDIR antes de arreglar.** Su plan es hacer que un
   evento con `agent_type` de primer nivel registre el rol; si hoy el rol llega
   por `subagent_type` y funciona, ese arreglo tocaría algo que no está roto.
   Queda anotado en su DoD.
3. **Lo que NO se probó en vivo es un turno real que FALLE.** Que el gate bloquee
   cuando falta el recibo está medido sintéticamente (payload de `Stop` con el
   comando registrado real), no con una sesión que se porte mal a propósito.
4. `verified=0` pese a que el verifier corrió `python -m pre_commit` y `wc -c`:
   coherente con A3 —`TEST_RUNNER_RE` no nombra `pre-commit`— y sin efecto en el
   veredicto, porque el recibo declara la verificación y el `Stop` la acredita
   por esa vía.

**Lo que quedó declarado antes de este turno, y por qué se corrige.** Al cerrar
la tarea se escribió que la cláusula "un turno `-saikit` real bloquea" era
incumplible por A10, apoyándose en la medición de la 1.4 (el turno real de aquel
día cerró limpio con `agents_seen` vacío). La corrida de hoy mide otra cosa sobre
el mismo host, así que la conclusión se corrige acá en vez de dejarla en pie: lo
que sigue sin resolverse es **A10** —no se sabe si el `TARGET` llega, porque este
turno satisfizo todos los gates y por lo tanto no distingue las dos ramas— y lo
que caducó es el efecto de **A9**.

### A1 cerrado (2026-08-10, Task 3.1): el rol se lee de `tool_input`, y de ahí solo

**Primero se midió dónde viaja el campo de verdad**, sobre los 308 payloads
crudos de la captura de la Task 1.4 (los mismos que sostienen A9 y A10):

| ruta JSON | payloads |
|---|---|
| `.tool_input.subagent_type` | 8 |
| `.tool_response.agentType` | 8 |
| `.agent_type` (primer nivel) | 281 |

`subagent_type` **nunca** aparece en el primer nivel: 8 de 8 vienen dentro de
`tool_input`. Esa medición es lo que vuelve seguro el arreglo restrictivo —
acotar la lectura a `tool_input` no toca ninguna vía por la que hoy llegue un
rol legítimo. (`.agent_type` es A9 y se lo lleva la Task 3.7, que tiene su propio
mandato de re-medir; acá no se tocó.)

**El defecto, con su huella exacta.** `json_string_field` arranca con `.*`
greedy sobre el payload CRUDO — que incluye `tool_response`, o sea texto que el
turno no escribió. Con `tool_input.subagent_type=implementer` y otro
`subagent_type` como clave JSON más adelante, el hook anotaba **reviewer**: no
solo inventaba un rol, **borraba el legítimo**. Los dos casos nuevos separan
esas dos mitades, y los dos estaban en rojo antes del arreglo.

**El arreglo es un escáner, no un parser JSON**, y la distinción importa:
recorre el payload carácter por carácter llevando dos cosas — si está adentro de
una string (respetando la barra de escape) y a qué profundidad de llaves está —
y con eso contesta la única pregunta que hace falta: *¿esta clave está adentro
del `tool_input` de primer nivel?*. No valida el documento, no entiende números
ni literales, y **no decodifica escapes**.

**Cero dependencias nuevas, y es una decisión declarada.** El renglón autorizaba
`python` con fallback declarado o leer sólo `tool_input`; se eligió lo segundo,
en `awk`, por dos razones: `awk` ya es dependencia dura del hook (lo usan
`json_escape` y el `task_hash`, así que si faltara el hook ya estaría roto antes
de llegar acá), y un primario-con-fallback son dos políticas que divergen en
silencio — exactamente lo que la Task 0.5 encontró en `hook-acl.ps1`. La Task
3.2 decide por su cuenta: decodificar el transcript es otro problema (texto
multilínea, no extracción de un campo) y puede pedir otra herramienta.

**Los escapes se dejan crudos a propósito.** Un valor escapado no mapea a ningún
rol en `canonical_agent_role`, así que el error cae del lado seguro: no se
acredita un subagente que no se pudo leer limpio. Decodificar acá abriría la
puerta a que un nombre con escapes unicode acredite un rol que no dice.

**Postura de fallo, declarada:** si el escáner no devuelve nada no se registra
rol — el mismo desenlace que un payload sin el campo. Es el lado estricto del
gate de secuencia, y es deliberado: inventar un rol para "dejar pasar" *es* A1.

**El diff de la línea base, declarado**: cambió **un solo escenario** (`12`),
**4 líneas** — desaparece `agent: reviewer` del log, `agents_seen` queda vacío y
el aviso de revisión deja de fechar una revisión que no ocurrió
(`last_review` vacío). Los otros 15 escenarios no se movieron, incluidos los
cuatro turnos completos (05, 06, 10, 11) que delegan por
`tool_input.subagent_type`: la vía legítima quedó intacta, medida y no supuesta.

**2 mutaciones dirigidas, 2 atrapadas, y cada una por un caso distinto** —
volver al lector greedy lo atrapa `caso_g3_gana_el_de_tool_input_no_el_ultimo`;
que el escáner deje de acotarse a `tool_input` lo atrapa
`caso_g3_eco_fuera_de_tool_input_no_cuenta`. El orden de los dos en `CASOS_G3`
no es cosmético: la batería corta en el primer rojo, así que invertirlos dejaría
una de las dos mutaciones sin caso propio en la declaración. Total del hook:
**15 mutaciones, 15 atrapadas**.

**Un test se puso rojo por haber cumplido su propósito, y el arreglo es parte de
esta tarea** — el mismo patrón que la Task 2.4 con la mitad byte a byte.
`test_hook_source.sh` exigía que el arnés **avisara** del cambio de identidad al
correr contra la fuente. Eso era cierto mientras la línea base viniera del hook
del vendor; desde que la Phase 3 cambia el comportamiento a propósito, la línea
base se regraba contra la fuente y ese aviso no puede existir. El caso pasa a
distinguir los dos estados sanos: línea base grabada contra **otra** identidad ⇒
se exige el aviso; grabada contra la **fuente misma** ⇒ se exige el silencio (si
avisara, la línea base estaría describiendo otro archivo). Sin uno de los dos
shas ⇒ `unknown`, no se inventa el veredicto. La transitividad hacia el vivo no
se apoyaba en ese aviso: la sostienen `test_golden_baseline.sh` y el `cmp` de la
mitad byte a byte. **3 mutaciones sobre este caso, 3 atrapadas**, una de ellas
—mutar el arnés para que avise siempre— dirigida específicamente a la rama nueva,
porque las dos primeras caían las dos en la rama vieja y no la habrían
distinguido.

**El install se corrió**, que es lo que lleva el arreglo al archivo que gatea
cada turno: el destino clasificó *nuestro pero distinto* ⇒ reparado con backup
(`…/saikit-backups/summonaikit-harness.sh.nuestro.20260810-214244.bak`), y el
vivo quedó byte a byte igual a la fuente. Sin ese paso el defecto seguiría vivo
donde importa y las dos baterías que comparan contra el vivo quedarían rojas.

**Lo que NO cierra esta tarea, declarado.** El gate sigue siendo **advisory**:
quien controla el `tool_input` de un evento de delegación sigue pudiendo nombrar
el rol que quiera. Lo que A1 cerró es que lo haga desde el *resultado* de una
herramienta, que es texto que el turno no escribió. Y la laxitud de
`implemented` (cualquier payload con `file_path` lo enciende) sigue igual: está
medida como inerte en la § Mediciones de la línea base, y arreglarla no es parte
de este renglón.

#### Revisión cruzada de la Task 3.1 (Codex, 2026-08-10): 1 hallazgo, aceptado con el arreglo corregido

Una ronda, sobre un worktree aparte con el diff de la tarea sin commitear
(`hooks/` + `tests/`, 22 224 caracteres — bien por debajo de los 44 k que
hicieron timeout en la retro de 2026-07-09). **Un solo hallazgo, severidad baja**,
y no se tomó al pie de la letra:

> `tests/golden/baseline.txt:927` agrega whitespace final; `git diff --check`
> falla con exit 2 y puede romper controles de higiene o CI.

**El hecho es cierto y la corrección obvia habría estado mal.** Lo que la
verificación agregó:

1. **Es preexistente, no una regresión de la 3.1.** Ya había 30 líneas así antes
   del cambio (ahora 31), y `git diff --check` ya salía 2 en `3421ad0`, el commit
   con que la Task 1.2 grabó la línea base por primera vez.
2. **23 de las 31 son contenido GRABADO**, no suciedad: líneas vacías del stdout
   del hook, que el arnés muestra con prefijo `| `. Ahí el espacio final es
   fidelidad — quitarlo falsificaría la grabación, y el propio `--check` del
   arnés marcaría divergencia contra su generador. Las otras 8 son `# `, del
   prefijado de los README. O sea que arreglar el generador —la lectura natural
   del hallazgo— **no habría alcanzado el objetivo**: las 23 seguirían ahí.
3. **La línea base es el único archivo versionado del repo con whitespace final**
   (medido sobre `git ls-files` entero). El resto cumple la disciplina al 100%.

Por eso el arreglo va en `.gitattributes` y no en el artefacto ni en el
generador: `tests/golden/** -whitespace` exime al path del chequeo, deja
`git diff --check` en 0, no toca un archivo que su propia cabecera declara "NO
editar a mano", y **no se derrama** al resto del repo (verificado con
`git check-attr`: `unset` sólo ahí, `unspecified` en el código). `text eol=lf`
sigue vigente para el path, que es lo que sostiene la comparación byte a byte
entre máquinas.

**Declarado y no corregido**: el generador sigue emitiendo `# ` al prefijar una
línea en blanco de un README. Con el path ya exento no cambia nada observable, y
corregirlo obligaría a regrabar la línea base entera —30 líneas de ruido— dentro
de la tarea cuya evidencia es justamente que el diff fueron 4 líneas y un solo
escenario.

**Sin hallazgos residuales.** Una sola ronda, como manda la política.

### El segundo host: zcode (GLM) — premisas medidas 2026-08-10

`zcode` es el CLI propio de Z.ai (paquete npm `zcode-app-cli`, config en
`~/.zcode/`). **No confundirlo con el launcher `glm`**, que es otra cosa medida
el mismo día: `glm` hace `exec claude` con `ANTHROPIC_BASE_URL` apuntando a Z.ai
y sin tocar `CLAUDE_CONFIG_DIR`, así que una sesión `glm` **ya está gateada hoy**
por este hook — los hooks los ejecuta el CLI, no el modelo, y el comando
registrado no nombra modelo ni proveedor (verificado con
`tools/check-hook-registration.sh` contra el settings real).

Lo medido de zcode, leyendo su config real y el bundle del CLI (incluida su
propia guía `zcode-guide-plugin/skills/diagnosing-hooks`):

1. **Tiene sistema de hooks, con el mismo contrato.** Config en
   `~/.zcode/cli/config.json`, forma
   `{enabled, timeoutMs, maxOutputBytes, events: {<Evento>: [{matcher, hooks:[{type,command,timeout}]}]}}`.
   El wrapper difiere del de Claude (`hooks.events.X` contra `hooks.X`); **el
   array interno es idéntico**.
2. **Los 7 eventos incluyen los 3 que este hook necesita**: `UserPromptSubmit`,
   `PostToolUse`, `Stop` (más `SessionStart`, `PreToolUse`, `PermissionRequest`,
   `PostToolUseFailure`). No soporta `SubagentStop` ni `PreCompact`.
3. **El payload y el contrato de salida usan el mismo vocabulario**: en el
   bundle aparecen `hook_event_name`, `tool_name`, `tool_input`,
   `transcript_path`, `session_id`, `hookSpecificOutput`, `additionalContext`,
   `stopReason`, `subagent_type` y `agent_type`.
4. **El operador YA corre hooks de Claude dentro de zcode**, apuntando a
   `$HOME/.claude/hooks/...` (`cbm-session-reminder`,
   `cbm-code-discovery-gate`). Es evidencia de compatibilidad práctica, no
   teórica — y la raíz del defecto que la Task 5.3 cierra.
5. **Override de workspace**: la guía y zcode.z.ai documentan
   `<repo>/.zcode/config.json`. **En este CLI (3.7.5-11) no corre:**
   `normalizeProjectConfig` (`gri`) saca la clave `hooks` y emite
   `config_project_hooks_ignored`. El canal que sí dispara es el user-config
   `~/.zcode/cli/config.json` (medido en el plan de la Task 5.1, no en la
   captura). La 5.5 no puede copiar el staging de 2.4 a ese override.

Y cuatro diferencias que fijan el diseño de la fase, todas declaradas por la
guía del propio CLI:

- **El matcher tiene alias `Task` ↔ `Agent`** (y `Write`/`Edit` ← `ApplyPatch`).
  En Claude eso es media A9: el matcher registrado nombra `Task` y la
  herramienta se llama `Agent`, así que esos eventos no llegan nunca. **En
  zcode el alias sí los transporta** (Task 5.1: un `PostToolUse` con matcher
  `Task` llegó para `tool_name=Agent`).
- **El stdout NO se valida con esquema estricto: una clave extra NO invalida la
  salida** (medido Task 5.2: una forma 1 con `"saikitProbe":true` añadido se
  inyectó al modelo igual que la forma limpia). El esquema de 3.7.5-11 tolera
  claves extra — coincide con la doc oficial zcode.z.ai, no con la guía
  `diagnosing-hooks`. Las cuatro formas de salida del hook tienen veredicto
  MEDIDO en zcode (aceptada/rechazada/ignorada) en `docs/task-5.2-salida.md`.
- **`exit 2` en Stop SÍ bloquea** (medido Task 5.2: 4 pasadas del modelo antes
  del tope interno de zcode); también bloquea `{"decision":"block"}` con exit 0.
  La lectura literal de la guía vieja ("Stop pide continuación, no bloquea") no
  aplica en 3.7.5-11. Era la medición que más pesaba de la fase y salió a favor
  del gate.
- **El matcher de `UserPromptSubmit` se prueba contra el TEXTO DEL PROMPT** y el
  de `Stop` contra la vista previa de la respuesta, no contra un nombre de
  herramienta. Un matcher copiado del registro de Claude no matchearía nunca.
  Además, los hooks de archivo **no corren sin `hooks.enabled: true`** (hoy está
  en `true`), y `timeout` va en **segundos**.

La forma anidada y el dueño del rol ya no son pregunta: Task 5.1 los midió
en un turno real. El contrato de **salida** tampoco: Task 5.2 midió las cuatro
formas + `exit 2` y declaró `TARGET=claude` alcanzando (`docs/task-5.2-salida.md`).

### Medido 2026-08-12, Task 5.1 (captura real de zcode)

Captura de un turno `-saikit` real en zcode (CLI 3.7.5-11), 3 fases
(`UserPromptSubmit`, `PostToolUse`, `Stop`). Detalle y tabla de diff de forma
en `docs/task-5.1-captura.md`. Veredicto por premisa:

- **Premisa 4 (alias `Task`↔`Agent`): CONFIRMADA, funciona.** El matcher `Task`
  disparó para un `tool_name=Agent`. Implicancia: el matcher PostToolUse del
  harness (`Bash|Edit|Write|apply_patch|Task`) atrapa la delegación en zcode
  sin cambiar — la mitad de A9 que falta en Claude acá llega.
- **Forma anidada:** zcode emite cada clave en snake_case (la que lee el hook,
  idéntica a Claude) **y** camelCase duplicada. Compatible.
- **Rol del subagente:** viaja en `tool_input.subagent_type`; **no** hay
  `agent_type` top-level. La herramienta se llama `Agent`.
- **Ninguna premisa de forma/rol tumbada** → Phase 5 sigue como adaptación
  del hook existente, no como port propio. El override de proyecto **ya
  estaba caído** para este CLI (punto 5); no es hallazgo de la captura.

Hechos **nuevos** (no en las premisas) que 5.2–5.5 deben resolver: `CLAUDECODE`
está **ausente** en el env del hook (la detección de target necesita
`ZCODE_SESSION_ID` / `ZCODE_PROJECT_DIR`); `transcript_path` apunta a un
**temp efímero**, no al perfil (revisar contención A6 en zcode); y
`tool_response.exitCode` **sí** viene en eventos Bash (inofensivo hoy, A11
retiró su uso).

### Medido 2026-08-12, Task 5.3 (aislamiento de estado cross-host)

Defecto nuevo, medido por lectura de la config real: si el harness se registra
desde zcode apuntando al **mismo `$0`** que Claude (la forma `cbm-*` que el
operador ya usa, `$HOME/.claude/hooks/…`), `STATE_ROOT` sale de `dirname $0` y
los dos hosts escribían **el mismo `harness-state.env`** del mismo proyecto con
la misma sesión — A4 en versión cross-host. Detalle y mecanismo en
`docs/task-5.3-aislamiento.md`.

- **Mecanismo: llaveado explícito por host** (no copia del binario). El path pasa
  a `STATE_ROOT/$HOST/$PROJECT_KEY/$SESSION_KEY/harness-state.env`. `HOST` se
  elige por señal de env medida (5.1): `zcode` si `ZCODE_SESSION_ID` o
  `ZCODE_PROJECT_DIR` no vacíos; `claude` si `CLAUDECODE=1`; `other` en cualquier
  otro caso. `ZCODE_*` gana a `CLAUDECODE`; `other` **nunca** escribe en `claude`
  ni `zcode` (Core Rule 2). `RN_PENDING_PATH` hereda `HOST` vía `PROJECT_DIR`
  (un Stop de zcode no puede tomar el aviso pendiente de Claude). No se migra el
  árbol viejo `state/$PROJECT_KEY/`: queda huérfano.
- **A6 en zcode = fail-open por temp.** `transcript_path` es un tmp efímero
  (`%TEMP%/zcode-claude-hook-*`) fuera del perfil; la contención de A6 lo
  rechaza (`transcript=unknown`) y el gate corre con `last_assistant_message`
  (presente, 5.1). **No** se agranda la allowlist de A6: leer un tmp plantable
  es una primitiva nueva, fuera de esta task.
- **`TARGET` no se toca** (5.2 declaró `TARGET=claude` alcanza; cablear el
  registro en zcode es 5.4). La medición **viva** (STOP estilo 2.4 sobre el mismo
  repo con los dos hosts) queda pendiente del operador: necesita registrar el
  harness en el user-config de zcode, que es alcance de 5.4. Mientras no exista,
  el lab es la evidencia y la task no se declara `cc:完了` (no se reescribe la
  DoD en silencio).

### Medido 2026-08-12, Task 5.4 (registro e instalación en zcode)

El harness queda registrado en las 3 fases del user-config de zcode
(`~/.zcode/cli/config.json`, forma `hooks.events.<Evento>[]`). Es la SEGUNDA
forma de registro que aprendieron los tools. Detalle en `docs/task-5.4-plan.md`.

- **Registro:** `--host zcode` es append-only al user-config (no instala el
  archivo, que va antes con la invocación sin `--host`). 3 fases, `type:command`,
  `timeout:15`; **sin matcher** en `UserPromptSubmit`/`Stop` (el match value ahí
  es el texto/preview, no el tool name — un matcher copiado de Claude no matchea);
  `PostToolUse` con `Bash|Edit|Write|Read|apply_patch|Task|Agent` (el alias
  `Task`↔`Agent` de 5.1 cubre). Idempotente por grupo propio bien formado;
  `--quitar-zcode` saca solo las entradas `--saikit-harness-id 5.4` (nivel entrada,
  no grupo). Preflight: `hooks.enabled==true` estricto y DEST `NUESTRO_IDENTICO` +
  la línea de código del aislamiento 5.3.
- **A10 cerrado en zcode:** `CLAUDECODE` no llega (zcode no lo setea). El hook
  resuelve `TARGET=claude` por `ZCODE_SESSION_ID`/`ZCODE_PROJECT_DIR` (la señal
  que 5.1 midió que el host sí inyecta). La ceremonia implementer→verifier→reviewer
  corre en el segundo host. No se crea `TARGET=zcode` (5.2 declaró que alcanza).
- **Budget zcode = exit 2:** `continue:false`+exit 0 es **ignorado** por zcode
  (5.2). El corte por presupuesto depende de `exit 2`, que en Stop sí bloquea en
  zcode. Solo se invierte el exit del budget para el segundo host; Claude intacto.
- **PHASE lee camel:** un Stop realista de zcode trae **solo** `hookEventName`
  (camel), no `hook_event_name`. Sin leer camel, `PHASE` cae a `tool` y
  `stop_gate` no corre. El hook lee ambos (con `json_top_level_string`, no el sed
  greedy).

### Medido 2026-08-12, Task 5.6 (perfiles de agente en zcode)

El runtime de zcode 3.7.5-11 solo acepta `subagent_type` registrados. Built-ins:
`general-purpose` y `Explore`. Carga user-level de `~/.zcode/agents/<name>.md`
y project-level de `<repo>/.zcode/agents/<name>.md` (Settings → Subagents
escribe el primero). Sin `implementer`/`verifier`/`reviewer` ahí, el Agent
tool rechaza el tipo **antes** de que el hook vea el evento, y el Stop no
puede pasar la ceremonia.

- **`--host zcode` instala los tres perfiles** desde `agents/` del repo a
  `~/.zcode/agents/` (override: `SAIKIT_ZCODE_AGENTS_DIR` /
  `SAIKIT_ZCODE_AGENTS_SOURCE`). Detecta `bash.exe` **antes** de escribir
  perfiles (si no hay bash, exit 2 y el dir queda vacío). Después valida
  plantillas y escribe; al final appendea el user-config. No toca DEST.
- **Tres estados**, igual que DEST: `AUSENTE` instala; `NUESTRO_IDENTICO`
  (marca `saikit_owned: summonaikit-claude` **solo en el primer bloque
  frontmatter** + `cmp` con la plantilla) no reescribe; `NUESTRO_DISTINTO`
  repara con backup; `DESCONOCIDO` (sin marca en frontmatter, aunque el
  body la cite) no se toca y se reporta — el hook igual se registra
  porque el tipo ya existe.
- **`--quitar-zcode`** borra solo los que llevan la marca en frontmatter,
  **archivando antes** (`agents/saikit-backups/`). Un `implementer.md` de
  otro se queda.
- **No se copia de `~/.claude/agents`.** Esa ruta es del otro host y
  lleva `model: sonnet`. La fuente versionada es `agents/*.md` (sin
  `model:`; heredan GLM del padre).
- Plantillas **no** cubren `closer`/`retro`: el gate los pide como
  secciones del recibo, no como tipos del Agent tool.
- **`saikit_owned` y `skills:` no rompen el loader de zcode** (Opus r1
  #1, verificado contra `zcode.cjs` 3.7.5-11): el parser exige
  `name`+`description`; `skills` es clave oficial; el resto se ignora.

### Medido 2026-08-13, G2 skip en español (vivo zcode)

Un turno `-saikit` con `hola.txt` ya existente corrió implementer →
verifier → reviewer (5.6) y escribió el recibo. El Stop igual bloqueó
con `Missing verification evidence or explicit skipped-check reason`:
el modelo dijo "No corrí los candados" y mostró `od`/`wc`, pero el
`grep` solo aceptaba `not run` / `not executed` / `skipped` / italiano.
El contrato UPS decía "or skipped with a concrete reason" sin listar
los tokens. Soplarle al operador las palabras mágicas no es el
producto.

- **`VERIFY_SKIP_RE`** acepta también `no corri` / `no se corrio` /
  `no se corrieron` / `no se ejecuto` / `no se ejecutaron` / `sin tests`
  (y las formas con acento). **No** acepta `se corrio` suelto: el
  recibo que afirma que sí corrió la batería sigue exigiendo runner o
  skip explícito (`caso_g2_falta_evidencia_reclama`).
- El contrato UPS nombra esas frases. El mensaje de Stop se deja
  igual para no regrabar la baseline.
- Catch: `caso_g2_excusa_espanol_no_reclama` (recibo del vivo).
  Mutación: `mut_skip_sin_espanol`.

**Residuales (Opus 5 max r1, 2026-08-12) — no se parchan, se declaran:**

- `#2` DESCONOCIDO registra el hook: por diseño (el tipo ya existe).
- `#6` `--host zcode` no honra `--dry-run`: residual de 5.4; no se
  arregla solo en agentes.
- `#7` no se instala `<repo>/.zcode/agents`: Settings Beta es user-level.
- `#8` verifier/reviewer heredan `Edit, Write` del kit Claude; el gate
  es estructural, no semántico.
- `#12` backups viven en `agents/saikit-backups/` (subdir, no `*.md`).
- `#14` dos fuentes (Claude `~/.claude/agents` vs `agents/` del repo):
  declarado, sin detector de deriva.

La medición **viva** de 5.3/5.4 cerró el 2026-08-13 (turno `-saikit` en
zcode: estado bajo `state/zcode/`, ceremonia implementer→verifier→reviewer,
budget exit 2).

### Medido 2026-08-13, Task 5.5 (línea base zcode)

Escenarios 17–25 en `tests/fixtures/escenarios/` y bloque en
`tests/golden/baseline.txt`. El token `zcode` del arnés exporta
`ZCODE_*` (no `TARGET=zcode`). `--check` reproducible (25 escenarios).
Cada gate tiene un caso que pasa y uno que bloquea en este target.
Staging por `<repo>/.zcode/config.json` no aplica (override ignorado,
5.1). El turno vivo `-saikit` arma y el pelado no (5.3/5.4/5.6).
Baseline regrabada contra el hook post-G2-skip-ES (contrato UPS nombra
`no corri`).

### Ampliaciones de host aprobadas — Phases 6 y 7

El contrato de producto se amplía de una fuente compartida por Claude/zcode a
dos hosts adicionales, sin prometer que ya estén operativos:

- **Phase 6 — Codex CLI 0.147.0:** adopta la copia estructural existente bajo
  `~/.codex/hooks/`, mantiene wrapper y `hooks.json` ajenos intactos, aísla el
  estado como `state/codex/` y sólo prende la ceremonia si la captura real 6.1
  demuestra que el rol llega. El contrato de salida se decide con 6.2.
- **Phase 7 — Grok Build 1.0.3:** instala una copia propia y un JSON propio bajo
  `~/.grok/hooks/`, conserva `compat.claude.hooks = false`, aísla el estado como
  `state/grok/` y adapta el envelope camel según los payloads reales 7.1
  (**ya medidos**, ver abajo). Las formas de bloqueo dependen de 7.2; si no se
  pueden medir, el host no se publica como gate funcional.

### Medido 2026-08-13, Task 7.1 (captura Grok)

37 payloads en 5 rondas de `grok -p` headless sobre repo descartable
(`docs/task-7.1-captura.md`). Envelope con **claves camel y valores snake**
(`hookEventName: "user_prompt_submit"`, `sessionId`, `toolInput`,
`lastAssistantMessage`, `transcriptPath` → adentro de `~/.grok/sessions/`, A6
contiene). El rol del subagente llega por **tres canales** (`SubagentStart`,
despacho `spawn_subagent` con `toolInput.subagent_type`, eventos internos con
`subagentType` de primer nivel) y el `env` map del handler entrega
`SUMMONAIKIT_HOOK_TARGET=grok` ⇒ **la ceremonia Grok es exigible**. El matcher
alias-expande (`Bash`→`run_terminal_command`, `Task`→`spawn_subagent`,
`Write`→`write`). `GROK_HOOK_EVENT`/`GROK_SESSION_ID` presentes, `CLAUDECODE`
ausente. Premisas de la doc que **cayeron**: `PostToolUseFailure` no dispara
(las fallas llegan como `post_tool_use` con `toolResult` de error), el shell
de hooks en Windows es **powershell.exe** (el comando registrado usa la forma
`& "bash.exe" "hook"`), la tool de escritura real es `write` (además de
`search_replace`), y el prompt del usuario llega envuelto en
`<user_query>…</user_query>`. Perfil `~/.grok` byte a byte intacto; trust del
repo descartable declarado y revocado.

### Medido 2026-08-14, Task 7.2 (contrato de salida Grok)

7 rondas headless (una por forma) + 4 variantes oráculo
(`docs/task-7.2-salida.md`). **Bloquea:** `decision:block` top-level con exit 0
(log `block=true`, el turno continúa y el modelo recibe el `reason`) y
`continue:false`+`stopReason` (log `prevent_continuation=true`). **No bloquea:**
`exit 2` — el wrapper PowerShell lo devuelve como exit 1 y Grok es fail-open
ante exit ≠ 0 en Stop. **No llega al modelo:** `additionalContext`, en ninguna
de las 4 formas medidas (envuelta camel/snake o top-level, en UPS o en Stop) —
el armado por contrato inyectado necesita otro canal en 7.3. `systemMessage`
parsea sin rechazo pero no tiene superficie en headless. El esquema **no es
estricto** (clave extra tolerada). La decisión sobre el Stop de cierre
(`reason=shutdown`) se emite y se ignora sin mutar estado ⇒ D6 confirmado.
Decisión: `TARGET=grok` con **forma propia** (bloqueo sin exit 2) y armado a
re-planificar; el gate no es decorativo. Perfil `~/.grok` byte a byte intacto
(cksums antes/después); trust declarado y revocado.

Las mediciones 7.1/7.2 son independientes de Phase 6. Las costuras compartidas
se serializan: 7.3 después de 6.4, 7.5 después de 6.5 y 7.6 después de 6.6. El
orden final de identidad es `grok > codex > zcode > claude > other`. Hasta que
los turnos vivos de 6.6/7.6 cierren, Codex y Grok son **alcance aprobado**, no
capacidad observada; `not_observed != absent` sigue aplicando.

### Medido 2026-08-16, Task 10.9 (la fase de arranque en los otros tres hosts)

La 10.6 acotó las reglas permanentes a `TARGET=claude` porque era el único host
con `SessionStart` medido. Esta medición saca a los otros tres de la hipótesis.
Detalle y evidencia: `docs/task-10.9-medicion.md`.

**Los tres tienen fase de arranque y disparó en los tres** (`.ok` del probe, no
lectura de documentación). El literal del evento sigue la misma tabla por host
que 7.1: `SessionStart` en zcode y Codex, **`session_start`** en Grok.

**Grok 1.0.4 — `additionalContext` IGNORADO en la fase de arranque.** Las tres
formas (envoltorio camel, envoltorio snake, top-level) emitieron y ninguna llegó:
ni a la respuesta del modelo ni a los archivos de sesión. El oráculo se agotó
antes de declarar `ignored`. Extiende a `SessionStart` lo que 7.2 midió en
UPS/Stop, y lo hace sobre **1.0.4** — 7.2 fue sobre 1.0.3, y esa diferencia de
versión queda declarada: **los veredictos de 7.2 describen una versión que ya no
es la instalada** y su revalidación es tarea propia, no de esta fila.

**Codex 0.147.0 — registrar un hook NO es editar `hooks.json`.** Cada handler
exige además un registro propio en `~/.codex/config.toml`:

```toml
[hooks.state.'<ruta del hooks.json>:<evento_snake>:<indice_grupo>:<indice_hook>']
trusted_hash = '…'
enabled = true        # presente en algunos
```

Un grupo sin ese registro **se saltea en silencio**: sin error, sin aviso y sin
línea en la traza del host. Se llegó descartando de a un turno real por
hipótesis: no es el cwd, no es el matcher, no son las comillas de la ruta y no es
la posición en el array. Es la misma familia que el hallazgo de la 6.1
(«`config.toml` exige `trusted_hash` por entrada y uno nuevo no corre»), medido
allá para un `<repo>/.codex/hooks.json` y **confirmado acá para el `hooks.json`
GLOBAL**. Consecuencia operativa: **los índices son parte de la clave de
confianza**, así que reordenar el array de una fase desalinea el `trusted_hash`
de los hooks ya registrados — no se reordena.

**zcode 3.7.5-11 — ACEPTADA, y sin rama nueva.** Turno real con el operador
adelante: el texto entra al request del modelo como mensaje `role="system"` con
el prefijo `SessionStart hook additional context:` y numeración `#1` —**la misma
forma que la 5.2 midió para UPS**, sólo cambia el nombre de la fase— y el modelo
devolvió el token literal que ese texto le pedía. `TARGET` para zcode resuelve a
`claude` (fallback `ZCODE_SESSION_ID`/`ZCODE_PROJECT_DIR`, decisión de la 5.4),
así que la condición del hook ya lo cubría: lo que cambió es el **registro**,
`install-hook.sh --host zcode` pasa de 3 a 4 fases.

Eso cierra de paso un **polizón**: el guard de la 10.6 —que su comentario
describe como «sólo Claude»— también cubría zcode, y lo único que lo frenaba era
que el instalador no registraba la fase de arranque, equilibrio que ningún caso
sostenía. El caso que lo ata nació exigiendo lo contrario (que la 4.ª fase NO se
registrara mientras zcode fuera `unknown`) y **se invirtió el mismo día**, con el
veredicto en la mano: el cambio de ese archivo es la declaración de que la
medición existió, en vez de un aflojamiento silencioso.

**Dos de tres habilitan emisión, y el resultado no fue uniforme** — que es
exactamente por lo que la fila mide en vez de extrapolar. zcode y Codex aceptan;
Grok se midió y da `ignorada`, así que no se registra: sería texto muerto en cada
arranque de ese host. `not_observed != absent`: en los tres la fase existe y
corre.

**Límite operativo de zcode, declarado:** su `/login` escribe la API key en
`~/.zcode/cli/config.json`, el mismo archivo donde el instalador y el probe hacen
su append. Cualquier verificación de integridad sobre ese archivo tiene que ser
**por estructura** (conteo de entradas por marker, vecinos ajenos, JSON válido),
no por cksum ni por diff de contenido.

## Ampliación de propiedad — Phase 12

**La reapertura, declarada.** Este repo pasa a ser dueño de los perfiles de
agente en `claude` (`~/.claude/agents/`) y `kimi` (`~/.agents/agents/`). Es el
mismo movimiento que la Phase 6 al reabrir `.codex`: se escribe con su razón —
que el gasto siga al riesgo, rol por rol, en vez de que los cinco perfiles del
kit corran todos en `model: sonnet` sin `effort` declarado— y su vuelta atrás,
que es la misma máquina de tres estados del hook: `--host claude
--restore-vendor`-equivalente no existe todavía como flag propio, pero el
backup del vendor archivado (`.vendor.<sello>.bak`, ver *Los límites* abajo)
es la evidencia recuperable si hay que revertir a mano.

**Qué compra la posesión y qué no.** El CLI del kit puede volver a escribir
esos perfiles en cualquier `saikit-update` posterior. La posesión hace que la
siguiente corrida del instalador lo **detecte y repare** — un archivo con la
marca `saikit_owned` que difiere de la fuente se archiva y se reescribe en la
corrida siguiente. Es **reparación, no exclusividad**: nada en este repo evita
que otro proceso escriba esos archivos entre corridas del instalador.

**Los límites**, uno por línea con su razón:

- `closer` y `retro` siguen con el `model: sonnet` del vendor. La fuente
  versionada de este repo cubre tres roles (`implementer`, `verifier`,
  `reviewer`); la posesión es por archivo, no por directorio, así que los dos
  que la fuente no cubre quedan `DESCONOCIDO` e intactos.
- Codex queda fuera. No tiene instalación de perfiles de agente y su
  ceremonia sigue condicionada a lo que mida la Task 6.1.
- Fable 5 fuera del ruteo automático. `review` en claude usa Opus 5 ($5/$25
  por millón contra $10/$50 de Fable 5, el doble en salida); Fable queda
  disponible como escalada manual.
- `effort` sólo donde se midió. Un `effort:` que el host ignora deja el
  perfil diciendo una cosa y el runtime haciendo otra — el tipo exacto de
  mentira que el resto de este spec persigue.
- La adopción por hash sólo repara si el vendor reescribe con los MISMOS
  bytes que ya están en `agents/vendor-manifest.sha256`. Si el vendor cambia
  el texto del perfil, el hash deja de matchear y el instalador cae a
  `DESCONOCIDO`: no toca nada y reporta, en vez de pisar un cambio que nadie
  miró.
- `--refrescar-manifiesto` reporta (hash + diff), JAMÁS adopta. Adoptar un
  hash nuevo del vendor es pegarlo en `agents/vendor-manifest.sha256` en un
  commit propio, con el diff a la vista en la revisión — no hay `--force`.
- La fila `claude` del router (`tools/model-routing.sh`) no tiene medición
  viva propia como zcode/grok/kimi (12.1/12.2/12.3): la evidencia es **cita**
  de documentación oficial del vendor (`https://code.claude.com/docs/en/sub-agents.md`
  y `https://code.claude.com/docs/en/model-config.md`, 2026-08-24), no
  captura contra un runtime, y se acota a lo citable (corrección del review
  cruzado de CodeRabbit sobre el PR #62, que encontró la primera redacción
  sobre-afirmando): el frontmatter de subagentes soporta `model:` y `effort:`
  (`low`/`medium`/`high`/`xhigh`/`max`, hereda por default); un `model:`
  override se valida contra la allowlist `availableModels` de la sesión —
  si el valor pedido queda excluido, la doc describe sustitución dentro de la
  MISMA familia permitida o, si no hay sustituto, mantener/heredar el modelo
  de la sesión. La conducta exacta ante un `model:` completamente
  desconocido (hay rutas documentadas donde falla la petición, no sólo
  fallback) y ante una clave de frontmatter no reconocida queda
  **NO OBSERVADA**: sin sonda reproducible contra el runtime no se afirma —
  misma disciplina que este spec ya aplica a captura viva (12.1/12.3), ahora
  también a cita de documentación de vendor.

### Medido 2026-08-23, Task 12.1

**zcode (`docs/task-12.1-medicion.md`, inspección estática de `zcode.cjs`
3.7.5-11, misma vía que la 5.6).** `model:` **sí** es clave oficial del
frontmatter de agentes (`a=h5i(Vj(o.model))` en el parser `ezt`). `effort:`
**NO existe** como clave de frontmatter — la clave real que el parser
destructura es `thoughtLevel:` (aunque `/effort` sí exista como slash command
de sesión, de cara al usuario, sin relación con el parser de agentes). Un
valor desconocido en `model` o `thoughtLevel` **pasa sin validar**: ninguno de
los dos tiene guardia como sí la tienen `color`/`permissionMode` (`Set`
fijo) — `h5i` sólo trata el literal `"inherit"` como "sin valor". El catálogo
real de la cuenta (entitlement) quedó **NO OBSERVADO**: el catálogo de
referencia embebido en el bundle es multi-proveedor genérico (contiene IDs de
proveedores ajenos a Z.AI) y su sola presencia ahí no confirma qué puede usar
esta cuenta. `~/.zcode/agents` byte a byte idéntico antes/después.

### Medido 2026-08-24, Task 12.2

**grok (`docs/task-12.2-medicion.md`, captura headless sobre repo
descartable, host grok 1.0.5).** grok **sí** honra `model:` y `effort:` por
agente — verificado por registro interno del host (`subagents/<id>/meta.json`
→ `effective_model_id`; `chat_history.jsonl` → `model_id`/`reasoning_effort`
del subagente), no por inferencia de la respuesta del modelo: el subagente
sonda corrió con `grok-4.5-build`/`low` mientras el turno padre corría con
`grok-4.6-build`/`xhigh` (los defaults de `config.toml`). Un `model:` con un
ID inexistente **cae en silencio al modelo por defecto del padre** — el
despacho NO falla, no hay error visible en la CLI ni en el `meta.json` — pero
el `effort:` válido de la misma sonda **se sigue aplicando** de forma
independiente (no cae al `xhigh` del padre). Catálogo real de esta cuenta,
2026-08-24 (`models_cache.json`, refrescado por el propio CLI en cada
invocación): `grok-4.6` (default) y `grok-4.5`; reemplaza al listado
2026-07-09 (`grok-4.5`, `grok-composer-2.5-fast`) que era de otra cuenta y
otra versión de CLI (0.2.93 contra 1.0.5 medido acá) y no se hereda. Perfil
`~/.grok/agents/` byte a byte intacto; el diff de huella completo quedó
estrictamente aditivo (tres logs nuevos bajo `~/.grok/debug/`, generados por
el `--debug` necesario para correlacionar el registro interno), adjudicado
por el Lead con el reviewer de la 12.2.

### Medido 2026-08-18, Task 12.3

**kimi (`docs/task-12.3-medicion.md`, captura viva, kimi-code 0.34.0).** La
premisa que gateaba la tarea — que kimi-code **lee** `~/.agents/agents/` —
quedó **CONFIRMADA**: no es inferencia, el lead resolvió un subagente sonda
citando su `description` del frontmatter. Pero el host **no acepta `model:`
ni `effort:` por agente**: el parser (`parseAgentFileText`) lee un conjunto
**cerrado** de claves (`name`, `description`, `whenToUse`, `override`,
`tools`, `disallowedTools`, `subagents`, `model_preference`), y ninguna de las
dos está ahí. La única palanca de modelo es `model_preference` ∈ {`primary`,
`secondary`} — dos slots, no un ID. La fila `kimi` de `tools/model-routing.sh`
queda **vacía de forma definitiva**, no provisoria. Hallazgo extra con más
consecuencia operativa: una **clave desconocida** (`model:`, `effort:`) se
ignora en silencio y el agente carga normal, pero un **valor inválido en una
clave conocida** (p. ej. `model_preference: sonnet`) hace que el archivo **no
parsee y el agente desaparezca del registro sin error visible en la CLI** —
si le pasara a `implementer`, `verifier` o `reviewer`, la ceremonia se queda
sin roles y el gate no tiene a quién acreditar. `~/.agents/agents/` byte a
byte idéntico (los 5 perfiles del vendor y la sonda borrada).

**Medido 2026-08-24, Task 12.7 (sonda directa contra el parser real de
kimi).** Gap señalado por el review del PR #59: el candado original de
`tests/test_install_hook.sh` verificaba con grep/sed, sin ejercer el parser
real de kimi, si `saikit_owned:` — la única clave que este instalador agrega
al perfil, ausente del conjunto cerrado que la 12.3 midió arriba — se
comporta como el resto de las claves desconocidas (se ignora en silencio) o
como un valor inválido en clave conocida (borra el agente del registro). Se
plantó `~/.agents/agents/saikit-probe-127.md` con `name`/`description`/`tools`
(subconjunto del set cerrado) más `saikit_owned: summonaikit-claude`, y
`kimi -p 'Delega al subagente saikit-probe-127...'` **resolvió el tipo y
devolvió la respuesta esperada** (`PROBE-127-OK`): `saikit_owned` cae en el
caso "clave desconocida, se ignora en silencio", confirmado contra el parser
real y no sólo por lectura de código. Huella de `~/.agents` y `~/.kimi-code`
idéntica antes/después (podada de contabilidad de runtime).

## El cuarto rol — adversary (Phase 13)

**Qué es.** `adversary` es un cuarto rol OPT-IN de la ceremonia: corre
DESPUÉS del verifier y ANTES del reviewer (`implementer → verifier →
adversary → reviewer`). Ataca el cambio — entradas no manejadas, datos
preexistentes, tests que no discriminan, blast radius, falla parcial, trust
boundary — y SOLO reporta a un artefacto: jamás repara, jamás toca fuente. El
disparador es una decisión del lead con el MISMO criterio que ya dispara el
cross-review — el cambio toca auth, pagos, migraciones o datos preexistentes,
o el hook mismo. **Sin invocación, el comportamiento del turno es
byte-idéntico al de los tres roles de siempre**: ningún host, gate ni perfil
cambia de comportamiento.

**Enforcement REAL, no prometido.** Ningún host registra `PreToolUse`: no
existe canal para negar una escritura antes de que ocurra, así que el candado
es detección post-hoc + bloqueo en el Stop, no un guardia preventivo.

- Única zona de escritura permitida: `.saikit/findings/` — un prefijo de
  DIRECTORIO, no una ruta con clave (dir-scoped keyless), porque el
  `session_id` no se propaga a ningún subagente en ningún host medido; un
  candado que dependiera de un id que el escritor no puede conocer no cierra
  nada.
- Canonicalización FÍSICA de ambos lados de la comparación (`cd` + `pwd -P`,
  no `pwd` lógico): cierra la forma `C:/` (Windows, vía `git rev-parse`)
  contra la forma `/c/` (Git Bash) del mismo path, y resuelve directorios
  symlink intermedios en la cadena — sin esto, la comparación fallaría
  siempre en Windows o dejaría pasar un symlink plantado.
- `.saikit` o `.saikit/findings/` como symlink es violación de SETUP, no ruta
  permitida: el candado la rechaza en vez de resolverla — resolverla con
  `realpath` haría pasar cualquier escritura a través de un enlace plantado
  por el hueco de `Bash` de abajo.
- El hook crea un `.gitignore` con `*` dentro de `.saikit/findings/` al
  primer evento que resuelva a adversary por cualquier canal medido (despacho
  o interno) — clase de efecto NUEVA para el hook (hasta hoy solo escribía
  bajo su propio directorio de estado). Idempotente: crea si está ausente,
  jamás reescribe uno existente, ni siquiera uno ajeno que no cubra los
  artefactos.
- Escaneo de secretos por sesión en el Stop: mira las rutas que el candado
  registró como escritas por el adversary de esta sesión más cualquier
  archivo del directorio con mtime posterior o igual a la ÉPOCA de armado
  guardada en el estado — el armado INICIALIZA ese estado (época, rutas y
  violación se reemplazan, nunca se heredan de una sesión anterior muerta).
  Las formas ya redactadas por el perfil (`token=[REDACTED]`,
  `://[REDACTED]@`) se DESCUENTAN antes de grepear: un artefacto redactado
  como manda el perfil no vuelve a disparar el escaneo que esa misma
  redacción existe para satisfacer.
- Fail-closed SOLO en dos entradas — el resto del candado es fail-open como
  el resto del hook: (1) una escritura atribuida al adversary detectada fuera
  de `.saikit/findings/` — defecto PROBADO por el propio evento que lo
  reporta; (2) un secreto matcheado en un artefacto de esta sesión — riesgo
  alto, no certeza (un regex tiene falsos positivos), con ruta de fuga MANUAL
  declarada: el mensaje nombra archivo y número de línea, jamás el
  contenido, y el remedio es redactar o borrar el artefacto y re-cerrar.
- El recibo lleva una línea `ADVERSARY: N findings, highest severity X` —
  label-only: presencia exigida por el gate cuando el adversary corrió,
  contenido NUNCA validado contra el artefacto (el gate no parsea el JSON en
  el Stop ni confía en un archivo que otro modelo pudo haber reescrito).
- El gate exige el orden `implementer → verifier → adversary → reviewer`
  SOLO cuando `adversary` aparece en `agents_seen` de la sesión; sin eso, el
  gate y el orden quedan exactamente como hoy.
- Dos escotillas nuevas: `DELEGATED - awaiting adversary` (el lead delegó en
  vivo y sigue esperando) y `ROLE FALLBACK: ADVERSARY` (el adversary fue
  despachado y murió sin reportar) — misma disciplina que las escotillas ya
  usadas por los otros tres roles.

**Los límites**, uno por línea con su razón — el consolidado completo de las
tasks 13.1–13.8 y sus cross-reviews (incluidos los del PR #63/#64) vive en
`docs/phase-13-adversary-design.md` § "Límites declarados (consolidado)"; acá
va la versión de cierre, con los hallazgos posteriores al diseño (cross-review
de los PRs #65 y #66) ya sumados:

- `Bash` es best-effort, no un parser de shell: detecta redirección/heredoc/
  `tee` OBVIOS en comandos atribuidos al adversary; `cp`/`mv`/`dd` y las
  expansiones de variable quedan fuera del vocabulario a propósito — un
  parser de shell completo es el pantano que este spec ya rechazó para otras
  guardias.
- El candado queda ciego en `zcode` y `kimi`: la atribución INTERNA (la que
  dice que un Edit/Write vino del adversary, no del lead) es `unknown` en
  esos dos hosts — fail-open declarado, sin bloqueos por atribución ahí. Si
  un canal no medido apareciera mañana, el candado correría DE MÁS, nunca de
  menos. **Actualización kimi (2026-08-25, lectura cruzada de capturas del
  port `summonaikit-kimi`, kimi-code 0.34.0):** el DESPACHO sí lleva
  `tool_input.subagent_type` (misma forma snake que claude/zcode — el lector
  actual lo acreditaría sin cambios) y los internos llevan `agent_name` solo
  en `SubagentStart/Stop`; los tool-events de adentro del subagente no
  aparecieron en la captura (`not_observed`). Matiz que reencuadra el límite:
  kimi no corre ESTE hook — corre el del port; encender el rol ahí es tarea
  del port (ver `docs/smoke-adversary-hosts-2026-08-25.md`).
- TOCTOU del artefacto: sin canal de negación no hay forma de sellarlo ni de
  hacerlo append-only — una re-corrida del adversary DESPUÉS de que el
  reviewer adjudicó puede reescribir el JSON conservando un `agents_seen`
  válido. El ancla real es el VEREDICTO del reviewer en el transcript, no el
  JSON: el gate jamás valida N contra el archivo, mismo límite que la línea
  `ADVERSARY:` label-only.
- Invocado-no-observado es indistinguible de no invocado: un nombre sin
  mapear o un host sin canal de atribución interna cierra el turno limpio,
  sin la línea `ADVERSARY:` — no se promete detectarlo.
- Ambigüedad de sesiones concurrentes: el canal primario de adjudicación es
  el LEAD nombrando el artefacto en el despacho del reviewer; degradado (no
  lo nombró), el reviewer toma el `*.json` de MAYOR mtime del directorio —
  dos sesiones corriendo a la vez pueden confundirse ahí. Es fail-safe:
  escanea de más, no de menos.
- Evasión por mtime retrocedido: un `touch -t` a una fecha anterior al armado
  saca al artefacto del escaneo de secretos por completo — instancia del
  mismo hueco de `Bash` de arriba, no uno nuevo: el escaneo atrapa
  persistencia ACCIDENTAL, no a un evasor deliberado.
- Filename con newline: un nombre de artefacto con `\n` parte el output de
  `find` y el loop `while read` salta los fragmentos — misma clase de
  evasión deliberada de arriba (el escaneo persigue persistencia
  ACCIDENTAL); en Windows ese nombre ni se puede crear.
- Falso negativo y falso positivo del escaneo de secretos: la familia de
  patrones es la MISMA que el hook ya usa inline (`redact_secrets`) —
  reducida a propósito, porque `tools/check-secrets.sh` no existe en el repo
  consumer donde el hook corre y duplicar sus formatos extendidos ahí sería
  una segunda copia sin candado de fuente única. Un secreto con forma no
  reconocida pasa; un valor con pinta de secreto que no lo es (p. ej. un
  `token=abc` de un test de auth) bloquea, con la misma ruta de fuga manual.
- Las rutas de fuga fail-closed viajan redactadas: el mensaje de violación,
  el de secreto matcheado y la línea de log usan `redact_secrets` sobre el
  PATH del artefacto, no solo sobre su contenido — el nombre del archivo lo
  elige el propio adversary y puede llevar pinta de secreto; sin esto, el
  canal que reporta una fuga podría abrir una segunda.
- El escaneo por mtime depende de GNU `date -d`: sin él (por ejemplo en BSD o
  macOS), esa rama se omite con diagnóstico por stderr — fail-open declarado
  de una falla de infraestructura, no de una decisión de producto.
- El remedio de una violación es revertir + RE-ARMAR un turno nuevo con
  `-saikit`, no re-cerrar el mismo turno: el flag de violación persiste a
  propósito toda la sesión y el bloqueo nunca verifica el revert (verificarlo
  sería correr git dentro del Stop); limpiarlo sin verificar perdonaría la
  escritura. Re-cerrar el turno bloqueado sigue bloqueado; solo un armado
  nuevo reinicia el estado. Agotar el presupuesto de 2 ciclos también
  resetea — mismo desenlace que cualquier otro presupuesto agotado del gate.
- El `.gitignore` del consumer es pisable: `*` no afecta archivos ya
  trackeados, y `git add -f` lo pisa igual; un `.gitignore` AJENO
  preexistente jamás se edita, así que si no cubre los artefactos quedan
  expuestos. La ventana de exposición varía por host: en `claude`/`grok`/
  `codex` el gitignore aparece a mitad de la corrida (con el primer evento
  interno del adversary); en `zcode`, donde solo el despacho tiene canal
  medido, aparece recién al TERMINAR la corrida entera.
- La superficie de eco de `ROLE FALLBACK: ADVERSARY` creció con el contrato:
  mismo trade-off ya aceptado para los otros tres roles — el match es una
  subcadena sin anclar sobre texto del asistente.
- El lane `fast` se salta la ceremonia entera, adversary incluido — el gate
  no exige despacharlo ahí, igual que no exige los otros tres roles. Pero si
  un turno `fast` SÍ lo despachó y quedó visto en `agents_seen`, la línea
  `ADVERSARY:` se exige igual que las demás etiquetas del recibo: no es una
  excepción.
- `kimi` instala el PERFIL sin ruteo: la posesión del archivo viaja por la
  costura sellada en la Phase 12 (12.6/12.7); el ruteo de modelo/effort no
  aplica ahí porque el host no acepta esas claves por agente (sellado,
  12.3) — no confundir las dos cosas.
- `zcode` hereda la fila vacía del padre en el router de modelo (12.1): sin
  catálogo observado, el tier `review` no tiene valores propios para este
  host.
- `codex` NO tiene costura de perfiles: `--host codex` instala solo la
  segunda copia del hook, no perfiles de agente — queda `unknown` declarado
  hasta que un canal de atribución interna se mida ahí, no se afirma.
- `adversary` es kit-owned SIN entrada de vendor: un `adversary.md` ajeno en
  el destino es DESCONOCIDO — nunca adoptable por hash como el resto de los
  perfiles, porque no hay un vendor que lo publique; `--refrescar-manifiesto`
  lo reporta como tal y advierte que ese camino de adopción no existe para
  este rol.
- El descuento de formas redactadas cubre las tres formas que el rol produce:
  `token=[REDACTED]` suelto, el valor ENTRECOMILLADO (`token="[REDACTED]"`,
  la forma natural al redactar dentro de un JSON) y las credenciales en URI.
  **La arista que este spec declaraba como límite quedó CERRADA** (2026-08-26,
  mejora traída del port `summonaikit-kimi`): un valor REAL pegado al marcador
  sin separador (`token=[REDACTED]sk-…`) ya NO se descuenta — el reemplazo
  exige un delimitador después del marcador —, así que ese secreto SÍ se
  detecta. La forma entrecomillada, que antes hacía BLOQUEAR un artefacto
  correctamente redactado, tampoco falla ya. El escaneo sigue siendo
  best-effort para lo que su familia de patrones no matchea.
  El delimitador es una **lista blanca** y se mantiene como tal. La primera
  versión omitía `;` y `)`, así que `token=[REDACTED];` y `token=[REDACTED])`
  —correctamente redactados— bloqueaban (Greptile P1, PR #75), que es la
  fricción que el rol no puede permitirse; se agregaron esos dos signos.
  **No se invierte**, aunque invertirla (`[^A-Za-z0-9_-]`, "cualquier signo
  cierra el valor") sea más corto de escribir: con la lista invertida
  `token=[REDACTED]!secreto` se descuenta y queda `token= !secreto`, donde el
  espacio corta el match y el secreto SALE (Greptile P1, PR #79). Esa permuta
  cambia un bloqueo falso —ruidoso pero visible— por una fuga silenciosa, y
  para un escaneo de secretos la dirección correcta es fallar hacia BLOQUEAR.
  El costo de que a la lista le falte un signo es fricción que alguien ve; el
  de que le sobre es un secreto que nadie ve. Criterio para agregar uno: que la
  redacción pueda producirlo **después** del valor (cierre de JSON, de comando,
  de prosa). No alcanza con que sea puntuación — `!`, `$`, `@`, `#` son
  prefijos perfectos de un secreto pegado y no cierran ningún valor.
  **COLA PEGADA TRAS UN DELIMITADOR — cerrada** (Greptile P1, PR #79). Un
  `token=[REDACTED],sk-real` tiene delimitador válido, así que la regla de una
  sola rama lo descontaba y la cola con el secreto sobrevivía. **Esto no lo
  trajeron `;` y `)`**: pasaba igual con `,`, `"` y `}` desde antes de la
  Phase 13. Medido sobre las tres versiones:

  Medido contra la versión original en 16 formas, la regla nueva es **mejor o
  igual en todas y peor en ninguna**:

  | entrada | original | tres ramas |
  |---|---|---|
  | `token=[REDACTED];` (correcto) | BLOQUEA | **PASA** |
  | `fn(password=[REDACTED])` (correcto) | BLOQUEA | **PASA** |
  | `token=[REDACTED],sk-real` | PASA | **BLOQUEA** |
  | `token=[REDACTED],!sk-real` | PASA | **BLOQUEA** |
  | `token=[REDACTED];sk-real` | BLOQUEA | BLOQUEA |
  | `token=[REDACTED];!sk-real` | BLOQUEA | BLOQUEA |
  | `token=[REDACTED];]sk-real` | BLOQUEA | BLOQUEA |
  | `token=[REDACTED]sk-real` | BLOQUEA | BLOQUEA |
  | `token=[REDACTED]","uri"…` (JSON) | PASA | PASA |
  | `token=[REDACTED] apareció en config` | PASA | PASA |
  | `token=[REDACTED],]sk-real` | PASA | PASA |

  El delimitador va en **tres ramas**, cada una con un conjunto y una exigencia
  distintos:

  - **(a)** espacio o fin de línea: descuenta siempre. Ahí el valor terminó, y
    exigirle algo más bloquearía la prosa normal.
  - **(b)** delimitadores de estructura (`] " [ , } >`): descuentan sólo si lo
    que sigue es otro carácter estructural o fin de línea. Así la forma JSON
    (`","`), que es la del camino real, se sigue descontando, y
    `token=[REDACTED],sk-real` no.
  - **(c)** `;` y `)`: descuentan sólo si después viene **espacio o fin de
    línea**.

  Por qué (c) es más estricta, que es el punto fino: `;` y `)` no estaban en la
  lista original, así que meterlos como delimitadores comunes **abre caminos que
  antes no existían para ellos**, y ningún guardia de **un** carácter alcanza —
  siempre hay un relleno que lo satisface. Medido: el guardia "no puede ser
  continuación de secreto" (`[^A-Za-z0-9_-]`) lo saltea `;!sk-real`; el guardia
  "estructural" lo saltea `;]sk-real`, porque `]` sí es estructural. Exigir
  espacio o fin de línea no se puede rellenar **por construcción**: cualquier
  carácter de relleno, por definición, no es espacio.

  **Límite que sigue abierto** (igual que antes — no es regresión): el relleno
  estructural tras un delimitador de (b), `token=[REDACTED],]sk-real`. Cerrarlo
  pide inspeccionar la cola entera con conciencia del formato, que es otra
  tarea: la forma JSON legítima también trae letras después del delimitador, así
  que ninguna regex de una pasada las distingue.

  Nota sobre lo que el bloqueo *original* hacía, porque explica por qué la lista
  corta no era la respuesta: cuando "bloqueaba" `token=[REDACTED];sk-real` no
  estaba detectando el secreto, sino matcheando `token=[`, el propio marcador.
  El escaneo está anclado a `keyword=valor` y a `://user@`, así que una cola
  suelta sin keyword delante le es invisible por diseño. La rama (b) sí la
  detecta, y por la vía correcta: dejando el marcador sin descontar.
  **Límite residual declarado — COMILLAS SIMPLES**: el valor entre comillas
  simples (`token='[REDACTED]'`) no se descuenta por ninguna regla —las dos
  piden `="` o `=[`— y por lo tanto un artefacto que use esa forma BLOQUEA
  aunque esté
  bien redactado. Es preexistente (tampoco se descontaba antes del PR #75) y se
  deja abierto a propósito: el contrato del rol exige artefactos JSON, y JSON
  no tiene strings con comilla simple, así que la forma no aparece en el camino
  real. Si algún día un perfil la produjera, se cierra con una tercera regla
  simétrica a la del entrecomillado, y con su mutación propia.
- El escaneo recorre el directorio con `find … | while read`, así que un
  artefacto cuyo NOMBRE contenga un salto de línea se parte en fragmentos y
  ninguno existe como archivo: ese artefacto no se escanea. Es evasión
  DELIBERADA — misma familia que el `touch -t` pre-época — y el escaneo
  persigue persistencia accidental (un evasor deliberado es trabajo del
  reviewer leyendo el artefacto). En Windows, el host de referencia, un nombre
  así ni se puede crear. Declarado tras el análisis del port
  (`summonaikit-kimi`, PR #13): endurecerlo sería `find -print0` acá y
  absorción por paridad allá; no se hace hasta que exista un caso real.
- `--quitar-zcode`/`--quitar-grok` IGNORAN `--dry-run` (escriben backup,
  config y borran perfiles igual): límite preexistente a la Phase 13,
  declarado acá — la promesa "dry-run no escribe" del README hoy solo está
  cumplida y testeada para los caminos de INSTALACIÓN (claude/kimi por
  12.9 #4, zcode por 13.9).
- El residual `#8` del spec (reparadores silenciosos) PERSISTE para
  verifier/reviewer: esta fase le puso un candado al rol NUEVO; los dos
  roles que ya existían conservan `Edit, Write` sin cambios.

## Atestación de verificación delegada (Phase 14)

**El problema.** En un host cuyo **canal interno es `unknown`** (zcode, medido
en el turno vivo 2026-08-25; kimi candidato declarado, ver abajo), los comandos
que corre un verifier **DELEGADO** no llegan al hook: `verified` queda en `0`, la
prosa honesta del lead no matchea runner ni skip, y el gate bloquea con
`Missing verification evidence`. El lead solo salía re-corriendo él mismo los
checks (pago doble). Diseño en
`docs/phase-14.1-atestacion-verificacion-delegada.md`.

**La vía nueva (contrato 14.1).** Una declaración en el recibo,
`VERIFIED BY SUBAGENT: <comandos y resultado>`, es una vía ADICIONAL de crédito
de verificación, en hosts con canal interno ciego. Acredita SOLO si se cumplen
las 5 condiciones:

1. **Prefijo literal** `VERIFIED BY SUBAGENT:` — subcadena libre sobre el texto
   del recibo, matcheada con `grep -Eiq` (case-INSENSITIVE, igual que `ROLE
   FALLBACK`, no `has_receipt_label`).
2. **Comando + resultado** con el predicado §4.3: la declaración nombra un
   **comando de verificación reconocido** (`SAIKIT_VERIFIED_CMD_RE` = unión del
   vocabulario de runners + `py_compile`/`compileall`/`dotnet build`/`bash -n`/
   `sh -n`/`node --check`/`git diff --check`) **y un resultado de ÉXITO**
   (`exit 0`, `N passed`, `ok`, `en verde`, `0 failed`, …). Un nombre genérico
   ("batería", "checks") NO cuenta. **El predicado corre sobre el SPAN del label**
   — el fragmento desde `VERIFIED BY SUBAGENT:` hasta el fin de ESA línea, como
   el diseño §4.3 (y no sobre el recibo entero). Esto cierra dos defectos: un
   `pytest` mencionado en otra línea o un `ok` suelto NO satisfacen el predicado
   (crédito por piezas dispersas), y un `TypeError:` en otra línea NO veta la
   atestación legítima (falso positivo del veto).
   **Con VARIOS labels en el recibo se juzgan TODOS los spans** (Greptile P1,
   PR #72): el veto corre sobre cada uno — un label con fallo declarado
   (`failed: 1`, `exit 1`, o **conteo cero** `0 passed`/`0 passing`/`0 tests
   passed`, `SAIKIT_VERIFIED_CERO_RE`: cero pruebas corridas no verifica, y el
   `[1-9]` de `SAIKIT_VERIFIED_RESULT_RE` no alcanza porque la rama `passed`
   pelada lo rematchea — CodeRabbit) descalifica el turno aunque otro label,
   antes o después, declare éxito ("cualquier fallo declarado veta", no "el
   último manda"); el crédito exige comando + resultado en la MISMA línea de
   algún span. La vía se juzga sobre el texto del turno ACTUAL
   (`last_assistant_message`), no sobre el tail del transcript: un label
   válido de un turno anterior no acredita el nuevo
   (`caso_g2_zcode_verif_label_de_turno_anterior_no_acredita`, mutación
   `verif_label_sobre_text_entero`). Antes se recortaba al primero (`head -n1`) y un éxito seguido de un
   fallo acreditaba. Casos: `caso_g2_zcode_verif_subagente_exito_luego_fallo_bloquea`
   (atrapa la mutación `verif_subagente_solo_primer_span`) y su espejo
   `…_fallo_luego_exito_bloquea` (fija la semántica; no discrimina esa mutación,
   declarado).
3. **Host con canal interno ciego** — evaluado sobre `$HOST` (JAMÁS `$TARGET`:
   en zcode el fallback 5.4 deja `TARGET=claude`). En este repo es `$HOST=zcode`.
   `kimi` es **candidato** con canal interno `unknown` declarado — el label ahí
   se prende SOLO si el port mide que el canal no entrega esos eventos; hasta
   esa medición queda `unknown`.
4. **Verifier despachado** — `verifier` en `agents_seen`.
5. **Solo cuando `verified != 1`** — la evidencia real ya observada no necesita
   el label.

**El veto de fallo.** Cualquier señal de fallo DESCALIFICA el label, aunque
también aparezca un "passed". El veto reusa las constantes del raíl del EVENTO —
`FAILURE_SIGNAL_RE_CI` y `FAILURE_SIGNAL_RE_CS` — en la forma EXACTA del hook
(dos greps, variables expandidas, la CS case-SENSITIVE) **MÁS una forma propia
del label** (el raíl de evento recibe el `exit` por otro canal y esas constantes
no cubren `exit 1`): `exit[[:space:]]+[1-9]`. **Responsabilidad del lead
(declarado):** el diseño original tenía `exit [1-9]`; al reusar las constantes se
perdió esa cobertura y se re-sumó como extra del label. NUNCA con comillas
simples (buscaría el literal del nombre y el veto jamás dispararía). Reusar esas
constantes garantiza por construcción que el label jamás sea MÁS LAXO que el
raíl del evento y hereda sus mejoras sin drift.

**Refinamiento sobre el pseudocódigo §3 del diseño (derivado del caso Greptile,
ver `Plans.md` 14.2).** Cuando el label `VERIFIED BY SUBAGENT:` está **presente en
un host de canal interno ciego (`$HOST=zcode`)**, la evidencia la juzga SOLO el
predicado §4.3 (con el veto de fallo) — **NO** se consulta el fallback de
prosa/runner. Sin esto, `VERIFIED BY SUBAGENT: pytest -q, 12 passed, failed: 1`
acreditaría por la vía laxa de prosa (A11), contraviniendo la promesa §4.3 de
"nunca más laxo que el raíl". Sin label (o en un host NO ciego), la evidencia se
juzga exactamente como antes — el label NO cambia el comportamiento de
claude/codex/grok (la condición de host ciego lo acota). El fallback de prosa
(que acredita fallos, A11) permanece para los recibos SIN label.

**Límites declarados (no se pretenden cerrar).** El label es texto del
asistente, subcadena sin anclar (mismo trade-off que `ROLE FALLBACK`/`DELEGATED`).
El hook no valida que el comando corrió de verdad (en el host ciego no puede);
lo audita el humano. kimi NO es host ciego medido — es candidato `unknown`
declarado (Core Rule 2); el port mide antes de prender el label. En un host con
canal observable, un comando no reconocido como runner (`py_compile`) sigue sin
acreditar por la vía normal (problema de vocabulario, fuera de alcance).
**Residual (Greptile r3 del PR #72, 2026-08-27, medido):** un `failed`/`error`
PELADO sin conteo (`VERIFIED BY SUBAGENT: pytest -q, ok, failed.`) no lo veta
ninguna constante — `FAILURE_SIGNAL_RE_CI` cubre `N failed` y `failed: N`,
`_CS` las formas de runner, y el veto propio del label `exit [1-9]` y el conteo
cero — así que ese label acredita. El raíl de EVENTO usa exactamente las mismas
constantes: el label queda A LA PAR del raíl (el invariante de esta sección), no
más laxo. Arreglo candidato, en PR propio con caso + mutación + regrabado: veto
propio del label para `fail(ed|ing|ure|s)?`/`error(s)?` pelados NO precedidos
de `0 ` (que es forma de éxito: `0 failed`).

## Non-Goals

- **No se actualiza al kit v5.** Verificado: mismos bugs, mismo contrato.
- **No se adoptan `.cursor`** en este alcance. `.codex` se reabre de forma
  explícita en Phase 6, Grok (`~/.grok`) entra como host distinto en Phase 7,
  y Phase 12 reabre la propiedad de los perfiles de agente en `.claude` y
  `.agents` (kimi) — ver *Ampliación de propiedad — Phase 12* arriba. Ninguna
  de esas ampliaciones autoriza a tocar `.cursor`, que sigue fuera.
- **No se persigue que el gate sea un control de seguridad.** Es advisory: aun
  corregidos A1 y A2, quien controla el texto del turno puede influirlo. Se
  documenta; no se promete lo contrario.
- **No se borra el código de los parches de quality-kit**, solo su target
  `.claude`: el resto de perfiles depende de ellos y de su cobertura de tests.
