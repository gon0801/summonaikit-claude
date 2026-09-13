# 21.3 — Identidad autoritativa del worktree revisado (spike)

Fila `[Recommended]` `[lane:release]` `[tdd:skip:medición]` `[needs-spike]`.
Pregunta: ¿qué señal liga turno, repo, HEAD y worktree de la task
**antes** de cambiar el validador de rastro?

## Identidad de ESTA evidencia

| Campo | Valor |
|---|---|
| Fecha | 2026-09-13 |
| CLI observado | `codex-cli 0.154.0` (`codex exec --dangerously-bypass-hook-trust -s workspace-write --json`) |
| Lab | repo sintético `origen` + 2 worktrees concurrentes (`wt-A` rama-A, `wt-B` rama-B) + checkout ajeno (`alien`, clon separado); los 4 con HEAD distinto; CODEX_HOME temporal con auth copiada; hook shim grabador puro (sin gate, sin mutación) |
| Turnos | 3 `codex exec` concurrentes: A escribe `TRAIL-A.txt` en wt-A, B escribe `TRAIL-B.txt` en wt-B, X escribe `TRAIL-X.txt` en alien |
| Resultado funcional | EXIT=0 ×3; cada archivo con su línea exacta, nada más modificado |
| Captura | 8 payloads (`fixture-00…07`; redactado: `/Users/dn/lab-21.3` → `[LAB]`) |
| Incidente | el shim nombraba archivos por conteo de directorio y dos eventos (SessionStart/UserPromptSubmit de B y X) se sobrescribieron entre sesiones concurrentes; la cobertura del veredicto está completa (los 3 Stop + 1 PostToolUse por sesión, cada uno con `session_id`+`turn_id`+`cwd` nativos) |
| Checkout principal | solo observación read-only (`git worktree list`): master ede1337 + wt-2018-19, wt-bloque6, wt-bloque7; ninguna escritura; los procesos `codex` ajenos de la Mac (probe en read-only) no se usaron ni se tocaron |

Claves de correlación observadas (IDs de sesión de laboratorio, descartable):

| Símbolo | `session_id` | Turno | Checkout (nativo `cwd`) | HEAD medido |
|---|---|---|---|---|
| A | `…801ef4` | `…31ef` | `[LAB]/wt-A` | `0bc5c74a` (rama-A) |
| B | `…cb2834` | `…9989` | `[LAB]/wt-B` | `ed4a0103` (rama-B) |
| X (ajeno) | `…f364e0`… | `…1b62` | `[LAB]/alien` | `03a5f795` |

Medición git por checkout (hook shim, verificable en fixtures):

| Checkout | `--show-toplevel` | `--git-dir` | `--git-common-dir` |
|---|---|---|---|
| wt-A | `[LAB]/wt-A` | `[LAB]/origen/.git/worktrees/wt-A` | `[LAB]/origen/.git` |
| wt-B | `[LAB]/wt-B` | `[LAB]/origen/.git/worktrees/wt-B` | `[LAB]/origen/.git` |
| alien | `[LAB]/alien` | `.git` | `.git` |

## Matriz de señales y amenazas

`autoriza` = puede acreditar por sí sola la raíz de la task.

| Señal candidata | Observado | ¿Autoriza? | Amenaza que la derriba |
|---|---|---|---|
| `git-common-dir` por sí solo | **idéntico** en wt-A y wt-B (`origen/.git`) | NO | dos worktrees del mismo clon lo comparten: no elige cuál produjo la evidencia de esta task (medido, no asumido) |
| ruta declarada (prosa del recibo) | generada por el agente | NO | el agente la escribe a mano; sin cruce contra git es solo una afirmación |
| `task_hash` | **ausente**: ninguna clave así en ningún payload | NO | no existe en el canal |
| mtime | **ausente** en payloads; mutable en disco | NO | no observado + falsificable |
| texto del recibo | generado por el agente | NO | acredita contenido declarado, no ejecución/repo/HEAD |
| `cwd` nativo del payload | presente en los 4 eventos; coincide con el cwd medido por el hook en los 8 fixtures | SÍ, ligado a sesión | ver amenazas contenidas abajo |
| `session_id` + `turn_id` | estables por sesión/turno; distintos entre A/B/X | SÍ, como ligadura | no nombran repo por sí solos; necesitan combinarse con `cwd`→git |
| `--git-dir` derivado del `cwd` | **distinto** por worktree (`worktrees/wt-A` vs `wt-B`) aunque compartan common-dir | SÍ, discrimina hermanos | — |
| `HEAD` derivado del `cwd` | distinto por checkout (A/B/X/origen, 4 SHAs) | SÍ, liga el árbol | un clon ajeno puede compartir objetos: el SHA solo no elige clon; la raíz se acredita por (toplevel canónico + git-dir + HEAD) junto al SHA sellado del review |

