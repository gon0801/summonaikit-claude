# Task 7.2 — Medir el contrato de SALIDA de Grok Build (plan, tras 7.1)

`[Test]` `[lane:gate]` `[tdd:required]`.
**DoD íntegra en `Plans.md` (fila 7.2):** (1) las **4 formas** que el hook emite
hoy (`additionalContext`, `decision:block`, `continue:false`+`stopReason`,
`systemMessage`) y `exit 2` en `Stop` tienen veredicto vivo distinguible
(aceptada / rechazada / ignorada) en Grok Build 1.0.3; (2) se mide que el Stop
de cierre (`reason=shutdown`) ignora la decisión sin mutar estado; (3) el
resultado fija `TARGET`/budget de Grok, declarado con su evidencia. Si ninguna
forma bloquea de manera fiable, 7.3–7.6 no arrancan. **Depende de:** 7.1
(cerrada 2026-08-13, `docs/task-7.1-captura.md`).

> **Esto NO implementa el gate en Grok ni toca el hook de producto.** Es la
> medición que decide si 7.3–7.6 son "el mismo hook + otro registro" o hace
> falta una forma de salida propia. Si `decision:block` y `exit 2` no mueven
> el Stop, el gate es decorativo en Grok y la Phase 7 se re-planifica **antes**
> de cablear `install-hook.sh --host grok`.

## Cross-review del PLAN con Codex (1 ronda, 2026-08-13) — tope cumplido

Tope: 1 ronda; una 2ª solo si hay severidad alta residual. Los 6 hallazgos se
evaluaron uno a uno y los 6 eran legítimos; quedaron incorporados en el cuerpo
(las notas "hallazgo N del cross-review" marcan dónde). **No hay 2ª ronda.**

1. **[alta] ACEPTADO** — El plan corría el probe desde
   `C:\dev\summonaikit-claude` (master), que no tiene `--host grok` hasta el
   merge; correrlo desde ahí instalaba la versión vieja o tocaba el
   user-config de zcode. Fix: el probe se ejecuta desde el checkout de la 7.2
   (`<CO>`), declarado en §A3 y §E4.
2. **[media] ACEPTADO** — `block0`/`exit2` emitían en cada Stop sin tope: un
   block aceptado re-bloquea la continuación y el turno repite hasta el límite
   interno de Grok (8), ensuciando la observación del `shutdown`. Fix: una
   sola emisión de bloqueo por ronda (§A1), y el conteo estructural de la DoD
   se ajusta a "exactamente 2 `end_turn`" (§B).
3. **[media] ACEPTADO** — El restore del trust por `cp` de backup podía pisar
   un cambio concurrente del operador y una interrupción dejaba el repo
   confiado. Fix: restore quirúrgico (se quita solo la entrada agregada; si
   el archivo difiere en algo más, se para y se reporta) en §A3/§E4.
4. **[media] ACEPTADO** — El `command` PowerShell interpolaba rutas en
   comillas dobles sin validación: una ruta con `"`, backtick o `$()` ejecuta
   expresiones. Fix: el instalador rechaza esas rutas (exit 2, fail-closed)
   en §A1.
5. **[media] ACEPTADO** — Declarar `ignored` por nonce ausente asumía que
   Grok persiste el `additionalContext` en los archivos de sesión. Fix: el
   oráculo se valida antes de declarar `ignored`; si no se puede confirmar
   que un contexto aceptado deja huella, la forma queda `unknown` (§B).
6. **[baja] ACEPTADO** — El diseño seguía diciendo `/hooks-trust` en los
   párrafos de staging pese a la evidencia de 7.1. Fix: `docs/phase-7-grok-
   design.md` actualizado (el trust se materializa como entrada en
   `trusted_folders.toml`; `/hooks-trust` en TUI escribe exactamente eso).

Nota de proceso: la primera invocación se colgó a los 300 s (diff de ~65k
caracteres, razonamiento alto) y el tope se subió a 900 s. La revisión corrió
con `gpt-5.6-sol`, 104k tokens.

