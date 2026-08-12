# Task 5.2 — Medir el contrato de SALIDA de zcode (plan para GLM, tras 5.1)

`[Test]` `[lane:gate]` `[tdd:required]`.
**DoD íntegra en `Plans.md:98`:** (1) cada una de las **4 formas** que el hook
emite hoy tiene un veredicto MEDIDO en zcode — aceptada / rechazada por el
esquema / ignorada — y el rechazo se distingue del silencio; (2) `exit 2` en
`Stop` tiene medido si bloquea, si continúa o si cuenta como error; (3) el
resultado decide si `TARGET=claude` alcanza o hace falta un `TARGET=zcode`
propio, y esa decisión queda **declarada con su evidencia**. **Depende de:**
5.1. **Se puede medir en el mismo repo descartable que la 5.1**; no en el
mismo proceso (zcode fotografía los hooks al arrancar).

> **Esto NO implementa el gate en zcode ni toca el hook.** Es la medición
> que decide si 5.3–5.5 son “el mismo hook + otro registro” o un port. Si
> `exit 2` en Stop no mueve el turno, el gate es decorativo en zcode y la
> Phase 5 se re-planifica **antes** de cablear `install-hook.sh`.

## Cross-review del PLAN con Codex (2 rondas, 2026-08-12) — tope cumplido

Tope: 2ª solo con alta, **jamás 3ª**. Ronda 1: 4 altas + 2 medias + 1 baja,
incorporadas. Ronda 2 (esta): 4 altas + 1 media + 1 baja, incorporadas.
**Listo para GLM. No hay 3ª.**

### Ronda 2 (sobre el texto post-ronda-1)

1. **[alta] ACEPTADO+verificado** — En 3.7.5-11, `exn()` solo llama
   `d3i` (parse JSON) si `exitCode===0`. Si `exitCode===2` va a `p3i`
   y **no lee stdout**. `block` (JSON+exit 2) y `exit2` miden lo mismo.
   **Fix:** forma 2 se mide con **exit 0** (`block0`). `exit2` se mide
   aparte (vacío + stderr). El hook vivo combina JSON+exit2+stderr: en
   este CLI el efecto real es `p3i` (stderr → `decision:block` en Stop).
2. **[alta] ACEPTADO+verificado** — hooks OK no dejan stdout/stderr en
   el log diario (`hook.run.completed=0` hoy); `transcript_path` es un
   tmp que `cleanup()` borra. Ausencia de `PROBE` en el log ≠ no corrió.
   **Fix:** side-channel en el dest (`probe-ran/<nonce>.ok`) que el
   probe escribe siempre. El nonce de context se busca en
   `~/.zcode/cli/agents/` de esa sesión, no en el tmp.
3. **[alta] ACEPTADO** — DoD pide accepted/rejected/ignored, no
   `indistinguishable`. Si `budget` = `empty` en Stop ⇒ **`ignored`**
   (sin efecto observable). Se declara la limitación; no se cierra con
   una cuarta categoría.
4. **[alta] ACEPTADO** — `extra` con nonce hallado = `accepted` y eso
   **confirma esquema no estricto**. Fila nueva en §E.
5. **[media] ACEPTADO** — limpieza: `grep -q` y fallar si **hay** hit
   (no `grep -l` ⇒ 0).
6. **[baja] ACEPTADO** — el pie que decía “aún no pasó Codex” se
   elimina. Este texto es post-2ª ronda.

### Ronda 1 (resumen; ya en el cuerpo)

1. **[alta] ACEPTADO** — El mismo modo en UPS y Stop hace que `exit2`/`block`
   puedan abortar el prompt y **nunca llegar a Stop**, y que `notice` se
   observe en el evento equivocado. **Fix:** el probe mira
   `hook_event_name` y solo emite la forma si el evento es el de esa
   forma. En el otro evento: stdout vacío, exit 0.
2. **[alta] ACEPTADO** — Que el modelo no cite `PROBE-CONTEXT` no prueba
   `ignored`. **Fix:** oráculo = log del hook (corrió / schema fail /
   nonce en el transcript o en el record de injection). Sin eso:
   `unobserved`, no `ignored`.
