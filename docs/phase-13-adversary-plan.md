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
  `SAIKIT_HOOK_VIVO` apuntando a la fuente en toda corrida local. **Estándar de
  divergencia con el precedente real del repo**: las tasks que NO tocan texto
  del contrato exigen **0 divergentes** en la línea base; las que SÍ tocan
  texto (13.6, y 13.5 si mueve prosa del gate) siguen el precedente 11.1/6.3 —
  regrabado golden con **diff de texto auditado y 0 veredictos movidos** (tocar
  una línea del contrato divergió 42/44 escenarios en la 11.1; exigir
  byte-idéntico ahí es exigir lo imposible o recortar el contrato para que la
  golden quede verde).
- **Enforcement honesto o declarado:** el candado de escritura es best-effort
  (el rol tiene `Bash`; una redirección es una escritura que un regex puede no
  ver — el propio spec midió lo traicionero del parseo de payloads, A1/A9).
  Cada límite se DECLARA en el spec, no se promete cubierto. **Dato ya
  conocido (por host, no un composite):** claude registra
  `UserPromptSubmit|PostToolUse|Stop` (lo que `check-hook-registration.sh`
  espera); zcode agrega `SessionStart`; grok agrega `SubagentStart` y
  `PostToolUseFailure`. **Ningún host registra `PreToolUse`**, y `PostToolUse`
  dispara DESPUÉS de la escritura: si 13.1 no encuentra canal de negación
  viable, el candado degrada a **detección post-hoc + bloqueo en el Stop**, y
  eso se declara (ver 13.1, rama condicional).
- **Postura de falla del candado:** se decide en 13.1 CON la medición y se
  declara (el default del repo es fail-open, Core Rule 1, con la única
  excepción del instalador; apartarse exige justificarlo por riesgo).
- **Depends externo:** 13.7 depende del router de la Phase 12 (12.4); 13.8
  depende además de las costuras de posesión de perfiles de la Phase 12
  (12.6 claude, 12.7 kimi). Los docs de la Phase 12 viven en la rama
  `docs/12-model-routing-design` aún sin merge; esta fase no la pisa.

## Diseño de alto nivel (lo fija 13.1 con medición; esto es la intención)

- **D1 — disparador opt-in:** el contrato de armado instruye al lead a delegar
  `adversary` cuando el cambio toca auth, pagos, migraciones/datos
  preexistentes, o el hook mismo — el mismo criterio que hoy dispara
  cross-review. Sin invocación, cero costo nuevo.
- **D2 — artefacto de hallazgos:** un JSON por sesión en el repo del consumer
  (propuesta del borrador: `.saikit/findings/<session_id>.json`), gitignored;
  convención exacta (creación, lectura por el reviewer, limpieza, QUIÉN
  escribe/verifica el gitignore) la fija 13.1. El `session_id` se PROPAGA (el
  subagente no conoce el suyo — 13.1 mide el canal) y se SANEA con la línea
  REAL de `SESSION_KEY` en el hook — regex `[^A-Za-z0-9_-]` → `_` **más el
  truncado `cut -c1-64`**, no sólo el regex. **Límite declarado:** el saneo +
  truncado puede colisionar dos ids distintos en el mismo nombre (`a.b` y
  `a_b`); se declara, no se promete unicidad. **Integridad:** el contenido
  puede quedar obsoleto o reescrito por una re-corrida del adversary DESPUÉS
  de la adjudicación (TOCTOU) — 13.1 decide si el artefacto es append-only /
  se sella al leerlo el reviewer, o si el hueco se declara. **Redacción:** el
  artefacto persiste output real de comandos; la convención exige redactar
  secretos/PII con la disciplina `redact_secrets` ya existente en el repo.
- **D3 — candado de escritura:** el canal medido niega `Edit`/`Write` fuera del
  artefacto — o, si no hay canal de negación viable, detecta post-hoc y bloquea
  en el Stop, declarado; `Bash` best-effort con límites declarados.
