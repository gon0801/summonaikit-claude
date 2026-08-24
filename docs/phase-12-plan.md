# Phase 12 — Plan de implementación: ruteo de modelo y effort por rol

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development`
> (recommended) or `superpowers:executing-plans` to implement this plan
> task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** que cada rol de la ceremonia (`implementer`, `verifier`, `reviewer`)
corra en el modelo y el nivel de esfuerzo que le corresponde, en los cuatro
hosts que instalan perfiles, resolviendo el valor en tiempo de instalación.

**Architecture:** un router (`tools/model-routing.sh`) traduce
`rol → tier → (modelo, effort)` por host y es el ÚNICO lugar donde viven los IDs
de modelo. `tools/install-hook.sh` lo consume al escribir el frontmatter de cada
perfil. El hook (`hooks/summonaikit-harness.sh`) no se toca: el gate no puede
regresionar por esta fase.

**Tech Stack:** bash (`set -u`, sin `-e`), `awk`, `cmp`, `mktemp`, `sha256sum`.
Sin dependencias nuevas. Tests en bash contra `tests/lib/sandbox.sh`.

**Diseño aprobado:** `docs/phase-12-model-routing-design.md`. Cuando este plan y
el diseño difieran, gana el diseño.

Ubicación del archivo: `docs/` plano, como `docs/phase-9-10-plan.md` y el resto
de los planes de este repo. Se mantiene la decisión de la Phase 6: no se abre
`docs/superpowers/plans/`.

## Global Constraints

Todo lo de acá aplica a TODAS las tareas de este plan.

- **`set -u`, nunca `set -e`.** Es la convención de los 7 scripts de `tools/`.
  Consecuencia obligatoria: **una función que quiera abortar NO puede hacerlo con
  `exit` adentro de `$( )`.** Bajo `set -u` sin `-e`, `X="$(f)"` con `exit 2`
  adentro deja `X` vacío y el llamador sigue. Toda función de resolución
  **imprime por stdout y devuelve un código**; el llamador chequea el código
  explícito. Hay un test dedicado a esto (Task 12.4, caso 6).
- **Core Rule 2 — un valor no reconocido no es evidencia de nada.** Host, rol o
  tier desconocido ⇒ `exit 2` con mensaje a stderr. Nunca un default silencioso.
- **`not_observed != absent`.** Lo que no se pudo observar se declara como no
  observado. Una fila de host sin medir queda vacía; no se rellena por analogía
  con otro host.
- **Fila vacía ⇒ clave omitida ⇒ hereda del padre.** Nunca se escribe
  `model:` con valor vacío.
- **Los IDs de modelo viven SOLO en `tools/model-routing.sh`.** Ni el
  instalador, ni las plantillas de `agents/`, ni los tests fuera del test del
  router los nombran. Hay un candado que lo verifica (Task 12.4, caso 7).
- **El hook no se toca.** Ninguna tarea de este plan modifica
  `hooks/summonaikit-harness.sh`.
- **Candados de commit: JAMÁS `--no-verify`.** Si `pre-commit` falla, se arregla
  el problema real.
- **Rama desde `origin/<default>`.** `git fetch` primero, `git switch -c <rama>
  origin/master`. Antes del PR, `git log origin/master..HEAD` tiene que listar
  SOLO los commits de esa tarea.
- **La batería completa corre UNA vez por tarea, y en CI.** Se empuja la rama,
  se **abre el PR** y se lee el resultado. Local, rojo/verde SOLO sobre el
  archivo de test que se está tocando:
  `bash tests/test_model_routing.sh`, nunca `bash tests/run.sh`.
- **`SAIKIT_HOOK_VIVO`**: sin esa variable apuntando a la fuente, la suite mide
  el hook **instalado**, no el del repo. Ninguna tarea de este plan cambia el
  hook, así que no aplica — pero si una corrida local lo necesita, es
  `SAIKIT_HOOK_VIVO="$PWD/hooks/summonaikit-harness.sh"`.
- **Guard de fuga.** `tests/run.sh` exige que el árbol del repo quede idéntico
  después de cada test. Nada de escribir adentro del repo desde un test: todo va
  a `$SANDBOX`. **No edites el repo mientras corre la suite** (~10 min) o el
  guard reporta fuga falsa.
- **Perfiles vivos de otros hosts, intactos.** Toda medición corre sobre repo
  descartable, mide el perfil del host antes y después (`cksum`), y aborta si
  cambió.

---

## File Structure

| Archivo | Estado | Responsabilidad |
|---|---|---|
| `tools/model-routing.sh` | **crear** | `rol → tier → (modelo, effort)` por host. Único lugar con IDs de modelo. |
| `tests/test_model_routing.sh` | **crear** | Tabla completa, `exit 2` en desconocidos, candado de IDs, trampa de `set -u`. |
| `agents/vendor-manifest.sha256` | **crear** | Hashes de los perfiles del vendor que el instalador puede adoptar. |
| `tools/install-hook.sh` | modificar | `agente_traducido <host>`, comparación contra traducida, `--host claude`, `--host kimi`. |
| `tests/test_install_hook.sh` | modificar | Casos de traducción, inyección, y los tres estados de los dos hosts nuevos. |
| `docs/task-12.1-medicion.md` | **crear** | Medición zcode. |
| `docs/task-12.2-medicion.md` | **crear** | Medición grok. |
| `docs/task-12.3-medicion.md` | **crear** | Medición kimi. |
| `docs/spec/00-project-spec.md` | modificar | Delta de producto: posesión, ruteo, límites. |
| `Plans.md` | modificar | Ledger de la Phase 12. |
| `README.md` | modificar | `--host claude` / `--host kimi` en la tabla de instalación. |
| `agents/*.md` | **NO se tocan** | Siguen sin `model:`. El valor lo inyecta la instalación. |
| `hooks/summonaikit-harness.sh` | **NO se toca** | — |

---

## Task 12.1: Medición zcode — ¿honra `model:` y `effort:`?

`[Test]` `[lane:gate]` `[tdd:required]`

**Files:**
- Create: `docs/task-12.1-medicion.md`
- Read-only: `~/.zcode/cli/**` (el bundle `zcode.cjs`), `~/.zcode/agents/`

**Interfaces:**
- Consumes: nada.
- Produces: la fila `zcode` de la tabla de tiers — cuatro valores
  (`acepta_model`, `acepta_effort`, `valor_desconocido`, `catalogo`) que la
  Task 12.5 lee del documento para llenar `tools/model-routing.sh`.

**Vía:** inspección estática del bundle, la misma que la Task 5.6 usó para
verificar que `saikit_owned` y `skills:` no rompen el loader. Es lo que este
host permite y ya hay precedente.

- [ ] **Step 1: Localizar el bundle y fijar su versión**

```bash
# La huella del directorio de agentes va PRIMERO: el step 5 la compara contra
# esta. Sin tomarla aca, la verificacion de no-mutacion no se puede hacer.
find "$HOME/.zcode/agents" -type f -print0 2>/dev/null \
  | sort -z | xargs -0 cksum > /tmp/zcode-agents-antes.txt
wc -l /tmp/zcode-agents-antes.txt

find "$HOME/.zcode" -name 'zcode*.cjs' -o -name 'zcode*.js' | head
# Registrar ruta, tamaño y sha256 en el documento. La versión medida por la 5.6
# fue 3.7.5-11; si difiere, se anota — no se asume paridad.
```

Esta tarea es **sólo lectura** (inspección del bundle), así que el árbol de
agentes no debería cambiar. La huella existe para probarlo, no para suponerlo.

- [ ] **Step 2: Encontrar el parser de frontmatter de agentes**

```bash
BUNDLE="<ruta del step 1>"
grep -aoE '.{200}(subagent_type|agents/|frontmatter).{200}' "$BUNDLE" | head -20
```

Buscá qué claves del frontmatter lee y cuáles ignora. La 5.6 midió que el parser
**exige `name`+`description`**, que `skills` es clave oficial, y que **el resto
se ignora**. La pregunta nueva es si `model` y `effort` están en la lista de
claves oficiales o caen en "el resto".

- [ ] **Step 3: Responder las cuatro preguntas, con la cita del bundle**

Cada respuesta va con el fragmento que la sostiene. Si una no se puede
responder por inspección, se declara **no observada** — no se infiere.

| Pregunta | Respuesta | Evidencia |
|---|---|---|
| ¿Acepta `model:` en frontmatter? | | |
| ¿Acepta `effort:` (o equivalente)? | | |
| ¿Qué hace con un valor desconocido? | | |
| ¿Catálogo real de la cuenta? | | |

- [ ] **Step 4: Confirmar el catálogo, que hoy es evidencia débil**

Los IDs `glm-4.6`, `glm-5-turbo`, `glm-5.1`, `glm-5.2`, `glm-5.3` salieron de un
grep contra `~/.zcode/cli/db/db.sqlite`. Eso es **menciones históricas**, no el
catálogo de la cuenta. Confirmalo por la vía que el host ofrezca (selector de
modelo de la UI, o el endpoint que el bundle nombre) y registrá cuál usaste.

- [ ] **Step 5: Verificar que no se tocó nada**

```bash
find "$HOME/.zcode/agents" -type f -print0 2>/dev/null \
  | sort -z | xargs -0 cksum > /tmp/zcode-agents-despues.txt
diff /tmp/zcode-agents-antes.txt /tmp/zcode-agents-despues.txt && echo "AGENTES INTACTOS"
```

`diff` no vacío ⇒ la medición no vale y se reporta qué quedó cambiado.

- [ ] **Step 6: Escribir `docs/task-12.1-medicion.md` y commitear**

Formato: el de `docs/task-10.9-medicion.md`. Tiene que incluir la versión del
bundle, las cuatro respuestas con su evidencia, lo que quedó **no observado**, y
la huella antes/después.

```bash
git add docs/task-12.1-medicion.md
git commit -m "test(12.1): medición de model/effort en el loader de agentes de zcode"
```

---

## Task 12.2: Medición grok — ¿honra `model:` y `effort:`?

`[Test]` `[lane:gate]` `[tdd:required]`

**Files:**
- Create: `docs/task-12.2-medicion.md`
- Read-only: `~/.grok/agents/`, perfil `~/.grok`

**Interfaces:**
- Consumes: nada.
- Produces: la fila `grok` de la tabla de tiers, mismos cuatro valores que 12.1.

**Vía:** captura headless estilo Task 7.1 (`grok -p` sobre repo descartable). El
bundle de Grok no se inspecciona: 7.1 ya estableció que la vía medible en este
host es la captura de payloads reales.

- [ ] **Step 1: Huella del perfil ANTES**

**La huella NO puede ser del perfil entero.** Correr `grok -p` escribe sesiones,
logs e índices por diseño: `find "$HOME/.grok" -type f` antes y después **nunca**
va a dar igual, y el chequeo gritaría en falso en cada corrida. Se vigila lo que
la medición no debe tocar, excluyendo lo que el host reescribe solo — la 7.1 hizo
exactamente eso.

Los steps de esta tarea corren en shells distintas (hay corridas interactivas en
el medio), así que el helper y las rutas van a un archivo que cada step
**sourcea**. Definirlos sueltos en el step 1 los pierde y el step 6 falla con
`command not found` — o peor, `rm -rf ""` sobre una variable vacía.

```bash
cat > /tmp/probe-122.env <<'EOF'
# IDEMPOTENTE: sourcear este archivo dos veces NO puede crear un segundo
# directorio ni perder la referencia al primero. Medido al ejecutar la 12.3:
# sin persistir la ruta, cada `source` corria mktemp de nuevo y quedaba un
# huerfano. La ruta se guarda la primera vez y se reusa despues.
# Repo descartable con nombre UNICO: nunca una ruta fija. Una ruta fija se
# puede pisar y despues borrar con rm -rf un repo preexistente del operador
# (en /c/dev ya conviven saikit-probe-109-zcode, saikit-captura y otros).
if [ -s /tmp/probe-122.path ]; then
  probe="$(cat /tmp/probe-122.path)"
else
  probe="$(mktemp -d /c/dev/saikit-probe-122-XXXXXX)"
  printf '%s' "$probe" > /tmp/probe-122.path
fi
huella_grok() {   # el perfil MENOS lo que el runtime reescribe solo
  find "$HOME/.grok" -type d \( -name sessions -o -name logs -o -name tmp \
                                -o -name cache -o -name telemetry \) -prune -o \
       -type f -print0 2>/dev/null | sort -z | xargs -0 cksum
}
EOF
. /tmp/probe-122.env
huella_grok > /tmp/grok-antes.txt
wc -l /tmp/grok-antes.txt; echo "repo descartable: $probe"
```

`mktemp -d` falla si no puede crear un directorio nuevo, así que `$probe` nunca
apunta a algo preexistente y el `rm -rf` del final sólo puede borrar lo que esta
medición creó. Cada step siguiente arranca con `. /tmp/probe-122.env`.

Antes de confiar en esa lista de podas, **verificá contra este perfil** qué
subdirectorios existen y cuáles cambian con una corrida en vacío: los nombres de
arriba salen de lo observado, y un directorio dinámico que no esté podado
produce el mismo falso positivo.

- [ ] **Step 2: Repo descartable y trust declarado**

```bash
. /tmp/probe-122.env
cd "$probe" && git init -q
# Declarar el trust del repo en Grok. Se REVOCA en el step 6 — no queda abierto.
```

- [ ] **Step 3: Perfil de prueba con `model:` y `effort:` en el frontmatter**

```bash
mkdir -p "$HOME/.grok/agents"
cat > "$HOME/.grok/agents/saikit-probe-122.md" <<'EOF'
---
name: saikit-probe-122
description: Sonda de la Task 12.2. Devuelve una sola línea y termina.
tools: Read
model: grok-4.5
effort: low
saikit_owned: summonaikit-claude
---

Respondé exactamente: PROBE-122-OK. Nada más.
EOF
```

Este archivo es el ÚNICO cambio al perfil y se borra en el step 6.

- [ ] **Step 4: Despachar el agente y capturar**

```bash
. /tmp/probe-122.env; cd "$probe"
grok -p 'Usá spawn_subagent con subagent_type=saikit-probe-122.' 2>&1 | tee /tmp/grok-122.log
```

Qué mirar en la salida y en los logs del host:
- ¿El agente resolvió, o el host rechazó el tipo por frontmatter inválido?
- ¿Hay alguna señal de qué modelo corrió (banner, telemetría, log de sesión)?

- [ ] **Step 5: Repetir con un valor DESCONOCIDO**

```bash
. /tmp/probe-122.env
sed -i 's/^model: grok-4.5$/model: modelo-que-no-existe-122/' "$HOME/.grok/agents/saikit-probe-122.md"
. /tmp/probe-122.env; cd "$probe"
grok -p 'Usá spawn_subagent con subagent_type=saikit-probe-122.' 2>&1 | tee /tmp/grok-122-malo.log
```

Ésta es la pregunta que decide si un ID equivocado es inerte o rompe el turno.
Tres resultados posibles, los tres válidos como medición: lo ignora y corre con
el default; falla el despacho con error; cae a un default distinto en silencio.

- [ ] **Step 6: Limpiar, revocar trust, verificar huella**

```bash
. /tmp/probe-122.env
rm -f "$HOME/.grok/agents/saikit-probe-122.md"
# Revocar el trust del repo descartable en Grok.
huella_grok > /tmp/grok-despues.txt
diff /tmp/grok-antes.txt /tmp/grok-despues.txt && echo "PERFIL INTACTO"
rm -rf "$probe"
```

`diff` no vacío ⇒ la medición no vale y se reporta qué quedó cambiado.

- [ ] **Step 7: Escribir `docs/task-12.2-medicion.md` y commitear**

Incluí las cuatro respuestas, los dos logs relevantes, el catálogo de la cuenta
(el harness observó `grok-4.5` y `grok-composer-2.5-fast` el 2026-07-09 en CLI
0.2.93 — **eso es de otra cuenta y no se hereda**), y la huella antes/después.

```bash
git add docs/task-12.2-medicion.md
git commit -m "test(12.2): medición de model/effort en los perfiles de agente de grok"
```

---

## Task 12.3: Medición kimi — ¿honra `model:` y `effort:`?

`[Test]` `[lane:gate]` `[tdd:required]` — **CERRADA 2026-08-18.**
Resultado en `docs/task-12.3-medicion.md`, rama `test/12.3-medicion-kimi`.

**Qué salió, en una línea:** la premisa de lectura se confirmó (kimi-code sí lee
`~/.agents/agents/`), pero el host **no acepta modelo ni effort por agente** —
su parser tiene un conjunto cerrado de claves y `model`/`effort` no están. La
fila `kimi` del router queda vacía de forma definitiva. Consecuencias aplicadas
en la Task 12.7 y en el diseño.

Los steps de abajo quedan como registro de lo que se ejecutó. **Dos defectos
propios que aparecieron al correrlos y que ya están corregidos acá y en la 12.2:**
el `/tmp/probe-*.env` creaba un `mktemp -d` nuevo en cada `source` (dejó un
directorio huérfano), y la lista de podas de la huella no cubría tres archivos
de contabilidad del runtime.

**Files:**
- Create: `docs/task-12.3-medicion.md`
- Read-only: `~/.agents/agents/`, `~/.kimi-code/config.toml`

**Interfaces:**
- Consumes: nada.
- Produces: la fila `kimi` de la tabla de tiers, mismos cuatro valores. Además,
  **la confirmación de que kimi-code lee `~/.agents/agents/`** — que hoy es
  inferencia de dos señales, no una carga observada.

**Vía:** captura viva. `~/.kimi-code/bin/kimi.exe` son ~141 MB compilados: no hay
inspección estática equivalente a `zcode.cjs`.

- [ ] **Step 1: Huella ANTES de los dos directorios en juego**

Misma disciplina que la 12.2, y por la misma razón: `~/.kimi-code/` tiene
`sessions/`, `logs/`, `cache/`, `telemetry/`, `updates/` y `search-index/`, que
el runtime reescribe solo. Una huella del árbol completo **nunca** vuelve a dar
igual y el chequeo gritaría en falso siempre.

```bash
cat > /tmp/probe-123.env <<'EOF'
# IDEMPOTENTE: sourcear este archivo dos veces NO puede crear un segundo
# directorio ni perder la referencia al primero. Medido al ejecutar la 12.3:
# sin persistir la ruta, cada `source` corria mktemp de nuevo y quedaba un
# huerfano. La ruta se guarda la primera vez y se reusa despues.
if [ -s /tmp/probe-123.path ]; then
  probe="$(cat /tmp/probe-123.path)"
else
  probe="$(mktemp -d /c/dev/saikit-probe-123-XXXXXX)"
  printf '%s' "$probe" > /tmp/probe-123.path
fi
huella_kimi() {
  # Los tres -name de la ultima linea salieron de EJECUTAR la 12.3: de 385
  # archivos vigilados cambiaron exactamente esos tres, y son contabilidad del
  # runtime (refresco de token, registro de sesiones, registro de workspaces).
  # Sin podarlos el chequeo de no-mutacion grita en falso en cada corrida.
  find "$HOME/.agents" "$HOME/.kimi-code" \
       -type d \( -name sessions -o -name logs -o -name cache -o -name telemetry \
                  -o -name updates -o -name search-index -o -name tmp \
                  -o -name user-history -o -name server -o -name bin \
                  -o -name .claude \) -prune -o \
       -type f \! -name kimi-code.json \! -name session_index.jsonl \
                  \! -name workspaces.json -print0 2>/dev/null \
    | sort -z | xargs -0 cksum
}
EOF
. /tmp/probe-123.env
huella_kimi > /tmp/kimi-antes.txt
wc -l /tmp/kimi-antes.txt; echo "repo descartable: $probe"
```

Verificá la lista de podas contra este perfil antes de confiar en ella: un
directorio dinámico sin podar da el mismo falso positivo que la huella completa.
Lo que **sí** tiene que quedar bajo vigilancia es `~/.agents/agents/`, que es
justo lo que la medición toca.

- [ ] **Step 2: Confirmar PRIMERO que kimi-code lee `~/.agents/agents/`**

Ésta es la premisa que sostiene toda la fila. Si cae, la fila queda vacía y el
host no recibe ruteo.

```bash
cat > "$HOME/.agents/agents/saikit-probe-123.md" <<'EOF'
---
name: saikit-probe-123
description: Sonda de la Task 12.3. Devuelve una sola línea y termina.
tools: Read
saikit_owned: summonaikit-claude
---

Respondé exactamente: PROBE-123-OK. Nada más.
EOF
. /tmp/probe-123.env
cd "$probe" && git init -q
kimi -p 'Delegá al subagente saikit-probe-123.' 2>&1 | tee /tmp/kimi-123.log
```

Si el tipo **no resuelve**, kimi no lee ese directorio: registralo, saltá los
steps 3–4, y la fila `kimi` queda vacía con su razón.

- [ ] **Step 3: Agregar `model:` y `effort:` al perfil de la sonda**

```bash
sed -i '/^tools: Read$/a model: kimi-code/k3\neffort: low' "$HOME/.agents/agents/saikit-probe-123.md"
. /tmp/probe-123.env; cd "$probe"
kimi -p 'Delegá al subagente saikit-probe-123.' 2>&1 | tee /tmp/kimi-123-model.log
```

`~/.kimi-code/config.toml` declara `support_efforts = [ "low", "high", "max" ]` y
`default_effort = "high"` **por modelo**. La pregunta es si un `effort:` de
frontmatter pisa ese default por agente, o si se ignora.

- [ ] **Step 4: Repetir con valor desconocido**

```bash
sed -i 's|^model: kimi-code/k3$|model: sonnet|' "$HOME/.agents/agents/saikit-probe-123.md"
. /tmp/probe-123.env; cd "$probe"
kimi -p 'Delegá al subagente saikit-probe-123.' 2>&1 | tee /tmp/kimi-123-sonnet.log
```

`sonnet` no es casual: es **exactamente el valor que los cinco perfiles del kit
tienen hoy** en ese directorio. Este step mide el defecto que ya está en
producción, no uno hipotético.

- [ ] **Step 5: Limpiar y verificar huella**

```bash
rm -f "$HOME/.agents/agents/saikit-probe-123.md"
. /tmp/probe-123.env
huella_kimi > /tmp/kimi-despues.txt
diff /tmp/kimi-antes.txt /tmp/kimi-despues.txt && echo "PERFILES INTACTOS"
rm -rf "$probe"
```

- [ ] **Step 6: Escribir `docs/task-12.3-medicion.md` y commitear**

Además de las cuatro respuestas: **qué hace kimi hoy con el `model: sonnet` que
ya tiene plantado**, que es el hallazgo con consecuencia inmediata.

```bash
git add docs/task-12.3-medicion.md
git commit -m "test(12.3): medición de model/effort en los perfiles de agente de kimi"
```

---

## Task 12.4: `tools/model-routing.sh` — el router

`[Feature]` `[lane:gate]` `[tdd:required]`

**Files:**
- Create: `tools/model-routing.sh`
- Test: `tests/test_model_routing.sh`

**Interfaces:**
- Consumes: nada. **No depende de 12.1/12.2/12.3** — nace con la fila `claude`
  completa y las otras tres vacías, que es el comportamiento de hoy.
- Produces:
  - `tools/model-routing.sh --host H --role R --field model` → ID de modelo por
    stdout, o **nada** (stdout vacío, exit 0) si la fila del host está vacía.
  - `--field effort` → nivel de effort, misma semántica.
  - `--format json` → `{"host":"…","role":"…","tier":"…","model":"…","effort":"…"}`
  - `--format frontmatter` → cero, una o dos líneas `model: X` / `effort: Y`,
    listas para insertar en un bloque de frontmatter.
  - `exit 2` en host, rol o tier desconocido.

- [ ] **Step 1: Escribir el test que falla**

Crear `tests/test_model_routing.sh`:

```bash
#!/usr/bin/env bash
# Task 12.4 — el router rol → tier → (modelo, effort) por host.
# Corre contra un sandbox propio: nunca toca el repo ni el perfil vivo.
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/lib/sandbox.sh"
sandbox_init

repo="$(cd "$here/.." && pwd)"
router="$repo/tools/model-routing.sh"

fail=0
caso() { printf '  caso: %s\n' "$1"; }
malo() { printf '    FAIL: %s\n' "$1" >&2; fail=1; }

igual() {  # $1=esperado $2=obtenido $3=etiqueta
  [ "$1" = "$2" ] || malo "$3: esperaba [$1], obtuve [$2]"
}

caso "la tabla del host claude, valor por valor"
igual "claude-sonnet-5" "$(bash "$router" --host claude --role implementer --field model)" "implementer/model"
igual "medium"          "$(bash "$router" --host claude --role implementer --field effort)" "implementer/effort"
igual "claude-sonnet-5" "$(bash "$router" --host claude --role verifier --field model)"    "verifier/model"
igual "low"             "$(bash "$router" --host claude --role verifier --field effort)"   "verifier/effort"
igual "claude-opus-5"   "$(bash "$router" --host claude --role reviewer --field model)"    "reviewer/model"
igual "xhigh"           "$(bash "$router" --host claude --role reviewer --field effort)"   "reviewer/effort"

caso "rol -> tier"
igual "standard" "$(bash "$router" --host claude --role implementer --field tier)" "implementer"
igual "verify"   "$(bash "$router" --host claude --role verifier --field tier)"    "verifier"
igual "review"   "$(bash "$router" --host claude --role reviewer --field tier)"    "reviewer"

caso "una fila de host sin valor devuelve VACIO con exit 0, no un default"
# zcode y grok: vacias hasta que 12.1 y 12.2 las llenen.
# kimi: vacia DEFINITIVA -- la 12.3 midio que el host no acepta model ni effort
# por agente, asi que esa fila no se llena nunca y este caso queda permanente.
for h in zcode grok kimi; do
  out="$(bash "$router" --host "$h" --role implementer --field model)"; rc=$?
  [ "$rc" -eq 0 ] || malo "$h: esperaba exit 0, obtuve $rc"
  [ -z "$out" ]   || malo "$h: esperaba stdout vacio, obtuve [$out]"
done

caso "--format frontmatter"
igual "model: claude-opus-5
effort: xhigh" "$(bash "$router" --host claude --role reviewer --format frontmatter)" "claude/reviewer"
igual "" "$(bash "$router" --host zcode --role reviewer --format frontmatter)" "zcode sin medir"

caso "--format json"
esperado='{"host":"claude","role":"reviewer","tier":"review","model":"claude-opus-5","effort":"xhigh"}'
igual "$esperado" "$(bash "$router" --host claude --role reviewer --format json)" "json"

caso "desconocido => exit 2, y NO imprime nada por stdout"
for args in "--host marte --role implementer" \
            "--host claude --role astronauta" \
            "--host claude --tier turbo"; do
  # shellcheck disable=SC2086
  out="$(bash "$router" $args 2>/dev/null)"; rc=$?
  [ "$rc" -eq 2 ] || malo "[$args]: esperaba exit 2, obtuve $rc"
  [ -z "$out" ]   || malo "[$args]: exit 2 no debe imprimir por stdout, obtuve [$out]"
done

caso "--role invalido NO se cuela por venir junto a un --tier valido"
out="$(bash "$router" --host claude --role astronauta --tier review 2>/dev/null)"; rc=$?
[ "$rc" -eq 2 ] || malo "un rol invalido debe salir 2 aunque el tier sea valido (obtuve $rc)"
printf '%s' "$out" | grep -q 'astronauta' && malo "no debe acreditar un rol inventado en la salida"

caso "una bandera sin valor NO cuelga el proceso (bucle infinito de shift 2)"
# Reproducido: `shift 2` con el valor ausente no shiftea y devuelve != 0; bajo
# `set -u` sin `-e` el while re-procesa la misma bandera para siempre.
for flag in --host --role --tier --field --format; do
  out="$(timeout 10 bash "$router" "$flag" 2>/dev/null)"; rc=$?
  [ "$rc" -eq 124 ] && malo "[$flag] sin valor colgo el proceso (bucle infinito)"
  [ "$rc" -eq 2 ]   || malo "[$flag] sin valor deberia salir 2, obtuve $rc"
done

caso "el rol desconocido NO se pierde adentro de una sustitucion (trampa de set -u)"
# Bajo `set -u` sin `-e`, X="$(f)" con `exit 2` adentro deja X vacio y sigue.
# El router tiene que salir 2 de verdad, no imprimir vacio y salir 0.
bash "$router" --host claude --role astronauta >/dev/null 2>&1
[ "$?" -eq 2 ] || malo "un rol desconocido tiene que salir 2 desde el proceso, no desde un subshell"

caso "candado: ningun ID de modelo vive fuera del router"
# Cubre tests/ ademas de tools/ y agents/: la primera version solo miraba esos
# dos y por ahi se colaba un `model: claude-opus-5` hardcodeado en
# test_install_hook.sh -- que es exactamente lo que la regla existe para evitar,
# porque obliga a editar dos archivos cada vez que cambia la tabla.
# Se excluye ESTE archivo (es el que declara la tabla) y los fixtures del vendor
# (son copias byte a byte de lo que el CLI del kit escribio: evidencia, no
# configuracion; editarlas invalidaria el manifiesto).
otros="$(grep -rlE 'claude-(sonnet|opus|haiku|fable)-[0-9]|glm-[0-9]|grok-[0-9]|kimi-code/' \
           "$repo/tools" "$repo/agents" "$repo/tests" 2>/dev/null \
         | grep -vE 'model-routing\.sh|test_model_routing\.sh|tests/fixtures/vendor-agents/')"
[ -z "$otros" ] || malo "IDs de modelo fuera del router: $otros"

if [ "$fail" -ne 0 ]; then
  echo "test_model_routing: FAIL" >&2
  exit 1
fi
echo "test_model_routing: OK"
```

- [ ] **Step 2: Correrlo y verificar que falla**

```bash
bash tests/test_model_routing.sh
```

Esperado: FAIL, con `bash: .../tools/model-routing.sh: No such file or directory`.

- [ ] **Step 3: Escribir `tools/model-routing.sh`**

```bash
#!/usr/bin/env bash
# Task 12.4 — resolver modelo y effort desde el contrato rol -> tier.
#
# Los IDs de modelo viven SOLO en este archivo. Ni el instalador ni las
# plantillas de agents/ los nombran: un ID repetido en dos lugares es un ID
# que se actualiza en uno solo. `tests/test_model_routing.sh` lo candea.
#
# La forma sale de `scripts/model-routing.sh` de claude-code-harness 5.6.0,
# cuya politica (docs/model-routing-policy.md, adoptada 2026-06-11) decide
# rutear por ROL y declara Non-Goal inferir el tier del texto del turno. Este
# repo llego a la misma regla por su cuenta en la Task 10.1: el carril fast se
# pide explicito, no se infiere de una regex de trivialidad.
#
# DIFERENCIA DELIBERADA con el router del harness: alla las funciones de
# resolucion hacen `exit 2` adentro de una sustitucion `$( )`, lo que funciona
# porque el script corre con `set -euo pipefail`. Los scripts de ESTE repo
# corren con `set -u` y SIN `-e` (los 7 de tools/), donde ese mismo patron deja
# la variable vacia y sigue de largo -- un fallback silencioso, justo lo que
# Core Rule 2 prohibe. Aca las funciones imprimen por stdout y DEVUELVEN un
# codigo; el llamador lo chequea.
set -u

HOST=''
ROLE=''
TIER=''
FIELD=''
FORMAT='json'

decir() { printf '%s\n' "$*" >&2; }

uso() {
  cat <<'EOF'
Uso:
  tools/model-routing.sh --host claude|zcode|grok|kimi
                         (--role implementer|verifier|reviewer | --tier standard|verify|review)
                         [--field model|effort|tier]
                         [--format json|frontmatter]

Una fila de host sin medir devuelve VACIO con exit 0: la clave se omite del
perfil y el agente hereda del padre. Host, rol o tier desconocido => exit 2.
EOF
}

# `shift 2` con el valor AUSENTE no shiftea nada y devuelve != 0. Bajo `set -u`
# sin `-e` eso no aborta: el while vuelve a procesar la misma bandera, para
# siempre. Reproducido: `--host` como ultimo argumento => bucle infinito. El
# valor se exige ANTES de shiftear.
requiere_valor() {  # $1=bandera  $2=args restantes ($#)
  if [ "$2" -lt 2 ]; then
    decir "[summonaikit] model-routing: $1 necesita un valor"
    exit 2
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --host)   requiere_valor --host "$#";   HOST="$2";   shift 2 ;;
    --host=*) HOST="${1#*=}"; shift ;;
    --role)   requiere_valor --role "$#";   ROLE="$2";   shift 2 ;;
    --role=*) ROLE="${1#*=}"; shift ;;
    --tier)   requiere_valor --tier "$#";   TIER="$2";   shift 2 ;;
    --tier=*) TIER="${1#*=}"; shift ;;
    --field)   requiere_valor --field "$#";  FIELD="$2";  shift 2 ;;
    --field=*) FIELD="${1#*=}"; shift ;;
    --format)   requiere_valor --format "$#"; FORMAT="$2"; shift 2 ;;
    --format=*) FORMAT="${1#*=}"; shift ;;
    -h|--help) uso; exit 0 ;;
    *) decir "[summonaikit] model-routing: argumento desconocido: $1"; uso >&2; exit 2 ;;
  esac
done

# Imprime el tier por stdout, devuelve 0. Rol desconocido: 1, sin imprimir.
rol_a_tier() {
  case "$1" in
    implementer) printf 'standard' ;;
    verifier)    printf 'verify' ;;
    reviewer)    printf 'review' ;;
    *) return 1 ;;
  esac
  return 0
}

# El rol se valida SIEMPRE que venga, aunque tambien venga --tier. Si la
# validacion viviera solo adentro del `if [ -z "$TIER" ]`, entonces
# `--role astronauta --tier review` saldria 0 y ademas imprimiria
# `"role":"astronauta"` en el JSON: un rol inventado acreditado por el router.
if [ -n "$ROLE" ]; then
  ROLE_TIER="$(rol_a_tier "$ROLE")" || {
    decir "[summonaikit] model-routing: rol desconocido: $ROLE"
    exit 2
  }
  [ -z "$TIER" ] && TIER="$ROLE_TIER"
fi

if [ -z "$TIER" ]; then
  decir "[summonaikit] model-routing: hace falta --role o --tier"
  exit 2
fi

# Un tier que ningun rol mapea no existe: no se define "por las dudas".
case "$TIER" in
  standard|verify|review) ;;
  *) decir "[summonaikit] model-routing: tier desconocido: $TIER"; exit 2 ;;
esac

MODEL=''
EFFORT=''

# --- Tablas por host ---------------------------------------------------------
# Una fila vacia NO es un error: es "todavia no medido" (Task 12.1/12.2/12.3).
# Se traduce a clave omitida, que es como zcode se comporta hoy (Task 5.6:
# "sin model:; heredan GLM del padre").
case "$HOST" in
  claude)
    # Catalogo y precios: skill claude-api, cacheado 2026-06-24.
    # review usa Opus 5 y NO Fable 5, a diferencia del harness (decision de
    # operador 2026-07-25). Fable son $10/$50 por millon contra $5/$25 de Opus
    # -- el doble en salida -- y xhigh ya es el mejor setting para trabajo de
    # codigo y agentico. Fable queda como escalada MANUAL, fuera del ruteo
    # automatico: una ruta automatica al tier mas caro es como se llega a una
    # factura que nadie decidio.
    case "$TIER" in
      standard) MODEL='claude-sonnet-5'; EFFORT='medium' ;;
      # verify: mismo modelo que standard, effort bajo. El verifier corre
      # comandos y lee salida (orquestacion) pero tambien inspecciona el diff
      # (juicio). Bajar el effort ahorra sin bajar de modelo, y evita el techo
      # de 200K de contexto del tier mas barato.
      verify)   MODEL='claude-sonnet-5'; EFFORT='low' ;;
      review)   MODEL='claude-opus-5';   EFFORT='xhigh' ;;
    esac
    ;;
  zcode)
    # Fila pendiente: Task 12.1. Hasta entonces, hereda GLM del padre.
    : ;;
  grok)
    # Fila pendiente: Task 12.2.
    : ;;
  kimi)
    # Fila pendiente: Task 12.3.
    : ;;
  '')
    decir "[summonaikit] model-routing: hace falta --host"
    exit 2
    ;;
  *)
    decir "[summonaikit] model-routing: host desconocido: $HOST"
    exit 2
    ;;
esac

case "$FIELD" in
  '') ;;
  model)  printf '%s\n' "$MODEL";  exit 0 ;;
  effort) printf '%s\n' "$EFFORT"; exit 0 ;;
  tier)   printf '%s\n' "$TIER";   exit 0 ;;
  *) decir "[summonaikit] model-routing: --field desconocido: $FIELD"; exit 2 ;;
esac

case "$FORMAT" in
  json)
    printf '{"host":"%s","role":"%s","tier":"%s","model":"%s","effort":"%s"}\n' \
           "$HOST" "$ROLE" "$TIER" "$MODEL" "$EFFORT"
    ;;
  frontmatter)
    # Cero, una o dos lineas. Nunca `model:` con valor vacio: eso seria escribir
    # una clave que miente en vez de omitirla.
    [ -n "$MODEL" ]  && printf 'model: %s\n' "$MODEL"
    [ -n "$EFFORT" ] && printf 'effort: %s\n' "$EFFORT"
    ;;
  *) decir "[summonaikit] model-routing: --format desconocido: $FORMAT"; exit 2 ;;
esac
exit 0
```

- [ ] **Step 4: Correr el test y verificar que pasa**

```bash
bash tests/test_model_routing.sh
```

Esperado: `test_model_routing: OK`.

Ojo con el caso `--field model` en una fila vacía: `printf '%s\n' ""` imprime un
salto de línea, y `$( )` lo recorta, así que `[ -z "$out" ]` da verdadero. Si el
caso falla, no lo "arregles" cambiando el test — mirá qué imprime de más.

- [ ] **Step 5: Commit**

```bash
git add tools/model-routing.sh tests/test_model_routing.sh
git commit -m "feat(12.4): router rol -> tier -> (modelo, effort) por host"
```

- [ ] **Step 6: Rama, PR, y la batería completa en CI**

```bash
git push -u origin HEAD
gh pr create --fill
git log origin/master..HEAD --oneline   # SOLO los commits de esta tarea
```

Leé el resultado de CI. **No corras `bash tests/run.sh` local**: son ~10 min acá
contra ~3 en CI.

---

## Task 12.5: Traducción por host e inyección en zcode y grok

`[Feature]` `[lane:gate]` `[tdd:required]`

**Files:**
- Modify: `tools/install-hook.sh` (`grok_agente_traducido` → `agente_traducido`;
  `zcode_agente_estado` y `zcode_instalar_agentes` para comparar y publicar
  contra la traducida)
- Test: `tests/test_install_hook.sh`

**Interfaces:**
- Consumes: `tools/model-routing.sh --host H --role R --format frontmatter`
  (Task 12.4). Las filas de `zcode` y `grok` se llenan con lo que midan 12.1 y
  12.2; **si una medición dice que el host ignora la clave, esa fila queda
  vacía** y esta tarea igual cierra: la traducción funciona, sólo que no inyecta
  nada.
- Produces: `agente_traducido <host> <fuente>` → plantilla traducida por stdout.
  La consumen las Tasks 12.6 y 12.7 para los dos hosts nuevos.

**El defecto que esta tarea introduce si se hace a medias:** grok ya clasifica
los tres estados contra la plantilla **traducida**
(`grok_agente_estado "$dest" "$(grok_agente_traducido "$fuente")"`, línea ~805),
pero zcode compara contra la **cruda** (`zcode_agente_estado "$dest" "$fuente"`,
línea ~362). Con inyección por host, esa comparación da `NUESTRO_DISTINTO` en
cada corrida: reescribe el perfil y deja un backup nuevo cada vez. Los dos
cambios van juntos o no van.

- [ ] **Step 1: Escribir los casos que fallan**

`tests/test_install_hook.sh` **invoca el instalador como subproceso**
(`bash "$tool" …`) y **nunca lo sourcea**: no se pueden llamar sus funciones
internas desde el test. Todo se ejercita por la CLI y se asierta sobre los
archivos resultantes. El helper `host_zcode()` (línea ~310) y los fixtures
`dest_listo` / `nuevo_zcode_cfg` ya existen — reusalos, y el temporal del
archivo es `$tmp`, no `$SANDBOX`.

Hace falta una costura nueva, del mismo tipo que `SAIKIT_INSTALL_TOOL`: sin ella
estos casos sólo pasan si la medición llenó la fila, y el test mediría la
medición en vez de la máquina.

```bash
# --- Costura: router de prueba con filas llenas para los cuatro hosts --------
# Mismo mecanismo que SAIKIT_INSTALL_TOOL: apuntar el tool bajo prueba a otra
# copia. Sin esto, si 12.1/12.2 midieron que el host ignora la clave, la fila
# queda vacia y estos casos no probarian la INYECCION, solo la medicion.
router_stub="$tmp/router-stub.sh"
cat > "$router_stub" <<'STUB'
#!/usr/bin/env bash
set -u
host=''; role=''; format='json'
while [ "$#" -gt 0 ]; do
  case "$1" in
    --host) host="$2"; shift 2 ;;
    --role) role="$2"; shift 2 ;;
    --format) format="$2"; shift 2 ;;
    *) shift ;;
  esac
done
[ "$format" = 'frontmatter' ] || exit 0
printf 'model: modelo-de-prueba-%s-%s\neffort: low\n' "$host" "$role"
STUB

host_zcode_stub() {
  SAIKIT_MODEL_ROUTING_TOOL="$router_stub" host_zcode "$@"
}

caso "zcode: el perfil instalado lleva el model/effort que emite el router"
dest_listo; nuevo_zcode_cfg
host_zcode_stub >/dev/null 2>&1
grep -q '^model: modelo-de-prueba-zcode-reviewer$' "$zcode_agents/reviewer.md" \
  || malo "el perfil de zcode no lleva el modelo ruteado"
grep -q '^effort: low$' "$zcode_agents/reviewer.md" \
  || malo "el perfil de zcode no lleva el effort ruteado"

caso "la inyeccion cae DENTRO del primer bloque frontmatter, una sola vez"
n="$(grep -c '^model: ' "$zcode_agents/reviewer.md")"
[ "$n" = "1" ] || malo "esperaba 1 linea model:, hay $n"
linea_model="$(grep -n '^model: ' "$zcode_agents/reviewer.md" | cut -d: -f1)"
linea_cierre="$(grep -n '^---' "$zcode_agents/reviewer.md" | sed -n 2p | cut -d: -f1)"
[ "$linea_model" -lt "$linea_cierre" ] || malo "model: cayo fuera del frontmatter"

caso "una fila de host vacia no inyecta ninguna clave (router real, host sin medir)"
dest_listo; nuevo_zcode_cfg
host_zcode >/dev/null 2>&1   # router REAL, no el stub
if grep -q '^model:' "$zcode_agents/reviewer.md"; then
  malo "un host sin fila medida no debe llevar model:"
fi

caso "instalar dos veces seguidas NO reescribe (el defecto de comparar contra la cruda)"
dest_listo; nuevo_zcode_cfg
host_zcode_stub >/dev/null 2>&1
antes="$(find "$zcode_agents" -type f -print0 | sort -z | xargs -0 cksum)"
host_zcode_stub >/dev/null 2>&1
despues="$(find "$zcode_agents" -type f -print0 | sort -z | xargs -0 cksum)"
[ "$antes" = "$despues" ] || malo "la segunda corrida reescribio los perfiles"
[ -d "$zcode_agents/saikit-backups" ] && malo "la segunda corrida dejo un backup: esta reescribiendo"

caso "grok sigue omitiendo skills: (traduccion de la 7.5, no se pierde)"
# Usa el helper de grok que ya existe en el archivo para --host grok.
# El frontmatter instalado no debe declarar skills:, y SI debe llevar model:.
grok_agents_de_prueba="$tmp/gagents-12-5"
SAIKIT_MODEL_ROUTING_TOOL="$router_stub" \
SAIKIT_GROK_AGENTS_DIR="$grok_agents_de_prueba" \
  bash "$tool" --host grok --dest "$dest" >/dev/null 2>&1
sed -n '/^---/,/^---/p' "$grok_agents_de_prueba/reviewer.md" | grep -q '^skills:' \
  && malo "grok no debe llevar skills: en el frontmatter"
grep -q '^model: modelo-de-prueba-grok-reviewer$' "$grok_agents_de_prueba/reviewer.md" \
  || malo "el perfil de grok no lleva el modelo ruteado"
```

El caso de "fila vacía" usa el router **real**: si 12.1 midió que zcode sí acepta
`model:` y llenaste su fila, ese caso deja de valer tal cual — cambialo para que
afirme el valor medido, no la ausencia. Es la única aserción de este bloque que
depende del resultado de una medición.

- [ ] **Step 2: Correr y verificar que falla**

```bash
bash tests/test_install_hook.sh
```

Esperado: FAIL, pero **no** por `command not found` — los casos van por la CLI y
no llaman funciones internas. El rojo real es el `grep` que no encuentra
`model:` en el perfil instalado ("el perfil de zcode no lleva el modelo
ruteado"), porque todavía no hay inyección. Si ves `command not found`, tenés un
caso mal escrito, no el rojo que buscabas.

- [ ] **Step 3: Generalizar la traducción**

Reemplazar `grok_agente_traducido()` (línea ~710 de `tools/install-hook.sh`) por:

```bash
# Traduccion de frontmatter por host. Dos operaciones, en este orden:
#
#   1. OMITIR claves que el host no acepta. Medido en la 7.5: el loader de Grok
#      espera `skills:` como secuencia y la fuente lo declara como string
#      (error medido: `skills: invalid type: string ..., expected a sequence`).
#   2. INYECTAR model:/effort: del router (Task 12.4). Una fila de host sin
#      medir no inyecta nada, y el agente hereda del padre -- que es como zcode
#      se comporta desde la 5.6.
#
# Solo el PRIMER bloque frontmatter: una linea `skills:` o `model:` en el body
# es contenido, no configuracion. La fuente del repo queda intacta: una sola
# fuente, sin dos sabores.
agente_traducido() {  # $1=host  $2=fuente → stdout
  local host="$1" fuente="$2" rol inyectar router
  rol="$(zcode_agente_frontmatter "$fuente" | sed -n 's/^name: //p' | head -1)"
  if [ -z "$rol" ]; then
    # `decir` imprime por STDOUT (install-hook.sh:176). Los llamadores redirigen
    # el stdout de esta funcion a un temporal que borran ante el error, asi que
    # un `decir` aca desaparece y el operador ve un exit 2 sin razon. Va a
    # stderr explicito.
    printf '[summonaikit] instalador: %s no declara name: en el frontmatter\n' "$fuente" >&2
    return 1
  fi
  # Costura de test, mismo mecanismo que SAIKIT_INSTALL_TOOL: la suite apunta el
  # router a un stub con las filas llenas y asi prueba la INYECCION aunque las
  # mediciones 12.1/12.2/12.3 hayan dejado alguna fila vacia.
  router="${SAIKIT_MODEL_ROUTING_TOOL:-$repo/tools/model-routing.sh}"
  # `bash "$router"`, NO "$router" a secas: los 7 scripts de tools/ estan
  # versionados 100644, sin bit de ejecucion (git ls-files -s tools/*.sh), asi
  # que la invocacion directa muere con "Permission denied" en Linux -- que es
  # donde corre el CI.
  inyectar="$(bash "$router" --host "$host" --role "$rol" --format frontmatter)" || return 1

  # `^$` NO sirve como "regex que no matchea nada": matchea las lineas vacias y
  # se las comeria del frontmatter, y ahi el instalado dejaria de ser la fuente
  # traducida. `a^` no matchea nunca.
  local omitir='a^'
  [ "$host" = 'grok' ] && omitir='^skills:'

  awk -v omitir="$omitir" -v inyectar="$inyectar" '
    /^---[[:space:]]*\r?$/ {
      n++
      # El cierre del primer bloque: inyectar JUSTO ANTES.
      if (n == 2 && inyectar != "") print inyectar
      print; next
    }
    n == 1 && $0 ~ omitir { next }
    # Una clave nuestra que ya viniera en la fuente se descarta: manda el router.
    n == 1 && /^(model|effort):/ { next }
    { print }
  ' "$fuente"
}
```

`repo` ya existe como variable en `install-hook.sh` (es la raíz resuelta del
repo). Verificalo antes de usarla: `grep -n '^repo=' tools/install-hook.sh`.

- [ ] **Step 4: Que grok use la función nueva**

```bash
# En install-hook.sh, reemplazar las 3 llamadas a grok_agente_traducido:
#   grok_agente_traducido "$fuente"   →   agente_traducido grok "$fuente"
grep -n 'grok_agente_traducido' tools/install-hook.sh
```

Son las líneas ~805, ~848 y la del rollback. **No dejes la función vieja como
alias**: dos nombres para lo mismo es cómo se actualiza uno solo.

- [ ] **Step 5: Que zcode compare y publique contra la traducida**

En `zcode_instalar_agentes()` (línea ~362), la clasificación y las dos
publicaciones pasan a usar un temporal con la traducción:

```bash
  for rol in $ZCODE_AGENT_ROLES; do
    fuente="$src/$rol.md"
    dest="$dest_dir/$rol.md"
    trad="$(mktemp "${TMPDIR:-/tmp}/.saikit-trad-XXXXXX")" || exit 5
    agente_traducido zcode "$fuente" > "$trad" || { rm -f "$trad"; exit 2; }
    estado="$(zcode_agente_estado "$dest" "$trad")"
    case "$estado" in
      AUSENTE)
        zcode_publicar_agente "$trad" "$dest" || {
          rm -f "$trad"
          decir "[summonaikit] instalador: no se pudo escribir $dest"; exit 5; }
        decir "[summonaikit] AGENTE ZCODE INSTALADO: $rol"
        decir "              destino: $dest"
        ;;
      NUESTRO_IDENTICO)
        : ;;
      NUESTRO_DISTINTO)
        zcode_archivar_agente "$dest" || {
          rm -f "$trad"
          decir "[summonaikit] instalador: no se pudo respaldar $dest"; exit 5; }
        zcode_publicar_agente "$trad" "$dest" || {
          rm -f "$trad"
          decir "[summonaikit] instalador: no se pudo reparar $dest"; exit 5; }
        decir "[summonaikit] AGENTE ZCODE REPARADO: $rol"
        decir "              destino: $dest"
        ;;
      DESCONOCIDO)
        decir "[summonaikit] AGENTE ZCODE DESCONOCIDO: $rol — no se toco."
        decir "              destino: $dest"
        decir "              No lleva saikit_owned. Puede ser un cambio legitimo."
        ;;
      NO_OBSERVABLE)
        rm -f "$trad"
        decir "[summonaikit] instalador: no se pudo clasificar $dest (no es un archivo legible)."
        exit 5
        ;;
    esac
    rm -f "$trad"
  done
```

El bucle de validación de plantillas de arriba (marca, `name:`) sigue mirando la
**fuente**, no la traducida: valida la plantilla del repo, no el producto.

- [ ] **Step 6: Llenar las filas de zcode y grok en el router**

Con lo que midieron 12.1 y 12.2, reemplazá los `: ;;` de esos dos hosts en
`tools/model-routing.sh` por su `case "$TIER"`, y agregá sus casos a
`tests/test_model_routing.sh` con la misma forma que los de claude.

**Si una medición dijo que el host ignora `effort:`**, ese host lleva sólo
`MODEL=`, con el comentario que cite la medición. No se escribe una clave que el
runtime no honra.

- [ ] **Step 7: Correr los dos tests y verificar que pasan**

```bash
bash tests/test_model_routing.sh
bash tests/test_install_hook.sh
```

- [ ] **Step 8: Commit**

```bash
git add tools/install-hook.sh tools/model-routing.sh tests/test_install_hook.sh tests/test_model_routing.sh
git commit -m "feat(12.5): traduccion de frontmatter por host e inyeccion de model/effort"
```

- [ ] **Step 9: PR y batería en CI**

```bash
git push -u origin HEAD && gh pr create --fill
git log origin/master..HEAD --oneline
```

---

## Task 12.6: Posesión en claude — manifiesto de vendor y `--host claude`

`[Setup]` `[lane:gate]` `[tdd:required]`

**Files:**
- Create: `agents/vendor-manifest.sha256`
- Modify: `tools/install-hook.sh` (aceptar `--host claude`, ruta y adopción)
- Test: `tests/test_install_hook.sh`

**Interfaces:**
- Consumes: `agente_traducido claude <fuente>` (Task 12.5).
- Produces: `--host claude` escribe `~/.claude/agents/{implementer,verifier,reviewer}.md`.
  Override de test: `SAIKIT_CLAUDE_AGENTS_DIR`.

**El problema que resuelve:** los perfiles de `~/.claude/agents/` los escribe el
CLI del kit y **no llevan `saikit_owned`**, así que la máquina de tres estados
los clasifica `DESCONOCIDO` y —correctamente— no los toca. Sin una vía de
adopción, la posesión no ocurre nunca. La vía es la que el instalador ya tiene
para el hook: un manifiesto de hashes conocidos del vendor.

**Cuarto estado, no un bypass:** `VENDOR_CONOCIDO` (hash en el manifiesto) ⇒
archivar y reemplazar. `DESCONOCIDO` (ni marca ni hash) ⇒ **no se toca**. Que el
comando se llame "instalar" no lo habilita a destruir el cambio de otro.

**Límite que hay que escribir, no descubrir después.** La reparación tras un
`saikit-update` sólo funciona si el update reescribe con los **mismos bytes** que
el manifiesto ya lista. Si el vendor cambia el texto de sus perfiles, el hash
nuevo no está, el archivo no lleva `saikit_owned`, y la clasificación correcta es
`DESCONOCIDO`: no se toca. El ruteo queda desactivado hasta que alguien lea el
reporte. Por eso el paso siguiente no es opcional.

- [ ] **Step 1: Escribir los casos que fallan**

Todo por la CLI, como el resto del archivo. Helper y fixture, al lado de
`host_zcode()`:

```bash
claude_agents=''
n_ca=0
nuevo_claude_agents() {   # dir de agentes limpio por caso
  n_ca=$((n_ca + 1))
  claude_agents="$tmp/cagents-$n_ca"
  rm -rf "$claude_agents"; mkdir -p "$claude_agents"
}
host_claude() {
  SAIKIT_CLAUDE_AGENTS_DIR="$claude_agents" \
  SAIKIT_MODEL_ROUTING_TOOL="$router_stub" \
    bash "$tool" --host claude --dest "$dest" "$@"
}
# Variante con el router REAL, solo para el caso de cableado de punta a punta.
host_claude_real() {
  SAIKIT_CLAUDE_AGENTS_DIR="$claude_agents" bash "$tool" --host claude --dest "$dest" "$@"
}
# Copia un perfil del vendor congelado en fixtures al dir del caso.
poner_vendor() { cp "$repo/tests/fixtures/vendor-agents/$1.md" "$claude_agents/$1.md"; }
```

```bash
caso "claude: AUSENTE => instala con el modelo ruteado y la marca"
dest_listo; nuevo_claude_agents
out="$(host_claude 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, obtuve $rc: $out"
[ -f "$claude_agents/reviewer.md" ] || malo "no instalo reviewer.md"
grep -q '^model: modelo-de-prueba-claude-reviewer$' "$claude_agents/reviewer.md" \
  || malo "el perfil instalado no lleva el modelo que emitio el router"
grep -q '^effort: low$' "$claude_agents/reviewer.md" \
  || malo "el perfil instalado no lleva el effort que emitio el router"
grep -q '^saikit_owned: summonaikit-claude$' "$claude_agents/reviewer.md" \
  || malo "el perfil instalado no lleva la marca"

caso "claude: cableado de punta a punta con el router REAL"
# El valor esperado se le PREGUNTA al router, no se hardcodea: la regla global
# del plan es que los IDs de modelo viven solo en tools/model-routing.sh, y un
# test que los copie obliga a editar dos archivos cada vez que cambia la tabla.
dest_listo; nuevo_claude_agents
host_claude_real >/dev/null 2>&1
esperado_model="$(bash "$repo/tools/model-routing.sh" --host claude --role reviewer --field model)"
esperado_effort="$(bash "$repo/tools/model-routing.sh" --host claude --role reviewer --field effort)"
[ -n "$esperado_model" ] || malo "la fila claude del router no deberia estar vacia"
grep -q "^model: ${esperado_model}\$" "$claude_agents/reviewer.md" \
  || malo "el perfil no lleva el modelo que el router real emite ($esperado_model)"
grep -q "^effort: ${esperado_effort}\$" "$claude_agents/reviewer.md" \
  || malo "el perfil no lleva el effort que el router real emite ($esperado_effort)"

caso "claude: instalar dos veces NO reescribe"
antes="$(find "$claude_agents" -type f -print0 | sort -z | xargs -0 cksum)"
host_claude >/dev/null 2>&1
[ "$antes" = "$(find "$claude_agents" -type f -print0 | sort -z | xargs -0 cksum)" ] \
  || malo "la segunda corrida reescribio"

caso "claude: VENDOR_CONOCIDO => archiva y reemplaza"
dest_listo; nuevo_claude_agents; poner_vendor reviewer
out="$(host_claude 2>&1)"
grep -q '^saikit_owned:' "$claude_agents/reviewer.md" || malo "no adopto el perfil del vendor"
ls "$claude_agents/saikit-backups/"reviewer.md.vendor.*.bak >/dev/null 2>&1 \
  || malo "no archivo el perfil del vendor antes de pisarlo"
printf '%s' "$out" | grep -q 'ADOPTADO' || malo "no reporto la adopcion"

caso "claude: DESCONOCIDO => no se toca, y se reporta"
dest_listo; nuevo_claude_agents
printf -- '---\nname: reviewer\ndescription: mio\n---\ncambio ajeno\n' > "$claude_agents/reviewer.md"
antes="$(cksum < "$claude_agents/reviewer.md")"
out="$(host_claude 2>&1)"
[ "$antes" = "$(cksum < "$claude_agents/reviewer.md")" ] || malo "un perfil ajeno no se debe tocar"
printf '%s' "$out" | grep -q 'DESCONOCIDO' || malo "no reporto el estado DESCONOCIDO"

caso "claude: closer y retro NO se tocan (la fuente cubre tres roles)"
dest_listo; nuevo_claude_agents; poner_vendor closer; poner_vendor retro
antes_closer="$(cksum < "$claude_agents/closer.md")"
antes_retro="$(cksum < "$claude_agents/retro.md")"
host_claude >/dev/null 2>&1
[ "$antes_closer" = "$(cksum < "$claude_agents/closer.md")" ] || malo "closer.md se toco"
[ "$antes_retro" = "$(cksum < "$claude_agents/retro.md")" ] || malo "retro.md se toco"

caso "claude: un hash que no esta en el manifiesto NO se adopta"
dest_listo; nuevo_claude_agents; poner_vendor reviewer
printf '\n' >> "$claude_agents/reviewer.md"   # un byte de mas => otro hash
antes="$(cksum < "$claude_agents/reviewer.md")"
out="$(host_claude 2>&1)"
[ "$antes" = "$(cksum < "$claude_agents/reviewer.md")" ] || malo "un vendor no listado no se debe pisar"
printf '%s' "$out" | grep -q 'DESCONOCIDO' || malo "un vendor no listado tiene que reportarse DESCONOCIDO"

caso "claude: --host claude NO toca DEST"
dest_listo; nuevo_claude_agents
dest_ck="$(cksum < "$dest")"
host_claude >/dev/null 2>&1
[ "$dest_ck" = "$(cksum < "$dest")" ] || malo "--host claude no debe tocar DEST"
```

- [ ] **Step 2: Congelar los fixtures del vendor y generar el manifiesto**

```bash
mkdir -p tests/fixtures/vendor-agents
for r in implementer verifier reviewer closer retro; do
  cp "$HOME/.claude/agents/$r.md" "tests/fixtures/vendor-agents/$r.md"
done
# El manifiesto lista SOLO los tres roles que la fuente cubre.
for r in implementer verifier reviewer; do
  sha256sum "tests/fixtures/vendor-agents/$r.md" \
    | awk -v r="$r" '{print $1"  "r".md"}'
done > agents/vendor-manifest.sha256
cat agents/vendor-manifest.sha256
```

Los fixtures son la copia **exacta** de lo que el CLI del kit escribió. No se
editan: son la evidencia de qué se adoptó.

- [ ] **Step 3: Correr y verificar que falla**

```bash
bash tests/test_install_hook.sh
```

Esperado: FAIL, y el rojo concreto es el `exit 2` del instalador —
`--host solo acepta "zcode", "codex" o "grok"` (`tools/install-hook.sh:108`)—
porque `claude` todavía no está en la lista aceptada. **No** es
`command not found`: los casos van por la CLI.

- [ ] **Step 4: Implementar**

```bash
CLAUDE_AGENT_ROLES='implementer verifier reviewer'

claude_agents_dir() {
  printf '%s' "${SAIKIT_CLAUDE_AGENTS_DIR:-${HOME:-}/.claude/agents}"
}

# Cuarto estado, solo para los directorios del vendor (claude y kimi). El hash
# del manifiesto es la UNICA vía de adopcion: sin el, un perfil sin marca es
# DESCONOCIDO y no se toca.
agente_es_vendor_conocido() {  # $1=dest  $2=rol
  local manifiesto hash esperado
  manifiesto="$repo/agents/vendor-manifest.sha256"
  [ -r "$manifiesto" ] || return 1
  hash="$(sha256sum "$1" 2>/dev/null | cut -d' ' -f1)"
  [ -n "$hash" ] || return 1
  esperado="$(awk -v r="$2.md" '$2 == r {print $1}' "$manifiesto")"
  [ -n "$esperado" ] && [ "$hash" = "$esperado" ]
}

# Como zcode_agente_estado, mas el estado VENDOR_CONOCIDO.
agente_estado_con_vendor() {  # $1=dest  $2=traducida  $3=rol
  local dest="$1" trad="$2" rol="$3"
  if [ ! -e "$dest" ]; then printf 'AUSENTE'; return 0; fi
  if [ ! -f "$dest" ] || [ ! -r "$dest" ]; then printf 'NO_OBSERVABLE'; return 0; fi
  if zcode_agente_tiene_marca "$dest"; then
    if cmp -s "$dest" "$trad"; then printf 'NUESTRO_IDENTICO'; else printf 'NUESTRO_DISTINTO'; fi
    return 0
  fi
  if agente_es_vendor_conocido "$dest" "$rol"; then printf 'VENDOR_CONOCIDO'; return 0; fi
  printf 'DESCONOCIDO'
}

claude_instalar_agentes() {
  local dest_dir rol fuente dest trad estado
  dest_dir="$(claude_agents_dir)"

  # PRIMERO valida las TRES plantillas, DESPUES escribe. Es el orden que
  # `zcode_instalar_agentes` ya usa (dos bucles separados) y no es estilo:
  # validando y escribiendo en el mismo bucle, una plantilla invalida en el
  # tercer rol deja los dos primeros ya publicados -- una instalacion a medias.
  # La validacion de `name:` va aca tambien: sin ella, un reviewer.md cuyo
  # frontmatter diga `name: implementer` se publicaria como reviewer con el
  # modelo del implementer.
  for rol in $CLAUDE_AGENT_ROLES; do
    fuente="$repo/agents/$rol.md"
    if [ ! -f "$fuente" ] || [ ! -r "$fuente" ]; then
      decir "[summonaikit] instalador: falta la plantilla de agente $fuente"
      exit 2
    fi
    zcode_agente_tiene_marca "$fuente" || {
      decir "[summonaikit] instalador: la plantilla $fuente no lleva saikit_owned."; exit 2; }
    zcode_agente_frontmatter "$fuente" | grep -q "^name: ${rol}$" || {
      decir "[summonaikit] instalador: la plantilla $fuente no declara name: $rol."; exit 2; }
  done

  mkdir -p "$dest_dir" || {
    decir "[summonaikit] instalador: no se pudo crear $dest_dir"; exit 5; }
  for rol in $CLAUDE_AGENT_ROLES; do
    fuente="$repo/agents/$rol.md"
    dest="$dest_dir/$rol.md"
    trad="$(mktemp "${TMPDIR:-/tmp}/.saikit-trad-XXXXXX")" || exit 5
    agente_traducido claude "$fuente" > "$trad" || { rm -f "$trad"; exit 2; }
    estado="$(agente_estado_con_vendor "$dest" "$trad" "$rol")"
    case "$estado" in
      AUSENTE)
        zcode_publicar_agente "$trad" "$dest" || { rm -f "$trad"; exit 5; }
        decir "[summonaikit] AGENTE CLAUDE INSTALADO: $rol"
        ;;
      NUESTRO_IDENTICO) : ;;
      NUESTRO_DISTINTO)
        zcode_archivar_agente "$dest" || { rm -f "$trad"; exit 5; }
        zcode_publicar_agente "$trad" "$dest" || { rm -f "$trad"; exit 5; }
        decir "[summonaikit] AGENTE CLAUDE REPARADO: $rol"
        ;;
      VENDOR_CONOCIDO)
        claude_archivar_vendor "$dest" || { rm -f "$trad"; exit 5; }
        zcode_publicar_agente "$trad" "$dest" || { rm -f "$trad"; exit 5; }
        decir "[summonaikit] AGENTE CLAUDE ADOPTADO (vendor conocido): $rol"
        ;;
      DESCONOCIDO)
        decir "[summonaikit] AGENTE CLAUDE DESCONOCIDO: $rol — no se toco."
        decir "              destino: $dest"
        decir "              Ni marca ni hash de vendor conocido. Puede ser un cambio legitimo."
        ;;
      NO_OBSERVABLE)
        rm -f "$trad"
        decir "[summonaikit] instalador: no se pudo clasificar $dest."; exit 5
        ;;
    esac
    rm -f "$trad"
  done
}

# El sello `.vendor.` distingue el backup de adopcion del de reparacion
# (`.nuestro.`), igual que hace el instalador del hook.
claude_archivar_vendor() {  # $1=dest
  local dest="$1" dir backup_dir sello backup n
  dir="$(dirname "$dest")"
  backup_dir="$dir/saikit-backups"
  mkdir -p "$backup_dir" || return 1
  sello="$(date +%Y%m%d-%H%M%S)"
  backup="$backup_dir/$(basename "$dest").vendor.$sello.bak"
  n=2
  while [ -e "$backup" ]; do
    backup="$backup_dir/$(basename "$dest").vendor.$sello-$n.bak"
    n=$((n + 1))
  done
  cp "$dest" "$backup" || return 1
  cmp -s "$backup" "$dest" || return 1
  return 0
}
```

- [ ] **Step 4b: Vía de refresco del manifiesto**

Sin esto, un `saikit-update` que cambie los perfiles del vendor deja el ruteo
apagado sin ruido. La vía es **deliberadamente manual** — un `--force` que
adopte cualquier hash convierte el cuarto estado en el bypass que la máquina de
tres estados existe para evitar.

Agregar a `tools/` un modo que **reporte, no adopte**:

```bash
# tools/install-hook.sh --host claude --refrescar-manifiesto
#
# NO escribe el manifiesto. Imprime el sha256 actual de cada perfil DESCONOCIDO
# junto al diff contra la plantilla del repo, para que una persona mire el
# cambio y decida. Adoptar es pegar ese hash en agents/vendor-manifest.sha256
# en un commit propio, con el diff a la vista en la revision.
```

El caso de test: con un perfil `DESCONOCIDO` presente, el modo imprime su hash y
**el manifiesto queda byte a byte igual**.

Documentar el procedimiento en el README junto a la tabla de estados (Task 12.8).

- [ ] **Step 5: Cablear `--host claude` en el parseo de argumentos**

En la validación de `--host` (línea ~107), agregar `claude` a la lista aceptada.
`--host claude` **no** cambia `DEST` (el hook global ya vive ahí por el flujo
normal): sólo dispara `claude_instalar_agentes`.

```bash
grep -n 'host solo acepta' tools/install-hook.sh
```

- [ ] **Step 6: Correr el test y verificar que pasa**

```bash
bash tests/test_install_hook.sh
```

- [ ] **Step 7: Commit**

```bash
git add agents/vendor-manifest.sha256 tests/fixtures/vendor-agents tools/install-hook.sh tests/test_install_hook.sh
git commit -m "feat(12.6): posesion de los perfiles de claude via manifiesto de vendor"
```

- [ ] **Step 8: PR y batería en CI**

```bash
git push -u origin HEAD && gh pr create --fill
git log origin/master..HEAD --oneline
```

---

## Task 12.7: Posesión en kimi — `--host kimi`

`[Setup]` `[lane:gate]` `[tdd:required]`

**Files:**
- Modify: `tools/install-hook.sh`
- Test: `tests/test_install_hook.sh`

**Interfaces:**
- Consumes: `agente_traducido kimi <fuente>` (12.5),
  `agente_estado_con_vendor` y `claude_archivar_vendor` (12.6).
- Produces: `--host kimi` escribe `~/.agents/agents/{implementer,verifier,reviewer}.md`.
  Override de test: `SAIKIT_KIMI_AGENTS_DIR`.

**Gate de entrada: LEVANTADO.** La Task 12.3 confirmó (2026-08-18) que kimi-code
lee `~/.agents/agents/` y parsea el frontmatter. La tarea puede correr.

**Pero su alcance se achicó, y hay que decirlo antes de empezar.** La misma
medición mostró que kimi **no acepta `model:` ni `effort:` por agente**: su
parser tiene un conjunto cerrado de claves y ninguna de las dos está. Entonces:

- **Esta tarea ya NO instala ruteo.** Instala los tres perfiles con la marca
  `saikit_owned` y nada más. La fila `kimi` del router queda vacía a propósito y
  el subagente hereda del lead, como hoy.
- **Lo que sí sigue justificándola**: el archivo pasa a ser nuestro (reparable,
  versionado, con la misma máquina de estados que los otros hosts) y se le saca
  el `model: sonnet` del vendor, que afirma algo falso.
- **La urgencia bajó**: ese `model: sonnet` es **inerte**, no un defecto activo.
  Si hay que priorizar, esta tarea va última.

**Riesgo específico de este host, medido en la 12.3:** un valor inválido en una
clave *conocida* no falla ruidoso — el archivo deja de parsear y **el agente
desaparece del registro sin error visible**. Por eso el test de esta tarea no
alcanza con verificar que el archivo se escribió: tiene que verificar que **el
tipo sigue resolviendo**.

**`~/.agents/` no es de un solo host.** El directorio tiene `agents/`, `hooks/`,
`plugins/` y `skills/`, y es la convención compartida del kit. El guard es
estricto: sólo se tocan los tres `<rol>.md` que la fuente cubre. Nada de borrar
el directorio ni de iterar lo que haya.

- [ ] **Step 1: Escribir los casos que fallan**

Los mismos siete casos de la Task 12.6, con el helper análogo:

```bash
kimi_agents=''
n_ka=0
nuevo_kimi_agents() {
  n_ka=$((n_ka + 1))
  kimi_agents="$tmp/kagents-$n_ka"
  rm -rf "$kimi_agents"; mkdir -p "$kimi_agents"
}
host_kimi() {
  SAIKIT_KIMI_AGENTS_DIR="$kimi_agents" bash "$tool" --host kimi --dest "$dest" "$@"
}
```

Más estos dos, que son propios del host:

```bash
caso "kimi: al adoptar se saca el model: sonnet del vendor (higiene)"
# NO es la correccion de un defecto activo: la 12.3 midio que kimi ignora la
# clave `model` por completo, asi que ese valor es INERTE. Se saca porque el
# archivo afirma algo falso, no porque cambie el comportamiento.
dest_listo; nuevo_kimi_agents
cp "$repo/tests/fixtures/vendor-agents/reviewer.md" "$kimi_agents/reviewer.md"
grep -q '^model: sonnet$' "$kimi_agents/reviewer.md" \
  || malo "el fixture del vendor deberia traer model: sonnet (es lo que hay hoy en disco)"
host_kimi >/dev/null 2>&1
grep -q '^model: sonnet$' "$kimi_agents/reviewer.md" \
  && malo "sigue el model: sonnet del vendor despues de adoptar"

caso "kimi: el perfil instalado NO lleva model: ni effort:"
# La fila kimi del router esta vacia a proposito (12.3): el host no acepta esas
# claves. Escribirlas seria poner en el archivo algo que el runtime ignora --
# exactamente la mentira que el resto del spec persigue.
grep -q '^model:'  "$kimi_agents/reviewer.md" && malo "kimi no debe llevar model:"
grep -q '^effort:' "$kimi_agents/reviewer.md" && malo "kimi no debe llevar effort:"

caso "kimi: el frontmatter instalado SIGUE PARSEANDO (el tipo no puede desaparecer)"
# El modo de falla medido en la 12.3: un valor invalido en una clave conocida no
# da error -- el agente se cae del registro en silencio. Un test que solo mire
# que el archivo existe no lo atrapa. Se verifica contra el contrato del parser:
# claves permitidas y, si aparece model_preference, su valor.
for rol in implementer verifier reviewer; do
  fm="$(sed -n '/^---/,/^---/p' "$kimi_agents/$rol.md" | sed '1d;$d')"
  printf '%s' "$fm" | grep -q "^name: ${rol}\$"   || malo "$rol: falta name: correcto"
  printf '%s' "$fm" | grep -q '^description:'     || malo "$rol: falta description (el parser la exige)"
  mp="$(printf '%s' "$fm" | sed -n 's/^model_preference: //p')"
  case "${mp:-primary}" in
    primary|secondary) ;;
    *) malo "$rol: model_preference invalido ($mp) — el agente desaparece del registro" ;;
  esac
done

caso "kimi: no se toca nada fuera de los tres roles"
dest_listo; nuevo_kimi_agents
printf 'ajeno\n' > "$kimi_agents/otro-agente.md"
mkdir -p "$kimi_agents/../skills" && printf 'ajeno\n' > "$kimi_agents/../skills/x.md"
antes_a="$(cksum < "$kimi_agents/otro-agente.md")"
antes_s="$(cksum < "$kimi_agents/../skills/x.md")"
host_kimi >/dev/null 2>&1
[ "$antes_a" = "$(cksum < "$kimi_agents/otro-agente.md")" ] || malo "un agente ajeno se toco"
[ "$antes_s" = "$(cksum < "$kimi_agents/../skills/x.md")" ] || malo "se toco algo fuera de agents/"
```

El segundo caso mira **fuera** de `agents/` a propósito: `~/.agents/` es la
convención compartida del kit y tiene `hooks/`, `plugins/` y `skills/` al lado.
Un instalador que itere el directorio padre rompe cosas que no son suyas.

- [ ] **Step 2: Correr y verificar que falla**

```bash
bash tests/test_install_hook.sh
```

- [ ] **Step 3: Implementar**

```bash
KIMI_AGENT_ROLES='implementer verifier reviewer'

kimi_agents_dir() {
  printf '%s' "${SAIKIT_KIMI_AGENTS_DIR:-${HOME:-}/.agents/agents}"
}
```

`kimi_instalar_agentes()` es la misma forma que `claude_instalar_agentes()` con
`kimi_agents_dir` y `agente_traducido kimi`. **Si las dos funciones quedan
idénticas salvo host y directorio, unificalas** en
`instalar_agentes_con_vendor <host> <dest_dir> <etiqueta>` y que las dos la
llamen: dos copias del mismo bucle es cómo se arregla una sola.

- [ ] **Step 4: Cablear `--host kimi` en el parseo de argumentos**

Agregar `kimi` a la lista aceptada de `--host`. No cambia `DEST`.

- [ ] **Step 5: Sellar la fila `kimi` del router como vacía DEFINITIVA**

Este step reemplaza al que decía "llenar la fila". La 12.3 midió que no hay nada
que llenar: kimi no acepta modelo ni effort por agente. Pero la fila no puede
quedar como un `: ;;` mudo — un lector futuro lo leería como "pendiente de
medir" y volvería a intentarlo.

En `tools/model-routing.sh`, dejar la rama del host con la razón escrita:

```bash
  kimi)
    # Fila VACIA DEFINITIVA, no pendiente. Medido en la Task 12.3
    # (docs/task-12.3-medicion.md, kimi-code 0.34.0): el parser de agentes
    # acepta un conjunto CERRADO de claves --name, description, whenToUse,
    # override, tools, disallowedTools, subagents, model_preference-- y ni
    # `model` ni `effort` estan. La unica palanca es model_preference, que
    # admite solo "primary"|"secondary": dos slots, no un ID de modelo.
    # Escribir aca un modelo seria emitir una clave que el host ignora.
    : ;;
```

Y en `tests/test_model_routing.sh`, el caso de "fila vacía" pasa a nombrar a
`kimi` como permanente en vez de provisorio:

```bash
caso "la fila de kimi esta vacia de forma DEFINITIVA (12.3), no pendiente"
igual "" "$(bash "$router" --host kimi --role reviewer --field model)"  "kimi/model"
igual "" "$(bash "$router" --host kimi --role reviewer --field effort)" "kimi/effort"
igual "" "$(bash "$router" --host kimi --role implementer --format frontmatter)" "kimi/frontmatter"
```

- [ ] **Step 6: Correr el test y verificar que pasa**

```bash
bash tests/test_install_hook.sh
```

- [ ] **Step 7: Commit**

```bash
git add tools/install-hook.sh tests/test_install_hook.sh
git commit -m "feat(12.7): posesion de los perfiles de kimi en ~/.agents/agents"
```

- [ ] **Step 8: PR y batería en CI**

```bash
git push -u origin HEAD && gh pr create --fill
git log origin/master..HEAD --oneline
```

---

## Task 12.8: Spec, ledger y README

`[Setup]` `[lane:fast]`

**Files:**
- Modify: `docs/spec/00-project-spec.md`
- Modify: `Plans.md`
- Modify: `README.md`

**Interfaces:**
- Consumes: los hechos que midieron y cerraron 12.1–12.7.
- Produces: nada que otra tarea consuma. Es la última.

- [ ] **Step 1: Delta de producto en el spec**

Agregar una sección `### Ampliación de propiedad — Phase 12`, con:

- **La reapertura, declarada.** Este repo pasa a ser dueño de los perfiles de
  agente en `claude` y `kimi`. Es el mismo movimiento que la Phase 6 al reabrir
  `.codex`; se escribe con su razón y su vuelta atrás.
- **Qué compra la posesión y qué no.** El CLI del kit puede volver a escribir
  esos perfiles en cualquier `saikit-update`. La posesión hace que la siguiente
  corrida del instalador lo **detecte y repare**. Es reparación, no
  exclusividad.
- **Los límites**, uno por línea con su razón: `closer` y `retro` siguen con
  el `model: sonnet` del vendor (la fuente cubre tres roles y la posesión es por
  archivo); Codex queda fuera; Fable 5 fuera del ruteo automático; `effort` sólo
  donde se midió.
- **Los hechos medidos por 12.1/12.2/12.3**, cada uno con su fecha y su tarea,
  siguiendo el formato de las secciones `### Medido AAAA-MM-DD, Task N.N`.

- [ ] **Step 2: Ledger en `Plans.md`**

Agregar la sección de la fase después de la Phase 11, con la tabla en el formato
del repo:

```markdown
## Phase 12 — Ruteo de modelo y effort por rol (2026-08-17)

**Propósito:** que el gasto siga al riesgo. Hoy los cinco perfiles del kit dicen
`model: sonnet` y ninguno declara `effort`: un reviewer que decide si un diff
cierra corre en el mismo tier que un verifier que corre comandos. Diseño en
`docs/phase-12-model-routing-design.md`.

| Task | 内容 | DoD | Depends | Status |
|------|------|-----|---------|--------|
| 12.1 | `[Test]` `[lane:gate]` `[tdd:required]` **Medición zcode.** ¿El loader de agentes honra `model:` y `effort:` en frontmatter, qué hace con un valor desconocido, y cuál es el catálogo real de la cuenta? Vía: inspección de `zcode.cjs`, la misma que usó la 5.6. El catálogo que hoy se conoce (`glm-4.6`, `5-turbo`, `5.1`, `5.2`, `5.3`) salió de un grep a `db.sqlite`: son menciones históricas, no el catálogo de la cuenta | `docs/task-12.1-medicion.md` responde las cuatro preguntas, cada una con la cita del bundle que la sostiene; lo que no se pudo observar queda declarado **no observado**; huella de `~/.zcode/agents` idéntica antes y después | — | TODO |
| 12.2 | `[Test]` `[lane:gate]` `[tdd:required]` **Medición grok.** Las mismas cuatro preguntas por captura headless estilo 7.1 sobre repo descartable, con un perfil sonda que lleva `model:`/`effort:` y una segunda corrida con un ID inexistente | `docs/task-12.2-medicion.md` con los dos logs; el catálogo del harness (`grok-4.5`, `grok-composer-2.5-fast`, 2026-07-09) se **confirma contra esta cuenta, no se hereda**; perfil `~/.grok` byte a byte intacto (cksum antes/después) y trust del repo descartable declarado y revocado | — | TODO |
| 12.3 | `[Test]` `[lane:gate]` `[tdd:required]` **Medición kimi — CERRADA.** `kimi.exe` son ~141 MB compilados: no hay inspección estática, va captura viva. Antes que nada confirma la premisa que sostiene toda la fila — que kimi-code **lee** `~/.agents/agents/`, hoy inferido del literal `.agents/**` en el binario más los perfiles en disco. Incluye qué hace hoy con el `model: sonnet` que el kit ya tiene plantado ahí | `docs/task-12.3-medicion.md`. Premisa CONFIRMADA (kimi lee ese directorio y parsea el frontmatter), pero el host **no acepta `model:` ni `effort:` por agente**: parser con claves cerradas, única palanca `model_preference` ∈ {primary, secondary}. Fila `kimi` vacía **definitiva**. Hallazgo extra: un valor inválido en clave conocida borra el agente del registro sin error. `~/.agents/agents/` byte a byte idéntico | — | **cc:完了** |
| 12.4 | `[Feature]` `[lane:gate]` `[tdd:required]` **`tools/model-routing.sh`**: `rol → tier → (modelo, effort)` por host, único lugar del repo con IDs de modelo. Nace con la fila `claude` completa y las otras tres vacías. Diverge del router del harness en un punto obligado: acá los scripts corren con `set -u` **sin** `-e`, donde un `exit 2` adentro de `$( )` deja la variable vacía y sigue — las funciones devuelven código y el llamador lo chequea | `tests/test_model_routing.sh` en verde con la tabla de claude valor por valor, `exit 2` en host/rol/tier desconocido **sin imprimir por stdout**, fila vacía ⇒ stdout vacío con exit 0, el caso de la trampa de `set -u`, y el candado de que ningún ID de modelo vive fuera del router | — | TODO |
| 12.5 | `[Feature]` `[lane:gate]` `[tdd:required]` **Traducción por host e inyección.** `grok_agente_traducido` → `agente_traducido <host> <fuente>`: omite lo que el host no acepta e inyecta `model:`/`effort:` del router. **En el mismo cambio**, zcode pasa a clasificar y publicar contra la plantilla **traducida**: hoy compara contra la cruda y con inyección reescribiría el perfil en cada corrida, dejando un backup cada vez | `tests/test_install_hook.sh` en verde por la CLI (nunca sourceando el instalador): inyección dentro del primer bloque frontmatter y una sola vez, fila vacía ⇒ sin clave, `skills:` sigue omitido en grok, y **dos corridas seguidas no reescriben ni dejan backup**. Costura `SAIKIT_MODEL_ROUTING_TOOL` para probar la inyección con filas llenas | 12.1, 12.2, 12.4 | TODO |
| 12.6 | `[Setup]` `[lane:gate]` `[tdd:required]` **Posesión en claude.** `--host claude` escribe los tres perfiles en `~/.claude/agents/`. Los del vendor no llevan `saikit_owned`, así que sin vía de adopción quedarían `DESCONOCIDO` para siempre: se agrega el cuarto estado **`VENDOR_CONOCIDO`** por hash en `agents/vendor-manifest.sha256`, el mismo mecanismo que el instalador del hook ya usa | Los cinco estados con su caso: `AUSENTE` instala con el modelo ruteado y la marca, dos corridas no reescriben, `VENDOR_CONOCIDO` archiva (`.vendor.<sello>.bak`) y reemplaza, `DESCONOCIDO` **no toca y reporta**, un hash fuera del manifiesto **no se adopta**, `closer`/`retro` intactos, y `--host claude` no toca DEST | 12.4, 12.5 | TODO |
| 12.7 | `[Setup]` `[lane:gate]` **Posesión en kimi — alcance REDUCIDO por la 12.3.** No instala ruteo (el host no lo acepta): sólo toma posesión del archivo con la marca y saca el `model: sonnet` del vendor, que está **inerte**. `--host kimi` escribe los tres perfiles en `~/.agents/agents/`, reusando el cuarto estado de la 12.6. `~/.agents/` es la convención compartida del kit (tiene `hooks/`, `plugins/`, `skills/` al lado): se tocan **sólo** los tres `<rol>.md`, nunca el directorio | Los siete casos de la 12.6 más dos propios: la fuga de `model: sonnet` del vendor queda cerrada tras adoptar, y nada fuera de los tres roles se toca — incluido un archivo en `../skills/`. Más un caso propio del host: que el frontmatter instalado **siga parseando**, porque un valor inválido tira el agente del registro en silencio (12.3) | 12.6 | TODO |
| 12.8 | `[Setup]` `[lane:fast]` **Spec, ledger y README.** Declara la reapertura de propiedad sobre los perfiles de `claude` y `kimi` con su razón y su vuelta atrás, qué compra la posesión (reparación, **no** exclusividad frente a un `saikit-update`), y los límites uno por línea | El spec incorpora los hechos medidos por 12.1/12.2/12.3 con su fecha y tarea, en el formato `### Medido AAAA-MM-DD, Task N.N`; `Plans.md` con las 8 filas cerradas; README con `--host claude`/`--host kimi` y el estado `VENDOR_CONOCIDO`; `python tools/check_context_docs.py . --sweep` sin hallazgos nuevos | 12.1–12.7 | TODO |
```

Los DoD son medibles a propósito: cada uno nombra el archivo o el caso que lo
prueba, no el relato de lo que se hizo.

- [ ] **Step 3: README**

En la tabla de instalación, agregar las dos filas nuevas:

```markdown
bash tools/install-hook.sh --host claude   # perfiles de agente en ~/.claude/agents
bash tools/install-hook.sh --host kimi     # perfiles de agente en ~/.agents/agents
```

Con la nota de qué hace cada estado, incluido **`VENDOR_CONOCIDO`**: hash en
`agents/vendor-manifest.sha256` ⇒ archiva y reemplaza; hash desconocido ⇒ no se
toca.

- [ ] **Step 4: Higiene de docs de contexto**

```bash
python tools/check_context_docs.py . --sweep
```

Reporta, no borra. Si señala algo, podalo antes de cerrar.

- [ ] **Step 5: Commit**

```bash
git add docs/spec/00-project-spec.md Plans.md README.md
git commit -m "docs(12.8): spec, ledger y README de la Phase 12"
```

- [ ] **Step 6: PR final y batería completa en CI**

```bash
git push -u origin HEAD && gh pr create --fill
git log origin/master..HEAD --oneline
```

---

## Orden sugerido y paralelismo

| Tarea | Estado | Depende de | Puede correr en paralelo con |
|---|---|---|---|
| 12.3 (med. kimi) | **CERRADA 2026-08-18** | — | — |
| 12.4 (router) | pendiente | — | 12.1, 12.2 |
| 12.1 (med. zcode) | pendiente | — | 12.2, 12.4 |
| 12.2 (med. grok) | pendiente | — | 12.1, 12.4 |
| 12.5 (traducción) | pendiente | 12.1, 12.2, 12.4 | — |
| 12.6 (claude) | pendiente | 12.4, 12.5 | — |
| 12.7 (kimi) | pendiente, **alcance reducido** | 12.6 | — |
| 12.8 (docs) | pendiente | todas | — |

Las mediciones que quedan (12.1, 12.2) son independientes entre sí y del router:
tres tareas pueden correr en paralelo.

**12.7 ya no depende de 12.3** (cerrada) y bajó de prioridad: al no haber ruteo
posible en kimi, su único aporte es la posesión del archivo y sacar un
`model: sonnet` que está inerte. Si hay que recortar la fase, es la primera
candidata a diferir.

## Qué NO hace este plan

- No toca `hooks/summonaikit-harness.sh`.
- No agrega `model:` a `agents/*.md`. La fuente sigue sin IDs de modelo.
- No crea variantes de perfil (`implementer-light`, etc.).
- No entra Codex.
- No rutea `closer` ni `retro`.
- **No rutea `kimi`** (medido 12.3): el host no acepta modelo ni effort por
  agente. Llevarlo a `model_preference` + `[secondaryModel]` daría dos niveles,
  no tres, y es una decisión de producto que esta fase no toma.
- No promete que el CLI del kit deje de pisar los perfiles.