3. **[alta] ACEPTADO** — `budget` (continue:false, exit 0) se ve igual
   que un Stop normal. **Fix:** se mide **después** de `exit2`/`block`.
   Si esos continúan el modelo y `budget` no, es `accepted-as-stop`. Si
   nadie continúa, forma 3 = `indistinguishable` (se declara, no se
   finge accepted/ignored).
4. **[alta] ACEPTADO** — La tabla de decisión no cubría mixtos (p. ej.
   `block` accepted + `exit2` ignored). **Fix:** filas mixtas en §E.
5. **[media] ACEPTADO** — Append al user-config: temp + validar JSON +
   `mv`. Si falla, el vivo queda intacto. Tests en sandbox.
6. **[media] ACEPTADO** — No registrar ni quitar 5.1 hasta que 5.1 haya
   cosechado/cerrado. El commit 1 del probe (código+tests) sí puede ir
   en paralelo. `--instalar` del probe es post-5.1.
7. **[baja] ACEPTADO** — Install parcial: completar la entrada que
   falta, no duplicar la que está.

**Veredicto sobre el draft: REQUEST_CHANGES.** Ejecutar el texto de abajo.

## Relación con 5.1 (no pisar, no esperar de más)

- 5.1 cierra el **contrato de entrada** (forma del payload, nombre de la
  herramienta, alias Task/Agent). 5.2 cierra el **contrato de salida**.
- Si 5.1 declara que zcode no dispara hooks, 5.2 **no arranca**: no hay
  stdout que medir. Plans.md de 5.2 se queda en TODO.
- “Misma sesión” en la DoD = mismo descartable
  (`C:\dev\saikit-captura-zcode`) y el mismo operador adelante. **Sesión
  zcode NUEVA** tras registrar el probe.
- **No se instala el probe ni se quita el capturador de 5.1** hasta que
  5.1 haya cosechado (o declarado fallo). El código+tests del probe
  (commit 1) sí pueden escribirse en paralelo.
- Lecciones de 5.1 que este plan **no re-litiga**:
  - Este CLI (3.7.5-11) **ignora** hooks de `<repo>/.zcode/config.json`.
    Registro = append quirúrgico al **user-config**.
  - Marker propio (`--saikit-probe-id 5.2`), no “contiene el nombre del
    script”.
  - Bash = `C:/Program Files/Git/bin/bash.exe` (archivo Windows). Nunca
    `/usr/bin/bash`.
  - Backup del user-config en `~/.zcode/cli/saikit-backups/`, no en el
    dest git.
  - Tests contra `SAIKIT_ZCODE_USER_CONFIG` de sandbox. Core Rule 4.
  - `--quitar` de 5.1 (id `5.1`) y de 5.2 (id `5.2`) no se pisan.

## A quién le toca qué

| Quién | Qué | Qué NO |
|---|---|---|
| **GLM** | Probe + tests (TDD); registrar/quitar en user-config; leer logs; escribir el veredicto | Abrir zcode, cambiar `probe-mode`, “ver” si el modelo recibió contexto |
| **Operador** | Sesión nueva de **zcode** (no `glm`) en el descartable; un prompt por modo; decir qué vio | Inventar veredictos, commitear logs |

Hay un **STOP** por cada modo (§D). GLM no simula la UI de zcode.

## Las 4 formas (fuente: el hook vivo, no la guía)

Verificado en `hooks/summonaikit-harness.sh` (2026-08-12):

| # | Quién la emite | Evento | stdout | exit | Qué pretende en Claude |
|---|---|---|---|---|---|
| 1 | `inject_contract` `:762` | `UserPromptSubmit` | `{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"…"}}` | 0 | Inyectar el contrato |
| 2 | `emit_gate_failure` `:990` | `Stop` | `{"decision":"block","reason":"…"}` | **2** | Bloquear / pedir otro turno |
| 3 | `emit_budget_exhausted` `:1012` | `Stop` | `{"continue":false,"stopReason":"…"}` | 0 | Cortar el ciclo |
| 4 | aviso RN `:1193` | `Stop` (cierre limpio) | `{"systemMessage":"SAIKIT REVIEW NOTICE: …"}` | 0 | Aviso al usuario, no decide |

Más el caso que la DoD nombra aparte:

| # | Qué | Evento | stdout | exit | Por qué |
|---|---|---|---|---|---|
| 5 | `exit 2` pelado | `Stop` | (vacío) | 2 | La guía vieja dice block solo en PreToolUse/PermissionRequest; Stop “pide continuación”. **Es la medición que más pesa.** |
| 6 | clave extra | `UserPromptSubmit` | forma 1 + `"saikitProbe":true` | 0 | La skill `diagnosing-hooks` dice esquema **estricto** (clave extra tumba todo). zcode.z.ai (2026-08-12) dice **unknown fields ignored**. Este CLI no se fía de ninguna de las dos. |

`emit_allow` en target no-cursor **no imprime nada** (`:694`, exit 0). No es
una de las 4 formas; es el control negativo (silencio = allow).

## Premisa que este plan NO da por cierta

El spec (`:1119`) y `Plans.md:98` afirman “esquema ESTRICTO”. Las docs
oficiales actuales lo contradicen. **5.2 mide cuál de las dos describe
3.7.5-11.** El caso 6 es el que lo decide. No se reescribe el spec hasta
tener el veredicto.

## Qué cambia y qué NO

**NO cambia:**
- `hooks/summonaikit-harness.sh`.
- Los hooks ajenos del user-config (SessionStart, RTK, tokentracker) ni
  las entradas `--saikit-capture-id 5.1` si el operador las dejó.
- 5.3–5.5. La decisión TARGET=claude vs zcode **se declara**; no se
  implementa acá.
- El override de workspace. Sigue muerto en este CLI.

**Cambia:**
- `tools/probe-zcode-output.sh` (nuevo) + `tests/test_probe_zcode_output.sh`.
- Registro temporal en el user-config (id `5.2`), con `--quitar`.
- `docs/task-5.2-salida.md` (veredictos, sin crudos de turno).
- Spec § El segundo host: el párrafo del esquema estricto se re-redacta
  con lo medido.
- `Plans.md:98` → `cc:完了` solo si los 5+6 casos tienen veredicto
  observado (no supposed).

---

## A) El probe (GLM solo, TDD)

`[tdd:required]` aplica al probe, no al acto de mirar zcode. Rojo/verde
sobre `tests/test_probe_zcode_output.sh`, no sobre `tests/run.sh`.

### A1. Contrato

```
# como hook (stdin → stdout + exit). Modo leído de:
#   1) $SAIKIT_PROBE_MODE
#   2) --mode <nombre>
#   3) archivo --mode-file <path>  (el operador lo pisa entre turnos)
#
# flags de registro (como 5.1):
#   --only-cwd <dir>     si pwd -P no coincide, exit 0 y stdout vacío
#   --saikit-probe-id 5.2
#   --mode-file <path>
```

Modos y salida **exacta** (byte a byte en los tests; el texto del
mensaje puede ser el literal `PROBE`):

| mode | stdout | exit |
|---|---|---|
| `context` | forma 1, `additionalContext":"PROBE-CONTEXT-<nonce>"` | 0 |
| `block0` | `{"decision":"block","reason":"PROBE-BLOCK-<nonce>"}` | **0** (para que `d3i` parseé el JSON) |
| `budget` | `{"continue":false,"stopReason":"PROBE-BUDGET-<nonce>"}` | 0 |
| `notice` | `{"systemMessage":"PROBE-NOTICE-<nonce>"}` | 0 |
| `exit2` | vacío; stderr `PROBE-EXIT2-<nonce>` | 2 |
| `extra` | forma 1 con `PROBE-EXTRA-<nonce>` **más** `"saikitProbe":true` | 0 |
| `empty` | (vacío) | 0 |
| (ausente/basura) | (vacío) | 0 |  fail-open

Registrar el mismo binario en **UserPromptSubmit y Stop** (sin matcher).
El probe **lee `hook_event_name` del stdin** y solo emite si el evento
es el de ese modo. Si no coincide: stdout vacío, exit 0 (no interfiere).

| mode | emite solo en |
|---|---|
| `context`, `extra` | `UserPromptSubmit` |
| `block0`, `budget`, `notice`, `exit2` | `Stop` |
| `empty` | ninguno (siempre vacío, exit 0) |

