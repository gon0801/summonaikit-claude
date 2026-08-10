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

## Data And Contracts

### Qué se hereda y qué se corrige

El archivo vivo (746 líneas) es la fuente inicial: el bash del vendor más dos
parches locales (`SAIKIT-SENTINEL-GATE v1`, `SAIKIT-REVIEW-NOTICE v1`). Al
adoptarlo, sus defectos pasan a ser responsabilidad propia. Los conocidos:

| # | Defecto | Efecto | Fase |
|---|---|---|---|
| A1 | `json_string_field` es greedy (`.*` inicial) y lee el payload CRUDO, que incluye `tool_response` | Cualquier `subagent_type` que aparezca como **clave JSON** fuera de `tool_input` registra el rol sin que corra ningún subagente; con varias ocurrencias gana la ÚLTIMA. **El efecto como estaba escrito acá —"un archivo del repo que contenga ese texto"— NO reproduce**: ver § Mediciones de la línea base | 3 |
| A2 | El recibo y la pausa se buscan en el tail del transcript entero | Un archivo con `SUMMONAIKIT HARNESS PAUSED`, o con las 6 etiquetas, deja pasar cualquier turno | 3 |
| A3 | `TEST_RUNNER_RE` sin fronteras de palabra | `cat pytest.log` cuenta como verificación (mismo hallazgo 6 ya corregido en el port de Kimi) | 3 |
| A4 | Estado llaveado por proyecto y sin revalidar el sentinel | Un turno `-saikit` abandonado sigue cobrando recibo a turnos que no lo pidieron (reproducido en vivo el 2026-08-08) | 3 |
| A5 | `command_text` crudo persiste en `harness-evidence.log` | Un comando con credenciales en la línea queda en claro en disco hasta el cierre limpio | 3 |
| A6 | `transcript_path` sale del payload y se hace `tail` sin acotar | Primitiva de lectura de archivo arbitrario controlada por payload | 3 |
| A7 | ACL: `CodexSandboxUsers` tiene `Modify` sobre el hook y su directorio de estado | Una identidad *aislada* puede reescribir el script que corre SIN sandbox en cada turno, o plantar `agents_seen` y anular el gate | 0 |
| A8 | `has_receipt_label` exige un carácter no alfabético antes de la etiqueta, y en un transcript real el que hay es la `n` del salto de línea escapado | Un recibo correcto escrito como texto corrido no satisface NINGUNA de las 6 etiquetas: el turno se bloquea hasta agotar el presupuesto. El mismo recibo en viñetas sí pasa | 3 (con A2: misma raíz, un solo arreglo) |
| A9 | La herramienta que invoca subagentes se llama **`Agent`**, y el matcher registrado nombra `Task`; los eventos de adentro del subagente sí llegan, pero llevan el rol en **`agent_type`** y el hook busca `subagent_type` | **El gate de secuencia no se puede satisfacer.** Los tres subagentes corren, el hook recibe sus eventos, y `agents_seen` queda vacío | 3 |
| A10 | El hook no ve `SUMMONAIKIT_HOOK_TARGET=claude` en la corrida real, pese a estar en el comando registrado. Mecanismo **`unknown`**: medido el efecto, no la causa | La rama exclusiva de Claude (toda la exigencia de secuencia) no corre nunca. Enmascara a A9: por eso hoy los turnos cierran limpios en vez de bloquear | 3 |
| A11 | El guardia de fallas busca `exitCode` en el payload, y el `tool_response` real de `Bash` **no tiene ese campo** (medido 59 de 59) | Una batería que falla se acredita como verificación, salvo que su salida diga literalmente `command not found`, `permission_denied` o `failure_type` | 3 |

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

**Orden de corrección, que importa:** A10 enmascara a A9. Arreglar A9 solo no
cambia nada mientras el `TARGET` no llegue; arreglar A10 solo hace que *todos*
los turnos empiecen a bloquear, porque A9 sigue vaciando `agents_seen`. Van
juntos o el gate pasa de inerte a inservible.

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

## Non-Goals

- **No se actualiza al kit v5.** Verificado: mismos bugs, mismo contrato.
- **No se adoptan los otros 3 perfiles** en este alcance. `.codex` es una
  variante distinta con parches de otro origen. La divergencia queda declarada.
- **No se persigue que el gate sea un control de seguridad.** Es advisory: aun
  corregidos A1 y A2, quien controla el texto del turno puede influirlo. Se
  documenta; no se promete lo contrario.
- **No se borra el código de los parches de quality-kit**, solo su target
  `.claude`: el resto de perfiles depende de ellos y de su cobertura de tests.
