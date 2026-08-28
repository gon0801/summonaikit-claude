# summonaikit-claude — Plans.md

Creado: 2026-08-08
Alcance: hacerse cargo del hook que gatea cada turno y llevar la misma fuente a
los hosts aprobados — Claude Code, zcode, Codex y Grok Build— con pruebas
propias, instalación controlada y cierre de los agujeros que hoy lo vuelven un
control decorativo. Contrato de producto y premisas medidas:
`docs/spec/00-project-spec.md`.

**Contrato de datos:** `not_observed != absent`. Lo que no se pudo observar se
marca `unknown`, nunca se afirma como ausente.

---

Fases 0-14 cerradas: ver docs/plans-archivo.md — movidas 2026-08-25 (0-12) y 2026-08-28 (13-14), higiene del tope de 200 lineas. La Clasificacion del alcance y la Validacion del plan original tambien viven alla.

## Phase 15 — summonaikit en dsh, el DeepSeek Harness (2026-08-27)

**Propósito:** el operador quiere el gate en el harness de DeepSeek — `dsh`
(`@deepseek-ai/dsh` 0.1.1-rc.2), NO el shim `deepseek` (que es Claude Code y ya
lo tiene). dsh no tiene hooks de shell: es un harness de plugins cordis con
`agent/pre-step`, `agent/turn-stopping`, `tools/*` y subagentes por `persona`.
Decisión: un **adaptador JS** que traduce esos eventos a los payloads del hook
existente y lo ejecuta con `SUMMONAIKIT_HOOK_TARGET=dsh` — una sola fuente de
verdad, el port es delgado. Diseño: `docs/phase-15-dsh-host-design.md`; plan
paso a paso: `docs/phase-15-dsh-host-plan.md`. Alcance medido: solo la UI web.