## Lo que la 7.1 ya midió (no se re-litiga)

De `docs/task-7.1-captura.md` y el diseño actualizado
(`docs/phase-7-grok-design.md` § Medición primero):

1. **Los hooks de proyecto corren en headless** (`grok -p`) con el repo en
   `~/.grok/trusted_folders.toml`. No hace falta operador en la TUI — a
   diferencia de la 5.2, no hay tarjetas STOP ni turnos manuales.
2. **No existe flag `--trust`** en 1.0.3 y `GROK_FOLDER_TRUST=0` no carga
   hooks (`hook_count=0`). El trust se hace editando `trusted_folders.toml`
   (backup + restore byte a byte; único estado global permitido).
3. **El shell de hooks en Windows es `powershell.exe`.** El `command` del JSON
   se emite como `& "<bash.exe>" "<probe>"`; la forma estilo zcode
   (`"exe" "script"`) muere con exit 1.
4. El envelope tiene claves camel y **valores snake**: `hookEventName` vale
   `user_prompt_submit` / `stop`. El probe matchea esos literales, no
   `UserPromptSubmit`/`Stop`.
5. Cada turno headless dispara **dos** Stops: `reason=end_turn` (con
   `promptId`, `lastAssistantMessage`) y `reason=shutdown` al salir (sin
   `promptId`). La medición (2) de la DoD se hace en el mismo turno.
6. Los transcripts viven en `~/.grok/sessions/<cwd-encoded>/<uuid>/`
   (`updates.jsonl`, `chat_history.jsonl`) — oráculo para buscar el nonce de
   `additionalContext`, junto al `--debug-file` del proceso.
7. El loader tolera una clave top-level de marcado en el JSON de hooks
   (`saikit_owned` o equivalente): el de captura la llevaba y disparó 37
   veces.

## Qué cambia y qué NO

**NO cambia:**
- `hooks/summonaikit-harness.sh` (el hook de producto).
- Nada bajo `~/.grok/` salvo `trusted_folders.toml` (backup + restore) durante
  la medición. `~/.grok/hooks/`, `config.toml`, `agents/` quedan byte a byte.
- El modo zcode del probe: comportamiento byte a byte igual (regresión).
- 7.3–7.6. La decisión de formas de salida **se declara**; no se implementa.

**Cambia:**
- `tools/probe-zcode-output.sh`: gana `--host grok` (default `zcode`, el
  comportamiento actual no se mueve).
- `tests/test_probe_zcode_output.sh`: casos grok nuevos.
- `docs/task-7.2-salida.md` (veredictos, sin crudos de turno).
- Spec § Phase 7 y `Plans.md` fila 7.2, al cerrar.

---

## A) El probe gana `--host grok` (TDD)

`[tdd:required]` aplica al probe, no al acto de correr grok. Rojo/verde sobre
`tests/test_probe_zcode_output.sh` en su sandbox (env de `tests/run.sh`:
`HOME`, `USERPROFILE`, `TMPDIR`, `SAIKIT_HOOK_VIVO` apuntando al hook fuente
del checkout de trabajo), **no** sobre `tests/run.sh`.

### A1. Contrato nuevo

