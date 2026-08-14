# Task 6.2 — Plan: medir el contrato de SALIDA de Codex

`[Test]` `[lane:gate]` `[tdd:required]`. Depende de 6.1 (`cc:完了`).

## Qué decide

El hook emite hoy cuatro formas de stdout y un `exit 2`, y **ninguna está
verificada contra Codex CLI 0.147.0**. La hipótesis del diseño
(`docs/phase-6-codex-design.md` § 6.2) es que el fork de Codex usa nuestra misma
forma de bloqueo y que el esquema de Claude sirve tal cual. **Es una creencia,
no una medición** — exactamente la clase de premisa que en 1.4 y 5.2 salió mal.

El resultado decide si `TARGET=codex` alcanza (6.4) o si hace falta una forma de
salida propia, como 7.2 acabó de decidir para Grok.

## Lo que NO se toca

- `~/.codex/hooks.json`, `~/.codex/hooks/summonaikit-harness.sh` y
  `~/.codex/hooks/summonaikit-harness.ps1`: los tres cksum antes/después son
  parte de la evidencia, igual que en 6.1.
- El hook de producto, el instalador y el perfil global. Esta tarea vale aunque
  el resto de la fase se cancele.
- El user-config de zcode y `~/.grok`. El camino codex no los mira.

## Qué hereda de 6.1, ya medido

| Hecho medido en 6.1 | Consecuencia para 6.2 |
|---|---|
| `~/.codex/hooks/summonaikit-harness.ps1` corre **UN** hook y **prefiere** `<repo>/.codex/hooks/summonaikit-harness.sh` cuando el cwd resuelve a un repo git | El registro es **colocación de archivo**, no mutación de config. `--instalar` deja el shim ahí y no toca nada más |
| `config.toml` exige `trusted_hash` **por entrada**, incluidas las de proyecto | **No se intenta** registrar un `<repo>/.codex/hooks.json`. En 6.1 capturó cero y no se distinguió de "no emite". Reintentarlo mediría cero y lo leeríamos como "el probe falló" |
| `hook_event_name` viaja en **clave snake con valor CamelCase** (`UserPromptSubmit`, `PostToolUse`, `Stop`) — igual que Claude | La tabla de eventos **no cambia**. A diferencia de grok, acá no hay literales nuevos: `extract_hook_event` sirve tal cual |
| El `Stop` trae `stop_hook_active` y `session_id` | Hay un oráculo de bloqueo **más directo** que el de 5.2 (ver § Oráculos) |
| El `Stop` **no** trae `reason` | No hay distinción `end_turn`/`shutdown` que hacer, a diferencia de 7.2 |
| El shim **reemplaza** al harness mientras está puesto | Durante la medición el sentinel no arma en ese repo. Es estructural y correcto: el probe no necesita el contrato, y los turnos de medición son turnos normales (no hace falta `-saikit`) |
| `transcript_path` cae en `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` | Ese rollout es el oráculo de inyección, en **solo lectura** |

## §A — Cambios de herramienta (TDD, rojo antes que verde)

`tools/probe-zcode-output.sh` gana `--host codex`. Tres bloques:

### A1. Registro por shim

`--instalar <repo> --host codex` escribe
`<repo>/.codex/hooks/summonaikit-harness.sh`: un shim que hace `exec` del probe
en modo hook con `--host codex --only-cwd <repo> --mode-file <repo>/probe-mode.txt`.
`--quitar` lo saca.

Tres estados, como siempre: **ausente** ⇒ se escribe; **nuestro** ⇒ se
reescribe (segunda instalación es no-op byte a byte); **desconocido** ⇒ no se
toca, se reporta, `exit 2`.

Identidad estricta, con la lección H1 de 7.2 ya aprendida: hace falta la marca
`<repo>/.codex/.probe-codex-owned` **y** el `--saikit-probe-id 6.2` adentro del
shim. Un archivo ajeno que *mencione* el id en un comentario no es nuestro.

El shim es **fail-open por sí mismo** (hallazgo 3 de la revisión cruzada de
6.1): si el probe no está en su ruta, calla y sale 0. Sin eso, mover o borrar el
repo del kit rompería **todos** los turnos de Codex en ese repo con un 127 por
fase.