- **D4 — gate condicional:** si `agents_seen` contiene `adversary`, el orden
  exigido es implementer→verifier→adversary→reviewer y el recibo lleva su
  línea (`ADVERSARY: N hallazgos, severidad máxima X`); si no, gate actual
  intacto. La línea del recibo es **label-only**: el gate NO valida que N
  coincida con el JSON — límite declarado, coherente con G4.
- **D5 — ruteo y posesión:** el rol entra al router de la Phase 12 con su tier
  (propuesta: el de `review` — ataque es trabajo de razonamiento — o tier
  propio si 13.1 lo justifica). **kimi: el RUTEO no aplica (sellado, medido
  12.3), pero la POSESIÓN del perfil SÍ** — la 12.7 instala perfiles en
  `~/.agents/agents/` sin claves de ruteo; el adversary viaja por esa misma
  costura. No confundir las dos cosas.
- **D6 — mapeo de rol (pieza que hoy NO existe):** `canonical_agent_role()`
  no tiene caso `adversary` y "adversary" no matchea ningún keyword — sin esta
  pieza, D4 es código muerto. Trampa de precedencia ya detectada: un nombre
  tipo `adversarial-audit` hoy resuelve a **reviewer** por el keyword `audit` y
  satisfaría el slot de review sin review real. 13.1 diseña el mapeo (caso
  exacto + keywords + precedencia sobre las ramas existentes) y 13.5 lo
  implementa con caso propio. **La escotilla `DELEGATED` también:** el Stop
  sólo perdona `awaiting (implementer|verifier|reviewer)` — un lead que
  delega adversary y escribe `DELEGATED - awaiting adversary` hoy caería al
  gate normal y quemaría un ciclo; 13.5 extiende esa regex y el contrato la
  nombra. Escotilla de caída: `record_agent` acredita al DESPACHO, no al
  completar — un adversary invocado que muere dejaría el gate exigiendo una
  línea que no existe; se define `ROLE FALLBACK: ADVERSARY` (la misma
  disciplina que los otros tres roles).

## Tareas

