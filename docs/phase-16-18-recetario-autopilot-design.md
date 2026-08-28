# Phases 16–18 — El recetario y el autopilot (super plugin de vibe coding): diseño

Fecha: 2026-08-28. Origen: `cursor/plugins` → `pstack` (poteto-mode), licencia
MIT — se copia y adapta con atribución. Triage de las 69 piezas leídas una por
una (23 recetas, 20 principios, 24 skills/agentes/guía) en el Apéndice A.
Validación de equipo (`team_validation_mode: subagent`): tres revisores
internos — Producto+Escéptico (15 hallazgos), Arquitectura+QA (16), Seguridad
(12) — y **una ronda de cross-review externo con codex y grok en paralelo**
(8 + 14 hallazgos) más el P1 de Greptile en el PR #95. Todo integrado en esta
v3; el registro de qué cambió está en el Apéndice C.

## Propósito

Darle al vibe coder — alguien que **no lee código ni inglés** y que hoy ya usa
el gate — dos cosas que el gate solo no le da:

1. **Un recetario**: el gate confirma que corrieron implementer → verifier →
   reviewer y que hay recibo con evidencia, pero no sabe si la tarea era un bug
   (reproducir primero) o una pantalla nueva (nombrar los datos primero). pstack
   sí lo sabe y no tiene inspector; nosotros tenemos inspector y una sola receta.
2. **Un autopilot**: "ya está listo, mergéalo tú" es inútil para quien no sabe
   qué es un merge. pstack lo resuelve con un permiso general del operador más
   un veredicto independiente antes de mergear. Aquí el veredicto ya existe en
   la ceremonia; falta atarlo al SHA, probar la app real y apretar el botón.

## Decisiones del operador (2026-08-28, no se re-litigan)

- **D0.1** El líder elige la receta (no el hook, no el usuario). Se declara en
  el recibo. Excepción acotada: los alias `-saikit:pregunta` / `-saikit:boceto`
  nombran su receta (D3), porque bajan el carril y una receta distinta en carril
  fast tocaría código de producción sin ceremonia.
- **D0.2** Vive **dentro de este repo**, con forma de plugin desde el día uno
  (skills, perfiles, hook); empaquetar después es un manifiesto, no reescritura.
- **D0.3** Sí autopilot: merge automático con permiso general dado de antemano.
- **D0.4** Criterio de adopción: utilidad real + no chocar; ni todo por inercia
  ni nada fuera por flojera; leer cada pieza; diseñado para sumar después.

## Invariantes (lo que NO cambia)

- Core Rules 1–5 del spec: fail-open del gate, `not_observed != absent`, el
  sentinel `-saikit` es la ÚNICA condición de armado, nunca contra el estado
  real, identidad declarada en el archivo.
- El gate sigue **advisory**; no se promete que sea un control de seguridad.
  **Consecuencia escrita para el autopilot:** el modelo tiene `gh`; un
  `gh pr merge` a pelo se salta `saikit-merge.sh`. El script es la **única vía
  sancionada**, no "la protección"; el merge a pelo es un límite declarado de
  la misma clase que un recibo falso, y la 18.11 (Recommended) intenta cerrarlo
  con un `PreToolUse` en Claude Code.
- Una ceremonia por task; **la batería completa corre UNA vez, en CI**; nunca
  la suite completa local (memoria `harness-lento-causas-y-topes`: la task de
  4 h fue 3 rondas de review + suite por fase, no el CI, que tarda 7–9 min).
- Tope de cross-review: 1 ronda (2 solo si la primera halló severidad alta).
  Este plan ya consumió su ronda (codex + grok); lo residual se declara aquí.
- `protected_branch_push: deny` (prohíbe push directo a master; NO prohíbe
  mergear un PR).
- No se importan archivos de pstack "por si acaso": lo que no entra queda
  registrado en el Apéndice A con su disparador.
- **Baseline de lint bash** de este repo: `tests/lib/check_syntax.sh` (`bash -n`
  sobre todo `*.sh`, corre en `run.sh`). shellcheck queda Optional, no bloquea.

---

## Phase 16 — El recetario

**D1 — Dónde viven y cómo se ofrecen.** Fuente en `recetas/` del repo. El
instalador las planta en `<dir-del-hook>/recetas/` (primera ola: host
`claude`, o sea `~/.claude/hooks/recetas/`). El hook resuelve
`RECETAS_DIR="${SAIKIT_RECETAS_DIR:-$(dirname "$0")/recetas}"` (el override de
entorno existe para que los casos del gate planten recetas de forma
determinista en `$LAB/hooks/recetas`). **El contrato NO imprime la ruta** —
en el lab y en golden el hook se copia a un tmpdir distinto por corrida, y una
ruta absoluta rompería la línea base. Imprime solo el menú
(`nombre — título — carril`) o la línea fija "sin recetario en este host". El
menú sale de **`recetas/MANIFEST.sha256`** (una línea por archivo, **campos
separados por TAB** en este orden: `sha256`, `tipo`, `nombre`, `carril`,
`titulo`; el título va al final y puede llevar espacios pero nunca TAB ni
salto de línea — el linter lo rechaza; `tipo` = `receta` | `lider`; el
formato se ata con un caso de contrato con título de varias palabras),
generado en el repo por `tools/gen-recetas-manifest.sh`, que **corre el mismo
linter** antes de incluir un archivo (un frontmatter roto no entra al
manifiesto: la validez del frontmatter se garantiza en generación, no en
runtime) y está candado por test (manifest == archivos). En runtime el hook
lee el manifiesto y **solo ofrece las recetas de `tipo: receta` cuyo sha256
instalado coincide**; `00-lider.md` (`tipo: lider`) se verifica por hash y se
**referencia** desde la regla de delegación, nunca se ofrece como receta. Una
receta ausente o con hash distinto se omite con aviso — fail-open del turno,
fail-closed de la receta. Sin manifiesto o sin directorio: línea fija y el
turno sigue como hoy. Nada de parseo de frontmatter en runtime (el hook ya
paga ~28 ms por fork en MSYS). **Los hashes tienen que ser iguales en Windows
y Linux**: `.gitattributes` gana `recetas/** text eol=lf` y
`recetas/MANIFEST.sha256 text eol=lf` (hoy solo `*.sh`, `*.sha256` y
`agents/**` van con `eol=lf`, y esta máquina tiene `core.autocrlf=true`: sin
la entrada, el `.md` cambia de bytes al hacer checkout y todas las recetas se
omitirían). Los otros hosts entran después por la vía de los perfiles.

