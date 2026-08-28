# Phases 16–18 — El recetario y el autopilot (super plugin de vibe coding): diseño

Fecha: 2026-08-28. Origen: `cursor/plugins` → `pstack` (poteto-mode), licencia
MIT — se copia y adapta con atribución. Triage de las 69 piezas leídas una por
una (23 recetas, 20 principios, 24 skills/agentes/guía) en el Apéndice A.
Validación de equipo (`team_validation_mode: subagent`): tres revisores
independientes — Producto+Escéptico (15 hallazgos), Arquitectura+QA (16),
Seguridad (12) — integrados en la v2 de este documento; el registro de qué
cambió está en el Apéndice C.

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
  el recibo.
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
- Una ceremonia por task; **la batería completa corre UNA vez, en CI**; nunca
  la suite completa local (memoria `harness-lento-causas-y-topes`: la task de
  4 h fue 3 rondas de review + suite por fase, no el CI, que tarda 7–9 min).
- Tope de cross-review: 1 ronda (2 solo si la primera halló severidad alta).
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
menú sale de **`recetas/MANIFEST.sha256`** (una línea por receta:
`sha256  nombre  carril  título`), generado en el repo por
`tools/gen-recetas-manifest.sh` y candado por test (manifest == archivos). En
runtime el hook lee el manifiesto y **solo ofrece las recetas cuyo sha
coincide con el archivo instalado**; una receta ausente, con hash distinto o
con frontmatter roto se omite con aviso — fail-open del turno, fail-closed de
la receta. Sin manifiesto o sin directorio: línea fija y el turno sigue como
hoy. Nada de parseo de frontmatter en runtime (el hook ya paga ~28 ms por fork
en MSYS). Los otros hosts entran después por la vía de los perfiles.

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
`Understand`/`Implement`/`Verify`). El linter `tests/test_recetas.sh` exige
frontmatter completo, tope de líneas, carril válido, links que resuelven,
tolera CRLF, y **rechaza términos prohibidos** (`gt `, `Graphite`, `Bugbot`,
`AskQuestion`, `/loop` de Cursor, `poteto`) con un fixture rojo — así el
`[tdd:required]` de una receta discrimina contenido, no solo forma.

**D3 — El carril lo fija el sentinel, no la receta.** Medido en el hook: en un
turno `-saikit` pleno el Stop exige los tres roles aunque el recibo diga "sin
cambio de código"; la única escotilla es `ROLE FALLBACK`, que es para fallas de
infraestructura. Investigar y Boceto son de solo lectura y piden `fast`. Reglas:

- `-saikit` = full; `-saikit:fast` = fast (hoy). **Nuevo, Required (16.6):**
  los alias en español `-saikit:pregunta` y `-saikit:boceto` mapean a `fast`
  (match exacto con frontera, como `:fast`; un typo cae a full — límite
  declarado, mismo que 10.1). Es un cambio de DETECCIÓN del carril, no del
  Stop gate; lleva rojo medido, caso, mutación y golden. Es Required porque
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
previstos en estas fases: 16.4, 17.3, 18.3, 18.6 (cuatro), cada uno con diff
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
consolida, no se suma.

**D6 — Principios del líder + brief → `recetas/00-lider.md`.** Los 4 del líder
(experience-first, exhaust-the-design-space, never-block-on-the-human con la
frontera de lo irreversible, encode-lessons-in-structure), la plantilla del
brief para delegar (GOAL / SCOPE / CONTEXT / ACCEPTANCE / VERIFY / TIMEBOX /
FORBIDDEN / REPORT, de `orchestrate`; REPORT incluye **"Lo que ves"**: el
resultado observable en palabras simples, de `multi-phase-plan`), las **5
secciones de la descripción del PR** (Why / Scope / Tradeoffs / Blast radius /
Verification, de `opening-a-pr`; nunca draft; PRs chicos), y "done como
predicado falsable; lo más incierto primero" (de `figure-it-out`). El contrato
lo referencia en la regla de delegación; no se pega entero.