En **todos** los modos (incluido `exit2`) el probe escribe
`<dest>/probe-ran/<nonce>.ok` *antes* de salir — prueba de que corrió,
independiente del log de zcode. Test: modo `exit2` + evento Stop ⇒
exit 2, archivo `.ok` existe.

`block0` (no `block`) es la forma 2: JSON con exit 0. El hook vivo
manda JSON+exit 2; en 3.7.5-11 ese JSON **no se parsea**. Se declara.

No volcar env. No escribir el payload a disco (eso es 5.1). Un printf a
stderr con `PROBE mode=<m> event=<hook_event_name> exit=<n>` ayuda a
leer el log de zcode; stderr no entra al esquema.

### A2. Tests del probe

`tests/test_probe_zcode_output.sh`, sandbox HOME. Casos:

1. Cada modo de la tabla, **con el evento correcto** en stdin: stdout
   exacto + exit exacto.
2. Cada modo Stop (`block0`/`exit2`/…) con evento UPS ⇒ exit 0, vacío,
   y **no** escribe `probe-ran` (evento incorrecto).
   Cada modo UPS con evento Stop ⇒ igual.
3. Modo basura / ausente ⇒ exit 0, stdout vacío.
4. `--only-cwd` de otro dir ⇒ exit 0, stdout vacío, sin `.ok`, aunque
   el modo sea `exit2` y el evento sea Stop.
5. `exit2` + Stop ⇒ exit 2, `.ok` existe, stdout vacío, stderr con nonce.
6. `extra` contiene `saikitProbe` y el `additionalContext`.
7. El script es `bash -n` válido.

```
bash tests/test_probe_zcode_output.sh
```

Verde ⇒ commit:

```
feat(5.2): probe de las 4 formas de stdout + exit 2 para medir zcode
```

### A3. Registro en el user-config (misma disciplina que 5.1)

Extender `tools/capture-payloads.sh` **o** un `tools/probe-zcode-output.sh
--instalar` propio. Preferible **script propio** (`--instalar` / `--quitar`)
para no mezclar ids 5.1 y 5.2 en el mismo parser. Si se reusa el
capturador, el id **tiene** que ser `5.2` y no tocar entradas `5.1`.

`--instalar <repo>`:

- User-config = `$SAIKIT_ZCODE_USER_CONFIG` (default
  `~/.zcode/cli/config.json`). No existe ⇒ exit 2, no crear de cero.
- Backup en `<dir-del-user-config>/saikit-backups/` (no en el dest git).
- Escritura: temp en el mismo dir → `python -m json.tool` (o
  equivalente) valida → `mv`. Si el temp no es JSON, se borra y el
  vivo queda intacto. Test: un user-config sandbox sobrevive a un
  append que se aborta antes del `mv`.
- Append a `UserPromptSubmit` y `Stop` (sin matcher), `type: process`,
  `command` = `C:/Program Files/Git/bin/bash.exe` si existe como
  archivo, `args`:

```
<probe> --saikit-probe-id 5.2 --only-cwd <dest> --mode-file <dest>/probe-mode.txt
```

- Marca: `<repo>/.zcode/.probe-zcode-owned`.
- `probe-mode.txt` inicial: `empty`.
- Si las 2 entradas con id 5.2 ya están ⇒ no duplicar. Si está 1 de 2
  ⇒ agregar solo la que falta.

`--quitar`: solo entradas `--saikit-probe-id 5.2`. No toca 5.1, ni
SessionStart, ni tokentracker.

Tests (en el mismo `test_probe_zcode_output.sh` o uno hermano):

1. Append no borra un Stop dummy ajeno.
2. `--quitar` deja el dummy y las entradas 5.1 si las hubiera.
3. Dest repo = `$HOME/.zcode` ⇒ exit 2.
4. `--instalar` no escribe `.claude/settings.json`.

---

## B) Preparar (GLM, Git Bash, **solo cuando 5.1 ya cosechó**)

Gate: existe `docs/task-5.1-captura.md` **o** Plans.md 5.1 está en
`cc:完了` **o** 5.1 declaró fallo de medición (hooks no corren ⇒ 5.2
no arranca). Hasta entonces: no `--instalar` probe, no `--quitar` el
capturador de 5.1.

Después de cosechar 5.1:

```bash
cd /c/dev/saikit-captura-zcode
bash /c/dev/summonaikit-claude/tools/capture-payloads.sh --quitar .
printf '%s\n' empty > probe-mode.txt
bash /c/dev/summonaikit-claude/tools/probe-zcode-output.sh --instalar .
```

Verificar: user-config tiene `--saikit-probe-id 5.2` en UPS y Stop;
tokentracker sigue; backup en `~/.zcode/cli/saikit-backups/`;
`~/.claude/settings.json` intacto.

**Nueva sesión de zcode** en ese repo. La que sirvió para 5.1 ya no vale.

---

## C) Cómo se distingue aceptada / rechazada / ignorada

Tres señales, en este orden. `not_observed != absent`.

1. **¿Corrió?** `<dest>/probe-ran/<nonce>.ok`. Sin ese archivo ⇒
   `unknown`. El log diario **no** es oráculo de “corrió”: los hooks
   OK no dejan stdout/stderr ahí (medido: `hook.run.completed=0`).
2. **Nonce de context/extra/notice:** buscar
   `PROBE-<mode>-<nonce>` en `~/.zcode/cli/agents/sess_*/` de **esta**
   sesión (wire/jsonl), no en `transcript_path` (tmp que zcode borra).
   Hallado ⇒ `accepted`. `.ok` existe y nonce ausente ⇒ `ignored`.
   `hook.run.failed` + schema ⇒ `rejected`.
3. **Stop:**
   - `exit2`: efecto de `p3i` (stderr → `decision:block` en Stop).
     ¿El modelo hizo otra pasada vs `empty`?
   - `block0`: ¿el JSON de forma 2 (exit 0) mueve el Stop? Si el log
     dice schema fail ⇒ `rejected`.
   - `budget`: si el efecto = `empty` ⇒ **`ignored`** (DoD: sin efecto
     observable). Si `exit2` continúa y `budget` no ⇒ `accepted` como
     corte. No existe la categoría `indistinguishable` en el cierre.

`rejected` ≠ `ignored` ≠ `unknown`. La DoD no admite una cuarta.

---

## D) STOP — un modo por turno (operador)

GLM escribe `probe-mode.txt`, pide sesión/turno, espera. No empaqueta
seis modos en un prompt.

Orden (Stop primero; `budget` **después** de `exit2`/`block0`):

1. `empty` — ¿aparece `probe-ran/<nonce>.ok`?
2. `exit2` — efecto de exit 2 en Stop (`p3i`).
3. `block0` — forma 2 parseada (`d3i`, exit 0).
4. `budget` — forma 3; vs `empty` / vs `exit2`.
5. `context` — forma 1 (nonce en `cli/agents/`, no en el tmp).
6. `extra` — si el nonce aparece, `accepted` = esquema no estricto.
7. `notice` — forma 4.

Tarjeta que GLM imprime:

```
STOP — Gon, no GLM.

1. Cerrá zcode sobre C:\dev\saikit-captura-zcode si estaba abierta
   (snapshot de hooks).
2. Abrí zcode (NO glm) en ese repo.
3. GLM te va a decir el modo. Confirmá que probe-mode.txt tiene esa
   palabra (una línea, nada más).
4. Mandá un prompt corto (con o sin -saikit: el probe no mira el
   sentinel). Para modos de Stop, el turno tiene que LLEGAR a Stop
   (que el modelo intente terminar).
5. Decile a GLM, en una frase, qué viste en Stop:
   - ¿el modelo hizo **otra pasada** o el turno se acabó?
   - ¿salió un error de hook?
   (El nonce de context/notice lo busca GLM en el log, no vos.)
6. No hace falta recibo ni delegar. Eso era 5.1.
```

Si un modo sale `unknown` (hook no corrió), no se afirma rejected.
Se mira el log. Si el registro no está, se re-instala y se abre
sesión nueva. No se rellena la tabla con la guía.

---

## E) Decisión TARGET=claude vs TARGET=zcode

Se escribe en `docs/task-5.2-salida.md`, no se implementa.