**D2 — Forma de una receta.** Markdown ≤ 80 líneas, en español, con frontmatter
YAML (sin comentario HTML: la marca va en el frontmatter para reutilizar
`agente_estado_con_vendor` del instalador tal cual):

```yaml
saikit_owned: summonaikit-claude
nombre: bug            # id estable, sin espacios
titulo: Arreglar algo que no funciona
carril: full | fast    # qué carril pide (advisory; el sentinel manda, D3)
cuando: ["no funciona", "se rompió", "da error", "está mal"]
adversary: opcional | obligatorio
tier_sugerido: standard | verify | review   # D9, opcional
```

Cuerpo: **Pasos** (numerados, copiables verbatim al todolist; un paso omitido
queda con `skip: <razón>`), **Qué le dices al usuario** (voz `teach`: primero
qué cambia para él, luego cómo, luego por qué), **Recibo** (qué va en
`Understand`/`Implement`/`Verify`). `00-lider.md` no es una receta: tiene
frontmatter (`tipo: lider`) y secciones propias, y el linter lo valida con
sus propias reglas. El linter `tests/test_recetas.sh` exige frontmatter
completo, tope de líneas, carril válido, links que resuelven, tolera CRLF en
lectura, y **rechaza términos prohibidos** (`gt` seguido de espacio, `Graphite`, `Bugbot`,
`AskQuestion`, `/loop` de Cursor, `poteto`) con un fixture rojo — así el
`[tdd:required]` de una receta discrimina contenido, no solo forma.

**D3 — El carril lo fija el sentinel, no la receta; el alias nombra la
receta.** Medido en el hook: en un turno `-saikit` pleno el Stop exige los
tres roles aunque el recibo diga "sin cambio de código"; la única escotilla es
`ROLE FALLBACK`, que es para fallas de infraestructura. Investigar y Boceto son
de solo lectura y piden `fast`. Reglas:

- `-saikit` = full; `-saikit:fast` = fast (hoy). **Nuevo, Required (16.6):**
  `-saikit:pregunta` ⇒ fast **y receta `investigar`**; `-saikit:boceto` ⇒
  fast **y receta `boceto`** (match exacto con frontera, como `:fast`; un typo
  cae a full — límite declarado, mismo que 10.1). El hook guarda
  `receta_alias` en el estado y el contrato lo dice: "este turno está en
  carril fast por `-saikit:boceto`: la receta es `boceto`; es un boceto
  desechable en un directorio aparte, **no toques código de producción**".
  Sin eso, un alias que solo bajara el carril dejaría al líder elegir `funcion`
  y escribir código real sin ceremonia (hallazgo de grok). Es Required porque
  sin él cada "¿cómo funciona X?" en `-saikit` pleno paga tres subagentes, y
  la guía del usuario enseña **tres palabras**: construir (`-saikit`),
  preguntar (`-saikit:pregunta`), bocetar (`-saikit:boceto`).
- Si el turno vino en full y la receta pide fast, el líder **hace la receta y
  corre la ceremonia igual** (implementer reporta "sin cambio de código",
  verifier verifica las afirmaciones corriendo comandos, reviewer revisa la
  respuesta). Es más caro, no es incorrecto, y no abre ninguna escotilla.
  Rechazado: que el líder declare el carril en el recibo (el modelo podría
  bajar cualquier turno a fast; contradice Core Rule 3 y la lección de 10.1).

**D4 — El menú en el contrato.** ~12 líneas nuevas en el heredoc
`HARNESS_CONTEXT`, por sustitución controlada (mismo mecanismo que
`$TOOL_HINT`; el heredoc sigue con delimitador entrecomillado): el menú de D1
+ la regla "elige una, léela entera, copia sus pasos al todolist antes de
razonar, declárala en `Understand:` como `Receta: <nombre>`, paso omitido =
`skip: <razón>`; si ninguna encaja, sigue este contrato como hasta hoy". Texto
del contrato ⇒ línea base golden regrabada con `tools/golden-harness.sh
--record` y diff auditado (precedente 11.1); casos
`caso_g1_contrato_nombra_recetario` (planta `$LAB/hooks/recetas` vía
`SAIKIT_RECETAS_DIR`), `caso_g1_sin_recetario_contrato_igual` (byte-idéntico
al de hoy salvo la línea fija), `caso_g1_receta_hash_distinto_se_omite`;
`test_hook_source` caso 131 sigue verde sin recetas. **Regrabados de golden
previstos en estas fases: 16.4, 16.6, 17.3, 18.3, 18.6 — cada uno con diff
auditado** — se declara, no se esconde.

**D5 — Principios por rol → secciones en `agents/*.md`**, no archivos aparte
(los perfiles ya se instalan por host con la máquina de estados). Cada
principio lleva una línea `Cuándo:` (chequeable con grep). Reparto (Apéndice
A, lote A): implementer ← laziness, foundational, subtract-first,
model-the-domain, type-discipline (recortado), idempotencia, migrar-y-borrar,
fix-root-causes, unidades verificables, + las 3 reglas de `architect` (primero
cómo lo usa el llamador; señales rojas de diseño; fricción repetida =
rediseña); reviewer ← minimize-reader-load, subtract-first, model-the-domain,
migrar-y-borrar, + sección "comentarios y supresiones" (de `comment-sicko`,
sin personalidad) + **los 4 cubos de adjudicación** de `interrogate` (Act on /
Consider / Noted / Dismissed) para hallazgos de adversary, blast y bots;
verifier ← prove-it-works (complemento: sospechar del método de observación;
artefactos, no autorreportes) + "mejor ningún test que un test malo, y
decláralo" (de `tdd`) + **regla de redacción antes de escribir** (hoy solo la
tiene el adversary; el verifier escribirá `blast-*.json`, D13); adversary ←
idempotencia (las 3 preguntas). `boundary-discipline` ya está en 3 lugares: se
consolida en UNA sección `## Boundary Discipline` (el DoD la busca por
encabezado, no por la palabra `boundary`, que también aparece en el ataque
"trust boundary" del adversary y debe seguir ahí).

