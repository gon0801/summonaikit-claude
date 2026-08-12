# Task 4.2 — Declarar el dueño del contrato: Kimi sigue a `summonaikit-claude`, no al vendor (plan revisado tras cross-review)

`[Docs]` `[lane:fast]` `[tdd:skip:docs-only]`. Cierra la declaración de propiedad de
la Phase 4.
**DoD íntegra en `Plans.md:77`:** (1) el spec de `summonaikit-kimi` declara la nueva
fuente; (2) su detector de drift apunta a lo correcto; (3) ningún documento sigue
afirmando que el contrato se sigue del vendor. **Depende de:** 2.4 (install global
de `summonaikit-claude`).

> **Alcance: documentación, comentarios, y una línea de prosa del detector en el
> repo `summonaikit-kimi`.** No toca control-flow, no agrega tests, no muta el hook
> de Claude. El código **ya apunta a la fuente correcta** (verificado); lo que queda
> es desterrar el framing "Kimi sigue al vendor" / "AVISO = parche de quality-kit"
> y decir "sigue a `summonaikit-claude`".

## Cross-review del PLAN con Grok (1 ronda, 2026-08-12) — 2 medias + 6 bajas, 0 altas

Tope del quality-kit: máx 1 ronda, 2da sólo con severidad alta. Esta ronda **no halló
alta** → **no hay segunda ronda**. Hallazgos incorporados al cuerpo del plan (textos
propuestos, cobertura, receta de verificación). Residual declarado al final de esta
sección.

**Veredicto: REQUEST_CHANGES sobre el draft; el cuerpo de abajo YA incorpora los
fixes.** Ejecutar contra este texto, no contra el draft pre-review.

### Puntos que el draft pidió escrutar

1. **Distinción `vendorizada` vs `vendor`** — **OK, no tocar `vendorizada`.**
   Verificado: `tests/test_extract_contract.sh:89` hace `grep -qi 'vendorizada'`
   sobre stderr (`hooks/summonaikit-harness-kimi.sh:120,188`). Invertir esto
   rompería tests. La cirugía reemplaza sólo `el vendor` como actor upstream.
2. **Ledger histórico (C1/C2)** — **edición quirúrgica del present-tense.**
   "sigue siendo" / "mueve" están en presente y hoy son falsos; el status
   `cc:完了` no se toca. No agregar `[nota 2026-08-12]` (fecharía el origen de
   un hecho que ya era cierto desde la 2.4).
3. **Non-Goals (A5)** — **aceptado con reword.** Kimi no es fork ni del kit ni de
   `summonaikit-claude`; el kit sigue sin repo fuente. Usar **"kit de terceros"**
   (no "kit del vendor") para no reintroducir la frase que el grep de la DoD
   destierra.
4. **Cobertura del sweep** — el listado del draft cubría todos los hits de
   `el vendor` como actor. **Faltaba el actor sustituto equivocado:** README +
   `check_drift.sh` siguen diciendo que AVISO es "un parche local de quality-kit".
   Tras la 4.1, quality-kit ya no itera `.claude`; quien mueve el hook es
   `summonaikit-claude`. El pin `docs/pinned/` se deja **fuera** (snapshot
   histórico; incluye `vendor emite` en :710 y banners de quality-kit — editarlo
   falsificaría el pin).
5. **Fecha** — **OK.** No fechar el origen. La propiedad la estableció la 2.4.

### Hallazgos

1. **[media] ACEPTADO+verificado** — La receta de verificación exigía **0 hits**
   de `el vendor|del vendor|…`, pero los textos propuestos de A1/A5/B1/B2
   reintroducían esas frases como contraste (`no el vendor`, `kit del vendor`,
   `ya no es el del vendor`). El grep habría fallado el día del cierre, o
   habría obligado a un "humano lee residuales" que el propio plan contradice.
   **Fix:** los contrastes redundantes se cortan (la propiedad ya se nombra);
   A5 dice "kit de terceros"; la receta exige 0 hits de verdad, con exclusiones
   explícitas (`docs/pinned/`, `sandbox/`, `out/`).