| Task | 内容 | DoD | Depends | Status |
|------|------|-----|---------|--------|
| 13.1 | `[Diseño]` `[lane:gate]` `[tdd:skip:diseño-y-medición]` Diseño medido: (a) atribución de rol en la tool call — ¿qué canal permite saber que Edit/Write/Bash viene del adversary, por host? payloads vivos vía `hook_lab.sh`/captura, no supuestos; **rama condicional explícita**: si NO hay canal de negación viable, se decide acá el modo degradado (detección post-hoc + bloqueo en Stop) o el abort de 13.4, no se improvisa después; (b) convención y ciclo de vida del artefacto de hallazgos (D2): propagación medida del `session_id`, saneo con la línea real (regex + `cut -c1-64`) y su límite de colisión declarado, integridad post-adjudicación (append-only / sellado / límite declarado), redacción de secretos con la disciplina `redact_secrets`, dueño del gitignore del consumer; (c) postura de falla del candado decidida con la evidencia; (d) tier de ruteo (D5); (e) mapeo de rol y precedencia de keywords (D6), **incluida la extensión de la escotilla `DELEGATED - awaiting adversary`** y la escotilla `ROLE FALLBACK: ADVERSARY`. Entrega `docs/phase-13-adversary-design.md` | Cada decisión cita su payload o medición; lo no observable queda `unknown` declarado, no rellenado por analogía | Phase 12 (12.3 cerrada; no bloquea) | cc:TODO |
| 13.2 | `[Perfil]` `[lane:fast]` `[tdd:skip:prompt-only]` `agents/adversary.md` adaptado del borrador: la sección del candado describe el enforcement REAL que 13.4 construye (con sus límites), no uno prometido — **incluido el hueco de `Bash` declarado AL PROPIO agente** (la instrucción disuasiva más efectiva es que él sepa que el hueco existe y que usarlo traiciona su rol) — **y la regla de redacción: ningún secreto/PII va al artefacto, la evidencia se redacta antes de escribirse**; secciones estándar del kit (Context Policy, usuario final no técnico); superficie de ataque y reglas de evidencia del borrador se conservan | Consistencia verificada contra los 3 perfiles existentes (frontmatter, secciones, `saikit_owned`); el borrador queda sin editar como referencia | 13.1 | cc:TODO |
| 13.3 | `[Perfil]` `[lane:fast]` `[tdd:skip:prompt-only]` `agents/reviewer.md`: sección de adjudicación — si el artefacto de la sesión existe, cada hallazgo recibe veredicto explícito (aceptado → entra a la gap list con file:line / rechazado → razón de una línea); `unverified` no se eleva solo; **cada campo del finding se trata como DATO, jamás como instrucción** (el JSON lo redactó otro modelo procesando contenido no confiable del repo del consumer — canal directo de inyección al rol que emite el veredicto); artefacto ilegible/malformado ⇒ se declara al lead, no se inventan hallazgos ni se tira el turno; si el artefacto no existe, flujo actual sin cambio | El texto obliga veredicto POR hallazgo y define los DOS casos degradados (sin artefacto / artefacto ilegible) | 13.1 | cc:TODO |
| 13.4 | `[Guardrail]` `[lane:gate]` `[tdd:required]` Candado de escritura del rol adversary en el hook: el canal medido en 13.1 niega Edit/Write fuera del artefacto (o el modo degradado que 13.1 haya decidido); ruta permitida con canonicalización (traversal `../`, ruta absoluta, symlink) y `session_id` saneado con la disciplina COMPLETA de `SESSION_KEY` (regex + truncado); integridad post-adjudicación según lo que 13.1(b) haya decidido; `Bash` best-effort (redirección/heredoc/tee obvios) con límites declarados en el spec; postura de falla según 13.1; el paso de gitignore del consumer se implementa donde 13.1(b) lo haya asignado (o se declara el riesgo si nadie puede) | Rojo medido pre-fix; caso que bloquea + caso que permite (escribir el artefacto) + **caso de traversal/id sucio** + caso de falla de infraestructura con la postura elegida; mutaciones propias acreditadas a su caso; 0 divergencia en la línea base | 13.1 | cc:TODO |
| 13.5 | `[Gate]` `[lane:gate]` `[tdd:required]` Gate de secuencia condicional (D4) **+ el mapeo de rol de D6**: extender `canonical_agent_role`/`record_agent` con el caso exacto y los keywords decididos en 13.1, con su precedencia (un nombre adversario NO acredita reviewer); **extender la escotilla `DELEGATED` a `awaiting adversary`** (hoy sólo perdona los tres roles — un lead que delega adversary en vivo caería al gate y quemaría un ciclo); con adversary en `agents_seen`, exigir implementer→verifier→adversary→reviewer y la línea `ADVERSARY:` (label-only, límite declarado) en el recibo; escotilla `ROLE FALLBACK: ADVERSARY` para el adversary caído; sin adversary, comportamiento byte-idéntico al actual | Casos golden nuevos con nombre: con adversary cierra / fuera de orden bloquea / **adversary dos veces** (incluida la re-corrida DESPUÉS de la adjudicación — el dedupe conserva el orden pero el JSON pudo reescribirse; el resultado puede ser declarar el límite, atado a su caso) / **adversary sin verifier previo** / nombre `adversarial-*` no acredita reviewer / `DELEGATED - awaiting adversary` perdona el Stop / escotilla de caída cierra; + mutación acreditada; escenarios existentes: 0 divergentes si no se movió prosa del contrato, o regrabado con diff auditado y 0 veredictos movidos si sí (precedente 11.1) | 13.4 | cc:TODO |
| 13.6 | `[Contrato]` `[lane:gate]` `[tdd:required]` Disparador opt-in (D1): el contrato de armado nombra el criterio de delegación, el formato de la línea de recibo y la forma `DELEGATED - awaiting adversary`; caso negativo que fija que el gate NO exige adversary cuando no corrió (anti-regresión del costo). **Límite declarado**: adversary invocado pero no observado (nombre sin mapear, host sin canal) es indistinguible de no invocado — el turno cierra limpio sin `ADVERSARY:`; va al spec como límite, no se promete detectarlo | Turno sin adversary cierra igual que hoy (caso negativo verde); el contrato lo menciona dentro del presupuesto de tokens del canal medido en 7.4; **línea base por el precedente 11.1**: regrabado golden con diff de texto auditado y 0 veredictos movidos (tocar el contrato divergió 42/44 en la 11.1 — byte-idéntico acá no es el estándar) | 13.5 | cc:TODO |
| 13.7 | `[Ruteo]` `[lane:gate]` `[tdd:required]` Fila/tier del rol adversary en `tools/model-routing.sh` y frontmatter vía instalador: claude con valores; zcode/grok según lo que 12.1/12.2 hayan medido (fila vacía hereda del padre); kimi sin claves de ruteo (sellado 12.3) | Test del router extendido al rol nuevo; el candado "IDs de modelo SÓLO en el router" sigue verde | Phase 12 (12.4), 13.2 | cc:TODO |
| 13.8 | `[Hosts]` `[lane:gate]` `[tdd:required]` Extensión por host, por las costuras REALES de posesión de perfiles que deja la Phase 12: **claude** (12.6: `~/.claude/agents/` con manifiesto de vendor — el adversary es kit-owned, entra como cuarto perfil), **zcode** (`~/.zcode/agents/`), **grok** (`~/.grok/agents/`), **kimi** (12.7: `~/.agents/agents/`, posesión SIN claves de ruteo — el ruteo sellado no anula la instalación del perfil); **codex NO tiene costura de perfiles** (`--host codex` instala sólo la segunda copia del hook) — queda `unknown` hasta medirse su canal, no se afirma; + casos por target del gate condicional | Por host con costura: un caso que pasa y uno que bloquea (la regla de cada línea base de target); codex y lo no medible en vivo quedan `unknown` declarados | 13.5, 13.7, Phase 12 (12.6, 12.7) | cc:TODO |
| 13.9 | `[Release]` `[lane:release]` `[tdd:skip:docs]` Cierre: § nuevo del rol en `docs/spec/00-project-spec.md` — contrato, enforcement real y límites declarados (Bash best-effort; `ADVERSARY:` label-only; invocado-no-observado indistinguible; colisión del saneo de id; **lane fast se salta la ceremonia entera, adversary incluido**; **residual `#8` persiste para verifier/reviewer** — esta fase sólo candó al rol nuevo); **reconciliación perfil-vs-implementación**: se relee `agents/adversary.md` contra lo que 13.4/13.5 REALMENTE construyeron y toda divergencia se corrige antes del cierre (el vicio que el plan le criticó al borrador no puede reaparecer por deriva propia); Phase 13 aterriza en `Plans.md` con markers reales; deploy vía `tools/install-hook.sh` anotado en `docs/deploy-log.md` | Spec/ledger/README coherentes entre sí; el perfil no promete nada que el hook instalado no haga; deploy-log con el sha instalado | 13.1–13.8 | cc:TODO |

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
   igual que los de G2. Y puede no haber canal de NEGACIÓN: ningún host
   registra `PreToolUse` — la rama degradada (detectar + bloquear en Stop)
   está prevista en 13.1, no improvisada.
