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

Los payloads siguen la forma real de los eventos de Claude Code y sus campos
(`tool_input` / `tool_response`) están calcados de registros reales de
transcripts de este mismo repo. **No son una captura cruda de stdin.** Capturar
el stdin de verdad exige registrar un hook de captura y arrancar una sesión
nueva — Claude Code fotografía los hooks al arrancar, así que un hook agregado
a mitad de sesión no corre. Queda como refresco explícito, no como supuesto:

```bash
bash tools/capture-payloads.sh --instalar <repo-descartable>
# ...arrancar una sesión ahí y hacer un turno -saikit completo...
bash tools/capture-payloads.sh --cosechar <repo-descartable>
```

Eso no es una sugerencia suelta: es la **Task 1.4** del plan. Mientras siga
abierta, la línea base describe el comportamiento del hook contra payloads
reconstruidos, y esa es la diferencia entre "medido" y "medido con lo que el
host manda de verdad".

Dos payloads están **construidos a propósito** y lo declaran en su README: el
`SessionStart` con sentinel del escenario 04 y el paso 03 del escenario 12. Los
dos existen para dejar grabada una rama del hook que en la práctica no se
alcanza sola; confundir "la rama existe" con "la rama ocurre" es justamente lo
que esta línea base evita.

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
