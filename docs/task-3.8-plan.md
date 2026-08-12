# Task 3.8 — A11: el guardia de fallas busca `exitCode` que el payload no trae (plan para revisión)

`[Guardrail]` `[lane:fast]` `[tdd:required]`. Cierra **A11**. **DoD íntegra en `Plans.md:68`.**
`spec_path: docs/spec/00-project-spec.md` — contrato canónico del proyecto; se actualiza al cerrar.

**Cross-review del PLAN con codex (1 ronda, 2026-08-12):** 4 hallazgos (3 altos + 1 medio),
**los 4 aceptados enteros** y verificados por mí con `/usr/bin/grep` (GNU grep 3.0, el real
del hook en producción). El plan original era "Minimal" (un grep con `[[:<:]]FAILED[[:>:]]`);
codex demostró que rompía GNU grep (rc=2) y que la rama `FAILED` con `-i` matcheaba `0
failed`. La decisión de alcance pasó a **Amplio con doble grep** (un `-Eiq` CI + un `-Eq`
CS), lo único fiel a la DoD universal "un runner que falla NO acredita" para los
ecosistemas que el hook ya reconoce (cargo/go/phpunit incluidos).

## Hallazgos de codex (aceptados, con verificación propia)

1. **[alta]** `[[:<:]]FAILED[[:>:]]` es inválido en GNU grep 3.0 → `rc=2 "Invalid character
   class name"`. Con `if ! grep`, rc=2 ⇒ "no encontró" ⇒ el guardia acreditaba SIEMPRE
   (rompía TODO el gate). **Verificado.**
2. **[alta]** Aun con `\bFAILED\b` (GNU), `-i` matchea `0 failed`, `passed, 0 failed`,
   `no FAILED entries` ⇒ falso positivo (un runner exitoso con `0 failed` se hubiera tomado
   como fracaso). **Verificado rc=0 en los tres.**
3. **[media]** `mut_falla_failed_quitada` no se acreditaría al caso pytest (la rama
   `FAILED` con `-i` seguiría matcheando `=== 1 failed ===`). Consecuencia de H2. Se
   resuelve al sacar la rama `FAILED` (no la necesitamos: pytest siempre imprime `=== N
   failed ===` además del summary corto).
4. **[alta]** "Minimal" incumplía la DoD universal: `1 failure` (rspec), `Failures: 1`
   (phpunit), `failures=1` (unittest Python), `test result: FAILED.` (cargo), `FAIL\t`
   (go), `FAILURES!` (phpunit banner) NO matcheaban. **Verificado.** → Se adopta Amplio.

## El defecto, con su huella exacta

`hooks/summonaikit-harness.sh:887-891` — el guardia de fallas de `record_tool_evidence`:

```bash
887   if printf '%s' "$tool_name $command_text" | grep -Eiq "$TEST_RUNNER_WORD_RE"; then
888     if ! printf '%s' "$combined" | grep -Eiq 'exitCode[^0-9]*[1-9]|failure_type|permission_denied|command not found'; then
889       mark_evidence "verified" "${command_text:-verification command}"
890     fi
891   fi
```

Cuatro señales en la `:888`, una estructural y tres textuales:

| Señal | Tipo | Estado medido |
|---|---|---|
| `exitCode[^0-9]*[1-9]` | campo JSON | **código muerto** — el `tool_response` real de `Bash` no trae `exitCode` (59/59, Task 1.4) |
| `failure_type` / `permission_denied` / `command not found` | texto | vivas — señales de rechazo/ausencia del tool |

**El hueco:** ninguna cubre "el runner corrió y reventó por aserción". pytest `=== N failed
===`/`FAILED tests/…`; vitest `Test Files N failed`; jest `Tests: N failed`; mocha `N
failing`; rspec `N failures`; phpunit `Failures: N`; unittest Python `failures=N`; cargo
`test result: FAILED.`; go `FAIL\t`; tsc `error TS1234`; Python crudo `Traceback` /
`AssertionError` / `SyntaxError`. Como la postura del bloque es **fail-open** (`if ! grep`),
ausencia de señal = acreditación.