**D6 — Principios del líder + brief → `recetas/00-lider.md`.** Los 4 del líder
(experience-first, exhaust-the-design-space, never-block-on-the-human con la
frontera de lo irreversible, encode-lessons-in-structure), la plantilla del
brief para delegar (GOAL / SCOPE / CONTEXT / ACCEPTANCE / VERIFY / TIMEBOX /
FORBIDDEN / REPORT, de `orchestrate`; REPORT incluye **"Lo que ves"**: el
resultado observable en palabras simples, de `multi-phase-plan`), las **5
secciones de la descripción del PR** (Why / Scope / Tradeoffs / Blast radius /
Verification, de `opening-a-pr`; nunca draft; PRs chicos), "done como
predicado falsable; lo más incierto primero" (de `figure-it-out`) y "el rastro
previo es autoritativo" (de `session-pickup`). El contrato lo referencia en la
regla de delegación; no se pega entero.

**D7 — Regla fusionada de preguntar, con su excepción escrita.** Se EDITA (no
se agrega) el bloque "Missing-information rule" del contrato para que tenga dos
ramas explícitas: técnico/reversible → decide y presenta el resultado;
producto/irreversible (force-push, borrar datos, mensajes a terceros, deploy,
pagos) → pregunta en palabras simples y cierra con `PAUSED`. **Excepción
explícita, en el mismo párrafo:** lo que el usuario autorizó de antemano por
`-saikit:autopilot` + `.saikit/autopilot.json` (el merge; el deploy que ese
merge dispara si `merge_despliega: true` fue aceptado en el setup; el aviso
por Telegram si `telegram: true`) no se vuelve a preguntar — sin esta
excepción D7 y D21 se contradirían en el mismo heredoc (hallazgo de grok). Y
la regla de `pstack`: "un factual que se observa corriendo algo no es pregunta
para el humano: boceto".

**D8 — Voz.** `/sencillo` (de `bro`): skill de 3 líneas, instalada a nivel
usuario (`~/.claude/skills/sencillo/`) por el instalador, **host claude
solamente** (fuera de alcance en los demás). `teach` vive dentro de la receta
Investigar — junto con la epistemología de `why` (cita todo; "parece que" vs
"es"; nombra los huecos; null es evidencia) — y en la línea `Close:` del
contrato: "primero qué cambia para ti; nunca inventes un link, cita o comando
que no hayas producido o leído en este turno".

**D9 — Ruteo por tarea (Optional).** `tools/model-routing.sh --task <receta>`
resuelve a un **tier existente** (`standard`/`verify`/`review`), nunca a un
modelo — los IDs siguen en un solo lugar (`test_model_routing.sh` lo candea).

**D10 — Medición y su costo.** Cada receta activa = un turno vivo en un repo
descartable con `tools/stage-override.sh`, transcript citado en
`docs/smoke-recetas-<fecha>.md`. Receta sin turno vivo no entra al manifiesto
como `tipo: receta` (queda en `recetas/pendientes/`). `00-lider.md` se ejercita
en cada turno vivo (lo referencia el contrato), no tiene turno propio.
**Costo declarado:** 11 turnos vivos con ceremonia (6 + 2 + 3) a 30–60 min ≈
6–10 h de medición en total; se permite medir hasta 3 recetas por sesión en el
mismo repo descartable. No se afirma que "el modelo sigue la receta" desde la
no-observación.

**Recetas de la primera ola (6):** `bug`, `funcion`, `refactor`, `lento`,
`investigar` (fast), `boceto` (fast). `cuidar-pr` va en Phase 18.

---

## Phase 17 — Verificación real y rastro