### A2. Modo hook para codex

El `.ok` gana tres líneas, sólo en este host (en zcode y grok queda byte a byte
igual):

```
mode=<m> event=<e> nonce=<n>
stop_active=<true|false|none>     <- stop_hook_active del payload
round=<session_id|none>           <- identidad de ronda (misma clave que grok)
suppressed=<0|1>                  <- si el tope calló esta visita
```

**Tope de 3 emisiones por ronda.** Si `block0` o `exit2` bloquean de verdad,
Codex vuelve a llamar al modelo y el probe se re-dispara. En 5.2 zcode cortó
solo a las 4 pasadas; **Codex no tiene tope medido** y el operador paga cada
pasada. Tres alcanza para el veredicto (1 visita = no bloqueó; ≥2 = bloqueó) y
acota el runaway.

Dos reglas heredadas de 7.2, que ahí costaron un ciclo de cross-review cada una:

- Los `.ok` **cosechados** (`<modo>-<nonce>.ok`, con guión) no cuentan. Si
  contaran, una re-medición arrancaría ya topada y daría un falso "ignorada".
- **Sin identidad de ronda no se suprime.** Preferible emitir de más que
  declarar "ignorada" por un `.ok` vivo de una ronda vieja sin cosechar.

### A3. Dos guardas que 6.2 abre y cierra en el mismo cambio

1. **`$HOME/.codex*` faltaba** en la lista de destinos rechazados (están
   `.claude*`, `.zcode*`, `.grok*`). Mientras no existía `--host codex` era una
   inconsistencia; con este cambio pasa a ser un agujero real.
2. **El repo del producto.** El shim *reemplaza* al harness. Apuntar el probe a
   `summonaikit-claude` mataría el gate ahí sin avisar. Se rechaza el destino si
   contiene `hooks/summonaikit-harness.sh` (la fuente del producto).
3. **Metacaracteres en las rutas.** El shim interpola rutas en un script bash
   entre comillas dobles; `"`, `` ` ``, `$` y `\` se rechazan (fail-closed).
   Mismo criterio que grok, distinta razón: allá era PowerShell, acá es bash.
4. **El destino tiene que ser la RAÍZ del repo** — apareció al implementar, no
   estaba en el plan original. `capture-payloads.sh` sólo verifica que
   `git rev-parse --show-toplevel` no falle, o sea "está adentro de algún
   repo". No alcanza: el `.ps1` busca `<raíz>/.codex/hooks/summonaikit-harness.sh`,
   así que un shim puesto en un **subdirectorio** no lo lee nadie. La medición
   entera daría "no corrió" y lo leeríamos como veredicto. Se compara
   `toplevel` contra el destino y se rechaza si difieren.

Cada una lleva su caso de test — regla de hierro 2 del repo. Y cada caso lleva
su aserto sobre el **mensaje**: sin eso, todos pasarían en verde por el rechazo
genérico de `--host codex` y no por la guarda que dicen medir.

## §B — Oráculos: cómo se lee cada veredicto

| Pregunta | Oráculo | Por qué ese |
|---|---|---|
| ¿Corrió? | `<repo>/probe-ran/<nonce>.ok` | Un hook OK no deja rastro propio. Sin `.ok` el veredicto es `unknown`, nunca "no corrió" |
| Inyección (UPS) | El nonce `PROBE-CONTEXT-<n>` / `PROBE-EXTRA-<n>` en el rollout de la sesión, `~/.codex/sessions/…/rollout-*.jsonl` | 6.1 midió que `transcript_path` apunta ahí. Lectura, nunca escritura |
| Bloqueo (Stop) | Conteo de `.ok` con `event=Stop` **de la misma `round=`**, más `stop_active=` | El control da 1. `stop_active=true` en la 2.ª visita prueba que la continuación es del hook y no del operador — señal que 5.2 no tuvo |
| Rechazo vs. silencio | Lo que Codex muestre en pantalla o log al recibir la forma | Si no hay superficie, el veredicto es **`ignorada`**, no `rechazada`, y se declara que no se pudo distinguir |

## §C — La ceremonia viva (operador adelante)

Repo descartable, sesión **nueva** por modo, un modo por turno. `REPO` es el
repo descartable (p. ej. `C:\dev\saikit-probe-codex`), `KIT` este repo.

**Antes de nada** — la línea base del perfil, que es la evidencia de que no se
tocó:

```bash
cd ~/.codex && cksum hooks.json hooks/summonaikit-harness.sh hooks/summonaikit-harness.ps1
```

**Armar** (el repo descartable tiene que existir y ser un repo git ya
inicializado; el instalador lo exige y explica por qué):

```bash
bash "$KIT/tools/probe-zcode-output.sh" --instalar "$REPO" --host codex
```

**Por cada modo**, en este orden — `empty` primero:

| # | modo | qué mide |
|---|---|---|
| 1 | `empty` | **control**: que el registro dispara en las 3 fases |
| 2 | `context` | `hookSpecificOutput.additionalContext` |
| 3 | `extra` | lo mismo + clave desconocida ⇒ si el esquema es estricto |
| 4 | `block0` | `decision:block` con exit 0 |
| 5 | `budget` | `continue:false` + `stopReason` |
| 6 | `notice` | `systemMessage` |
| 7 | `exit2` | `exit 2` pelado en el `Stop` |

```bash
echo <modo> > "$REPO/probe-mode.txt"
# sesion NUEVA de Codex en $REPO, un turno que corra algun comando
# cosecha, ya cerrada la sesion:
cd "$REPO/probe-ran" && for f in *.ok; do
  case "$f" in *-*) continue ;; esac      # ya cosechado: no re-prefijar
  mv "$f" "<modo>-$f"
