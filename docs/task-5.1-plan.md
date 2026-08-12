# Task 5.1 — Capturar payloads reales de zcode (plan para que GLM implemente)

`[Test]` `[lane:gate]` `[tdd:skip:captura-manual-con-persona-adelante]`.
**DoD íntegra en `Plans.md:97`:** (1) payloads crudos de las 3 fases
(`UserPromptSubmit`, `PostToolUse`, `Stop`) de un turno `-saikit` real de
**zcode**, en un repo descartable; (2) queda escrito el **diff de forma contra
los payloads de Claude** (campos presentes/ausentes, anidamiento); (3) se
declara **cómo se llama la herramienta de subagentes y en qué campo viaja el
rol** (`tool_input.subagent_type` vs `agent_type` de primer nivel); (4) se mide
si el alias `Task` ↔ `Agent` del matcher hace que los eventos de delegación SÍ
lleguen (la mitad de A9 que en Claude no llega nunca); (5) si la captura
contradice alguna premisa del spec, se re-redacta la Phase 5 **antes de escribir
una línea de hook**. **Depende de:** 2.4.

> **Esto NO es implementar el gate en zcode.** Es la lección de la Task 1.4:
> payloads reconstruidos con la forma correcta escondían A9, A10 y A11. Acá se
> mide. 5.2–5.5 esperan esta medición. Si las premisas caen, la fase se
> re-planifica como port propio (estilo `summonaikit-kimi`), no se parchea a
> ciegas.

## Cross-review del PLAN con Codex (2 rondas, 2026-08-12) — tope cumplido

Tope quality-kit: máx 1 ronda, 2ª sólo con severidad alta, **jamás una 3ª**.
Ronda 1: 1 alta + 4 medias, todas aceptadas (cuerpo de abajo). Ronda 2 (esta):
2 altas + 3 medias + 2 bajas, todas aceptadas e incorporadas. **No hay 3ª.**
Residuales de la 2ª: ninguno dejado sin fix o sin declaración.

### Ronda 2 (sobre el texto post-ronda-1)

1. **[alta] ACEPTADO+verificado** — `grep '^(…|ZCODE|CLAUDE_)'` vuelca
   `ZCODE_API_KEY`, `ZCODE_CREDENTIAL_SECRET`,
   `ZCODE_CUA_PERMISSION_BROKER_TOKEN` (nombres en el bundle 3.7.5-11).
   **Fix:** allowlist cerrada, sin prefijo `ZCODE`/`CLAUDE_`.
2. **[alta] ACEPTADO** — el bak del user-config no va adentro de un repo
   git (`<repo>/.zcode/user-config.bak`). Hoy el vivo no trae apiKey, pero
   es config de usuario. **Fix:** backup en
   `$HOME/.zcode/cli/saikit-backups/` (o hermano del user-config de
   sandbox), fuera del dest git. `<repo>/.zcode/` se ignora igual.
3. **[media] ACEPTADO** — no identificar lo nuestro solo por
   `capture-payloads.sh`. Marker `--saikit-capture-id 5.1`. Install
   completo = las 4 entradas con ese id. `--quitar` solo borra esas.
4. **[media] ACEPTADO** — el dummy de test incluye un `Stop` ajeno (el
   vivo ya tiene uno: tokentracker). Append/quitar no lo tocan.
5. **[media] ACEPTADO** — jamás persistir `command -v bash` (`/usr/bin/bash`
   en MSYS → ENOENT en Node). Ruta Windows que exista como archivo:
   `C:/Program Files/Git/bin/bash.exe`.
6. **[baja] ACEPTADO** — bloque B solo Git Bash.
7. **[baja] ACEPTADO** — TDD con `--files`; gate final del commit 1:
   `pre-commit run --all-files`.

### Ronda 1 (resumen; ya en el cuerpo)

