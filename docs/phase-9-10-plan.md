# Plan de implementación — Phase 9 (deuda del gate) + Phase 10 (velocidad de la ceremonia)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** cerrar la deuda confirmada de la auditoría 2026-08-13 (C6, C8–C14 + advisory del matcher) y quitar la lentitud de diseño de la ceremonia (carril rápido, re-review dirigido, batching, verificación no duplicada).

**Architecture:** Phase 9 son cambios mecánicos al gate hook con el patrón ya probado de la Phase 8: caso ROJO medido → fix mínimo → mutación dirigida → línea base auditada. Phase 10 es cambio de diseño: revive los clasificadores hoy muertos (`is_trivial_task`/`SUBSTANTIVE_RE`) como carril `fast` explícito, y mueve la disciplina de re-review/batching a los textos (contrato + role files), no al código del gate.

**Tech Stack:** bash (MSYS2/Git Bash), sed/awk POSIX, el banco `tests/lib/hook_lab.sh` + corpus `tests/lib/gate_cases.sh` + batería `tests/test_gate_mutations.sh` + línea base `tools/golden-harness.sh`.

## Global Constraints

- **TDD de hierro del repo**: cada fix con su caso que lo habría atrapado, ROJO medido ANTES del fix (driver suelto en sandbox, patrón AGENTS.md — no `tests/run.sh` por iteración).
- **`tests/run.sh` UNA vez por task, al final**, con `SAIKIT_HOOK_VIVO="$PWD/hooks/summonaikit-harness.sh"` (sin eso mide el hook instalado — lección 6.3).
- **Toda mutación nueva debe ser atrapada** por un caso propio; una mutación sin catch rompe la batería (guardia del driver).
- **Diff de línea base declarado por adelantado**: si un task mueve texto del contrato, se audita línea por línea que 0 veredictos (exit/decision) se muevan antes de regrabar.
- **JAMÁS `--no-verify`**; pre-commit pasa en cada commit.
- **El gate sigue advisory/fail-open**: ningún task agrega un motivo de bloqueo nuevo fuera de lo especificado; `not_observed != absent`.
- Cada task = un commit (o PR chico); deploy tras merge según AGENTS.md (install-hook + check + deploy-log).
- Números de línea del hook son orientativos (el archivo cambió en Phase 8): anclar por nombre de función/constante, no por línea.

---

## Phase 9 — Deuda del gate (mecánica, mismo patrón que Phase 8)

### Task 9.1: C6 — dotnet y gradle fallando ya no acreditan `verified`

**Files:**
- Modify: `hooks/summonaikit-harness.sh` (constantes `FAILURE_SIGNAL_RE_CI` y `FAILURE_SIGNAL_RE_CS`)
- Test: `tests/lib/gate_cases.sh` (índice `CASOS_G2` + 2 casos), `tests/test_gate_mutations.sh` (2 mutaciones)

**Interfaces:**
- Consumes: `lab_payload_bash COMANDO STDERR` (builder existente; el 2º arg es el stderr del runner).
- Produces: nada para otros tasks.

- [ ] **Step 1: casos ROJOS** — agregar a `gate_cases.sh` (y a `CASOS_G2`):

```sh
# C6 (auditoria 2026-08-13, Task 9.1) — dotnet VSTest fallando: su banner
# 'Failed!  - Failed:     1, ...' no trae digito ANTES de la palabra (via A)
# ni 'failures:' (via B). Sin senal, el runner fallido acreditaba verified=1.
caso_g2_runner_fallido_dotnet_no_marca() {
  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_bash 'dotnet test' 'Failed!  - Failed:     1, Passed:     3, Skipped:     0, Total:     4')"
  _igual "verified con dotnet fallido" "$(lab_estado verified)" "0"
}

# C6 — gradle fallando: 'FAILURE: Build failed with an exception.' y
# 'BUILD FAILED in 2s' tampoco matcheaban ninguna via.
caso_g2_runner_fallido_gradle_no_marca() {
  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_bash 'gradle test' 'FAILURE: Build failed with an exception. BUILD FAILED in 2s')"
  _igual "verified con gradle fallido" "$(lab_estado verified)" "0"
}
```

- [ ] **Step 2: correr ROJO** con el driver suelto (`driver` = copia del patrón scratchpad de la Phase 8: sourcea el lab + corpus, `HOOK_BAJO_PRUEBA` = fuente). Esperado: ambos FAIL con `esperaba [0], dio [1]`.
- [ ] **Step 3: fix mínimo** en el hook — extender las dos constantes:
  - `FAILURE_SIGNAL_RE_CI`: cambiar la vía B `(failures?|errors?)[=:]([[:space:]]*)?[1-9]` → `(failures?|errors?|failed)[=:]([[:space:]]*)?[1-9]` (atrapa `Failed:     1`; el `[1-9]` sigue protegiendo `Failed:     0`).
  - `FAILURE_SIGNAL_RE_CS`: agregar dos literales: `|FAILURE: Build failed|BUILD FAILED` (case-sensitive: no chocan con prosa `build failed` en minúsculas).
- [ ] **Step 4: correr VERDE** los 2 casos nuevos + controles negativos existentes (`caso_g2_runner_pasa_0_failed_sigue_acreditado`, `caso_g2_runner_marca_verificado`). Un runner dotnet EXITOSO (`Passed!  - Failed:     0`) debe seguir acreditando: agregar ese control si el corpus no lo tiene:

```sh
caso_g2_runner_dotnet_pasa_sigue_acreditado() {
  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_bash 'dotnet test' 'Passed!  - Failed:     0, Passed:     4, Skipped:     0, Total:     4')"
  _igual "verified con dotnet exitoso" "$(lab_estado verified)" "1"
}
```

- [ ] **Step 5: mutaciones** — catálogo + funciones en `test_gate_mutations.sh`:

```
G2|falla_dotnet_quitada|la palabra failed sale de la via B y dotnet fallido vuelve a acreditarse
G2|falla_gradle_quitada|los literales de gradle salen del CS y gradle fallido vuelve a acreditarse
```

```sh
mut_falla_dotnet_quitada() { sed 's/failures?|errors?|failed/failures?|errors?/'; }
mut_falla_gradle_quitada() { sed 's/|FAILURE: Build failed|BUILD FAILED//'; }
```

- [ ] **Step 6: batería acotada** (`SAIKIT_MUTACIONES` con las 2 líneas) → ambas atrapadas. **Step 7: suite completa + commit** `fix(9.1): dotnet y gradle fallidos ya no acreditan verificacion`.

---

### Task 9.2: C8 — el runner debe estar en POSICIÓN de comando, no de mención

**Files:**
- Modify: `hooks/summonaikit-harness.sh` (nueva constante `TEST_RUNNER_CMD_RE` + el chequeo en `record_tool_evidence`)
- Test: `tests/lib/gate_cases.sh` (+4 casos), `tests/test_gate_mutations.sh` (+1 mutación)

**Interfaces:**
- Produces: `TEST_RUNNER_CMD_RE` — wrapper de posición sobre `TEST_RUNNER_RE`. La superficie de PROSA del Stop gate **no cambia** (sigue `TEST_RUNNER_WORD_RE`): el recibo declara, el evento acredita.

- [ ] **Step 1: casos ROJOS** (2 fakes que hoy acreditan) + 2 controles verdes desde el día 1:

```sh
# C8 (Task 9.2) — mencionar un runner en un echo NO es correrlo.
caso_g2_runner_en_echo_no_marca() {
  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_bash 'echo listo, luego corremos pytest')"
  _igual "verified con runner en echo" "$(lab_estado verified)" "0"
}

# C8 — un directorio que se llama como el runner tampoco.
caso_g2_runner_como_argumento_no_marca() {
  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_bash 'ls tsc/')"
  _igual "verified con runner de argumento" "$(lab_estado verified)" "0"
}

# Controles: las formas legitimas de posicion siguen acreditando.
caso_g2_runner_tras_and_marca() {
  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_bash 'cd app && pytest -q')"
  _igual "verified con runner tras &&" "$(lab_estado verified)" "1"
}
caso_g2_runner_con_env_prefijo_marca() {
  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_bash 'CI=1 pytest -q')"
  _igual "verified con VAR=val antes del runner" "$(lab_estado verified)" "1"
}
```

- [ ] **Step 2: ROJO medido** (los 2 fakes fallan; los 2 controles ya pasan — se declaran como controles, no como catch).
- [ ] **Step 3: fix** — nueva constante junto a `TEST_RUNNER_WORD_RE` (forma ajustada por cross-review codex r1, hallazgos 1 y 2):

```sh
# Task 9.2 (C8): para ACREDITAR un evento, el runner debe estar en posicion de
# comando: inicio, o tras un separador de shell (; & | ( ` " '), o tras un
# salto/tab ESCAPADO (\n / \t literales de dos chars: $command_text viene del
# escaner SIN decodificar — un comando multilinea real trae \n crudo, medido
# en r1 hallazgo 1), opcionalmente precedido por prefijos de entorno (VAR=val,
# time, env, nice, xargs) o una ruta. La PROSA del recibo sigue con
# TEST_RUNNER_WORD_RE (declarar != correr).
TEST_RUNNER_CMD_RE='(^|[;&|(`"'"'"']|\\n|\\t)[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*((time|env|nice|xargs)[[:space:]]+)*([A-Za-z0-9_./-]*/)?('"$TEST_RUNNER_RE"')([^A-Za-z0-9_.-]|\.([^A-Za-z0-9_.-]|$)|$)'