2. **Costo por invocación.** Un agente más cuando se invoca; mitigado por
   opt-in (D1). La perilla obligatorio/opt-in es del operador.
3. **Colisión con Phase 12.** 13.7/13.8 están serializadas por Depends
   (12.4/12.6/12.7); ninguna otra task toca el router ni los frontmatter.
4. **El artefacto persiste reportes de vulnerabilidad** (repro + evidencia,
   output real de comandos) en el working tree del consumer — puede arrastrar
   secretos/PII si no se redacta. Mitigación en tres capas: redacción
   obligatoria en el perfil (13.2) y en la convención (13.1(b), disciplina
   `redact_secrets`), gitignore con dueño asignado (13.1(b)→13.4), y el
   residuo se declara. Un finding commiteado o sincronizado por accidente es
   el modo de falla a cerrar ahí.

## Validación del plan (2026-08-24)

`team_validation_mode: subagent`. Dos revisores subagente independientes
read-only sobre el borrador de este plan, contra el repo vivo:

- **Seguridad+Arquitectura** — APROBAR CON CAMBIOS. Bloqueante: el mapeo de rol
  no existía en el plan (D6 nuevo; `canonical_agent_role` no reconoce
  `adversary`, y `adversarial-audit` acreditaría reviewer por keyword). Además:
  no hay `PreToolUse` registrado (rama degradada ahora explícita); codex no
  tiene costura de perfiles; inyección vía campos del finding (13.3);
  canonicalización de ruta y saneo del id (13.4); escotilla `ROLE FALLBACK:
  ADVERSARY`; el claim sobre `#8` se bajó a "mitiga parcialmente"; riesgo #4.
