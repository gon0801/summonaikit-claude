# Phase 12 — Ruteo de modelo y effort por rol

Fecha: 2026-08-17

Diseño aprobado. El ledger de tareas sale de acá y vive en `Plans.md`; el delta
de producto aprobado para esta fase se incorpora a `docs/spec/00-project-spec.md`.
Cada tarea agrega allí sólo los hechos que mida al cerrar.

Ubicación del archivo: `docs/` plano, como el resto de los planes de este repo
(`phase-6-codex-design.md`, `phase-7-grok-design.md`). Se mantiene la decisión
que fijó la Phase 6: no se abre `docs/superpowers/specs/`.

## Purpose

Que cada rol de la ceremonia corra en el modelo y el nivel de esfuerzo que le
corresponde, en los cuatro hosts que instalan perfiles, en vez de correr todos
en el mismo modelo plano.

Hoy los cinco perfiles del kit dicen `model: sonnet` en `~/.claude/agents/` y en
`~/.agents/agents/`, y ninguno declara `effort`. Un reviewer que decide si un
diff cierra corre en el mismo tier que un verifier que corre comandos y lee la
salida. El gasto no sigue al riesgo.

**Esto reabre una frontera.** Los perfiles de agente en `claude` y `kimi` los
escribe hoy el CLI autenticado del kit, no este repo. La fase toma posesión de
ellos con el mismo mecanismo de tres estados y manifiesto de vendor que el
instalador ya usa para el hook. Es el mismo movimiento que la Phase 6 hizo al
reabrir `.codex`: se declara, no se hace en silencio.

## Premisas medidas (2026-08-17, no supuestas)

Estas mediciones son la base del alcance. Si alguna cae, la fase se re-planifica.

### Dónde vive el perfil de cada host

| Host | Mecanismo de subagente | Directorio de perfiles | Quién lo escribe hoy | `model` hoy |
|---|---|---|---|---|
| `claude` | `Task` | `~/.claude/agents/` | el CLI del kit | `model: sonnet` |
| `zcode` (GLM) | Agent tool, **sólo tipos registrados** | `~/.zcode/agents/` | `install-hook.sh --host zcode` (Task 5.6) | ninguno |
| `grok` | `spawn_subagent` | `~/.grok/agents/` | `install-hook.sh --host grok` (Task 7.5) | ninguno |
| `kimi` | `Agent` + `SubagentStart`/`SubagentStop` | `~/.agents/agents/` | el CLI del kit | `model: sonnet` |

`~/.zcode/agents/` verificado en disco: `implementer.md`, `reviewer.md`,
`verifier.md`, los tres con `saikit_owned: summonaikit-claude` en frontmatter y
**sin** `model:`. `~/.agents/agents/` verificado en disco: los cinco perfiles
(`implementer`, `verifier`, `reviewer`, `closer`, `retro`), los cinco con
`model: sonnet`.

La ruta `.agents/**` aparece como literal en `~/.kimi-code/bin/kimi.exe`, y
`~/.agents/agents/` existe en disco con esos cinco perfiles. Que kimi-code los
**lea** es inferencia de esas dos señales, no una carga observada: la 12.3 lo
mide.

### La ausencia de `model:` en la fuente del repo es deliberada

`agents/*.md` de este repo no lleva `model:`. No es drift. Lo fijó la Task 5.6 y
está en el spec:

> *No se copia de `~/.claude/agents`. Esa ruta es del otro host y lleva
> `model: sonnet`. La fuente versionada es `agents/*.md` (sin `model:`;
> heredan GLM del padre).*

Una fuente compartida por varios hosts no puede llevar un ID de modelo: los
nombres son de cada host. Ese es el hecho que obliga a que el valor se resuelva
en la instalación y no en la plantilla.

### Ya hay una fuga de modelo cross-host, hoy, en producción

