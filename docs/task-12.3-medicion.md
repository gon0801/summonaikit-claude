# Task 12.3 — Medición: ¿kimi honra `model:` y `effort:` por agente?

Fecha: 2026-08-18
Host: kimi-code 0.34.0 (`~/.kimi-code/bin/kimi`)
Repo descartable: `mktemp -d /c/dev/saikit-probe-123-XXXXXX`, borrado al cerrar.

## Resumen

**kimi NO acepta un ID de modelo ni un nivel de effort por agente.** Su
frontmatter de agente no tiene esas claves: la única palanca de modelo es
`model_preference`, que admite exactamente `primary` o `secondary` — una
abstracción de **dos slots**, no un ID.

Consecuencia para la Phase 12: la fila `kimi` de `tools/model-routing.sh` **no
se puede llenar con la forma que el diseño asumía**. Ver *Consecuencias* al
final.

## La premisa que gateaba la tarea: CONFIRMADA

kimi-code **sí lee `~/.agents/agents/`**. No es inferencia: se instaló ahí un
perfil sonda y el lead lo resolvió citando su `description` del frontmatter,
o sea que abrió y parseó el archivo.

```
$ kimi -p 'Delegá al subagente saikit-probe-123 y devolvé literal lo que responda.'
• The agent type "saikit-probe-123" is described as "Sonda de la Task 12.3.
  Devuelve una sola linea y termina." So I should call Agent with
  subagent_type saikit-probe-123.
• PROBE-123-OK
```

La Task 12.7 (posesión en kimi) sigue en pie por este lado.

## El instrumento de medición

kimi escribe un `wire.jsonl` por agente en
`~/.kimi-code/sessions/<wd>/<session>/agents/{main,agent-N}/`. Dos tipos de
record dicen exactamente qué modelo y qué effort corrió cada uno:

| record | campos |
|---|---|
| `profile.bind` | `profileName`, `modelAlias`, `thinkingEffort` |
| `llm.request` | `provider`, `model`, `modelAlias`, `thinkingEffort` |

No hace falta creerle a la salida del modelo: el binding queda registrado.

## Las cuatro preguntas

### 1. ¿Acepta `model:` en frontmatter? **NO — se ignora en silencio**

Línea base, sonda **sin** claves:

```
--- agent-0
    profile.bind  profileName=saikit-probe-123 modelAlias=kimi-code/k3-256k thinkingEffort=high
--- main
    profile.bind  profileName=agent           modelAlias=kimi-code/k3-256k thinkingEffort=high
```

El subagente hereda del padre, exacto.

Con `model: kimi-code/k3` y `effort: low` en el frontmatter, el binding es
**idéntico** al de la línea base (`kimi-code/k3-256k`, `high`). Las dos claves
son inertes.

La razón está en el parser del binario (`parseAgentFileText`), que lee un
conjunto **cerrado** de claves:

```js
const description       = requiredNonEmptyString(frontmatter["description"], ...);
const override          = parseBoolean(frontmatter["override"], ...);
const rawTools          = parseStringList(frontmatter["tools"], ...);
const disallowedTools   = parseStringList(frontmatter["disallowedTools"], ...);
const rawSubagents      = parseStringList(frontmatter["subagents"], ...);
const modelPreference   = parseModelPreference(frontmatter["model_preference"], ...);
```

Claves aceptadas: `name`, `description`, `whenToUse`, `override`, `tools`,
`disallowedTools`, `subagents`, `model_preference`. **`model` y `effort` no
están.** Una clave que no está en esa lista se ignora sin aviso.

### 2. ¿Acepta `effort:`? **NO, y no hay equivalente por agente**

No existe ninguna clave de effort en el parser. `thinkingEffort` sale del
modelo (`support_efforts` / `default_effort` de la entrada `[models]` en
`config.toml`) y se hereda del padre.

### 3. ¿Qué hace con un valor desconocido? **Dos comportamientos distintos**

- **Clave desconocida** (`model:`, `effort:`) ⇒ se ignora en silencio. El
  agente carga normal.
- **Valor inválido en una clave conocida** ⇒ el archivo **no parsea y el agente
  desaparece del registro**, sin error visible en la CLI:

```
$ # con model_preference: sonnet   (inválido)
$ kimi -p 'Delegá al subagente saikit-probe-123.'
• There's no such subagent type. Available types: plan, agent, coder, explore,
  closer, implementer, retro, reviewer, verifier. There's no "saikit-probe-123"
  agent type.
```

`parseModelPreference` lo explica:

```js
if (value === "primary" || value === "secondary") return value;
throw new AgentFileParseError(`Frontmatter field "model_preference" in ${filePath}
  must be "primary" or "secondary"`);
```

**Este es el hallazgo con más consecuencia operativa.** El `AgentFileParseError`
no llega al operador: el agente simplemente no está, y el lead improvisa con un
tipo genérico. Si eso le pasara a `implementer`, `verifier` o `reviewer`, la
ceremonia se quedaría sin roles y **el gate no tendría a quién acreditar** —
un modo de falla silencioso.

Nota lateral medida en esa misma corrida: los tipos disponibles incluyen
`closer, implementer, retro, reviewer, verifier`, o sea que los cinco perfiles
del kit **sí están registrados** en kimi.

