# Deploy log — summonaikit-claude

Registro de cada deploy (post-merge) del gate hook al perfil vivo. Ver
`AGENTS.md` § "Deploy tras merge".

El deploy de este repo = garantizar que el hook vivo
(`~/.claude/hooks/summonaikit-harness.sh`) coincide con `master`, y verificar
que siga registrado en las 3 fases de `~/.claude/settings.json`.

## 2026-08-15 — PR #22 / Phase 9: seis defectos del gate (merge `637330a`)

- **Mergeado:** PR #22 `feat/phase-9-gate-defects` → master — Tasks **9.1, 9.2,
  9.4, 9.5, 9.6 y 9.7**. Reparto acordado con la sesión de Phase 6, que tomó
  9.3 y 9.8 (viven en `stop_gate`) y cerró Phase 6 en paralelo.
- **¿Cambió el hook?** **Sí**, y en seis lugares:
  - **9.4** el fallback al payload crudo se acota a `PHASE=session` (sin eso, un
    `-saikit` en un campo de resumen **armaba la ceremonia sin que nadie la
    pidiera**);
  - **9.5** la frontera izquierda del sentinel excluye `/` y `-` (referenciar
    `docs/-saikit.md` o citar `--saikit` armaba);
  - **9.6** el walker resetea `en_text`/`en_assistant` al cerrar llaves — sin
    eso **el gate CERRABA por texto que el asistente no escribió**;
  - **9.7** `podar_dir_sesion` + `barrer_estado_viejo` (TTL 14 días): `state/`
    dejaba un directorio inmortal por sesión;
  - **9.1** `failed` entra a la vía B del CI y los literales de gradle al CS
    (dotnet y gradle **reventados acreditaban verificación**);
  - **9.2** `ECHO_LEAD_RE` y el crédito deja de mirar `tool_name` (`echo pytest`
    acreditaba, y una tool MCP llamada como un runner también).
- **`install-hook.sh`:** `REPARADO: el destino era nuestro y difiere de la
  fuente.` Backup:
  `~/.claude/hooks/saikit-backups/summonaikit-harness.sh.nuestro.20260815-114439.bak`
  **Vivo vs master:** cksum idéntico (`3755086874 97179`).
- **`check-hook-registration.sh`:** exit 0 y **silencio**.
- **Gates:** `tests/run.sh` **OK (18 tests)** con `SAIKIT_HOOK_VIVO` a la fuente
  (corrida al final, tras integrar master); `pre-commit run --all-files` Passed.
- **Mutaciones:** 8 nuevas, todas atrapadas por su propio caso. Se **retiró**
  `tool_name_desacotado` (se quedó sin detector al sacar `tool_name` del
  crédito) y se **reemplazó** por `credito_por_tool_name`, que sí es observable.