`~/.agents/agents/*.md` — el directorio asociado a kimi-code — trae
`model: sonnet` en los cinco perfiles. `sonnet` no es un modelo de Kimi. Qué
hace kimi-code con ese valor (lo ignora, lo respeta, falla) **no está medido**.
El defecto contra el que esta fase diseña ya existe.

### Kimi tiene effort, pero no por agente

`~/.kimi-code/config.toml`, medido:

```toml
[models."kimi-code/k3"]
max_context_size = 1048576
support_efforts = [ "low", "high", "max" ]
default_effort  = "high"
```

Es **por modelo y global**, no por agente. Si kimi no honra un `effort:` de
frontmatter, ese host recibe sólo `model:` y el límite se declara.

### La costura de traducción ya existe

`tools/install-hook.sh` ya traduce frontmatter por host:

```sh
grok_agente_traducido() {  # $1=fuente → stdout
  awk '
    /^---[[:space:]]*\r?$/ { n++; print; next }
    n == 1 && /^skills:/ { next }
    { print }
  ' "$1"
}
```

Hoy sólo omite `skills:` (el loader de Grok lo exige como secuencia y la fuente
lo declara como string). El punto de inyección de `model:`/`effort:` es ese
mismo, generalizado. No hay que inventar un mecanismo.

### El gate acredita las variantes de nombre por substring

`canonical_agent_role()` mapea por substring. Ejecutado contra la función del
hook vivo:

```
implementer-light   -> [implementer]
haiku-implementer   -> [implementer]
reviewer-cheap      -> [reviewer]
verifier-fast       -> [verifier]
sonnet-worker       -> []
```

Se registra como hecho medido aunque esta fase **no** use variantes: si alguna
vez se agregan, el gate ya las acredita, siempre que el nombre conserve la
palabra del rol.

### La referencia: la política del harness

`claude-code-harness` 5.6.0 tiene una política adoptada (2026-06-11) en
`docs/model-routing-policy.md`, implementada en `scripts/model-routing.sh` y
cubierta por `tests/test-model-routing.sh`. Su decisión:

> **Use explicit role tiers, not prompt-text inference.**
> *Do not infer effort from free-text markers such as "think harder".*
> Non-Goal: *Do not route by vague prompt words.*

Forma: `role → tier → (model, effort)` por host, con los IDs de modelo viviendo
sólo en el router (*"Keep model IDs only here — skills must not hardcode them"*),
`exit 2` ante host/tier/rol desconocido, y prioridad de override declarada
(caller explícito > default ruteado > herencia).

Este repo ya tomó la misma decisión por su cuenta, en otro eje, en la Task 10.1:

> *el sentinel es la única condición de armado, y el carril fast **NO se infiere
> de regex de trivialidad** — se pide explícito (`-saikit:fast`).*

## Decisiones

### D1 — Se rutea por ROL, no por dificultad de tarea

El pedido original era subir el modelo en tareas difíciles y bajarlo en las
fáciles. **Se descarta**, por tres razones convergentes:

1. La política del harness lo declara Non-Goal explícito.
2. La Task 10.1 de este repo ya rechazó inferir trivialidad del texto del turno.
3. El gate es fail-open y no puede verificar que una clasificación de dificultad
   sea honesta. Un ruteo que el modelo elige y nadie audita es un ruteo que
   optimiza el gasto del modelo, no el del operador.

El eje que queda es el rol, que es estable, declarado, y ya lo exige la
ceremonia.

Consecuencia: **siguen siendo tres perfiles por host**, no nueve. Sólo cambia
qué modelo y qué effort lleva cada uno.

### D2 — `tools/model-routing.sh`, espejo recortado del router del harness

```
role → tier → (model, effort)   por host

implementer → standard
verifier    → verify
reviewer    → review
*           → exit 2
```

Interfaz:

```
tools/model-routing.sh --host claude|zcode|grok|kimi \
                       --role implementer|verifier|reviewer \
                       [--tier standard|verify|review] \
                       [--field model|effort] \
                       [--format json|frontmatter]
```