**Segundo consumidor del falso positivo:** `stop_gate` en `:1077` lee `verified` y, si es
`1`, no exige justificación de skip. El falso positivo se propaga al gate de Stop.

**Caso que documenta el defecto (hoy afirma lo falso):** `tests/lib/gate_cases.sh:267-271`:

```bash
caso_g2_runner_fallido_forma_real() {
  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_bash 'npm test' 'AssertionError: expected true to equal false')"
  _igual "verified pese a que la bateria fallo (A11)" "$(lab_estado verified)" "1"
}
```

## El arreglo (Amplio, dos greps)

`hooks/summonaikit-harness.sh:887-891` hoy → mañana:

```bash
  if printf '%s' "$tool_name $command_text" | grep -Eiq "$TEST_RUNNER_WORD_RE"; then
    if ! { printf '%s' "$combined" | grep -Eiq "$FAILURE_SIGNAL_RE_CI" \
           || printf '%s' "$combined" | grep -Eq  "$FAILURE_SIGNAL_RE_CS"; }; then
      mark_evidence "verified" "${command_text:-verification command}"
    fi
  fi
```

Dos constantes nuevas cerca de `TEST_RUNNER_WORD_RE` (`:84`). **Patrones medidos contra
`/usr/bin/grep` GNU 3.0** — cada muestra probada antes de escribirla:

```bash
# Case-INSENSITIVE. A11 (medido 59/59, Task 1.4): el tool_response de Bash no trae
# exitCode; la unica senal de fracaso es el TEXTO de stdout/stderr del runner.
# - failure_type|permission_denied|command not found: las 3 originales (rechazo/ausencia
#   del tool). Se conservan para no romper los casos que ya viven.
# - AssertionError|AssertionFailedError: Node assert, pytest E-line, JUnit.
# - Traceback (most recent call last): Python crudo sin pytest.
# - SyntaxError|TypeError|ReferenceError|RangeError: crashes JS/Python (Node, Python repl).
# - error TS[0-9]: tsc en fracaso.
# - [1-9][0-9]*[[:space:]]+(failed|failing|failures?|errors?): pytest `=== 1 failed ===`,
#   vitest/jest `1 failed`, mocha `1 failing`, rspec `1 failure`/`2 failures`,
#   pytest `1 error`. La frontera del digito NO-cero evita `0 failed`, `0 errors`.
# - (failures?|errors?)[=:]([[:space:]]*)?[1-9]: phpunit `Failures: 1`,
#   unittest Python `failures=1`, `Errors: 5`. El digito NO-cero evita `Failures: 0`.
FAILURE_SIGNAL_RE_CI='failure_type|permission_denied|command not found|AssertionError|AssertionFailedError|Traceback \(most recent call last\)|SyntaxError|TypeError|ReferenceError|RangeError|error TS[0-9]|[1-9][0-9]*[[:space:]]+(failed|failing|failures?|errors?)|(failures?|errors?)[=:]([[:space:]]*)?[1-9]'

# Case-SENSITIVE: frases literales donde -i daria falso positivo en prosa (`0 failures!`,
# `failed to...`, `--- fail:`). Cubre los runners cuya senal de fracaso no trae numero
# inmediato. -E sin -i a proposito.
# - test result: FAILED. — cargo test.
# - FAIL[^a-zA-Z] — go test (`FAIL\tpkgname`). SIN ancla `^`: $combined es una
#   sola linea (json_string_field colapsa saltos), asi que `^FAIL` nunca matcheaba
#   (descubierto al correr el caso go: daba falso verde). El `FAIL` del JSON llega
#   precedido por la comilla de `"stderr":"FAIL\t..."`, que NO es letra, y matchea.
#   Limite declarado: `test_FAIL.py` en un comando que pasa seria falso positivo.
# - FAILURES! — banner de phpunit.
# - ---[[:space:]]+FAIL: — go test individual (`--- FAIL: TestX`).
FAILURE_SIGNAL_RE_CS='test result: FAILED|FAIL[^a-zA-Z]|FAILURES!|---[[:space:]]+FAIL:'
```