| Evidencia | Decisión |
|---|---|
| Forma 1 `accepted` **y** (`block0` **o** `exit2`) mueve el Stop | `TARGET=claude` alcanza. En este CLI el vivo (JSON+exit2) se comporta como `exit2`; si `exit2` mueve, el gate actual sirve. |
| `block0` accepted **y** `exit2` ignored | Raro en 3.7.5-11 (exit 2 siempre entra a `p3i`). Anotar. El vivo usa exit 2, así que **no** alcanza: haría falta dejar de mandar exit 2. `TARGET=zcode`. |
| `exit2` accepted **y** `block0` rejected | El JSON de forma 2 no se usa (y con exit 0 el schema lo tira). El vivo se apoya en `p3i`. `TARGET=claude` si nos quedamos con exit 2+stderr. |
| `block0` e `exit2` ambas `ignored`/`rejected` | **Gate decorativo.** Re-planificar. |
| Forma 1 `rejected` | Adaptador UPS. `TARGET=zcode`. |
| Forma 1 `ignored` y Stop sí mueve | Contrato no llega. No se cierra como “claude alcanza”. |
| `budget` = `ignored` (igual que `empty`) | DoD cumplida: ignorada. No bloquea TARGET si Stop ya se decidió. |
| `extra` = `accepted` (nonce hallado pese a `saikitProbe`) | Esquema **no** estricto. Corregir el spec. |
| `extra` = `rejected` (schema fail) | Esquema estricto confirmado. |
| `extra` = `ignored` (`.ok` sí, nonce no) | La forma 1 no inyectó; ver forma 1. |
| `notice` = `ignored` | RN fail-open. No bloquea 5.3–5.5. |
| Cualquier modo de la DoD (4 formas + exit2) en `unknown` | No se decide TARGET. 5.2 no cierra. |

La decisión es **una frase + la tabla**. Sin “probablemente”.

---

## F) Entregables

### F1. `docs/task-5.2-salida.md`

Tabla de los 7 modos (4 formas + exit2 + extra + empty) con veredicto,
señal (UI / log / ambos) y cita de una línea del log **redactada**.
Cero payloads, cero prompts, cero rutas de perfil. La decisión
TARGET=… al final.

### F2. Spec § El segundo host

Reemplazar el bullet del esquema estricto por lo medido. Mismo bloque
para `exit 2` en Stop. Sin diario.

### F3. `Plans.md:98`

`cc:完了 [<sha>]` **solo si** las 4 formas + `exit2` tienen
accepted / rejected / ignored (no `unknown`). `budget` idéntico a
`empty` cuenta como **ignored**. Convención: SHA de este repo.

### F4. Limpieza

```bash
bash /c/dev/summonaikit-claude/tools/probe-zcode-output.sh --quitar /c/dev/saikit-captura-zcode
```

```bash
# tiene que FALLAR el grep (no hay hit). grep -q exit 0 = todavía está.
if grep -q 'saikit-probe-id 5.2' ~/.zcode/cli/config.json; then
  echo FAIL: el probe sigue registrado; else echo OK; fi
```
Tokentracker / 5.1 (si quedó) siguen.

---

## G) Commits

1. `feat(5.2): probe de stdout/exit para medir el contrato de zcode` —
   probe + tests + `--instalar/--quitar`.
2. **STOP** (§D), un modo por turno.
3. `docs(5.2): veredictos de las 4 formas y exit 2 en Stop`.
4. `docs(5.2): cerrar Task 5.2 en Plans.md` — solo si F3 aplica.

TDD: `bash tests/test_probe_zcode_output.sh`.
Gate final del commit 1: `pre-commit run --all-files` + `tests/run.sh`.
Nunca `--no-verify`.

---

## Límites

1. No se toca el hook.
2. User-config: solo append/quitar id `5.2`.
3. No se cablea zcode en producción (5.4).
4. No se resuelve 5.3 (estado cross-host).
5. Workspace override sigue muerto; 5.5 tendrá que dejar de usarlo como
   staging. Fuera de esta task.
6. El gate sigue **advisory**.
7. `glm` ≠ `zcode`.

## Cross-review

**2 rondas hechas. No hay 3ª.** Este texto se le puede pasar a GLM
después de que 5.1 cosechó (Depends).

Residual declarado: el nonce de context se busca en
`~/.zcode/cli/agents/` de la sesión, no en `transcript_path`. Si esa
carpeta no conserva el additionalContext, forma 1 queda `ignored` o
`unknown` según haya `.ok` o no — no se inventa accepted.
