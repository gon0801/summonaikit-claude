# Fixtures del arnés de salida dorada (Task 1.2)

Cada subdirectorio de `escenarios/` es **un turno**: una secuencia ordenada de
payloads que se le dan al hook, uno por paso, contra el mismo directorio de
estado. Lo que el hook contesta y lo que deja escrito queda grabado en
`tests/golden/baseline.txt`.

## Convención de nombres

```
escenarios/<NN>-<nombre>/
  README                                  # se copia como comentario a la línea base
  <NN>.<phase>.<target>.json              # el payload del paso
  <NN>.<phase>.<target>.transcript.jsonl  # opcional: el transcript de ese paso
```

- `phase`: `prompt` | `session` | `tool` | `stop` | `auto`
- `target`: `claude` | `cursor` | `auto`
- `auto` significa **no exportar** esa variable de entorno: el hook la deriva
  del payload. Es un camino real (ver escenario 15) y hay que poder ejercitarlo.
- El token `__TRANSCRIPT__` dentro del payload se reemplaza por la ruta real del
  transcript del paso. Sin archivo companion apunta a uno inexistente — que
  también es un caso real: `transcript_path` ilegible ⇒ tail vacío.

Los pasos corren en orden lexicográfico del nombre de archivo, así que el
prefijo numérico es el que manda.

## Procedencia de los payloads — dicho sin adornos

**Task 1.4, hecha:** se capturaron 308 payloads crudos de stdin en un turno
`-saikit` real (repo descartable, sesión nueva), y los fixtures se llevaron a
esa forma: mismos campos, mismo orden de claves, mismos nombres de herramienta.
Los **valores** siguen siendo sintéticos — un fixture no lleva texto ni rutas de
una sesión real — pero la **forma** ya no es una reconstrucción.

Lo que la captura corrigió, y que no se veía sin ella:

- Los 54 fixtures **no eran JSON válido** (`C:\dev\demo` con barra simple; el
  real escapa `C:\\dev\\demo`). El hook grepea texto crudo: eso cambia lo que
  ven sus greps.
- Faltaban `prompt_id`, `effort`, `tool_use_id`, `duration_ms` y, en el `Stop`,
  **`last_assistant_message`**: el texto final del asistente viaja en el propio
  payload. El recibo y la pausa tienen dos canales, no uno.
- La herramienta de subagentes se llama **`Agent`**, no `Task`.
- El `tool_response` de `Bash` **no trae `exitCode`** (59 de 59).
- `permission_mode` real es `auto` / `dontAsk`, nunca `default`.

Para refrescarla cuando el host cambie de forma:

```bash
bash tools/capture-payloads.sh --instalar <repo-descartable>
# ...arrancar una sesión NUEVA ahí y hacer un turno -saikit completo...
bash tools/capture-payloads.sh --cosechar <repo-descartable>
```

Sigue reconstruido, declarado: la fase `SessionStart` (el capturador registra
las 3 fases que nombra la DoD de la 1.4) y todos los payloads de `cursor`, que
no salen de una sesión de Claude.

Tres escenarios están **construidos a propósito** y lo declaran en su README: el
`SessionStart` con sentinel del 04, el paso 03 del 12 y el turno entero del 16.
Existen para dejar grabada una rama del hook que en la práctica no se alcanza
sola; confundir "la rama existe" con "la rama ocurre" es justamente lo que esta
línea base evita.

La captura de la 1.4 le puso número a esa distinción para el escenario 12: de
308 payloads reales, los únicos que traen la clave `subagent_type` son los 8 del
`Agent`, todos adentro de `tool_input`. **El vector de A1 no aparece solo en el
corpus observado** — el escenario lo construye, y eso ahora está medido, no
supuesto.

## Lo que la captura real dejó medido (Task 1.4)

- **El gate de secuencia no se puede satisfacer** (escenario 16). Los eventos
  que invocan subagentes (`tool_name: Agent`) no llegan al hook porque el
  matcher registrado nombra `Task`; los que sí llegan traen el rol en
  `agent_type`, y el hook busca `subagent_type`. Tres subagentes corren y
  `agents_seen` queda vacío. Defecto A9. **CERRADO por la Task 3.7**: el hook
  ahora lee `agent_type` de primer nivel como fallback (`:831`) y `agents_seen`
  se puebla; el escenario 16 pasó de bloquear a cerrar limpio. La mitad del
  matcher sigue: los eventos `Agent` aún no llegan, y un subagente read-only
  (Read/Grep/Glob) sigue sin registrar su rol — `check-hook-registration.sh` lo
  reporta. Esta línea es el registro de lo que 1.4 midió; el estado vigente es
  "cerrado".
- **Ningún veredicto de la línea base se movió** al pasar a la forma real. Lo
  único que cambió es el escapado de rutas en el log de evidencia y el
  `task_hash` del escenario 04 (`SessionStart` no trae campo `prompt`, así que
  el hash sale del payload entero). Eso es la declaración que pedía la DoD:
  los 15 veredictos grabados con payloads reconstruidos se sostienen.

## Lo que la línea base dejó medido (y contradice al spec)

Tres cosas salieron distintas de como estaban escritas. Están grabadas en los
escenarios que las miden, no solo acá:

1. **El recibo depende de cómo esté formateado** (escenarios 05 vs 06). En un
   transcript real las líneas del asistente van con el salto de línea escapado,
   y `has_receipt_label` exige un carácter no alfabético antes de la etiqueta —
   el que hay es la `n` de la secuencia escapada. Un recibo correcto escrito
   como texto corrido **no satisface ninguna de las 6 etiquetas**; el mismo
   recibo en viñetas sí. No está en la tabla de defectos del spec.
2. **A1 no reproduce como está descrito** (escenario 12). El contenido de un
   archivo llega al payload con las comillas escapadas, así que un archivo del
   repo que mencione `subagent_type` NO registra el rol. Lo que sí lo registra
   es la clave JSON real en cualquier nivel del payload. El vector a cerrar en
   la Task 3.1 es otro del que dice su DoD.
3. **Leer documentación marca el turno como implementado** (mismo escenario).
   La detección de `implemented` mira el payload entero, y ahí aparece
   `file_path` en cualquier `Read`.

## Reglas

- Ningún fixture lleva credenciales, tokens ni rutas de un perfil real.
- Todo se compara byte a byte: los archivos de este árbol van con final de
  línea LF, fijado en `.gitattributes`. Un checkout con CRLF cambiaría el
  `task_hash` (es un `cksum` del prompt) y la línea base daría divergencia.
- `arnes-falso/` no es un fixture del hook: es el hook de mentira con el que se
  prueba el arnés mismo, para que sus tests corran igual en una máquina donde
  el hook vivo no existe.