```
# flags nuevos:
#   --host zcode|grok     (default zcode; valor inválido => exit 2)
#
# MODO HOOK con --host grok (lo pone --instalar en el command del JSON):
#   - el evento se lee de hookEventName (camel) y el VALOR es snake:
#     los modos UPS (context/extra) disparan sobre "user_prompt_submit";
#     los modos Stop (block0/budget/notice/exit2) disparan sobre "stop"
#   - el side-channel <nonce>.ok agrega una línea reason=<valor del campo
#     "reason" del payload, o "none"> — es la evidencia de la DoD (2)
#   - en "stop" con reason=end_turn emite la forma UNA SOLA VEZ por ronda:
#     si probe-ran/ ya tiene un .ok con reason=end_turn para el modo actual,
#     sale en silencio (exit 0). Sin este tope, un block aceptado vuelve a
#     bloquear el Stop de la continuación y el turno repite hasta el limite
#     interno de Grok (8 continuaciones) — se queman tokens y se ensucia la
#     observacion del shutdown (hallazgo 2 del cross-review con Codex)
#   - en "stop" con reason=shutdown emite SIEMPRE (el proceso ya esta
#     saliendo; que la decision se emita y se ignore es lo que se mide)
#
# --instalar <repo> --host grok:
#   - escribe <repo>/.grok/hooks/saikit-probe.json (archivo PROPIO, no append
#     a config ajeno) con UserPromptSubmit + Stop (sin matcher), un handler
#     por evento:
#       { "type": "command",
#         "command": "& \"<bash.exe>\" \"<probe>\" --saikit-probe-id 7.2 --host grok --only-cwd \"<dest>\" --mode-file \"<dest>/probe-mode.txt\"",
#         "timeout": 30 }
#   - el JSON lleva marca top-level "saikit_probe": "7.2"
#   - marca de propiedad <repo>/.grok/.probe-grok-owned (mismo patrón que la
#     marca .grok del capturador de 7.1)
#   - <bash.exe> sale de zcode_bash_win (ya existe en el script; reusarla,
#     no duplicarla)
#   - el command es un string de PowerShell con comillas dobles: el
#     instalador RECHAZA (exit 2, fail-closed) cualquier ruta (bash.exe,
#     probe, dest) que contenga `"`, backtick o `$` — son metacaracteres de
#     PowerShell y una ruta así ejecutaría expresiones al dispararse el hook
#     (hallazgo 4 del cross-review). Las rutas reales de esta máquina no los
#     tienen; si aparecen, se declara y se pasa a comillas simples medidas
#   - idempotente: si el JSON ya es nuestro y byte-igual, no-op; si existe y
#     es ajeno => exit 2, no se pisa
#   - guard: destino que resuelve a $HOME/.grok* => exit 2
#
# --quitar <repo> --host grok:
#   - borra saikit-probe.json SOLO si es nuestro (marca + probe-id), y la
#     marca; no toca saikit-capture.json ni nada ajeno
```

Los 7 modos (`context`, `extra`, `block0`, `budget`, `notice`, `exit2`,
`empty`) y sus salidas byte a byte **no cambian**: son las formas del hook
vivo y la DoD mide exactamente esas. La tabla de eventos por modo se vuelve
host-aware:

| mode | zcode (hoy) | grok |
|---|---|---|
| `context`, `extra` | `UserPromptSubmit` | `user_prompt_submit` |
| `block0`, `budget`, `notice`, `exit2` | `Stop` | `stop` |
| `empty` | siempre corre, nunca emite | igual |

### A2. Tests (rojo primero)

Casos nuevos en `tests/test_probe_zcode_output.sh` (sección grok):

1. Cada modo, con el literal snake correcto en `hookEventName`: stdout exacto
   + exit exacto (reusa los payloads camel de los tests zcode cambiando el
   valor del evento).
2. Modo Stop (`block0`, `exit2`) con evento `user_prompt_submit` ⇒ exit 0,
   vacío, sin `.ok`. Modo UPS (`context`) con evento `stop` ⇒ igual.
3. `block0` con `stop` + `"reason":"shutdown"` en el payload ⇒ emite la forma
   (exit 0, JSON block) y el `.ok` registra `reason=shutdown`.
3b. Tope de una emisión por ronda (hallazgo 2 del cross-review): `block0` con
   `stop` + `reason=end_turn` emite; una segunda invocación igual (con el
   `.ok` de la primera ya en `probe-ran/`) ⇒ exit 0, **stdout vacío**, y el
   segundo `.ok` igual se escribe (la visita se registra; el bloqueo no se
   repite).
4. `--host grok --instalar` en sandbox ⇒ `saikit-probe.json` parseable por
   `jq`, 2 eventos sin matcher, todo `command` empieza con `& "` y nombra un
   `bash.exe`, marca top-level presente, marca de propiedad creada.