**D11 — `verificar-app`.** Skill de kit a nivel usuario
(`~/.claude/skills/saikit-verificar-app/`) que GENERA en el repo del usuario un
`verify/` con `LEEME.md` (mapa de 3–5 funciones en español: "entrar", "crear
X", "ver la lista") y los pasos Launch / Doctor / Drive / Evidence / Cleanup.
**Drive es una prueba e2e que vive bajo `verify/` y ejercita la app por su
superficie de usuario** (navegador o CLI real), escrita en el framework que el
repo ya tiene e invocada siempre por un comando que `TEST_RUNNER_RE` acredita
— medido: `npm test`, `pnpm test`, `vitest`, `jest`, `playwright test`,
`pytest` sí; **`node --test` NO** (se envuelve como `npm test`). **La suite
unitaria del repo NO cuenta como Drive** (hallazgo de grok): `verify_app:
PASS` exige que el comando corrido incluya la ruta `verify/` y que el archivo
de Drive exista ahí; el script del autopilot lo comprueba (D18). Así la corre
CI (batería una vez) y el hook la acredita sin cambios. Si el repo no tiene
framework, el generador **pide un sí explícito al usuario** en palabras
simples antes de instalar el más liviano que la plataforma ya soporte
(capability-first), con versión pinneada en el lockfile del repo, nunca `npx
<pkg>@latest`; si no acepta, `verify/` se genera con Drive "manual, pendiente"
y `verify_app: n/a` declarado — y en autopilot `n/a` **solo autoriza el merge
si el usuario aceptó `sin_verify_app: true` en el setup** (D15), en palabras
simples ("sin prueba de la app, ¿mergeo solo?"); por defecto exige `PASS`. Se
ejecuta **una vez antes de entregar**. Se funde con el skill `run` de la
sesión: `run` arranca y mira; `verificar-app` deja el procedimiento escrito y
probado. Si aparece un runner fuera del regex, se agrega con TDD (Optional).

**D12 — Rastro de decisiones.** `.saikit/decisiones/<task>.tsv`, columnas
`cuando | etapa | decision | por_que | evidencia | resultado`, en español
llano; lo escribe el líder en cada gate con `tools/saikit-decision.sh` (append
seguro). **Redacción compartida:** `tools/lib/redactar.sh` con los patrones
del hook **más** las formas de token conocidas — `ghp_`, `github_pat_`,
`gho_`, `sk-`, `AKIA`, `xox[bp]-` — que el `redact_secrets` actual no cubre
(medido); la usan el rastro (D12) y el blast (D13), y **la familia de patrones
del hook se extiende con las mismas formas** (rojo/verde + mutación en 17.3),
para que el escaneo por sesión de 13.4 también las conozca. `Close:` cita la
ruta y una sección **Atención** con las filas cuyo `resultado` ≠ ok. **Se
commitea ANTES de despachar al reviewer** (D16: cualquier commit posterior
cambia el SHA del veredicto); `.saikit/` no entra a la allowlist de gitleaks.
El adversary, cuando corre, lee el tsv y reporta "afirmación sin evidencia".
**No se leen transcripts** (A6/privacidad).

**D13 — Blast radius.** Paso del verifier "el hecho único": nombra el hecho por
el que el cambio es seguro, lo prueba **corriendo** algo, y asigna nivel
1 (afirmado) · 2 (leído en código) · 3 (test existente) · 4 (corrido a
propósito: script o test nuevo) · 5 (corrido en la superficie real).
Artefacto `.saikit/findings/blast-<task>.json` (`hecho`, `comando`, `salida`,
`nivel`); `salida` **recortada a N líneas y redactada con `redactar.sh`**
(patrones extendidos) antes de escribir — `findings/` está dentro del escaneo
de secretos por sesión (13.4) y una salida cruda con `token=` dispararía un
GATE falso. Verificado: el candado post-hoc del adversary solo aplica a
eventos con rol adversary, así que el verifier puede escribir ahí sin
violación (anotado para que nadie lo re-diagnostique). `findings/` es
gitignored por el hook: el blast es evidencia **local** que `saikit-merge.sh`
lee en la misma sesión, no evidencia del PR — declarado. El reviewer adjudica
(nivel ≥ 4 sin `comando` ⇒ malformado). En autopilot, nivel ≥ 4 es
precondición del merge (D18).

**D14 — Voz en `Close:`.** Primero qué cambia para el usuario, luego cómo,
luego por qué; diagrama mermaid opcional (Artifact lo renderiza nativo).

---

## Phase 18 — El autopilot

**D15 — Autorización: una llave humana + una config versionada, y el límite
declarado.** (1) Sentinel `-saikit:autopilot` → carril full + `autopilot=1` en
el estado (Core Rule 3: explícito, no inferido). Es la **única llave
independiente del modelo**: la teclea el humano. (2) Config por repo
`.saikit/autopilot.json` — `{ "merge": true, "merge_despliega": "unknown",
"salud_url": null, "revert_si_rojo": true, "rama": "master",
"sin_verify_app": false, "telegram": false }` — creada por
`saikit-setup-autopilot` con preguntas en español (¿mergear solo? ¿mergear a
`<rama>` publica la app? ¿hay una URL para checar que sigue viva? ¿sin prueba
de la app, mergeo solo? ¿te aviso por Telegram?). **El script hace `git fetch
origin <rama>` y la lee SOLO de `origin/<rama>`** (`git show
origin/<rama>:.saikit/autopilot.json`), nunca del working tree ni del head del
PR; un PR que toque ese archivo **nunca se auto-mergea**. Con
`protected_branch_push: deny`, cambiarla exige un PR mergeado por el humano.
Límite declarado (hallazgo de los cinco revisores): el modelo tiene `Write` y
`gh`; el gate es advisory; lo que impide que el modelo se auto-autorice en el
mismo turno es esta lectura desde `origin/<rama>` + el deny, no una barrera
criptográfica. Sin config, o con `merge_despliega: "unknown"`, no se mergea.

**D16 — Veredicto atado al SHA y sellado por el hook.** Orden del turno
autopilot: implementer → verifier (+ `verify/`, blast) → adversary (si aplica)
→ **el líder commitea todo, incluido el rastro** → reviewer, que graba `sha =
git rev-parse HEAD` en `.saikit/veredictos/<sha>.json`: `{ sha, pr, verifier:
PASS|FAIL, verify_app: {resultado: PASS|FAIL|n/a, comando}, blast: {nivel,
hecho, comando}, adversary: {findings, max_sev}|n/a, reviewer: clean|findings,
decisiones: ruta }`. **Sello:** el hook, en el `PostToolUse` del `Write`
atribuido al rol reviewer sobre `.saikit/veredictos/`, registra en el estado de
sesión `veredicto_sha256 = sha256(tool_input.content)` (el payload trae el
contenido; es un registro de estado, no un check del Stop). Cualquier
escritura posterior — del líder, de otro rol, por `Edit` o por `Bash` — cambia
el archivo y el hash deja de coincidir (hallazgo alto de codex y grok: "hubo
un Write del reviewer" no bastaba). Un fix tras la revisión = commit nuevo =
SHA nuevo = veredicto nuevo (coherente con la línea `Close:` "¿se tocó código
después del reviewer?"). Sin excepción por `patch-id` en la primera ola.
`veredictos/` y el lock son **gitignored siempre** (el hook crea el
`.gitignore`, como en `findings/`).

**D17 — Receta `cuidar-pr`** (de `babysit` + `bugbot-triage`): declarar el modo
(revisar / cuidar / solo-hilos); orden conflictos → hilos → CI; clasificar un
CI rojo antes de reintentar (flake → un build fresco y solo uno; base vieja →
merge de `config.rama` en la rama, memoria
`rebase-choca-en-deploy-log-usar-merge`; bug real → commit); triage de
Greptile/CodeRabbit con la rúbrica
fix / dismiss / ask y patrones aprendidos en `.saikit/triage-patrones.md`;
esperas SIN bloquear (Monitor + heartbeat largo, nunca un segundo sleep loop;
antes de esperar, checar si ya terminó); tope 2 rondas; **cuidar nunca
autoriza mergear** — eso es D18.

**D18 — `tools/saikit-merge.sh`, fail-closed y acotado.** Segunda excepción
declarada al fail-open (la primera es el instalador): mergear es la acción que
no admite "dejar pasar". **Alcance acotado, nunca argumento libre:** repo =
`gh repo view --json nameWithOwner` del cwd; PR = el de la rama actual (`gh pr
view --json number,baseRefName,headRefOid,author,mergeable`); exige
`baseRefName == config.rama`, `headRefOid == sha del veredicto`, y `author ==
la cuenta de gh` (el PR lo abrió el propio flujo; no se juzga el autor de los
commits). Precondiciones, TODAS observadas: `git fetch origin <rama>` hecho y
**la rama al día con la base** (`git merge-base --is-ancestor origin/<rama>
<head>`; si no: "base vieja ⇒ merge de `config.rama` en la rama y CI de
nuevo", como en `cuidar-pr` — `--match-head-commit` fija el head, no la base,
hallazgo de codex; 18.4 prueba también una config con `rama: main`); PR
`mergeable` (si GitHub devuelve `UNKNOWN`, que lo calcula en
diferido, se reintenta UNA vez tras unos segundos; sigue `UNKNOWN` ⇒ no
merge; 18.1 mide la frecuencia real); CI del head concluido en `success`
(`gh pr checks` + run del workflow; "no hay checks" ≠ verde; forma real medida
en 18.1); veredicto para ESE sha con `verifier: PASS`, `blast.nivel ≥ 4`,
`reviewer: clean`, `verify_app.resultado: PASS` (con `comando` que incluya
`verify/`) o `n/a` con `sin_verify_app: true` en la config; **cruce con el
estado del hook de la sesión** (Required, no opcional): `agents_seen` contiene
`reviewer`, `veredicto_sha256` del estado == sha256 del archivo actual, y el
`comando` del blast aparece en `harness-evidence.log` con éxito — por eso **el
merge corre DENTRO del turno armado, antes del recibo** (el cierre limpio
borra ese estado); `git log origin/<rama>..HEAD` no vacío y sin commits que
no sean del `user.email` local o de la cuenta de gh (así se observa "solo
commits de la task"; hallazgo de grok: "autor ajeno" sin definir podía
bloquear al propio usuario); config de D15 válida. Entonces `gh pr merge
--squash --match-head-commit <sha> --body "Saikit-Merge: <sha-veredicto>"`
(medido: `gh` 2.88 lo soporta; pinea el SHA; **el trailer sella el squash**
para D19). **Sin `--delete-branch`**: tras el merge `gh` intenta borrar la rama
local y hacer checkout de la default, que falla cuando master vive en otro
worktree (flujo de este repo) DESPUÉS de haber mergeado; la rama remota se
borra como paso aparte e idempotente (`git push origin --delete <rama>`), y
"merge ok + borrado falla" se reporta sin reintentar el merge. Nunca
`--admin`, nunca force. Cualquier `unknown` ⇒ no mergea y dice cuál. **El
veredicto sellado no se toca nunca después del sello**: el script registra el
`merge_commit` en un archivo aparte, `.saikit/veredictos/<sha>.merge`
(hallazgo de CodeRabbit: escribirlo dentro del veredicto invalidaba el propio
`veredicto_sha256`), y D19 de todos modos no confía en ese archivo — lo
confirma contra `origin/<rama>` y el trailer. 18.1 mide además si `gh pr
merge` pasa el runtime floor sin prompt humano: un autopilot que pide
confirmación en cada merge no es autopilot.
**La protección de rama de GitHub no está disponible en este repo** (privado,
plan free: 403 medido). Alternativa rechazada con razón: hacer el repo público
la habilita gratis, pero es una decisión del operador sobre visibilidad, no de
este plan. El script es la **vía sancionada** (ver Invariantes: no es "la
protección"); `protected_branch_push: deny` sigue.

**D19 — `tools/saikit-postmerge.sh`.** Corre en un turno **desarmado** (el
turno autopilot cierra con recibo citando el sha; un Monitor de fondo
despierta al modelo cuando el CI de la rama termina — el script no necesita
estado del hook). Identifica el run con `gh run list --commit <merge_commit>`
(verificado en `gh` 2.88); **sin run todavía ⇒ `unknown`, espera con heartbeat
acotado; timeout ⇒ reporta `unknown`, NO revierte**. `GET salud_url` si
existe: solo `http(s)`, sin seguir redirects, `--max-time`, y la URL pasa por
redacción antes de escribirse en cualquier lado. En rojo → **`git revert
<merge_commit>`** (squash: no hay `-m`), PR de revert que pasa por
`saikit-merge.sh --revert-de <merge_commit>`: un **modo distinto, con sus
propias precondiciones**, porque el turno desarmado ya no tiene el estado del
hook que D18 exige (P1 de Greptile) — y **no confía en el JSON local** para
saber qué se puede revertir (hallazgo de codex y grok: `merge_commit` era
plantable): exige que `<merge_commit>` sea **la punta actual de
`origin/<rama>`** tras `git fetch` (si algo aterrizó después, no revierte:
reporta), que su mensaje lleve el trailer `Saikit-Merge:` que solo pone D18,
que el revert sea **exactamente el inverso** del `merge_commit` — se
comprueba por **igualdad exacta de árboles**: `git rev-parse
<head-del-revert>^{tree}` == `git rev-parse <merge_commit>^^{tree}` (el árbol
que había antes del merge); `patch-id` queda solo como comprobación adicional,
porque ignora cambios de espacios en blanco (hallazgo de CodeRabbit; caso:
un revert con un cambio extra de whitespace se rechaza) —, que no traiga
ningún otro commit,
`baseRefName == rama`, CI del head del revert en `success`, y
`--match-head-commit`; NO exige reviewer, blast ni estado de sesión (es la
inversa mecánica de algo ya revisado). Sigue fail-closed: cualquier `unknown`
⇒ no mergea el revert y **avisa al usuario que la rama está roja y cómo
revertir a mano**. Una sola profundidad (un revert rojo se reporta, no se
re-revierte). Mensaje al usuario en español (qué aterrizó, qué cambia para él,
cómo deshacerlo) armado desde el `Close:` ya redactado, ≤ 4096 chars;
`telegram-send` solo con `telegram: true` en la config.

**D20 — En serie, con protocolo de lock definido.** Un PR a la vez por repo:
el lock vive en `$(git rev-parse --git-common-dir)/saikit-autopilot.lock` —
compartido por todos los worktrees del mismo repo (hallazgo de codex: un lock
por worktree dejaba mergear en paralelo). Protocolo (hallazgo de CodeRabbit:
"ruta" no es "protocolo"): **adquisición atómica por `mkdir`** del directorio
de lock (atómico en MSYS/Windows y Linux; sin `flock`, que no es portable),
que contiene `pid`, `host`, `started_at` y `pr`; **liberación** por `rmdir`
en un `trap EXIT` del script; **lock viejo** = su `pid` no vive en este host
o `started_at` supera N horas ⇒ el script lo **reporta y no mergea**
(fail-closed; nunca lo borra solo); `--liberar-lock` explícito lo quita tras
mostrar su contenido. Caso de contención con dos worktrees del mismo repo en
18.7. Los PRs en paralelo chocan con la memoria
`worktree-compartido-entre-workers`; quedan para una ola posterior.

**D21 — Contrato.** Párrafo "autopilot" (qué hará solo; qué NUNCA: force-push,
borrar datos, mensajes a terceros salvo el reporte autorizado, deploy manual;
**el merge ocurre antes del recibo y solo por `tools/saikit-merge.sh`, nunca
`gh pr merge` a pelo**; `Close:` cita el sha mergeado o la razón exacta de
no-merge). **Sin checks nuevos en el Stop gate**: el control es el script
(D18); el hook solo gana el registro de `veredicto_sha256` (D16), que es
estado, no bloqueo.

**D22 — CI mínimo cuando no hay (Required, 18.8).** El repo típico del vibe
coder NO tiene CI, y con "sin checks ≠ verde" el autopilot nunca mergearía. El
setup detecta la ausencia de workflows y **ofrece en español** scaffoldear un
workflow mínimo de Actions que corre el comando de test del repo + `verify/`
(pinneado, sin secretos). Sin CI y sin aceptar el scaffold, el autopilot lo
dice y no mergea.

**D23 — Medición.** Repo descartable `gon0801/<nombre fijado en 18.1>` con
topic `saikit-descartable` y archivo marcador; tres escenarios en vivo: verde →
merge; CI rojo → no merge con razón; post-merge rojo → revert. Costo por PR
(tokens/tiempo) medido contra la ceremonia actual. Se borra al cerrar **solo
si `gh repo view` muestra el topic y el marcador**, o a mano por el operador
(recomendado).

**D24 — Cerrar el merge a pelo (Recommended, 18.11).** Claude Code sí ofrece
`PreToolUse` (lo que el spec dice es que *nuestro hook* no está registrado
ahí en ningún host). Medir primero que un `PreToolUse` con `decision: deny`
detiene un `Bash` cuyo comando matchea `gh pr merge` / `gh api … /merge` /
`git push … <rama>`. **La autorización del script NO puede ser una variable
de entorno que el script exporte** — `PreToolUse` corre ANTES de que el
comando exista, así que esa marca nunca está en el evento (hallazgo de
CodeRabbit). La regla es por **forma canónica del comando**: el hook deja
pasar únicamente un `tool_input.command` que invoque `tools/saikit-merge.sh`
(o su ruta instalada) y cuyo archivo, leído en ese momento, tenga el sha256
del manifiesto del kit; cualquier otra forma que contenga las órdenes de
merge se niega con razón. Límite declarado: es un match de texto sobre el
comando — un `gh` escondido dentro de otro archivo no es visible; cierra el
camino directo, no todos. Si la medición confirma el deny: registrar la fase
en `settings.json` (el checker `check-hook-registration.sh` pasa de 3 fases a
4, advisory), con caso que niega el directo, caso que deja pasar al script
con hash correcto, caso que niega al script con hash distinto, mutación y
golden. Si no confirma: se declara el límite y se cierra la task con
`unknown`. Es Recommended, no Required: el autopilot funciona sin ella; lo
que cambia es cuánto del límite "el modelo puede mergear a pelo" queda
cerrado en Claude Code.

---

## Clasificación (Required / Recommended / Optional / Reject)

- **Required:** 16.1–16.6, 16.8–16.9; 17.1–17.6; 18.1–18.10.
- **Recommended:** 18.11 (`PreToolUse` que niega el merge a pelo, D24).
- **Optional:** 16.7 (ruteo por tarea → tier); runner extra en `TEST_RUNNER_RE`
  si un repo lo necesita (17.1); aviso por Telegram (18.5); shellcheck.
- **Reject (con razón):** importar las 10 piezas NO del Apéndice A; PRs en
  paralelo (choque de worktree); Graphite/stacks; modo pegajoso (contradice
  Core Rule 3); paneles de 4 modelos (tope de 1 ronda) — un panel = adversary
  + 1 cross-review de otro vendor; leer transcripts para auditar (A6); que el
  líder cambie el carril desde el recibo; `--delete-branch` en el merge;
  config del autopilot leída del working tree; `merge_commit` leído de un JSON
  local para revertir; hacer público el repo para ganar protección de rama
  (decisión del operador, no de este plan).

## Riesgos y límites declarados

- **El gate sigue siendo advisory.** El modelo puede escribir un veredicto
  falso, o correr `gh pr merge` a pelo saltándose el script (D24 intenta
  cerrarlo en Claude Code; en los demás hosts no hay autopilot). El script
  verifica forma + CI + sello del hook, no verdad. El CI es lo independiente
  del modelo; blast ≥ 4 exige un comando que aparezca en
  `harness-evidence.log`.
- **merge = deploy** es `unknown` por defecto ⇒ no merge hasta que el setup lo
  responda. Es la única pregunta técnica que se le hace al usuario, y se le
  hace en palabras simples, una vez por repo.
- **Token de `gh` de usuario completo**: el script acota repo/PR/rama/head
  (D18) y nunca borra nada que no sea la rama remota del PR.
- **Recetas = inyección persistente si alguien las edita**: manifiesto sha256
  en runtime (D1); `test_hook_acl.sh` y `check-hook-registration.sh` se
  extienden a `~/.claude/hooks/recetas/` y a la **lista explícita**
  `~/.claude/skills/{sencillo,saikit-verificar-app,saikit-setup-autopilot}`
  (un glob `saikit-*` dejaba fuera a `sencillo`, hallazgo de grok);
  `hook-acl.ps1` acepta esa lista.
- **Costo:** +1 lane (verify-app) + blast por task ≈ 1.3–1.5× la ceremonia
  actual (estimado, no medido; 18.9 lo mide). Lo que NO sube: sigue una sola
  batería, en CI. Medición de las fases: 6–10 h (D10).
- **Windows-bound:** solo los casos del instalador (16.5, 17.6, 18.7) se saltan
  en CI con `SAIKIT_CI_LINUX=1`; se corren en local y se citan en el cierre
  (excepción de AGENTS.md). `tests/test_verificar_app.sh` (17.1) es portable y
  **sí corre en CI** — no copiar la etiqueta al skip (hallazgo de grok).
- **Hosts:** Phases 16–18 en Claude Code. En los demás hosts el contrato no
  muestra menú (D1), `/sencillo` no existe y el autopilot no existe.
- **Prosa de recetas:** la suite mide el gate, no si el modelo sigue la receta;
  eso lo mide el turno vivo (D10, n=1 por receta). Evals ciegos (`eval` de
  pstack) quedan para cuando haya > 6 recetas.
- **Residual del cross-review, declarado:** grok leyó el diff completo desde el
  repo (el script se lo pasó truncado a 60 K de 95 K); codex lo cubrió entero.
  No hay tercera ronda: lo que quede lo atrapa el turno vivo de cada fase.

## Apéndice A — Triage de pstack (69 piezas)

| Lote | TRAER | SOLO LA IDEA | DESPUÉS | NO |
|---|---|---|---|---|
| Recetas (23) | 6 | 7 | 4 | 6 |
| Principios (20) | 14 | 5 | 1 | 0 |
| Skills de flujo (10) | 1 | 7 | 1 | 1 |
| Skills herramienta + guía (14) | 4 | 4 | 4 | 2 |
| Agentes (2) | 0 | 1 | 0 | 1 |

**Recetas.** TRAER: bug-fix, feature, refactoring, perf-issue, investigation
(fast), prototype (fast). IDEA (cada una con la task que la aterriza):
opening-a-pr (→ D6), babysit + bugbot-triage (→ D17), orchestrate (solo la
plantilla del brief → D6), multi-phase-plan ("Lo que ves" → D6; review gate →
receta `funcion`: una pantalla que cambia una interacción espera el vistazo del
usuario con captura), autonomous-run (predicado de salida + checkpoint; los
descubrimientos se reportan, no se arreglan → receta `cuidar-pr`),
session-pickup ("el rastro previo es autoritativo" → `00-lider.md`), SKILL.md
(dueño del trabajo de subagentes, subagente fresco, nunca inventar link,
primero qué cambia para ti, no narrar en comentarios, "no" es respuesta válida
→ D6/D8/16.4). DESPUÉS: hillclimb, eval, worktree-cleanup (auditor sin
borrar), visual-parity, runtime-forensics. NO: autopilot-full tal cual
(reescrito sin Graphite/cloud como Phase 18), autopilot-stack, shipping
(Graphite), orchestrate (resto), trace-forensics, pause-safely (duplica
`PAUSED`), authoring-a-skill (duplica `writing-skills`).

**Principios.** TRAER (14): laziness-protocol, foundational-thinking,
subtract-before-you-add, minimize-reader-load, experience-first,
exhaust-the-design-space, build-the-lever, model-the-domain,
type-system-discipline, make-operations-idempotent,
migrate-callers-then-delete, prove-it-works, fix-root-causes,
sequence-verifiable-units, never-block-on-the-human,
encode-lessons-in-structure. IDEA (5): redesign-from-first-principles,
boundary-discipline (ya en 3 lugares), separate-before-serializing,
guard-the-context-window, prove-it-works como complemento. DESPUÉS:
outcome-oriented-execution. Tensiones resueltas: unidades verificables vs "una
ceremonia por task" → check enfocado por unidad, ceremonia y batería una vez;
never-block vs "pregunta y espera" → D7; build-the-lever vs "no auto-lances
servidores" → el lever se corre, no se inventa. Agentes: `poteto-agent` NO
(solo la línea "lee los principios antes"); `comment-sicko` → sección del
reviewer.

**Skills de flujo.** TRAER: teach. IDEA: how (formato de salida → Investigar;
exploración con codebase-memory), why (su epistemología → Investigar, D8),
architect (3 reglas → implementer, D5), swarm (skill NO — el tool `Workflow`
ya es la mecánica; idea: las 3 lanes del veredicto), interrogate (4 cubos →
reviewer, D5; consenso entre modelos = alta confianza), figure-it-out (→ D6),
reflect (si un lint lo cumple mejor no escribas prosa; nunca auto-aplicar
cambios a skills → Retro). DESPUÉS: arena. NO: recall (el arranque ya lo
inyecta).

**Skills herramienta + guía.** TRAER: create-verification-skill (→ D11),
show-me-your-work (→ D12), blast-radius (→ D13), bro (→ D8). IDEA: tdd (→
D5 verifier), unslop (5 reglas en español: sin frases de chatbot, sin puffery,
sin adulación, sin conclusiones genéricas, "di qué hace" → `00-lider.md`),
setup-pstack (→ D9), guía ("goal + condición de fin en tus palabras; una
duración no es condición de fin" → guía de usuario, 16.9). DESPUÉS:
maintain-verification-skill, technical-writing, automate-me ("el modo de Gon"
tras la primera ola), typescript-best-practices. NO: no-comments (choca con
"escribe el supuesto en el código"), make-bot-ui (100 % Cursor).

## Apéndice B — Lo que pstack dice del CI y del merge (citas)

- "CI green is an input to a verdict, not a verdict." / "Green is not safe."
- "no owner merges on its own verdict. A swarm of fresh verifiers checks every
  merge-ready head, and only a clean verdict authorizes the merge."
- "The operator's full-autonomy grant plus the root's clean verdict is the
  merge authorization that babysitting alone never has."
- "a duration is not a finish condition."
- Su propia receta de orquestación admite: "this playbook's ceremony turned a
  half-hour 12-unit job into 1 landed unit while a plain agent landed all 12".

## Apéndice C — Qué cambió con las revisiones

**v1 → v2 (validación interna, 43 hallazgos, 12 altos):** `git revert -m 1`
no aplica a squash → `git revert <sha>` (D19); las "dos llaves" eran una →
config leída de `origin/<rama>`, PR que la toca no se auto-mergea, límite
declarado (D15); repo sin CI ⇒ autopilot inalcanzable → D22/18.8 Required;
rastro commiteado después del reviewer invalidaba el SHA → orden explícito
(D12/D16); token de `gh` sin acotar → repo/PR/rama/head del cwd (D18);
veredicto escribible por cualquiera → cruce con estado del hook, merge dentro
del turno (D18); recetas como inyección persistente → manifiesto sha256 en
runtime + ACL (D1); ruta absoluta en el contrato rompía golden → menú sin ruta
+ `SAIKIT_RECETAS_DIR` (D1/D4); `salida` cruda del blast dispara el escaneo →
recortar y redactar (D13); `--delete-branch` falla con worktrees → borrado
remoto aparte (D18); reviewer corre antes del último commit → el líder
commitea antes (D16); `node --test` no acredita → `npm test` (D11); marca en
frontmatter YAML (D2); 18.6 dependía de una task opcional → 16.6 Required;
casos del instalador Windows-bound declarados; "run aún no creado" ⇒ `unknown`
(D19); `veredictos/` y lock gitignored (D16); regrabados de golden declarados
(D4); baseline de lint nombrada; linter con términos prohibidos (D2); ideas
del triage aterrizadas (Apéndice A); guía de 3 palabras (D3); costo de
medición declarado (D10); framework nuevo con sí explícito y pin (D11);
redacción de tokens (D12); revert solo del merge propio (D19); `salud_url`
acotada (D19); `gh repo delete` solo con topic + marcador (D23); DoD Yes/No;
17.1 sin depender del instalador; CRLF tolerado; `/sencillo` fuera de alcance
en otros hosts; protección de rama como alternativa rechazada.

**v2 → v3 (Greptile P1 + cross-review codex y grok, 1 + 8 + 14 hallazgos):**
el revert exigía estado del hook que el turno desarmado no tiene → modo
`--revert-de` con precondiciones propias (D19, Greptile); el veredicto se
podía reescribir tras el `Write` del reviewer → sello `veredicto_sha256` en el
estado del hook (D16, codex+grok alta); `merge_commit` plantable en JSON local
→ trailer `Saikit-Merge:` en el squash + revert solo de la punta de
`origin/<rama>` (D18/D19, codex+grok); `origin/<rama>` sin fetch y base no
fijada → `git fetch` obligatorio + `merge-base --is-ancestor` (D18, codex);
"el script ES la protección" era falso → "vía sancionada", límite declarado y
D24/18.11 Recommended con `PreToolUse` (grok alta); lock por worktree →
`git-common-dir` (D20, codex); `verify_app: n/a` mergeaba y una suite unitaria
contaba como Drive → `sin_verify_app` explícito + Drive bajo `verify/`
(D11/D15/D18, codex+grok); blast sin patrones de token → `redactar.sh`
compartido + familia del hook extendida (D12/D13, codex); manifiesto de 7 con
6 medidas → columna `tipo`, `00-lider` referenciado, no ofrecido (D1/D10,
codex+grok); frontmatter roto con hash válido → validación en generación (D1,
grok); hash distinto entre Windows y Linux → `.gitattributes eol=lf` para
`recetas/**` (D1, grok); `/sencillo` fuera del glob de ACL → lista explícita
(Riesgos, grok); el alias bajaba el carril sin fijar la receta → el alias
nombra la receta y el contrato lo dice (D3, grok); D7 vs D21 en el mismo
heredoc → excepción escrita para lo autorizado en el setup (D7, grok); "solo
commits de la task" sin forma de observarlo y "autor ajeno" ambiguo →
definidos por `user.email`/cuenta de gh y autor del PR (D18, grok); DoD de
`boundary` por palabra → por encabezado (D5, grok); 17.1 no es Windows-bound
(Riesgos, grok); `mergeable: UNKNOWN` diferido → reintento único y medición en
18.1 (D18, grok); `cat $lista` sin comillas en el test → array (codex).