**Por qué dos greps y no uno:** `-i` es global en grep; meter las frases case-sensitive en
el mismo regex las case-insensitiveizaría y `0 failures!` / `failed to connect` /
`--- fail:` serían falsos positivos. Dos greps (`-Eiq` + `-Eq`) son la forma de mantener
las mayúsculas como señal donde hace falta. Medido.

**Postura:** sigue **fail-open** (no fail-closed). Razón: **tsc exitoso no imprime nada**;
fail-closed rompería DoD "un runner que pasa sigue acreditando". El arreglo achica el
hueco de 59/59 a los patrones no cubiertos (declarados abajo), no lo elimina. **Sin `\b`,
sin `[[:<:]]/[[:>:]]`** (H1+H2 cerrados).

## Cambios por archivo

### 1. `hooks/summonaikit-harness.sh`
- Definir `FAILURE_SIGNAL_RE_CI` y `FAILURE_SIGNAL_RE_CS` después de `TEST_RUNNER_WORD_RE`
  (`:84`), antes de `json_string_field` (`:86`).
- Cambiar el bloque `:887-891` por el doble-grep con `{ … || …; }`.
- Reescribir el comentario `:882-886`: ya no afirma "exit codes live in the tool result".

### 2. `tests/lib/gate_cases.sh`
- **Invertir** `caso_g2_runner_fallido_forma_real` (`:267-271`): esperar `verified=0`,
  reescribir el mensaje y la cabecera (`:257-266`). Mantener el nombre (DoD lo nombra).
- **5 casos nuevos** (cada uno aísla una rama del regex):
  - `caso_g2_runner_fallido_pytest_summary_no_marca` — `pytest -q` + `=== 1 failed in 0.5s ===` → `verified=0` (vía A `[1-9]...failed`).
  - `caso_g2_runner_fallido_tsc_no_marca` — `tsc --noEmit` + `error TS2322: ...` → `verified=0` (`error TS[0-9]`).
  - `caso_g2_runner_fallido_phpunit_no_marca` — `phpunit tests/` + `Failures: 1, Errors: 0.` (sin banner) → `verified=0` (vía B `(failures?|errors?)[=:]...[1-9]`).
  - `caso_g2_runner_fallido_cargo_no_marca` — `cargo test` + `test result: FAILED.` (sin `N failed`) → `verified=0` (CS `test result: FAILED`).
  - `caso_g2_runner_fallido_go_no_marca` — `go test ./...` + `FAIL\texample.com/pkg 0.12s` (al inicio de línea) → `verified=0` (CS `^FAIL[^a-zA-Z]`).
- **1 caso negativo** (guardia anti-falso-positivo, protege la frontera `[1-9]`):
  - `caso_g2_runner_pasa_0_failed_sigue_acreditado` — `pytest -q` + `5 passed, 0 failed in 0.5s ===` → `verified=1`. Una mutación que afloje `[1-9]` a `[0-9]` lo pone rojo.
- **No se tocan** `caso_g2_runner_marca_verificado`, `caso_g2_runner_no_encontrado_no_marca` (cubren DoD "runner pasa sigue acreditando" y "command not found sigue funcionando").
- `CASOS_G2` (`:231`): agrupar los 6 casos nuevos junto al invertido. **Total G2: 15 → 21.**
- Actualizar la cabecera del archivo (`:34-35`) para declarar la inversión (estilo `caso_g3_agent_type_cuenta`).

### 3. `tests/test_gate_mutations.sh`
- **Reescribir comentario** de `mut_sin_guardia_de_falla` (`:120-123`): ya no es verdad
  que `exitCode` sea "la única rama muerta"; la mutación sigue apuntando a `command not
  found` (vivo, DoD lo exige conservar), acreditada a `caso_g2_runner_no_encontrado_no_marca`.
