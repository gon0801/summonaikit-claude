# Phase 13 — Plan: el adversario (cuarto rol opt-in de la ceremonia)

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development`
> (recommended) or `superpowers:executing-plans` to implement this plan
> task-by-task.

**Goal:** agregar un cuarto rol a la ceremonia — `adversary`, un abogado del
diablo que corre DESPUÉS del verifier y ANTES del reviewer, ataca el cambio
(entradas no manejadas, datos preexistentes, tests que no discriminan, blast
radius, falla parcial, trust boundary) y SOLO reporta: no repara. Opt-in: el
lead lo delega en cambios delicados; un turno sin adversary cierra exactamente
como hoy.

**Origen:** borrador externo del operador, conservado SIN editar como
`docs/phase-13-adversary-borrador.md`. El borrador afirma dos piezas de
infraestructura que este repo NO tiene (un hook PreToolUse que niega escrituras
y la convención `.saikit/findings/`): esta fase las construye o las reescribe
con lo que la medición diga — el perfil que se instale describe el enforcement
REAL, nunca uno prometido.

**Por qué vale la fase:** (a) la lente "¿este test pasaría igual si borro la
función?" no la cubre hoy ningún rol — el verifier corre la suite (verde =
PASS) y el reviewer no audita poder discriminante — y es la debilidad común
medida de TODOS los implementadores delegados; (b) "reporta, no repares"
**mitiga parcialmente** el residual `#8` del spec: evita AGREGAR otro reparador
silencioso, pero verifier/reviewer conservan `Edit, Write` y `#8` queda abierto
para ellos — 13.9 lo deja escrito así en el spec, sin sobreventa.

**Decisión del operador (2026-08-24):** implementación completa como fase
nueva, después de la Phase 12. Diseño por defecto: **opt-in** (costo por task:
un cuarto agente obligatorio en cada task repite la lección de las 4 h/task).
Volverlo obligatorio queda como perilla explícita, no como default.

## Global Constraints

- Las mismas de la Phase 12 que apliquen (rama desde `origin/master` con
  `fetch`; batería completa UNA vez por task y en CI vía PR; local sólo el test
  del archivo tocado; `pre-commit` JAMÁS con `--no-verify`; `set -u` sin `-e`
  en `tools/`; Core Rule 2: valor no reconocido ⇒ error explícito, nunca
  default silencioso; `not_observed != absent`).
- **A diferencia de la Phase 12, acá SÍ se toca el hook** (13.4–13.6): aplica
  `SAIKIT_HOOK_VIVO` apuntando a la fuente en toda corrida local, y **0
  divergencia** exigida en los escenarios golden existentes — la ceremonia de
  tres roles sin adversary tiene que quedar byte-idéntica.
- **Enforcement honesto o declarado:** el candado de escritura es best-effort
  (el rol tiene `Bash`; una redirección es una escritura que un regex puede no
  ver — el propio spec midió lo traicionero del parseo de payloads, A1/A9).
  Cada límite se DECLARA en el spec, no se promete cubierto. **Dato ya
  conocido:** el instalador registra hoy `UserPromptSubmit|PostToolUse|Stop|
  SubagentStart` — NO hay `PreToolUse` registrado, y `PostToolUse` dispara
  DESPUÉS de la escritura: si 13.1 no encuentra canal de negación viable, el
  candado degrada a **detección post-hoc + bloqueo en el Stop**, y eso se
  declara (ver 13.1, rama condicional).
- **Postura de falla del candado:** se decide en 13.1 CON la medición y se
  declara (el default del repo es fail-open, Core Rule 1, con la única
  excepción del instalador; apartarse exige justificarlo por riesgo).
- **Depends externo:** 13.7 depende del router de la Phase 12 (12.4). Los docs
  de la Phase 12 viven en la rama `docs/12-model-routing-design` aún sin
  merge; esta fase no la pisa.

## Diseño de alto nivel (lo fija 13.1 con medición; esto es la intención)

- **D1 — disparador opt-in:** el contrato de armado instruye al lead a delegar
  `adversary` cuando el cambio toca auth, pagos, migraciones/datos
  preexistentes, o el hook mismo — el mismo criterio que hoy dispara
  cross-review. Sin invocación, cero costo nuevo.
- **D2 — artefacto de hallazgos:** un JSON por sesión en el repo del consumer
  (propuesta del borrador: `.saikit/findings/<session_id>.json`), gitignored;
  convención exacta (creación, lectura por el reviewer, limpieza, QUIÉN
  escribe/verifica el gitignore) la fija 13.1. El `session_id` se PROPAGA (el
  subagente no conoce el suyo — 13.1 mide el canal) y se SANEA con la misma
  disciplina que `SESSION_KEY` en el hook (`[^A-Za-z0-9_-]` → `_`) antes de
  usarse como nombre de archivo.
