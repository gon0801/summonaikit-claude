# Task 7.6 — Release de Grok: recaptura, línea base, staging, install y turno real

Fecha: 2026-08-16. Grok Build 1.0.3 (`grok 1.0.3 (1a29d5bc12) [stable]`, modelo
`grok-4.6`), el mismo binario que midieron 7.1/7.2. Sesión de trabajo en el
worktree `summonaikit-76`, rama `feat/7.6-grok-release`.

## Línea de tiempo del perfil `~/.grok` (auditoría de integridad)

Esta task detectó una **sesión gemela** haciendo 7.6 en paralelo (worktree
`summonaikit-claude-wt-p7`, rama `feat/7.6-grok-baseline`, **sin commits
propios**). Su trabajo no está en git; lo que tocó del perfil quedó declarado
acá y NO se limpió (decisión del lead). Horas PDT del 2026-08-16:

| Hora | Actor | Acción sobre el perfil |
|---|---|---|
| 01:13 | gemela | crea `saikit-recaptura-grok`, agrega su entrada de trust (TOML 491→572 bytes) |
| 01:26-01:32 | **esta task** | fase A: 3 turnos headless de recaptura (sesiones `01a009af`, `01a009b0`, pelado) |
| ~01:45 | **esta task** | fase A limpia: `--quitar --host grok`, TOML restaurado a 572 (byte a byte) |
| ~01:50 | gemela | su staging (`saikit-staging-grok`); restaura el TOML a 491 (quitando SU entrada de la mañana) |
| 01:52:02 | gemela | `install-hook.sh --host grok` al perfil REAL: hook + JSON + agentes implementer/reviewer (verifier ajeno: DESCONOCIDO, intacto) |
| 01:53:12 | gemela | turno real `-saikit` en `saikit-turno-grok-76` (sesión `01a009c6`): dejó estado `cycle=1 agents_seen=implementer` (el gate BLOQUEÓ, ceremonia incompleta — residuo que queda declarado) |
| ~02:00 | gemela | restaura el TOML a 491; último artefacto suyo detectado; sin procesos activos desde entonces |
| 02:09 | **esta task** | detecta la instalación ajena al preparar la fase C; lo reporta al lead y continúa con salvaguardas |
| 02:13-02:18 | **esta task** | fase C: turno staging `-saikit` (sesión `01a009d9`) con hook de PROYECTO |
| 02:19 | **esta task** | fase C limpia: residuo vacío propio retirado, TOML restaurado a 491 |
| 02:21 | **esta task** | fase D: install propio ⇒ **YA AL DIA** (no-op verificado byte a byte) |
| 02:23-02:26 | **esta task** | fase D: turno real `-saikit` (sesión `01a009e0`) en `saikit-turno-real-76` |
| ~02:27 | **esta task** | fase D: turno pelado en sesión nueva (sin estado) |

Cksums del perfil (config.toml `158636524`, agents/verifier.md `353659411`,
hooks/imported-from-claude.json.disabled `3615174159`): **idénticos en todas
las fotos** de esta task (antes/después de A, C y D). El TOML volvió siempre a
su forma de arranque de cada fase, byte a byte, desde backup propio.

## A) Recaptura headless (payloads crudos)