Se copian del harness las tres propiedades que lo hacen mantenible, y que además
coinciden con reglas que este repo ya tiene:

- **Los IDs de modelo viven sólo en el router.** Ni el instalador ni las
  plantillas los nombran.
- **Sin fallback silencioso**: host, rol o tier no reconocido ⇒ `exit 2`. Es
  Core Rule 2 (*un valor no reconocido no es evidencia de nada*).
- **Prioridad de override declarada**: caller explícito > default ruteado >
  herencia del padre.

Se recorta la lista de tiers del harness (`lite`, `standard`, `deep`, `review`,
`advisor`, `release`, `long-context`, `spark`) a los tres que esta fase usa.
Un tier que ningún rol mapea no se define.

`verify` no existe en el harness — el harness no tiene rol verifier. Se define
acá: modelo del tier `standard` con effort bajo. El verifier corre comandos y
lee salida (orquestación), pero también inspecciona el diff buscando errores
tragados y guardas faltantes (juicio). Bajar el effort captura el ahorro sin
bajar de modelo, y evita el techo de contexto del tier más barato.

### D3 — La tabla por host, y qué significa una celda vacía

| tier | claude | zcode (GLM) | grok | kimi |
|---|---|---|---|---|
| `standard` | `claude-sonnet-5` / `medium` | 12.1 | 12.2 | 12.3 |
| `verify` | `claude-sonnet-5` / `low` | 12.1 | 12.2 | 12.3 |
| `review` | `claude-opus-5` / `xhigh` | 12.1 | 12.2 | 12.3 |

**Una celda sin valor ⇒ la clave se omite del perfil ⇒ el agente hereda del
padre.** Ese es exactamente el comportamiento que zcode tiene hoy y que la 5.6
midió como correcto. Hasta que una medición llene su fila, ese host queda igual
que ahora. El cambio es aditivo: ningún host empeora por esperar su medición.

`review` en claude usa **Opus 5**, no Fable 5. El harness rutea review a Fable 5
por decisión de operador (2026-07-25). Acá se diverge a propósito: Fable 5 son
$10/$50 por millón contra $5/$25 de Opus 5 — el doble en salida — y el propio
skill `claude-api` fija `xhigh` como el mejor setting para trabajo de código y
agéntico. Fable queda disponible como escalada manual, fuera del ruteo
automático: una ruta automática al tier más caro es cómo se llega a una factura
que nadie decidió.

Precios de referencia (API first-party, del skill `claude-api`, cacheados
2026-06-24): Fable 5 $10/$50, Opus 5 $5/$25, Sonnet 5 $3/$15 ($2/$10 intro hasta
2026-08-31), Haiku 4.5 $1/$5 con 200K de contexto contra 1M de los otros tres.
Bajo suscripción no llega esa factura; los ratios se traducen a consumo de
límites de uso y siguen valiendo.

### D4 — La inyección va en la traducción de frontmatter, y zcode tiene que comparar contra la traducida

`grok_agente_traducido()` se generaliza a `agente_traducido <host> <fuente>`:
omite `skills:` donde el host lo exija, e inyecta `model:`/`effort:` desde el
router.

**Defecto que este cambio introduce si no se corrige en el mismo paso:** grok ya
clasifica los tres estados contra la plantilla **traducida**
(`grok_agente_estado "$dest" "$(grok_agente_traducido "$fuente")"`), pero zcode
compara contra la plantilla **cruda**. Con valores por host inyectados, esa
comparación daría `NUESTRO_DISTINTO` en cada corrida y reescribiría el perfil
siempre, con backup cada vez. zcode pasa a comparar contra la traducida, con su
caso en la suite.

### D5 — Posesión en `claude` y `kimi` vía manifiesto de vendor

`--host claude` escribe en `~/.claude/agents/`; `--host kimi`, en
`~/.agents/agents/`. Los dos con la máquina de tres estados que ya existe.

