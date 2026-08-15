# Task 6.2 — Contrato de SALIDA de Codex: veredictos y decisión TARGET

`[Test]` `[lane:gate]`. Medido el **2026-08-14** en Codex CLI **0.147.0**,
**12 turnos reales** en el repo descartable `C:\dev\saikit-probe-codex`, con
`tools/probe-zcode-output.sh --host codex`.

Los turnos son **headless** (`codex exec --json`), no la TUI — ver § Límite de
la medición. Un modo por turno, sesión nueva por turno.

**DoD cumplida:** las 4 formas + `exit 2` tienen veredicto MEDIDO; el rechazo se
distingue del silencio; `exit 2` en `Stop` tiene medido qué hace; y la decisión
sobre `TARGET=codex` queda escrita con su evidencia. **Cero payloads crudos,
cero prompts, cero rutas de perfil** en este documento.

**El perfil no se tocó, y es evidencia:** los tres cksum de `~/.codex/` son
idénticos antes y después de los 12 turnos — `hooks.json 2271698800 2717`,
`summonaikit-harness.sh 2998360912 55609`,
`summonaikit-harness.ps1 2437289870 1501`. Ningún `hooks.json` se editó: el
registro es colocación de shim, que el `.ps1` prefiere solo.

## El veredicto que decide la 6.4

> **El hook vivo, tal como emite hoy, sería DECORATIVO en Codex.**

`emit_gate_failure` manda el JSON de forma 2 **más `exit 2`**. Medido:

| lo que se emitió | Stops en la ronda | `hook_prompt` en el rollout | ¿bloqueó? |
|---|---|---|---|
| `{"decision":"block",…}` + **exit 0** | **4** | **3** | ✅ **sí** |
| `{"decision":"block",…}` + **exit 2** | **1** | **0** | ❌ **no** (2/2 corridas) |

Mismo JSON byte a byte, mismo repo, misma máquina, misma versión del probe y el
mismo payload de `Stop`. **Sesiones distintas** — cada turno abre una nueva, así
que la sesión no puede ser una constante y no se la invoca como tal. Lo único
que se movió a propósito entre las dos filas es el código de salida.
⇒ **Codex 0.147.0 descarta el stdout del hook cuando el exit no es 0.**

Y no es que el 2 no llegue: se verificó la cadena entera aparte —
`.ps1 → shim → probe` devuelve **exit 2** y el stderr con el nonce sale. Codex
lo recibe y no actúa.

⇒ **`TARGET=codex` necesita forma propia**: el JSON de bloqueo tiene que ir con
**exit 0**. Es la misma conclusión a la que llegó 7.2 para Grok, por otra razón.

## Cómo se leyó cada señal

1. **¿Corrió?** `<repo>/probe-ran/<nonce>.ok`. Sin ese archivo ⇒ `unknown`,
   nunca "no corrió". El control lo validó: dejó `.ok` en las **3** fases
   (`UserPromptSubmit`, `PostToolUse`, `Stop`) con el mismo `round=`.
2. **Inyección (UPS):** el nonce en el rollout de la sesión
   (`~/.codex/sessions/…/rollout-*.jsonl`), que 6.1 midió como destino de
   `transcript_path`. Aparece —o no— como mensaje de rol `developer`. Lectura,
   nunca escritura.
3. **Bloqueo (Stop):** conteo de `.ok` con `event=Stop` **de la misma
   `round=`**, más la línea `stop_active=` (el `stop_hook_active` del payload).
   El control da **1**; `stop_active` pasa a `true` desde la 2.ª visita cuando
   la continuación la fuerza el hook. Esa segunda señal es la que 5.2 no tuvo:
   distingue "el hook forzó otra pasada" de "llegó otro turno".
4. **Rechazo vs. silencio:** el rollout muestra si el texto entró
   (`<hook_prompt …>`) o no entró. Un `no entró` con el `.ok` presente es
   rechazo del contenido, no falta de ejecución.

## Tabla de veredictos

| # | forma (fuente en el hook) | evento | exit | señal medida | veredicto |
|---|---|---|---|---|---|
| 1 | `empty` (control) | ambos | 0 | 3 `.ok` (las 3 fases), 1 Stop, `stop_active=false` | **control** |
| 2 | `hookSpecificOutput.additionalContext` (`inject_contract`) | UPS | 0 | el nonce entra como mensaje `developer`, **2/2 turnos** | ✅ **aceptada** |
| 3 | forma 2 + clave extra `"saikitProbe":true` | UPS | 0 | el nonce **NO** entra, **0/3 turnos** | ❌ **rechazada** ⇒ **esquema ESTRICTO** |
| 4 | `decision:block` (`emit_gate_failure`, sin su exit) | Stop | 0 | **4 Stops**, `stop_active=true` desde la 2.ª, 3 `hook_prompt`, el modelo emite el `reason` como su mensaje | ✅ **aceptada** |
| 5 | `continue:false`+`stopReason` (`emit_budget_exhausted`) | Stop | 0 | 1 Stop = control | ⚪ **ignorada** |
| 6 | `systemMessage` (aviso RN) | Stop | 0 | 1 Stop = control, sin superficie visible | ⚪ **ignorada** |
| 7 | `exit 2` pelado | Stop | 2 | 1 Stop = control. Cadena verificada: el `.ps1` devuelve 2 y el stderr llega | ⚪ **ignorada** (recibido, no actuado) |
| 8 | **forma 2 + `exit 2` = el hook VIVO** | Stop | 2 | 1 Stop, **0** `hook_prompt`, **2/2 corridas** | ⚪ **ignorada** ⇒ el stdout se descarta si `exit != 0` |

