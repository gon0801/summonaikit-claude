# Task 12.1 — Medición zcode: ¿el loader de agentes honra `model:` y `effort:`?

Fecha: **2026-08-23**. Vía: inspección **estática** del bundle `zcode.cjs`, la
misma vía que usó la Task 5.6 para verificar `saikit_owned` y `skills:`. Sólo
lectura sobre `~/.zcode/**`; no se editó ningún perfil ni se registró ningún
hook.

**Estado: CERRADO.** `model:` sí es clave oficial del frontmatter de agentes;
`effort:` **no existe como tal** — el equivalente oficial se llama
`thoughtLevel:`. Ninguno de los dos se valida contra un catálogo en el parser
de frontmatter: cualquier string no vacío pasa tal cual. El catálogo real de la
cuenta quedó **no observado**.

## Versión y ubicación del bundle

| Campo | Valor |
|---|---|
| Paquete | `zcode-app-cli@3.7.5-11` (`zcode-runtime` / CLI `0.16.1`) — **igual que la Task 5.6** |
| Ruta del bundle | `C:\Users\ehven\AppData\Roaming\npm\node_modules\zcode-app-cli\vendor\zcode.cjs` |
| Tamaño | 12.5 MB (3626 líneas; algunas líneas superan los 2 MB por ser JSON minificado embebido) |
| sha256 | `31bd43939ad05779b7e296840cb3fde53a57da707be01c1e6370e6e704025ecf` |

## Integridad de `~/.zcode/agents` — antes y después

`cksum` de los 6 archivos del directorio, tomado antes de tocar el bundle y
después de la medición completa:

```
1839327597 6312 /c/Users/ehven/.zcode/agents/implementer.md
1855255800 3913 /c/Users/ehven/.zcode/agents/reviewer.md
2440272748 6103 /c/Users/ehven/.zcode/agents/saikit-backups/implementer.md.nuestro.20260816-174153.bak
3044216841 3870 /c/Users/ehven/.zcode/agents/saikit-backups/reviewer.md.nuestro.20260816-174155.bak
3827161911 3583 /c/Users/ehven/.zcode/agents/saikit-backups/verifier.md.nuestro.20260816-174154.bak
4241417395 3809 /c/Users/ehven/.zcode/agents/verifier.md
```

`diff` antes/después: **vacío ⇒ AGENTES INTACTOS.**

**Nota de higiene, declarada sin maquillar:** el primer intento de fijar la
huella escribió a `/tmp/zcode-agents-antes.txt` (ruta plana, no el scratchpad
de la sesión) y ese archivo apareció **pisado por otro proceso concurrente**
(contenido de `~/.grok/agents`, no de `~/.zcode/agents`) cuando se lo leyó de
nuevo para el diff — evidencia de que `/tmp` en este entorno es compartido
entre sesiones, no aislado por sesión. Se descartó ese archivo y se rehizo la
comparación completa dentro del scratchpad aislado de esta sesión, usando el
valor de "antes" que ya estaba capturado literalmente en la transcripción (los
mismos 6 `cksum` de arriba) contra una huella "después" tomada de nuevo desde
cero. Los dos coinciden byte a byte. La lección — no escribir a `/tmp` plano en
mediciones con más de un paso — queda para la próxima tarea de este plan.

## El parser de frontmatter de agentes

`grep -aoE '.{200}(subagent_type|agents/|frontmatter).{200}'` no dio contexto
legible (la coincidencia cae en una de las líneas gigantes de JSON embebido, sin
saltos de línea reales cerca). Se ubicó el parser por el término
`frontmatter` a secas, que sí resuelve a código legible en la línea 2745-2746
del bundle: la función `ezt` — internamente nombrada `parseAgentProfileFromMarkdown`
por su entrada en la tabla de nombres al final del mismo bloque
(`s(ezt,"parseAgentProfileFromMarkdown")`).

Cita literal (bundle, línea 2745-2746, recortada a lo relevante):