5. Segunda `--instalar` ⇒ no-op (cksum idéntico). JSON ajeno preexistente ⇒
   exit 2 y cksum intacto.
6. Destino `$HOME/.grok` del sandbox ⇒ exit 2, no escribe.
7. `--quitar` ⇒ saca el JSON propio y la marca; un `saikit-capture.json`
   vecino (del capturador 7.1) sobrevive.
8. `--host` sin valor / con valor inventado ⇒ exit 2.
9. Regresión: la sección zcode corre sin tocar (verde tal cual).
10. `bash -n` sobre el script.

Verde ⇒ commit 1 (§G).

### A3. Preparación del descartable (después del commit 1)

El repo `C:\dev\saikit-captura-grok` ya existe (7.1). **El probe se ejecuta
desde el checkout donde se implementó este cambio** (el worktree/rama de la
7.2), NO desde `C:\dev\summonaikit-claude`: el master checkout no tiene
`--host grok` hasta que este trabajo mergee, y correrlo desde ahí instalaría
la versión vieja — o peor, tocaría el user-config de zcode (hallazgo 1 del
cross-review). En los comandos de abajo, `<CO>` = ese checkout.

Secuencia:

```bash
cd /c/dev/saikit-captura-grok
# 1) cksums del perfil ANTES (van al writeup):
cksum ~/.grok/trusted_folders.toml ~/.grok/config.toml ~/.grok/hooks/* ~/.grok/agents/*
# 2) instalar el probe:
bash <CO>/tools/probe-zcode-output.sh --instalar . --host grok
# 3) trust: backup + entrada del repo en trusted_folders.toml
cp ~/.grok/trusted_folders.toml trusted_folders.toml.bak-7.2
#    agregar la ruta del repo en el formato que ya tenga el archivo
#    (leerlo primero; replicar la forma de las entradas existentes).
#    Se agrega UNA línea/entrada identificable: el restore la saca a ella,
#    no pisa el archivo entero (hallazgo 3 del cross-review)
# 4) verificar que grok ve el hook:
grok inspect 2>&1 | grep -i -A2 hook   # hook_count >= 1, Project trusted: yes
```

Si `grok inspect` no muestra el hook, PARAR: no se mide nada hasta que el
registro cargue (lección 6.1: un registro que no corre vuelve todo `unknown`).

---

## B) Cómo se distingue aceptada / rechazada / ignorada

Tres oráculos, en este orden. `not_observed != absent`.

1. **¿Corrió?** `probe-ran/<nonce>.ok`. Sin ese archivo ⇒ `unknown`. A
   diferencia de zcode, Grok **sí** logea hooks: el `--debug-file` muestra el
   run del hook y su exit (7.1 lo usó). Ambos se citan.
2. **Nonce de `context`/`extra`/`notice`:** el oráculo tiene dos niveles y
   hay que **validarlo antes de declarar `ignored`** (hallazgo 5 del
   cross-review: que el nonce no aparezca en los archivos de sesión solo
   prueba `ignored` si esos archivos efectivamente persisten el contexto
   aceptado). Jerarquía:
   - Nonce `PROBE-<mode>-<nonce>` hallado en el `updates.jsonl` /
     `chat_history.jsonl` de la sesión del turno (el `<uuid>` más nuevo bajo
     `~/.grok/sessions/<cwd-encoded>/`) ⇒ `accepted`.
   - El `--debug-file` registra si la salida del hook se aplicó o se rechazó
     por esquema (7.1 mostró que los hook runs quedan logeados): aplicada ⇒
     `accepted`; rechazo de esquema ⇒ `rejected`.
   - `.ok` existe y **ninguno** de los dos niveles muestra el nonce ⇒
     `ignored`, declarando la limitación del oráculo. Si tampoco se pudo
     confirmar que un contexto aceptado deja huella en alguno de los dos
     niveles, la forma queda `unknown` — no se finge `ignored`.