1. **[alta] ACEPTADO+verificado** — En `zcode-app-cli` **3.7.5-11** (el que corre
   acá: `vendor/zcode.cjs`), `normalizeProjectConfig` (`gri`) **saca** la clave
   `hooks` de `<repo>/.zcode/config.json` / `zcode.json` y emite
   `config_project_hooks_ignored` ("Project hooks were ignored by the security
   policy"). Un `--instalar` que solo escriba el override de workspace **nunca
   dispara**. Las docs de zcode.z.ai y la skill `diagnosing-hooks` están
   desfasadas respecto de este CLI. **Fix:** registrar en el config **de
   usuario** `~/.zcode/cli/config.json` (append quirúrgico + backup +
   `--quitar` que saca solo nuestras entradas) y el capturador no escribe si
   el cwd físico no es el repo descartable. Tests contra un
   `SAIKIT_ZCODE_USER_CONFIG` de sandbox, **nunca** contra el HOME real.
2. **[media] ACEPTADO** — `^(…|ZCODE|CLAUDE_|TERM)=` no matchea
   `ZCODE_PROJECT_DIR` ni `CLAUDE_PROJECT_DIR`. Grep sin el `=` pegado al
   nombre corto: `^(SUMMONAIKIT|PWD|CLAUDECODE|ZCODE|CLAUDE_|TERM)`.
3. **[media] ACEPTADO** — Matcher `Task` solo no distingue "alias roto" de
   "no se emitió el evento". Tercer bloque PostToolUse con matcher `Agent` y
   `--tag` distinto. Veredicto del alias según qué tag llegó.
4. **[media] ACEPTADO** — `find|wc -l` + write no es atómico (1.5 lo dejó
   declarado). En 5.1 dos tools del mismo turno pueden pisarse. Reserva con
   `mktemp` en el modo hook.
5. **[media] ACEPTADO** — No se marca `cc:完了` si falta una de las 3 fases.
   Medición incompleta ≠ DoD cumplida. Plans.md se queda en TODO o se declara
   fallo de medición; no se cierra.

**Veredicto sobre el draft: REQUEST_CHANGES.** Ejecutar el texto de abajo.

## A quién le toca qué (leer antes de tocar nada)

| Quién | Qué puede hacer | Qué NO puede |
|---|---|---|
| **GLM (implementer)** | Extender `capture-payloads.sh` + tests; preparar el repo descartable; cosechar; escribir el diff; actualizar spec/Plans | Abrir zcode, escribir el prompt, delegar. Claude Code / `glm` **no cuentan**. |
| **Operador (Gon)** | El STOP: sesión **nueva** de **zcode** (no `glm`) en el repo descartable, un turno `-saikit` que **delegue** | Inventar payloads, reconstruir JSON, commitear `capturas/` |

`glm` (launcher) es `exec claude` contra Z.ai: **ya está gateado hoy** por este
hook (spec:1079–1087). **5.1 es el CLI `zcode`**, paquete `zcode-app-cli`,
config `~/.zcode/cli/config.json`. Confundirlos invalida la medición.

Hay un **STOP obligatorio** (§D). GLM no lo salta ni simula la sesión.

## Premisas medidas (2026-08-10, spec § El segundo host) — no re-medir el bundle

Verificadas leyendo `~/.zcode/cli/config.json` **y** la guía
`zcode-guide-plugin/skills/diagnosing-hooks` (re-leídas 2026-08-12 para este
plan). Siguen en pie salvo que la captura las tumbe:

1. Hooks con el mismo vocabulario. Wrapper distinto:
   `hooks.events.<Evento>[]` vs `hooks.<Evento>[]` de Claude. El array interno
   es idéntico.
2. Los 3 eventos que este hook necesita existen. No hay `SubagentStop`.
3. Workspace override `<repo>/.zcode/config.json`: **la guía y zcode.z.ai lo
   documentan; este CLI (3.7.5-11) lo ignora** (hallazgo 1). No usarlo como
   canal de captura.
4. Matcher `Task` ↔ `Agent` (case-sensitive). En Claude el matcher dice `Task`
   y la herramienta se llama `Agent` ⇒ esos eventos no llegan. **Medirlo es
   esta task.**
5. Matcher de `UserPromptSubmit` = texto del prompt; de `Stop` = vista previa
   de la respuesta. Un matcher copiado de Claude no matchearía. **Omitir
   matcher** en esas dos fases.
6. Hooks de archivo no corren sin `hooks.enabled: true` (hoy el global lo
   tiene). El override del workspace **también** tiene que llevarlo.
7. `timeout` de un hook `command` va en **segundos**. `type: process` usa
   `timeoutMs`.
8. **No medido (por eso esta task):** forma anidada real del payload, y en qué
   campo viaja el rol.

## Distinción que rige el diseño de la captura

La captura y el gate ven **poblaciones distintas** (lección de 3.7, no
repetir):

- Si registrás matcher `"*"`, ves **todo**. Eso no prueba el alias.
- El alias se prueba con **dos** bloques PostToolUse, cada uno con `--tag`
  propio: matcher **`Task`** (`--tag task`) y matcher **`Agent`** (`--tag
  agent`). Si llega `tool_name=Agent` con tag `task` ⇒ el alias funciona. Si
  solo llega con tag `agent` ⇒ el evento existe y el alias no lo transporta.
  Si no llega ninguno ⇒ el evento no se emitió (o el operador no delegó) —
  **unknown**, no "el alias no funciona".
- Para tener forma de `PostToolUse` que no sea delegación (Bash/Write/…), un
  tercer bloque con matcher `Bash|Edit|Write|Read` (`--tag tools`). Esos
  nombres **no** matchean `Agent`/`Task`.

No registrar el harness real en esta sesión. Solo el capturador. Mezclarlos
ensucia estado (justo lo que 5.3 cierra) y confunde poblaciones.

## Qué cambia y qué NO

**NO cambia:**
- `hooks/summonaikit-harness.sh` (ni una línea).
- Los hooks **ajenos** del global (`SessionStart` de quality-kit, RTK,
  tokentracker). Se **appendean** entradas nuestras; no se reescribe el
  archivo entero.
- `~/.claude/**`.
- La forma Claude de `--instalar` (sin `--host`): regresión cero.
- 5.2–5.5. 5.2 **se puede** medir en la misma sesión; no se hace en esta task.
  Dejá el repo descartable vivo si el operador quiere seguir.

**Cambia (excepción declarada al "no tocar el global"):**
- `tools/capture-payloads.sh`: `--host zcode` **appendea** 3 eventos de
  captura en `~/.zcode/cli/config.json` (o `$SAIKIT_ZCODE_USER_CONFIG` en
  tests). El capturador no escribe si el cwd no es el repo descartable.
- `tests/test_capture_payloads.sh`: casos del host nuevo + los viejos siguen
  verdes. HOME/config de prueba en sandbox.
- `docs/task-5.1-captura.md` (el diff de forma; **sin payloads crudos**).
- `docs/spec/00-project-spec.md` § El segundo host: hechos medidos, o
  premisas tumbadas.
- `Plans.md:97` → `cc:完了` al cerrar.

**Nunca se commitea:** `C:\dev\saikit-captura-zcode/capturas/` (texto de un
turno real). La 3.7 borró `C:\dev\saikit-captura` por eso.

---

## A) Extender `tools/capture-payloads.sh` (GLM solo, TDD)

El modo hook (stdin → archivo) **ya sirve** para guardar JSON. Hay que
sumarle `--tag` / `--only-cwd` / `--capture-dir` y escritura atómica.
El cambio gordo es **dónde se registra** (user-config, no proyecto).

`[tdd:skip:captura-manual-…]` aplica al acto de capturar, no a este tool.
Calidad del repo: el comportamiento nuevo lleva su caso. Rojo/verde sobre
`tests/test_capture_payloads.sh`, no sobre `tests/run.sh`.

### A1. Contrato del flag

```
bash tools/capture-payloads.sh --instalar <repo>            # Claude (igual que hoy)
bash tools/capture-payloads.sh --instalar <repo> --host zcode
bash tools/capture-payloads.sh --cosechar <repo>
bash tools/capture-payloads.sh --quitar <repo>
```

- `--host` solo vale `zcode`. Otro valor ⇒ exit 2, no escribe.
- Default (sin `--host`) = Claude. No romper `tests/test_capture_payloads.sh`
  existente.
- Parsear `--host` **antes** de exigir el repo, y en cualquier orden
  (`--instalar X --host zcode` y `--host zcode --instalar X`). Un flag sin
  valor no puede colgar el `while` (lección 0.4: `shift 2` al final).

### A2. Filtro de perfil — el *repo destino* no puede ser el perfil

Hoy se niega `$HOME` y `$HOME/.claude*`. Sumar que el dest **repo** no
resuelva a `$HOME/.zcode*`. Comparar rutas físicas (`pwd -P`).

Eso **no** impide editar el user-config: esa ruta se toma de
`SAIKIT_ZCODE_USER_CONFIG` (default `$HOME/.zcode/cli/config.json`). En
tests se apunta a un archivo del sandbox. Core Rule 4: ningún caso de
`test_capture_payloads.sh` escribe el `~/.zcode` real.

### A3. Qué hace `--instalar --host zcode` (excepción declarada)

El override de proyecto **no corre** en este CLI. El canal que sí corre
es el user-config, que **ya tiene** `hooks.enabled: true`.

1. Repo dest: crea `<repo>/capturas/` + `capturas/.gitignore` (`*`) y
   `<repo>/.zcode/.capture-payloads-owned` (marca; adentro, la ruta del
   user-config que se parcheó y el cwd permitido).
2. User-config (`$SAIKIT_ZCODE_USER_CONFIG`):
   - Si no existe ⇒ exit 2, no crear uno de cero (el operador ya tiene
     uno; fabricarlo es otra clase de daño).
   - Backup fechado **fuera del dest git**, hermano del user-config:
     `<dir-del-user-config>/saikit-backups/config.<YYYYmmdd-HHMMSS>.bak`
     (en prod: `~/.zcode/cli/saikit-backups/`). `cmp` contra el origen.
     No se escribe `<repo>/.zcode/user-config.bak`.
   - **Append** (no replace) a `hooks.events.UserPromptSubmit`,
     `PostToolUse` y `Stop`. No tocar `SessionStart` / `PreToolUse` /
     lo demás.
   - Nuestras entradas llevan `--saikit-capture-id 5.1` en `args`.
     Si ya están las 4 ⇒ no duplicar, exit 0. Si hay menos de 4 ⇒
     completar las que falten (install no se da por bueno a medias).
3. `UserPromptSubmit` y `Stop`: **sin** matcher.
4. `PostToolUse`: **tres** entradas, cada una con `--tag` en `args`:

```
process  <bash-win>  <capturador> --saikit-capture-id 5.1 --only-cwd <dest> --capture-dir <dest>/capturas --tag ups
         (evento UserPromptSubmit; sin matcher)

process  <bash-win>  <capturador> --saikit-capture-id 5.1 --only-cwd <dest> --capture-dir <dest>/capturas --tag task
         matcher: Task

process  <bash-win>  <capturador> --saikit-capture-id 5.1 --only-cwd <dest> --capture-dir <dest>/capturas --tag agent
         matcher: Agent     ← control

process  <bash-win>  <capturador> --saikit-capture-id 5.1 --only-cwd <dest> --capture-dir <dest>/capturas --tag tools
         matcher: Bash|Edit|Write|Read
```

`<bash-win>` = `C:/Program Files/Git/bin/bash.exe` **si ese path existe
como archivo**. Si no, otro `.exe` de bash de Windows (`cygpath -w` de
un bash hallado, o abortar). **Nunca** persistir `/usr/bin/bash` ni la
salida cruda de `command -v bash` (MSYS; Node da ENOENT). `args[0]` =
`$capturador` con `pwd -P`. `timeoutMs`: 15000. `type: process`.

No pongas `SUMMONAIKIT_HOOK_TARGET=claude` en el comando.

### A4. `--quitar` y `--cosechar`

- `--quitar --host zcode` (o `--quitar` si la marca dice zcode): si
  existe la marca, **saca solo** las entradas con
  `--saikit-capture-id 5.1`. No borra un hook ajeno que mencione
  `capture-payloads.sh` sin ese id. SessionStart/RTK/tokentracker
  intactos. Borra la marca. El bak en `saikit-backups/` se deja (no
  se restaura a ciegas: el operador pudo editar el vivo). Si no hay
  marca ⇒ exit 2, no toca el user-config.
- `--cosechar`: `<repo>/capturas/*.json`. Host-agnóstico.

### A5. Modo hook: flags, cwd, env, atomicidad

El modo hook (stdin → archivo) parsea, **además** de nada, estos flags
(siguen siendo fail-open, exit 0):

- `--saikit-capture-id 5.1`: lo pone el instalador; el modo hook lo
  ignora (solo marca de propiedad en el user-config).
- `--only-cwd <dir>`: si `pwd -P` del proceso ≠ `pwd -P` de `<dir>`,
  **no escribe** (otras sesiones de zcode no filtran un turno).
- `--capture-dir <dir>`: equivale a `SAIKIT_CAPTURE_DIR`.
- `--tag <nombre>`: entra en el nombre del archivo (`mktemp`).

Atomicidad (hallazgo 4): **no** numerar con `find|wc -l` y escribir
ese path. Crear con `mktemp "$salida/XXXXXX-<evento>-<tag>.json"` (o
equivalente que no pise). El orden de cosecha es `sort` del nombre;
no hace falta secuencia densa.

Dump de env — **allowlist cerrada**, no prefijo `ZCODE`/`CLAUDE_`:

```
env | grep -E '^(PWD|TERM|CLAUDECODE|SUMMONAIKIT|ZCODE_PROJECT_DIR|ZCODE_SESSION_ID|CLAUDE_PROJECT_DIR|CLAUDE_SESSION_ID)='
```

Prohibido: `ZCODE_API_KEY`, `ZCODE_CREDENTIAL_SECRET`, `*_TOKEN`,
`*_SECRET`, `*_PASSWORD`. Si hace falta otra señal de host, se agrega
**por nombre** al allowlist, no por prefijo.

### A6. Tests — rojo primero, luego el flag

Archivo: `tests/test_capture_payloads.sh`. Correr solo ese archivo.
**Todos** los casos de `--host zcode` exportan
`SAIKIT_ZCODE_USER_CONFIG=$SANDBOX/zcode-home/.zcode/cli/config.json`
y fabrican ahí un config mínimo con `hooks.enabled: true`, un
`SessionStart` dummy **y un `Stop` dummy** (el vivo real ya tiene
tokentracker en Stop; el test tiene que ver esa clase de vecino).

1. `--instalar --host zcode` appendea UserPromptSubmit / PostToolUse /
   Stop en el **user-config de sandbox**. No escribe
   `.claude/settings.json`. No crea `<repo>/.zcode/config.json` (solo
   la marca). SessionStart dummy **y Stop dummy** sobreviven. El bak
   queda bajo el dir del user-config de sandbox, no bajo el dest repo.
2. UPS y Stop **sin** matcher. PostToolUse tiene `Task`, `Agent` y
   `Bash|Edit|Write|Read`, cada uno con `--tag` y
   `--saikit-capture-id 5.1`.
3. Cada entrada lleva `--only-cwd` apuntando al dest.
4. Dest repo = `$HOME/.zcode` (o que resuelva ahí) ⇒ exit ≠ 0.
5. Segunda `--instalar` no duplica (las 4 con el id ya están).
6. `--quitar` saca solo `--saikit-capture-id 5.1`; SessionStart dummy
   **y Stop dummy** quedan. Un Stop sandbox que mencione
   `capture-payloads.sh` **sin** el id no se borra.
7. `--host inventado` ⇒ exit 2.
8. **Regresión:** `--instalar` sin `--host` sigue escribiendo
   `.claude/settings.json` y no toca `SAIKIT_ZCODE_USER_CONFIG`.
9. Modo hook: `--only-cwd` de otro directorio ⇒ no crea archivo.
10. Modo hook: dos writes seguidos al mismo dir no se pisan
    (`mktemp`; ambos archivos existen y tienen contenido distinto).

Rojo medido contra el tool **actual** (los casos 1–7 fallan). Después el
mínimo cambio que los pone verdes. Los casos viejos (perfil, symlink,
fail-open del modo hook) no se tocan.

```
bash tests/test_capture_payloads.sh
```

Verde ⇒ commit:

```
feat(5.1): capture-payloads --host zcode appendea captura en el user-config
```

---

## B) Preparar el repo descartable (GLM solo, **todo en Git Bash**)

```bash
mkdir -p /c/dev/saikit-captura-zcode
cd /c/dev/saikit-captura-zcode
git init
printf '%s\n' '# saikit-captura-zcode' 'repo descartable Task 5.1 — no commitear capturas/ ni .zcode/' > README.md
printf '%s\n' 'capturas/' '.zcode/' > .gitignore
git add README.md .gitignore
git commit -m "chore: repo descartable para captura zcode (Task 5.1)"
bash /c/dev/summonaikit-claude/tools/capture-payloads.sh --instalar . --host zcode
```

Verificar a mano antes del STOP:

- Existe `<repo>/.zcode/.capture-payloads-owned` y `capturas/.gitignore`.
- `~/.zcode/cli/config.json` **sí cambió**, pero solo se **agregaron**
  entradas con `--saikit-capture-id 5.1`. SessionStart/RTK/tokentracker
  siguen. Guardá el `cksum` de esos bloques ajenos antes/después.
- `~/.claude/settings.json` no cambió.
- Hay backup en `~/.zcode/cli/saikit-backups/`, **no** en el dest git.

No registres el harness. No copies agentes.

---

## C) Tarjeta del operador (GLM la imprime; no la ejecuta)

```
STOP — esto lo hace Gon, no GLM.

1. Cerrá cualquier sesión de zcode que tenga abierto C:\dev\saikit-captura-zcode
   (zcode, como Claude, fotografía los hooks al arrancar — supuesto; tratarlo
   como cierto).
2. Abrí zcode (el CLI, NO el launcher `glm`) en C:\dev\saikit-captura-zcode.
3. Un solo prompt, con -saikit, que haga DOS cosas:
     a) delegar a un subagente (implementer / Agent / Task — el que zcode
        ofrezca; el nombre es justo lo que estamos midiendo)
     b) correr un comando bash trivial (p. ej. `echo saikit-5.1`)
   No hace falta que el gate bloquee. No hace falta recibo. Queremos eventos,
   no un turno "correcto".
4. Cuando el turno termine, avisale a GLM: "ya corrí el turno".
5. Si zcode no dispara hooks (cero archivos en capturas/), no inventes el
   turno. Avisá. Eso también es un resultado (unknown ≠ "el alias no funciona").
```

---

## D) STOP — persona adelante

GLM se detiene acá. No fabrica JSON. No usa fixtures de Claude como si
fueran de zcode. No abre `glm`.

Si el operador no puede ahora, el commit de §A queda. El resto espera.

---

## E) Cosechar y analizar (GLM, después del STOP)

```
bash /c/dev/summonaikit-claude/tools/capture-payloads.sh --cosechar C:/dev/saikit-captura-zcode
```

Mínimo aceptable para no declarar `unknown`:

- ≥1 `*UserPromptSubmit*.json`
- ≥1 `*PostToolUse*.json`
- ≥1 `*Stop*.json`

Si falta una fase: declarar **qué** faltó y **no** afirmar la DoD entera.
Revisar el log de zcode
(`~/.zcode/cli/log/zcode-YYYY-MM-DD.jsonl`) a ver si el hook corrió,
timeout, o matcher. No adivinar.

### E1. Análisis (correr en el descartable; no commitear la salida cruda)

```python
# tools no: script de un solo uso, stdout. No agregar al repo salvo que
# resulte reutilizable; si se agrega, que lea un dir y no hardcodee payloads.
import json, os, sys
from collections import Counter
d = sys.argv[1]
files = sorted(f for f in os.listdir(d) if f.endswith(".json"))
print("archivos", len(files))
eventos = Counter()
tools = Counter()
roles_top = Counter()
roles_input = Counter()
for name in files:
    p = os.path.join(d, name)
    try:
        data = json.loads(open(p, encoding="utf-8").read())
    except Exception as e:
        print("NO-JSON", name, e)
        continue
    ev = data.get("hook_event_name", "?")
    eventos[ev] += 1
    tn = data.get("tool_name")
    if tn:
        tools[tn] += 1
    if "agent_type" in data:
        roles_top[data.get("agent_type")] += 1
    ti = data.get("tool_input") or {}
    if isinstance(ti, dict) and "subagent_type" in ti:
        roles_input[ti.get("subagent_type")] += 1
    # claves de primer nivel
    print(name, "keys=", sorted(data.keys()), "tool=", tn)
print("eventos", dict(eventos))
print("tool_name", dict(tools))
print("agent_type top-level", dict(roles_top))
print("tool_input.subagent_type", dict(roles_input))
```

Comparar contra un fixture Claude de cada fase, p. ej.:

- `tests/fixtures/escenarios/05-turno-completo-recibo-plano/01.prompt.claude.json`
- `tests/fixtures/escenarios/05-turno-completo-recibo-plano/02.tool.claude.json`
- `tests/fixtures/escenarios/05-turno-completo-recibo-plano/07.stop.claude.json`

Tabla mínima del diff (va a `docs/task-5.1-captura.md`):

| Campo | Claude (fixture 05 / captura 1.4) | zcode (esta captura) |
|---|---|---|
| `hook_event_name` | sí | ? |
| `tool_name` en PostToolUse | sí (`Agent` / `Bash` / …) | ? |
| `tool_input.subagent_type` | sí, en eventos `Agent` | ? |
| `agent_type` top-level | sí, en eventos internos | ? |
| `transcript_path` | sí | ? |
| `session_id` | sí | ? |
| `cwd` (cómo escapan `\`) | `C:\\…` | ? |
| `last_assistant_message` en Stop | sí | ? |
| `tool_response.exitCode` en Bash | no (59/59) | ? |
| `prompt` forma | string | ? |
| env `CLAUDECODE` | `1` en Claude | ? |

### E2. Las dos preguntas que la DoD exige responder en prosa

1. **¿Cómo se llama la herramienta de subagentes y dónde va el rol?**
   Una de: `Agent`+`tool_input.subagent_type` / `Agent`+`agent_type` /
   `Task`+… / no se emitió el evento / unknown (no se pudo mirar).
2. **¿El alias `Task` ↔ `Agent` hace llegar la delegación?**
   - Archivo `*-task.json` con `tool_name=Agent` ⇒ **sí** (el matcher
     `Task` vio un `Agent`).
   - Solo `*-agent.json` con `tool_name=Agent` (y cero `*-task.json` de
     delegación) ⇒ el evento existe, el alias **no** lo transporta.
   - `*-task.json` con `tool_name=Task` ⇒ el host la nombra `Task`; el
     alias no hace falta.
   - Ni `task` ni `agent` y el operador **dice** que delegó ⇒ **unknown**
     (no se observó el evento; no se afirma "el alias no funciona").
   - El operador no delegó ⇒ **unknown**, repetir el turno.

`not_observed != absent`. Vacío en capturas no es "zcode no tiene
PostToolUse".

### E3. Si una premisa del spec cae

Antes de cualquier cambio al hook, reescribir en el spec (y en Plans.md
Phase 5 purpose) **qué cayó** y **qué implica**. Ejemplos:

- Payloads con forma distinta (prompt en bloques, sin `hook_event_name`) ⇒
  la fase deja de ser "el mismo hook sirve" y se re-planifica como port.
  (El override de proyecto **ya cayó** para este CLI; no es un hallazgo
  de la captura, está en este plan.)
- No hay evento de delegación en absoluto ⇒ la mitad de A9 no aplica; 5.4
  no puede copiar el matcher de Claude.
- `hooks.enabled` del workspace no basta y hay que tocar el global ⇒
  declararlo; no tocar el global en esta task.

No se escribe código de 5.3–5.5 en este cierre.

---

## F) Entregables en este repo (GLM)

### F1. `docs/task-5.1-captura.md`

Hechos medidos, la tabla de E1, las dos respuestas de E2, recuentos
(`N` archivos por evento, `tool_name` vistos). **Cero payloads crudos, cero
prompts, cero rutas de perfil del operador.** Si hace falta un ejemplo de
forma, un objeto con campos vacíos / redacted.

### F2. Spec `docs/spec/00-project-spec.md` § El segundo host

Agregar un bloque "Medido 2026-08-1X, Task 5.1" con las dos respuestas y
el veredicto: premisas en pie / cuál cayó. Sin diario de sesión.

### F3. `Plans.md:97` → `cc:完了 [<sha>]` **solo si hay 3 fases**

Si falta una fase, Plans.md se queda en TODO y el commit 3 no se hace.
El SHA es el commit de **este** repo donde vive el diff (F1+F2).
Convención 4.1: Status = commit de `summonaikit-claude`.

### F4. Limpieza

```
bash /c/dev/summonaikit-claude/tools/capture-payloads.sh --quitar C:/dev/saikit-captura-zcode
```

Las `capturas/` se **borran** al cerrar (mismo motivo que 3.7), **salvo**
que el operador pida dejarlas para medir 5.2 en la misma máquina. Si se
dejan: fuera de git, dueño-only (`umask 077` ya lo hace el capturador).

No se commitea `C:\dev\saikit-captura-zcode`.

---

## G) Orden de commits (este repo)

1. `feat(5.1): capture-payloads --host zcode appendea captura en el user-config`
   — §A + tests verdes (sandbox, no HOME real).
2. **STOP** (§D).
3. `docs(5.1): captura zcode — diff de forma y dueño del rol`
   — F1 + F2.
4. `docs(5.1): cerrar Task 5.1 en Plans.md`
   — F3. SHA del commit 3.

Candados: TDD sobre `tests/test_capture_payloads.sh` y
`pre-commit run --files` de lo tocado. Gate final del commit 1:
`pre-commit run --all-files` (nunca `--no-verify`) y `tests/run.sh`.
El commit 3 (docs) no mueve el hook; `run.sh` no es su gate.

---

## Límites declarados (no cerrados por esta task)

1. No se toca el hook.
2. El user-config de zcode **sí se toca**, solo para append/quitar las
   entradas de captura. Es la excepción del hallazgo 1, no un permiso
   para reescribir SessionStart/RTK/tokentracker.
3. No se mide el contrato de **salida** (5.2), ni el estado cross-host
   (5.3), ni el install permanente (5.4), ni la línea base (5.5).
4. Un turno sin delegación no responde la pregunta del alias: se repite,
   no se inventa.
5. El gate sigue **advisory**.
6. `glm` ≠ `zcode`. Esta task no habla del launcher.

## Cross-review del PLAN

Tope quality-kit cumplido (2 rondas; la 1ª tuvo alta). **No hay 3ª.**
Review de código: **sólo si el operador la pide**, al cerrar.

Residual declarado (no se re-revisa): `type: process` + `args[]` vs
`type: command` para stdin — se mide en la sesión del operador; si
process no recibe stdin, GLM cae a `command` con la ruta Windows de
bash (sin reabrir review).

---

## Receta de cierre (DoD)

Las 3 fases son **gate**. Si falta UserPromptSubmit **o** PostToolUse **o**
Stop: **no** se marca `cc:完了`. Se declara la medición incompleta (qué
faltó, qué dijo el log de zcode) y Plans.md se queda en TODO. No se
afirma la DoD a medias.

Si las 3 están:

1. Existen `*UserPromptSubmit*`, `*PostToolUse*`, `*Stop*` en el
   descartable.
2. `docs/task-5.1-captura.md` tiene la tabla de forma y las dos
   respuestas, sin crudos. El alias se decide por tags `task`/`agent`,
   no por "el operador dijo que delegó".
3. El spec nombra la fuente (Task 5.1) y no afirma lo no visto.
4. Phase 5 se re-redactó **solo si** una premisa cayó.
5. Tras `--quitar`: `grep -l 'saikit-capture-id 5.1' ~/.zcode/cli/config.json`
   ⇒ 0, y los hooks ajenos (SessionStart/RTK/Stop tokentracker) siguen.
6. `git -C C:/dev/summonaikit-claude status` no lista nada bajo
   `saikit-captura` ni `capturas/`.