- **6 mutaciones nuevas**, una por caso nuevo/invertido/negativo (corrige H3: cada una aislada a SU caso):
  - `mut_falla_assertion_quitada` — `sed 's/AssertionError|AssertionFailedError/ZZZ_NUNCA_Z/'` → atrapa `caso_g2_runner_fallido_forma_real` (al quitarlas, `AssertionError: ...` no matchea, `verified` vuelve a 1, el caso da rojo).
  - `mut_falla_failed_quitada` — `sed 's/\[1-9\]/[A-Z]/'` (sólo primera ocurrencia → vía A; vía B intacta) → atrapa `caso_g2_runner_fallido_pytest_summary_no_marca`.
  - `mut_falla_tsc_quitada` — `sed 's/error TS\[0-9\]/error TS_NUNCA/'` → atrapa `caso_g2_runner_fallido_tsc_no_marca`.
  - `mut_falla_phpunit_quitada` — `sed 's/(failures?|errors?)\[=:\]/(ZZ_NUNCA_ZZ)[Z]/'` → atrapa `caso_g2_runner_fallido_phpunit_no_marca`.
  - `mut_falla_cs_quitada` — `sed 's/"$FAILURE_SIGNAL_RE_CS"/"CS_NUNCA_ZZZ"/'` → atrapa `caso_g2_runner_fallido_cargo_no_marca`.
  - `mut_falla_frontera_aflojada` — `sed 's/\[1-9\]/[0-9]/g'` (global → afloja vía A y B) → atrapa `caso_g2_runner_pasa_0_failed_sigue_acreditado` (el negativo).
- Catálogo `MUTACIONES` (`:44-75`): 6 líneas G2 nuevas. **Total mutaciones: 30 → 36 (G2 6 → 12).**

> **Desviación del plan original (5 → 6 mutaciones):** durante la implementación se
> agregó `mut_falla_frontera_aflojada` para que el caso negativo
> `caso_g2_runner_pasa_0_failed_sigue_acreditado` tenga una mutación propia que lo
> atrape (regla del repo: cada caso no trivial tiene su mutación). Sin ella, una
> regresión que afloje `[1-9]` a `[0-9]` pasaría inadvertida.

### 4. `tests/lib/hook_lab.sh`
- **Sin cambio de código.** `lab_payload_bash` (`:228-233`) ya acepta `command`+`stderr`
  arbitrarios — los 6 casos nuevos se construyen con él.
- Ampliar el comentario `:228-230`: el hook ya NO es ciego al texto; grepea patrones reales
  de fracaso (dos regex CI/CS desde la Task 3.8).

### 5. `tests/fixtures/README.md`
- `:45` se mantiene ("no trae `exitCode` (59 de 59)" sigue siendo medición vigente).
- Agregar: "A11 cerrado en Task 3.8 — el hook grepea patrones de fracaso del runner en
  stdout/stderr (dos regex: CI case-insensitive + CS case-sensitive); `exitCode` era
  código muerto y se retiró."

### 6. `docs/spec/00-project-spec.md`
- `:80` — cerrar la fila A11 con `3 — **CERRADO** (Task 3.8)`.
- `:205-208` — agregar párrafo de cierre (estilo `:215-227` de 3.7): declarar retiro de
  `exitCode`, dos regex (CI/CS), cobertura medida por ecosistema, postura fail-open,
  **tsc silencioso en éxito sigue acreditando (límite declarado)**, gate sigue advisory.

### 7. `Plans.md`
- `:68` — status `cc:TODO` → `cc:完了 [<hash>]` + resumen (incluye: cross-review del plan
  con codex 1 ronda, 4 hallazgos aceptados, decisión Amplio).

## Verificación

1. `bash -n` sobre `hooks/summonaikit-harness.sh` y `tests/lib/*.sh`.
2. **Rojo** (sólo `gate_cases.sh` modificado, sin tocar el hook aún): correr
   `tests/test_gate_behavior.sh` suelto en sandbox (env de `tests/run.sh` +
   `SAIKIT_HOOK_VIVO="$PWD/hooks/summonaikit-harness.sh"`) → los 6 casos
   nuevos/invertidos dan rojo (el invertido porque hoy sigue dando `verified=1`; los 5
   nuevos porque el hook actual SÍ los acredita al no matchear las señales nuevas).
3. **Verde** (aplicado el arreglo al hook): mismo test → 6 verdes, 15 preexistentes intactos.
4. **Mutaciones** (`tests/test_gate_mutations.sh` suelto): "G2 12, 12 atrapadas", cada una
   acreditada a su caso (la corrida lo declara). Total hook: **36 mutaciones, 36 atrapadas**.