La fila 8 no estaba en el plan: se agregó al medir la 7 y ver que el `exit 2`
solo no hace nada. Sin ella, 6.4 habría prendido un gate que no gatea.

## Premisas tumbadas

- **La hipótesis del diseño cae en sus DOS mitades.**
  `docs/phase-6-codex-design.md` § 6.2 declaraba, como creencia explícita, que
  «el fork de Codex usa nuestra misma forma de bloqueo y el esquema de Claude
  sirve ahí». No: el esquema **es estricto** y el `exit 2` **anula** el stdout.
- **«El esquema no es estricto» no es una propiedad del esquema: es por host.**
  5.2 midió en zcode que la clave extra se toleraba y con eso se corrigió el
  spec (F2). En Codex la misma clave extra **invalida la salida entera**. Las
  dos mediciones son correctas y opuestas; lo que estaba mal era generalizar.
- **`exit 2` en `Stop` no es universal.** En zcode bloqueaba (4 pasadas). En
  Codex no hace nada — y encima tira la salida que sí habría funcionado.

## Datos nuevos para 6.4 y 6.6

- **Bloquear en Codex = el JSON con `exit 0`.** La rama de salida de `codex`
  tiene que separar el código de salida de la decisión.
- **El `reason` llega al modelo** envuelto en
  `<hook_prompt hook_run_id="stop:N:…">…</hook_prompt>`, y el modelo lo trata
  como instrucción: en el turno de `block0` respondió con el literal del nonce.
  El canal de feedback del gate funciona.
- **La inyección del contrato viaja como mensaje de rol `developer`** (en zcode
  era `system`). Inofensivo para el hook, que lee el payload y no el contexto.
- **`emit_budget_exhausted` (`continue:false` + exit 0) es ignorado**, igual que
  en zcode. Si 6.4 quiere el corte por presupuesto, necesita otra forma.
- **El aviso RN (`systemMessage`) es ignorado** — fail-open, inocuo.
- **Coexistir con otro hook en la misma fase no rompe nada.** El `Stop` y el
  `UserPromptSubmit` del operador tienen un segundo hook registrado
  (`harness-mem`). La inyección nuestra entró igual, 2/2. El confusor que el
  plan declaró en § B-bis quedó **descartado por medición**, no supuesto.

## Límite de la medición, declarado

**Todo se midió con `codex exec` (headless), no con la TUI interactiva.** Para
el bloqueo y la inyección eso no debería importar —son el mismo motor— pero
para `systemMessage` **sí puede importar**: un mensaje de sistema podría tener
superficie en la TUI y ninguna en headless. Su veredicto de `ignorada` vale
**para headless**; en interactivo queda `unknown`.

## Lo que sigue `unknown`, declarado

- **Cuántas pasadas hace Codex antes de cortar solo.** No se midió porque
  nuestro tope de 3 emisiones por ronda llegó primero — a propósito: la
  alternativa era dejar correr un lazo que paga el operador.
- Si Codex tiene un **Stop de cierre** distinto del de turno (Grok sí).
- **Qué hace cuando dos hooks de la misma fase salen 2.** No se pudo observar:
  el nuestro salió 2 y fue ignorado, así que no hubo efecto que atribuir.
- Si `spawn_agent` emite evento de despacho — heredado de 6.1, fuera de alcance.

## Cómo se midió / fuente

- Probe: `tools/probe-zcode-output.sh --host codex` (commits `feat(6.2)`).
  Registro por **colocación de shim** en `<repo>/.codex/hooks/`, que el `.ps1`
  del perfil prefiere; ninguna config se editó. Limpieza con `--quitar --host
  codex` (verificado: shim fuera, marca fuera, cksums idénticos).
- 12 turnos `codex exec --json -s workspace-write`, sesión nueva cada uno:
  1 control, 2 `context`, 3 `extra`, 1 `block0`, 1 `budget`, 1 `notice`,
  1 `exit2`, 2 `block2`.
- Oráculos: `.ok` (corrió), rollout de la sesión (inyección y `hook_prompt`),
  conteo de Stops por `round=` + `stop_active=` (bloqueo).
- Verificación local aparte (sin turno): la cadena `.ps1 → shim → probe`
  devuelve `exit 2` para `exit2` y `exit 0` para `block0` — o sea que el código
  de salida que Codex ve es el que creemos.