| Task | 内容 | DoD | Depends | Status |
|------|------|-----|---------|--------|
| 15.1 | `[Medición]` `[lane:gate]` `[tdd:skip:medición]` **Captura de payloads reales de dsh.** Plugin espía en un profile desechable; un turno vivo con `-saikit` y delegación; tabla observado/ausente/`unknown` para las 7 preguntas (texto del usuario en `pre-step`, persona en `subagent`, tools de fs y su campo de ruta, texto final del asistente, `SessionId`/cwd, JSONL de sesión, `AGENTS.md`); fixtures redactados en `tests/fixtures/dsh/` | Las 7 preguntas con cita o `unknown`; sin secretos; el espía no queda instalado | — | cc:完了 [PR #84, merge `5c4a37d`] — **CIERRE**: `docs/task-15.1-medicion-dsh.md` con 8 preguntas (7 + redacción) citadas o `unknown`; corrigió 4 hipótesis del diseño (la persona NO viene en `arguments`; la tool de edición es `edit`; el texto vive en `event.data.message`; el JSONL de sesión es zstd → sin `transcript_path`); fixtures redactados (0 hits verificados por el lead). Cross-review: 2 rondas (codex, qwen) |
| 15.2 | `[Gate]` `[lane:gate]` `[tdd:required]` **`HOST=dsh` en el hook** por `SUMMONAIKIT_HOOK_TARGET=dsh` (D2, como codex); estado en `state/dsh/`; cada rama por host decide dsh explícitamente; `saikit_host_ciego()` intacto salvo medición (D7) | Rojo medido; `caso_g1_dsh_arma_y_aisla_estado` + `_no_se_hereda_sin_target`; G2 ceremonia cierra / sin recibo bloquea; mutación `host_dsh_no_reconocido`; golden 0 divergencias | 15.1 | cc:完了 [PR #85, merge `3c3b71f`; fix del lead PR #92, `3327710`] — **CIERRE**: rama `HOST=dsh` por target, `TOOL_HINT` "the subagent tool", ceremonia en `claude|codex|grok|dsh`; 6 casos dsh (G1×3, G2×2, G3×1) y 3 mutaciones (`host_dsh_no_reconocido`, `tool_hint_sin_dsh`, `ceremonia_sin_dsh`) — poder discriminante medido por el lead: cada mutación pone rojo SOLO a su caso. **Incidente:** el PR se mergeó con `suite` en ROJO — tres mutaciones viejas ancladas al `case` de la ceremonia quedaron obsoletas y la guardia lo atrapó en CI; master rojo desde `3c3b71f` hasta el #92 |
| 15.3 | `[Adaptador]` `[lane:gate]` `[tdd:required]` **`hosts/dsh/` = `@summonaikit/dsh-gate`**: `translate.js` (4 traducciones, puro), `spawn-hook.js` (bash + stdin + timeout, fail-open), `index.js` (listeners; bloqueo → `agent.followup`); banco `node --test` con dsh falso y hook falso; CI | Casos: arma / no arma / bloquea-y-encola / cierra / hook ausente / no-JSON / timeout; sin reglas del gate en JS | 15.1 | cc:完了 [PR #86, merge `7b9680b` (huérfano: el contenido `41c77da`…`97d773e` entró a master por el merge local `d49efea`)] — **CIERRE**: `translate.js`/`spawn-hook.js`/`index.js`, 25 tests (`node --test`, job `node-adapter` en CI) incluidos cola por sesión, `sessionKey` única, fail-open, y dos gaps hallados en vivo — subagentes en sesión propia re-acreditados a la madre (Gap1) y `turn-stopping` intermedio diferido mientras hay hijos vivos (Gap2). Rol inferido del texto cuando la tool es `subagent` a secas (límite declarado en el spec). **Proceso:** 4 rondas de cross-review (tope: 2) |
| 15.4 | `[Instalador]` `[lane:gate]` `[tdd:required]` **`--host dsh`**: hook a `~/.dsh/hooks/`, plugin a `~/.dsh/plugins/`, entrada entre marcas en `~/.dsh/cordis.patch.yml`, personas con marca; `--dry-run` que no escribe; `--quitar-dsh`; checker `--dsh-home`; fila `dsh` vacía del router | 7 casos del instalador (limpio / dry-run / ajeno intacto / repara / quitar / sin bash / versión distinta reporta) + 3 del checker + 1 del router | 15.2, 15.3 | cc:完了 [`fc29fff`, `7290310`, `68663fc` (PRs #87–#89 cerrados sin mergear, entraron por `d49efea`) + PR #91 `d05284d`] — **CIERRE**: `--host dsh` (hook, plugin como dir real en `~/.dsh/profiles/node_modules/@summonaikit/dsh-gate/` — no en `plugins/`: dsh resuelve por nombre de paquete —, patch entre marcas con rutas Windows vía `cygpath -m`, 4 personas inline como instancias `subagent_<rol>`), `--dry-run`, `--quitar-dsh`, checker `--dsh-home`, fila `dsh` del router; 13 casos del instalador + 7 del checker. Los dos bugs de rutas los halló el turno vivo, no los tests (que usaban `SAIKIT_DSH_HOME` Windows) — declarado |
| 15.5 | `[Release]` `[lane:release]` `[tdd:skip:docs-y-vivo]` **Turno vivo + docs + deploy**: 3 escenarios en la UI web con transcript (arma y cierra / sin recibo bloquea y vuelve / sin `-saikit` byte-idéntico); spec § host dsh; fila dsh en `agents/adversary.md`; README; deploy-log | Evidencia literal de los 3; spec/perfil/README coherentes con el instalador | 15.4 | cc:完了 con límite declarado [`ebff9c8` (PR #90 cerrado, entró por `d49efea`) + smoke en PR #91] — **CIERRE**: spec § "Host dsh (Phase 15)" + límites, README, fila dsh en `agents/adversary.md`, `docs/task-15.5-runbook.md`, `docs/smoke-dsh-2026-08-28.md`. **El turno vivo del worker se corrió en `headless`**: escenarios 1 y 3 ✅; el 2 (GATE por recibo ausente) NO se reprodujo. **UI web (2026-08-28 07:18, operador, leído por el lead del `session.jsonl.zstd`)**: escenario 1 ✅ medido — contrato inyectado (el modelo lo dice literal en su `reasoning`), `subagent_implementer` → `_verifier` → `_reviewer` → `_adversary` (artefacto con esquema del contrato, 0 findings) → adjudicación → recibo con `ADVERSARY:`; escenario 3 ✅ (turnos sin `-saikit` sin ningún marcador); **escenario 2 (GATE en la UI) sigue `unknown`** — sin ningún followup del adaptador en 28 turnos; cubierto por la suite del hook y el banco del adaptador. Deploy ejecutado por el worker fuera del proceso; verificado y firmado por el lead en `docs/deploy-log.md` (2026-08-28) |
| 15.6 | `[Release]` `[lane:release]` `[tdd:skip:docs]` **Cierre del ledger** (y archivo de Phase 13 si `Plans.md` pasa de 200 líneas) | Filas cerradas con sha/PR | 15.5 | cc:完了 [PR de cierre del lead, 2026-08-28] — **CIERRE**: filas 15.1–15.5 con sha/PR; límites nuevos en el spec (rol por texto, `meta.cwd`, UI web sin medir); deploy-log firmado; `Plans.md` bajo las 200 líneas (sin archivar). **Retro de proceso de la fase:** (1) un PR mergeado con `suite` en rojo dejó master rojo un día; (2) 15.4/15.5 entraron por merge local + push directo (PRs #87–#90 cerrados) y el merge del #86 quedó huérfano — `protected_branch_push` pasa a `deny` (lo cambia el operador: ruta protegida) y se pide protección de rama en GitHub; (3) 4 rondas de cross-review en 15.3 (tope 2); (4) el deploy lo hizo el worker (lo reservaba el lead); (5) alcance movido a `headless` sin pedirlo |

**Fuera de alcance, declarado:** `headless`/`tui` (profiles no instalados), el
shim `deepseek` (Claude Code, ya cubierto), reglas nuevas del gate, y cualquier
cosa que 15.1 no haya observado.

---

## Phase 16 — El recetario (2026-08-28)

**Propósito:** encima del gate — que sigue midiendo lo mismo — un recetario por
tipo de tarea que el **líder elige y declara en el recibo**, con principios por
rol en los perfiles y la voz para un usuario que no lee código ni inglés.
Origen: pstack (MIT), triage de 69 piezas. Diseño y decisiones D0–D23 (v2,
validada por 3 revisores): `docs/phase-16-18-recetario-autopilot-design.md`; plan paso a paso para
workers: `docs/phase-16-recetario-plan.md` (implementa DeepSeek; el lead
revisa, cierra y despliega). Host de la primera ola: Claude Code. **El carril
lo fija el sentinel, nunca la receta** (D3, medido). Lint bash baseline:
`tests/lib/check_syntax.sh`.

| Task | 内容 | DoD | Depends | Status |
|------|------|-----|---------|--------|
| 16.1 | `[Diseño]` `[lane:fast]` `[tdd:skip:docs]` **Diseño + spec delta.** `docs/phase-16-18-recetario-autopilot-design.md` (D0–D23 + Apéndices A–C) y § "Ampliación — Phases 16–18" del spec; Phases 13–14 archivadas; validación de equipo con 3 revisores (43 hallazgos integrados) | Cada decisión cita su medición o `unknown`; spec y diseño coherentes; `test_plans_ledger` verde; `Plans.md` ≤200 líneas | — | cc:完了 [PR #95, merge `dd37809`] — **CIERRE**: diseño v3 (D0–D24, Apéndices A–C) + spec § Ampliación (8 reglas + límites + Non-Goals); Phases 13–14 archivadas; validación interna de 3 revisores (43 hallazgos) + Greptile P1 + cross-review externo **codex y grok en paralelo** (22) + CodeRabbit (9): 75 hallazgos, todos integrados o rechazados con razón (Apéndice C). Incidente del PR: `test_adversary_artifact_contract` se puso rojo en CI al archivar la fila 14.3 (ancla a `Plans.md`); corregido en `b5716c1`/`1d455f3` (el ancla sigue al ledger archivado y valida SOLO la fila 14.3, con 4 casos sintéticos). 事前確認 aprobado por el operador el 2026-08-28 y registrado en `.claude/state/plan-preapprovals.json`. Deploy no-op (docs-only), ver `docs/deploy-log.md` |
| 16.2 | `[Recetario]` `[lane:fast]` `[tdd:required]` **`recetas/` fuente**: `00-lider.md` (4 principios del líder, brief de 8 campos con "Lo que ves", 5 secciones del PR, regla de preguntar en dos ramas, "rastro previo autoritativo") + 6 recetas en español ≤80 líneas con frontmatter YAML (`saikit_owned`, D2): `bug`, `funcion`, `refactor`, `lento`, `investigar` (fast, con voz `teach` y epistemología de `why`), `boceto` (fast); `tools/gen-recetas-manifest.sh` → `recetas/MANIFEST.sha256` (campos separados por TAB: `sha256`, `tipo` `receta`\|`lider`, `nombre`, `carril`, `titulo` al final; título sin TAB ni salto) y que corre el linter antes de incluir; `.gitattributes`: `recetas/** text eol=lf` (hash igual en Windows y Linux); linter `tests/test_recetas.sh` escrito ANTES que las recetas | Linter rojo con fixture rota / con término prohibido (`Graphite`, `Bugbot`, `gt` seguido de espacio, `AskQuestion`, `/loop` de Cursor) / con manifiesto desactualizado / con `00-lider` marcado `receta` / con TAB en el título; verde con 6 recetas + lider + manifiesto, incluido un título de varias palabras que se lee entero; tolera CRLF en lectura; cada receta trae Pasos / Qué le dices al usuario / Recibo; el hash del manifiesto coincide en CI Linux y en local Windows | 16.1 | cc:TODO |
| 16.3 | `[Perfiles]` `[lane:fast]` `[tdd:skip:prompt-only]` **Principios por rol en `agents/*.md`** (D5): implementer (9 + 3 reglas de `architect`), reviewer (4 + "comentarios y supresiones" + 4 cubos de adjudicación), verifier (prove-it-works complemento + "mejor ningún test que uno malo, declarado" + regla de redacción antes de escribir), adversary (idempotencia); `boundary-discipline` consolidado en UN lugar | `grep -c '^Cuándo:'` en cada perfil = número de principios asignados; frontmatter/`saikit_owned` intactos; el encabezado `## Boundary Discipline` existe en exactamente 1 perfil (la palabra `boundary` sigue en el ataque "trust boundary" del adversary); ningún perfil promete lo que el hook no mide | 16.1 | cc:TODO |
| 16.4 | `[Contrato]` `[lane:gate]` `[tdd:required]` **Menú de recetas en el contrato** (D1/D4): `RECETAS_DIR` con override `SAIKIT_RECETAS_DIR`; menú desde `MANIFEST.sha256` con verificación de hash por receta (mismatch/ausente ⇒ omitida + aviso; sin manifiesto ⇒ línea fija); **sin ruta absoluta en el contrato**; regla "elige/lee/copia/declara `Receta:`/`skip: razón`"; edición del bloque de preguntar (D7); `Close:` con "nunca inventes link/cita/comando" (D8) | Rojo medido; `caso_g1_contrato_nombra_recetario` (planta `$LAB/hooks/recetas` vía `SAIKIT_RECETAS_DIR`) + `caso_g1_sin_recetario_contrato_igual` (byte-idéntico salvo la línea fija) + `caso_g1_receta_hash_distinto_se_omite`; mutación `menu_recetas_apagado`; `test_hook_source` 131 verde; golden regrabada con `--record` y diff auditado (1 de 5 declarados); el Stop gate sin cambios | 16.2 | cc:TODO |
| 16.5 | `[Instalador]` `[lane:gate]` `[tdd:required]` **`install-hook.sh` planta `<hookdir>/recetas/` + `MANIFEST.sha256`** (host claude) reutilizando `agente_estado_con_vendor` por archivo (marca `saikit_owned` en frontmatter; ajeno ⇒ `DESCONOCIDO`, no se toca), `--dry-run` que no escribe, y `~/.claude/skills/sencillo/SKILL.md` (D8) con la misma marca; `check-hook-registration.sh` reporta recetario/manifiesto ausente y ACE ajenos (advisory, exit 0); `test_hook_acl.sh` y `hook-acl.ps1` extendidos a `hooks/recetas/` y a la LISTA explícita `skills/{sencillo,saikit-verificar-app,saikit-setup-autopilot}` (un glob `saikit-*` deja fuera a `sencillo`) | Casos: limpio / dos corridas no reescriben / archivo ajeno intacto y reportado / dry-run sin escritura / quitar; clasifica todo antes de publicar (precedente 12.9); **Windows-bound**: casos corridos en local y citados en el cierre (CI los salta con `SAIKIT_CI_LINUX=1`) | 16.2 | cc:TODO |
| 16.6 | `[Carril]` `[lane:gate]` `[tdd:required]` **Alias en español del carril fast que NOMBRAN su receta** (D3, **Required**): `-saikit:pregunta` ⇒ `lane=fast` + `receta_alias=investigar`; `-saikit:boceto` ⇒ `lane=fast` + `receta_alias=boceto`; el contrato lo dice ("carril fast por `-saikit:boceto`: la receta es `boceto`, no toques código de producción"); match exacto con frontera; cualquier otro sufijo ⇒ full sin alias (límite declarado, como 10.1) | Rojo medido; caso por alias (lane + estado + línea del contrato) + `caso_g1_sufijo_desconocido_arma_full` sigue verde; mutación `alias_pregunta_apagado` y `alias_sin_receta`; golden regrabada con diff auditado (2 de 5) | 16.4 | cc:TODO |
| 16.7 | `[Ruteo]` `[lane:gate]` `[tdd:required]` **`model-routing.sh --task <receta>`** ⇒ tier existente, nunca modelo (D9, Optional) | `test_model_routing.sh`: cada receta resuelve a `standard`\|`verify`\|`review`; el candado "IDs solo en el router" sigue verde | 16.2 | cc:TODO |
| 16.8 | `[Medición]` `[lane:release]` `[tdd:skip:medición]` **Un turno vivo por receta** (D10; hasta 3 por sesión en el mismo repo descartable) con `tools/stage-override.sh`: el líder eligió la receta correcta, la declaró en `Understand:`, copió los pasos, y el recibo cerró; `docs/smoke-recetas-<fecha>.md` con cita del transcript por receta | 6 de 6 con evidencia literal o `unknown` declarado; receta sin turno vivo NO entra al manifiesto (queda en `recetas/pendientes/`) | 16.4, 16.5, 16.6 | cc:TODO |
| 16.9 | `[Release]` `[lane:release]` `[tdd:skip:docs]` **Cierre**: README con la guía de usuario en español (**tres palabras**: construir / preguntar / bocetar; qué hace cada receta), spec § final con límites medidos, deploy vía `install-hook.sh` anotado en `docs/deploy-log.md` (lo hace el lead), filas cerradas con sha/PR; archivar Phase 15 | `tests/test_recetas.sh` + `python tools/check_context_docs.py . --sweep` sin hallazgos nuevos; deploy-log con el sha; `Plans.md` ≤200 líneas | 16.2–16.8 | cc:TODO |

**Fuera de alcance, declarado:** recetas, `/sencillo` y menú en zcode/codex/
grok/kimi/dsh (entran después por la vía de los perfiles); las 10 piezas NO y
las 10 DESPUÉS del Apéndice A; que el líder cambie el carril; shellcheck.

---

## Phase 17 — Verificación real y rastro (2026-08-28)

**Propósito:** que el verifier pruebe **la app como usuario**, no solo tests y
typecheck; que cada task deje un **rastro de decisiones en español** legible
sin abrir código; y que el verifier nombre **el hecho único** por el que el
cambio es seguro y lo corra (blast radius, nivel 1–5). Es lo que hace posible
un autopilot que no mergee a ciegas. Decisiones D11–D14 del diseño.

| Task | 内容 | DoD | Depends | Status |
|------|------|-----|---------|--------|
| 17.1 | `[Skill]` `[lane:gate]` `[tdd:required]` **`saikit-verificar-app`** (D11): skill a nivel usuario que genera `verify/` en el repo del usuario (`LEEME.md` con mapa de 3–5 funciones en español + Launch/Doctor/Drive/Evidence/Cleanup); **Drive = e2e bajo `verify/` que ejercita la superficie de usuario, en el framework que el repo ya tiene, invocado por un comando que `TEST_RUNNER_RE` acredita** (`node --test` se envuelve en `npm test`; la suite unitaria del repo NO cuenta como Drive); framework nuevo solo con sí explícito del usuario, pinneado, nunca `npx @latest`; sin sí ⇒ Drive "manual, pendiente" y `verify_app: n/a`; se corre UNA vez antes de entregar | `tests/test_verificar_app.sh` (portable, corre en CI) contra 2 repos fixture (node con `node --test`, python+pytest) en sandbox: archivos esperados bajo `verify/` + el comando de Drive incluye `verify/` y matchea `TEST_RUNNER_RE` LEÍDO del hook con `grep -o`; repo sin framework ⇒ propone y espera el sí, no instala | 16.1 | cc:TODO |
| 17.2 | `[Perfil]` `[lane:fast]` `[tdd:skip:prompt-only]` **`agents/verifier.md`, lane de app real**: si existe `verify/` lo corre y su salida es evidencia; si no existe, lo propone (no lo inventa en el turno); "inconcluso o superficie equivocada no es PASS" | `grep` de las 3 frases en el perfil; consistente con 16.3; el perfil no promete nada que el hook no acredite | 17.1, 16.3 | cc:TODO |
| 17.3 | `[Rastro]` `[lane:gate]` `[tdd:required]` **`.saikit/decisiones/<task>.tsv`** (D12): columnas `cuando|etapa|decision|por_que|evidencia|resultado`; `tools/saikit-decision.sh` append seguro; **`tools/lib/redactar.sh` compartido** (patrones del hook + `ghp_`/`github_pat_`/`gho_`/`sk-`/`AKIA`/`xox[bp]-`) usado por rastro y blast, y **la familia de patrones del hook se extiende** con esas formas (rojo/verde + mutación, escaneo de 13.4); contrato: `Close:` cita la ruta + sección **Atención**; **se commitea antes de despachar al reviewer**; adversary lee el tsv | `tests/test_saikit_decision.sh`: append crea/agrega sin partir filas; cada forma de token sale `[REDACTED]` en el helper Y en el escaneo del hook (caso de gate + mutación `redaccion_sin_ghp`); tsv malformado se reporta, no se repara; golden regrabada con diff auditado (3 de 5) | 16.4 | cc:TODO |
| 17.4 | `[Blast]` `[lane:gate]` `[tdd:required]` **El hecho único** (D13): paso del verifier + esquema `.saikit/findings/blast-<task>.json` (`hecho`,`comando`,`salida` recortada y redactada,`nivel` 1–5) + adjudicación en `reviewer.md`; anotar que el candado del adversary no aplica al verifier (medido) | `tests/test_blast_artifact_contract.sh` (molde `test_adversary_artifact_contract.sh`): válido / nivel ≥4 sin `comando` ⇒ inválido / nivel fuera de rango ⇒ inválido; caso de gate: blast con secreto en `salida` NO dispara el escaneo de 13.4 (llega `[REDACTED]`) | 17.2 | cc:TODO |
| 17.5 | `[Medición]` `[lane:release]` `[tdd:skip:medición]` **Dos turnos vivos** (app node, app python) con `verify/` generado, rastro y blast; `docs/smoke-verificacion-<fecha>.md` | Evidencia literal: el hook acreditó la corrida de Drive como verificación (evento de tool o prosa); el tsv y el blast existen y el reviewer los adjudicó; lo no observado `unknown` | 17.1–17.4 | cc:TODO |
| 17.6 | `[Release]` `[lane:release]` `[tdd:skip:docs]` **Cierre**: spec § límites medidos (qué runners acredita, qué no), README, instalador planta `saikit-verificar-app` (Windows-bound), deploy-log, filas cerradas | `test_recetas.sh` + sweep sin hallazgos nuevos; casos del instalador citados; deploy-log con el sha | 17.5, 16.5 | cc:TODO |

**Fuera de alcance, declarado:** `maintain-verification-skill` (cuando `verify/`
tenga >5 funciones y haya rotado); leer transcripts para auditar (A6);
runners fuera de `TEST_RUNNER_RE` (se agregan con TDD si un repo lo pide).

---

## Phase 18 — El autopilot (2026-08-28)

**Propósito:** que el PR se mergee solo cuando un **veredicto atado al SHA
exacto** y el **CI** lo permiten, con permiso general del usuario dado de
antemano y vuelta atrás automática si master se pone rojo. Sin humano en el
loop, no "más rápido por PR". **El script de merge es fail-closed y acotado a
repo/PR/rama/head** (D18); la protección de rama de GitHub no está disponible
(403 medido). El merge corre DENTRO del turno armado (cruce con el estado del
hook); el post-merge, en un turno desarmado. En serie. Decisiones D15–D23.

| Task | 内容 | DoD | Depends | Status |
|------|------|-----|---------|--------|
| 18.1 | `[Diseño]` `[lane:gate]` `[tdd:skip:diseño-y-medición]` **Diseño medido + plan paso a paso** (`docs/phase-18-autopilot-plan.md`): formas reales de `gh pr checks` (concluido / pendiente / **sin checks**), `gh pr view --json mergeable` (frecuencia real de `UNKNOWN` diferido) y `gh run list --commit`; `gh pr merge --match-head-commit --body "Saikit-Merge: …"` **sin `--delete-branch`** y si pasa el runtime floor sin prompt; flujo de revert de un squash medido; las 5 preguntas del setup; esquemas del veredicto (D16) y de `autopilot.json` (D15); crea el repo descartable `gon0801/<nombre>` con topic `saikit-descartable` + marcador | Cada precondición de D18 con su forma observada o `unknown`; el descartable creado, nombrado y documentado | 17.6 | cc:TODO |
| 18.2 | `[Receta]` `[lane:fast]` `[tdd:required]` **`recetas/cuidar-pr.md`** (D17): modos revisar/cuidar/solo-hilos; orden conflictos→hilos→CI; clasificación del CI rojo (flake 1 build / base vieja merge de master / real fix); rúbrica fix/dismiss/ask + `.saikit/triage-patrones.md`; esperas sin bloquear; tope 2 rondas; descubrimientos se reportan; **cuidar nunca mergea** | Pasa `tests/test_recetas.sh` incluida la regla de términos prohibidos; manifiesto regenerado | 16.2, 18.1 | cc:TODO |
| 18.3 | `[Veredicto]` `[lane:gate]` `[tdd:required]` **`.saikit/veredictos/<sha>.json` sellado por el hook** (D16): el líder commitea (incluido el rastro) ANTES de despachar al reviewer; el reviewer graba `sha = git rev-parse HEAD` + campos (`verify_app` con `comando`); **el hook registra `veredicto_sha256` del `tool_input.content` en el `Write` atribuido al reviewer sobre `veredictos/`** (registro de estado, sin check nuevo en el Stop); esquema + test de contrato; `.gitignore` de `veredictos/` creado por el hook; contrato: `Close:` cita sha y ruta | Rojo medido; `tests/test_veredicto_contract.sh`: válido / `sha` ≠ HEAD ⇒ inválido / campo faltante ⇒ inválido; casos de gate: `Write` del reviewer registra el hash / `Write` de otro rol NO lo registra / `Edit` posterior deja el archivo con hash distinto al registrado; mutación `sello_veredicto_apagado`; golden regrabada con diff auditado (4 de 5) | 17.4, 18.1 | cc:TODO |
| 18.4 | `[Merge]` `[lane:gate]` `[tdd:required]` **`tools/saikit-merge.sh` fail-closed y acotado** (D18): repo del cwd, PR de la rama actual, `baseRefName == config.rama`, `headRefOid == sha`, autor del PR = cuenta de gh; `git fetch origin <rama>` + rama al día con la base (`merge-base --is-ancestor`); config leída de `origin/<rama>`; `mergeable: UNKNOWN` ⇒ un reintento; `verify_app: PASS` con comando bajo `verify/` o `n/a` solo con `sin_verify_app: true`; cruce con el estado del hook (`reviewer` en `agents_seen`, **`veredicto_sha256` == sha256 del archivo actual**, comando del blast en `harness-evidence.log` con éxito); commits del rango solo del `user.email` local o de la cuenta de gh; `gh pr merge --squash --match-head-commit <sha> --body "Saikit-Merge: <sha>"` sin `--delete-branch`; borrado remoto aparte; registra `merge_commit` en `veredictos/<sha>.merge` (el veredicto sellado no se toca); `--dry-run`; **modo `--revert-de <merge_commit>`** (D19): sin estado del hook y sin confiar en JSON local — exige que sea la punta de `origin/<rama>` tras fetch + trailer `Saikit-Merge:` + **igualdad exacta de árboles** (`<head>^{tree}` == `<merge_commit>^^{tree}`; `patch-id` solo como extra) + ningún otro commit + CI verde + `--match-head-commit` | `tests/test_saikit_merge.sh` con `gh` falso y git real en sandbox: todo ok ⇒ merge con trailer y el veredicto sellado queda byte-idéntico; config con `rama: main` ⇒ funciona igual; CI rojo / sin checks / pendiente / `mergeable` UNKNOWN dos veces / base avanzada / veredicto de otro sha / **veredicto reescrito tras el sello** / commits después del veredicto / `blast.nivel<4` / `verifier: FAIL` / `verify_app: n/a` sin `sin_verify_app` / Drive fuera de `verify/` / config ausente o `unknown` / PR que toca `autopilot.json` / PR de otra rama base / repo distinto / autor del PR ≠ cuenta / commit de otro email / sin estado del hook ⇒ NO mergea y nombra la razón; merge ok + borrado remoto falla ⇒ reporta sin reintentar; `--revert-de`: inverso exacto de la punta con trailer ⇒ merge; árbol distinto (incluido un cambio extra solo de whitespace, que `patch-id` no ve) / commit extra / sin trailer / no es la punta ⇒ NO; nunca `--admin` | 18.3 | cc:TODO |
| 18.5 | `[Post-merge]` `[lane:gate]` `[tdd:required]` **`tools/saikit-postmerge.sh`** (D19), turno desarmado: run por `gh run list --commit <merge_commit>`; sin run ⇒ `unknown` con heartbeat acotado, timeout ⇒ `unknown` sin revert; `GET salud_url` solo http(s), sin redirects, `--max-time`, redactada; rojo ⇒ `git revert <merge_commit>` (squash) SOLO si es la punta de `origin/<rama>` con trailer `Saikit-Merge:`, PR de revert mergeado con `saikit-merge.sh --revert-de`, una vez; si algo aterrizó después o el revert no puede mergearse ⇒ avisa que la rama está roja y cómo revertir a mano; mensaje en español desde el `Close:` redactado (≤4096); `telegram-send` solo con `telegram: true` | `tests/test_saikit_postmerge.sh`: verde ⇒ mensaje; rojo ⇒ revert mergeado; revert rojo ⇒ para y avisa; salud caída ⇒ revert; sin run aún ⇒ `unknown`; merge_commit sin trailer o que no es la punta ⇒ no revierte y avisa | 18.4 | cc:TODO |
| 18.6 | `[Sentinel+Contrato]` `[lane:gate]` `[tdd:required]` **`-saikit:autopilot`** ⇒ full + `autopilot=1` en estado (D15) y párrafo del contrato (D21: qué hará solo, qué nunca; merge antes del recibo y SOLO por `tools/saikit-merge.sh`, nunca `gh pr merge` a pelo; `Close:` con sha mergeado o razón de no-merge) + la excepción escrita en la regla de preguntar (D7: lo autorizado en el setup no se vuelve a preguntar); **sin checks nuevos en el Stop** | Rojo medido; caso arma-autopilot / sufijo desconocido ⇒ full sin flag; mutación; golden regrabada con diff auditado (5 de 5) | 16.4, 18.4 | cc:TODO |
| 18.7 | `[Setup]` `[lane:gate]` `[tdd:required]` **`saikit-setup-autopilot`**: 5 preguntas en español ⇒ `.saikit/autopilot.json` (esquema + test; `merge_despliega` nace `unknown`; `sin_verify_app` y `telegram` nacen `false`); lock en `$(git rev-parse --git-common-dir)/saikit-autopilot.lock` (D20): `mkdir` atómico con `pid`/`host`/`started_at`/`pr`, `rmdir` en `trap EXIT`, lock viejo se reporta y bloquea (nunca se borra solo), `--liberar-lock` explícito; `.gitignore` idempotente de `veredictos/`; el instalador planta la skill (Windows-bound) | `tests/test_autopilot_config.sh`: JSON válido/inválido; defaults; contención real con dos worktrees del mismo repo ⇒ el segundo espera o reporta, nunca dos merges; lock viejo (pid muerto) ⇒ reporta y bloquea; `--liberar-lock` lo quita | 18.1 | cc:TODO |
| 18.8 | `[CI]` `[lane:gate]` `[tdd:required]` **CI mínimo cuando no hay** (D22, Required): el setup detecta ausencia de workflows y ofrece en español un workflow de Actions que corre el test del repo + `verify/` (acciones pinneadas, sin secretos); sin CI y sin aceptar ⇒ el autopilot lo dice y no mergea | Test del generador: repo sin workflows ⇒ propone; con sí ⇒ YAML válido (`check-yaml`) que nombra el comando de test del repo; con no ⇒ nada escrito y razón declarada | 18.7 | cc:TODO |
| 18.9 | `[Medición]` `[lane:release]` `[tdd:skip:medición]` **Tres escenarios en vivo** (D23) en el descartable con Actions reales: verde ⇒ merge; CI rojo ⇒ no merge con razón; post-merge rojo ⇒ revert; costo por PR (tokens/tiempo) vs ceremonia actual; `docs/smoke-autopilot-<fecha>.md` | 3 de 3 con evidencia literal (sha, run, PR de revert); costo medido, no estimado | 18.2–18.8 | cc:TODO |
| 18.10 | `[Release]` `[lane:release]` `[tdd:skip:docs]` **Cierre**: spec § límites medidos, README (guía en español: qué hace solo, qué nunca, cómo deshacerlo), deploy-log, retro de la fase; el descartable se borra SOLO con topic + marcador verificados (o a mano por el operador, recomendado) | Coherencia; deploy-log con el sha; descartable borrado y anotado, o entregado al operador | 18.9 | cc:TODO |
| 18.11 | `[Guardia]` `[lane:gate]` `[tdd:required]` **`PreToolUse` que niega el merge a pelo** (D24, **Recommended**): medir primero que un `PreToolUse` de Claude Code con `decision: deny` detiene un `Bash` cuyo comando matchea `gh pr merge` / `gh api … /merge` / `git push … <rama>`; la vía permitida es por **forma canónica del comando** (invoca `tools/saikit-merge.sh` y el archivo tiene el sha256 del manifiesto del kit), NUNCA una variable de entorno (el `PreToolUse` corre antes del comando; la marca no existe en el evento); límite declarado: match de texto, un `gh` dentro de otro archivo no es visible; si confirma: registrar la fase (checker pasa de 3 a 4 fases, advisory), casos + mutación + golden; si no confirma: límite declarado y cierre con `unknown` | Medición citada; con deny confirmado: rojo medido, caso que niega el directo + caso que deja pasar al script con hash correcto + caso que niega al script con hash distinto + mutación + golden 0 divergencias; `check-hook-registration.sh` reporta la 4ª fase | 18.4 | cc:TODO |

**Fuera de alcance, declarado:** PRs en paralelo (choque de worktree medido);
Graphite/stacks; excepción por `patch-id`; autopilot en otros hosts; leer
transcripts; que GitHub proteja la rama (no disponible en plan free; hacer
público el repo es decisión del operador, no de este plan); `--delete-branch`.

---

## 事前確認

- 事項: escritura de ACLs sobre `~/.claude/hooks/` y `~/.claude/hooks/state/`
  理由: quitar `Modify` a identidades de sandbox sobre el script que corre sin sandbox
  scope: Phase 0 / Task 0.1
- 事項: lectura de `~/.claude/settings.json` y `~/.claude/settings.local.json`
  理由: verificar que el hook sigue registrado (modo de falla silencioso) y el cableado del heal
  scope: Phase 0 / Task 0.3, Phase 2 / Task 2.4
- 事項: remoción de ACE de cuentas BORRADAS (SID no resoluble) en `~/AppData`,
  `~/AppData/Local` y `%TEMP%` — aprobado en sesión 2026-08-08
  理由: A7-bis — `%TEMP%` re-contamina `~/.claude` por `move`, y los 5 SID
  huérfanos estaban explícitos repartidos en esos tres niveles. NO se toca
  `CodexSandboxUsers`, que ahí sí escribe legítimamente
  scope: Phase 0 / Task 0.2
- 事項: escritura de ACLs sobre `~/.claude` (la RAÍZ del perfil, no solo `hooks/`)
  理由: ahí vive el otorgamiento explícito medido en la 0.1; mientras siga, el hook
  se puede desregistrar desde `settings.json` sin tocar el archivo
  scope: Phase 0 / Task 0.2
- 事項: escritura sobre `~/.claude/hooks/summonaikit-harness.sh` (el archivo que gatea cada turno)
  理由: la adopción por reemplazo es el objetivo de la Phase 2
  scope: Phase 2 / Task 2.4
- 事項: escritura sobre `C:\Users\ehven\quality-kit\saikit-gate-heal.ps1` y su batería
  理由: el skip por marcador debe mergearse antes de instalar, para no tener dos escritores
  scope: Phase 2 / Task 2.3, Phase 4 / Task 4.1
- 事項: creación de repo remoto y `git push` a `gon0801/summonaikit-claude`
  理由: regla de dejar en git + remoto todo lo tocado
  scope: Phase 1 / Task 1.1 en adelante
- 事項: descarga del kit del vendor en directorio desechable (ya ejecutada 2026-08-08)
  理由: verificar la premisa de si conviene actualizar; se hizo fuera del home y se borró
  scope: pre-plan, completado
- 事項: escritura y reemplazo recuperable de `~/.codex/hooks/summonaikit-harness.sh`
  理由: instalar la fuente aprobada de Phase 6 y validar un turno real con backup/restore listo
  scope: Phase 6 / Task 6.6
- 事項: alta y revocación de folder trust para repos descartables de Grok
  理由: ejecutar hooks de proyecto durante captura, probe y staging sin instalar el harness global
  scope: Phase 7 / Tasks 7.1, 7.2 y 7.6
- 事項: escritura/reemplazo recuperable y remoción selectiva bajo `~/.grok/hooks/` y `~/.grok/agents/`
  理由: instalar o retirar sólo artefactos con propiedad `summonaikit-claude`, preservando el verifier ajeno
  scope: Phase 7 / Tasks 7.5 y 7.6
- 事項: escritura vía `tools/install-hook.sh` (deploy) en `~/.claude/hooks/`,
  `~/.claude/agents/`, `~/.zcode/agents/` + user-config de zcode, y
  `~/.agents/agents/` (kimi) — codex y grok ya cubiertos por las entradas de
  Phase 6/7
  理由: 13.9 instala hook y perfiles con las disciplinas existentes (tres/cinco
  estados, backups, atómico); zcode/kimi no tenían entrada propia en este
  ledger (hueco desde Phase 5/12, cerrado acá)
  scope: Phase 13 / Task 13.9
- 事項: sesiones vivas de medición en 13.1 (turnos claude contra `hook_lab.sh`)
  理由: los canales de atribución de rol se miden, no se suponen; preferencia por el lab, no el perfil vivo (lección 9.9)
  scope: Phase 13 / Task 13.1, ya ejecutada
- 事項: escritura vía `tools/install-hook.sh` en `~/.claude/hooks/recetas/` (con `MANIFEST.sha256`) y `~/.claude/skills/{sencillo,saikit-verificar-app,saikit-setup-autopilot}/`
  理由: plantar recetas y skills del kit con marca `saikit_owned` + hash por archivo; ACL auditada como `hooks/`
  scope: Phase 16 / Tasks 16.5, 16.9; Phase 17 / Task 17.6; Phase 18 / Task 18.7
- 事項: staging por override (`tools/stage-override.sh`) y turnos vivos `-saikit` en repos descartables LOCALES
  理由: medir recetas y la lane de app real sin tocar el hook global (D10, 17.5)
  scope: Phase 16 / Task 16.8; Phase 17 / Task 17.5
- 事項: external-send acotado al repo descartable `gon0801/<nombre fijado en 18.1>` (topic `saikit-descartable` + marcador): `gh repo create`, `git push`, `gh pr create`, `gh pr merge --squash --match-head-commit`, `gh api` de hilos; destructive: `gh repo delete` SOLO de ese repo, verificado por topic + marcador, o a mano por el operador (recomendado)
  理由: 18.1/18.9 miden merge, post-merge y revert contra Actions reales; expira al cerrar 18.10
  scope: Phase 18 / Tasks 18.1, 18.9, 18.10
- 事項: merge automático en repos del usuario — NO se preaprueba en este ledger: la autorización en uso real es por repo y por dos llaves (`-saikit:autopilot` + `autopilot.json` leído de `origin/<rama>`), con `saikit-merge.sh` fail-closed y acotado (D15/D18); aquí solo tests con `gh` falso
  理由: un permiso permanente en este ledger sería más amplio que lo necesario; el producto lleva su propia autorización
  scope: Phase 18 / Tasks 18.4, 18.5
- 事項: external-send opcional — `telegram-send` con el `Close:` redactado (≤4096 chars)
  理由: aviso al usuario sin mirar la terminal; solo si lo activa en el setup
  scope: Phase 18 / Task 18.5
