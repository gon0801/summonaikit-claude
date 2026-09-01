# Phase 18 — Plan de diseño MEDIDO del autopilot (Task 18.1)

> Contrato: filas 18.1/18.2/18.3 de `Plans.md` y la decisión del operador
> 2026-08-30 (**el autopilot NO mergea solo**). Este documento es el diseño
> medido y el plan paso a paso; el código de las Tasks 18.2 (receta) y 18.3
> (veredicto sellado) se implementa contra este documento y el diseño
> `docs/phase-16-18-recetario-autopilot-design.md` (D15–D24). Nada de lo que
> aquí se diseña ni lo que se construye puede contradecir la regla madre: el
> autopilot prepara, **para antes de publicar**, y solo mergea con el «sí»
> explícito del operador.

---

## 1. Repo descartable creado y nombrado

Se creó el repo descartable para medir contra Actions reales, **sin tocar
ningún repo real del usuario** y **sin** decidir la visibilidad del repo (se
dejó **privado**; hacer los repos públicos es decisión del operador, fuera del
alcance):

| Campo | Valor |
|-------|-------|
| Repo | `gon0801/saikit-descartable` |
| URL | `https://github.com/gon0801/saikit-descartable` |
| Visibilidad | **private** |
| Topic | `saikit-descartable` (verificado con `gh repo view --json repositoryTopics`) |
| Marcador | `SAIKIT-ORIGEN.md` (identifica el repo como artefacto de la Phase 18) |
| Rama default | `main` |
| Contenido | `app.sh` + `tests/test_app.sh` + `.github/workflows/ci.yml` (workflow `ci`, job `test`, corre `bash tests/test_app.sh` en push/pull_request) |

El `external-send` a este repo está **pre-aprobado en el ledger** (entrada de
`Plans.md` §事前確認, scope Phase 18 / Tasks 18.1/18.9/18.10). El repo quedó
**vivo** con su topic y marcador para que 18.9/18.10 lo reusen. A la fecha de
este plan se usó para tres PRs:

- **PR #1** `feat: agrega saludo a app.sh` — `feat/agrega-saludo`, CI verde (2
  runs `test` pass) + `CodeRabbit` pendiente. Quedó abierto (no se mergeó).
- **PR #2** `chore: version 1.1.0` — `feat/version-bump`, **mergeado en squash**
  (measurement del merge), `merge_commit` `71d1dfca…`, rama remota NO borrada.
- **PR #3** `chore: sin checks` — `feat/sin-checks`, **elimina el workflow** para
  observar la forma «sin checks». Quedó abierto.

---

## 2. Formas reales MEDIDAS de los comandos gh (hechos, no supuestos)

### 2.1 `gh pr checks <pr>` — formas observadas

- **Concluido success** (CI verde): tras terminar el run, `gh pr checks 1`
  muestra `test  pass  6s  <url…/runs/…/job/…>`. El check hereda el nombre del
  job (`test`) y concluye `pass` con la duración.
- **Pendiente** (durante CI / bot): `test  pending  0  <url>` y, en el PR #1,
  `CodeRabbit  pending  0        Review in progress` (check de un bot
  tercero, no del repo).