3. **Stop (señal estructural, medida gratis):** en headless cada turno cierra
   con Stop `end_turn` + Stop `shutdown`. Si la decisión sobre `end_turn`
   **continúa el turno** (decision:block aceptada), el modelo hace otra
   pasada ⇒ aparece **otro par** de Stops ⇒ el `.ok` cuenta los `end_turn`:
   - `empty`: exactamente 1 `end_turn` + 1 `shutdown`.
   - `block0`/`exit2` aceptada: **exactamente 2** `end_turn` — el probe
     bloquea una sola vez por ronda (§A1), la continuación cierra limpio y el
     texto del turno muestra la pasada extra. **3+ `end_turn` = el tope de
     una emisión falló**: bug del probe, no un veredicto.
   - `block0`/`exit2` ignorada: igual que `empty`.
   - `budget` aceptada (force-stop): el turno corta donde `block0` siguió.
   - `budget` = `empty` ⇒ **`ignored`** (la DoD no admite `indistinguishable`).
   - `shutdown`: el `.ok` con `reason=shutdown` existe (la decisión se emitió)
     y el proceso salió limpio (exit 0, sin segundo ciclo, sin error en el
     debug log) ⇒ la decisión sobre el cierre es **ignorada sin mutar
     estado** — DoD (2). Si Grok errora o re-trabaja sobre `shutdown`, la 7.3
     tiene que filtrar por `reason` antes de emitir (ya diseñado en D6).

`rejected` ≠ `ignored` ≠ `unknown`. No se rellena la tabla con la guía.

---

## C) Rondas de medición (headless, un modo por turno)

Orden (Stop primero; `budget` **después** de `exit2`/`block0`, como 5.2):

```bash
cd /c/dev/saikit-captura-grok
# por cada modo M en: empty exit2 block0 budget context extra notice
printf '%s\n' "$M" > probe-mode.txt
grok -p "Crea el archivo probe-$M.txt con el texto $M y termina." \
  --always-approve --debug-file "debug-7.2-$M.log"
# tras cada turno: cosechar probe-ran/ (renombrar a probe-ran/$M-*.ok),
# anotar exit code del proceso y si el output muestra continuación
```

Notas:
- Para modos Stop el turno tiene que LLEGAR a Stop (que el modelo complete su
  tarea y termine). El prompt de arriba alcanza.
- Un modo que sale `unknown` no se rellena: se mira el debug log, se
  corrige el registro si hace falta, sesión nueva.
- Económico: 7 turnos, uno por modo. Si `block0` continúa el turno, esa
  continuación también dispara el probe — esperado, se anota.

---

## D) Decisión de formas de salida para Grok

Se escribe en `docs/task-7.2-salida.md`, no se implementa (7.3/7.4 la
consumen).

| Evidencia | Decisión |
|---|---|
| `context` accepted **y** (`block0` **o** `exit2`) continúa el Stop | El vocabulario Claude sirve entero. `TARGET=grok` sin forma propia. |
| `block0` accepted **y** `exit2` ignored | Grok parsea el JSON con exit 0 pero no el exit 2: la forma de bloqueo en target grok emite el JSON **sin** exit 2. `TARGET=grok` con forma propia (análogo al budget zcode de 5.4). |
| `exit2` accepted **y** `block0` rejected | El esquema rechaza el JSON pelado: el vivo se apoya en exit 2 + stderr. `TARGET=grok`, forma exit-2. |
| `block0` **y** `exit2` ambas ignored/rejected | **Gate decorativo.** Re-planificar una salida propia o cancelar el host. 7.3–7.6 no arrancan. |
| `context` rejected | La inyección de contrato no entra: el armado necesita otro canal. Re-planificar 7.3 antes de seguir. |
| `context` ignored (`.ok` sí, nonce no) y Stop sí mueve | El contrato no llega: no se cierra como "alcanza". Re-planificar el armado. |
| `budget` = `ignored` (igual que `empty`) | DoD cumplida: ignorada. El budget de Grok usa la forma de bloqueo medida. No bloquea. |
| `extra` = `accepted` | Esquema **no** estricto (margen para claves propias). |
| `extra` = `rejected` | Esquema estricto: el JSON canónico de 7.5 no puede llevar claves extra más allá de `saikit_owned` (tolerada, 7.1). |
| `notice` = `ignored` | Review-notice fail-open. No bloquea 7.3–7.6. |
| La decisión sobre `shutdown` muta estado o errora | D6 se endurece: la 7.3 filtra `reason` **antes de emitir**, no sólo antes de gatear. |
| Cualquier forma de la DoD en `unknown` | No se decide. 7.2 no cierra. |