5. **Baseline**: `tools/golden-harness.sh --check` → 0 divergentes esperados (verificado:
   ningún escenario pone un runner que matchee `TEST_RUNNER_WORD_RE` con salida de fracaso;
   el 13 ya no matchea runner tras 3.3).
6. **Gate final**: `tests/run.sh` una sola vez → `OK`, 0 FAIL/LEAK/UNKNOWN.
7. **Candados**: `pre-commit run --all-files`.
8. **Install** (post-commit): `tools/install-hook.sh` lleva el arreglo al archivo vivo
   (`~/.claude/hooks/summonaikit-harness.sh`). Destino *nuestro pero distinto* ⇒ reparado
   con backup, vivo byte a byte igual a la fuente (`cmp`).
9. **Cross-review del CÓDIGO (opcional, regla nueva: sólo si la pide el operador):** al
   haber rendido la del plan 4 hallazgos reales, propongo 1 ronda con codex sobre el feat
   commit antes del cierre canónico en spec/Plans.

## Orden (TDD)

1. Preparar sandbox (env de `tests/run.sh`: `HOME`, `TMPDIR`, `USERPROFILE`,
   `SAIKIT_HOOK_VIVO` apuntando a la fuente).
2. **Rojo**: invertir `caso_g2_runner_fallido_forma_real` + agregar los 6 nuevos en
   `gate_cases.sh` y listarlos en `CASOS_G2`. Correr `test_gate_behavior.sh` → 6 rojos.
3. **Arreglo**: definir `FAILURE_SIGNAL_RE_CI`/`_CS`, cambiar el bloque `:887-891`,
   reescribir el comentario `:882-886` en `summonaikit-harness.sh`.
4. **Verde**: `test_gate_behavior.sh` → 6 verdes, 15 preexistentes intactos.
5. **Mutaciones**: 5 entradas nuevas en catálogo + 5 `mut_*` funcs + reescritura del
   comentario de `mut_sin_guardia_de_falla`. Correr `test_gate_mutations.sh` → G2 12/12.
6. **Baseline**: `golden-harness.sh --check` → 0 divergentes.
7. **Docs**: `tests/fixtures/README.md`, `tests/lib/hook_lab.sh` (comentario),
   `docs/spec/00-project-spec.md` (cerrar A11), `Plans.md` (cerrar 3.8).
8. **Gate final**: `tests/run.sh` una vez.
9. **Candados**: `pre-commit run --all-files`.
10. **Commit** (sin `--no-verify`).
11. (Opcional) **Cross-review del código** con codex.
12. **Install**: `tools/install-hook.sh`.
13. `git status --short` limpio.

## No entra en esta tarea (límites declarados)

- **Re-captura de payloads** (DoD no la pide; la 59/59 se borró al cerrar 3.7; medición
  vigente en spec + README + comentarios del lab).
- **Cobertura de ecosistemas NO listados en `TEST_RUNNER_RE`** (p. ej. `node test.js`
  crudo): el hook no los reconoce como runners, así que el guardia no aplica — no es un
  hueco del guardia, es que el gate no los exige.
- **Fail-closed puro**: rompería `tsc` exitoso silencioso (violando DoD "un runner que pasa
  sigue acreditando"). El arreglo achica el hueco; no lo elimina.
- **Escenario 17 en la baseline** (`17-defecto-a11-runner-fallido`): `lane:fast`; ningún
  runner fallido matchea `TEST_RUNNER_WORD_RE` en la baseline hoy, y la DoD no exige
  cobertura de baseline (consistente con 3.5/3.6 que tampoco agregaron escenarios).
- **Patrones residuales no medidos**: vitest `×`/`✗`, jest `✕`, mocha `✗` (iconos sin
  palabra) no se cubren — la cobertura actual es por TEXTO de reporte, no por iconos.
  Declarado, no silenciado.
- **Mutación sobre `exitCode`**: código muerto retirado, no mutado (mutar código muerto no
  prueba nada — lección de 0.5/1.5).
- **El gate sigue advisory** — A11 cierra un falso positivo de acreditación, no vuelve al
  gate un control de seguridad; quien controla el texto del turno puede influirlo.
- **`tools/capture-payloads.sh`**: sin cambios (no hay nueva captura).