```js
function ezt(e){
  let t=dyn(e.content);
  if(!t.frontmatter)
    return{diagnostic:{code:"agent_missing_frontmatter", ...}};
  let{mcpServers:r,values:o}=pyn(t.frontmatter),
      n=Vj(o.name),
      i=Vj(o.description)?.replace(/\\n/gu,`\n`);
  if(!n) return yyn("name",e.path);
  if(!i) return yyn("description",e.path);
  let a=h5i(Vj(o.model)),
      u=Vj(o.thoughtLevel),
      l=g5i(Vj(o.color)),
      c=_5i(Vj(o.permissionMode)),
      ...
  return {..., profile:{
    name:n, description:i, source:e.source, systemPrompt:t.body.trim(),
    ...(a?{model:a}:{}),
    ...(u?{thoughtLevel:u}:{}),
    ...(l?{color:l}:{}),
    ...(c?{permissionMode:c}:{}),
    ...
  }};
}
```

Esto confirma lo que la Task 5.6 ya había medido para `skills`/resto: **exige
`name`+`description`** (con diagnóstico `agent_missing_required_frontmatter` si
faltan), y **el resto de claves reconocidas se vuelca al `profile` sólo si el
parser las nombra explícitamente** — `model`, `thoughtLevel`, `color`,
`permissionMode`, `maxTurns`, `memory`, `tools`, `disallowedTools`, `skills`,
`background`, `injectAgentsMd`, `mcpServers`. Una clave no listada ahí (por
ejemplo `effort:` tal cual) **no se lee ni se destructura**: cae en "el resto se
ignora", igual que midió la 5.6 para claves ajenas.

## Las cuatro preguntas

| Pregunta | Respuesta | Evidencia |
|---|---|---|
| ¿Acepta `model:` en frontmatter? | **SÍ** — es clave oficial | `a=h5i(Vj(o.model))` … `...(a?{model:a}:{})` en `ezt` (línea 2745-2746). `o.model` se lee, se pasa por `Vj` (recorta string) y por `h5i`, y si el resultado es verdadero se guarda como `profile.model`. |
| ¿Acepta `effort:` (o equivalente)? | **NO existe la clave `effort:`** — el equivalente oficial es `thoughtLevel:` | El destructuring de `ezt` lee `o.thoughtLevel` (`u=Vj(o.thoughtLevel)`), nunca `o.effort`. `grep -c '"effort"'` sobre el bundle completo da **0** — el literal `effort` no aparece ni una vez en 12.5 MB. `thoughtLevel` aparece 108 veces, incluyendo `defaultThoughtLevel`, `workspace_default_thought_level_changed`, `t.app.setThoughtLevel(i)`, `t.app.listThoughtLevels()` — es un concepto de primera clase en el runtime, sólo que con otro nombre. |
| ¿Qué hace con un valor desconocido? | **Lo acepta sin validar, silenciosamente** — en el parser de frontmatter no hay catálogo ni diagnóstico para `model`/`thoughtLevel` | `function h5i(e){if(e)return e==="inherit"?void 0:e}` — cualquier string no vacío se devuelve tal cual, salvo el literal `"inherit"` que se trata como "sin valor" (hereda). `u=Vj(o.thoughtLevel)` es aún más simple: sólo recorta el string, sin ninguna función normalizadora. Contraste explícito dentro del mismo `ezt`: `color` sí se valida contra un `Set` fijo (`g5i` → `u5i.has(e)`, colores: red/blue/green/yellow/purple/orange/pink/cyan) y `permissionMode` también (`_5i` → `l5i.has(e)`, valores: acceptEdits/auto/bypassPermissions/default/dontAsk/plan). `model` y `thoughtLevel` **no tienen ese guardia** en el parser de frontmatter. Búsqueda de `"Unknown model"` / `unknown_model` en el bundle completo: **0 coincidencias** — no existe ni el mensaje de error para ese caso. Nota aparte (no aplica al parser de frontmatter, sí a runtime): en `t.app.listThoughtLevels().includes(i)&&await t.app.setThoughtLevel(i)` (línea 3494, restauración de estado de sesión) SÍ hay una validación contra una lista dinámica antes de aplicar un `thoughtLevel` — pero esa ruta es de sesión/runtime, no la que corre al parsear el Markdown de un agente. |
| ¿Catálogo real de la cuenta? | **NO OBSERVADO** | Se ubicó un catálogo de modelos embebido en el bundle (línea 1992, JSON minificado ~2 MB) con entradas de múltiples proveedores; contiene `"glm-4.6"` con metadata completa (`family:"glm"`, contexto 204800, pricing). **`glm-5-turbo`, `glm-5.1`, `glm-5.2`, `glm-5.3` NO aparecen en ese catálogo embebido** — ni una sola vez. Esto es evidencia adicional (no del `db.sqlite`, sino del propio bundle) de que esos cuatro IDs son de otra fuente y no del catálogo de referencia que trae el CLI. Se intentó confirmar por la vía no interactiva que el CLI ofrece: `zcode --json --prompt "/model" --cwd <scratchpad>` — el único acercamiento headless a la slash command `/model` (`Show or switch the current session model`), ya que no existe un subcomando tipo `models list` (el `--help` sólo lista `commands`, `plugins`, `skills` como listables). El intento terminó en `Error: Turn execution failed` sin listar catálogo. No se reintentó una segunda vez para no ejecutar turnos reales adicionales contra la cuenta. El selector interactivo de la TUI (`/model` dentro de una sesión con operador) es la única vía que queda, y no se usó porque esta medición es headless. |