El problema: esos archivos no llevan `saikit_owned`, así que la máquina los
clasifica `DESCONOCIDO` y — correctamente — **no los toca**. Sin una vía de
adopción, la posesión no ocurre nunca.

La vía es la que el instalador ya tiene para el hook: **`agents/vendor-manifest.sha256`**.
Hash conocido del vendor ⇒ archivar y reemplazar. Hash desconocido ⇒ plantarse y
reportar, sin escribir. Es el mismo contrato de tres estados, aplicado a otro
archivo. No se inventa nada y no se destruye en silencio el cambio de nadie.

Efecto colateral que cierra: la fuga de `model: sonnet` en `~/.agents/agents/`
para los tres roles que la fuente cubre.

**Qué pasa con `closer` y `retro`.** Los directorios del vendor traen cinco
perfiles (`~/.agents/agents/`) y seis (`~/.claude/agents/`, que suma
`loop-verifier`); la fuente versionada de este repo cubre **tres**
(`implementer`, `verifier`, `reviewer`), porque la 5.6 ya decidió que el gate
pide `closer` y `retro` como secciones del recibo, no como tipos del Agent tool.
La posesión es **por archivo, no por directorio**: el instalador escribe los tres
que tiene y deja los demás como `DESCONOCIDO`, intactos y reportados. Consecuencia
declarada: `closer.md` y `retro.md` **siguen diciendo `model: sonnet`** después
de esta fase, incluido en `~/.agents/agents/`, que es de kimi. Cerrarlo exige
decidir antes si esos dos roles deben ser tipos de agente o quedarse como
secciones del recibo — es una tarea propia, no un arreglo al pasar.

**Advertencia a declarar en el spec:** el CLI del kit puede volver a escribir
esos perfiles en un `saikit-update` posterior. La posesión no impide la
sobrescritura; hace que la siguiente corrida del instalador la detecte y la
repare. Es reparación, no exclusividad.

### D6 — Codex queda fuera

No tiene instalación de perfiles de agente y su ceremonia sigue condicionada a lo
que mida la 6.1. Se declara como límite conocido, no como pendiente. Traerlo es
una fase propia, y arranca por medir si Codex tiene una herramienta de
subagentes que transporte el rol.

### D7 — El hook no se toca

Todo el ruteo ocurre en tiempo de instalación, escribiendo frontmatter. No hay
cambios en `hooks/summonaikit-harness.sh`, en el contrato inyectado, ni en
ninguna condición de bloqueo. El gate no puede regresionar por esta fase.

Consecuencia operativa: **re-rutear es re-instalar.** No hay resolución en
runtime. A cambio, el ruteo queda auditable en disco y sin dependencia viva.

## Medición primero — 12.1, 12.2, 12.3

Ninguna toca el hook de producto ni el perfil global de un host que no sea el
suyo. Valen aunque el resto de la fase se cancele, igual que 5.1/5.2/6.1/7.1.

Cada una responde las mismas cuatro preguntas, cada una con una decisión
colgando:

| Pregunta | Qué decide |
|---|---|
| ¿El loader acepta `model:` en frontmatter? | Si el host recibe ruteo de modelo |
| ¿Acepta `effort:`? | Si el host recibe ruteo de effort o sólo de modelo |
| ¿Qué hace con un valor desconocido — lo ignora, falla, o cae a un default? | Si un ID equivocado es inerte o rompe el turno |
| ¿Cuál es el catálogo real de la cuenta? | Los valores de la fila del host |

Vía de medición por host, elegida por lo que cada uno permite:

- **12.1 — zcode.** Inspección de `zcode.cjs`, la misma vía que la 5.6 usó para
  verificar que `saikit_owned` y `skills:` no rompen el loader. Catálogo: los
  IDs `glm-4.6`, `glm-5-turbo`, `glm-5.1`, `glm-5.2`, `glm-5.3` salieron de un
  grep contra `~/.zcode/cli/db/db.sqlite` — **evidencia débil**, hay que
  confirmar cuáles ofrece la cuenta.