Los 37 payloads de 7.1 ya no existían (`C:\dev\saikit-captura-grok\capturas\`
borrado). Recaptura en repo NUEVO `C:\dev\saikit-recaptura-grok-76` (git init)
con `bash tools/capture-payloads.sh --instalar <repo> --host grok` (7 entradas
con env map `SUMMONAIKIT_HOOK_TARGET=grok`), trust por entrada en
`trusted_folders.toml` con backup y restore byte a byte, y **3 turnos
headless** (`grok --always-approve --prompt-file`):

1. turno `-saikit`: tool `write` + comando `sh -c 'exit 1'` + despacho
   `spawn_subagent` (falló: tipo desconocido, ver abajo);
2. turno con `.grok/agents/implementer.md` de proyecto: despache
   `implementer` exitoso + eventos internos del hijo;
3. turno pelado (sin sentinel).

**22 payloads** (44 archivos: cada uno con su `.env`): 4 `user_prompt_submit`
(wrappeado el del usuario, pelado el del subagente), 10 `post_tool_use` en los
3 matchers (write, run_terminal_command ok y exit 1, spawn_subagent, read_file
interno), 1 `post_tool_use_failure`, 6 `stop` (pares `end_turn`/`shutdown`), 1
`subagent_start`. Los dumps `.env` confirman `GROK_HOOK_EVENT`,
`GROK_SESSION_ID`, `GROK_WORKSPACE_ROOT`, `CLAUDE_PROJECT_DIR`,
`SUMMONAIKIT_HOOK_TARGET=grok` y `CLAUDECODE` ausente.

**Forma 1:1 contra task-7.1-captura.md** (envelope camel, literales snake,
sentinel dentro de `<user_query>`, `toolResult` con `exit_code` NUMERO, Stop
`end_turn` con `lastAssistantMessage` vs `shutdown` sin él, rol por tres
canales). Ninguna premisa cayó. **Un dato NUEVO** que resuelve el `unknown` de
7.1: `PostToolUseFailure` SÍ disparó (1 evento en esta captura) — con un campo
`error` y SIN
`toolResult`, sobre el despacho `spawn_subagent` con tipo desconocido. Es
decir: PTUF = falla de runtime/despacho del tool; los errores de dominio
(exit≠0, FileNotFound, NoMatchesFound) siguen llegando como `post_tool_use`
normal con `toolResult` de error, exactamente como D5 lo asumió. El hook
registra PTUF en el JSON canónico (7.5 lo declaró "por si un release lo emite")
y su payload cae a `PHASE=tool` sin acreditar nada que no corresponda.

Nota de variación (no premisa): `background:true` en el despacho medido (7.1
midió `false`); el verificador interno corrió `read_file` (7.1 midió
`run_terminal_command`). La forma es la misma.

Limpieza: `--quitar --host grok` (rc 0), TOML restaurado byte a byte, cuatro
cksums del perfil idénticos a los de antes de la fase.

## B) Bloque golden 35-42 (commit `7c79194`)

Espejo del bloque codex de 6.6 (27-33) construido desde la recaptura: **8
escenarios** (35 sin armar / 36 arma+contrato / 37 evidencia incompleta con
runner ROJO / 38 falta verifier / 39 turno completo / 40 sin recibo / 41
presupuesto / 42 Stop `shutdown`). Cambios de código: `tools/golden-harness.sh`
(token `grok` con las tres señales reales del runner, unsets de `GROK_*`,
`estado_host` para grok), `tests/test_golden_harness.sh` (casos grok, conteo
4→5, bloque codex acotado), `tests/fixtures/arnes-falso/hook-falso.sh` (rama
D2 por SETNESS) + `05-grok`. ROJO medido: neutralizada la rama del falso, el
caso `estado_host: grok` se pone rojo (emite `other`).

Auditoría del regrabado: **región 01-34 BYTE-IDENTICA** (127211 bytes exactos,
0 veredictos movidos; el "diff" del bloque 34 en el split por bloques es el
separador en blanco que pasa a quedar a mitad de archivo, no contenido);
+1183 líneas = solo los bloques grok; `--check` reproducible 42/42 en dos
corridas; `test_golden_baseline` OK; `test_fixtures_json` OK (169 json).

Dos pines de cobertura que ningún otro bloque grok toca: el **37** graba el
veto D5 del `exit_code` NUMERO (runner rojo: `verified=0` en el estado; su
contracara verde vive en el 39) y el **42** graba que el Stop de cierre
`reason=shutdown` sale inmediato con el turno armado (`estado sin cambios`,
sin contar ciclo). La ceremonia se acredita por los DOS canales que tocan la
sesión armada (despacho `toolInput.subagent_type` + `SubagentStart`
`subagentType`); el canal interno del hijo viaja con `sessionId` PROPIO y no
acredita el estado del padre — medido en la recaptura, declarado en el README
del 38.

## C) Staging real con hook de proyecto (ANTES del perfil global)

Repo NUEVO `C:\dev\saikit-stage-76`: hook copia del source en
`<repo>/.grok/hooks/summonaikit-harness.sh` y `summonaikit.json` **generado
por el propio instalador 7.5** con overrides (`SAIKIT_GROK_HOOKS_DIR` al repo,
`SAIKIT_GROK_AGENTS_DIR` a un descartable — el perfil real no se tocó):
salida "REGISTRO GROK PUBLICADO" + command PowerShell
`& "<bash.exe>" "<hook de PROYECTO>"`. Trust declarado (backup previo) y un
turno `-saikit` headless.

Evidencia de que el hook de PROYECTO disparó (debug log):
`loaded hooks hook_count=10` (5 del registro global de la gemela + 5 del
proyecto) y `hook completed hook_name=project/summonaikit:user_prompt_submit`
y `...:stop` — **AMBOS registros corren** con el global vivo; cada uno escribe
su propio árbol de estado. El turno cerró la ceremonia COMPLETA con recibo
(implementer → verifier vía `loop-verifier` → reviewer) y el Stop pasó
`block=false` en ambos hooks: cierre limpio, que retira los archivos de estado
y deja solo el dir del proyecto (`state/grok/4028764718/` en ambos árboles).
`~/.grok/hooks/` quedó con sus ARCHIVOS byte-identicos; el dir vacío que mi
turno dejó en el árbol global se retiró con `rmdir` (el mismo primitivo que
usa el hook) y el listado volvió a calzar.

**Hallazgo del propio turno** (lo escribió el modelo en su Retro, y el D
lo repite): en Grok el tipo `spawn_subagent verifier` NO existe como persona
bundled (disponibles: explore, general-purpose, loop-verifier, plan); el
verificador se cubre con `loop-verifier`, que `canonical_agent_role` mapea al
rol verifier por el stem `verif`. El gate pasó por mapeo de función, como
diseñó D3/D4 — y el install NO puede instalar nuestro verifier.md porque el
slot lo ocupa el `verifier.md` AJENO del operador (7.5 lo declara DESCONOCIDO
y no lo pisa).

Limpieza: TOML restaurado byte a byte (491), cksums del perfil idénticos.

## D) Install global + verificador + turno real

1. `bash tools/install-hook.sh --host grok` contra el perfil REAL: **YA AL DIA**
   (el destino es nuestro y byte a byte igual a la fuente) + "AGENTE GROK
   DESCONOCIDO: verifier — no se toco". La instalación la había hecho la gemela
   a las 01:52; la medición honesta del tres-estados de ESTA corrida es el
   no-op con identidad verificada: sha256 del hook instalado == source del
   worktree (`b8176b54f0f754ba…`) y el JSON clasificado NUESTRO_IDENTICO por
   el propio instalador (comparación byte a byte contra `grok_json_canonico()`).
2. `bash tools/check-hook-registration.sh --grok-hooks-dir ~/.grok/hooks`:
   **exit 0, silencio** (verde — reporta solo huecos; se probó con un dir
   inexistente y sí reporta "unknown — ningun settings legible").
3. `~/.grok/agents/verifier.md` ajeno intacto (`353659411 373`, el cksum de
   7.1) e `imported-from-claude.json.disabled` intacto (`3615174159 894`).
4. Turnos reales en repo NUEVO `C:\dev\saikit-turno-real-76`:
   - `-saikit` (sesión nueva `01a009e0`): ARMÓ bajo
     `~/.grok/hooks/state/grok/1699990704/` (el dir se creó en esta fase; no
     existía en ninguna foto previa), corrió la ceremonia con recibo completo
     y el Stop pasó `block=false` — cierre limpio: los archivos de estado se
     retiran y queda el dir del proyecto. El receipt del modelo documenta
     implementer → verifier (loop-verifier, VERDICT PASS) → reviewer.
   - pelado en sesión nueva: "listo", **cero estado** (mi key sin cambios,
     ningún dir nuevo).
   - Conteo con scope a mi key (decisión del lead): **1 estado tras ambos
     turnos**. El residuo de la gemela (`2401780966`) queda declarado, no
     borrado.
5. `~/.claude/hooks/` y `~/.codex/hooks/` cksums idénticos antes/después.
6. El install QUEDA puesto (es el entregable). `--quitar-grok` existe como red;
   no hizo falta.

## Límites declarados

- **Sesión gemela**: su branch no tiene commits; su recaptura/staging/turnos
  usaron repos propios (`saikit-recaptura-grok`, `saikit-staging-grok`,
  `saikit-turno-grok-76`, `saikit-turno-grok-pelado`) y su install al perfil
  es la que esta task verificó en vez de publicar de cero. Su estado residual
  (`state/grok/2401780966/01a009c6…/`, `cycle=1`) queda como evidencia de un
  gate que bloqueó una ceremonia incompleta. El lead decide qué hacer con esa
  sesión.
- **Cierre limpio vs estado persistente**: los dos turnos `-saikit` de esta
  task completaron la ceremonia y cerraron limpio, así que el "arma bajo
  state/grok/" se afirma por el dir del proyecto creado + la decisión del Stop
  en el debug log, no por archivos de estado sobrevivientes (el cierre los
  retira por diseño, A4/Task 9.7). El caso "bloquea y deja estado" quedó
  medido por la gemela y por el bloque 37/40 de la línea base.
- **verifier bundling**: nuestro `verifier.md` no se instala en grok (slot
  ocupado por el ajeno); la ceremonia depende del mapeo de `loop-verifier`
  (medido dos veces) o del agente ajeno si el operador lo deja cargar.
  Declarado, no arreglado acá.
- **Turnos**: 3 de recaptura + 1 de staging + 2 del turno real = 6 headless
  en total para esta task.

## Pendiente tras merge (para el lead)

- PR de `feat/7.6-grok-release`, CI (`suite` job) en verde como gate final.
- Deploy post-merge según AGENTS.md **más `--host grok`** (el install ya está
  en el perfil; el deploy lo re-verifica como YA AL DIA) y registro en
  `docs/deploy-log.md`.
