# Phase 22 Implementation Plan

> **For agentic workers:** las filas de `Plans.md` (22.1–22.4) son el contrato; este plan las aterriza a archivos, casos y mutantes concretos. TDD rojo/verde por fila, un PR por fila, carril según la fila.

**Goal:** corregir los cuatro hallazgos medidos en vivo durante las mediciones 20.9–20.11 (reconocimiento del runner de blast, guard de merge que niega lecturas, frescura de sha en `ci_chequear`, referencia rota en `cuidar-pr`).

**Architecture:** tres fixes acotados (hook PreToolUse, `tools/saikit-merge.sh`, linter de recetas) y una decisión de convención (22.1 vía (a): wrapper `tests/run.sh` generado/verificado por el setup, sin tocar el vocabulario cerrado del hook).

**Tech Stack:** bash (hook + tools), test suites propias (`tests/test_gate_behavior.sh`, `tests/test_gate_mutations.sh`, `tests/test_saikit_merge.sh`, `tests/test_recetas.sh`).

**Spec:** `Plans.md` líneas 261–264 (filas 22.1–22.4 con sus DoD literales). Evidencia de origen: `docs/evidence/phase-20/20.10/runs/turn1.json` (22.1), `docs/evidence/phase-20/20.11/runs/turn-cuidar-denials.txt` (22.2, 22.3, 22.4).

## Global Constraints

- Rojo MEDIDO antes del verde, con salida pegada en el PR; por cada protección, una mutación que la ponga roja (`tests/test_gate_mutations.sh` con `SAIKIT_MUTACIONES` acotada a las líneas tocadas).
- TDD rojo/verde sobre UN archivo de test con `SAIKIT_HOOK_VIVO="$PWD/hooks/summonaikit-harness.sh"` + `HOME`/`TMPDIR`/`USERPROFILE` aislados (regla 1 de AGENTS.md); nunca contra el perfil vivo del operador.
- `pre-commit run --files <tocados>` durante el dev; `--no-verify` jamás. Gate final = job `gate` del CI en verde.
- Rama desde `origin/master` con `git fetch` previo; el número de fila NO va como scope del commit (usar `fix(hook):`, `fix(tools):`, `fix(tests):`…).
- `Plans.md` PROHIBIDO para el implementador; las filas las cierra el líder tras mergear.
- Un PR por fila (son independientes). Carril: 22.4 = `fast` (bots + lead); 22.1/22.2/22.3 = `gate` (+ reviewer del harness).
- No cambiar la semántica fail-closed de nada que no esté en la DoD de la fila.

---

### Task 1: 22.4 — Referencia rota `.saikit/triage-patrones.md` (carril fast)

**Decisión (declarada en el PR):** NO crear el archivo semilla — **ya existe** en el kit (`.saikit/triage-patrones.md`, 2258 bytes, desde `f36be8a`, Phase 18) con la rúbrica fix/dismiss/ask y el patrón «rate limited ≠ revisión». La premisa de la fila era imprecisa: la medición 20.11 corrió en el repo descartable, donde no existe. La referencia se queda pero se marca **opt-in** y la receta queda autocontenida; el checker nuevo garantiza las referencias de TODAS las recetas.

**Files:**
- Modify: `recetas/cuidar-pr.md:15` (paso 4)
- Modify: `tests/lib/recetas_lint.sh` (nueva regla de referencias en prosa)
- Modify: `tests/test_recetas.sh` (casos sandbox + caso repo-real)
- Regenerate: `recetas/MANIFEST.sha256` (`bash tools/gen-recetas-manifest.sh`)

