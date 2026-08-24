# Phase 13 — Diseño del cuarto rol: el adversario

Fecha: 2026-08-24. Autor: Task 13.1 (lead + medición de repo).

Diseño aprobado. El ledger de tareas sale de acá y vive en `Plans.md`; el delta
de producto que esta fase aprueba se incorpora a `docs/spec/00-project-spec.md`
al cierre (13.9), no antes. Cada decisión de este documento cita su evidencia
(payload, línea de hook, o doc de medición con fecha y task); lo que no se
pudo observar queda `unknown` declarado con la razón — jamás rellenado por
analogía (Core Rule 2: `not_observed != absent`).

Ubicación del archivo: `docs/` plano, como el resto de los diseños de este repo
(`phase-6-codex-design.md`, `phase-7-grok-design.md`,
`phase-12-model-routing-design.md`). El borrador externo del operador queda
conservado SIN editar en `docs/phase-13-adversary-borrador.md`; este diseño lo
corrige donde promete infraestructura que no existe (ver § Divergencias con el
borrador).

## Purpose

Agregar un cuarto rol a la ceremonia — `adversary`, un abogado del diablo que
corre DESPUÉS del verifier y ANTES del reviewer, ataca el cambio (entradas no
manejadas, datos preexistentes, tests que no discriminan, blast radius, falla
parcial, trust boundary) y SOLO reporta: no repara.

La lente que ningún rol cubre hoy es la del poder discriminante: "¿este test
pasaría igual si borro la función bajo test?" El verifier corre la suite
(verde = PASS) y el reviewer no audita poder discriminante — es la debilidad
común medida de todos los implementadores delegados (`docs/phase-13-adversary-plan.md:21-27`).
El rol es **opt-in**: el costo medido de ceremonia inflada (la lección de las
4 h/task) prohíbe hacerlo obligatorio por default; un turno sin adversary
cierra exactamente como hoy.

"Reporta, no repara" mitiga PARCIALMENTE el residual `#8` del spec (reparadores
silenciosos): evita agregar otro, pero verifier/reviewer conservan `Edit, Write`
y `#8` queda abierto para ellos. 13.9 lo deja escrito así, sin sobreventa.

## Premisas medidas (2026-08-24, no supuestas)

Estas mediciones son la base del diseño. Si alguna cae, la fase se re-planifica.

### El mapa de fases por host: no existe canal de negación en ningún host

Mapa por host (no un composite), del plan y del verificador de registro:

- **claude** registra `UserPromptSubmit|PostToolUse|Stop` — exactamente las
  fases que `tools/check-hook-registration.sh:189` declara en `ESPERADAS`.
- **zcode** agrega `SessionStart`.
- **grok** agrega `SubagentStart` y `PostToolUseFailure`.
- **NINGÚN host registra `PreToolUse`** (`docs/phase-13-adversary-plan.md:54-60`;
  el hook no tiene una sola rama que lo nombre — verificado por grep sobre
  `hooks/summonaikit-harness.sh`, 0 ocurrencias).

`PostToolUse` dispara DESPUÉS de la escritura. Conclusión medida: **no existe
canal de NEGACIÓN previa en ningún host**. Todo candado de escritura que esta
fase prometa tiene que ser detección post-hoc o ser una promesa falsa — el
vicio exacto que el plan le criticó al borrador.

### Canales de atribución de rol por host

La pregunta (a) de 13.1: ¿qué canal permite saber que un Edit/Write/Bash vino
del adversary? Los canales son los mismos que el hook ya lee hoy
(`hooks/summonaikit-harness.sh:1461-1481`), y su estado de medición por host:

