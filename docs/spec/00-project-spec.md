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

### Convivencia con quality-kit

`saikit-gate-heal.ps1` aplica los dos parches a 4 perfiles (`.claude`, `.codex`,
`.cursor`, `.agents`). Dos escritores en `SessionStart` sobre la misma ruta con
modelos distintos (parche-por-ancla vs reemplazo) pueden producir un archivo
doblemente parcheado o truncado.

La costura es **por host**: quality-kit saltea cualquier archivo que lleve el
marcador de propiedad. Un condicional. `.codex`/`.cursor`/`.agents` no cambian.
Ese cambio se mergea ANTES de instalar lo nuestro.

## Non-Goals

- **No se actualiza al kit v5.** Verificado: mismos bugs, mismo contrato.
- **No se adoptan los otros 3 perfiles** en este alcance. `.codex` es una
  variante distinta con parches de otro origen. La divergencia queda declarada.
- **No se persigue que el gate sea un control de seguridad.** Es advisory: aun
  corregidos A1 y A2, quien controla el texto del turno puede influirlo. Se
  documenta; no se promete lo contrario.
- **No se borra el código de los parches de quality-kit**, solo su target
  `.claude`: el resto de perfiles depende de ellos y de su cobertura de tests.