- **12.2 — grok.** Captura headless estilo 7.1 sobre repo descartable. El
  harness observó `grok-4.5` y `grok-composer-2.5-fast` (2026-07-09, CLI
  0.2.93); el catálogo de esta cuenta se confirma, no se hereda.
- **12.3 — kimi.** `kimi.exe` son ~141 MB compilados: no hay inspección estática
  equivalente a `zcode.cjs`, así que va **captura viva**. Catálogo de
  `config.toml`: `kimi-code/k3` (1M de contexto), `k3-256k`,
  `kimi-for-coding`, `kimi-for-coding-highspeed`.

**Condición no negociable:** los valores de la tabla D3 salen de estas
mediciones, no de documentación ni de inferencia. Un host cuya medición no
cierre queda con su fila vacía y hereda del padre — que es su comportamiento de
hoy.

## Arquitectura resultante

```
agents/*.md                      fuente única, sin IDs de modelo
   │
   ├── tools/model-routing.sh    role → tier → (model, effort) por host
   │                             IDs de modelo SÓLO acá
   ▼
tools/install-hook.sh
   agente_traducido <host> <fuente>
   │  omite skills: donde el host lo exija
   │  inyecta model:/effort: desde el router
   ▼
~/.claude/agents/    ~/.zcode/agents/    ~/.grok/agents/    ~/.agents/agents/
   (D5, manifiesto)     (5.6)               (7.5)              (D5, manifiesto)
```

| Host | Perfiles escritos por | Adopción | Estado de la fila |
|---|---|---|---|
| `claude` | `--host claude` (nuevo) | manifiesto de vendor | completa |
| `zcode` | `--host zcode` (5.6) | ya es nuestro | pendiente 12.1 |
| `grok` | `--host grok` (7.5) | ya es nuestro | pendiente 12.2 |
| `kimi` | `--host kimi` (nuevo) | manifiesto de vendor | pendiente 12.3 |
| `codex` | — | fuera de alcance (D6) | — |

## Tests

`tests/test_model_routing.sh`:

- La tabla completa rol → tier → (modelo, effort) por host, valor por valor.
- `exit 2` en host desconocido, rol desconocido y tier desconocido — los tres,
  cada uno con su caso.
- Ningún ID de modelo aparece fuera de `tools/model-routing.sh` (candado de la
  regla que hace mantenible al router).
- Una fila vacía omite la clave en vez de escribir un valor vacío.

En la suite del instalador, casos nuevos para:

- Los tres estados de zcode comparando contra la plantilla **traducida** (D4).
- Los tres estados de `--host claude` y `--host kimi`, incluyendo
  `DESCONOCIDO ⇒ no se toca` y `vendor conocido ⇒ archiva y reemplaza` (D5).

## Non-Goals y límites declarados

- **No se rutea por dificultad de tarea** (D1). El eje es el rol.
- **No se agregan variantes de perfil** (`implementer-light`, etc.). El gate ya
  las acreditaría, pero triplicarían la superficie de instalación sin un eje que
  las use.
- **No entra Codex** (D6).
- **No se toca el hook** (D7).
- **No se promete exclusividad sobre los perfiles del vendor** (D5): el
  instalador repara, no impide que el CLI del kit escriba.
- **`closer` y `retro` no se rutean** (D5): la fuente cubre tres roles y la
  posesión es por archivo. Los dos quedan con el `model: sonnet` del vendor.
- **Fable 5 queda fuera del ruteo automático** (D3), disponible como escalada
  manual.
- **`effort` fuera de claude no se escribe hasta medirlo.** Un `effort:` que el
  host ignora deja el perfil diciendo una cosa y el runtime haciendo otra — el
  tipo exacto de mentira que el resto de este spec persigue.