- **D3 — candado de escritura:** el canal medido niega `Edit`/`Write` fuera del
  artefacto — o, si no hay canal de negación viable, detecta post-hoc y bloquea
  en el Stop, declarado; `Bash` best-effort con límites declarados.
- **D4 — gate condicional:** si `agents_seen` contiene `adversary`, el orden
  exigido es implementer→verifier→adversary→reviewer y el recibo lleva su
  línea (`ADVERSARY: N hallazgos, severidad máxima X`); si no, gate actual
  intacto. La línea del recibo es **label-only**: el gate NO valida que N
  coincida con el JSON — límite declarado, coherente con G4.
- **D5 — ruteo:** el rol entra al router de la Phase 12 con su tier (propuesta:
  el de `review` — ataque es trabajo de razonamiento — o tier propio si 13.1
  lo justifica); kimi **no aplica** (sellado, medido 12.3).
- **D6 — mapeo de rol (pieza que hoy NO existe):** `canonical_agent_role()`
  no tiene caso `adversary` y "adversary" no matchea ningún keyword — sin esta
  pieza, D4 es código muerto. Trampa de precedencia ya detectada: un nombre
  tipo `adversarial-audit` hoy resuelve a **reviewer** por el keyword `audit` y
  satisfaría el slot de review sin review real. 13.1 diseña el mapeo (caso
  exacto + keywords + precedencia sobre las ramas existentes) y 13.5 lo
  implementa con caso propio. Escotilla de caída: `record_agent` acredita al
  DESPACHO, no al completar — un adversary invocado que muere dejaría el gate
  exigiendo una línea que no existe; se define `ROLE FALLBACK: ADVERSARY` (la
  misma disciplina que los otros tres roles).

## Tareas