**D7 — Regla fusionada de preguntar.** Se EDITA (no se agrega) el bloque
"Missing-information rule" del contrato para que tenga dos ramas explícitas:
técnico/reversible → decide y presenta el resultado; producto/irreversible
(force-push, borrar datos, mensajes a terceros, deploy, pagos) → pregunta en
palabras simples y cierra con `PAUSED`. Y la regla de `pstack`: "un factual que
se observa corriendo algo no es pregunta para el humano: boceto".

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
`docs/smoke-recetas-<fecha>.md`. Receta sin turno vivo no entra al menú (queda
en `recetas/pendientes/`). **Costo declarado:** 11 turnos vivos con ceremonia
(6 + 2 + 3) a 30–60 min ≈ 6–10 h de medición en total; se permite medir hasta
3 recetas por sesión en el mismo repo descartable. No se afirma que "el modelo
sigue la receta" desde la no-observación.

**Recetas de la primera ola (6):** `bug`, `funcion`, `refactor`, `lento`,
`investigar` (fast), `boceto` (fast). `cuidar-pr` va en Phase 18.

---

## Phase 17 — Verificación real y rastro

**D11 — `verificar-app`.** Skill de kit a nivel usuario
(`~/.claude/skills/saikit-verificar-app/`) que GENERA en el repo del usuario un
`verify/` con `LEEME.md` (mapa de 3–5 funciones en español: "entrar", "crear
X", "ver la lista") y los pasos Launch / Doctor / Drive / Evidence / Cleanup.
**Drive es una prueba e2e en el framework que el repo ya tiene**, invocada
siempre por un comando que `TEST_RUNNER_RE` acredita — medido: `npm test`,
`pnpm test`, `vitest`, `jest`, `playwright test`, `pytest` sí; **`node --test`
NO** (se envuelve como `npm test`). Así la corre CI (batería una vez) y el hook
la acredita sin cambios. Si el repo no tiene framework, el generador **pide un
sí explícito al usuario** en palabras simples antes de instalar el más liviano
que la plataforma ya soporte (capability-first), con versión pinneada en el
lockfile del repo, nunca `npx <pkg>@latest`; si no acepta, `verify/` se genera
con Drive "manual, pendiente" y `verify_app: n/a` declarado. Se ejecuta **una
vez antes de entregar**. Se funde con el skill `run` de la sesión: `run`
arranca y mira; `verificar-app` deja el procedimiento escrito y probado. Si
aparece un runner fuera del regex, se agrega con TDD (Optional).

**D12 — Rastro de decisiones.** `.saikit/decisiones/<task>.tsv`, columnas
`cuando | etapa | decision | por_que | evidencia | resultado`, en español
llano; lo escribe el líder en cada gate con `tools/saikit-decision.sh` (append
seguro; redacción con los patrones del hook **más** las formas de token
conocidas — `ghp_`, `github_pat_`, `gho_`, `sk-`, `AKIA`, `xox[bp]-` — que el
`redact_secrets` actual no cubre, medido). `Close:` cita la ruta y una sección
**Atención** con las filas cuyo `resultado` ≠ ok. **Se commitea ANTES de
despachar al reviewer** (D16: cualquier commit posterior cambia el SHA del
veredicto); `.saikit/` no entra a la allowlist de gitleaks. El adversary,
cuando corre, lee el tsv y reporta "afirmación sin evidencia". **No se leen
transcripts** (A6/privacidad).

**D13 — Blast radius.** Paso del verifier "el hecho único": nombra el hecho por
el que el cambio es seguro, lo prueba **corriendo** algo, y asigna nivel
1 (afirmado) · 2 (leído en código) · 3 (test existente) · 4 (corrido a
propósito: script o test nuevo) · 5 (corrido en la superficie real).
Artefacto `.saikit/findings/blast-<task>.json` (`hecho`, `comando`, `salida`,
`nivel`); `salida` **recortada a N líneas y redactada** antes de escribir —
`findings/` está dentro del escaneo de secretos por sesión (13.4) y una salida
cruda con `token=` dispararía un GATE falso. Verificado: el candado post-hoc
del adversary solo aplica a eventos con rol adversary, así que el verifier
puede escribir ahí sin violación (anotado para que nadie lo re-diagnostique).
`findings/` es gitignored por el hook: el blast es evidencia **local** que
`saikit-merge.sh` lee en la misma sesión, no evidencia del PR — declarado. El
reviewer adjudica (nivel ≥ 4 sin `comando` ⇒ malformado). En autopilot, nivel
≥ 4 es precondición del merge (D18).

**D14 — Voz en `Close:`.** Primero qué cambia para el usuario, luego cómo,
luego por qué; diagrama mermaid opcional (Artifact lo renderiza nativo).

---

## Phase 18 — El autopilot

**D15 — Autorización: una llave humana + una config versionada, y el límite
declarado.** (1) Sentinel `-saikit:autopilot` → carril full + `autopilot=1` en
el estado (Core Rule 3: explícito, no inferido). Es la **única llave
independiente del modelo**: la teclea el humano. (2) Config por repo
`.saikit/autopilot.json` — `{ "merge": true, "merge_despliega": "unknown",
"salud_url": null, "revert_si_rojo": true, "rama": "master" }` — creada por
`saikit-setup-autopilot` con tres preguntas en español (¿mergear solo?
¿mergear a `<rama>` publica la app? ¿hay una URL para checar que sigue viva?).
**El script la lee SOLO de `origin/<rama>`** (`git show
origin/<rama>:.saikit/autopilot.json`), nunca del working tree ni del head del
PR; un PR que toque ese archivo **nunca se auto-mergea**. Con
`protected_branch_push: deny`, cambiarla exige un PR mergeado por el humano.
Límite declarado (hallazgo de los tres revisores): el modelo tiene `Write` y
`gh`; el gate es advisory; lo que impide que el modelo se auto-autorice en el
mismo turno es esta lectura desde `origin/<rama>` + el deny, no una barrera
criptográfica. Sin config, o con `merge_despliega: "unknown"`, no se mergea.

**D16 — Veredicto atado al SHA: el líder commitea antes del reviewer.** Orden
del turno autopilot: implementer → verifier (+ `verify/`, blast) → adversary
(si aplica) → **el líder commitea todo, incluido el rastro** → reviewer, que
graba `sha = git rev-parse HEAD` en `.saikit/veredictos/<sha>.json`: `{ sha,
pr, verifier: PASS|FAIL, verify_app: PASS|FAIL|n/a, blast: {nivel, hecho,
comando}, adversary: {findings, max_sev}|n/a, reviewer: clean|findings,
decisiones: ruta }`. Un fix tras la revisión = commit nuevo = SHA nuevo =
veredicto nuevo (coherente con la línea `Close:` "¿se tocó código después del
reviewer?"). Sin excepción por `patch-id` en la primera ola. `veredictos/` y
el lock son **gitignored siempre** (el hook crea el `.gitignore`, como en
`findings/`). El reviewer tiene `Write` (medido en su perfil); el que
distingue quién escribió el archivo es D18, no la convención.

**D17 — Receta `cuidar-pr`** (de `babysit` + `bugbot-triage`): declarar el modo
(revisar / cuidar / solo-hilos); orden conflictos → hilos → CI; clasificar un
CI rojo antes de reintentar (flake → un build fresco y solo uno; base vieja →
merge de master en la rama, memoria `rebase-choca-en-deploy-log-usar-merge`;
bug real → commit); triage de Greptile/CodeRabbit con la rúbrica
fix / dismiss / ask y patrones aprendidos en `.saikit/triage-patrones.md`;
esperas SIN bloquear (Monitor + heartbeat largo, nunca un segundo sleep loop;
antes de esperar, checar si ya terminó); tope 2 rondas; **cuidar nunca
autoriza mergear** — eso es D18.

**D18 — `tools/saikit-merge.sh`, fail-closed y acotado.** Segunda excepción
declarada al fail-open (la primera es el instalador): mergear es la acción que
no admite "dejar pasar". **Alcance acotado, nunca argumento libre:** repo =
`gh repo view --json nameWithOwner` del cwd; PR = el de la rama actual (`gh pr
view --json number,baseRefName,headRefOid,author`); exige `baseRefName ==
config.rama` y `headRefOid == sha del veredicto`. Precondiciones, TODAS
observadas: PR `mergeable`; CI del head concluido en `success` (`gh pr checks`
+ run del workflow; "no hay checks" ≠ verde; forma real medida en 18.1);
veredicto para ESE sha con `verifier: PASS`, `blast.nivel ≥ 4`, `reviewer:
clean`, `verify_app: PASS` o `n/a` declarado; **cruce con el estado del hook
de la sesión** (Required, no opcional): `agents_seen` contiene `reviewer`, el
`Write` de `veredictos/<sha>.json` está atribuido a un evento del rol reviewer
(misma maquinaria de atribución que el candado del adversary) y el `comando`
del blast aparece en `harness-evidence.log` con éxito — por eso **el merge
corre DENTRO del turno armado, antes del recibo** (el cierre limpio borra ese
estado); `git log origin/<rama>..HEAD` solo commits de la task; config de D15
válida. Entonces `gh pr merge --squash --match-head-commit <sha>` (medido: `gh`
2.88 lo soporta; pinea el SHA). **Sin `--delete-branch`**: tras el merge `gh`
intenta borrar la rama local y hacer checkout de la default, que falla cuando
master vive en otro worktree (flujo de este repo) DESPUÉS de haber mergeado;
la rama remota se borra como paso aparte e idempotente (`git push origin
--delete <rama>`), y "merge ok + borrado falla" se reporta sin reintentar el
merge. Nunca `--admin`, nunca force. Cualquier `unknown` ⇒ no mergea y dice
cuál. El script registra `merge_commit` en el veredicto (lo usa D19). 18.1
mide además si `gh pr merge` pasa el runtime floor sin prompt humano: un
autopilot que pide confirmación en cada merge no es autopilot.
**La protección de rama de GitHub no está disponible en este repo** (privado,
plan free: 403 medido). Alternativa rechazada con razón: hacer el repo público
la habilita gratis, pero es una decisión del operador sobre visibilidad, no de
este plan ⇒ el script ES la protección; `protected_branch_push: deny` sigue.

**D19 — `tools/saikit-postmerge.sh`.** Corre en un turno **desarmado** (el
turno autopilot cierra con recibo citando el sha; un Monitor de fondo
despierta al modelo cuando el CI de la rama termina — el script no necesita
estado del hook: solo el `merge_commit` del veredicto). Identifica el run con
`gh run list --commit <merge_commit>` (verificado en `gh` 2.88); **sin run
todavía ⇒ `unknown`, espera con heartbeat acotado; timeout ⇒ reporta
`unknown`, NO revierte**. `GET salud_url` si existe: solo `http(s)`, sin
seguir redirects, `--max-time`, y la URL pasa por redacción antes de escribirse
en cualquier lado. En rojo → **`git revert <merge_commit>`** (squash: no hay
`-m`), **solo del merge que él mismo registró**, PR de revert que pasa por el
MISMO `saikit-merge.sh` (CI verde + `--match-head-commit`), una sola
profundidad (un revert rojo se reporta, no se re-revierte). Mensaje al usuario
en español (qué aterrizó, qué cambia para él, cómo deshacerlo) armado desde el
`Close:` ya redactado, ≤ 4096 chars; `telegram-send` opcional.

**D20 — En serie.** Un PR a la vez por repo (`.saikit/autopilot.lock`,
gitignored). Los PRs en paralelo chocan con la memoria
`worktree-compartido-entre-workers`; quedan para una ola posterior.

**D21 — Contrato.** Párrafo "autopilot" (qué hará solo; qué NUNCA: force-push,
borrar datos, mensajes a terceros salvo el reporte, deploy manual; el merge
ocurre antes del recibo; `Close:` cita el sha mergeado o la razón exacta de
no-merge). **Sin checks nuevos en el Stop gate**: el control es el script (D18).

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

---

## Clasificación (Required / Recommended / Optional / Reject)

- **Required:** 16.1–16.6, 16.8–16.9; 17.1–17.6; 18.1–18.10.
- **Optional:** 16.7 (ruteo por tarea → tier); runner extra en `TEST_RUNNER_RE`
  si un repo lo necesita (17.1); aviso por Telegram (18.5); shellcheck.
- **Reject (con razón):** importar las 10 piezas NO del Apéndice A; PRs en
  paralelo (choque de worktree); Graphite/stacks; modo pegajoso (contradice
  Core Rule 3); paneles de 4 modelos (tope de 1 ronda) — un panel = adversary
  + 1 cross-review de otro vendor; leer transcripts para auditar (A6); que el
  líder cambie el carril desde el recibo; `--delete-branch` en el merge;
  config del autopilot leída del working tree; hacer público el repo para
  ganar protección de rama (decisión del operador, no de este plan).

## Riesgos y límites declarados

- **El gate sigue siendo advisory.** El modelo puede escribir un veredicto
  falso; el script verifica forma + CI + atribución en el estado del hook, no
  verdad. El CI es lo independiente del modelo; blast ≥ 4 exige un comando
  que aparezca en `harness-evidence.log`.
- **merge = deploy** es `unknown` por defecto ⇒ no merge hasta que el setup lo
  responda. Es la única pregunta técnica que se le hace al usuario, y se le
  hace en palabras simples, una vez por repo.
- **Token de `gh` de usuario completo**: el script acota repo/PR/rama/head
  (D18) y nunca borra nada que no sea la rama remota del PR.
- **Recetas = inyección persistente si alguien las edita**: manifiesto sha256
  en runtime (D1); `test_hook_acl.sh` se extiende a `recetas/` y
  `~/.claude/skills/saikit-*`; `check-hook-registration.sh` reporta ACE ajenos.
- **Costo:** +1 lane (verify-app) + blast por task ≈ 1.3–1.5× la ceremonia
  actual (estimado, no medido; 18.9 lo mide). Lo que NO sube: sigue una sola
  batería, en CI. Medición de las fases: 6–10 h (D10).
- **Windows-bound:** los casos del instalador (16.5, 17.1, 18.7) se saltan en
  CI con `SAIKIT_CI_LINUX=1`; se corren en local y se citan en el cierre
  (excepción de AGENTS.md).
- **Hosts:** Phases 16–18 en Claude Code. En los demás hosts el contrato no
  muestra menú (D1), `/sencillo` no existe y el autopilot no existe.
- **Prosa de recetas:** la suite mide el gate, no si el modelo sigue la receta;
  eso lo mide el turno vivo (D10, n=1 por receta). Evals ciegos (`eval` de
  pstack) quedan para cuando haya > 6 recetas.

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

## Apéndice C — Qué cambió con la validación de equipo (v1 → v2)

Integrados (43 hallazgos, 12 altos, 0 rechazados sin razón):

- **Altos:** `git revert -m 1` no aplica a squash → `git revert <sha>` (D19);
  las "dos llaves" eran una → config leída de `origin/<rama>`, PR que la toca
  no se auto-mergea, límite declarado (D15); repo sin CI ⇒ autopilot
  inalcanzable → D22/18.8 Required; rastro commiteado después del reviewer
  invalidaba el SHA → orden explícito (D12/D16); token de `gh` sin acotar →
  repo/PR/rama/head del cwd (D18); veredicto escribible por cualquiera → cruce
  con estado del hook, Required, merge dentro del turno (D18); recetas como
  inyección persistente → manifiesto sha256 en runtime + ACL (D1); ruta
  absoluta en el contrato rompía golden → menú sin ruta + `SAIKIT_RECETAS_DIR`
  (D1/D4); `salida` cruda del blast dispara el escaneo de secretos → recortar y
  redactar (D13); `--delete-branch` falla con worktrees tras mergear → borrado
  remoto aparte (D18); reviewer corre antes del último commit → el líder
  commitea antes (D16); `node --test` no acredita → envuelto en `npm test`
  (D11).
- **Medios:** marca en frontmatter YAML para reutilizar el instalador (D2);
  18.6 dependía de una task opcional → 16.6 Required y depends corregidos;
  casos del instalador no corren en CI → Windows-bound declarado; "run aún no
  creado" ⇒ `unknown` (D19); `veredictos/` y lock gitignored (D16); 4
  regrabados de golden declarados (D4); baseline de lint bash nombrada;
  `[tdd:required]` sobre markdown → linter con términos prohibidos (D2); ideas
  del triage sin task → cada una aterrizada (Apéndice A); 5 sentinels → la
  guía enseña 3 palabras (D3); costo de medición declarado (D10); framework
  nuevo exige sí explícito y pin (D11); redacción de tokens `ghp_`/`sk-`/…
  (D12); revert solo del merge propio y por el mismo script (D19);
  `salud_url` acotada (D19); `gh repo delete` solo con topic + marcador (D23);
  skills con marca + hash + ACL (Riesgos).
- **Bajos:** DoD Yes/No en 16.3/16.9/17.6; 17.1 ya no depende del instalador;
  CRLF tolerado; `/sencillo` fuera de alcance en otros hosts; protección de
  rama anotada como alternativa rechazada; archivar Phase 15 al cerrar 16.