done
```

El `case` no es adorno: los `.ok` vivos se llaman `<nonce>.ok` **sin guión** y
los cosechados llevan el modo adelante. Un glob por prefijo hexadecimal
(`[0-9a-f]*.ok`) volvería a tomar `block0-…`, `context-…`, `extra-…` — todos
empiezan con una letra de ese rango — y los prefijaría dos veces. Es la misma
regla de "el guión distingue vivo de cosechado" que aplica el tope.

La cosecha **no es opcional**: los `.ok` vivos sin cosechar topan la ronda
siguiente y el modo que venga daría un falso `ignorada`. El renombre a
`<modo>-<nonce>.ok` es justamente lo que el tope aprende a no contar.

**Desarmar y cerrar:**

```bash
bash "$KIT/tools/probe-zcode-output.sh" --quitar "$REPO" --host codex
cd ~/.codex && cksum hooks.json hooks/summonaikit-harness.sh hooks/summonaikit-harness.ps1
```

Los tres cksum idénticos a los de la línea base, o la tarea no cierra.

El control `empty` va primero: si no deja `.ok` en las 3 fases, el registro no
está corriendo y **toda** medición posterior sería `unknown` disfrazado de
"ignorada".

## §D — Qué queda `unknown` de antemano, declarado

- Si Codex tiene un **Stop de cierre** distinto del de turno (Grok sí lo tiene;
  en Claude y zcode no se midió). Si aparece, se anota; no se persigue.
- Si `spawn_agent` emite evento — heredado de 6.1, fuera de alcance acá.
- Si Codex expone errores de hook en alguna superficie. De eso depende que
  "rechazada" sea siquiera medible; si no lo es, se declara.

## §E — Criterio de cierre (la DoD, en verificable)

1. Las 4 formas + `exit 2` tienen veredicto **medido** (aceptada / rechazada /
   ignorada), cada uno con su evidencia citada.
2. El rechazo se distingue del silencio, **o** se declara que no se pudo.
3. `exit 2` en `Stop` tiene medido si bloquea, si continúa o si cuenta como
   error.
4. La decisión `TARGET=codex` queda escrita con su evidencia, y 6.4 la hereda.
5. Los tres cksum de `~/.codex/` idénticos antes y después.
6. `tests/run.sh` en verde y `pre-commit run --all-files` Passed.

Resultado en `docs/task-6.2-salida.md`, sin payloads crudos, prompts ni rutas de
perfil del operador — mismo criterio que `docs/task-5.2-salida.md`.