- **CodeRabbit (PR #22):** 3 hallazgos, los 3 válidos y atendidos. El segundo
  proponía dejar sólo `TEST_RUNNER_CMD_RE`: **se probó y rompió tres casos
  legítimos** — esa constante cubre únicamente el runner propio del repo, así
  que habría borrado el crédito de pytest y compañía. El agujero era real, la
  receta no. El tercero encontró que mi propio caso de regresión **no probaba
  lo que decía**: el fixture ponía el `tool_name` real en `Bash`. Corregido con
  un fixture nuevo y su mutación.
- **Integración con la sesión paralela:** master avanzó con los PRs #23/#24/#25
  durante la review; se integró por **merge** (force-push prohibido). Los dos
  conflictos fueron de UNIÓN, no de decisión: las listas `CASOS_G1`/`CASOS_G4` y
  las filas 9.x de `Plans.md`. **Lección anotada:** la primera resolución salió
  invertida (en `git merge` el primer lado es HEAD, no el entrante) y pisó los
  cierres propios con el estado de master; se detectó verificando fila por fila
  después de resolver, no antes.
- **Operador:** Gon.

## 2026-08-15 — PR #19 / Task 10.6: reglas permanentes en `SessionStart` (merge `3f4f076`)

- **Mergeado:** PR #19 `feat/10.6-standing-rules-sessionstart` → master — el kit
  gana un canal para **invariantes permanentes**: en la fase `SessionStart`
  inyecta 3 reglas de velocidad **arme o no** el turno. No gatea, no arma, no
  cuenta ciclos, y **no toca el invariante del sentinel**.
- **Por qué existe, medido:** el transcript `e86ddb2c` (2026-08-14) mostró una
  task de ~7 h con **2.6 h bloqueado esperando** (51 % del tiempo de
  herramientas), ~1.75 h evitables. **La regla ya estaba** en el contrato desde
  la 10.2 — pero `harness_context()` sólo corre en el camino **armado**, y esa
  sesión nunca armó (`/goal`, sin `-saikit`). La regla existía y era invisible.
- **¿Cambió el hook?** **Sí.** `standing_rules()` + `emit_standing_rules()` y una
  rama en `start_harness` acotada a `PHASE=session` **y** `TARGET=claude`,
  después del desarme y antes del `emit_allow`.
- **`install-hook.sh`:** `REPARADO: el destino era nuestro y difiere de la
  fuente.` Backup:
  `~/.claude/hooks/saikit-backups/summonaikit-harness.sh.nuestro.20260815-001541.bak`
  **Vivo vs master:** cksum idéntico (`1303783510 88474`).
- **`check-hook-registration.sh`:** exit 0 y **silencio** — sin el advisory de
  `SessionStart` (la fase quedó registrada) y sin el advisory de A9 (el matcher
  ya cubre `Agent`).
- **Registro (acción de operador, no del instalador):** entrada `SessionStart`
  sin matcher con `PHASE=session` en `~/.claude/settings.json`, con backup
  (`settings.json.bak-10.6-20260814-215110`), las 7 entradas ajenas intactas y
  JSON validado antes de escribir. `install-hook.sh` **no** registra en Claude:
  sólo instala el archivo, y su única rama de registro es `--host zcode`.
- **Verificación viva POST-DEPLOY:** un turno headless `claude -p` en un repo
  nuevo, **sin `-saikit` y sin staging**, devolvió las 3 reglas **textuales**. La
  medición previa (antes de diseñar) ya había confirmado que `SessionStart` en
  Claude acepta `hookSpecificOutput.additionalContext`.
- **Alcance:** sólo `TARGET=claude`. zcode, Codex y Grok quedan `unknown`, no
  "no lo tienen": registrar a ciegas es el error que la 6.2 evitó por un pelo.
- **CodeRabbit (PR #19):** 3 hallazgos, los 3 válidos. Dos arreglados; el Major
  (un `summary` de sesión reanudada que cite un `-saikit` viejo hace que la
  sesión arme y las reglas no salgan) **no se arregló a propósito**: ese fallback
  es C9 / Task 9.4, cuya DoD decide conservarlo, y acotarlo puso rojo
  `caso_g6_armado_por_target`. Queda **atado por caso** y declarado como pérdida
  de cobertura.
- **Integración con la sesión paralela:** master avanzó con PR #17/#18/#20
  durante la review y el #20 tocó el hook (`TEST_RUNNER_CMD_RE`). Se integró por
  **merge** (el force-push está prohibido acá) dejando el árbol byte a byte igual
  al ya verificado, y la suite se re-corrió **después** de fusionar los dos
  cambios del hook.
- **Gates:** `tests/run.sh` OK (18 tests) con `SAIKIT_HOOK_VIVO` a la fuente;
  `pre-commit run --all-files` Passed.
- **Operador:** Gon.

## 2026-08-15 — PR #15 / Task 6.2: contrato de salida de Codex (merge `5006de7`)

- **Mergeado:** PR #15 `feat/6.2-probe-codex` → master — `probe-zcode-output.sh`
  gana `--host codex` (registro por **colocación de shim**, no mutación de
  config), el modo `block2`, cuatro guardas nuevas con su caso, veredictos
  medidos (`docs/task-6.2-salida.md`), plan (`docs/task-6.2-plan.md`) y cierre
  de la fila 6.2 con la restricción heredada escrita en la DoD de 6.4.
- **¿Cambió el hook?** **No.** Cero commits sobre `hooks/`; sólo andamiaje de
  medición (`tools/`), tests y docs.
- **`install-hook.sh`: NO se ejecutó, y es deliberado.** El merge trajo el hook
  de Phase 10 (PR #16), y el working tree de esta sesión estaba en la rama 6.2,
  o sea con el hook **anterior**. Correr el instalador desde ahí habría **pisado
  el hook vivo con una copia vieja** — el deploy habría revertido Phase 10 en
  silencio. En su lugar se verificó la igualdad, que es lo que el deploy
  realmente afirma: `cksum` del vivo == `cksum` de
  `origin/master:hooks/summonaikit-harness.sh`. Deploy **no-op verificado**.
- **`check-hook-registration.sh`:** exit 0; mismo advisory conocido de A9
  (matcher PostToolUse sin `Agent`), preexistente.
- **Medición 6.2 (contexto):** 12 turnos headless (`codex exec --json`) en
  `C:\dev\saikit-probe-codex`, Codex CLI 0.147.0, sesión nueva por turno.
  **Hallazgo que decide la 6.4:** con el MISMO JSON de bloqueo, `exit 0` ⇒ 4
  Stops y 3 `hook_prompt` (bloquea); `exit 2` ⇒ 1 Stop y 0 `hook_prompt` (no
  bloquea, 2/2). Codex **descarta el stdout del hook cuando el exit no es 0**,
  así que `emit_gate_failure` tal como emite hoy sería **decorativo** ahí.
  `additionalContext` aceptada (2/2, entra como rol `developer`); clave extra
  **rechazada** (0/3) ⇒ esquema **estricto**, al revés que zcode. Perfil
  `~/.codex` byte a byte intacto (3 cksum antes/después); ninguna config
  editada.
- **CodeRabbit (PR #15):** 4 hallazgos, los 4 verificados contra el código y
  válidos, atendidos en `559e952` — orden marca→shim (el shim quedaba vivo y
  `--quitar` se negaba a sacarlo), marca ajena que se pisaba, symlinks bajo la
  raíz del repo (esquivaban la negativa a tocar el perfil real) y un error
  factual del doc. **Límite declarado:** el caso del symlink reporta `unknown`
  en Windows/MSYS y su mutación no queda atrapada en esta máquina.
- **Vivo vs master:** cksum idéntico (`3561109110 81554`).
- **Operador:** Gon.

## 2026-08-14 — PR #14 / Task 7.2: contrato de salida Grok (merge `fcccf87`)

- **Mergeado:** PR #14 `feat/7.2-probe-grok` → master — `probe-zcode-output.sh`
  gana `--host grok` (con 2 ciclos de corrección: reviewer interno +
  cross-review Codex, 3 hallazgos), tests, veredictos medidos
  (`docs/task-7.2-salida.md`), párrafo spec y cierre de la fila 7.2.
- **¿Cambió el hook?** **No.** Sólo andamiaje de medición (`tools/`), tests y
  docs; `hooks/summonaikit-harness.sh` intacto.
- **`install-hook.sh`:** `YA AL DIA: el destino es nuestro y byte a byte igual a
  la fuente.` (deploy no-op, exit 0).
- **`check-hook-registration.sh`:** exit 0; mismo advisory conocido de A9
  (matcher PostToolUse sin `Agent`), preexistente.
- **Medición 7.2 (contexto):** 7 rondas headless + 4 variantes oráculo en
  `C:\dev\saikit-captura-grok`; bloquean `decision:block` (exit 0) y
  `continue:false`; ignoradas `exit 2`, `additionalContext` (4 formas) y
  `systemMessage`; perfil `~/.grok` byte a byte intacto (cksums), trust
  revocado. Decisión: `TARGET=grok` con forma propia; armado se re-planifica
  en 7.3.
- **Operador:** Gon.

## 2026-08-13 — PR #13 / Phase 8: auditoría del sentinel (merge `ed8ff80`)

- **Mergeado:** PR #13 `fix/phase-8-sentinel-audit` → master — tasks 8.1–8.4
  (lectores escape-aware en armado/evidencia, escotillas PAUSED/DELEGATED al
  turno actual, etiquetas `**Label**:`, contrato honesto sobre el desarme).
  Incluye el trabajo validado de la sesión anterior (escotilla DELEGATED +
  ROLE FALLBACK, Task 6.3) que estaba sin commitear.
- **¿Cambió el hook?** **Sí.** `json_top_level_decoded` para `prompt`;
  `command`/`file_path` acotados a `tool_input`; `tool_name`/`transcript_path`
  top-level; `text_hatch` para las escotillas; bold en `has_receipt_label`;
  bullets PAUSED/DELEGATED del contrato reescritos.
- **`install-hook.sh`:** `REPARADO: el destino era nuestro y difiere de la
  fuente.` Backup:
  `~/.claude/hooks/saikit-backups/summonaikit-harness.sh.nuestro.20260813-235148.bak`
- **`check-hook-registration.sh`:** registro en las 3 fases OK (exit 0). Mismo
  advisory conocido de A9 (matcher PostToolUse sin `Agent`).
- **Vivo vs master:** cksum idéntico (`2905702708 80780`).
- **Nota:** deploy corrido desde worktree limpio de `origin/master` — el árbol
  de trabajo principal tenía WIP de la Task 7.2 de otra sesión y no se tocó.
- **Operador:** Gon.

## 2026-08-13 — PR #12 / diseño Phase 7 corregido + plan 7.2 (merge `4088213`)

- **Mergeado:** PR #12 `docs/7.2-plan-y-diseno` → master — diseño de Phase 7
  actualizado con la evidencia de la 7.1 (D2/D3/D5/D6/D7, JSON canónico con
  comando PowerShell, riesgos cerrados), párrafo "Medido …, Task 7.1" en el
  spec, filas 7.2–7.6 de `Plans.md` corregidas, y `docs/task-7.2-plan.md` con
  cross-review de Codex incorporado (1 ronda, 6 hallazgos aceptados).
- **¿Cambió el hook?** **No.** Todo el PR es documentación.
- **`install-hook.sh`:** `YA AL DIA: el destino es nuestro y byte a byte igual a
  la fuente.` (deploy no-op, exit 0).
- **`check-hook-registration.sh`:** exit 0. Mismo advisory conocido de A9
  (matcher de `PostToolUse` sin `Agent`), sin cambios.
- **Vivo vs master:** cksum idéntico (`2628234111 70227`).
- **Coordinación:** deploy corrido desde el worktree; el checkout principal
  sigue con cambios sin commitear de la 6.3 (otro agente) y su `git pull`
  queda pendiente hasta que esa task commitee.
- **Operador:** Gon (vía kimi).

## 2026-08-13 — PR #11 / Task 7.1 (merge `e41f7da`)

- **Mergeado:** PR #11 `feat/7.1-grok-capture` → master — Task 7.1 medida y
  cerrada (`cc:完了`): captura de **37 payloads reales de Grok Build 1.0.3** en
  5 rondas sobre `C:\dev\saikit-captura-grok` (descartable). Writeup:
  `docs/task-7.1-captura.md`. `tools/capture-payloads.sh` gana `--host grok`
  (andamiaje de medición, como 5.1/6.1) + 13 casos en
  `tests/test_capture_payloads.sh`.
- **¿Cambió el hook?** **No.** Todo el PR es medición + herramienta de
  captura; `hooks/summonaikit-harness.sh` no se toca. Grok no se instala hasta
  la 7.6.
- **`install-hook.sh`:** `YA AL DIA: el destino es nuestro y byte a byte igual a
  la fuente.` (deploy no-op, exit 0).
- **`check-hook-registration.sh`:** exit 0. Mismo advisory conocido de A9
  (matcher de `PostToolUse` sin `Agent`), sin cambios.
- **Vivo vs master:** cksum idéntico (`2628234111 70227`), sha256
  `ef9a66bf3a51ee5b…`.
- **Lo que la 7.1 mide, y no vale perder:** **D3 se prende entero** — el rol
  del subagente llega por 3 canales (`SubagentStart`, despacho
  `spawn_subagent`, eventos internos) y el `env` map entrega
  `SUMMONAIKIT_HOOK_TARGET=grok`. `transcriptPath` cae en `~/.grok/sessions/`
  (A6 contiene). Premisas caídas, declaradas: `PostToolUseFailure` no dispara
  (las fallas llegan como `post_tool_use` con `toolResult` de error), el runner
  de hooks en Windows ejecuta vía **powershell.exe** (la 7.5 emite
  `& "bash.exe" "hook"`), la tool de escritura real es `write` además de
  `search_replace`. Perfil `~/.grok` byte a byte intacto (cksums
  antes/después); trust declarado y revocado.
- **Nota de coordinación:** el trabajo se hizo en worktree
  (`C:\dev\summonaikit-claude-7.1`) para no colisionar con la Phase 6 en curso
  en el checkout principal. El `git pull` post-merge en el checkout principal
  queda **pendiente**: tiene cambios sin commitear de la 6.3 que tocan
  `Plans.md` y bloquean el ff — se sincroniza cuando esa task commitee.
- **Operador:** Gon (vía kimi).

## 2026-08-13 — PR #10 / Phase 6 + Phase 7 + Task 6.1 (merge `454b02a`)

- **Mergeado:** PR #10 `docs/phase-6-codex-design` → master. Diseño de **Phase 6
  (codex como tercer host)** con D1–D5, diseño de **Phase 7 (Grok Build TUI)**
  con D1–D8, las 6 filas de Phase 6 en `Plans.md`, y **Task 6.1 medida y
  cerrada** (`cc:完了`).
- **¿Cambió el hook?** **No.** Todo el PR es medición, diseño y herramienta de
  captura; `hooks/summonaikit-harness.sh` no se toca. Codex no se toca hasta
  la 6.6.
- **`install-hook.sh`:** `YA AL DIA: el destino es nuestro y byte a byte igual a
  la fuente.` (deploy no-op, exit 0).
- **`check-hook-registration.sh`:** exit 0. Repite el advisory conocido de A9
  (el matcher de `PostToolUse` no cubre `Agent`), sin cambios respecto de los
  deploys anteriores.
- **Vivo vs master:** cksum idéntico (`2628234111 70227`), sha256
  `ef9a66bf3a51ee5b…`.
- **Lo que el PR mide, y no vale perder:** el rol del subagente **llega al gate
  en Codex**, en `agent_type` de primer nivel, y `:927` ya lo lee sin cambios
  ⇒ D3 se prende en la 6.4. `transcript_path` cae dentro de
  `~/.codex/sessions/` ⇒ la contención de A6 funciona allá. El perfil de codex
  del operador **no se tocó** en ninguna de las 3 corridas de captura (los 3
  cksum idénticos antes y después).
- **Revisión:** kimi (1 ronda, 5 hallazgos bajos) + **CodeRabbit (6 hallazgos,
  4 Major, los 4 legítimos)**. Con codex no se pudo — su skill `harness-review`
  secuestró el prompt; arreglado en `quality-kit` `138fe42`, medido.
- **Operador:** Gon.

## 2026-08-13 — PR #9 / Task 5.5 (merge `b401fdd`)

- **Mergeado:** PR #9 `feat/5.5-zcode-golden` → master — escenarios 17–25
  (zcode) + token `ZCODE_*` en el arnés + baseline de 25 escenarios
  (`--check` reproducible). Cierra `Plans.md` 5.5.
- **¿Cambió el hook?** **No.** 5.5 es línea base + arnés; el harness intacto.
- **`install-hook.sh`:** `YA AL DIA` (deploy no-op).
- **Vivo vs master:** cksum idéntico (`2628234111 70227`).
- **Operador:** Gon. Phase 5 del target zcode queda cerrada (5.1–5.6).

## 2026-08-12 — PR #8 / G2 skip ES (merge `024e0ec`)

- **Mergeado:** PR #8 `feat/g2-verify-skip-es` → master — `VERIFY_SKIP_RE`
  acepta `no corri` / `no se corrio` / `sin tests` (el vivo zcode decía
  "No corrí los candados" y el gate no lo leía). Cierra STOP vivo de
  5.3 y 5.4 en `Plans.md`.
- **¿Cambió el hook?** **Sí.** Skip de Verify + contrato UPS nombra las frases.
- **`install-hook.sh`:** `YA AL DIA` (el vivo se había reparado antes del
  merge; cksum idéntico `2628234111 70227`).
- **`check-hook-registration.sh`:** 3 fases OK. Advisory A9 de siempre
  (matcher PostToolUse sin `Agent`).
- **Vivo vs master:** cksum idéntico (`2628234111 70227`).
- **Operador:** Gon. El próximo `-saikit` (sesión nueva) ya usa este hook.

## 2026-08-12 — PR #7 / Task 5.6 (merge `269802a`)

- **Mergeado:** PR #7 `feat/5.6-zcode-agent-profiles` → master — Task 5.6:
  `install-hook --host zcode` instala `implementer`/`verifier`/`reviewer` en
  `~/.zcode/agents/` (tres estados, marca solo en frontmatter, bash.exe
  antes de escribir, backup al quitar). Spec + `Plans.md` 5.6.
- **¿Cambió el hook?** **No.** 5.6 tocó el instalador y las plantillas;
  `hooks/summonaikit-harness.sh` intacto.
- **`install-hook.sh`:** `YA AL DIA: el destino es nuestro y byte a byte igual
  a la fuente.` (deploy no-op del hook).
- **`install-hook.sh --host zcode`:** `REGISTRADO: harness en el user-config de
  zcode (3 fases, id 5.4).` Perfiles vivos **IDENTICO** a `agents/*.md`
  (NUESTRO_IDENTICO, sin reescribir). Backup del config:
  `~/.zcode/cli/saikit-backups/config.json.zcode.20260812-231448.bak`.
- **`check-hook-registration.sh --zcode-config`:** **silencio** (registro
  completo).
- **`check-hook-registration.sh` (Claude):** 3 fases OK. Advisory conocido de
  A9 (matcher PostToolUse sin `Agent`).
- **Vivo vs master:** cksum idéntico (`1507687064 69327`).
- **Operador:** Gon. Los tres tipos ya están en `~/.zcode/agents/`. Hace falta
  **sesión zcode nueva** para que Agent los liste (la pausada nació antes).

## 2026-08-12 — PR #2 / Task 5.1 (merge `2420162`)

- **Mergeado:** PR #2 `feat/5.1-capture-payloads-zcode` → master — Task 5.1:
  `tools/capture-payloads.sh --host zcode` (utilidad de captura) + tests TDD +
  `docs/task-5.1-captura.md` + spec + cierre de `Plans.md:97`.
- **¿Cambió el hook?** **No.** 5.1 tocó `tools/capture-payloads.sh` (utilidad)
  y docs; `hooks/summonaikit-harness.sh` intacto.
- **`install-hook.sh`:** `YA AL DIA: el destino es nuestro y byte a byte igual
  a la fuente.` (deploy no-op).
- **`check-hook-registration.sh`:** registro en las 3 fases OK (exit 0).
  Advisory conocido: el matcher PostToolUse (`Bash|Edit|Write|apply_patch|Task`)
  no cubre `Agent` — gap de A9 en Claude (en zcode lo cierra el alias
  `Task`↔`Agent` medido en esta misma task).
- **Vivo vs master:** cksum idéntico (`3605963032 66538`).
- **Operador:** Gon (config real restaurada tras `--quitar` en el cierre de 5.1).

## 2026-08-12 — PR #4 / Task 5.2 (merge `b722150`)

- **Mergeado:** PR #4 `feat/5.2-probe-zcode-output` → master — Task 5.2: probe de
  las 4 formas de stdout + `exit 2` para medir el contrato de salida de zcode
  (`tools/probe-zcode-output.sh` + tests TDD), `docs/task-5.2-salida.md`
  (veredictos), spec § segundo host corregido (esquema no estricto + `exit 2` en
  Stop sí bloquea), cierre de `Plans.md:98`. Decisión: `TARGET=claude` alcanza.
- **¿Cambió el hook?** **No.** 5.2 sumó un tool de medición + docs;
  `hooks/summonaikit-harness.sh` intacto.
- **`install-hook.sh`:** `YA AL DIA: el destino es nuestro y byte a byte igual a
  la fuente.` (deploy no-op).
- **`check-hook-registration.sh`:** registro en las 3 fases OK (exit 0). Mismo
  advisory conocido de A9 (matcher PostToolUse sin `Agent`).
- **Vivo vs master:** cksum idéntico (`3605963032 66538`).
- **Operador:** Gon (config de zcode restaurada tras `--quitar` del probe en el
  cierre de 5.2; el probe midió en sesiones nuevas sobre repo descartable).

## 2026-08-12 — PR #6 / Task 5.4 (merge `fdb875c`)

- **Mergeado:** PR #6 `feat/5.4-zcode-registration` → master — Task 5.4: el harness
  queda registrado en las 3 fases del user-config de zcode (`hooks.events.*`).
  `check-hook-registration --zcode-config` y `install-hook --host zcode` aprenden
  la segunda forma de registro. Hook: `TARGET` por `ZCODE_*` (A10 cerrado en
  zcode), budget zcode→`exit 2`, `PHASE` lee `hookEventName` (camel). Plans.md 5.4
  queda `cc:TODO` hasta el STOP vivo (turno `-saikit` real en zcode).
- **¿Cambió el hook?** **Sí.** TARGET (fallback por `ZCODE_*`), budget (rama zcode
  `exit 2`), PHASE (lectura camel además de snake).
- **`install-hook.sh`:** `REPARADO: el destino era nuestro y difiere de la fuente.`
  Backup: `~/.claude/hooks/saikit-backups/summonaikit-harness.sh.nuestro.20260812-212905.bak`
- **`install-hook.sh --host zcode`:** `REGISTRADO: harness en el user-config de
  zcode (3 fases, id 5.4).` Backup del config:
  `~/.zcode/cli/saikit-backups/config.json.zcode.20260812-212918.bak`. Primera task
  que cablea el harness en el segundo host.
- **`check-hook-registration.sh --zcode-config`:** **silencio** (registro completo:
  3 fases, `enabled:true`, sin matcher indebido en UPS/Stop, PTU cubre Agent).
- **`check-hook-registration.sh` (Claude):** 3 fases OK (exit 0). Advisory conocido
  de A9 (matcher PostToolUse sin `Agent`); en zcode lo cierra el alias
  `Task`↔`Agent` (5.1).
- **Vivo vs master:** cksum idéntico (`1507687064 69327`).
- **Operador:** Gon. **STOP §D pendiente:** turno `-saikit` real en zcode que arme
  y deje estado bajo `state/zcode/` (cierra `Plans.md:100`).

## 2026-08-12 — PR #5 / Task 5.3 (merge `053c853`)

- **Mergeado:** PR #5 `feat/5.3-host-state-isolation` → master — Task 5.3:
  `STATE_ROOT` llavea por host (`claude`/`zcode`/`other`). Un turno de zcode y
  uno de Claude sobre el mismo `$0` ya no comparten `harness-state.env` ni
  `RN_PENDING`. Plans.md 5.3 queda `cc:TODO` (STOP vivo pide el registro de 5.4).
- **¿Cambió el hook?** **Sí.** `PROJECT_DIR` pasa a
  `STATE_ROOT/$HOST/$PROJECT_KEY`.
- **`install-hook.sh`:** `REPARADO: el destino era nuestro y difiere de la
  fuente.` Backup:
  `~/.claude/hooks/saikit-backups/summonaikit-harness.sh.nuestro.20260812-190346.bak`
- **`check-hook-registration.sh`:** registro en las 3 fases OK (exit 0). Mismo
  advisory conocido de A9 (matcher PostToolUse sin `Agent`).
- **Vivo vs master:** cksum idéntico (`4023882360 67915`).
- **Operador:** Gon.

## 2026-08-14 — PR #16 / Phase 10 (Tasks 10.1, 10.2 y 10.3)

- **Mergeado:** PR #16 `feat/phase-10-ceremonia-velocidad` → master — Phase 10
  (velocidad de la ceremonia): 10.1 carril `-saikit:fast` (lane= en el estado,
  Stop exige recibo+verify pero no los 3 subagentes; clasificadores muertos
  retirados), 10.2 contrato con re-review dirigido al delta + evidencia en
  batch + coletilla al aviso RN, 10.3 role files del repo sin verificación
  duplicada. 9.x y 10.4 quedan `cc:TODO`. Plan doc commiteado byte-idéntico al
  staged de la sesión de 6.2 (coordinación en `.harness-mem/`).
- **¿Cambió el hook?** **Sí** (10.1 + 10.2: detección de lane, `write_state`
  con lane, `stop_gate` con exención de ceremonia, contrato con carril y
  bloque CHEAP-way, aviso RN con coletilla).
- **`install-hook.sh`:** `REPARADO/ACTUALIZADO: el destino era nuestro y difiere
  de la fuente` — vivo actualizado a master. **Desviación declarada:** deploy
  ejecutado desde el worktree `summonaikit-claude-wt-p10` (master) porque el
  árbol principal está ocupado por la sesión de `feat/6.2-probe-codex` con
  trabajo sin commitear; `git checkout master && git pull --ff-only` hechos en
  el worktree.
- **`check-hook-registration.sh`:** registro en las 3 fases OK (exit 0). Mismo
  advisory conocido del matcher PostToolUse sin `Agent`.
- **Vivo vs master:** cmp byte a byte idéntico (verificado por la sesión).
- **10.3 Step 4 (reinstalar perfiles al host, flujo 5.6):** sigue diferido —
  instala sólo a `~/.zcode/agents` con `--host zcode`; no se ejecutó en este
  deploy (ver fila 10.3 en Plans.md). El dir neutral `~/.agents/agents/` es
  propiedad del kit vendor y NO se toca (medido: contenido propio, no deriva
  de este repo).
- **Operador:** Gon (sesión zcode, goal "fase de eficiencia de kimi").

## 2026-08-15 — PR #17 / Task 9.10 + PR #18 / Task 10.5

- **Mergeado:** PR #17 `feat/9.10-runner-bash` — `TEST_RUNNER_RE` reconoce el
  runner bash propio (`bash tests/run.sh`, ruta absoluta, tras `&&`, invocación
  directa `./tests/run.sh`), sin reabrir A3 (`cat tests/run.sh` y
  `grep run.sh tests/run.sh` no cuentan; corpus G2 32 casos verde). Motivación:
  en hosts sin transcript legible el gate de verificación quedaba insatisfible
  para repos bash-only. PR #18 `feat/10.5-ci-linux` — job `suite` en
  ubuntu-latest (~1m35s vs ~18 min de MSYS2), `SAIKIT_CI_LINUX=1` salta los 4
  tests Windows-bound con listado explícito (capture/install/probe exigen
  bash.exe de Windows; hook_acl clasifica SIDs vía PowerShell).
- **¿Cambió el hook?** **Sí** (9.10: dos ramas nuevas en TEST_RUNNER_RE).
- **`install-hook.sh`:** vivo actualizado a master. **Desviación declarada:**
  deploy desde worktree `summonaikit-claude-wt-p10` (árbol principal sigue
  ocupado por la sesión de 6.2).
- **`check-hook-registration.sh`:** 3 fases OK, exit 0 — y sin el advisory del
  matcher: el operador agregó `Agent` (y `SendMessage`) al matcher de
  PostToolUse de settings.json (backup `.pre-agent-matcher-20260815.bak`), la
  acción que la 3.7 pedía.
- **Vivo vs master:** cmp byte a byte idéntico (verificado).
- **Operador:** Gon (sesión zcode).

## 2026-08-15 — PR #20 / Cross-review codex r1 (9.10 cmdpos + runner)

- **Mergeado:** PR #20 `feat/9.10-cmdpos` — fix del hallazgo ALTA del
  cross-review codex r1: las ramas run.sh salen de `TEST_RUNNER_RE` (vuelve a
  su forma pre-9.10) y viven en `TEST_RUNNER_CMD_RE` nueva, sin wrapper, con
  posición de comando estricta y segmentos de path — los 5 decoys
  (`bash contest/run.sh`, `bash tests/run.sh/typo`, `grep bash tests/run.sh`,
  `printf 'bash tests/run.sh'`, `echo bash tests/run.sh`) medidos en ROJO y
  cerrados. Además: resumen de SKIP del runner siempre imprime (hallazgo BAJA)
  y env-determinism del caso nuevo (`env -u SAIKIT_CI_LINUX`). Residual
  declarado en 10.5: skip linux-ci por archivo entero.
- **¿Cambió el hook?** **Sí** (constante nueva + call sites del crédito).
- **`install-hook.sh`:** vivo actualizado a master (worktree, desviación de
  siempre: árbol principal ocupado por la sesión de 6.2).
- **`check-hook-registration.sh`:** 3 fases OK, exit 0.
- **Vivo vs master:** cmp byte a byte idéntico. CI del PR: quality PASS,
  suite PASS (1m43s), CodeRabbit PASS.
- **Operador:** Gon (sesión zcode). Ronda de cross-review: 1 de 1 (tope
  respetado; residuales declarados, sin re-revisión).

## 2026-08-15 — PR #21 / Task 10.7 (ceremonia por tarea)

- **Mergeado:** PR #21 `feat/10.6-ceremonia-por-tarea` — Task 10.7: el contrato
  gana "One ceremony per task, not per edit" (batch de ediciones + la
  secuencia UNA vez sobre el diff estable; ediciones triviales no re-delegan,
  se verifican una misma con check enfocado y se declaran en el recibo).
  Origen: feedback del operador post-10.2 (re-cadena por rename/move). Sin
  cambio de condición del gate; auditoría de línea base 0 veredictos.
- **¿Cambió el hook?** **Sí** (solo texto del contrato, 6 líneas).
- **Deploy:** install desde blob de origin/master (desviación adicional: el
  worktree no pudo hacer checkout de master — lo tiene tomado el árbol
  principal de la sesión 6.2; se desplegó el blob exacto de origin/master
  post-merge y se verificó byte a byte + registro OK).
- **`check-hook-registration.sh`:** 3 fases OK, exit 0.
- **CI del PR:** quality PASS, suite PASS (1m43s), CodeRabbit PASS.
- **Operador:** Gon (sesión zcode).

## 2026-08-15 — Merge ajeno 9.4+9.5 (f78e9c7) — deploy desde sesión zcode

- **Mergeado/pusheado por la sesión de Phase 9** (`f78e9c7` fix(9.4+9.5): el
  sentinel deja de armar por texto citado — campo ausente; `0b4c77f` reserva
  de filas 6.4/6.5/6.6/9.3/9.8 en cc:WIP). Su sesión sigue trabajando; este
  deploy sincroniza el vivo a master para no dejar el artefacto atrás
  (regla: deploy tras merge, SIEMPRE — su próximo deploy será no-op).
- **Deploy:** install desde blob de origin/master (worktree, desviación de
  siempre). **Vivo vs master:** cmp byte a byte idéntico (0b4c77f).
- **`check-hook-registration.sh`:** 3 fases OK, exit 0.
- **Operador:** Gon (sesión zcode).

## 2026-08-15 — PR #23 (2e7a181): Phase 6 (6.4+6.5+línea base 6.6) + 9.3 — deploy `~/.codex` (TERCER HOST)

- **Mergeado por la sesión de Phase 6** (worktree `wt-p6`). Contenido: HOST=codex
  por señal explícita (D2), ceremonia `case claude|codex` (D3 prendida), bloqueo
  con exit 0 en codex (lo que 6.2 midió), `--host codex` en el instalador,
  manifiesto con el vivo de Codex, verificador con la cadena wrapper, frontera
  anti-cita de 9.3, y línea base con los escenarios codex 27-33.
- **Deploy `~/.codex` (PRIMERA VEZ):** `install-hook.sh --host codex` desde wt-p6
  con contenido == origin/master (diff vacío verificado antes). Destino clasificó
  **VENDOR CONOCIDO** (etiqueta del manifiesto 6.5) → backup
  `saikit-backups/summonaikit-harness.sh.vendor.20260815-094928.bak` → reemplazo
  byte a byte (cmp OK). `--restore-vendor` queda como red (backup en manifiesto).
- **Verificador codex:** silencio, exit 0 (registro→wrapper y wrapper→hook verdes).
- **Perfiles ajenos intactos:** `~/.codex/hooks.json` cksum 2271698800 y
  `~/.claude/hooks/summonaikit-harness.sh` cksum 4159550777, idénticos antes/después.
- **Turnos reales (codex exec, headless):** `-saikit` ARMÓ — contrato inyectado,
  el modelo intentó `spawn_agent`, reintentó una vez como exige el flujo y declaró
  `SUMMONAIKIT HARNESS DELEGATED - awaiting implementer` (la escotilla, viva);
  estado en `state/codex/1686855735/<session>/`. El turno pelado NO armó (1 solo
  estado tras ambos). Nota: `codex exec` corre read-only por defecto — el patch
  del turno A fue rechazado por el sandbox de Codex, no por el gate.
- **`~/.claude` NO se tocó en este deploy**: el hook vivo de Claude quedó en el
  estado del deploy anterior (98ef786) y ahora está DETRÁS de master (6.4/9.3
  también lo cambian) — le toca al flujo de siempre de la sesión zcode/Phase 9
  en su próximo ciclo (avisado por broadcast).
- **Operador:** sesión Claude Phase 6 (autónoma), Gon dormido.

## 2026-08-15 — PR #25 (e332def): review de bots del PR #23 atendida — deploy no-op

- **Contenido:** Greptile P1 (la afirmación (b) del wrapper aceptaba una mención
  solo-en-comentario — ahora exige línea de código, con el límite "no se parsea
  PowerShell" declarado, criterio de la 0.4) + minor de CodeRabbit (el caso
  aserta el diagnóstico exacto). CodeRabbit no había alcanzado a correr en el
  #23 (mergeado antes de su pasada — lección aprendida: el #25 esperó a los DOS
  bots + CI antes de mergear). ROJO medido; CI 4/4.
- **Deploy `~/.codex`:** no-op — "YA AL DIA: el destino es nuestro y byte a byte
  igual a la fuente" (el merge tocó tools/tests, no el hook). Se corre y se
  registra igual, para no perder la costumbre.
- **Operador:** sesión Claude Phase 6 (autónoma).

## 2026-08-15 — PR #24 (73307cc): detección de secretos (Recommended) — deploy ACTUALIZA el vivo ~/.claude pendiente desde el PR #23

- **Mergeado por la sesión zcode** (worktree aparte, rama `feat/ci-secret-detection`).
  Contenido: `tools/check-secrets.sh` (gitleaks por archivo + fallback grep con los
  falsos conocidos excluidos), hook local de pre-commit, job `secrets` del CI
  (gitleaks 8.30.1 sobre el historial, sha256 pineado, `persist-credentials: false`),
  `.gitleaks.toml` (config default extendida + allowlist `tests/`) y test con 12
  casos y mutaciones acreditadas. Cierra el ítem "Recommended" de Plans.md.
- **Review de bots atendida en 2 rondas:** Greptile P1 real y confirmado por
  medición (`gitleaks dir` multi-arg IGNORA los archivos y escanea el CWD entero
  — fix: una invocación por archivo, con caso que lo habría atrapado y mutación
  roja), P2 checksum del binario, CR Major-sec (`persist-credentials`,
  `curl --fail`) y 3 minors (reporte `archivo:linea`, PATH del test verificado,
  wording de Plans.md). Greptile final: **5/5, sin blockers**. CI:
  quality/secrets/suite PASS.
- **¿Cambió el hook? El PR #24 NO lo toca — pero el deploy NO fue no-op:** el
  vivo estaba DETRÁS, cksum `4159550777` (= `f78e9c7`, exactamente el estado que
  el deploy del PR #23 dejó declarado pendiente "para el próximo ciclo").
  `install-hook.sh` lo REPARÓ con backup
  `saikit-backups/summonaikit-harness.sh.nuestro.20260815-105455.bak`. El vivo
  ahora incluye lo que trajeron #23/#25: HOST=codex por señal explícita (D2),
  ceremonia `claude|codex` (D3), bloqueo con exit 0 en codex y la frontera
  anti-cita de 9.3.
- **`check-hook-registration.sh`:** 3 fases OK, exit 0.
- **Vivo vs master:** cmp byte a byte idéntico.
- **Operador:** Gon (sesión zcode).