# r1 hallazgo 2: la comilla como separador dejaba pasar `echo "pytest"`.
# Guardia del lado ESTRICTO (filosofia del repo: sin credito el gate pide la
# razon, que es recuperable; acreditar de mas no lo es): un comando cuyo
# PRIMER token es echo/printf no acredita jamas. Limite declarado: el legitimo
# `echo empiezo && pytest` tampoco acredita — cae al lado estricto a proposito.
ECHO_LEAD_RE='^[[:space:]]*(echo|printf)([[:space:]]|$)'
```

  y en `record_tool_evidence`, el chequeo de crédito cambia a: `TEST_RUNNER_CMD_RE` sobre `$command_text` **Y NO** `ECHO_LEAD_RE` sobre `$command_text` (el `tool_name` deja de concatenarse: un `tool_name` que matchee runner no es un comando; `caso_g2_eco_de_tool_name_en_tool_response_no_marca` ya cubre el eco).
  Casos adicionales por r1: `caso_g2_runner_multilinea_marca` (command `cd app\npytest -q` con `\n` literal → acredita) y `caso_g2_echo_entrecomillado_no_marca` (`echo "pytest"` → no acredita), más el control negativo declarado `caso_g2_echo_con_and_no_acredita_declarado` (`echo empiezo && pytest` → verified=0, límite del lado estricto ATADO por test para que el día que se afloje sea decisión, no accidente).
- [ ] **Step 4: VERDE** los 4 nuevos + TODO `CASOS_G2` (regresión: `caso_g2_runner_con_ruta_marca`, `caso_g2_comando_entrecomillado_marca_verificado` — la comilla es separador en el RE nuevo — y `caso_g2_runner_en_path_no_marca`).
- [ ] **Step 5: mutación**:

```
G2|credito_por_mencion|el credito vuelve a TEST_RUNNER_WORD_RE y un echo con pytest acredita
```

```sh
mut_credito_por_mencion() { sed 's/"\$TEST_RUNNER_CMD_RE"/"$TEST_RUNNER_WORD_RE"/'; }
```

- [ ] **Step 6: batería acotada → suite completa → commit** `fix(9.2): el credito de verificacion exige posicion de comando`.

**Riesgo declarado:** este RE es el más delicado del plan — si un legítimo deja de acreditar, el gate sobre-exige (recuperable con la excusa declarada, pero molesto). Por eso los controles verdes van desde el Step 1 y la corrida final incluye la línea base entera.

---

### Task 9.3: C11 — citar el feedback del gate ya no satisface etiquetas

**Files:**
- Modify: `hooks/summonaikit-harness.sh` (`has_receipt_label` + textos de `build_gate_feedback`)
- Test: `tests/lib/gate_cases.sh` (+1 caso), `tests/test_gate_mutations.sh` (+1 mutación)

- [ ] **Step 1: caso ROJO** — el turno que responde al gate citando su feedback textual NO cierra:

```sh
# C11 (Task 9.3) — el feedback del gate contiene "add a line beginning
# 'Understand:'..." y el marcador del recibo; un mensaje que lo CITA
# satisfacia las 6 etiquetas sin recibo real (la comilla ' pasaba la
# frontera [^[:alpha:]]).
_TEXTO_CITA_FEEDBACK='El gate me pidio: agregar una linea que empiece con '"'"'Understand:'"'"' dentro del bloque SUMMONAIKIT HARNESS RECEIPT, y lo mismo para '"'"'Implement:'"'"', '"'"'Verify:'"'"', '"'"'Review:'"'"', '"'"'Close:'"'"' y '"'"'Retro:'"'"'. Lo hago en el siguiente turno.'