### 4. Catálogo real de la cuenta

De `~/.kimi-code/config.toml`, entradas `[models]`:

| alias | contexto | efforts soportados | default |
|---|---|---|---|
| `kimi-code/k3` | 1 048 576 | `low`, `high`, `max` | `high` |
| `kimi-code/k3-256k` | 262 144 | `low`, `high`, `max` | `high` |
| `kimi-code/kimi-for-coding` | 262 144 | — | — |
| `kimi-code/kimi-for-coding-highspeed` | 262 144 | — | — |

El modelo de sesión observado en las cuatro corridas fue `kimi-code/k3-256k` con
`thinkingEffort=high`.

## El mecanismo que kimi SÍ tiene, y lo que no se pudo activar

El binario declara un slot secundario global:

- config: sección `secondaryModel` (con `model` y su effort);
- env: `KIMI_SECONDARY_MODEL` y `KIMI_SECONDARY_EFFORT`;
- opt-in por agente: `model_preference: secondary`.

**No observado:** con `model_preference: secondary` y
`KIMI_SECONDARY_MODEL=kimi-code/k3 KIMI_SECONDARY_EFFORT=low`, el binding del
subagente **no cambió** (siguió en `kimi-code/k3-256k` / `high`) y no se emitió
error ni advertencia. Un `KIMI_SECONDARY_MODEL` con un valor inexistente
tampoco produjo el error que el binario tiene escrito para ese caso, lo que
sugiere que en 0.34.0 esas variables no se leen por esta ruta — pero **no se
midió** si el slot se activa declarando `[secondaryModel]` en `config.toml`, y
no se probó porque exigía editar la config viva del operador.

`not_observed != absent`: no se afirma que el slot secundario no funcione. Se
afirma que **no se logró activar por env**, y que aun activándose daría **dos
slots**, no un modelo por rol.

## Consecuencias para la Phase 12

1. **La fila `kimi` no se llena con `model`/`effort`.** Queda vacía: el
   instalador omite las claves y el agente hereda del padre, que es lo que ya
   pasa hoy. El Step 5 de la Task 12.7 (llenar la fila) **se cae**; la 12.7
   conserva sentido sólo por la posesión del archivo y la marca `saikit_owned`.
2. **La "fuga de `model: sonnet`" es inerte, no un defecto activo.** Los cinco
   perfiles del vendor en `~/.agents/agents/` traen `model: sonnet` y kimi lo
   ignora por completo. Sigue conviniendo sacarlo por higiene —dice algo que no
   es cierto—, pero **no cambia ningún comportamiento** y no es urgente. El caso
   de test de la 12.7 que exigía "la fuga queda cerrada" hay que reescribirlo
   como higiene, no como corrección de un defecto.
3. **Riesgo nuevo, no previsto por el diseño:** un valor inválido en una clave
   conocida borra el agente del registro sin avisar. Si la Phase 12 llega a
   escribir `model_preference` en los perfiles de kimi, un valor equivocado deja
   la ceremonia sin roles. Cualquier escritura futura de esa clave necesita su
   propio caso de test que verifique que **el tipo sigue resolviendo**, no sólo
   que el archivo se escribió.
4. Si algún día se quiere ruteo real en kimi, la vía es `model_preference` +
   `[secondaryModel]` en `config.toml`, y da **dos niveles** (primary /
   secondary), no tres. Mapear tres tiers a dos slots es una decisión de
   producto que esta fase no tomó.

## Verificación de no-mutación

`~/.agents/agents/` quedó **byte a byte idéntico**: los 5 perfiles del vendor
intactos y la sonda borrada.

```
089330b4bb1a0c68  closer.md
1d96670a25e36d94  implementer.md
27b66a8d112a36a5  retro.md
a11aaf9cebbe20b5  reviewer.md
c5de1cbe0072d68a  verifier.md
```

De los 385 archivos vigilados, cambiaron 3, los tres contabilidad del runtime
que la lista de podas del plan no cubría:

| archivo | por qué |
|---|---|
| `~/.kimi-code/credentials/kimi-code.json` | refresco de token |
| `~/.kimi-code/session_index.jsonl` | registro de sesiones |
| `~/.kimi-code/workspaces.json` | registro de workspaces |

**Corrección al plan:** esos tres hay que agregarlos a la poda de `huella_kimi`,
o el chequeo de no-mutación grita en falso en cada corrida. `workspaces.json`
queda con una entrada apuntando al repo descartable ya borrado; se declara y no
se edita, porque tocar el registro vivo del operador para limpiar cosmética es
peor que la entrada huérfana.

No se creó trust nuevo: `~/.kimi-code/workspace-trust/` no tiene entrada para el
repo de la sonda. No hubo nada que revocar.

## Corrección adicional al plan (defecto propio, hallado al ejecutar)

El `/tmp/probe-123.env` del plan corre `probe="$(mktemp -d ...)"` **cada vez que
se sourcea**: sourcearlo en dos steps crea dos directorios y pierde la
referencia al primero (pasó: quedó un huérfano). El env file tiene que persistir
la ruta la primera vez y reusarla después. Aplica igual al
`/tmp/probe-122.env` de la Task 12.2, que tiene el mismo defecto sin ejecutar.