## Lo no observado, explícito

- **Catálogo real de la cuenta** (Q4): no confirmado por ninguna vía no
  interactiva disponible. El único intento headless (`--prompt "/model"`)
  falló con un error genérico de ejecución de turno, no con una lista. La vía
  que sí funcionaría — el selector interactivo de la TUI — requiere operador
  delante y no se ejecutó en esta medición.
- **La lista de valores válidos de `thoughtLevel` en runtime**
  (`app.listThoughtLevels()`): se confirmó que es una función dinámica —
  aparece usada como `supportedThoughtLevels:a.app.listThoughtLevels()` al
  emitir `emitModelSelected` — pero su enumeración depende del modelo activo en
  tiempo de ejecución y no está fijada como un `Set` estático legible por
  inspección de código (a diferencia de `color` o `permissionMode`, que sí lo
  están). No se infiere ninguna lista concreta.
- **Si un `model:`/`thoughtLevel:` con valor no reconocido produce un error más
  adelante en el flujo** (por ejemplo al intentar arrancar el agente con ese
  modelo, fuera del parser de frontmatter): no observado. Esta medición cubre
  el parser de frontmatter (`ezt`), que es el punto donde la Task 12.5
  necesita el veredicto; no cubre el resto del pipeline de arranque del agente.

## Lo que esto significa para la Task 12.5

- `tools/model-routing.sh` puede escribir `model:` en el frontmatter de los
  perfiles zcode con confianza: es clave oficial, se lee, se guarda en el
  `profile`.
- Para "effort" en zcode, la clave a escribir es **`thoughtLevel:`**, no
  `effort:`. Escribir `effort:` sería texto muerto — cae en "el resto se
  ignora", igual que cualquier clave no reconocida por `ezt`.
- Como el parser no valida ni `model` ni `thoughtLevel` contra ningún catálogo,
  un ID equivocado no produce un error visible en la instalación — el fallo,
  si lo hay, aparecería más adelante (no medido aquí). Esto no bloquea a la
  12.5, pero sí es una razón para que el candado de IDs de modelo (Core Rule del
  plan, Task 12.4 caso 7) sea estricto: nada en zcode va a avisar si el ID está
  mal.
