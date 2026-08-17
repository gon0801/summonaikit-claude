# Task 11.6 — Captura real de zcode: qué trae el Stop y qué decide sobre el camino 1

`[Test]` `[lane:fast]` `[tdd:skip:captura-manual-con-operador-adelante]`. Medido
el **2026-08-17** en un turno `-saikit` real de **zcode**, con el operador
adelante, sobre el repo descartable `C:/dev/saikit-captura-11.6` y
`tools/capture-payloads.sh --instalar … --host zcode` (5 entradas en el
user-config, quitadas al terminar; los 4 registros del harness quedaron
intactos).

**Cero payloads crudos, cero prompts del operador, cero rutas de perfil** en
este documento — misma disciplina que `docs/task-5.1-captura.md`.

## Recuentos

- Archivos capturados: **24** (12 payloads + 12 `.env`).
- Eventos: `UserPromptSubmit`×2, `PostToolUse`×9 (matchers `tools`/`task`/`agent`),
  `Stop`×1.
- Los pares `task`/`agent` vuelven a ser el MISMO tool call visto por los dos
  matchers — el alias `Task`↔`Agent` de la 5.1 se sostiene.

**Nota de método, y datapoint en sí misma:** el turno real recibió un SEGUNDO
prompt humano a mitad de camino, sin sentinel. El gate lo trató como corresponde
y **desarmó** (A4), así que el `Stop` capturado en vivo ya no juzgó nada. La
medición de abajo replaya la secuencia real —los mismos payloads, con el env
real— contra una copia AISLADA del hook, salteando ese prompt. El desarme
observado es, de paso, la Task 2.12/10.14 funcionando en campo.

## (a) ¿Qué trae el `last_assistant_message` real del Stop de zcode?

**Llega, y llega COMPLETO.** Medido sobre el Stop real:

| clave | largo | ¿trae el recibo? |
|---|---|---|
| `last_assistant_message` | **4522** | **sí** |
| `responseText` | 4522 | sí |
| `responsePreview` | **4003** (truncado) | sí |
| `lastAssistantMessage` (camel) | — | **AUSENTE** |

Dos cosas que corrigen supuestos previos:

1. **La hipótesis de la truncación era falsa para el canal que el gate lee.**
   El truncado es `responsePreview`, que el hook NO mira. `last_assistant_message`
   trae el mensaje entero, con el recibo adentro.
2. **La generalización de la 5.1 —"zcode emite CADA clave en snake_case y
   camelCase"— NO vale para este campo**: `lastAssistantMessage` no existe en el
   payload. Vale para `hook_event_name`, `session_id`, `transcript_path`,
   `permission_mode` y `stop_hook_active`, que sí aparecen duplicados.

### El gate lo extrae, y cierra limpio

Replay de la secuencia real contra una copia aislada del hook vivo, más dos
mutaciones del MISMO payload para probar que el gate estaba juzgando y no
pasando de largo:

| variante del Stop | exit | stderr | estado al cerrar |
|---|---|---|---|
| **real, sin tocar** | **0** | vacío | borrado (cierre limpio) |
| A — sin la clave `last_assistant_message` | 0 | 325 B, `unknown honesto` | borrado |
| B — con la clave, con el recibo mutado | **2** | 794 B, `Failed gates: Missing SUMMONAIKIT HARNESS RECEIPT` | `cycle=1` |

B bloquea y A toma la rama de la 11.4: el gate estaba midiendo. Sobre el payload
real, **encuentra el recibo y cierra sin consumir ciclo**.

### Consecuencia directa sobre la Task 11.4

**La rama "ambos canales ciegos" de la 11.4 NO alcanza a zcode.** Exige la clave
AUSENTE (`hooks/summonaikit-harness.sh`, detección por subcadena sobre el payload
crudo) y zcode la manda siempre — hizo falta borrarla a mano (control A) para que
la rama dispare. La rama sigue siendo correcta como guarda de Core Rule 2 para la
clase de host/turno donde el campo falte de verdad; lo que no hace es cerrar el
fallo de campo que la motivó.

**Residual declarado:** con esta medición, el fallo del turno de GLM (3 bloqueos
por "Missing SUMMONAIKIT HARNESS RECEIPT" sobre un turno con recibo válido) **NO
queda explicado** por un canal de payload ciego, porque ese canal funciona. La
causa real queda `unknown`: no se reprodujo acá y no se afirma desde la
no-observación. Si vuelve a pasar, lo que hace falta es capturar el Stop DEL
TURNO QUE FALLA, no reconstruirlo.

## (b) ¿El `transcript.jsonl` del tmpdir parsea con `assistant_text_transcript`?

**`unknown`, y con un motivo medido: el archivo no sobrevive al turno.** El Stop
declara su `transcript_path` en `%TEMP%\zcode-claude-hook-<rand>\transcript.jsonl`;
al cosechar (~1 minuto después del cierre) ese directorio **ya no existía**, y en
toda la máquina había **cero** directorios `zcode-claude-hook-*`, incluidas todas
las sesiones previas.