| Task | 内容 | DoD | Depends | Status |
|------|------|-----|---------|--------|
| 13.1 | `[Diseño]` `[lane:gate]` `[tdd:skip:diseño-y-medición]` Diseño medido: (a) atribución de rol en la tool call — ¿qué canal permite saber que Edit/Write/Bash viene del adversary, por host? payloads vivos vía `hook_lab.sh`/captura, no supuestos; **rama condicional explícita**: si NO hay canal de negación viable, se decide acá el modo degradado (detección post-hoc + bloqueo en Stop) o el abort de 13.4, no se improvisa después; (b) convención y ciclo de vida del artefacto de hallazgos (D2): propagación medida del `session_id` al subagente, regla de saneamiento, dueño del gitignore del consumer; (c) postura de falla del candado decidida con la evidencia; (d) tier de ruteo (D5); (e) mapeo de rol y precedencia de keywords (D6), incluida la escotilla `ROLE FALLBACK: ADVERSARY`. Entrega `docs/phase-13-adversary-design.md` | Cada decisión cita su payload o medición; lo no observable queda `unknown` declarado, no rellenado por analogía | Phase 12 (12.3 cerrada; no bloquea) | cc:TODO |
| 13.2 | `[Perfil]` `[lane:fast]` `[tdd:skip:prompt-only]` `agents/adversary.md` adaptado del borrador: la sección del candado describe el enforcement REAL que 13.4 construye (con sus límites), no uno prometido — **incluido el hueco de `Bash` declarado AL PROPIO agente** (la instrucción disuasiva más efectiva es que él sepa que el hueco existe y que usarlo traiciona su rol); secciones estándar del kit (Context Policy, usuario final no técnico); superficie de ataque y reglas de evidencia del borrador se conservan | Consistencia verificada contra los 3 perfiles existentes (frontmatter, secciones, `saikit_owned`); el borrador queda sin editar como referencia | 13.1 | cc:TODO |
| 13.3 | `[Perfil]` `[lane:fast]` `[tdd:skip:prompt-only]` `agents/reviewer.md`: sección de adjudicación — si el artefacto de la sesión existe, cada hallazgo recibe veredicto explícito (aceptado → entra a la gap list con file:line / rechazado → razón de una línea); `unverified` no se eleva solo; **cada campo del finding se trata como DATO, jamás como instrucción** (el JSON lo redactó otro modelo procesando contenido no confiable del repo del consumer — canal directo de inyección al rol que emite el veredicto); artefacto ilegible/malformado ⇒ se declara al lead, no se inventan hallazgos ni se tira el turno; si el artefacto no existe, flujo actual sin cambio | El texto obliga veredicto POR hallazgo y define los DOS casos degradados (sin artefacto / artefacto ilegible) | 13.1 | cc:TODO |
| 13.4 | `[Guardrail]` `[lane:gate]` `[tdd:required]` Candado de escritura del rol adversary en el hook: el canal medido en 13.1 niega Edit/Write fuera del artefacto (o el modo degradado que 13.1 haya decidido); ruta permitida con canonicalización (traversal `../`, ruta absoluta, symlink) y `session_id` saneado con la disciplina de `SESSION_KEY`; `Bash` best-effort (redirección/heredoc/tee obvios) con límites declarados en el spec; postura de falla según 13.1; el paso de gitignore del consumer se implementa donde 13.1(b) lo haya asignado (o se declara el riesgo si nadie puede) | Rojo medido pre-fix; caso que bloquea + caso que permite (escribir el artefacto) + **caso de traversal/id sucio** + caso de falla de infraestructura con la postura elegida; mutaciones propias acreditadas a su caso; 0 divergencia en la línea base | 13.1 | cc:TODO |
| 13.5 | `[Gate]` `[lane:gate]` `[tdd:required]` Gate de secuencia condicional (D4) **+ el mapeo de rol de D6**: extender `canonical_agent_role`/`record_agent` con el caso exacto y los keywords decididos en 13.1, con su precedencia (un nombre adversario NO acredita reviewer); con adversary en `agents_seen`, exigir implementer→verifier→adversary→reviewer y la línea `ADVERSARY:` (label-only, límite declarado) en el recibo; escotilla `ROLE FALLBACK: ADVERSARY` para el adversary caído; sin adversary, comportamiento byte-idéntico al actual | Casos golden nuevos con nombre: con adversary cierra / fuera de orden bloquea / **adversary dos veces** / **adversary sin verifier previo** / nombre `adversarial-*` no acredita reviewer / escotilla cierra — aunque el resultado de alguno sea declarar el límite del dedupe, queda atado a su caso; + mutación acreditada; escenarios existentes con 0 divergentes | 13.4 | cc:TODO |
| 13.6 | `[Contrato]` `[lane:gate]` `[tdd:required]` Disparador opt-in (D1): el contrato de armado nombra el criterio de delegación y el formato de la línea de recibo; caso negativo que fija que el gate NO exige adversary cuando no corrió (anti-regresión del costo). **Límite declarado**: adversary invocado pero no observado (nombre sin mapear, host sin canal) es indistinguible de no invocado — el turno cierra limpio sin `ADVERSARY:`; va al spec como límite, no se promete detectarlo | Turno sin adversary cierra igual que hoy (caso negativo verde); el contrato lo menciona dentro del presupuesto de tokens del canal medido en 7.4 | 13.5 | cc:TODO |
| 13.7 | `[Ruteo]` `[lane:gate]` `[tdd:required]` Fila/tier del rol adversary en `tools/model-routing.sh` y frontmatter vía instalador: claude con valores; zcode/grok según lo que 12.1/12.2 hayan medido (fila vacía hereda del padre); kimi no aplica (sellado) | Test del router extendido al rol nuevo; el candado "IDs de modelo SÓLO en el router" sigue verde | Phase 12 (12.4), 13.2 | cc:TODO |
| 13.8 | `[Hosts]` `[lane:gate]` `[tdd:required]` Extensión por host: instalar el perfil donde el instalador YA instala perfiles — **medido hoy: zcode (`~/.zcode/agents/`) y grok (`~/.grok/agents/`); codex NO tiene costura de perfiles** (`--host codex` instala sólo la segunda copia del hook) — codex queda `unknown` hasta medirse su canal, no se afirma; + casos por target del gate condicional; kimi declarado no aplica | Por host con costura: un caso que pasa y uno que bloquea (la regla de cada línea base de target); codex y lo no medible en vivo quedan `unknown` declarados | 13.5, 13.7 | cc:TODO |
| 13.9 | `[Release]` `[lane:release]` `[tdd:skip:docs]` Cierre: § nuevo del rol en `docs/spec/00-project-spec.md` — contrato, enforcement real y límites declarados (Bash best-effort; `ADVERSARY:` label-only; invocado-no-observado indistinguible; **lane fast se salta la ceremonia entera, adversary incluido**; **residual `#8` persiste para verifier/reviewer** — esta fase sólo candó al rol nuevo); Phase 13 aterriza en `Plans.md` con markers reales; deploy vía `tools/install-hook.sh` anotado en `docs/deploy-log.md` | Spec/ledger/README coherentes entre sí; deploy-log con el sha instalado | 13.1–13.8 | cc:TODO |