2. **[media] ACEPTADO+verificado** — El camino que la gente lee cuando salta
   `DRIFT`/`AVISO` nombra al actor equivocado. `README.md:95-97` ("Es lo que
   pasa con cada parche local de `quality-kit`") y el **echo de runtime**
   `tools/check_drift.sh:95` (`(tipico: un parche local de quality-kit)`) no
   dicen "vendor", así que el sweep del draft no los veía — pero oscurecen a
   quién mirar, que es el motivo de esta task. Tras 4.1, quality-kit no parchea
   `.claude`. **Fix:** §B4 + §E3 + §E4. El echo es la única línea que no es
   comentario: es prosa del detector; `test_check_drift.sh:92` sólo asserta
   `AVISO`, no el substring `quality-kit`; el control-flow no cambia.
3. **[baja] ACEPTADO** — §G no puede ser opcional si el grep de la DoD incluye
   `*.sh`. Pasa a requerido. Se suma el comentario de calibración en
   `test_check_drift.sh:80` (mismo actor equivocado).
4. **[baja] ACEPTADO** — A1 colaba `; verificado` (diario de sesión) en el spec.
   Fuera: el spec declara el hecho, no que alguien lo miró hoy.
5. **[baja] ACEPTADO** — B1 "ya no es el del vendor" es absoluto de *esta*
   máquina y envenena el grep. Basta con declarar la propiedad vía install.
6. **[baja] ACEPTADO** — Relacionados / Independencia / spec Links todavía
   dicen que quality-kit heals el sentinel **de Claude**. Tras 4.1 es falso.
   Mismos archivos que ya se tocan (§A6, §B5, §B6).
7. **[baja] ACEPTADO** — La cláusula 1 de verificación no listaba A3 (sí se
   cambia). Queda en los hits esperados de `summonaikit-claude`.
8. **[baja] ACEPTADO** — C3: `Plans.md:62` (Task 4.1) afirma en presente que el
   hash cambia "con cada parche local de quality-kit". Misma cirugía que C1/C2.

**Declarado, no se arregla:** el pin congelado (incluye `vendor emite` y los
banners de quality-kit); `vendorizada` / símbolos `VENDORED_*`; el
`printf '\n# parche local:…'` del fixture en `test_check_drift.sh:85` (es el
cambio sintético del caso, no nombra actor); spec de `summonaikit-claude`;
marcador `SAIKIT-KIMI-OWNED` (no existe, no lo pide el DoD); el gate sigue
advisory.

**Chequeos de premisa (no eran hallazgos):** el contrato inyectado sigue siendo
71 líneas (`hooks/summonaikit-harness.sh:589-659`); el vivo y la fuente llevan
`# SAIKIT-CLAUDE-OWNED summonaikit-claude 1.0.0` en la línea 2; `summonaikit-kimi`
no tiene `.pre-commit-config.yaml`.

---

## Por qué ahora (premisa verificada, no supuesta)

El hook **vivo** en `~/.claude/hooks/summonaikit-harness.sh` es propiedad de
`summonaikit-claude`. Verificado leyendo la línea 2 del archivo instalado **y** de
la fuente del repo: ambas dicen `# SAIKIT-CLAUDE-OWNED summonaikit-claude 1.0.0`.
`summonaikit-claude` lo instala **entero** desde su propia fuente (Task 2.1
byte-a-byte + Task 2.4 install global con `--restore-vendor`) y encima le corrigió
A1–A11 (Phase 3). Es decir: el hook que Kimi lee en runtime **divergió del vendor**;
lo que hoy puede mover `TEST_RUNNER_RE`, el mapeo de roles y las anclas del contrato
—justo las regiones que vigila el detector de drift— es `summonaikit-claude`, no el
vendor ni quality-kit (Task 4.1 sacó `.claude` de `$targets`).

Mientras los documentos de Kimi sigan diciendo "es lo que el vendor mejora entre
versiones" / "no hay repositorio fuente" / "avisa cuando el vendor lo cambia" /
"AVISO = parche de quality-kit", **mienten sobre el dueño del contrato** y oscurecen
a quién mirar cuando salte `DRIFT`. Esta task corrige eso. Es **declaración, no
cambio de comportamiento**.

## Distinción que rige la cirugía (leer antes de tocar nada)

El repo Kimi usa dos vocablos parecidos que **no son lo mismo**:

- **`vendorizada` / `vendorizado` / `VENDORED_HARNESS_CONTEXT` / `vendored_contract()`
  / `refresh_vendored_contract.sh`** = jerga interna para la **copia embebida del
  contrato como respaldo**. Es **string funcional**: el hook la emite por stderr
  (`hooks/summonaikit-harness-kimi.sh:120,188`) y `tests/test_extract_contract.sh:89`
  la afirma con `grep -qi 'vendorizada'`. **NO se toca.** Renombrarla arrastra una
  cascada de tests y de símbolos-delimitadores por cero valor de comportamiento, y el
  DoD no la exige.
- **`el vendor` / `lo que el vendor mejora` / `el vendor lo cambia` / `el vendor
  mueve` / `kit del vendor … no hay repo fuente`** = afirma que el **upstream que
  Kimi sigue** es el kit del vendor. **Esto es lo falseado** y lo que el DoD destierra
  → se reemplaza por `summonaikit-claude` (el dueño declarado del hook).
- **`parche local de quality-kit` como causa típica de AVISO** = el otro actor
  equivocado. Tras la 4.1, quality-kit no escribe el hook de Claude. Misma cirugía,
  mismo motivo.

Una salvedad honesta: "el SummonAI Kit es un producto de terceros … no hay
repositorio fuente" **sigue siendo cierto para el kit** (binario `summonaikit` +
agentes + skills). Lo que cambió es más angosto: **el hook de Claude que Kimi lee**.
La cirugía respeta esa frontera —aclara el dueño del hook sin borrar que el kit en
sí sigue siendo de terceros.

