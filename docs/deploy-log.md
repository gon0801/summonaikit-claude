# Deploy log — summonaikit-claude

Registro de cada deploy (post-merge) del gate hook al perfil vivo. Ver
`AGENTS.md` § "Deploy tras merge".

El deploy de este repo = garantizar que el hook vivo
(`~/.claude/hooks/summonaikit-harness.sh`) coincide con `master`, y verificar
que siga registrado en las 3 fases de `~/.claude/settings.json`.

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