Amenazas contenidas sobre la señal positiva:

- `cwd` lo emite el CLI (codex), no la prosa del agente: mismo nivel de confianza que `session_id`. Un agente que hace `cd` a otro lado solo logra que su propia acreditación falle en cerrado (el HEAD/árbol no cuadra): fail-closed, no fail-open.
- El checkout ajeno X produjo eventos propios con `session_id`, `cwd` y HEAD distintos: nada de X es confundible con A o B, y resolver los paths de A desde el cwd de X (conducta actual de `PROJECT_ROOT` ambiental) mira el árbol equivocado — esa es la falla vigente que 21.4 corrige.
- Prefijo parecido (`wt-A` vs `wt-A-malicioso`), `..` y symlink/escape se rechazan exigiendo que `git -C <raíz> rev-parse --show-toplevel` canonice exactamente a la raíz citada y que los paths se resuelvan físicamente bajo ella sin enlaces que escapen.

## Veredicto: SEÑAL POSITIVA (decisión implementable)

La cadena turno→`session_id`/`turn_id`→`cwd` nativo→(`toplevel`, `git-dir`, `HEAD` por git) liga ejecución, repo, HEAD y worktree con datos del CLI + plomería git, sin confiar en prosa, mtime ni common-dir. **21.4 SE ACTIVA** con este diseño:

- El recibo cita la raíz acreditada como unidad (raíz absoluta + SHA del commit/árbol revisado).
- El validador canoniza la raíz (`--show-toplevel` debe devolverla exacta), exige `HEAD == SHA` citado, y resuelve los paths citados con `git -C <raíz>` (nunca con el cwd ambiental): acepta rastro/blast versionados en ese árbol exacto aunque el cwd pertenezca a otra sesión; rechaza untracked, dirty, escritos después del review, checkout ajeno, otro worktree/HEAD/repo, prefijo parecido, `..` y symlink/escape.
- Fuera del vínculo con el SHA, el contrato de contenido vigente no cambia; otros hosts intactos; el mutante que vuelve a `PROJECT_ROOT` ambiental queda rojo (lo mata el caso "cwd de otra sesión").

## Qué quedó `unknown` (con razón)

- `unknown`: si versiones futuras del CLI agregan un identificador de worktree/repo directo al payload (observado solo en 0.154.0; hoy se deriva por git desde `cwd`).
- `unknown`: SessionStart/UserPromptSubmit de B y X (perdidos por colisión de nombres del shim; irrelevantes para el veredicto: no aportan campos distintos a los conservados).
- No se renovó §8/D23; no se tocó el checkout principal, wt-bloque6 ni sesiones vivas ajenas.
- Phase 20 NO está cerrada formalmente (20.26 DRAFT): este bloque corre por orden del operador en el mismo run que 7–9; la implementación de 21.4 aterriza en rama sin merge hasta el cierre.

## Anexo: contexto medido por el shim en cada fixture

(Los fixtures guardan el payload nativo puro; esta tabla es la medición del
shim al recibirlo: `cwd` del proceso hook + plomería git.)

| Fixture | hook `cwd` | `--show-toplevel` | `--git-dir` | `--git-common-dir` | `HEAD` |
|---|---|---|---|---|---|
| 00 SessionStart (A) | `[LAB]/wt-A` | `[LAB]/wt-A` | `[LAB]/origen/.git/worktrees/wt-A` | `[LAB]/origen/.git` | `0bc5c74a` |
| 01 UserPromptSubmit (A) | `[LAB]/wt-A` | `[LAB]/wt-A` | `…/worktrees/wt-A` | `[LAB]/origen/.git` | `0bc5c74a` |
| 02 PostToolUse (X) | `[LAB]/alien` | `[LAB]/alien` | `.git` | `.git` | `03a5f795` |
| 03 PostToolUse (A) | `[LAB]/wt-A` | `[LAB]/wt-A` | `…/worktrees/wt-A` | `[LAB]/origen/.git` | `0bc5c74a` |
| 04 PostToolUse (B) | `[LAB]/wt-B` | `[LAB]/wt-B` | `[LAB]/origen/.git/worktrees/wt-B` | `[LAB]/origen/.git` | `ed4a0103` |
| 05 Stop (X) | `[LAB]/alien` | `[LAB]/alien` | `.git` | `.git` | `03a5f795` |
| 06 Stop (B) | `[LAB]/wt-B` | `[LAB]/wt-B` | `…/worktrees/wt-B` | `[LAB]/origen/.git` | `ed4a0103` |
| 07 Stop (A) | `[LAB]/wt-A` | `[LAB]/wt-A` | `…/worktrees/wt-A` | `[LAB]/origen/.git` | `0bc5c74a` |

En los 8 casos el `cwd` nativo del payload coincide con el `cwd` medido.