- **Sin checks**: el PR #3 (cabecera sin workflow) → `gh run list --commit
  <head>` devuelve **vacío** (rc 0, sin errores), y `gh pr checks 3` muestra
  **solo** `CodeRabbit  pass  0   Review rate limited` (el bot aparece aunque
  no haya CI). **Consecuencia para el diseño:** `gh pr checks` puede estar NO
  vacío por un bot aunque el repo no tenga CI, así que «no hay checks» se debe
  detectar con `gh run list --commit` vacío, **no** con `gh pr checks` solo (y
  aun así, "no hay checks" ≠ verde, ver §5.4).
- **Quirk real (importante):** el mismo `head sha` dispara **dos** runs del
  workflow `ci` — uno por el evento `push` y otro por `pull_request` (observado
  en `gh run list --commit aa92cf8…`: `completed success … ci … push` y
  `in_progress/… pull_request`). El `gh pr checks` agrega **dos** checks `test`
  para el mismo head. El autopilot debe mirar el run del evento `pull_request`
  (o filtrar por evento), no asumir un solo run.

### 2.2 `gh pr view --json mergeable` — formas observadas

- **`mergeable`**: `MERGEABLE` en la totalidad de las lecturas (se sondeó
  rápido post-crear el PR #2, 10 lecturas a ~300 ms: todas `MERGEABLE`).
  **`UNKNOWN` NO se observó** en estos PRs chicos — GitHub lo calcula
  demasiado rápido. Frecuencia de `UNKNOWN` diferido: **0/2 PRs** (declarado
  como "no observado", no como "no existe": con diffs grandes o infra ocupada
  puede aparecer; D18 mantiene el reintento único como fallback seguro).
- **`mergeStateStatus`**: es el campo que **sí** distingue checks. Observado:
  `UNSTABLE` (mientras hay checks pendientes: run `ci` + `CodeRabbit` pendiente)
  → `CLEAN` (todos los checks del repo en verde; se alcanzó en el PR #2).
  Un PR **mergado** reporta `mergeStateStatus: UNKNOWN`.
- **Consecuencia para el diseño:** `mergeable: MERGEABLE` solo dice "sin
  conflictos", **no** "checks verdes". Para "listo para publicar" hay que cruzar
  `mergeStateStatus` y la conclusión del run del workflow.

### 2.3 `gh run list --commit <sha>` — formas observadas

- Devuelve **todos** los runs cuyo head es ese commit (push + pull_request),
  con `event`, `workflow`, `branch`, `status` (`in_progress`/`completed`),
  `conclusion` (`success`/…) y `id`.
- **Vacío** cuando la cabecera no tiene workflow (PR #3). rc 0 — no es error,
  es ausencia (eso es "no hay CI").

### 2.4 `gh pr merge --squash --match-head-commit <sha> --body "Saikit-Merge: <sha>"` SIN `--delete-branch`

- **Resultado:** RC **0**, ~**3.6 s**, stdout **vacío**, con **stdin cerrado**
  (no es TTY) → **no pidió confirmación** y no colgó esperando un prompt.
  **Pasa el runtime floor sin prompt humano.**
- Tras el merge: `gh pr view 2 --json state,mergeCommit,mergedAt` →
  `state: MERGED`, `mergeCommit.oid: 71d1dfca…`, `mergedAt: …`, y
  `mergeStateStatus: UNKNOWN` (un PR mergeado ya no tiene estado útil).
- **La rama remota `feat/version-bump` NO se borró** (sigue en
  `refs/heads/feat/version-bump` → `7acab92…`): confirma que sin
  `--delete-branch` el borrado remoto no ocurre, y este repo (con `master` en
  otro worktree) no sufre el "checkout fallido tras mergear" que describe D18.
- **Implicación para la regla madre:** como el script de merge pasa el floor sin
  prompt, el freno humano **no** puede estar en el script (no hay nada que lo
  pare). El diseño (D18/D21) lo pone en la **invocación separada
  `--confirmado`** que solo existe si el operador dijo que sí, y que **repite el
  gate completo** — coherente con la decisión del 2026-08-30.

### 2.5 Revert de un squash — medido, no supuesto

- `git revert <merge_commit>` sobre un squash **funciona sin `-m`** (el squash
  es un commit lineal; no hay merge parents). RC 0.
- La **igualdad exacta de árboles** que exige D19 se confirmó:
  `` `HEAD^{tree}` `` del commit de revert = `19deb13d…` ==
  `` `<merge_commit>^^{tree}` `` (el árbol ANTES del squash) = `19deb13d…`
  ⇒ **ARBOLES_IGUALES=SI**.
- El commit de revert: `Revert "chore: bump version a 1.1.0 (#2)"` — `app.sh`
  `6 ++----` (2 insertions, 4 deletions), restaurando exactamente el árbol
  previo. `patch-id` queda como comprobación adicional (D19), no como la
  principal.

### 2.6 Rama al día con la base — formas observadas (`git merge-base --is-ancestor`)

- **Al día:** en su momento, PR #2 (`7acab92…` sobre base `8edac0d…`,
  `origin/main` en `8edac0d…`): `git merge-base --is-ancestor <base> <head>`
  → rc **0**. (D18: `git merge-base --is-ancestor origin/<rama> <head>`.)
- **Base vieja:** ahora `origin/main` avanzó a `71d1dfca…` (por el merge del PR
  #2) y el PR #1 (`aa92cf8…`, basado en `8edac0d…`) quedó **detrás**:
  `git merge-base --is-ancestor origin/main origin/feat/agrega-saludo` → rc **1**.
  Es la condición que D18 usa para decir "base vieja ⇒ merge de `config.rama` en
  la rama y CI de nuevo".
- `git log origin/<rama>..HEAD` (el PR #1): `rev-list --count` = **1** → no
  vacío y solo los commits de la task.

---

## 3. Las 5 preguntas del setup (D15) — en español, una por respuesta

El asistente (`saikit-setup-autopilot`, Task 18.7) crea `.saikit/autopilot.json`
preguntando, en español y una por una:

1. **¿Mergear solo?** — SI/NO. → `merge: true|false`. Sin `merge: true` el
   autopilot no ofrece mergear.
2. **¿Mergear a `<rama>` publica la app?** — una de tres: "sí, publica" /
   "no, solo el código" / "no sé". → `merge_despliega: "publica" | "no" |
   "unknown"` (nace `unknown`).
3. **¿Hay una URL para checar que la app sigue viva?** — URL https o vacía.
   → `salud_url` (alias `null` si el operador no tiene una).
4. **¿Sin prueba de la app, mergeo solo?** — SI/NO. → `sin_verify_app:
   true|false` (nace `false`). ES en palabras simples: "sin prueba de la app,
   ¿mergeo solo?".
5. **¿Te aviso por Telegram?** — SI/NO. → `telegram: true|false` (nace
   `false`).

Campos adicionales que nacen con default: `rama` (default `master`),
`revert_si_rojo` (default `true`).

---

## 4. Esquema del veredicto sellado (D16) y de `autopilot.json` (D15)

### 4.1 `.saikit/veredictos/<sha>.json` (D16) — el reviewer lo graba, el hook lo sella

```json
{
  "sha": "<git rev-parse HEAD del turno, en el momento del review>",
  "pr": "<numero del PR>",
  "verifier": "PASS | FAIL",
  "verify_app": {
    "resultado": "PASS | FAIL | n/a",
    "comando": "<comando bajo verify/ que se corrio, o null si n/a>"
  },
  "blast": { "nivel": 1, "hecho": "<hecho unico>", "comando": "<comando>" },
  "adversary": { "findings": 0, "max_sev": "none" } | "n/a",
  "reviewer": "clean | findings",
  "decisiones": "<ruta del tsv .saikit/decisiones/<task>.tsv>"
}
```

**Sello (hook, Task 18.3):** en el `PostToolUse` de un `Write` **atribuido al
rol reviewer** sobre `.saikit/veredictos/`, el hook registra en el estado de
sesión `veredicto_sha256 = sha256(tool_input.content)` (registro de estado, sin
check nuevo en el Stop — el gate sigue advisory). Cualquier escritura posterior
(`Edit`, otro rol, `Bash`) cambia el archivo y el hash deja de coincidir. El
hook también crea el `.gitignore` de `veredictos/` (siempre, como con
`findings/`). Contrato: la línea `Close:` del recibo cita `sha` y ruta.

### 4.2 `.saikit/autopilot.json` (D15) — leído SOLO de `origin/<rama>`

```json
{
  "merge": true,
  "merge_despliega": "unknown",
  "salud_url": null,
  "revert_si_rojo": true,
  "rama": "master",
  "sin_verify_app": false,
  "telegram": false
}
```

El script hace `git fetch origin <rama>` y la lee con
`git show origin/<rama>:.saikit/autopilot.json` (nunca del working tree ni del
head del PR). Un PR que toque ese archivo **nunca se auto-mergea**. Sin config,
o con `merge_despliega: "unknown"`, no se mergea.

---

## 5. Precondiciones de D18 — forma OBSERVADA o `unknown` declarado

Cada precondición que `tools/saikit-merge.sh` (Task 18.4) exige, con su forma
medida. «No se pudo medir» se declara como `unknown` **sin inventar nada**.

| # | Precondición D18 | Forma OBSERVADA / `unknown` |
|---|------------------|------------------------------|
| 1 | `git fetch origin <rama>` hecho y la rama al día (`git merge-base --is-ancestor origin/<rama> <head>`) | **OBSERVADO**. Fetch real; `merge-base --is-ancestor` rc 0 (al día, PR #2 en su momento) y rc 1 (base vieja, PR #1 ahora detrás de main). |
| 2 | `mergeable` del PR | **OBSERVADO** `MERGEABLE`. `UNKNOWN`: **no observado** en 2 PRs (0/2) — sondeo rápido. D18 mantiene el reintento único como fallback. |
| 3 | CI del head concluido en `success` | **OBSERVADO** via `gh run list --commit`: `completed / success` en el run del workflow. **`gh pr checks` por sí solo NO basta** (agrega checks de bots: `CodeRabbit`). "No hay checks" ⇒ `gh run list --commit` vacío, y **no** equivale a verde. |
| 4 | Veredicto para ese sha: verifier PASS, blast.nivel ≥ 4, reviewer clean, verify_app PASS (comando con `verify/`) o n/a con `sin_verify_app: true` | **`unknown`** — el veredicto sellado es la Task 18.3 (se implementa aquí mismo); su forma se define en §4.1. La verificación del `comando` bajo `verify/` se hereda de D11 (Task 17.1, ya medida). |
| 5 | Cruce con el estado del hook (`agents_seen` contiene `reviewer`, `veredicto_sha256` == sha256 del archivo actual, comando del blast en `harness-evidence.log` con éxito) | **`unknown`** en su forma final (depende del sello de 18.3); el `veredicto_sha256` se define en §4.1 y se mide en 18.3. |
| 6 | `git log origin/<rama>..HEAD` no vacío y solo commits de `user.email` local o de la cuenta de gh | **OBSERVADO** (rev-list count 1, solo la task). El filtro por autor se implementa en 18.4 y se prueba con `gh` falso; la forma del comando `git log` ya está medida. |
| 7 | Config D15 válida | **`unknown`** en su esquema definido (§4.2) — el generador es 18.7. El esquema y defaults quedan fijados acá. |
| — | `gh pr merge --squash --match-head-commit <sha> --body "Saikit-Merge: <sha>"` sin `--delete-branch` | **OBSERVADO**: RC 0, ~3.6 s, sin prompt, rama remota NO borrada (§2.4). |
| — | Protección de rama de GitHub disponible | **NO disponible** (repo privado, plan free: 403 medido en el diseño; decisión de visibilidad es del operador). El script es la vía sancionada. |

---

## 6. Plan paso a paso del turno autopilot (lo que Tasks 18.4–18.9 construirán)

El orden del turno (armado con `-saikit:autopilot`):

1. **Armado**: sentinel `-saikit:autopilot` ⇒ carril `full` + `autopilot=1` en
   el estado (D15/D21), contrato con el párrafo autopilot (qué hará solo, qué
   NUNCA; **merge solo por `tools/saikit-merge.sh`, nunca `gh pr merge` a
   pelo**; `Close:` cita el sha mergeado o la razón de no-merge). Sin checks
   nuevos en el Stop.
2. **Implementer → verifier (verificar-app + blast + rastro) → adversary (si
   aplica) → líder commitea todo (incluido el rastro) → reviewer.** El reviewer
   graba `sha = git rev-parse HEAD` en `.saikit/veredictos/<sha>.json`; el hook
   sella `veredicto_sha256` (18.3).
3. **Receta `cuidar-pr`** (18.2): declarar modo (revisar/cuidar/solo-hilos);
   orden conflictos → hilos → CI; clasificar CI rojo (flake/base vieja/real);
   triage Greptile/CodeRabbit con la rúbrica fix/dismiss/ask +
   `.saikit/triage-patrones.md`; esperas sin bloquear; tope 2 rondas;
   **cuidar nunca mergea**.
4. **Verificación del merge** (18.4, fail-closed): repo/PR/rama/head del cwd;
   precondiciones de §5 todas en verde; **NO mergea**: reporta "listo" y
   termina. El merge ocurre en una invocación aparte `--confirmado` (solo existe
   si el operador dijo que sí) que **repite el gate completo**.
5. **Merge** (solo con el `--confirmado` del operador): `gh pr merge --squash
   --match-head-commit <sha> --body "Saikit-Merge: <sha>"` sin `--delete-branch`;
   borrado remoto aparte; `merge_commit` a `.saikit/veredictos/<sha>.merge` (el
   veredicto sellado no se toca).
6. **Post-merge** (18.5, turno desarmado, reducido por la decisión): mirar el
   run y la salud y **AVISAR** (mensaje + comando de revert listo), sin ejecutar
   el revert. Sin merge desatendido no hay revert automático que deshacer.
7. **Cierre**: `Close:` con lo que cambió para el usuario; y **PARA** — pregunta
   al operador. Recién con el «sí» se hace el merge/deploy/bitácora/cierre de
   fila.

---

## 7. Deuda del harness a declarar en el diseño (lección pagada, medida en 16.12)

El candado del adversary (D3, `docs/phase-13-adversary-design.md`) exige que un
rol adversary escriba **solo** en `.saikit/findings/`, pero su trabajo real
**requiere fixtures desechables** (perfiles, junctions de Windows, scripts
temporales) para reproducir y atacar. Hoy es un rol con **tarea imposible**: el
material no cabe en `findings/` y no puede escribirse en otra parte.

**Declaración de diseño (para la ola que toque al adversary):** el diseño debe
(a) declarar una **zona de trabajo** del adversary dentro del sandbox del
proyecto (p.ej. `.saikit/tmp-adversary/`, gitignored por el hook y cubierta por
el candado), o (b) permitir que el adversary **derive el material a
`.saikit/findings/`** (que ya está gitignored) como artefactos de evidencia.
La opción (a) es preferible (el material de trabajo no es evidencia, es el
medio para generarla). Esta deuda NO se resuelve en 18.1–18.3; se declara acá
para que la fila que la aborde no re-diagnostique el problema.

---

## 8. Límites y declaraciones honestas

- **`unknown` admitido:** las precondiciones 4, 5, 7 de §5 no se midieron
  todavía porque dependen de Tasks posteriores (18.3, 18.4, 18.7). Se declaran
  `unknown` con razón, no inventadas.
- **Un dato que no se pudo medir no se afirma:** se medió lo que el repo
  descartable podía producir (PRs chicos, CI simple, CodeRabbit activo). La
  frecuencia de `mergeable: UNKNOWN`, el costo por PR en tokens/tiempo y el
  comportamiento con diffs grandes quedan como `unknown`/medición de 18.9.
- **El autopilot no mergea solo:** todo lo diseñado arriba converge en "dejar
  el PR listo y **PARAR a preguntar**". La regla madre no se contradice en
  ningún paso.
