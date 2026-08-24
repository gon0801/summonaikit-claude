# Task 12.1 — Medición zcode: ¿el loader de agentes honra `model:` y `effort:`?

Fecha: **2026-08-23**. Vía: inspección **estática** del bundle `zcode.cjs`, la
misma vía que usó la Task 5.6 para verificar `saikit_owned` y `skills:`. Sólo
lectura sobre `~/.zcode/**`; no se editó ningún perfil ni se registró ningún
hook.

**Estado: CERRADO.** `model:` sí es clave oficial del frontmatter de agentes.
`effort:` como concepto de producto **sí existe** en zcode — hay una slash
command `/effort` de cara al usuario — pero **el parser de frontmatter de
agentes no lee `o.effort`**; la clave que sí destructura y guarda es
`thoughtLevel:`. Ninguno de los dos (`model`/`thoughtLevel`) se valida contra
un catálogo en ese parser: cualquier string no vacío pasa tal cual. El
entitlement real de la cuenta (qué IDs puede usar) quedó **no observado**; lo
que sí se confirmó es que el catálogo de *referencia* embebido en el bundle
contiene 3 de los 4 IDs `glm-5.x` en cuestión.

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
cero. Los dos coinciden byte a byte. **El valor "antes" no tiene artefacto de
archivo persistente** — el archivo original en `/tmp` se perdió por la
colisión descrita arriba; lo que sostiene la comparación es únicamente la
transcripción de la sesión (el `cksum` de 6 líneas de más arriba, copiado tal
cual de la salida real del primer comando) contra un `cksum` "después" que sí
quedó en el scratchpad. La lección — no escribir a `/tmp` plano en mediciones
con más de un paso — queda para la próxima tarea de este plan.

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
| ¿Acepta `effort:` (o equivalente)? | **El parser de frontmatter NO lee `o.effort`** — lee `o.thoughtLevel`. Pero "effort" SÍ es un concepto de producto/sesión de primera clase en zcode, con su propia slash command | Evidencia principal — el bundle registra una slash command de cara al usuario (línea 43): `{aliases:["variant"],details:["In the TUI, type /effort or /variant to open composer suggestions.","Submitting the empty command or list shows the current and selectable efforts as text.","Use a listed level to switch the current session reasoning effort."],name:"effort",summary:"Show or switch the current session reasoning effort.",usage:"/effort [list\|<level>]"}`. Su handler está registrado como `s(PWn,"handleEffortCommand")` (línea 3541), junto a `s(CWn,"formatEffortList")` y el mensaje `Wha="Use /effort <level>, /variant <level>, or /effort list."` — y ese handler opera sobre `getThoughtLevel()`/`listThoughtLevels()`/`setThoughtLevel()` (confirmado en línea 3494: `i=r.thoughtLevel?.trim();i&&t.app.listThoughtLevels().includes(i)&&await t.app.setThoughtLevel(i)`). Es decir: **"effort" es el nombre de cara al usuario; `thoughtLevel` es la clave interna/de frontmatter para el mismo concepto.** La función `ezt` (parser de frontmatter, ya citada arriba) destructura `o.thoughtLevel`, nunca `o.effort` — por eso escribir `effort:` en el frontmatter de un agente sería texto muerto, aunque `/effort` sí exista como comando de sesión. Conteos reales, re-corridos contra el bundle con `grep -f` sobre un pattern-file (necesario porque pasar comillas embebidas como argumento inline de `grep` en este entorno se corrompe silenciosamente — hallazgo metodológico, ver nota abajo):<br>`grep -aoc '"effort"' zcode.cjs` (vía pattern-file) → **5** líneas: 43, 1992 (×4 veces en esa línea, dentro de `"reasoning_options":[{"type":"effort","values":["low","high","max"]}]` del catálogo embebido — metadata de qué modelos soportan varios niveles de esfuerzo), 3100, 3551, 3560.<br>`grep -aoc "thoughtLevel" zcode.cjs` → **17** líneas (108 apariciones totales con `grep -ao ... \| wc -l`), incluyendo `defaultThoughtLevel`, `workspace_default_thought_level_changed`, `t.app.setThoughtLevel(i)`, `t.app.listThoughtLevels()`. |
| ¿Qué hace con un valor desconocido? | **En el parser de frontmatter, lo acepta sin validar, silenciosamente** — no hay catálogo ni diagnóstico para `model`/`thoughtLevel` ahí | `function h5i(e){if(e)return e==="inherit"?void 0:e}` — cualquier string no vacío se devuelve tal cual, salvo el literal `"inherit"` que se trata como "sin valor" (hereda). `u=Vj(o.thoughtLevel)` es aún más simple: sólo recorta el string, sin ninguna función normalizadora. Contraste explícito dentro del mismo `ezt`: `color` sí se valida contra un `Set` fijo (`g5i` → `u5i.has(e)`, colores: red/blue/green/yellow/purple/orange/pink/cyan) y `permissionMode` también (`_5i` → `l5i.has(e)`, valores: acceptEdits/auto/bypassPermissions/default/dontAsk/plan). `model` y `thoughtLevel` **no tienen ese guardia** en el parser de frontmatter. Búsqueda de `"Unknown model"` / `unknown_model` en el bundle completo: **0 coincidencias** — no existe ni el mensaje de error para ese caso. Nota aparte (no aplica al parser de frontmatter, sí a runtime): en `t.app.listThoughtLevels().includes(i)&&await t.app.setThoughtLevel(i)` (línea 3494, restauración de estado de sesión) SÍ hay una validación contra una lista dinámica antes de aplicar un `thoughtLevel` — y el handler de `/effort` (`PWn`) también opera sobre esa misma lista dinámica al cambiar el esfuerzo de una sesión activa — pero esa ruta es de sesión/runtime, no la que corre al parsear el Markdown de un agente. |
| ¿Catálogo real de la cuenta? | **NO OBSERVADO** (el entitlement real de la cuenta no se pudo confirmar). Lo que SÍ se observó, y es más débil de lo que el plan asumía: el catálogo de *referencia* embebido en el bundle **sí** contiene 3 de los 4 IDs `glm-5.x` | Se ubicó un catálogo de modelos embebido en el bundle (línea 1992, JSON minificado ~2 MB) con entradas de múltiples proveedores. Conteos reales re-corridos (vía `grep -aoc`, sin el problema de comillas porque estos patrones no las llevan):<br>`"glm-4.6"` → 1 línea, con metadata completa (`family:"glm"`, contexto 204800, pricing).<br>`"glm-5.1"` → **2** líneas — catálogo completo: `"glm-5.1":{"id":"glm-5.1","name":"GLM-5.1","family":"glm","attachment":false,"reasoning":true,...,"limit":{"context":200000,"output":64000},"cost":{"input":1.4,"output":4.4,"cache_read":0.26}}`.<br>`"glm-5.2"` → 3 líneas — SIN entrada de catálogo propia (`grep -c '"id":"glm-5.2"'` → 0); existe sólo como constante interna (`reo=`/`Rei=`/`$7n=`) referenciada por las reglas de reasoning-depth/context-window vía el regex `glm-\d{4}`, no como modelo listado con precio/límites.<br>`"glm-5-turbo"` → **1** línea — catálogo completo: `"glm-5-turbo":{"id":"glm-5-turbo","name":"GLM-5-Turbo","family":"glm",...}`.<br>`"glm-5.3"` → **0** líneas — el único de los cuatro que de verdad está ausente del catálogo embebido.<br>**Esto invierte lo que decía la versión anterior de este documento** (que afirmaba los cuatro ausentes): el catálogo de referencia del bundle SÍ conoce `glm-5-turbo`/`glm-5.1` con metadata completa de precios y límites (y a `glm-5.2` sólo como constante interna de sus reglas de razonamiento, sin entrada de catálogo propia), igual que conoce decenas de modelos de otros proveedores que la cuenta probablemente no tiene contratados. **Que un ID esté en este catálogo de referencia no confirma que la cuenta pueda usarlo** — es un catálogo multi-proveedor genérico (aparecen también `llama-3.3-70b-versatile`, `kimi-k3`, `gemini-2.5-pro`, etc., ninguno de los cuales es exclusivo de Z.AI/zcode), no un listado de entitlement. Se intentó confirmar el entitlement real por la única vía no interactiva que el CLI ofrece: `zcode --json --prompt "/model" --cwd <scratchpad>` (no existe un subcomando tipo `models list`; el `--help` sólo lista `commands`, `plugins`, `skills` como listables). El intento terminó en `Error: Turn execution failed` sin listar catálogo. No se reintentó una segunda vez para no ejecutar turnos reales adicionales contra la cuenta. El selector interactivo de la TUI (`/model` o `/effort` dentro de una sesión con operador) es la única vía que queda, y no se usó por ser esta una medición headless. |