caso_g4_cita_del_feedback_no_satisface() {
  _sembrar_turno_completo
  lab_run stop claude "$(lab_payload_stop "$_TEXTO_CITA_FEEDBACK")"
  _igual "exit citando el feedback" "$LAB_RC" "2"
}
```

- [ ] **Step 2: ROJO medido.**
- [ ] **Step 3: fix en dos mitades** (las dos, no una):
  1. `has_receipt_label`: la frontera izquierda excluye la comilla simple y la doble — `(^|[^[:alpha:]'\"])` (en el grep del hook: `(^|[^[:alpha:]'\''"])` con el quoting de shell que corresponda). Límite declarado al lado: una etiqueta legítima precedida por apóstrofo deja de contar (recuperable; A8 cubría prosa, no comillas).
  2. `build_gate_feedback`: reescribir las 6 líneas de ayuda para que NO contengan la forma `Label:` matchable — p. ej. `add a line that begins with the Understand label, then a colon` (sin comillas alrededor de `Understand:`). El bloque "Required receipt shape" del feedback conserva el template literal (es multilínea con `Understand: ...`), así que la mitad 1 sola no alcanza NI la 2 sola: la 1 mata la cita entre comillas, la 2 evita regalar la forma exacta en prosa; el template queda — límite declarado: citar el template completo con sus saltos seguiría contando (es indistinguible de un recibo real por diseño del gate advisory).
- [ ] **Step 4: VERDE** + regresión completa de G4 (bold, viñetas, corrido, pegada).
- [ ] **Step 5: mutación** `G4|frontera_acepta_comillas` (revierte la mitad 1):

```sh
mut_frontera_acepta_comillas() { sed "s/\\[^\\[:alpha:\\]'\\\"\\]/[^[:alpha:]]/"; }
```

  (ajustar el escape exacto al literal que quede en el hook; la guardia `cmp` de la batería valida que mutó).
- [ ] **Step 6: batería acotada → suite → commit** `fix(9.3): citar el feedback del gate ya no satisface etiquetas`. **Línea base:** el texto del feedback cambia → declarar por adelantado que divergen los escenarios con gate fallido (07, 11, 19, 20, 22 y hermanos) y auditar 0 veredictos movidos antes de regrabar.

---

### Task 9.4: C9 — sin campo `prompt` no se arma (salvo `session` de cursor)

**Files:**
- Modify: `hooks/summonaikit-harness.sh` (`start_harness`, el fallback `prompt_text="$INPUT"`)
- Test: `tests/lib/gate_cases.sh` (+2 casos), `tests/lib/hook_lab.sh` (+1 builder), `tests/test_gate_mutations.sh` (+1 mutación)

- [ ] **Step 1: builder + casos ROJOS**:

```sh
# hook_lab.sh — un UserPromptSubmit SIN campo prompt cuyo resto del payload
# menciona -saikit (p.ej. un summary de resume). No debe armar: el usuario
# no escribio el sentinel en ESTE turno.
lab_payload_prompt_sin_campo() {
  printf '{"session_id":"__SESSION_ID__","transcript_path":"__TRANSCRIPT__","cwd":"/proyecto","prompt_id":"c1a70000-1111-4222-8333-777788889999","permission_mode":"auto","hook_event_name":"UserPromptSubmit","resumen_previo":"el turno anterior uso -saikit para el endpoint"}'
}
```

```sh
# gate_cases.sh
# C9 (Task 9.4) — el fallback prompt_text=$INPUT armaba con -saikit en
# CUALQUIER campo del payload cuando prompt faltaba.
caso_g1_prompt_ausente_no_arma_por_otro_campo() {
  lab_run prompt claude "$(lab_payload_prompt_sin_campo)"
  _vacio "stdout sin campo prompt" "$LAB_OUT"
  if lab_hay_estado; then _mal "sin campo prompt no se arma aunque el payload mencione -saikit (C9)"; fi
}
```

- [ ] **Step 2: ROJO medido.**
- [ ] **Step 3: fix** — el fallback se acota a la fase `session`:

```sh
  prompt_text="$(json_top_level_decoded prompt)"
  # Task 9.4 (C9): el fallback al payload entero queda SOLO para la fase
  # session (cursor arma ahi con -saikit en el texto de sesion,
  # caso_g6_armado_por_target). En PHASE=prompt, un payload sin campo prompt
  # no trae nada que el usuario haya escrito ESTE turno: no se arma.
  if [ -z "$prompt_text" ] && [ "$PHASE" = "session" ]; then prompt_text="$INPUT"; fi
```

- [ ] **Step 4: VERDE** + regresión `caso_g6_armado_por_target` (cursor session sigue armando) y `CASOS_G1` completo.
- [ ] **Step 5: mutación** `G1|fallback_sin_acotar` (`sed 's/\[ -z "\$prompt_text" \] && \[ "\$PHASE" = "session" \]/[ -z "$prompt_text" ]/'`) → la atrapa el caso nuevo. **Step 6: suite → commit** `fix(9.4): sin campo prompt no se arma fuera de la fase session`.

---

### Task 9.5: C10 — `docs/-saikit.md` y `--saikit` ya no arman

**Files:**
- Modify: `hooks/summonaikit-harness.sh` (`SAIKIT_SENTINEL_RE`)
- Test: `tests/lib/gate_cases.sh` (extender `caso_g1_sentinel_con_frontera` + 1 caso nuevo), `tests/test_gate_mutations.sh` (+1 mutación)

- [ ] **Step 1: caso ROJO**:

```sh
# C10 (Task 9.5) — la frontera izquierda aceptaba '/' y '-': REFERENCIAR un
# archivo o flag que contiene el token armaba la ceremonia entera.
caso_g1_referencia_a_ruta_o_flag_no_arma() {
  lab_run prompt claude "$(lab_payload_prompt 'lee docs/-saikit.md y resume que dice')"
  if lab_hay_estado; then _mal "docs/-saikit.md no debe armar (C10)"; fi
  lab_limpiar_estado
  lab_run prompt claude "$(lab_payload_prompt 'que hace el flag --saikit del README?')"
  if lab_hay_estado; then _mal "--saikit no debe armar (C10)"; fi
}
```

- [ ] **Step 2: ROJO medido.**
- [ ] **Step 3: fix** — `SAIKIT_SENTINEL_RE='(^|[^A-Za-z0-9_/-])-saikit([^A-Za-z0-9_-]|$)'` (la clase izquierda excluye `/` y `-`). Controles que deben seguir armando: inicio de línea, tras espacio, tras `\n` decodificado, tras `(`/`,`/comillas.
- [ ] **Step 4: VERDE** + `caso_g1_arma_con_sentinel` / `caso_g1_arma_con_sentinel_en_linea_nueva` / `caso_g1_sentinel_con_frontera` en verde.
- [ ] **Step 5: mutación** `G1|frontera_izquierda_floja` (`sed 's/\[^A-Za-z0-9_\/-\]/[^A-Za-z0-9_]/'` — revierte la clase) → la atrapa el caso nuevo. **Step 6: suite → commit** `fix(9.5): la frontera izquierda del sentinel excluye / y -`.

---

### Task 9.6: C12 — el walker del transcript deja de filtrar valores top-level

**Files:**
- Modify: `hooks/summonaikit-harness.sh` (`assistant_text_transcript`, los resets de estado en el cierre de llaves)
- Test: `tests/lib/hook_lab.sh` (+1 fixture), `tests/lib/gate_cases.sh` (+1 caso), `tests/test_gate_mutations.sh` (+1 mutación)

- [ ] **Step 1: fixture + caso ROJO** — una línea de transcript cuyo valor top-level POSTERIOR a `message` contiene una etiqueta:

```sh
# hook_lab.sh — tras el cierre de message, un campo top-level (p.ej. un
# requestId artificial) cuyo VALOR trae texto de etiqueta. El walker sano no
# debe emitirlo; el que no resetea en_text/en_assistant lo concatena a $text.
lab_transcript_fuga_top_level() {
  printf '{"parentUuid":"a1","type":"assistant","message":{"id":"m1","role":"assistant","model":"claude-opus-5","content":[{"type":"text","text":"trabajando en ello"}]},"uuid":"a2","requestId":"Retro: none y Close: entregado","timestamp":"2026-08-09T12:00:00.000Z"}'
}
```

```sh
# gate_cases.sh — con recibo al que le FALTAN Close y Retro en el payload, y
# la fuga en el transcript aportando justo esas dos: el gate sano bloquea.
caso_g4_fuga_top_level_no_aporta_etiquetas() {
  _sembrar_turno_completo
  lab_run stop claude "$(lab_payload_stop 'SUMMONAIKIT HARNESS RECEIPT\n- Understand: a.\n- Implement: b.\n- Verify: skipped, sin bateria.\n- Review: sin hallazgos.')" "$(lab_transcript_fuga_top_level)"
  _igual "exit con fuga top-level" "$LAB_RC" "2"
}
```

- [ ] **Step 2: ROJO medido** (hoy la fuga aporta `Retro:`/`Close:` y el gate cierra o exige menos).
- [ ] **Step 3: fix** en el awk de `assistant_text_transcript`, en la rama de cierre `}`/`]`:

```awk
        if (c == "}" || c == "]") {
          if (depth == 4 && emiti) { printf "\n"; emiti = 0 }
          depth--
          if (depth < 4) en_text = 0
          if (depth < 2) { en_assistant = 0; c2 = ""; c4 = "" }
          espera = 0; continue
        }
```

- [ ] **Step 4: VERDE** + regresión de los casos del walker (`caso_g4_recibo_solo_en_transcript_pasa`, `caso_g4_recibo_dos_bloques_pasa`, `caso_g4_pausa_en_resultado_bloquea`, `caso_g4_pausa_en_thinking_no_cuenta`).
- [ ] **Step 5: mutación** `G4|walker_sin_resets` (`sed 's/if (depth < 4) en_text = 0/if (0) en_text = 0/'`). **Step 6: suite → commit** `fix(9.6): el walker resetea estado al cerrar message (fuga top-level)`.

---

### Task 9.7: C13 — `state/` deja de acumular sesiones para siempre

**Files:**
- Modify: `hooks/summonaikit-harness.sh` (los 3 puntos de limpieza + barrido TTL en `start_harness`)
- Test: `tests/lib/gate_cases.sh` (+2 casos), `tests/test_gate_mutations.sh` (+1 mutación)

**Diseño (declarado antes de codear):** dos mitades. (a) Toda limpieza que hoy hace `rm -f` de los archivos remata con `rmdir` best-effort del dir de sesión (vacío ⇒ se va; con archivos ajenos ⇒ `rmdir` falla en silencio y no pasa nada — jamás `rm -rf` aquí). (b) Barrido TTL al ARMAR (una vez por turno armado, no por evento): sesiones hermanas del MISMO proyecto+host con `harness-state.env` más viejo de 14 días se borran (`rm -rf` acotado al dir de sesión bajo `$PROJECT_DIR`); una sesión armada 14 días sin tocar su estado está muerta — A4 protege sesiones VIVAS, no cadáveres. Fail-open: sin `find` o con error, no se barre.

- [ ] **Step 1: casos ROJOS**:

```sh
# C13 (Task 9.7, mitad a) — el cierre limpio debe llevarse tambien el
# directorio de la sesion, no solo sus archivos.
caso_g5_cierre_limpio_borra_directorio() {
  _sembrar_turno_completo
  lab_run stop claude "$(lab_payload_stop "$_RECIBO_VINETAS")"
  _igual "exit del cierre" "$LAB_RC" "0"
  if [ -d "$(dirname "$LAB_ESTADO_PATH")" ]; then _mal "el dir de sesion debe irse en el cierre limpio (C13)"; fi
}

# C13 (mitad b) — un estado hermano con mtime de hace 15 dias se barre al
# armar; uno FRESCO del mismo proyecto+host sobrevive. Las DOS mitades en el
# MISMO caso (cross-review codex r1, hallazgo 3): sin la hermana fresca
# sembrada, una implementacion que hiciera rm -rf de TODAS las hermanas
# pasaria la bateria — el caso debe discriminar muerta de viva.
caso_g1_armado_barre_solo_sesiones_muertas() {
  proyecto_dir="$(dirname "$(dirname "$LAB_ESTADO_PATH")")"
  viejo_dir="$proyecto_dir/sesion-muerta-xyz"
  fresco_dir="$proyecto_dir/sesion-viva-abc"
  mkdir -p "$viejo_dir" "$fresco_dir"
  printf 'task_hash=1\ncycle=0\n' > "$viejo_dir/harness-state.env"
  printf 'task_hash=2\ncycle=0\n' > "$fresco_dir/harness-state.env"
  touch -d '15 days ago' "$viejo_dir/harness-state.env" 2>/dev/null \
    || touch -t "$(date -d '15 days ago' +%Y%m%d%H%M 2>/dev/null)" "$viejo_dir/harness-state.env"
  lab_run prompt claude "$(lab_payload_prompt '-saikit turno que barre')"
  if [ -d "$viejo_dir" ]; then _mal "la sesion muerta (15d) debe barrerse al armar (C13)"; fi
  [ -f "$fresco_dir/harness-state.env" ] \
    || _mal "la sesion hermana FRESCA debe sobrevivir al barrido (C13 / A4)"
  if ! lab_hay_estado; then _mal "el barrido no debe tocar el estado del turno que arma"; fi
}
```

- [ ] **Step 2: ROJO medido.** (Si `touch -d` no funciona en MSYS2 de esta máquina, medirlo y cambiar el caso a `-mmin` con TTL parametrizable por env `SAIKIT_STATE_TTL_MIN` solo-para-tests — decisión al implementar, documentada en el caso.)
- [ ] **Step 3: fix** — (a) tras cada `rm -f "$STATE_PATH" ...` de desarme/cierre/presupuesto: `rmdir "$STATE_DIR" 2>/dev/null || true`; (b) en `start_harness`, tras armar:

```sh
  # Task 9.7 (C13): barrido TTL de sesiones muertas del MISMO proyecto+host.
  # 14 dias sin tocar harness-state.env = cadaver; A4 protege sesiones vivas.
  find "$PROJECT_DIR" -mindepth 2 -maxdepth 2 -name harness-state.env -mtime +14 2>/dev/null \
    | while IFS= read -r _muerto; do
        case "$_muerto" in "$STATE_DIR"/*) continue ;; esac
        rm -rf "$(dirname "$_muerto")" 2>/dev/null || true
      done
```

- [ ] **Step 4: VERDE** + regresión A4 (`caso_g1_dos_sesiones_no_comparten_estado` — la sesión B fresca sobrevive al armado de A).
- [ ] **Step 5: mutación** `G5|estado_inmortal` (neutraliza el `rmdir` del cierre limpio: `sed 's/rmdir "\$STATE_DIR"/true "$STATE_DIR"/'`) → la atrapa `caso_g5_cierre_limpio_borra_directorio`. **Step 6: suite → commit** `fix(9.7): limpieza de directorios de sesion + barrido TTL de 14 dias`.

---

### Task 9.8: C14 — solo un Stop LIMPIO borra el aviso RN pendiente ajeno

**Files:**
- Modify: `hooks/summonaikit-harness.sh` (el `elif` del bloque REVIEW-NOTICE en `stop_gate`)
- Test: `tests/lib/gate_cases.sh` (+1 caso), `tests/test_gate_mutations.sh` (+1 mutación)

- [ ] **Step 1: caso ROJO** — un Stop que BLOQUEA no debe llevarse el aviso de otra sesión:

```sh
# C14 (Task 9.8) — el borde declarado dice "el Stop de una sesion con
# secuencia limpia puede borrar el aviso"; un Stop que BLOQUEA no es eso.
caso_g5_stop_fallido_no_borra_aviso_ajeno() {
  lab_sembrar 123456 0 0 0 ""   # armado e incompleto: este Stop bloquea
  rn_ajeno="$(dirname "$(dirname "$LAB_ESTADO_PATH")")/review-notice-pending.log"
  printf 'SAIKIT REVIEW NOTICE: aviso de la sesion hermana.\n' > "$rn_ajeno"
  lab_run stop claude "$(lab_payload_stop 'sin recibo')"
  _igual "el Stop bloquea" "$LAB_RC" "2"
  [ -f "$rn_ajeno" ] || _mal "un Stop FALLIDO no debe borrar el aviso pendiente ajeno (C14)"
}
```

- [ ] **Step 2: ROJO medido** (hoy el `elif` corre en todo Stop y lo borra).
- [ ] **Step 3: fix** — mover el borrado del `elif` al camino limpio: el bloque `elif [ -n ... ] || [ -n ... ]; then rm -f "$RN_PENDING_PATH"` se reemplaza por dejar `rn_pendiente_borrable=1` y ejecutar el `rm` SOLO dentro del `if [ -z "$missing" ]` (junto al `rm -f "$RN_ORDER_PATH"` que ya vive ahí). El disparo del aviso (la mitad `-gt`) no se toca.
- [ ] **Step 4: VERDE** + regresión del caso RN existente (`caso_g1_dos_hosts_mismo_repo_no_comparten_estado`, mitad 3) y del flujo aviso→entrega.
- [ ] **Step 5: mutación** `G5|aviso_se_borra_en_fallo` (revierte la condición al Stop incondicional). **Step 6: suite → commit** `fix(9.8): el aviso RN pendiente solo lo borra un cierre limpio`.

---

### Task 9.9: advisory del matcher — `Agent` entra al matcher de PostToolUse

**Corregida por cross-review codex r1 (hallazgo 5, verificado):** `tools/check-hook-registration.sh` YA prueba el matcher contra `Agent` (regex del host contra el literal, línea ~163) y `tests/test_hook_registration.sh` ya cubre presente/ausente — **no hay cambio versionable de código**. La task queda como acción de operador + verificación viva:

**Files:**
- Modify: `~/.claude/settings.json` del operador (matcher `Bash|Edit|Write|apply_patch|Task` → `...|Task|Agent`) — el repo no genera ese archivo (declarado, A10)

- [ ] **Step 1:** editar el matcher en `~/.claude/settings.json` y correr `bash tools/check-hook-registration.sh` → el advisory desaparece, exit 0.
- [ ] **Step 2:** turno `-saikit` vivo: verificar en `harness-evidence.log` que el despacho `Agent` registra el rol (hoy solo entran los eventos internos del subagente).
- [ ] **Step 3:** anotar el cambio en `docs/deploy-log.md` (acción de operador, sin commit de código).

---

## Phase 10 — Velocidad de la ceremonia (diseño; medida antes y después)

**Línea base ya medida (2026-08-13, transcript 1ed06dd2):** una task = implementer 2h19m + verifier 58m + reviewer 32m (+2ª ronda) ≈ 4 h; 436 llamadas Bash en un implementer (~55 min solo de latencia de turnos); 1–2.4 h de agente ocioso; suite de ~18 min re-corrida por fase. La DoD de la fase entera es re-medir UNA task real comparable y que el total baje a ≤ 1 h sin perder ningún gate.

### Task 10.1: carril `fast` explícito — `-saikit:fast`

**Files:**
- Modify: `hooks/summonaikit-harness.sh` (`SAIKIT_SENTINEL_RE` gana variante, `start_harness` escribe `lane` al estado, `write_state`/`read_state_value` ganan el campo, `stop_gate` exige menos con `lane=fast`)
- Test: `tests/lib/gate_cases.sh` (+4 casos), `tests/test_gate_mutations.sh` (+2 mutaciones), línea base (+1 escenario)

**Diseño (decisión ya tomada, coherente con el sentinel: "si lo escribiste, lo quieres"):** el carril NO se infiere de regex de trivialidad (los clasificadores `is_trivial_task`/`SUBSTANTIVE_RE` quedan muertos y se RETIRAN en esta task — código muerto fuera). El usuario lo pide explícito: `-saikit:fast`. Con `lane=fast` el Stop gate exige **recibo completo + evidencia de verificación (o skip declarado)** pero **NO la ceremonia de 3 subagentes** (el lead puede implementar directo). `-saikit` pelado = ceremonia completa, sin cambios. El desarme al turno siguiente sin sentinel aplica igual a los dos carriles.

**Interfaces:**
- Produces: campo `lane=` en `harness-state.env` (`full` | `fast`); regex `SAIKIT_SENTINEL_RE` extendido a `-saikit(:fast)?`.

- [ ] **Step 1: casos ROJOS**:

```sh
# 10.1 — -saikit:fast arma con lane=fast; -saikit pelado sigue lane=full.
caso_g1_fast_arma_con_lane() {
  lab_run prompt claude "$(lab_payload_prompt '-saikit:fast corrige el typo del header')"
  _igual "lane" "$(lab_estado lane)" "fast"
}
caso_g1_pelado_arma_lane_full() {
  lab_run prompt claude "$(lab_payload_prompt '-saikit agrega el endpoint')"
  _igual "lane" "$(lab_estado lane)" "full"
}
# 10.1 — con lane=fast, un turno con recibo completo y verify cierra SIN
# subagentes; con lane=full el mismo turno sigue bloqueando por la ceremonia.
caso_g3_fast_cierra_sin_subagentes() {
  lab_run prompt claude "$(lab_payload_prompt '-saikit:fast corrige el typo')"
  lab_run tool claude "$(lab_payload_edit '/proyecto/src/header.ts')"
  lab_run tool claude "$(lab_payload_bash 'pytest -q')"
  lab_run stop claude "$(lab_payload_stop "$_RECIBO_VINETAS")"
  _igual "fast cierra sin ceremonia" "$LAB_RC" "0"
}
caso_g3_fast_sin_recibo_sigue_bloqueando() {
  lab_run prompt claude "$(lab_payload_prompt '-saikit:fast corrige el typo')"
  lab_run tool claude "$(lab_payload_edit '/proyecto/src/header.ts')"
  lab_run stop claude "$(lab_payload_stop 'listo, creo')"
  _igual "fast sin recibo bloquea" "$LAB_RC" "2"
}
```

- [ ] **Step 2: ROJO medido.** OJO (cross-review codex r1, hallazgo 4, verificado con grep): `-saikit:fast` **YA ARMA hoy** — el `:` satisface la frontera derecha del RE actual, así que arma como full. El rojo del caso fast es por el campo `lane` ausente del estado (`lab_estado lane` da vacío ≠ `fast`), NO por no armar. El RE del sentinel NO necesita la alternativa `(:fast)?` — se queda como está (9.5 incluida); lo nuevo es solo la DETECCIÓN del carril.
- [ ] **Step 3: fix** — (a) el sentinel no cambia; (b) `start_harness` detecta `lane` con grep EXACTO del sufijo:

```sh
  # r1 hallazgo 4: el match del sufijo es EXACTO (:fast con frontera derecha);
  # cualquier otro sufijo (-saikit:fasst, -saikit:rapido) arma FULL — limite
  # declarado: un typo del carril cae al lado seguro (ceremonia completa),
  # nunca a un fast silencioso. Se ATA con caso propio.
  lane="full"
  if printf '%s' "$prompt_text" | grep -Eq '(^|[^A-Za-z0-9_/-])-saikit:fast([^A-Za-z0-9_-]|$)'; then lane="fast"; fi
```

  Caso adicional por r1: `caso_g1_sufijo_desconocido_arma_full` (`-saikit:fasst` → arma con `lane=full`, no fast, no silencio).

  (c) `write_state` persiste `lane=%s` (parámetro 6; TODOS los call sites se actualizan — el patrón de `agents_seen` marca el camino); (d) en `stop_gate`, el bloque de secuencia de subagentes queda envuelto en `if [ "$(read_state_value lane)" != "fast" ]`; (e) el contrato inyectado gana 3 líneas que explican el carril (y la línea base divergirá SOLO por ese texto — declarar por adelantado).
- [ ] **Step 4: VERDE** los 4 + `CASOS_G3` completo (la ceremonia full intacta).
- [ ] **Step 5: mutaciones**:

```
G1|fast_no_se_detecta|el lane fast deja de detectarse y todo arma full
G3|fast_no_exime_ceremonia|lane=fast deja de eximir la secuencia (el carril no sirve)
```

  La segunda se atrapa con `caso_g3_fast_cierra_sin_subagentes`; la primera con `caso_g1_fast_arma_con_lane`.
- [ ] **Step 6:** retirar `is_engineering_task` / `is_trivial_task` / `TRIVIAL_RE` / `SUBSTANTIVE_RE` (código muerto desde el parche sentinel; `grep -n` para confirmar cero call sites antes de borrar). **Step 7:** escenario nuevo en la línea base (armado fast + cierre sin ceremonia) + regrabar con diff auditado. **Step 8: suite → commit** `feat(10.1): carril -saikit:fast (recibo+verify sin ceremonia de subagentes)`.

---

### Task 10.2: re-review dirigido tras hallazgos (contrato + aviso RN)

**Files:**
- Modify: `hooks/summonaikit-harness.sh` (texto del contrato en `harness_context` + texto del aviso RN)
- Test: línea base (diff de texto declarado); sin caso nuevo de gate (no cambia ninguna condición)

**Diseño:** la 2ª ronda completa (implement→verify→review de nuevo) es comportamiento del LEAD inducido por el texto, no una exigencia del gate (el gate solo pide que los 3 rols hayan corrido UNA vez, en orden). Se corrige el texto, no el código de decisión:

- [ ] **Step 1:** en `harness_context`, tras la "Delegation rule", agregar:

```
Revision after findings (do this the CHEAP way):
- If the reviewer returns findings, do NOT restart the ceremony. Fix the exact
  findings, then have the verifier re-check ONLY those points (targeted
  commands, not the full battery), and the reviewer re-read ONLY the new diff.
- One full battery run per task, at the end, is enough evidence for the
  receipt. Re-running the entire suite after every fix wastes the turn.
- Batch your evidence: group verification commands into ONE shell invocation
  per checkpoint instead of dozens of single-command calls.
```

- [ ] **Step 2:** el aviso RN (`SAIKIT REVIEW NOTICE: ... those edits were not reviewed`) gana la coletilla `Re-review the new diff only; do not restart the ceremony.`
- [ ] **Step 3:** auditar diff de línea base (solo texto; 0 veredictos) → regrabar. **Step 4: suite → commit** `feat(10.2): el contrato pide re-review dirigido y evidencia en batch`.

---

### Task 10.3: role files — verifier no duplica al reviewer, y ambos en batch

**Files:**
- Modify: `agents/verifier.md`, `agents/reviewer.md`, `agents/implementer.md` (fuente del repo; se instalan al perfil con el flujo de 5.6)
- Test: sin gate; la validación es la medición de 10.4

- [ ] **Step 1: `agents/reviewer.md`** — la sección "Verification" cambia de "Run the repo's own type-check / build / test commands" a: *"Do NOT re-run the full test suite: the verifier already did and its evidence is in the turn. Re-run ONLY a check whose result you have concrete reason to distrust, and say why. Your job is the diff: correctness, consistency, reuse, security."*
- [ ] **Step 2: `agents/verifier.md`** — en "Tests": *"run the focused suite for the changed area; the FULL suite at most once per task, and only when the change is broad or the task is closing"* + nueva sección **Batch your evidence**: *"group your verification commands into a few shell invocations (one per checkpoint), never one call per command — each call costs a full model turn."*
- [ ] **Step 3: `agents/implementer.md`** — misma sección de batching + *"run focused checks while editing; leave the full battery to the verifier"*.
- [ ] **Step 4:** reinstalar perfiles al host (flujo 5.6) y commit `feat(10.3): role files sin verificacion duplicada y con evidencia en batch`.

---

### Task 10.4: medición de cierre de la fase

- [ ] **Step 1:** correr UNA task real comparable con `-saikit` (ceremonia completa) y UNA con `-saikit:fast`, cronometrar con el método del transcript (gaps por evento, como la medición 2026-08-13).
- [ ] **Step 2:** DoD de la fase: task full ≤ 1 h (antes ~4 h), task fast ≤ 15 min, cero gates perdidos (recibo + verify presentes en ambas). Si no se cumple, el residuo se mide y se decide (no se itera a ciegas).
- [ ] **Step 3:** registrar resultado en `docs/` + cerrar filas en Plans.md.

---

## Orden y dependencias

```
9.5 (frontera) ──> 10.1 (fast reusa la frontera nueva)
9.1, 9.2, 9.3, 9.4, 9.6 — independientes entre sí (serializar por convención: 1 PR c/u)
9.7, 9.8 — tocan limpieza de estado; después de 9.4 para no chocar en start_harness
9.9 — independiente (settings + check)
10.2, 10.3 — independientes de Phase 9; 10.1 primero que 10.4
10.4 — al final de todo
```

**Estimación:** Phase 9 ≈ 7 tasks mecánicas (patrón Phase 8: ~30–60 min c/u con suite final) + 9.9 corta. Phase 10 ≈ 10.1 es la grande (~2 h con línea base), 10.2/10.3 cortas, 10.4 es medición.

**Riesgos globales:** (1) 9.2 es el regex más propenso a sobre-exigir — controles verdes desde el día 1 y línea base completa; (2) 10.1 toca `write_state` (todos los call sites) — la batería de mutaciones existente es la red; (3) cada regrabado de línea base exige el audit de 0-veredictos ANTES (disciplina ya ejercida en 8.4 y 6.3).

---

## Cross-review (codex, ronda 1 — 2026-08-14)

5 hallazgos (4 media, 1 baja, 0 alta ⇒ sin segunda ronda, tope de quality-kit). Los 5 verificados e incorporados arriba:

1. [media] 9.2 sin `\n` como separador → agregado (`\\n`/`\\t` literales de dos chars — `$command_text` viaja sin decodificar) + `caso_g2_runner_multilinea_marca`.
2. [media] 9.2 comillas dejaban pasar `echo "pytest"` → guardia `ECHO_LEAD_RE` del lado estricto + 2 casos (incluido el límite atado por test).
3. [media] 9.7 el barrido no discriminaba hermana viva de muerta en la cobertura → el caso siembra AMBAS y exige que la fresca sobreviva.
4. [media] 10.1: `-saikit:fast` YA arma hoy (el `:` pasa la frontera — verificado con grep); el RE del sentinel no cambia, la detección del carril es grep exacto y el sufijo desconocido arma FULL (atado por `caso_g1_sufijo_desconocido_arma_full`).
5. [baja] 9.9 estaba desactualizada: el check ya prueba `Agent` — task reescrita como acción de operador + verificación viva, sin commit de código.

Residuales: ninguno de severidad alta; no se abre segunda ronda.