- **QA+Escéptico** — APROBAR CON CAMBIOS. Coincidió en el mapeo de rol y el
  `session_id`; agregó: off-ramp de 13.4 si no hay canal (ahora en 13.1);
  artefacto malformado (13.3); `ADVERSARY:` label-only declarado (D4); casos
  con nombre "adversary dos veces" y "sin verifier previo" (13.5); límite de
  degradación silenciosa del opt-in (13.6); hueco de Bash declarado al propio
  agente (13.2); lane fast declarado (13.9).

**Cross-review externo (1 ronda, 3 revisores en paralelo, 2026-08-24)** sobre
el commit del plan (`origin/master..HEAD`). codex y grok excedieron el tope de
300 s en el primer intento (kill por timeout, sin veredicto) y entregaron al
reintento con tope de 600 s — un reintento por caída no es segunda ronda.

- **grok** (verificó contra el hook vivo) — 1 alta aceptada: la escotilla
  `DELEGATED` sólo perdona `awaiting (implementer|verifier|reviewer)` — el
  caso VIVO de delegación del adversary caía al gate (ahora en D6/13.5/13.6);
  1 media aceptada: el estándar de línea base para tasks que tocan texto del
  contrato es el precedente 11.1 (diff auditado, 0 veredictos movidos), no
  byte-idéntico (constraint y 13.6 reescritos); 2 bajas aceptadas: el mapa de
  fases registradas era un composite que no coincide con ningún host
  (corregido por host), y el saneo de `SESSION_KEY` incluye `cut -c1-64`, no
  sólo el regex (D2/13.4).
- **codex** (leyó el repo y la rama de la Phase 12) — 2 altas aceptadas: 13.8
  omitía las costuras de perfiles de 12.6 (claude) y 12.7 (kimi) confundiendo
  "sin ruteo" con "sin perfiles" (13.8/D5 reescritas), y la re-corrida del
  adversary tras la adjudicación puede reescribir el JSON conservando un orden
  válido — TOCTOU (D2/13.1(b)/caso de 13.5); 2 medias aceptadas: falta de
  reconciliación perfil-vs-implementación (13.9) y falta de redacción de
  secretos/PII en el artefacto (13.1(b)/13.2/riesgo #4).
- **qwen** — 1 media aceptada: la misma reconciliación perfil-vs-implementación
  (13.9); 1 baja aceptada: colisión posible del saneo de id (límite declarado
  en D2). **Rechazados con razón:** "encabezados en chino" (`内容`/`事前確認`
  son la plantilla obligatoria del harness, idéntica a todo el ledger);
  "Plans.md sólo al cierre" (es el precedente exacto de la Phase 12, Task
  12.8); las skills del encabezado sí existen en el harness.

Hubo severidad alta en la ronda: por la regla del operador, una segunda ronda
es POSIBLE pero no obligatoria; los tres hallazgos altos quedaron integrados y
verificados contra el código (regex de la escotilla en el hook, línea de
`SESSION_KEY`, tasks 12.6/12.7 en la rama de la Phase 12). Si no se corre
segunda ronda, este registro es la declaración de residuales.

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