## Nota metodológica: `grep` con comillas embebidas inline

Un `REQUEST_CHANGES` de revisión detectó que la primera versión de este
documento reportaba `grep -c '"effort"'` = 0 y `"glm-5.1"`/`"glm-5.2"`/`"glm-5-turbo"`
= 0, cifras que resultaron falsas al re-verificarlas. La causa: en este
entorno, pasar un patrón con comillas dobles embebidas como argumento inline de
`grep` (p. ej. `grep -o '"effort"' archivo`) se corrompe en algún punto de la
capa de shell/sandboxing y devuelve **0 falsos negativos**, sin error visible.
La forma que sí da el resultado real es escribir el patrón a un archivo con
`printf` y usar `grep -F -f <patrón> archivo`. Todos los conteos con comillas
de este documento (`"effort"`, `"glm-5.1"`, `"glm-5.2"`, `"glm-5-turbo"`,
`"glm-4.6"`, `"glm-5.3"`) están re-verificados con esa técnica o, para los que
no llevan comillas (`thoughtLevel`, `isGlm52ReasoningModelId`,
`glm-5.2-reasoning-depth`), con `grep -aoc` directo (que sí funciona sin
comillas). Cualquier medición futura sobre este bundle debería asumir que un
conteo en 0 para un patrón con comillas es sospechoso hasta reconfirmarlo por
pattern-file.

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
- Para "effort" en zcode, la clave de **frontmatter** a escribir es
  **`thoughtLevel:`**, no `effort:` — aunque `/effort` exista como slash
  command de sesión, el parser de agentes no lee esa clave por ese nombre.
  Escribir `effort:` en el frontmatter sería texto muerto — cae en "el resto
  se ignora", igual que cualquier clave no reconocida por `ezt`.
- Como el parser no valida ni `model` ni `thoughtLevel` contra ningún catálogo,
  un ID equivocado no produce un error visible en la instalación — el fallo,
  si lo hay, aparecería más adelante (no medido aquí). Esto no bloquea a la
  12.5, pero sí es una razón para que el candado de IDs de modelo (Core Rule del
  plan, Task 12.4 caso 7) sea estricto: nada en zcode va a avisar si el ID está
  mal.
- El catálogo de referencia embebido en el bundle NO sirve como fuente de
  verdad para qué IDs `glm-5.x` puede rutear `tools/model-routing.sh`: contiene
  IDs de decenas de proveedores ajenos a Z.AI, así que su sola presencia ahí no
  confirma entitlement de cuenta. Si la 12.4/12.5 necesitan confirmar qué IDs
  `glm-5.x` están realmente disponibles, esa confirmación sigue pendiente de
  una vía interactiva (TUI) que esta medición headless no cubrió.