Lo que NO se midió, y no se afirma: si el archivo existe **en el instante** en que
corre el hook. Un observador externo no puede saberlo; haría falta que el propio
hook lo copie durante el evento.

## (c) ¿Los despachos reales de subagentes escriben `agents_seen`?

**Sí, medido** — y sin necesidad de la captura: el estado vivo de una sesión zcode
real (otro repo, mismo día) mostraba

```
agents_seen=implementer,verifier,reviewer
lane=full   implemented=1   verified=1   cycle=0
```

con una línea `agent: <rol>` por rol en `harness-evidence.log`. De paso confirma
en campo el split de `STATE_ROOT` por host de la Task 5.3: el estado vive bajo
`state/zcode/`, no bajo `state/claude/`.

## Veredicto sobre el camino 1 (extender la contención A6 al tmpdir de zcode)

**RECHAZADO.** Tres razones, en orden de peso:

1. **No hace falta.** El canal que el gate lee ya funciona en zcode: el recibo
   llega completo por `last_assistant_message` y el gate lo acepta (medido
   arriba). Un segundo canal no agrega nada que el gate necesite.
2. **Lo que compraría es dudoso.** El archivo es demostrablemente efímero: no
   sobrevive al turno. Extender la contención para leer algo que se borra deja
   un permiso permanente a cambio de una lectura intermitente.
3. **Lo que costaría está declarado desde la Task 0.2.** `%TEMP%` es el vector
   A7-bis; el precedente que citaba el datapoint (alias camel de Grok, 7.3/D4)
   caía DENTRO del perfil y no ensanchó la raíz de contención.

El cierre del camino 2 (la 11.4) queda como está, con su alcance ahora declarado.

## Forma medida del Stop de zcode (insumo para el alcance restante de la 11.8)

18 claves de primer nivel: `cwd`, `hookEventName`, `hook_event_name`,
`last_assistant_message`, `mode`, `permission_mode`, `responsePreview`,
`responseText`, `sessionId`, `session_id`, `stopHookActive`, `stop_hook_active`,
`timestamp`, `toolCallCount`, `traceId`, `transcriptPath`, `transcript_path`,
`turnId`.

Los `*.stop.zcode.json` de los escenarios 17-25 y del 46 traían un subconjunto
snake_case. Alinearlos a esta forma fue la Task 11.9, que esta medición
desbloqueó — con el matiz que acaba de aparecer: **no todas las claves se
duplican en camelCase**, así que la alineación se hizo contra esta lista, no
contra la regla general de la 5.1.

### Las otras dos fases, medidas en la misma captura

Quedan REGISTRADAS acá para que alinear sus fixtures no necesite otra sesión con
operador adelante:

- **`UserPromptSubmit`** (13 claves): `cwd`, `hookEventName`, `hook_event_name`,
  `mode`, `permission_mode`, `prompt`, `sessionId`, `session_id`, `timestamp`,
  `traceId`, `transcriptPath`, `transcript_path`, `turnId`.
- **`PostToolUse`** (19 claves): las de arriba menos `prompt`, más
  `toolCallId`/`tool_use_id`, `toolInput`/`tool_input`, `toolName`/`tool_name`,
  `toolResponse`/`tool_response` y `toolResultPreview`. Confirmado otra vez que
  **no hay `agent_type` top-level**: el rol viaja en `tool_input.subagent_type`
  y en `tool_response.agentType` (5.1). El `tool_response` real de un `Agent`
  trae `status`, `agentId`, `agentType`, `content[]`, `totalToolUseCount`,
  `totalDurationMs`, `totalTokens` y `usage`.

**Alinear estas dos NO se hizo en la 11.9 y no es cosmético**: `toolResultPreview`
duplica la salida de la herramienta dentro del payload, y el guard de señales de
falla de la Task 10.15 grepea el payload ENTERO — meter esa copia puede mover
veredictos de acreditación. Es trabajo con su propio riesgo, y por eso queda
declarado en vez de colado.

## Cómo se midió / fuente

- Repo descartable: `C:/dev/saikit-captura-11.6`. **Queda en la máquina del
  operador** con los payloads crudos adentro (traen el prompt del turno y rutas
  del perfil): borrarlo es un acto del operador, no de la sesión. Nada de eso
  entró al repo — lo único que se conserva versionado es la forma medida, en
  este documento.
- Registro: `tools/capture-payloads.sh --instalar … --host zcode`, con backup del
  user-config; `--quitar` al cerrar (verificado: 0 entradas de captura, 4
  registros del harness intactos).
- Replay y controles: copia del hook vivo en un tmpdir, con el env real del turno
  (`ZCODE_SESSION_ID` / `ZCODE_PROJECT_DIR`, sin `CLAUDECODE`).
- El turno: un `-saikit` que creó un archivo, corrió un comando, delegó en los
  tres subagentes y cerró con recibo completo y largo a propósito (para que la
  truncación, si existía, se notara).