La decisión es **una frase + la tabla**. Sin "probablemente".

---

## E) Entregables

### E1. `docs/task-7.2-salida.md`

Tabla de los 7 modos + la fila `shutdown` con veredicto, señal (`.ok` /
debug log / transcript) y cita de una línea **redactada**. Cero payloads,
cero prompts, cero rutas de perfil completas. La decisión de formas al final.

### E2. Spec § Phase 7

Un párrafo "Medido …, Task 7.2" con los veredictos de las 4 formas + exit 2 +
shutdown, al estilo del párrafo 7.1.

### E3. `Plans.md` fila 7.2

`cc:完了 [<sha>]` **solo si** las 4 formas + `exit2` tienen
accepted/rejected/ignored (no `unknown`) y la fila `shutdown` tiene su
veredicto.

### E4. Limpieza

```bash
bash <CO>/tools/probe-zcode-output.sh --quitar /c/dev/saikit-captura-grok --host grok
# restore QUIRURGICO del trust (hallazgo 3 del cross-review): se quita SOLO
# la entrada que agregamos en A3; NO se pisa el archivo con el backup, porque
# un cambio concurrente del operador se perderia. OJO (corregido 2026-08-14,
# leccion de la medicion real): la entrada son TRES lineas (header + trusted +
# decided_at); un `grep -v` del header solo deja las otras dos HUESPEDAS de la
# seccion anterior y rompe el TOML. La forma segura: restaurar el backup SOLO
# si el diff contra el archivo actual es exactamente nuestra entrada; si el
# archivo difiere en algo mas, se para y se reporta.
diff trusted_folders.toml.bak-7.2 ~/.grok/trusted_folders.toml   # == solo nuestra entrada
cp trusted_folders.toml.bak-7.2 ~/.grok/trusted_folders.toml
cksum ~/.grok/trusted_folders.toml   # == al cksum ANTES de A3
grok inspect  # Project trusted: no (o el valor previo)
```

Cksums finales de `~/.grok/hooks/*`, `config.toml`, `agents/*`: idénticos a
los de A3. Van al writeup.

---

## F) Commits

1. `feat(7.2): probe --host grok para medir el contrato de salida` — probe +
   tests (verde en sandbox) + `--instalar/--quitar`.
2. Rondas de medición (§C). Sin commit.
3. `docs(7.2): veredictos del contrato de salida de Grok`.
4. `docs(7.2): cerrar Task 7.2 en Plans.md` — solo si E3 aplica.

TDD: `bash tests/test_probe_zcode_output.sh` en sandbox.
Gate final del commit 1: `pre-commit run --all-files` + `tests/run.sh`.
Nunca `--no-verify`.

---

## Límites

1. No se toca el hook de producto.
2. `~/.grok`: solo `trusted_folders.toml` durante la medición, con backup y
   restore byte a byte verificado por cksum.
3. No se instala el harness global (eso es 7.6).
4. No se implementa la decisión de formas (eso es 7.3/7.4).
5. El repo descartable no se commitea; los debug logs y `.ok` quedan ahí.
6. El gate sigue **advisory**.
7. `grok -p` headless ≠ TUI: si una forma se comporta distinto en TUI, queda
   `unknown` para TUI y se declara — no se extrapola.