**Interfaces:**
- Consumes: `lint_receta()` de `tests/lib/recetas_lint.sh` (ya tiene el check de links markdown `:66-68`); helpers `caso`/`malo`/`buena`/`sed_i` de `tests/test_recetas.sh`.
- Produces: regla nueva dentro de `lint_receta`: todo token entre backticks con pinta de ruta (regex `[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)+`) debe existir relativo a la RAÍZ del repo, salvo: (i) tokens con `<`/`>` (placeholders como `origin/<base>`), (ii) tokens que empiezan con `$` (p.ej. `$HOME/...`), (iii) líneas marcadas `(opt-in)` o `(externa)`. Mensaje de fallo: `referencia rota: <token>`.

- [ ] **Step 1: Test rojo — referencia rota plantada en sandbox**

Agregar a `tests/test_recetas.sh` (patrón `buena` + append, como el caso de término prohibido `:45-51`):

```bash
caso "referencia rota en prosa => 1 con motivo"
buena "$SANDBOX/p/bug.md"
printf 'Sigue los patrones de `.saikit/no-existe.md` siempre.\n' >> "$SANDBOX/p/bug.md"
out="$(lint_receta "$SANDBOX/p/bug.md")" && malo "acepto referencia rota"
printf '%s' "$out" | grep -q "referencia rota" || malo "motivo sin 'referencia rota': $out"

caso "referencia opt-in marcada => pasa"
buena "$SANDBOX/p/bug2.md"
printf 'Si existe `.saikit/triage-patrones.md` (opt-in), aplicalo.\n' >> "$SANDBOX/p/bug2.md"
out="$(lint_receta "$SANDBOX/p/bug2.md")" || malo "rechazo referencia opt-in: $out"

caso "placeholder y ruta externa => pasa"
buena "$SANDBOX/p/bug3.md"
printf 'Hace `git fetch origin <base>` y mira `$HOME/.claude/saikit-tools/x.sh` (externa).\n' >> "$SANDBOX/p/bug3.md"
out="$(lint_receta "$SANDBOX/p/bug3.md")" || malo "rechazo placeholder/externa: $out"
```

Ojo: `lint_receta` resuelve contra la raíz del repo bajo test — el sandbox de recetas vive fuera del repo; la regla debe recibir la raíz como la recibe el check de links (`$(dirname "$f")/..` NO sirve para `.saikit/...`). Definir: la regla resuelve contra `$REPO_ROOT` (dir del `.git` que contiene `recetas/`; en sandbox, el dir padre del dir de recetas sembrado). Ajustar `buena` para sembrar también `.saikit/triage-patrones.md` vacío si hace falta un positivo.

- [ ] **Step 2: Correr y verificar rojo**

Run: `SAIKIT_HOOK_VIVO="$PWD/hooks/summonaikit-harness.sh" bash tests/test_recetas.sh`
Expected: FAIL — el caso de referencia rota pasa en verde indebido (la regla no existe).

- [ ] **Step 3: Implementar la regla en `tests/lib/recetas_lint.sh`**

Dentro de `lint_receta`, tras el check de links (`:66-68`):

```bash
# rutas en prosa/backticks tienen que existir (raíz del repo) salvo marca
while IFS= read -r linea; do
  case "$linea" in *"(opt-in)"*|*"(externa)"*) continue ;; esac
  for tok in $(printf '%s' "$linea" | grep -Eo '`[A-Za-z0-9_.$-]+(/[A-Za-z0-9_.$-]+)+/?`' | tr -d '`'); do
    case "$tok" in *"<"*|*">"*|'$'*) continue ;; esac
    [ -e "$repo_root/$tok" ] || { echo "referencia rota: $tok"; rc=1; }
  done
