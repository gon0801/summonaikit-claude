# Deploy log — summonaikit-claude

Registro de cada deploy (post-merge) del gate hook al perfil vivo. Ver
`AGENTS.md` § "Deploy tras merge".

El deploy de este repo = garantizar que el hook vivo
(`~/.claude/hooks/summonaikit-harness.sh`) coincide con `master`, y verificar
que siga registrado en las 3 fases de `~/.claude/settings.json`.

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
