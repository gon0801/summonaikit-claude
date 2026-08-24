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

**Medido 2026-08-18 (Task 12.3, `docs/task-12.3-medicion.md`):** kimi-code
**sí lee** `~/.agents/agents/`. Ya no es inferencia — un perfil sonda instalado
ahí resolvió como `subagent_type` y el lead citó su `description` del
frontmatter, o sea que abrió y parseó el archivo.

### La ausencia de `model:` en la fuente del repo es deliberada

`agents/*.md` de este repo no lleva `model:`. No es drift. Lo fijó la Task 5.6 y
está en el spec:

> *No se copia de `~/.claude/agents`. Esa ruta es del otro host y lleva
> `model: sonnet`. La fuente versionada es `agents/*.md` (sin `model:`;
> heredan GLM del padre).*

Una fuente compartida por varios hosts no puede llevar un ID de modelo: los
nombres son de cada host. Ese es el hecho que obliga a que el valor se resuelva
en la instalación y no en la plantilla.

### La "fuga" de modelo cross-host existe, pero es INERTE (medido 12.3)

`~/.agents/agents/*.md` — el directorio que kimi-code lee — trae `model: sonnet`
en los cinco perfiles, y `sonnet` no es un modelo de Kimi.

**Medido 2026-08-18:** kimi lo **ignora por completo**. Su parser de frontmatter
lee un conjunto cerrado de claves y `model` no está entre ellas, así que la
clave es inerte: no cambia el binding ni produce error. Sacarla sigue siendo
correcto —el archivo afirma algo que no es cierto— pero es **higiene, no la
corrección de un defecto activo**, y no tiene urgencia.

### Kimi no acepta modelo ni effort por agente (medido 12.3)

Ésta es la premisa que más cambió al medirla. El parser de agentes del binario
(`parseAgentFileText`) acepta exactamente:

```
name, description, whenToUse, override, tools, disallowedTools,
subagents, model_preference
```

**`model` y `effort` no están.** La única palanca de modelo es
`model_preference`, que admite exactamente `"primary"` o `"secondary"` — una
abstracción de **dos slots**, no un ID de modelo. El effort sale de la entrada
`[models]` de `config.toml` (`support_efforts` / `default_effort`), es global
por modelo, y se hereda del padre.

Medido con los `wire.jsonl` por agente, que registran `profile.bind` y
`llm.request` con `modelAlias` y `thinkingEffort`: con y sin las claves, el
binding del subagente es idéntico al del lead (`kimi-code/k3-256k`, `high`).

**Riesgo nuevo que la medición descubrió, y que este diseño no había previsto:**
un valor *inválido* en una clave *conocida* no falla ruidoso — el archivo deja
de parsear y **el agente desaparece del registro sin error visible**. Con
`model_preference: sonnet`, el tipo dejó de existir y el lead improvisó con uno
genérico. Si eso le pasara a `implementer`, `verifier` o `reviewer`, la
ceremonia se quedaría sin roles y el gate no tendría a quién acreditar. Cualquier
escritura futura de esa clave necesita un caso que verifique que **el tipo sigue
resolviendo**, no sólo que el archivo se escribió.

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
| `standard` | `claude-sonnet-5` / `medium` | *(vacía)* | `grok-4.6` / `medium` | **no aplica** |
| `verify` | `claude-sonnet-5` / `low` | *(vacía)* | `grok-4.6` / `low` | **no aplica** |
| `review` | `claude-opus-5` / `xhigh` | *(vacía)* | `grok-4.6` / `xhigh` | **no aplica** |

**zcode queda vacía por catálogo NO OBSERVADO, no por falta de soporte**
(medido 12.1, `docs/task-12.1-medicion.md`): el parser de agentes sí lee
`model:` como clave oficial, pero el entitlement real de la cuenta (qué IDs
`glm-5.x` puede usar) no se pudo confirmar por ninguna vía headless — el
catálogo de referencia embebido en el bundle es multi-proveedor genérico, no
un listado de entitlement. Nota aparte, no de catálogo: el nombre de clave de
`effort` en zcode **no es `effort:`** — el parser destructura `thoughtLevel:`
(`EFFORT_KEY='thoughtLevel'` en `tools/model-routing.sh`); escribir `effort:`
sería texto muerto aunque el catálogo se confirmara mañana.