done < "$f"
```

(`$repo_root` se computa una vez en el linter; documentar en comentario la decisión raíz-del-repo, no relativo-a-la-receta, porque las referencias son `.saikit/...` y `tools/...`.)

- [ ] **Step 4: Editar la receta y regenerar el manifiesto**

`recetas/cuidar-pr.md:15` — paso 4 queda autocontenido con la marca:

```
4. **Hilos de bots** (Greptile, CodeRabbit y similares): evalúa cada hallazgo con la rúbrica **fix / dismiss / ask**; si el repo trae `.saikit/triage-patrones.md` (opt-in), aplica también los patrones aprendidos ahí (si no existe, la rúbrica de este paso alcanza):
```

`recetas/00-lider.md:44` — la línea de `$HOME/.claude/saikit-tools/saikit-decision.sh` queda marcada `(externa)`.
Luego: `bash tools/gen-recetas-manifest.sh` y verificar `bash tools/gen-recetas-manifest.sh --check` (rc 0).

- [ ] **Step 5: Verde + caso repo-real**

Agregar al bloque repo-real de `tests/test_recetas.sh` (junto a la regla de orden `:179-198`): loop que corre `lint_receta` sobre `recetas/*.md` reales y exige rc 0 (ya existe el loop `:174+`; la regla nueva corre sola ahí).
Run: `bash tests/test_recetas.sh` → OK. Commit: `fix(tests): checker de referencias de archivos en recetas + marca opt-in triage-patrones (roto en consumidores)`.

- [ ] **Step 6: Sweep de fichas + PR carril fast**

La DoD pide el sweep general de recetas **y fichas**: grep de referencias a archivos en `docs/spec/*.md` y las fichas del feature map; cualquier referencia rota se reporta en el PR (si aparecen, se corrigen o se marcan en el mismo PR; el checker nuevo cubre `recetas/`, las fichas quedan barridas y declaradas). PR con el rojo medido pegado, la decisión (archivo ya existe en el kit; la referencia queda opt-in), y nota de que `recetas/pendientes/` está vacío.

---

### Task 2: 22.3 — Frescura de sha en `ci_chequear` (carril gate)

**Files:**
- Modify: `tools/saikit-merge.sh` (`ci_chequear`, ~`:424-460`)
- Modify: `tests/test_saikit_merge.sh` (casos + `refix()` + banco de mutaciones `:1588-1623`)

**Interfaces:**
- Consumes: `$SHA` (head bajo gate, ya comparado en `:290`), el gh falso del test (`tests/test_saikit_merge.sh:129-272`; ignora flags y sirve `$SB/ghfix/runs.json`), `refix()` (`:309-319`).
- Produces: `ci_chequear` solo acepta verde del sha exacto bajo gate; rechazo con razón nombrada (`NO-MERGE: CI verde pero de otro sha (...)`). Estados VERDE/ROJO/PENDIENTE/JSON inválido intactos.

- [ ] **Step 1: Test rojo — verde de otro sha se acepta hoy**

En `tests/test_saikit_merge.sh`, caso nuevo (patrón `:449-456`):

```bash
caso "ci_verde_de_otro_sha_no_merguea"
{
  printf '[{"event":"pull_request","status":"completed","conclusion":"success","workflow":"ci","headSha":"0000000000000000000000000000000000000000"}]' > "$SB/ghfix/runs.json"
  correr --confirmado
  _contiene "razon sha ajeno" "$OUT" "NO-MERGE: CI verde pero de otro sha"
  if merge_disparado; then _mal "mergeo con verde de otro sha"; fi
}
fin_caso "ci_verde_de_otro_sha_no_merguea"
```

Además `refix()` (`:315`) debe incluir `"headSha"` del HEAD real en el runs.json verde por defecto, o TODOS los casos existentes se ponen rojos (el verde sano tiene que seguir pasando: es el control).

- [ ] **Step 2: Correr y verificar rojo**

Run: `bash tests/test_saikit_merge.sh`
Expected: el caso nuevo sale verde indebido (hoy se acepta el verde ajeno) y/o NO-MERGE no nombra el sha.

- [ ] **Step 3: Fix en `ci_chequear`**

En `tools/saikit-merge.sh`, donde hoy se listan los runs (~`:435`): pedir los runs del commit exacto y exigir correspondencia local:

```bash
gh run list --commit "$SHA" --json status,conclusion,event,workflow,headSha ...
# y al evaluar: todo run requerido con conclusion=success tiene que tener headSha == $SHA;
# si el campo viene y no calza => no_merge "CI verde pero de otro sha ($head != $SHA)"
```

(Mantener la clasificación VERDE/ROJO/PENDIENTE existente y el rechazo de JSON inválido; el gh falso tolera cualquier `--json`. Si `--commit` ya está, el fix es solo la verificación local de `headSha`.)

- [ ] **Step 4: Verde + estados conservados**

Run: `bash tests/test_saikit_merge.sh` → OK, incluidos `ci_rojo_no_merguea`, `ci_pendiente`, `skipped`, `solo_push`, `sin_checks`.

- [ ] **Step 5: Mutante en el banco**

Fila nueva en el banco TSV (`:1588-1623`): `ci_sin_chequeo_sha<TAB>s/...quitar la comparación headSha.../<TAB>ci_verde_de_otro_sha_no_merguea` — la mutación deja el caso en verde indebido. Correr el banco auto-auditado (`:1625-1676`).

- [ ] **Step 6: PR carril gate**

Rojo medido pegado + mutante. Commit: `fix(tools): ci_chequear exige verde del sha exacto bajo gate`.

---

### Task 3: 22.2 — El guard de merge permite lecturas del script (carril gate)

**Causa raíz (medida en exploración):** `pretool_token_hatch` (`hooks/summonaikit-harness.sh:4466-4482`) toma CUALQUIER token cuyo basename sea `saikit-merge.sh` y `pretool_hatch_verifica` (`:4501-4530`) exige path existente + sha256 == pin del `MANIFEST.sha256`. Un token con `:` (`origin/main:tools/saikit-merge.sh`) nunca resuelve → deny. La guardia no distingue invocación de mención.

**Files:**
- Modify: `hooks/summonaikit-harness.sh` (`pretool_merge_guard` `:4532-4560`; predicado nuevo junto a `pretool_es_hatch` `:4446`)
- Modify: `tests/lib/gate_cases.sh` (`CASOS_G7` `:4519`; helpers `_g7_*` `:4521-4548`)
- Modify: `tests/test_gate_mutations.sh` (catálogo G7 `:189-201` + `mut_` nueva)

**Interfaces:**
- Consumes: `lab_payload_pretool_bash` (`tests/lib/hook_lab.sh:302`), `_g7_plantar_hatch match|mismatch`, `_g7_assert_deny`/`_g7_assert_allow`, driver `tests/test_pretool_merge.sh` (recoge `$CASOS_G7`).
- Produces: predicado `pretool_es_lectura_hatch <cmd>` → 0 si el comando COMPLETO es una lectura simple que menciona el script (sin `;`, `|`, `&`, `<`, `>`, `$(`, backtick fuera de la forma simple), con verbo en lista cerrada: `git show|log|diff`, `cat`, `grep`, `head`, `tail`, `less`, `file`, `stat`, `wc`, `sha256sum`, `shasum`; admite prefijo `rtk` (forma medida en 20.11). La evaluación va ANTES del hatch pero DESPUÉS de los patrones a pelo (`gh pr merge`, `gh api /merge`, push protegida, spoof) — esos quedan intactos y primero.

- [ ] **Step 1: Casos rojos (G7)**

En `tests/lib/gate_cases.sh`, siguiendo `caso_g7_niega_hatch_sufijo_bak` como molde:

```bash
caso_g7_permite_git_show_hatch() {
  _g7_plantar_hatch match
  lab_run auto claude "$(lab_payload_pretool_bash 'git show origin/main:tools/saikit-merge.sh')"
  _g7_assert_allow
}
caso_g7_permite_rtk_git_show_hatch() {
  _g7_plantar_hatch match
  lab_run auto claude "$(lab_payload_pretool_bash 'rtk git show origin/main:tools/saikit-merge.sh')"
  _g7_assert_allow
}
caso_g7_permite_grep_hatch() {
  _g7_plantar_hatch match
  lab_run auto claude "$(lab_payload_pretool_bash 'grep -n ci_chequear tools/saikit-merge.sh')"
  _g7_assert_allow
}
```

Y los que SIGUEN negados (controles de no-regresión, varios ya existen): `caso_g7_niega_lectura_encadenada` (`git show origin/main:tools/saikit-merge.sh | bash` → deny — cae al hatch, el token con `:` no resuelve), `gh pr merge` directo, `gh api .../merge`, push a protegida, sufijo `.bak`. Listar los tres nuevos en `CASOS_G7` (`test_gate_behavior.sh:37-55` exige índice exacto).

- [ ] **Step 2: Rojo medido**

Run: `SAIKIT_HOOK_VIVO="$PWD/hooks/summonaikit-harness.sh" bash tests/test_pretool_merge.sh`
Expected: los tres casos `permite_*` en rojo (hoy deny).

- [ ] **Step 3: Fix en el hook**

En `pretool_merge_guard`, tras los chequeos a pelo y antes de `pretool_es_hatch`:

```bash
if pretool_es_lectura_hatch "$1"; then
  :  # lectura simple que menciona el script: no es invocacion
elif printf '%s' "$1" | grep -Eq '(^|[^[:alnum:]._-])saikit-merge\.sh([^[:alnum:]._-]|$)'; then
  ...hatch actual...
fi
```

`pretool_es_lectura_hatch`: trocear el comando; rechazar (return 1) si hay metacaracteres de encadenamiento; quitar prefijo `rtk` opcional; exigir verbo de la lista cerrada; exigir que todo token que mencione `saikit-merge.sh` NO esté en posición de comando.

- [ ] **Step 4: Verde + behavior completo**

Run: `bash tests/test_pretool_merge.sh` → OK; luego `bash tests/test_gate_behavior.sh` → OK (sin regresión en otros gates).

- [ ] **Step 5: Mutante**

`mut_pretool_lectura_vuelve_ancho` (filtro sed que anula el predicado nuevo, p.ej. `s/pretool_es_lectura_hatch/false/`) atrapada por `caso_g7_permite_git_show_hatch`. Agregar fila al catálogo G7 (`:189-201`) y la función `mut_`. Correr acotado: `SAIKIT_MUTACIONES='G7|pretool_lectura_vuelve_ancho|...' bash tests/test_gate_mutations.sh` + las G7 existentes.

- [ ] **Step 6: PR carril gate**

Rojo medido literal (el deny real de `rtk git show ...` citado de `20.11/runs/turn-cuidar-denials.txt`), controles de denegación intactos, mutante. Commit: `fix(hook): el guard de merge distingue lectura de invocacion de saikit-merge.sh`.

---

### Task 4: 22.1 — Runner de blast reconocido (carril gate) — decisión vía (a)

**Decisión (declarada en el PR con su motivación):** vía **(a) convención documentada** — `saikit-setup-autopilot` genera/verifica el wrapper `tests/run.sh` y la guía lo declara. Motivación: es exactamente lo que destrabó la medición 20.10 (descartable, PR #10); mantiene el vocabulario del hook CERRADO (fail-closed, `TEST_RUNNER_CMD_RE` `:272` literal `tests?/run\.sh`); la vía (b) exigiría que el hook leyera config del repo en PostToolUse — canal nuevo hacia el Stop gate que hoy no existe (el hook no lee ningún `.saikit/*.json`, medido) y superficie nueva de bypass.

**Files:**
- Modify: `tools/saikit-setup-autopilot.sh` (ofrecer/generar el wrapper cuando el runner real no es reconocido)
- Modify: `tools/saikit-ci-minimo.sh` si hace falta (su `detectar_test_cmd` `:104-121` ya prefiere `tests/run.sh`)
- Modify: `skills/saikit-setup-autopilot/SKILL.md` + `docs/guia-usuario.html` (declarar la convención)
- Test: `tests/test_autopilot_config.sh` (wrapper generado/verificado por el setup) y `tests/test_ci_minimo.sh` (detección del comando tras generar el wrapper)

**Interfaces:**
- Consumes: detección de runner existente en `saikit-ci-minimo.sh:104-121`; patrón de escritura atómica del setup (`mktemp` en el mismo dir + validar + `mv -f`, como `autopilot.json`).
- Produces: wrapper `tests/run.sh` generado con el comando real detectado:
  ```bash
  #!/bin/sh
  # Generado por saikit-setup-autopilot: wrapper de bateria para el gate saikit (22.1).
  # El gate solo acredita runners reconocidos; este wrapper expone la bateria real.
  exec bash tests/test_app.sh "$@"
  ```
  (con el comando detectado en lugar de `tests/test_app.sh`; chmod +x).

- [ ] **Step 1: Test rojo**

Sandbox-repo con `tests/test_app.sh` y sin `tests/run.sh`: correr el setup → hoy no propone wrapper (rojo: el gate nunca podrá acreditar el blast). Positivo tras el fix: el wrapper existe, es ejecutable, corre la batería real (ejecutarlo y verificar rc/salida), y `detectar_test_cmd` pasa a emitir `bash tests/run.sh`.

- [ ] **Step 2-3: Implementar generación/verificación del wrapper en el setup** (ofrecer antes de escribir, como el resto del asistente; repo con `tests/run.sh` real → no-op verificado; repo sin ningún runner → aviso y sin wrapper, no inventar).

- [ ] **Step 4: Docs** — `skills/saikit-setup-autopilot/SKILL.md` y `docs/guia-usuario.html`: la convención en palabras simples (el gate exige que la batería se corra como `tests/run.sh`, pytest o jest; el setup genera el wrapper si tu batería tiene otro nombre).

- [ ] **Step 5: Verde + mutación acotada + PR carril gate.** Mutante acotada a las líneas tocadas del setup (banco propio del test si lo tiene, patrón de `test_saikit_merge.sh:1588-1623`; si el test del setup no tiene banco, declararlo en el PR y agregar la fila mínima). Commit: `feat(setup): wrapper tests/run.sh para baterias con nombre propio (convencion blast del gate)`.

---

## Orden y dependencias

1. **Task 1 (22.4)** — independiente, carril fast, la más chica.
2. **Task 2 (22.3)** — independiente, solo `tools/saikit-merge.sh` + su test.
3. **Task 3 (22.2)** — toca el hook; conviene después de 22.3 (mismo archivo lógico de merge, pero sin solape de líneas; podrían ir en paralelo si se acepta rebase).
4. **Task 4 (22.1)** — setup + docs; independiente de las otras tres.

Las cuatro pueden correr en paralelo en worktrees distintos salvo 22.2/22.3 si se pisa el rebase; cada una entrega PR propio con CI `gate` verde. Al mergear las cuatro: deploy de las copias del hook (22.2 lo cambia) + cierre de filas en UN PR de ledger.

## Riesgos / notas

- **22.2:** la lista cerrada de verbos de lectura es el punto delicado — un verbo de más abre ejecución encadenada, uno de menos deja la queja original viva. Los controles de deny existentes (`caso_g7_niega_cadena_*`) no se tocan.
- **22.3:** el gh falso ignora flags — el caso rojo depende del fixture `runs.json`, no del `--commit`; declararlo en el PR (la correspondencia local de `headSha` es la protección real).
- **22.1:** documentar que la vía (b) quedó evaluada y descartada con razón (canal nuevo hacia el gate), no por omisión.
- R34 residual conocido: el bash 3.2 del sistema no parsea el hook (preexistente); no empeorar la sintaxis en las líneas tocadas de 22.2.