**No reintroducir `el vendor` / `del vendor` ni siquiera como contraste** ("no el
vendor", "ya no es el del vendor"). La propiedad se declara nombrando a
`summonaikit-claude`; el contraste sobra y rompe el grep de la DoD.

## Qué cambia y qué NO

**NO cambia:**
- Control-flow del hook de Kimi, del detector, ni del refresh. `[tdd:skip:docs-only]`.
- Tests: ningún assert, ningún fixture. Sólo **comentarios** en
  `tests/test_check_drift.sh` (§G, §G2).
- Símbolos ni strings funcionales: `VENDORED_HARNESS_CONTEXT`, `vendored_contract()`,
  `refresh_vendored_contract.sh`, y toda ocurrencia de `vendorizada`/`vendorizado`.
- El **pin congelado** `docs/pinned/summonaikit-harness.claude.sh` (snapshot del
  2026-08-09, pre-marcador): editarlo falsificaría el pin. Re-pinnear (`--pin`) es un
  acto consciente aparte y **no corresponde acá** (las regiones no se movieron ⇒ no
  hay `DRIFT` que aceptar).
- `docs/pinned/claude-hook.sha256` (el hash de referencia): idem, no se toca.
- El `printf '\n# parche local:…'` de `test_check_drift.sh:85` (contenido del
  caso sintético, no nombra actor).

**Cambia (prosa/comentarios + 1 echo):**
- `docs/spec/00-project-spec.md` (spec — objetivo principal), `README.md`,
  `Plans.md` (framing, no status), `hooks/summonaikit-harness-kimi.sh` (comentarios),
  `tools/check_drift.sh` (comentarios **y** el echo de AVISO en :95),
  `tools/refresh_vendored_contract.sh` (comentarios), y
  `tests/test_check_drift.sh` (comentarios :80 y :96).

---

## A) `summonaikit-kimi/docs/spec/00-project-spec.md` (primario)

### A1. Core Rule 1 (lín. 27–31)
**Hoy:**
> Pero el **contrato de 71 líneas** que se le inyecta al modelo NO se reimplementa:
> se extrae en tiempo de ejecución del heredoc `HARNESS_CONTEXT` del hook vivo de
> Claude. Ese texto es el valor del kit y es lo que el vendor mejora entre versiones;
> reimplantarlo lo condena a quedarse viejo en silencio.

**Propuesta:**
> Pero el **contrato de 71 líneas** que se le inyecta al modelo NO se reimplementa:
> se extrae en tiempo de ejecución del heredoc `HARNESS_CONTEXT` del hook vivo de
> Claude. Ese texto es el valor del kit. **El hook vivo de Claude es propiedad del
> repo `summonaikit-claude`** (lo instala entero con su marcador
> `# SAIKIT-CLAUDE-OWNED` en `~/.claude/hooks/summonaikit-harness.sh`):
> es ese repo quien hoy lo mejora entre versiones; reimplantarlo lo
> condena a quedarse viejo en silencio.

### A2. Core Rule 2 (lín. 32–33)
**Hoy:** `Un hash pinneado del hook de Claude avisa cuando el vendor lo cambia.`
**Propuesta:** Un hash pinneado del hook vivo de Claude avisa cuando
`summonaikit-claude` lo cambia (el dueño declarado del hook — ver Core Rule 1).

### A3. Divergencia conocida #3 (lín. 119)
**Hoy:** `La LISTA de runners sigue siendo la del vendor (el drift la vigila); solo
el USO diverge.`
**Propuesta:** La LISTA de runners sigue siendo la del hook de
`summonaikit-claude` (el drift la vigila); solo el USO diverge.

### A4. Contrato de drift (lín. 132)
**Hoy:** `El hash del hook vivo de Claude (\`~/.claude/hooks/summonaikit-harness.sh\`)
se pinnea en el repo.`
**Propuesta:** El hash del hook vivo de Claude
(`~/.claude/hooks/summonaikit-harness.sh`, propiedad de `summonaikit-claude` — ver
Core Rule 1) se pinnea en el repo.

### A5. Non-Goals (lín. 144)
**Hoy:** `- No se hace fork del kit del vendor: no hay repo fuente que forkear.`
**Propuesta:**
> - No se hace fork: ni del kit de terceros (producto de terceros, sin repo fuente) ni
>   de `summonaikit-claude` (que sí es un repo, pero el port sigue su contrato **por
>   extracción en runtime + detector de drift**, no por bifurcación — son dos hooks
>   con plomería distinta sobre el mismo contrato).

### A6. Links (lín. 163)
**Hoy:** `- gon0801/quality-kit — heal del sentinel para Claude (repo independiente)`
**Propuesta:** `- gon0801/quality-kit — heal del sentinel para Codex/Cursor/\`.agents\`
(Claude ya no: el hook lo instala \`summonaikit-claude\` entero)`
Agregar encima (o al lado) un link a `gon0801/summonaikit-claude` — dueño del hook
vivo de Claude que este port lee.

## B) `summonaikit-kimi/README.md`

### B1. "Qué es esto" (lín. 7–12)
**Hoy:**
> El SummonAI Kit es un producto de terceros: el binario `summonaikit` se autentica
> contra su servidor y baja el kit ya armado (hook + agentes + skills). No hay
> repositorio fuente. Este repo **no es un fork** — contiene un hook propio para
> Kimi, escrito desde cero contra el contrato de hooks de Kimi, que reproduce el
> comportamiento del hook de Claude.

**Propuesta:**
> El SummonAI Kit es un producto de terceros: el binario `summonaikit` se autentica
> contra su servidor y baja el kit ya armado (hook + agentes + skills). No hay
> repositorio fuente del **kit**. **El hook instalado en
> `~/.claude/hooks/summonaikit-harness.sh` es propiedad del
> repo `summonaikit-claude`**, que lo instala con su marcador `# SAIKIT-CLAUDE-OWNED`.
> Este repo **no es un fork** ni del kit ni de `summonaikit-claude` — contiene un
> hook propio para Kimi, escrito desde cero contra el contrato de hooks de Kimi, que
> reproduce el comportamiento del hook de Claude.

### B2. "El contrato se lee, no se copia" (lín. 25–33)
**Hoy:**
> Las 71 líneas que se le inyectan al modelo se extraen en tiempo de ejecución del
> heredoc `HARNESS_CONTEXT` del hook vivo de Claude, con una copia vendorizada como
> respaldo. Ese texto es el valor real del kit y es lo que el vendor mejora entre
> versiones; …
>
> … un **detector de drift** compara el hook de Claude contra un hash pinneado y
> avisa cuando el vendor lo cambia …

**Propuesta:**
> Las 71 líneas que se le inyectan al modelo se extraen en tiempo de ejecución del
> heredoc `HARNESS_CONTEXT` del hook vivo de Claude, con una copia vendorizada como
> respaldo. Ese texto es el valor real del kit. **Ese hook es propiedad de
> `summonaikit-claude`**: es ese repo quien lo mejora entre
> versiones, y reimplantarlo lo condenaría a quedarse viejo sin que nadie note. …
> (La "copia vendorizada" es jerga interna para el respaldo embebido; ver § Independencia.)
>
> … un **detector de drift** compara el hook vivo de Claude contra un hash pinneado
> y avisa cuando `summonaikit-claude` lo cambia …

### B3. Sección Verificación (lín. 82)
**Hoy:** `` bash tools/check_drift.sh      # ¿el vendor movió algo de lo que copiamos? ``
**Propuesta:** `` bash tools/check_drift.sh      # ¿summonaikit-claude movió algo de lo que copiamos? ``

### B4. "Qué hacer cuando salta DRIFT" (lín. 95–97)
**Hoy:**
> - **`AVISO` (exit 0)** — el hook de Claude cambió, pero no en lo que este port
>   copia. Es lo que pasa con cada parche local de `quality-kit`. No requiere nada;

**Propuesta:**
> - **`AVISO` (exit 0)** — el hook de Claude cambió, pero no en lo que este port
>   copia. Es lo que pasa cuando `summonaikit-claude` edita regiones que este port
>   no copió (comentarios, marcador, plomería propia). No requiere nada;

### B5. Relacionados (lín. 119)
**Hoy:** `- gon0801/quality-kit — candados de calidad + heal del sentinel de Claude`
**Propuesta:** agregar `gon0801/summonaikit-claude` (dueño del hook vivo de Claude
que este port lee) y reword de quality-kit a "heal del sentinel de
Codex/Cursor/`.agents`" (Claude ya no).

### B6. Independencia (lín. 37–39)
**Hoy:** `` `quality-kit` sigue siendo el dueño del heal del sentinel para Claude/Codex/Cursor/`.agents` ``
**Propuesta:** `` `quality-kit` sigue siendo el dueño del heal del sentinel para Codex/Cursor/`.agents` (Claude ya no: lo instala `summonaikit-claude` entero) ``

## C) `summonaikit-kimi/Plans.md` (framing en present-tense, no status)

> Afirmaciones en **presente** ("sigue siendo", "mueve", "cambia con cada parche")
> que hoy son falsas. El status `cc:完了` **no se toca**; se reescribe sólo la
> palabra que afirma el dueño / la causa. Sin nota fechada.

### C1. Task 2.15 descripción (lín. 41)
**Hoy:** `… la lista de runners sigue siendo la del vendor, y la divergencia queda
declarada en el spec`
**Propuesta:** … la lista de runners sigue siendo la del hook de
`summonaikit-claude`, y la divergencia queda declarada en el spec.

### C2. Phase 4 Purpose (lín. 57)
**Hoy:** `Purpose: probar la paridad con evidencia, y detectar cuando el vendor
mueve el piso.`
**Propuesta:** Purpose: probar la paridad con evidencia, y detectar cuando
`summonaikit-claude` (el dueño declarado del hook de Claude) mueve el piso.

### C3. Task 4.1 descripción (lín. 62)
**Hoy:** `… CALIBRADO en dos niveles porque el hash entero cambia con cada parche
local de quality-kit: …`
**Propuesta:** … CALIBRADO en dos niveles porque el hash entero cambia con cada
edición de `summonaikit-claude` que no toca lo que el port copió: …

## D) `summonaikit-kimi/hooks/summonaikit-harness-kimi.sh` (comentarios)

### D1. Header (lín. 5–7)
**Hoy:** `# reimplementa: se extrae del hook vivo de Claude por los delimitadores de
su / # heredoc, con copia vendorizada embebida como respaldo (Task 2.2).`
**Propuesta:** `# reimplementa: se extrae del hook vivo de Claude (propiedad de
# summonaikit-claude) por los delimitadores de su heredoc, con copia vendorizada
# embebida como respaldo (Task 2.2).`

### D2. Bloque HARNESS-CONTRACT-EXTRACTION (lín. 35–36)
**Hoy:** `# al fail-open: anclas rotas = drift estructural del vendor (Core Rule 2) y
# tiene que gritar, no degradar en silencio.`
**Propuesta:** `# al fail-open: anclas rotas = drift estructural del hook de
# summonaikit-claude (Core Rule 2) y tiene que gritar, no degradar en silencio.`

### D3. Comentario interno (lín. 216)
**Hoy:** `# hook de Claude (si el vendor la cambia lo avisa el detector de drift, …`
**Propuesta:** `# hook de Claude (si summonaikit-claude la cambia lo avisa el
detector de drift, …`  *(leer la línea completa al editar; es un comentario
multilinea que envuelve).*

## E) `summonaikit-kimi/tools/check_drift.sh` (comentarios + 1 echo)

### E1. Bloque "QUÉ VIGILA" (lín. 7–9)
**Hoy:** `#   1. El CONTRATO se extrae en runtime. Si el vendor lo cambia, el port
lo / #      sigue solo. Ya hay un guard para su copia vendorizada`
**Propuesta:** `#   1. El CONTRATO se extrae en runtime. Si summonaikit-claude (el
dueño / #      del hook de Claude) lo cambia, el port lo sigue solo. Ya hay un guard
para / #      su copia vendorizada`

### E2. (lín. 11–12)
**Hoy:** `#      los sigue solos: si el vendor los cambia, este port se queda viejo
EN / #      SILENCIO. Esto es lo que de verdad vigila este detector.`
**Propuesta:** `#      los sigue solos: si summonaikit-claude los cambia, este port
se queda / #      viejo EN SILENCIO. Esto es lo que de verdad vigila este detector.`

### E3. Calibración (lín. 16–18)
**Hoy:** `# CADA parche local de quality-kit (el sentinel, el review-notice).`
**Propuesta:** `# CADA edicion de summonaikit-claude que no toca las regiones
copiadas (comentarios, marcador, plomeria propia).`

### E4. Echo de AVISO (lín. 95) — única línea que no es comentario
**Hoy:** `echo "check_drift: (tipico: un parche local de quality-kit). Re-pinear cuando quieras:"`
**Propuesta:** `echo "check_drift: (tipico: una edicion de summonaikit-claude fuera de las regiones copiadas). Re-pinear cuando quieras:"`

No es control-flow. `test_check_drift.sh:92` sólo busca `AVISO`. ASCII, mismo
estilo que el resto del archivo (`tipico`, `edicion`, sin tilde).

## F) `summonaikit-kimi/tools/refresh_vendored_contract.sh` (comentarios)

### F1. Header (lín. 6–7)
**Hoy:** `# Se corre cuando el detector de drift (Task 4.1) avisa que el vendor
movio / # el contrato y se decidio seguir el cambio.`
**Propuesta:** `# Se corre cuando el detector de drift (Task 4.1) avisa que
summonaikit-claude / # movio el contrato y se decidio seguir el cambio.`

> **No se tocan** (strings/símbolos internos): `VENDORED_HARNESS_CONTEXT`,
> `refresh_vendored_contract:` (prefijo de todos los echoes), `bloque vendorizado
> refrescado` (lín. 71). `vendorizado` = "la copia embebida", no el actor upstream.

## G) `summonaikit-kimi/tests/test_check_drift.sh` (comentarios, **requerido**)

### G1. (lín. 96)
**Hoy:** `# 4) DRIFT de verdad: el vendor cambia TEST_RUNNER_RE, que este port copia`
**Propuesta:** `# 4) DRIFT de verdad: summonaikit-claude cambia TEST_RUNNER_RE, que
este port copia`

### G2. (lín. 80)
**Hoy:** `# parche local de quality-kit sobre el hook de Claude). Debe AVISAR sin gritar:`
**Propuesta:** `# edicion de summonaikit-claude fuera de las regiones copiadas). Debe AVISAR sin gritar:`

No tocar `:85` (`printf '\n# parche local: no toca TEST_RUNNER_RE…'`): es el
contenido sintético del caso, no afirma actor.

---

## Cómo se verifica cada cláusula de la DoD

Correr los greps en **Git Bash** (el `grep -r --include` de GNU; no el alias de
PowerShell).

1. **"El spec declara la nueva fuente"** — `grep -niE 'summonaikit-claude'
   docs/spec/00-project-spec.md` devuelve hits en Core Rule 1, Core Rule 2,
   Divergencia #3, Contrato de drift, Non-Goals y Links (A1–A6).
2. **"Su detector de drift apunta a lo correcto"** — **ya cierto por código**:
   `tools/check_drift.sh:33` usa
   `claude_hook="${SAIKIT_CLAUDE_HOOK:-$HOME/.claude/hooks/summonaikit-harness.sh}"`,
   y ese archivo lleva el marcador de `summonaikit-claude`. El aporte de esta task es
   alinear los **comentarios** y el echo de AVISO (§E). Verificación: el detector
   corre en silencio / exit 0 sobre el perfil real (nada se movió).
3. **"Ningún documento sigue afirmando que el contrato se sigue del vendor"** —
   receta (Git Bash, desde `C:/dev/summonaikit-kimi`):
   ```
   grep -rniE "el vendor|del vendor|lo que el vendor|vendor (lo|mueve|mejora|movio|la cambia)" \
     --include='*.md' --include='*.sh' --include='*.py' \
     --exclude-dir=pinned --exclude-dir=sandbox --exclude-dir=out --exclude-dir=.git \
     .
   ```
   ⇒ **0 hits.** Lo que **sí** debe seguir apareciendo (otro grep, no éste):
   `vendorizada` / `vendorizado` (respaldo embebido, string funcional) y
   "SummonAI Kit es un producto de terceros / no hay repositorio fuente del **kit**"
   (cierto para el kit, no para el hook).
4. **Actor de AVISO (hallazgo 2 de la review)** — el mismo barrido, frase
   quality-kit-como-quien-mueve-el-hook:
   ```
   grep -rniE "parche local de quality-kit|cada parche local de .quality-kit" \
     --include='*.md' --include='*.sh' \
     --exclude-dir=pinned --exclude-dir=sandbox --exclude-dir=out --exclude-dir=.git \
     .
   ```
   ⇒ **0 hits.** `quality-kit` como dueño del heal de Codex/Cursor/`.agents` y
   como "este repo no depende de quality-kit" **sí** deben quedar.

## Límites declarados (no cerrados por esta task)

1. **`vendorizada` se conserva** — es jerga interna (= copia embebida de respaldo) y
   string funcional; renombrarla está fuera del DoD y rompería `test_extract_contract.sh`.
2. **No se re-pinea el hook** — las regiones vigiladas (TEST_RUNNER_RE, mapeo de roles,
   anclas) no se movieron; no hay `DRIFT` que aceptar. Re-pinnear es un acto consciente
   aparte (`check_drift.sh --pin`).
3. **El pin congelado** `docs/pinned/summonaikit-harness.claude.sh` queda **intacto**
   (snapshot histórico pre-marcador; editarlo falsificaría el pin).
4. **`summonaikit-claude` no gana marcador propio en el hook de Kimi** — el hook de
   Kimi no lleva `SAIKIT-KIMI-OWNED` (no existe; no lo pide el DoD). Simetría con
   Claude queda como posible task futura, no acá.
5. **El spec del repo Claude** (`summonaikit-claude/docs/spec/00-project-spec.md`) no
   se toca: el DoD apunta al spec y detector de **Kimi**, no a éste.
6. El **gate sigue advisory** (no cambia en una task de docs).
7. **El echo de AVISO (§E4) es prosa, no comportamiento.** Si un test futuro
   empezara a afirmar el substring `quality-kit` del echo, eso sería un test
   nuevo — hoy no existe.

## Orden de commits

1. **`summonaikit-kimi`** (1 commit): §A–§G — prosa/comentarios + el echo de AVISO
   en un solo commit `docs(4.2): declarar dueño del contrato — Kimi sigue a
   summonaikit-claude, no al vendor`.
2. **`summonaikit-claude`** (1 commit): `docs/task-4.2-plan.md` (este doc) +
   `Plans.md:77` → `cc:完了 [<sha-summonaikit-kimi>]`. *(Convención: la columna
   Status de Plans.md cita el commit del repo donde vivió el cambio; aquí el
   cambio vive en Kimi, así que el SHA es el de Kimi.)*

## Candados / validación final

- `summonaikit-kimi` **no tiene** `.pre-commit-config.yaml` (verificado) ⇒ sin
  candados de commit. Validación (Git Bash):
  - `bash -n` sobre cada `.sh` tocado (trivial: comentarios + un echo; pero corre
    para no romper la regla de higiene).
  - `bash tests/run.sh` verde (**regresión**: nada debió moverse; 18 archivos).
  - `bash tools/check_drift.sh` ⇒ silencio / exit 0 (el hook vivo no cambió).
  - `bash tools/parity_harness.sh` ⇒ los 5 campos siguen coincidiendo.
  - Los dos greps de la DoD (cláusulas 3 y 4) ⇒ 0 hits.
- `summonaikit-claude`:
  - `pre-commit run --all-files` (regla de hierro: jamás `--no-verify`).
  - `tests/run.sh` verde (gate final). Esta task **no toca la fuente del hook**, así
    que la baseline dorada no se mueve.
- Regla de hierro del quality-kit: cada bug arreglado incluye su prueba. Esta task es
  `[tdd:skip:docs-only]` — no arregla un bug ni cambia comportamiento; su "prueba" es
  el grep de verificación del DoD (cláusulas 3 y 4).

## Cross-review del CÓDIGO
Regla del repo: **sólo si el operador la pide**. Se ofrece al cerrar; no se auto-corre.