| Host | Despacho (identidad) | Eventos internos del hijo (identidad) | Negación previa |
|---|---|---|---|
| `claude` | **medido** — `Task` con `tool_input.subagent_type` (Task 1.4; lector en el hook `:1461`) | **medido** — `agent_type`/`agent_id` de PRIMER NIVEL en PostToolUse internos (Tasks 1.4 y 3.7; fixture `tests/fixtures/escenarios/16-eventos-dentro-de-subagente/02.tool.claude.json`: payload real con `agent_type: "implementer"` top-level en un PostToolUse de `Edit`; lector `:1481`) | NO (sin `PreToolUse`) |
| `grok` | **medido** — `toolInput.subagent_type` en el despacho `spawn_subagent` (7.1 ronda 5, `docs/phase-7-grok-design.md:41`; lector `:1467`) | **medido** — `subagentType` top-level en los eventos internos (7.1; `docs/phase-7-grok-design.md:41`; lectores `:1468-1469`) | NO |
| `codex` | **sin identidad** — el despacho NO emite `subagent_type` (Task 7.3 D4, comentario del hook `:1462-1465`: "el despacho spawn_subagent SI emite post_tool_use con toolInput.subagent_type (a diferencia de Codex)") | **medido** — `agent_type` de primer nivel, forma idéntica a claude (Task 6.1; comentario Task 6.4 D3, `hooks/summonaikit-harness.sh:1995-1999`) | NO |
| `zcode` | **medido** — `Agent` con `tool_input.subagent_type` (Task 5.5; fixture `tests/fixtures/escenarios/21-zcode-turno-completo/02.tool.zcode.json`: `tool_name: "Agent"` con `tool_input.subagent_type: "implementer"` — ÉSTE es el citable; corroboración adicional, NO citable como artefacto (re-etiquetada así por
claude #10): la sesión que escribió este doc observó sus tres despachos de
ceremonia acreditados en orden en su propio `harness-state.env` vivo,
archivo efímero que el cierre limpio borra y que por eso no se lista como
evidencia) | **unknown** — no existe captura de un evento interno zcode. La golden zcode modela el turno sólo con eventos de despacho (escenario 21: tres `Agent` + un `Bash` del lead — `02`/`04`/`05` Agent, `03` Bash — sin eventos internos). El log de evidencia vivo no registra identidad por evento, así que tampoco distingue ediciones del lead de las del subagente. No se asume | NO |
| `kimi` | **resolución de tipo medida; identidad en el payload unknown** — la sonda 12.7 probó que kimi resuelve el `subagent_type` del perfil y lo despacha (`docs/spec/00-project-spec.md:1590-1599`, PROBE-127-OK), y la tabla de `docs/phase-12-model-routing-design.md:38-42` documenta que registra `Agent` + `SubagentStart`/`SubagentStop`; pero NINGUNA captura de hook-payload kimi existe en el repo para afirmar el CAMPO de identidad — unknown, no se asume | **unknown** — 12.3 midió `wire.jsonl` de binding de modelo (`docs/task-12.3-medicion.md:36`), no payloads de hook. No se asume | NO |

Nota de disciplina sobre zcode: el `tool_response` del despacho en el fixture
21 trae `agentType` anidado — pero `tool_response` es el RESULTADO de la
herramienta, que el turno no escribió, y el hook deliberadamente no lo lee
(disciplina A1, `hooks/summonaikit-harness.sh:1457-1460`). Un valor anidado en
resultado no es un canal de atribución: confirmaría que el hijo existió, no
quién escribió cada evento posterior.

Conclusión de la tabla: la atribución INTERNA (la que el candado necesita para
saber que una escritura vino del adversary) está medida en 3 de 5 hosts
(claude, grok, codex). En zcode y kimi el candado queda declarado ciego —
fail-open con diagnóstico, ver D3.

**Nota sobre las citas de línea (cross-review, claude #11):** las ~40 citas
`hooks/summonaikit-harness.sh:NNNN` de este doc corresponden al hook en
`cbfb6c9` (2026-08-24). 13.4/13.5 editarán el hook y las desfasarán — son
fotografías de la fecha, no anclas vivas; 13.9 re-verifica las que copie al
spec.

### La sesión no se propaga: el único canal pre-despacho que el modelo lee

Ningún host expone el `session_id` al lead — el modelo que despacha al
adversary. El `session_id` viaja en cada payload (`hooks/summonaikit-harness.sh:331,347`,
medido Task 1.4), pero los payloads los lee el hook, no el modelo.

El único canal pre-despacho que llega al modelo es la salida del armado UPS.
Medido 7.2 (Task 7.4, comentario y código en `hooks/summonaikit-harness.sh:1645-1657`):
en grok `additionalContext` es IGNORADO en las 4 formas medidas; el único canal
que llega al modelo en grok es el `reason` del Stop bloqueado — es decir,
DESPUÉS de que el adversary corrió. Propagar un `session_id` pre-despacho
exigiría tocar el contrato del armado en claude/zcode y sería igualmente
imposible en grok. Ésa es la razón por la que D2 es keyless.

### El hook hoy escribe sólo bajo su propio state dir

Todo efecto de escritura persistente del hook vive bajo
`hooks/summonaikit-harness.sh:341-346` — `STATE_ROOT="$HOOK_DIR/state"` y
debajo. El hook NO escribe hoy en el working tree del repo consumer. D2
(agrega un gitignore en el consumer) es una clase de efecto NUEVA y se declara
como tal.

### El gate hoy: precedencia de keywords, dedupe, escotillas

- `canonical_agent_role()` (`hooks/summonaikit-harness.sh:1389-1402`) mapea por
  caso exacto + keyword con frontera `(^|[^a-z])`, precedencia
  reviewer > verifier > implementer. No tiene caso `adversary` y "adversary"
  no matchea ningún keyword — sin D6, D4 es código muerto.
- Trampa medida (cross-review del plan): `adversarial-audit` hoy resuelve a
  **reviewer** por el keyword `audit` (`hooks/summonaikit-harness.sh:1398`) —
  un nombre adversario acreditaría el slot de review sin review real.
- `record_agent` acredita al DESPACHO y el dedupe conserva el orden de primera
  aparición (`hooks/summonaikit-harness.sh:1420-1423`).
- La escotilla `DELEGATED` sólo perdona `awaiting
  (implementer|verifier|reviewer)` (`hooks/summonaikit-harness.sh:1881`).
- La escotilla `ROLE FALLBACK` acepta `IMPLEMENTER|VERIFIER|REVIEWER` por
  subcadena sin anclar, con el límite declarado en el propio comentario
  (`hooks/summonaikit-harness.sh:2007-2029`).
- El orden exigido hoy es `implementer.*verifier.*reviewer`
  (`hooks/summonaikit-harness.sh:2030-2034`) y sólo corre con lane != fast
  (`:1989-1994`).

### El router de la Phase 12 ya tiene el tier que este rol necesita

`tools/model-routing.sh` mapea `reviewer → review` (`:77`, bloque
`rol_a_tier` `:73-78`); en ese tier claude usa `claude-opus-5`/`xhigh`
(`:140`) y grok `grok-4.6`/`xhigh` (`:177`). La fila zcode está vacía a
propósito (catálogo no observado, 12.1) y la fila kimi está vacía de forma
definitiva (sellado 12.3, `docs/task-12.3-medicion.md`). Los IDs de modelo
viven sólo en el router.

## Decisiones

### D1 — Disparador opt-in, mismo criterio que el cross-review

El contrato de armado instruye al lead a delegar `adversary` cuando el cambio
toca auth, pagos, migraciones/datos preexistentes, o el hook mismo — el mismo
criterio que hoy dispara el cross-review (`docs/phase-13-adversary-plan.md:71-74`).
Sin invocación, cero costo nuevo: ningún host, ningún gate, ningún perfil
cambia de comportamiento. **Alcance exacto del "cero costo" (hallazgo A1 del
review):** todos los mecanismos nuevos de esta fase (escaneo de secretos,
violaciones, gitignore) disparan SOLO en sesiones cuyo estado registra
`,adversary,` en `agents_seen` — esto es, un despacho o evento interno
acreditado por cualquiera de los canales MEDIDOS de la tabla de premisas —
o una violación/artefacto ya registrado por el candado. El estado es
llaveado por sesión (`hooks/summonaikit-harness.sh:328-333` y
`:361-362`: `SESSION_KEY` → `STATE_DIR`), así
que una sesión que no lo invocó no escanea ni bloquea nada, aunque el repo
tenga artefactos de sesiones anteriores. **Límite de host declarado
(cross-review, claude #2; dirección corregida por kimi r2 #1):** en kimi
ningún canal MEDIDO acredita al adversary — se PROYECTA que ni la capa 2
ni el gitignore corren ahí, pero es proyección sobre unknown, no ausencia
afirmada (Core Rule 2 aplicada pareja): si un canal no medido existiera y
llegara, los mecanismos correrían DE MÁS (más enforcement, no menos —
dirección fail-safe), el riesgo #4 quedaría cubierto por más capas, y el
gate D4 pasaría a exigir la línea `ADVERSARY:`. En codex el despacho no
emite identidad pero el interno sí (`agent_type`, medido 6.1), así que
`agents_seen` sí se puebla.

Volverlo obligatorio queda como perilla explícita del operador, no como
default (decisión del operador 2026-08-24, `docs/phase-13-adversary-plan.md:29-32`).
El case negativo que fija esta decisión es parte de 13.6: un turno sin
adversary cierra igual que hoy (anti-regresión del costo).

**Límite heredado declarado:** adversary invocado pero no observado (nombre
sin mapear, host sin canal de atribución interna) es indistinguible de no
invocado — el turno cierra limpio sin línea `ADVERSARY:`. Va al spec como
límite; no se promete detectarlo (`docs/phase-13-adversary-plan.md`, task 13.6).

**Lane fast:** el lane fast se salta la ceremonia de subagentes entera
(`hooks/summonaikit-harness.sh:1989-1994`) — el gate NO EXIGE despachar
adversary (como no exige los otros tres). No se añade excepción. Pero si un
turno fast IGUAL despachó un adversary (posible: `record_agent` corre en
cualquier lane), la línea `ADVERSARY:` del recibo sigue las mismas reglas que
las demás labels — exigida cuando `,adversary,` ∈ `agents_seen`, lane-independiente
(los otros labels del recibo ya se exigen en fast; éste no es una excepción).
Caso con nombre para 13.5: "fast con adversary visto exige la línea". 13.9 lo
deja escrito en el spec.

### D2 — Artefacto de hallazgos dir-scoped keyless (diverge del borrador)

**Forma.** El adversary puede escribir SOLO bajo el directorio
`.saikit/findings/` del repo consumer — un prefijo de DIRECTORIO, no un nombre
de archivo. Convención de nombre sugerida al perfil (13.2):
`adversary-<timestamp-UTC>.json` (el subagente tiene `Bash`, puede fechar).
El candado (13.4) valida el prefijo de directorio con canonicalización; el
nombre del archivo queda fuera de lo que el gate exige.

**Por qué keyless.** El borrador propone `.saikit/findings/<session_id>.json`.
Medido (§ premisas): ningún canal uniforme propaga el `session_id` al
subagente — el único canal pre-despacho que llega al modelo es la salida del
armado, tocar su contrato sería una modificación de contrato por task de la
fase (13.6 ya diverge 42/44 por menos, precedente 11.1) y en grok es
directamente imposible (`additionalContext` ignorado, 7.2). Un candado cuya
ruta permitida dependa de un id que el escritor no puede conocer no cierra
nada: o el adversary escribe fuera de su única ruta permitida, o el candado se
abre a nombres adivinados. Keyless cierra el prefijo real que se puede hacer
cumplir.

La disciplina de saneo de `SESSION_KEY` (`regex [^A-Za-z0-9_-] → _` MÁS el
truncado `cut -c1-64`, `hooks/summonaikit-harness.sh:361`, con su comentario
de razón `:335-340`) sigue siendo OBLIGATORIA para cualquier id que entre en
una ruta en este repo — pero el artefacto keyless no construye rutas desde
ids, así que esa clase de riesgo no aplica a la convención en sí.

**Adjudicación.** El canal primario es el LEAD: cuando despachó adversary en
el turno, su despacho del reviewer NOMBRA el artefacto a adjudicar (el lead lo
conoce — es quien recibió del adversary la línea de resumen y quien puede
listar el directorio). Eso cierra el staleness SECUENCIAL (hallazgo M2 del
review + codex #2): sin nombre explícito, un reviewer de un turno SIN
adversary adjudicaría el artefacto viejo de otra task contra el cambio
nuevo — contradiciendo la promesa de comportamiento intacto sin invocación
(D1). **Regla que lo cierra (fija, para 13.3/13.6): un turno que NO corrió
adversary NO adjudica NADA** — no hay sección de adjudicación sin adversary
en el turno, y el fallback de abajo jamás se alcanza desde un turno sin
invocación. Forma degradada (el lead SÍ corrió adversary pero no nombró el
archivo): el reviewer adjudica el `*.json` de MAYOR mtime del directorio
(mtime, no el timestamp del nombre — divergen justo en la re-escritura
TOCTOU, que cambia mtime y no el nombre; B3 del review), y lo declara así
en su veredicto. Ambigüedad de sesiones CONCURRENTES declarada
como límite — misma familia declarada que la colisión del saneo de
`SESSION_KEY` (dos ids que sanean al mismo nombre): se declara, no se promete
unicidad (`docs/phase-13-adversary-plan.md:80-82`). El contrato de 13.6 fija
la forma del despacho que nombra el artefacto y la instrucción negativa
("si este turno no corrió adversary, no adjudiques artefacto alguno").

**Integridad post-adjudicación (TOCTOU): límite DECLARADO, sin sellado.**
Razón: no hay canal de negación (§ premisas), así que append-only o sellado no
son exigibles — el adversary con `Bash` siempre puede reescribir el archivo.
El ancla de la adjudicación es el TEXTO de veredictos del reviewer (vive en el
transcript, no en el artefacto), no el JSON; y la línea `ADVERSARY:` del
recibo es label-only (el gate NUNCA valida N contra el JSON — D4, coherente
con la familia G4: el gate juzga labels de texto, no artefactos). Una
re-corrida del adversary DESPUÉS de la adjudicación puede reescribir el JSON
conservando un orden de `agents_seen` válido — caso con nombre en 13.5
("adversary dos veces"), atado a su caso.

**Redacción de secretos/PII — tres capas (riesgo #4 del plan).**

1. **Regla en el perfil (13.2):** ningún secreto/PII va al artefacto; la
   evidencia se redacta ANTES de escribirse. Referencia de disciplina:
   `redact_secrets` del hook (`hooks/summonaikit-harness.sh:1343-1347`) —
   tokens/passwords entrecomillados o no, y credenciales en URI.
2. **Escaneo en el Stop (13.4):** disparo acotado a la sesión (hallazgo A1
   del review): SOLO cuando el estado de ESTA sesión registra `,adversary,`
   en `agents_seen` — una sesión que no lo invocó jamás escanea, aunque el
   repo tenga artefactos acumulados. **Alcance acotado a los artefactos de
   ESTA sesión (Greptile P1 del PR #63 — cierra el "escaneo mezcla
   sesiones"):** se escanea (a) cada ruta bajo `.saikit/findings/` que el
   candado REGISTRÓ como escrita por el adversary de esta sesión (el hook
   ya procesa esos PostToolUse para el candado; las escrituras permitidas
   bajo el dir se anotan en el estado de la sesión), más (b) cualquier
   archivo del directorio cuyo mtime sea POSTERIOR al armado de la sesión
   (época guardada en el estado al armar) — eso cubre al artefacto escrito
   por `Bash` del adversary, que el candado no ve como Edit/Write. Un
   artefacto HISTÓRICO de otra task ya no bloquea este turno: el problema
   de persistencia cross-sesión queda reducido a los artefactos de esta
   sesión (y a los frescos de una sesión CONCURRENTE — mtime posterior al
   armado —, que es la ambigüedad concurrente ya declarada, en dirección
   fail-safe: escanea de más, no de menos). CUALQUIER extensión
   (cross-review codex #1 / claude #1, la alta convergente: el candado de
   ruta permite cualquier archivo del directorio — filtrar el escaneo a
   `*.json` dejaba un `leak.txt` pasar el candado y evadir el control). La
   familia de patrones es la que el hook YA lleva inline (`redact_secrets`,
   `hooks/summonaikit-harness.sh:1343-1347`) — cross-review claude #3: el
   hook corre en el repo CONSUMER, donde `tools/check-secrets.sh` NO existe;
   los formatos extendidos de token de ese checker no están disponibles en
   runtime y NO se duplican al hook (una segunda copia sin candado de
   fuente única es drift garantizado). Capa reducida, declarada. Match ⇒
   **bloqueo (fail-closed JUSTIFICADO por riesgo** — secreto persistido en
   el working tree; excepción declarada a Core Rule 1, misma disciplina que
   el instalador, `docs/spec/00-project-spec.md:449`). Archivo ilegible ⇒ no
   bloquea (fail-open, Core Rule 1). **Ruta de fuga del FALSO POSITIVO
   (declarada, A1):** el bloqueo nombra archivo y NÚMERO de línea, jamás el
   contenido (misma disciplina de `tools/check-secrets.sh:24-25`); el
   remedio es manual y declarado — redactar o borrar el artefacto y
   re-cerrar (2 ciclos + presupuesto si no se atiende, camino existente).
   **Persistencia residual ACOTADA (cross-review claude #7 / codex #3 +
   Greptile P1):** sin auto-borrado, un match en un artefacto de ESTA
   sesión bloquea los siguientes Stops de ESTA sesión hasta redactarlo o
   borrarlo; los artefactos de sesiones ANTERIORES ya no bloquean (alcance
   por sesión, arriba). Declarado, no prometido auto-limitado.
3. **Gitignore del consumer** (abajo).

**Residual declarado (en ambos sentidos, hallazgo A1 del review):** falso
NEGATIVO — PII/secreto que la familia de regexes no matchee (el escaneo es
best-effort, no un scanner de secretos, misma familia declarada que el propio
`redact_secrets` `:1331-1334`); y falso POSITIVO — evidencia de repro que
matchea un patrón de token sin serlo (p.ej. un `token=abc` de un test de
auth): el bloqueo es fail-closed por diseño, con la ruta de fuga manual
declarada en la capa 2 (archivo:línea, redactar/borrar, re-cerrar).

**Gitignore del consumer — dueño: el HOOK.** Disparador (corregido por el
hallazgo M1 del review): el PRIMER evento que resuelva a adversary por
CUALQUIER canal medido — despacho (`tool_input.subagent_type`) O interno
(`agent_type`/`subagentType` top-level). Anclarlo sólo al despacho dejaba a
codex sin gitignore para siempre (su despacho no emite identidad,
§ premisas); su canal interno sí trae `agent_type` medido, así que el
disparador any-channel lo cubre. En kimi ambos canales son unknown ⇒
proyección declarada (kimi r2 #1): se espera que ni el gitignore ni la
capa 2 corran ahí hasta que un canal se mida — pero si un canal no medido
llegara, correrían de más (dirección fail-safe), no de menos.
Al disparar, el hook crea si ausente `.saikit/` + `.saikit/findings/` +
`.saikit/findings/.gitignore` con contenido `*` (cross-review claude #6 /
codex #4: DENTRO de `findings/` — un `*` en `.saikit/` raíz ignoraría el
namespace entero, no sólo los hallazgos).

Esto es una **clase de efecto NUEVA para el hook**: hoy sólo escribe bajo su
propio state dir (`hooks/summonaikit-harness.sh:341-346`). Se declara como tal,
con la razón: la alternativa es evidencia de repro de ataques (output real de
comandos) asomando en el `git status` del consumer, a un `git add -A` de ser
commiteada — el modo de falla exacto del riesgo #4 del plan. Límites del
mecanismo declarados: `*` no afecta archivos ya trackeados (git sólo ignora
untracked) y `git add -f` lo pisa. Idempotente: crea si ausente, jamás
reescribe un gitignore existente (mismo criterio conservador que la máquina de
tres estados del instalador: lo no reconocido no se toca) — **lo que incluye
el gitignore AJENO ya presente (codex #4): si un `.saikit/findings/.gitignore`
preexistente ajeno no cubre los artefactos, quedan expuestos; el hook jamás
edita archivos ajenos, límite declarado**. **Ventana de exposición por host
(corregida, cross-review claude #5 — B2 estaba subestimada):** el PostToolUse
del despacho llega al RETORNAR la herramienta, o sea al TERMINAR la corrida
del subagente. En claude/grok/codex el disparador any-channel se enciende
antes, con el primer evento INTERNO del adversary (a mitad de corrida); en
zcode, donde sólo el despacho está medido, el gitignore llega recién al FINAL
— el artefacto asoma en el `git status` durante la corrida ENTERA en ese
host. Declarado por host, no prometido angosto.

**Ciclo de vida: sin auto-borrado.** Destruir evidencia post-adjudicación
sería el hook borrando registros de lo que encontró el rol que existe para
encontrar. La acumulación se declara como costo trivial (JSON chico,
gitignored). El operador puede limpiar el directorio a mano cuando quiera.

### D3 — Candado en modo degradado: detección post-hoc + bloqueo en el Stop

**Rama condicional de 13.1, resuelta: MODO DEGRADADO. NO se aborta 13.4.**

La rama venía del plan: "si 13.1 no encuentra canal de negación viable, el
candado degrada a detección post-hoc + bloqueo en el Stop, y eso se declara"
(`docs/phase-13-adversary-plan.md:57-60`). La medición confirmó que no hay canal
de negación en NINGÚN host (§ premisas) — pero también que la atribución
interna está medida en 3 de 5 hosts. El canal de DETECCIÓN existe aunque el de
negación no: abortar 13.4 tiraría un canal de detección real y dejaría el rol
sin ningún candado. Se construye el modo degradado; el enforcement que el
perfil de 13.2 describe es ÉSTE, no un PreToolUse prometido.

**Qué detecta (13.4 construye esto; hoy NO existe):**

- **Edit/Write:** en cada PostToolUse con identidad atribuible al adversary
  (top-level `agent_type` en claude/codex, `subagentType` en grok — § tabla de
  premisas) cuyo `file_path` canonicalizado cae FUERA de `.saikit/findings/`
  ⇒ se registra la violación. Canonicalización obligatoria: traversal `../`,
  ruta absoluta, symlink (el spec ya midió esa familia en A6). **Ancla de la
  comparación (cross-review claude #4):** el prefijo permitido se ancla al
  `PROJECT_ROOT` que el hook YA resuelve para su propio state
  (`hooks/summonaikit-harness.sh:325-346`) — no al cwd del proceso, que un
  `cd` del turno puede mover; un `file_path` relativo se resuelve contra
  esa raíz. Si el host entrega un cwd distinto de la raíz real del repo
  (familia A6), la familia de normalización existente es la que decide;
  declarado, no git (el hook no llama git para esto). **Symlink del propio
  directorio (cross-review claude #9):** si `.saikit/findings/` ES un
  symlink (plantable por el hueco de `Bash` ya declarado), canonicalizar
  ambos lados con realpath hace pasar todo — 13.4 RECHAZA un `findings/`
  que sea symlink (la comparación se hace sobre el prefijo SIN resolver el
  directorio, o el symlink se trata como violación de setup, no como ruta
  permitida). En el Stop, la
  violación produce una entrada **unsatisfiable-by-label**: ningún label del
  recibo la perdona. Bloquea los 2 ciclos; luego el camino de presupuesto
  agotado existente informa al usuario. **SIN git en el Stop** — no se agrega
  maquinaria de desbloqueo. **Remedio del operador (nombrado por qwen r2
  #4, simetría con la ruta de fuga del secreto):** inspeccionar y revertir
  la escritura no autorizada (p.ej. `git restore <archivo>` o borrar el
  archivo creado) y re-cerrar o informar; el bloqueo NO verifica la
  reversión (eso sería git en el Stop) — el remedio es manual, declarado.
- **Domicilio del flag de violación (hallazgo M3 del review):** la violación
  vive en el estado de la sesión que la registró, y 13.4 DEBE hacerlo en un
  archivo que los caminos de limpieza EXISTENTES ya borran — extender
  `harness-state.env`/`write_state` (firma actual de 6 campos,
  `hooks/summonaikit-harness.sh:1365-1368`) o la lista cerrada del A4-c4
  (`:2105-2113`, que hoy borra tres archivos y hace `rmdir` del dir). Un
  archivo NUEVO bajo `$STATE_DIR` que ninguna limpieza conoce resurrecta la
  violación como fantasma en el próximo armado: prohibido por diseño, no
  sólo desaconsejado.
- **Orden de evaluación en el Stop (hallazgo A2 del review):** los chequeos
  de violación y de secreto corren ANTES de las escotillas tempranas
  PAUSED/DELEGATED (hook `:1844` y `:1881`, ambas `emit_allow` sin señal).
  Sin esto, un lead cuyo adversary escribió fuera del dir cierra el turno
  con una frase de PAUSED — cero ciclos, cero señal — y la única entrada
  fail-closed del diseño queda eludida por una escotilla que se escribió para
  otro propósito. Las escotillas quedan intactas en todo lo demás.
- **Bash:** heurística best-effort sobre redirección/heredoc/tee OBVIOS en
  comandos atribuidos al adversary. Misma familia declarada que la guardia G2
  de detección de runners (el spec ya midió lo traicionero del parseo de texto
  de comandos: comillas, runners encadenados, formas que no cuentan — límites
  al spec, no parser de shell completo: Reject del plan). Los huecos van al
  spec como límites.

**Postura de falla:**

- **Default fail-open** (Core Rule 1, `docs/spec/00-project-spec.md:46`):
  canal de detección ausente (zcode/kimi internos unknown) ⇒ candado ciego
  DECLARADO, sin bloqueos por atribución en esos hosts; fallo de
  infraestructura de detección (payload ilegible, state no escribible) ⇒
  fail-open + diagnóstico por stderr/log.
- **Fail-closed por excepción JUSTIFICADA por riesgo** (misma disciplina que
  el instalador, `docs/spec/00-project-spec.md:449` — la única excepción
  declarada a Core Rule 1 hasta hoy):
  1. **Violación detectada** — escritura atribuible al adversary fuera de
     `.saikit/findings/` (entrada unsatisfiable-by-label, arriba): defecto
     PROBADO por el propio evento que lo reporta.
  2. **Secreto matcheado en el artefacto** por el escaneo de D2 capa 2 —
     aquí el "probado" NO aplica al match individual (un regex tiene falsos
     positivos, claude #8): la excepción se justifica por RIESGO ALTO con
     ruta de fuga manual declarada (secreto persistido en el working tree a
     un commit de distancia), no por certeza.

  La primera cierra sobre un defecto probado; la segunda sobre riesgo alto
  con escape. Ninguna bloquea desde inferencia de no-observación — la
  distinción que Core Rule 2 exige antes de bloquear.
### D4 — Gate condicional: orden con adversary + línea de recibo label-only

Si `,adversary,` ∈ `agents_seen` ⇒ el orden exigido pasa a
`implementer.*verifier.*adversary.*reviewer` (adversary DESPUÉS de verifier y
ANTES de reviewer). Si no ⇒ gate actual intacto.

**Nota de diseño para 13.5:** la regex ACTUAL
`implementer.*verifier.*reviewer` (`hooks/summonaikit-harness.sh:2031`) ya
matchearía con adversary en el medio — un `agents_seen` =
`implementer,verifier,adversary,reviewer` pasa el orden de hoy. La nueva regex
es la que exige la POSICIÓN del adversary: rechaza adversary-antes-de-verifier
y adversary-después-de-reviewer. El caso "adversary sin verifier previo"
bloquea por dos vías según la forma: sin verifier en `agents_seen` (la rama
missing-verifier existente, `:2022-2025`) o con verifier tardío (la nueva
regex de orden).

**Línea de recibo:** `ADVERSARY: N hallazgos, severidad máxima X`. Cuando
`,adversary,` ∈ `agents_seen`, el recibo debe llevar la línea — presencia
exigida por el gate como las demás labels (familia G4); el CONTENIDO es
**label-only**: el gate NUNCA valida N contra el JSON del artefacto, límite
declarado (un gate que validara N tendría que parsear el artefacto en el Stop
y confiar en un archivo que otro modelo reescribió — TOCTOU de D2). Si el
adversary fue despachado pero cayó sin reportar, `ROLE FALLBACK: ADVERSARY`
sustituye la línea (D6) — es el desenlace del caso "el gate exigiendo una
línea que no existe" que el plan previó (`docs/phase-13-adversary-plan.md:113-116`).

**Sin adversary en `agents_seen`: comportamiento byte-idéntico** — regex de
orden, mensajes y recibo exactamente los actuales. Ésta es una condición del
DoD de 13.5, no una intención.

### D5 — Ruteo: tier `review`, sin tier propio

**adversary → tier `review`** (el de reviewer). Razones:

1. Atacar es trabajo de razonamiento adversarial + lectura de código, no
   throughput de comandos como verify — el perfil del tier review.
2. La fila ya existe y está medida: `tools/model-routing.sh:73-78` mapea
   `reviewer → review`; claude usa `claude-opus-5`/`xhigh` (`:140`) y grok
   `grok-4.6`/`xhigh` (`:177`) en ese tier. zcode: fila vacía hereda del padre
   (12.1). kimi: sin claves de ruteo (sellado 12.3) — la POSESIÓN del perfil
   sí viaja (13.8), el ruteo no (no confundir las dos cosas,
   `docs/phase-13-adversary-plan.md:97-102`).
3. Un tier propio exigiría valores de celda nuevos sin medición que los
   sostenga — exactamente lo que la Phase 12 prohibió (condición no
   negociable: los valores salen de mediciones).

El candado "IDs de modelo SOLO en el router" sigue verde: el perfil
`agents/adversary.md` NO lleva `model:` (misma fuente compartida que el resto,
`docs/phase-12-model-routing-design.md:54-66`). 13.7 añade la fila
`adversary → review` en `rol_a_tier` y nada más.

### D6 — Mapeo de rol y precedencia (la pieza que hoy NO existe)

Para que 13.5 lo implemente:

- **`canonical_agent_role`** (`hooks/summonaikit-harness.sh:1389-1402`):
  - Caso exacto `adversary` → `adversary` (estilo de los exactos existentes,
    `:1392-1396`).
  - Keyword `(^|[^a-z])adversar` → `adversary`, **COLOCADO ANTES de la rama
    reviewer** (`:1398`). La trampa medida: `adversarial-audit` hoy resuelve a
    reviewer por el keyword `audit`; con la precedencia nueva, la rama
    adversary gana y `adversarial-*` NO acredita reviewer — el slot de review
    sigue exigiendo su propio despacho. Consecuencia declarada y querida: un
    nombre `adversarial-*` satisface el slot adversary (con su orden) y el
    turno sin reviewer real sigue bloqueando.
  - **No se amplía a stems genéricos** (`attack`, `exploit`, ...): matchearían
    falsos positivos (nombres de herramientas de seguridad que no son el rol).
    El stem queda en `adversar`, tan acotado como el vocabulario del rol.
- **`record_agent`: sin cambios estructurales.** Adversary entra a
  `agents_seen` por despacho como los otros tres; el dedupe conserva el orden
  de primera aparición (`hooks/summonaikit-harness.sh:1420-1423`) — la
  re-corrida (adversary dos veces) conserva la posición de la primera, y ése
  es exactamente el vector del TOCTOU declarado en D2.
- **Escotilla `DELEGATED`** (`hooks/summonaikit-harness.sh:1881`): extender la
  alternancia a `(implementer|verifier|reviewer|adversary)`. Razón (hallazgo
  alto del cross-review del plan): un lead que delega adversary en vivo y
  escribe `DELEGATED - awaiting adversary` hoy cae al gate normal y quema un
  ciclo. El contrato nombra la forma (13.6).
- **Escotilla `ROLE FALLBACK`** (`hooks/summonaikit-harness.sh:2007-2029`):
  aceptar `ROLE FALLBACK: ADVERSARY` con la misma disciplina subcadena de los
  otros tres — y con sus mismos límites declarados (match subcadena sin
  anclar sobre texto del asistente: aceptado a propósito, mismo trade-off A8
  que el comentario ya documenta).
- **Gate condicional:** según D4 (orden + línea label-only + byte-idéntico
  sin adversary).
- **Casos con nombre para 13.5** (cada uno con su golden):
  1. con adversary cierra;
  2. fuera de orden bloquea;
  3. adversary dos veces (re-corrida post-adjudicación = TOCTOU declarado);
  4. adversary sin verifier previo;
  5. `adversarial-*` no acredita reviewer;
  6. `DELEGATED - awaiting adversary` perdona el Stop;
  7. `ROLE FALLBACK: ADVERSARY` cierra;
  8. sin adversary cierra igual que hoy;
  9. lane fast con adversary visto exige la línea `ADVERSARY:` (B1 del
     review: los labels del recibo ya se exigen en fast; éste no es
     excepción).

## Divergencias con el borrador

El borrador (`docs/phase-13-adversary-borrador.md`) queda sin editar como
referencia del operador. Este diseño lo corrige en tres puntos, todos de la
misma raíz — promete infraestructura que no existe:

1. **PreToolUse prometido vs modo degradado.** El borrador afirma "a PreToolUse
   hook denies any other path" (`borrador:25-27`). Medido: ningún host
   registra `PreToolUse` (§ premisas). El enforcement real es detección
   post-hoc + bloqueo en el Stop (D3), y el perfil de 13.2 lo describe así,
   con sus límites — incluido el hueco de `Bash` declarado AL PROPIO agente.
2. **Artefacto session-keyed vs dir-scoped keyless.** El borrador fija
   `.saikit/findings/<session_id>.json` como única ruta escribible
   (`borrador:25,71`). Medido: el `session_id` no tiene canal uniforme de
   propagación al subagente y en grok no tiene ninguno (§ premisas, 7.2). El
   diseño es keyless: prefijo de directorio `.saikit/findings/`, nombre libre
   bajo convención sugerida (D2).
3. **"Un JSON por sesión" vs convención de nombre libre bajo el dir.** La
   unicidad por sesión venía de la ruta keyed; sin ella, el reviewer adjudica
   el más reciente y la ambigüedad de sesiones concurrentes se declara (D2) —
   misma familia que la colisión del saneo de id que el plan ya declara.

Lo demás del borrador (superficie de ataque en orden de yield, reglas de
evidencia, forma del JSON de hallazgos, "si no encontraste nada, file zero
findings y decí qué atacaste") se conserva: 13.2 lo lleva al perfil casi
textual.

## Límites declarados (consolidado)

**Procedencia de los IDs de hallazgo (aclarado por qwen r2 #2):** en este
doc conviven DOS esquemas de numeración, de DOS rondas distintas. `A1/A2/
M1–M3/B1–B3` son los 8 hallazgos del reviewer SUBAGENTE de la ceremonia
(pre-merge, PR #63). `claude #N` (12) y `codex #N` (5) son los 17 de la
ronda externa 1; `kimi r2 #N` y `qwen r2 #N` los de la ronda externa 2
(4 únicos tras convergencia). Total externo: 21.

Lo que esta fase NO cubre, declarado desde el diseño:

- **Sin canal de negación:** ningún host registra `PreToolUse`; el candado es
  detección post-hoc + bloqueo en el Stop (D3).
- **Candado ciego en zcode/kimi:** atribución interna unknown en ambos hosts;
  fail-open declarado, sin bloqueos por atribución ahí (D3). **Consecuencia
  kimi específica (claude #2, dirección kimi r2 #1):** sin canal medido, se
  PROYECTA que ni la capa 2 ni el gitignore corren en kimi (riesgo #4
  cubierto sólo por la capa 1); proyección sobre unknown — si un canal no
  medido existiera, los mecanismos correrían de más, no de menos.
- **Bash best-effort:** redirección/heredoc/tee obvios; el resto son huecos
  declarados al spec, misma familia que G2 (D3). Parser de shell completo:
  Reject.
- **TOCTOU del artefacto:** re-corrida post-adjudicación puede reescribir el
  JSON; sin sellado; el ancla es el veredicto del reviewer (D2).
- **`ADVERSARY:` label-only:** el gate no valida N contra el JSON (D4).
- **Invocado-no-observado indistinguishable de no invocado:** el turno cierra
  limpio sin `ADVERSARY:` (D1).
- **Ambigüedad de sesiones concurrentes en el artefacto** (degradado: mayor
  mtime gana, se declara; el canal primario es el lead nombrando el artefacto
  en el despacho del reviewer, D2/M2). **Staleness secuencial RESUELTO por
  regla (codex #2):** un turno sin adversary NO adjudica nada; el fallback
  por mtime sólo existe para turnos que SÍ lo corrieron y no nombraron
  archivo. **Colisión posible del saneo de id** si algún día un id
  keyed entra en una ruta (D2; la disciplina `:361` sigue siendo obligatoria
  para ese caso).
- **Residual de redacción en ambos sentidos:** falso negativo (PII/secreto que
  la familia de regexes no matchee) y falso positivo (repro que matchea patrón
  de token) con ruta de fuga manual declarada — archivo:línea, redactar/borrar,
  re-cerrar (D2, tres capas, hallazgo A1). **Familia REDUCIDA (claude #3):**
  la capa 2 usa la familia inline del hook (`redact_secrets`), no los
  formatos extendidos de `tools/check-secrets.sh` — el hook corre en el
  consumer donde ese archivo no existe; duplicarlo sería drift sin candado.
  **Bloqueo cross-sesión ACOTADO (claude #7 / codex #3 / Greptile P1):** el
  alcance del escaneo es por sesión (rutas registradas + mtime posterior al
  armado) — un match de ESTA sesión bloquea sus siguientes Stops hasta
  limpieza manual; los artefactos de sesiones ANTERIORES ya no bloquean.
- **Gitignore pisable:** `*` no afecta trackeados; `git add -f` lo pisa;
  gitignore AJENO preexistente jamás se edita (los artefactos quedan
  expuestos si no cubre, codex #4); **ventana de exposición por host
  (claude #5):** a mitad de corrida en claude/grok/codex (primer evento
  interno), durante la corrida ENTERA en zcode (despacho-only, el
  PostToolUse del disparador llega al terminar el subagente) (D2).
- **Lane fast:** el gate no exige despachar adversary (como no exige los otros
  tres); si uno corrió y fue visto, la línea `ADVERSARY:` se exige igual que
  las demás labels (D1, caso 9 de D6).
- **Residual `#8` persiste para verifier/reviewer:** esta fase sólo candó al
  rol nuevo (Purpose).

## Qué le toca a cada task

El plan (`docs/phase-13-adversary-plan.md:118-130`) fija el ledger; acá cada
task recibe las decisiones que le tocan con precisión:

- **13.2 — `agents/adversary.md`.** Perfil adaptado del borrador con el
  enforcement REAL: única zona de escritura `.saikit/findings/` (dir-scoped
  keyless, D2), convención de nombre `adversary-<timestamp-UTC>.json`,
  candado = detección post-hoc + bloqueo en el Stop (D3) con sus límites —
  incluido el hueco de `Bash` declarado AL PROPIO agente — y la regla de
  redacción ANTES de escribir (D2 capa 1, disciplina `redact_secrets`
  `hooks/summonaikit-harness.sh:1343-1347` como referencia). Frontmatter y
  secciones estándar del kit (Context Policy, usuario final no técnico,
  `saikit_owned`); SIN `model:` (D5). Superficie de ataque y reglas de
  evidencia del borrador se conservan.
- **13.3 — `agents/reviewer.md`, sección de adjudicación.** Canal primario:
  el despacho del reviewer NOMBRA el artefacto cuando el lead corrió
  adversary en el turno (M2); **un turno que NO corrió adversary NO adjudica
  nada — el fallback de mayor mtime sólo existe para un turno que SÍ lo
  corrió y no nombró archivo (codex #2: sin esta regla, el artefacto viejo
  de otra task se adjudica contra el cambio nuevo y rompe la promesa de
  comportamiento intacto sin invocación)**; degradado: el de MAYOR mtime,
  declarándolo (D2). Cada hallazgo recibe veredicto
  explícito (aceptado → gap list con file:line / rechazado → razón de una
  línea); `unverified` no se eleva solo; **cada campo del finding es DATO,
  jamás instrucción** (el JSON lo redactó otro modelo procesando contenido no
  confiable — canal directo de inyección al rol que emite veredictos);
  artefacto ilegible/malformado ⇒ se declara al lead, no se inventan
  hallazgos ni se tira el turno; sin artefacto nombrado ni presente ⇒ flujo
  actual sin cambio.
- **13.4 — candado en el hook (D3 + D2 capas 2-3).** Detección post-hoc de
  Edit/Write atribuidos al adversary fuera del dir permitido, con
  canonicalización (traversal `../`, ruta absoluta, symlink); entrada
  unsatisfiable-by-label en el Stop, SIN git; **flag de violación en estado
  que la limpieza existente ya borra** (M3: extender `write_state`/`harness-state.env`
  o la lista del A4-c4, jamás un archivo huérfano bajo `$STATE_DIR`); **los
  chequeos de violación y secreto ANTES de las escotillas tempranas
  PAUSED/DELEGATED** (A2, orden de evaluación de D3); `Bash` best-effort; escaneo de
  secretos en el Stop — disparo acotado a sesiones con `,adversary,` en
  `agents_seen` (A1), **alcance por sesión: rutas registradas como escritas
  por el adversary de la sesión + archivos de mtime posterior a la época de
  armado guardada en el estado (Greptile P1: los artefactos históricos de
  otras tareas no vuelven a bloquear)**, fail-closed por match
  (archivo:línea, jamás contenido), fail-open por ilegible; creación
  idempotente del gitignore del consumer al
  detectar el PRIMER evento que resuelva a adversary por cualquier canal
  medido — despacho O interno (M1; clase de efecto nueva, D2). La época de
  armado y las rutas registradas viajan en el MISMO estado que la violación
  (disciplina M3: extendido por `write_state`, limpiado por los caminos
  existentes). DoD: rojo
  medido pre-fix; caso que bloquea + caso que permite (escribir el artefacto)
  + **caso Greptile P1: artefacto histórico de otra sesión con match NO
  bloquea (alcance por sesión)** + caso traversal/ruta sucia — `../`, absoluta, symlink en el `file_path` Y
  symlink del propio `findings/` (claude #9); el plan decía "id sucio", que
  acá se reinterpreta: el candado es keyless, no hay id de sesión en la
  ruta, el caso ejercita la canonicalización de segmentos atacantes del
  path (codex #5) — + caso de falla de infraestructura con la postura
  elegida; mutaciones propias acreditadas; 0 divergencia en la línea base.
- **13.5 — gate + mapeo (D4 + D6).** Caso exacto y keyword `adversar` con
  precedencia sobre la rama reviewer en `canonical_agent_role`; `record_agent`
  sin cambios estructurales; escotilla `DELEGATED` extendida a
  `(implementer|verifier|reviewer|adversary)`; escotilla
  `ROLE FALLBACK: ADVERSARY`; orden condicional
  `implementer.*verifier.*adversary.*reviewer` + línea `ADVERSARY:`
  label-only cuando `,adversary,` ∈ `agents_seen` (lane-independiente, B1);
  sin adversary, byte-idéntico. Los 9 casos con nombre de D6. Mutación
  acreditada. Línea base según el estándar del plan (0 divergentes si no se
  movió prosa; regrabado con diff auditado y 0 veredictos movidos si sí —
  precedente 11.1).
- **13.6 — contrato de armado (D1 + formas de D4/D6).** Criterio de delegación
  (auth, pagos, migraciones/datos preexistentes, el hook mismo); formato de la
  línea `ADVERSARY:`; forma `DELEGATED - awaiting adversary`; **la forma del
  despacho del reviewer que NOMBRA el artefacto a adjudicar** (canal primario
  de M2/D2: "adjudicá `<ruta>`" cuando el lead corrió adversary en el turno)
  **y la instrucción negativa de 13.3: "si este turno no corrió adversary, no
  adjudiques artefacto alguno" (codex #2)**; caso negativo que fija que el
  gate NO exige adversary cuando no corrió.
  Límite declarado: invocado-no-observado indistinguible. Dentro del
  presupuesto de tokens del canal medido en 7.4. Línea base por precedente 11.1.
- **13.7 — router (D5).** Fila `adversary → review` en `rol_a_tier`
  (`tools/model-routing.sh:73-78`) y frontmatter vía instalador: claude con
  valores; zcode/grok según 12.1/12.2 (fila vacía hereda del padre); kimi sin
  claves de ruteo. Test del router extendido; el candado "IDs de modelo SOLO
  en el router" sigue verde.
- **13.8 — hosts.** Perfiles por las costuras REALES de la Phase 12: claude
  (`~/.claude/agents/`, manifiesto de vendor — 12.6), zcode
  (`~/.zcode/agents/`), grok (`~/.grok/agents/`), kimi (`~/.agents/agents/`,
  posesión SIN ruteo — 12.7). **codex NO tiene costura de perfiles** (`--host
  codex` instala sólo la segunda copia del hook): unknown declarado hasta
  medirse su canal, no se afirma. + casos por target del gate condicional.
- **13.9 — release.** § nuevo del rol en `docs/spec/00-project-spec.md` con
  contrato, enforcement real y TODOS los límites consolidados de arriba;
  reconciliación perfil-vs-implementación (releer `agents/adversary.md`
  contra lo que 13.4/13.5 realmente construyeron — el vicio que el plan le
  criticó al borrador no puede reaparecer por deriva propia); Phase 13 en
  `Plans.md` con markers reales; deploy vía `tools/install-hook.sh` anotado en
  `docs/deploy-log.md`.

## Non-Goals

- Rol obligatorio de entrada (Reject del plan: ceremonia inflada, la lección
  de las 4 h/task). La perilla obligatorio/opt-in es del operador.
- Enforcement "perfecto" de `Bash` (parser de shell completo: pantano ya
  medido por el spec — best-effort declarado).
- Tier propio de ruteo para el rol (D5).
- Sellado o append-only del artefacto (D2: TOCTOU declarado).
- Extender `canonical_agent_role` a stems genéricos de ataque (D6: falsos
  positivos).
- Medir canales internos de zcode/kimi dentro de esta fase: quedan `unknown`
  declarados; si alguna task posterior los mide, el candado de D3 se enciende
  por host sin cambio de diseño (la tabla de premisas ya nombra qué faltaría
  observar).