**grok se llenó con el catálogo confirmado de la cuenta** (medido 12.2,
`docs/task-12.2-medicion.md`, 2026-08-24): `grok-4.6` (default de
`config.toml`) y `grok-4.5`. La medición no comparó capacidad entre los dos
IDs — sólo confirmó que ambos se aplican literalmente por registro interno —
así que no hay evidencia para preferir uno sobre otro por tier: se usa
`grok-4.6` en los tres tiers y se varía sólo el `effort`, mismo criterio que
claude entre `standard`/`verify`.

**La fila `kimi` queda vacía de forma DEFINITIVA, no provisoria** (medido 12.3):
el host no acepta un ID de modelo ni un effort por agente — su parser sólo
tiene `model_preference` ∈ {`primary`, `secondary`}, dos slots, no un ID por
rol — así que no hay valor que poner. Sus perfiles se instalan sin esas claves
y el subagente hereda del lead — que es lo que ya hace hoy. La posesión del
archivo (D5) conserva sentido por la marca `saikit_owned` y por sacar el
`model: sonnet` inerte; el ruteo, no. Sellado: no hay ruta de ruteo real en
kimi dentro del alcance de esta fase (ver Non-Goals).

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

**Advertencia a declarar en el spec, y su límite exacto.** El CLI del kit puede
volver a escribir esos perfiles en un `saikit-update` posterior. La posesión no
impide la sobrescritura. Y la reparación **no es incondicional**: el instalador
sólo re-adopta un archivo cuyo hash esté en `agents/vendor-manifest.sha256`.

Las dos ramas, medidas contra la máquina de estados:

- El update reescribe el perfil con los **mismos bytes** que el manifiesto ya
  lista ⇒ `VENDOR_CONOCIDO` ⇒ archiva y repara. La promesa vale.
- El update trae un perfil **distinto** (el vendor cambió el texto) ⇒ hash
  desconocido, sin `saikit_owned` ⇒ **`DESCONOCIDO` ⇒ no se toca y se
  reporta.** La promesa NO vale: el ruteo se pierde en silencio hasta que
  alguien mire el reporte.

Ese segundo caso no es un defecto de la máquina de estados — es lo correcto: no
se pisa un archivo que nadie miró. Pero significa que **el manifiesto necesita
una vía de refresco**: un procedimiento declarado para agregar el hash nuevo del
vendor después de revisar el diff, no un `--force` que adopte cualquier cosa.
Sin esa vía, la fase entrega un ruteo que un update ajeno puede desactivar sin
ruido.

Enunciado honesto para el spec: *la posesión repara mientras el vendor no cambie
sus perfiles; cuando los cambia, el instalador se planta y lo reporta, y hace
falta refrescar el manifiesto a mano.*

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
- **12.3 — kimi. CERRADA (2026-08-18, `docs/task-12.3-medicion.md`).** Fue
  captura viva más lectura del parser adentro del binario. Resultado: la premisa
  de lectura de `~/.agents/agents/` se confirmó, y el host **no acepta modelo ni
  effort por agente** — su fila queda vacía de forma definitiva. Catálogo
  observado: `kimi-code/k3` (1M), `k3-256k` (256K, el de sesión), y
  `kimi-for-coding` / `-highspeed`.

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
| `kimi` | `--host kimi` (nuevo) | manifiesto de vendor | **no aplica** (medido 12.3) |
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
  tipo exacto de mentira que el resto de este spec persigue. **Actualizado tras
  12.1/12.2:** grok ya se midió (12.2) y su `effort:` **sí** se escribe —
  aplicado y confirmado por registro interno del host. zcode sigue sin
  escribirlo, no porque el host lo ignore (`thoughtLevel:` sí se lee), sino
  porque el catálogo real de la cuenta (12.1) quedó no observado y no hay un
  ID que rutear con confianza.
- **`kimi` no recibe ruteo de modelo ni de effort** (medido 12.3): el host no
  tiene esas claves por agente. Su `--host kimi` existe sólo por la posesión del
  archivo y la marca. Llevarlo a `model_preference` + `[secondaryModel]` daría
  **dos** niveles, no tres, y es una decisión de producto que esta fase no toma.