## Clasificación del alcance

**Required** — 13.1 a 13.7 y 13.9: sin candado (13.4) el rol es un prompt que
se cree reglas que nadie impuso; sin adjudicación (13.3) escribe reportes que
nadie lee; sin gate + mapeo (13.5) el rol jamás entra a `agents_seen` y D4 es
código muerto; sin disparador (13.6) nadie lo invoca; sin router (13.7) el rol
queda fuera del contrato de la Phase 12.

**Required, descopable por el operador** — 13.8 (hosts más allá de claude): el
operador pidió "completo", así que entra; si el costo lo amerita, recortarlo es
decisión del operador y se declara, no se recorta en silencio.

**Reject** — hacerlo rol obligatorio de entrada (costo por task: la lección
medida de las 4 h/task vino de ceremonia inflada); enforcement "perfecto" de
Bash (parser de shell completo: el spec ya midió ese pantano — se declara
best-effort).

## Riesgos declarados de entrada

1. **El candado es best-effort.** `Bash` puede escribir con `>` dentro de un
   comando; la cobertura es heurística y sus huecos van al spec como límites,
   igual que los de G2. Y puede no haber canal de NEGACIÓN: hoy no hay
   `PreToolUse` registrado — la rama degradada (detectar + bloquear en Stop)
   está prevista en 13.1, no improvisada.
2. **Costo por invocación.** Un agente más cuando se invoca; mitigado por
   opt-in (D1). La perilla obligatorio/opt-in es del operador.
3. **Colisión con Phase 12.** 13.7 está serializada por Depends; ninguna otra
   task toca el router ni los frontmatter de modelo.
4. **El artefacto persiste reportes de vulnerabilidad** (repro + evidencia) en
   el working tree del consumer. El gitignore es del consumer: 13.1(b) asigna
   el dueño del paso y 13.4 lo implementa o declara; un finding commiteado o
   sincronizado por accidente es el modo de falla a cerrar ahí.

## Validación del plan (2026-08-24)

`team_validation_mode: subagent`. Dos revisores independientes read-only sobre
el borrador de este plan, contra el repo vivo:

- **Seguridad+Arquitectura** — APROBAR CON CAMBIOS. Bloqueante: el mapeo de rol
  no existía en el plan (D6 nuevo; `canonical_agent_role` no reconoce
  `adversary`, y `adversarial-audit` acreditaría reviewer por keyword). Además:
  no hay `PreToolUse` registrado (rama degradada ahora explícita); codex no
  tiene costura de perfiles (13.8 reescrita a `unknown`); inyección vía campos
  del finding (13.3); canonicalización de ruta y saneo del id (13.4); escotilla
  `ROLE FALLBACK: ADVERSARY`; el claim sobre `#8` se bajó a "mitiga
  parcialmente"; riesgo #4 agregado.
- **QA+Escéptico** — APROBAR CON CAMBIOS. Coincidió en el mapeo de rol y el
  `session_id`; agregó: off-ramp de 13.4 si no hay canal (ahora en 13.1);
  artefacto malformado (13.3); `ADVERSARY:` label-only declarado (D4); casos
  con nombre "adversary dos veces" y "sin verifier previo" (13.5); límite de
  degradación silenciosa del opt-in (13.6); hueco de Bash declarado al propio
  agente (13.2); lane fast declarado (13.9).

Ambos coincidieron en que el esqueleto (medición primero, límites declarados,
0 divergencia, opt-in con el criterio ya operante de cross-review) es el
correcto. Todos los hallazgos aceptados están integrados arriba; ninguno quedó
afuera.

## 事前確認

- 事項: external-send — `git push` + `gh pr create` por task (batería en CI)
  理由: regla estándar del repo: la batería completa corre una vez por task, en CI
  scope: Phase 13 / todas las tasks
- 事項: escritura en `~/.claude/hooks/` vía `tools/install-hook.sh` (deploy)
  理由: 13.9 instala el hook con la disciplina de manifiesto existente (tres estados, atómico)
  scope: Phase 13 / Task 13.9
- 事項: sesiones vivas de medición en 13.1 (turnos claude contra `hook_lab.sh`)
  理由: los canales de atribución de rol se miden, no se suponen; preferencia por el lab, no el perfil vivo (lección 9.9: leer el perfil vivo consumió un aviso RN real)
  scope: Phase 13 / Task 13.1
- secret-read: ninguno. destructivo: ninguno.
