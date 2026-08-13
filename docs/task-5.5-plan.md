# Task 5.5 — Línea base y casos del target zcode (plan para GLM, **después** de 5.4)

> ## Estado de implementación (2026-08-12)
>
> **A–C + commit 0 HECHOS y verificados, sin commitar** (el operador decidió
> esperar a que el hook working-tree se asiente; `Plans.md:101` sigue `cc:TODO`).
> Branch `feat/5.5-zcode-baseline` perdida — el operador mergeó 5.6 (PR #7) a
> master durante la sesión y el trabajo 5.5 quedó en el árbol sobre master.
>
> - **Commit 0** (Plans.md staging reescrito): absorbido en HEAD por el merge 5.6.
> - **Parte A**: token `zcode` en `tools/golden-harness.sh` (exporta `ZCODE_*`,
>   no `TARGET`; emite `estado_host`), `hook-falso.sh` con `state/<host>/`, esc.
>   `03-zcode`, 6 casos en `test_golden_harness.sh` → **verde**.
> - **Parte B**: escenarios 17–25 + `tests/fixtures/README.md` → `test_fixtures_json` **verde (101 json)**.
> - **Parte C**: `--record` contra la fuente (hook HEAD `7dbe1566`) + diff revisado
>   (01–15 idénticos; 16 +1 línea separador; 23 = 3× exit 2; estado_host ok) +
>   `--check` verde + reproducible.
> - **pre-commit** (files 5.5): Passed.
> - **Bug encontrado y arreglado**: el bloque `estado_host` con `[ -n ] && printf`
>   devolvía non-zero sin estado → `generar` caía en `|| exit 2`. Cambiado a
>   `if/then`. El TDD contra el falso no lo pescó (el falso siempre escribe
>   estado); sí la grabación contra el fuente (esc. 17 sin armar).
>
> **PENDIENTE (no autónomo):**
> - **§D** (turno vivo zcode): STOP entregado al operador. Preflight OK (registro
>   5.4 + agentes 5.6 en sitio). `Plans.md:101` cierra `cc:完成` sólo con el §D.
> - **Commit 5** (docs spec § segundo host + README staging zcode + Plans cc:完成):
>   post-§D.
>
> **run.sh ROJO, NO por 5.5** (verificado): `test_hook_source`/`test_golden_baseline`
> fallan porque el hook working-tree está editado sin commitar (contrato
> expandido, sha `ef9a66bf` vs HEAD `7dbe1566`); `test_restore_vendor` LEAK por
> `docs/phase-6-codex-design.md` (Phase 6). Forzando el hook de HEAD, `--check`
> da verde (25 escenarios).
>
> **Al commitear 5.5 (cuando el hook se asiente):** `git add` selectivo de
> `tools/golden-harness.sh`, `tests/fixtures/arnes-falso/{hook-falso.sh,escenarios/03-zcode/}`,
> `tests/test_golden_harness.sh`, `tests/fixtures/escenarios/1[789]-* 2[0-5]-*`,
> `tests/fixtures/README.md`, `tests/golden/baseline.txt`. **Re-grabar la baseline**
> si el hook cambió (disciplina: quien cambia el hook re-graba).

`[Test]` `[lane:gate]` `[tdd:required]`.
**DoD íntegra en `Plans.md:101` — con UNA cláusula reescrita
abajo, no copiada:** (1) los escenarios de zcode tienen su bloque
en la línea base y `--check` es reproducible; (2) cada gate tiene
al menos un caso que pasa y uno que bloquea **en este target**;
(3) ~~staging por `<repo>/.zcode/config.json`~~ — **premisa
caída**, ver §Staging; la puesta en producción se verifica
**ejecutando** un turno real, no leyendo el user-config; (4) un
turno `-saikit` real en zcode arma, y uno pelado no. **Depende
de:** 5.4, 3.8 (3.8 ya `cc:完了`).

> **Esto NO registra el harness** (eso es 5.4) **ni inventa
> `TARGET=zcode`** (5.2 declaró que `TARGET=claude` alcanza).
> Es la línea base del segundo host + el turno vivo que **falle**
> el gate a propósito (omitir verifier). 5.4 deja el cableado y
> un smoke de armado; 5.5 es el que afirma que el gate *corta*
> en zcode y que `--check` lo vuelve a decir mañana.

## Este plan se escribe en paralelo a 5.4 — no se implementa todavía

**Cero `--record` de la línea base real** hasta que la *fuente*
tenga el fallback `ZCODE_*` → `TARGET=claude`, el budget zcode
= exit 2 y el fallback camel de PHASE. **Cero turno que falle
el gate** hasta que el user-config tenga el id `5.4`. Grabar
antes congela A10 (TARGET vacío ⇒ no hay secuencia) y el
budget decorativo (`continue:false`+exit 0).

No se espera el checkbox `Plans.md:99` ni `Plans.md:100`. Se
esperan **hechos**. El ciclo 5.3↔5.4↔5.5, si se leen los
renglones al pie de la letra, es este:

- 5.4 plan: cero append vivo hasta que 5.3 esté `cc:完了`
- 5.3: el STOP vivo (y por tanto el `cc:完了`) necesita el
  registro de 5.4
- 5.5, en el draft: esperar `cc:完了` de 5.4

Eso no cierra nunca. **Se rompe así** (Codex r1.1):

| Hecho (no checkbox) | Qué desbloquea |
|---|---|
| HOST ya está en el dest (`PROJECT_DIR="$STATE_ROOT/$HOST/$PROJECT_KEY"`, 5.3 código en master) | 5.4 puede `--host zcode` vivo. El renglón de 5.4 que pide `5.3 cc:完了` se lee como “HOST en DEST”, no como el marcador de Plans. No se reabre 5.4 acá |
| Fuente con TARGET-por-ZCODE + budget exit 2 + PHASE camel | A+B+C (`--record`) |
| User-config con id `5.4` bien formado (verificador en silencio) | §D vivo |
| 5.3 `cc:TODO` (solo STOP vivo) | **No bloquea nada.** §D paso 2 (estado armado, *antes* de quemar el presupuesto) cierra 5.3 |
| Replan / budget sigue exit 0 / no hay HOST en dest | No se graba. Este doc queda como evidencia |

El token `zcode` del arnés **sí** se TDD-ea contra
`arnes-falso` en cualquier momento; no se mezcla con el
`--record` real.

3.8 (`cc:完了`) ya está: el guardia de fallas grepea stdout/stderr,
no `exitCode`. 5.1 midió que en zcode `tool_response.exitCode`
**sí** viene. El escenario 24 de esta task es el caso que habría
vuelto a acreditar un runner roto si alguien re-encendiera esa
rama: `exitCode: 0` + `AssertionError` ⇒ `verified` se queda en 0.

## Cross-review del PLAN con Codex (1 ronda, 2026-08-12)

Tope quality-kit: máx 1 ronda, 2ª sólo con severidad alta, jamás
una 3ª **salvo que el operador lo pida**. Ronda 1: 3 altas + 4
medias, las 7 aceptadas e incorporadas abajo. **No hay 2ª**
salvo que el operador la pida.

### Ronda 1 (Codex, 2026-08-12)

1. **[alta] ACEPTADO+verificado** — 5.5 esperaba `5.4 cc:完了`,
   5.4 prohibe el append vivo hasta `5.3 cc:完了`, y 5.3 solo
   cierra después del registro de 5.4. Ciclo. **Fix:** la
   tabla de arriba espera *hechos* (HOST en dest, fuente 5.4,
   user-config 5.4), no checkboxes. 5.3 `cc:TODO` no bloquea.
2. **[alta] ACEPTADO+verificado** — DoD: cada gate pasa **y**
   bloquea. El 23 solo agota presupuesto; el 21 cierra en
   ciclo 0. Faltaba `g5_ciclo_consumido_no_impide_cerrar`.
   **Fix:** escenario 25.
3. **[alta] ACEPTADO+verificado** — `stop_gate` con
   `cycle >= MAX_CYCLES` (2) **borra** `harness-state.env`
   (`:1223-1228`) antes de `emit_budget_exhausted`. Tras el
   omitir-verifier el árbol zcode puede quedar vacío y el
   paso 4 de aislamiento era vacuo. Además “~4 pasadas” era
   el probe 5.2 (siempre exit 2), no el harness: acá son 2
   gate + 1 budget (estado borrado) y el Stop siguiente
   `emit_allow`. **Fix:** aislar **después del armado**,
   antes de quemar ciclos; corregir el conteo.
4. **[media] ACEPTADO+verificado** — `[ -r "$transcript_path" ]`
   (`:1096`) corta antes de `transcript_en_perfil` si el
   archivo no existe. El path fijo a un tmp inexistente **no**
   reconfirma A6; solo deja `tail` vacío (mismo observable).
   **Fix:** se declara así. A6 sigue siendo de 5.3.
5. **[media] ACEPTADO+verificado** — `normalizar` come
   `state/zcode/<key>` **antes** de emitir (`golden-harness.sh:108`).
   `--print` nunca muestra `state/zcode/`. **Fix:** el arnés
   emite `estado_host: zcode` (solo target `zcode`) leyendo
   el path **antes** de normalizar. 01–16 no ganan esa línea.
6. **[media] ACEPTADO** — diferir la corrección de
   `Plans.md:101` hasta el cierre deja el contrato oficial
   mintiendo durante toda la implementación. **Fix:** commit 0,
   antes de A–C.
7. **[media] ACEPTADO** — el gate `pre-commit --all-files` +
   `run.sh` estaba solo en el commit 3; el 5 todavía toca
   spec/Plans/README. **Fix:** commit 5 corre `pre-commit
   --files` de lo tocado; al cierre (después del 5) se
   repite `--all-files`. `run.sh` no se repite por docs.

Residual declarado: el renglón de 5.4 que pide `5.3 cc:完了`
antes del append **no se reescribe acá**; 5.5 lo interpreta
como “HOST en DEST”. 5.4 §D deja el registro puesto; 5.5
**no** corre `--quitar-zcode`.

---

## Premisas medidas (no re-litigar)

De **5.1** (forma):

- Override de proyecto (`<repo>/.zcode/config.json`) **ignorado**
  (`gri` / `config_project_hooks_ignored`). Registro = user-config.
- Forma dual snake+camel. El hook lee snake. `Agent` +
  `tool_input.subagent_type`. Alias `Task`↔`Agent` **sí**
  transporta: en zcode los eventos de delegación **llegan**.
- `CLAUDECODE` ausente. `ZCODE_SESSION_ID` / `ZCODE_PROJECT_DIR`
  presentes. `transcript_path` es tmp efímero (fuera del perfil).
- `permission_mode` / `mode` = `yolo`. `tool_response.exitCode`
  presente en Bash.

De **5.2** (salida):

- Forma 1 (`additionalContext`) aceptada. `decision:block`+exit 0
  aceptada. `exit 2` en Stop aceptada (4 pasadas).
- Esquema **no** estricto. `notice` ignorada (RN fail-open).
- `budget` (`continue:false`+exit 0) **ignorada**. 5.4 lo cambia
  a exit 2 **solo** en zcode.
- `TARGET=claude` alcanza. **No** se inventa `TARGET=zcode`.

De **5.3** (estado):

- Un solo archivo: `~/.claude/hooks/summonaikit-harness.sh`.
  `PROJECT_DIR=STATE_ROOT/$HOST/$PROJECT_KEY`. `HOST=zcode` si
  `ZCODE_*`, `claude` si `CLAUDECODE=1`, `other` si ninguno.
- `golden-harness.sh` **unsetea** `ZCODE_*` (y `CLAUDECODE`) para
  que `--check` no dependa del host que lo corre. El token nuevo
  de esta task es la **única** vía para volver a poner `ZCODE_*`.
- A6 en zcode = fail-open por tmp. **No** se agranda la allowlist.
  El gate vivo corre con `last_assistant_message`.
- STOP vivo de aislamiento: pendiente del registro de 5.4.

De **5.4** (cuando cierre; este plan lo da por hecho):

- Registro en `~/.zcode/cli/config.json`, 3 fases, UPS/Stop sin
  matcher, PTU cubre `Task|Agent`, id `5.4`.
- Fallback: `ZCODE_*` ⇒ `TARGET=claude`. A10 cerrado en zcode.
- `emit_budget_exhausted` en zcode ⇒ exit 2 (Claude intacto).
- `PHASE` lee `hook_event_name` y cae a `hookEventName`.
- STOP de 5.4 = arma + no pisa vecinos. **Un turno que falle el
  gate es esta task.**

---

## Staging — la cláusula que se reescribe (no se implementa el canal muerto)

El renglón de `Plans.md:101` dice:

> staging por `<repo>/.zcode/config.json` (el override de
> workspace que la guía del CLI declara) verificado ejecutando
> el registro, no leyéndolo —igual que la 2.4

Esa premisa **cayó en 5.1**. Copiar `tools/stage-override.sh` a
`.zcode/config.json` es exactamente la trampa que 2.4 midió y
además **no dispara** en 3.7.5-11. No se escribe ese archivo.
No se crea `tools/stage-zcode.sh`. No se toca
`tools/stage-override.sh`.

Lo que **sí** se conserva de 2.4 es el espíritu, no el canal:

> **La herramienta no lee el registro para creerle: lo ejecuta.**

En Claude el canal era el override de proyecto (un hook por
turno, estado aislado por `dirname $0`). En zcode el canal que
dispara es el **user-config** (5.4 ya lo appendeó) y el estado
lo aísla **HOST+proyecto+sesión** (5.3), no una segunda copia
del binario.

Traducción de la DoD para esta task:

| 2.4 (Claude) | 5.5 (zcode) |
|---|---|
| Poner el hook en `<repo>/.claude/hooks/` | Ya está en `~/.claude/hooks/` (un solo archivo) |
| El comando registrado elige repo vs global | No hay elección: el user-config apunta al mismo `$0` |
| Medir con `HOME` desechable ejecutando el comando | Medir **abriendo zcode** y mirando que el gate se mueva |
| Un `-saikit` arma, uno pelado no | Igual, en zcode, sobre un **repo descartable** |
| Un Stop armado bloquea | Igual, **omitir verifier** (acá sí llega `Agent`) |
| `--restore-vendor` | `--quitar-zcode` existe; **no se corre** al cerrar |

Aislamiento del riesgo vivo: repo descartable
(`C:\dev\saikit-captura-zcode` o hermano). El estado se llavea
por `PROJECT_KEY`; un turno ahí no pisa el estado de
`summonaikit-claude`. El user-config **sí** es global para
todas las sesiones zcode — eso es el producto, no un accidente.
No hay staging de proyecto que lo evite.

Veredicto que **no** cuenta como DoD: “el user-config tiene las
tres fases”. Eso es lectura. 5.4 ya lo afirma con el
verificador. 5.5 afirma que un turno **hizo** algo.

`Plans.md:101` se reescribe en el **commit 0**, antes de
A–C: el contrato oficial no puede seguir pidiendo
`.zcode/config.json` mientras se implementa. El README gana
el párrafo (zcode no tiene staging de proyecto; install =
`install-hook.sh --host zcode`) en el commit 5, con el resto
de docs.

---

## Qué cambia y qué NO

**NO cambia:**

- El dest del archivo. No hay segunda copia bajo `~/.zcode/hooks/`.
- `TARGET`. Sigue siendo `claude` (por fallback de 5.4). No se
  exporta `SUMMONAIKIT_HOOK_TARGET=zcode`.
- `emit_gate_failure` / forma 1 / `notice`.
- El budget de Claude (`continue:false`+exit 0).
- A6 / allowlist de transcripts.
- Los escenarios 01–16 (claude/cursor/auto). Su bloque en la
  línea base queda **byte-idéntico**.
- `tools/stage-override.sh` y el override de Claude.
- El user-config: 5.5 no appendea ni quita. Usa el registro de 5.4.
- `glm` (ya gateado por Claude).

**Cambia:**

- `tools/golden-harness.sh`: token de target `zcode`.
- `tests/fixtures/README.md`: `target` pasa a
  `claude | cursor | auto | zcode`.
- `tests/fixtures/escenarios/17-…` … `25-…` (nuevos).
- `tests/fixtures/arnes-falso/escenarios/`: un escenario
  `.zcode` para TDD del arnés, no del hook vivo.
- `tests/test_golden_harness.sh`: el token se afirma.
- `tests/golden/baseline.txt`: **solo** se le agregan los
  bloques 17–25. Diff revisado antes del commit.
- Spec § segundo host: bloque “Medido, Task 5.5”.
- `Plans.md:101` (cláusula de staging en el commit 0;
  `cc:完了` al cierre).
- README: zcode no tiene staging de proyecto.

---

## A) Token `zcode` en `golden-harness.sh` (TDD primero)

Hoy (`:267-271`) el arnés unsetea `ZCODE_*` y, si el filename
no es `auto`, exporta `SUMMONAIKIT_HOOK_TARGET=<token>`. Un
archivo `01.prompt.zcode.json` **hoy** haría
`TARGET=zcode` — la cosa que 5.2 prohibió — y `HOST=other`
(porque `ZCODE_*` sigue unset). La línea base grabaría el
camino equivocado.

### A1. Contrato del token

`target` del filename:

| token | env que deja el arnés |
|---|---|
| `claude` | `SUMMONAIKIT_HOOK_TARGET=claude` (igual que hoy). `ZCODE_*` unset. `CLAUDECODE` unset. `HOST=other` |
| `cursor` | `SUMMONAIKIT_HOOK_TARGET=cursor` (igual que hoy) |
| `auto` | no exporta TARGET ni PHASE (igual que hoy) |
| **`zcode`** | **no** exporta `SUMMONAIKIT_HOOK_TARGET`. Exporta `ZCODE_SESSION_ID=sess_golden_zcode` y `ZCODE_PROJECT_DIR=C:/dev/saikit-golden-zcode` (constantes, no la ruta del sandbox). `CLAUDECODE` unset |

Después de 5.4, `zcode` ⇒ `HOST=zcode` + `TARGET=claude` por el
fallback. Es el camino vivo (A10: el host no propaga
`VAR=val`). Si el arnés pusiera `TARGET=claude` a mano, el
golden **no** ejercitaría el fallback y un regress de 5.4
pasaría `--check`.

Las dos constantes son literales fijas. **No** se usa
`$sb/proyecto` como `ZCODE_PROJECT_DIR`: esa ruta cambia entre
corridas y, si algún día se filtrara al estado, rompería
`--check`. El hook solo mira “no vacío” para elegir HOST;
`PROJECT_KEY` sale del cwd, no de esa var.

Cualquier otro token sigue como hoy (se exporta como TARGET).
No se agrega un validador de tokens: fuera de alcance.

### A4. `estado_host` — el HOST que `--print` sí puede afirmar

`normalizar` (`:108`) reemplaza `state/zcode/<key>` por
`state/<PROJECT_KEY>` **antes** de emitir. Un `--print` no
puede mostrar `state/zcode/`; pedir “afirmarlo a ojo” era
imposible (Codex r1.5).

En `generar`, **después** de `instantanea_estado` y **solo**
si `objetivo=zcode`: leer el snapshot **sin** normalizar,
sacar el segmento `state/<host>/` y emitir una línea propia:

```
estado_host: zcode
```

Si no hay estado (escenario 17, o un Stop que ya borró), no
se emite la línea — el 17 no crea estado, no inventa host.
Si el token falló y el hook escribió `state/other/` (o
`state/claude/`), la línea dice eso y `--check` queda rojo
contra una baseline que espera `zcode`.

01–16 no ganan esta línea (siguen byte-idénticos). No se
agrega `--no-normalize`.

### A2. El hook falso tiene que **mostrar** el env

`tests/fixtures/arnes-falso/hook-falso.sh` hoy escribe
`phase=` y `target=` (`SUMMONAIKIT_HOOK_TARGET`). Si no escribe
`ZCODE_SESSION_ID`, el caso de A3 es vacuo: el arnés podría
olvidar exportarla y el registro se vería igual.

Agregar al estado del falso:

```
zcode_session=${ZCODE_SESSION_ID:-<sin-zcode>}
zcode_project=${ZCODE_PROJECT_DIR:-<sin-zcode-project>}
```

Un escenario nuevo `tests/fixtures/arnes-falso/escenarios/03-zcode/`
con `01.prompt.zcode.json` (payload mínimo, JSON válido). El
`--print` contra el falso tiene que grabar
`target=<sin-target>`, `zcode_session=sess_golden_zcode`,
`zcode_project=C:/dev/saikit-golden-zcode`.

### A3. Tests (`tests/test_golden_harness.sh`)

Sigue siendo contra el hook **falso**. No toca HOME. No corre
el hook vivo.

1. Escenario `03-zcode` presente ⇒ el registro nombra el
   escenario y el estado del paso trae las tres líneas de A2.
2. El mismo paso **no** trae `target=zcode` ni
   `target=claude` (TARGET no se exportó).
3. Un filename `.claude` **sigue** sin `zcode_session`
   (regresión: el unset de 5.3 no se rompió) **y** sin
   línea `estado_host:`.
4. Un paso `.zcode` que deja estado trae `estado_host: zcode`
   (A4). El falso hoy escribe `state/$KEY/` sin host: para
   que el caso no sea vacuo, el falso **pasa** a escribir
   `state/other/$KEY/` por defecto y `state/zcode/$KEY/`
   cuando `ZCODE_SESSION_ID` está seteado. 01-verde /
   02-bloqueo cambian de path; su baseline de sandbox se
   regraba en el mismo test (no toca
   `tests/golden/baseline.txt`).
5. Dos `--print` seguidos con `03-zcode` son byte-idénticos
   (las constantes no introducen no-determinismo).
6. `--record` + `--check` del falso, ahora con 3 escenarios,
   sigue en 0. El mutation-test existente (hook mutado ⇒
   `--check` = 1) no se toca.

Rojo medido **antes** de tocar `golden-harness.sh`: el caso 1
falla porque el arnés exporta `TARGET=zcode` y no pone
`ZCODE_*`. El caso 4 queda rojo hasta A4 + el falso que
escribe `state/zcode/`. Esos dos rojos acreditan el cambio.

```
bash tests/test_golden_harness.sh
```

No `tests/run.sh` en el loop.

---

## B) Escenarios 17–25 — un pasa y un bloquea por gate

No se clonan los 16. La DoD pide **cada gate**, no cada
escenario histórico. Clonar 01–16 con `.zcode` infla la línea
base (~18 min de `run.sh` no es el loop, pero `--check` del
golden ya es caro en MSYS) y mezcla defectos de forma Claude
(A8 de viñetas, A1 construido) que zcode no necesita regrabar.

Los 6 gates de `docs/spec/00-project-spec.md` § semántica
(`g1`–`g6`). Un directorio por afirmación. Prefijo `17+` para
no renumerar.

| # | directorio | Gate | Veredicto que se graba |
|---|---|---|---|
| 17 | `17-zcode-sin-armar` | G1 no-arma + G6 allow | Prompt **sin** `-saikit` + tool + stop. **No** crea estado. stdout vacío. exit 0 |
| 18 | `18-zcode-armado-contrato` | G1 arma + G6 inject | UPS con `-saikit`. Estado bajo `state/zcode/…`. stdout = forma 1 (`additionalContext` / contrato) |
| 19 | `19-zcode-evidencia-incompleta` | G2 bloquea + G6 block | Armado, sin subagentes, sin runner. Stop **bloquea** (exit 2 + `decision:block`) |
| 20 | `20-zcode-falta-verifier` | G3 bloquea | `Agent` implementer + `Agent` reviewer, **sin** verifier. Recibo en viñetas. Stop bloquea por secuencia. **Este es el análogo vivo del §D** |
| 21 | `21-zcode-turno-completo` | G2+G3+G4 pasan | implementer → verifier (runner que pasa) → reviewer, recibo en viñetas. Stop **allow**, borra estado |
| 22 | `22-zcode-sin-recibo` | G4 bloquea | Secuencia completa + verified, Stop **sin** etiquetas. Bloquea por recibo |
| 23 | `23-zcode-presupuesto` | G5 bloquea | Como el 08: tres Stop del mismo turno. 1/2 bloquea, 2/2 bloquea, el tercero es presupuesto agotado. **En zcode el tercero es exit 2**, no `continue:false`+exit 0. Ese delta es el de 5.4 y **tiene** que verse en el diff contra el 08 |
| 24 | `24-zcode-exitcode-cero-con-falla` | G2 / A11 en forma zcode | PostToolUse Bash con `tool_response.exitCode: 0` **y** stdout `AssertionError: …`. `verified` se queda en 0. Si alguien re-enciende la rama de `exitCode`, este escenario se pone verde de mentira y `--check` / el lab lo dicen |
| 25 | `25-zcode-ciclo-consumido-cierra` | G5 pasa | Un Stop que falla (ciclo 0→1) y después el turno completo (secuencia + verified + recibo en viñetas) **cierra** (exit 0, borra estado). Es `g5_ciclo_consumido_no_impide_cerrar` en este target: gastar un ciclo no es motivo de bloqueo. El 21 no lo cubre (cierra en ciclo 0); el 23 no lo cubre (solo agota) |

G6 “salidas por target” no necesita un 26º: en zcode las
formas son las de `TARGET=claude` (5.2). Quedan grabadas en
18 (inject), 19/20/22 (block exit 2) y 23 (budget exit 2).

Pausa declarada (G4 `g4_pausa_permite`): el 09 ya la graba en
claude y el canal vivo de zcode es `last_assistant_message`
(mismo campo). **No** se agrega un 25 de pausa. Residual
declarado: si un Stop camel-only + PAUSED se rompe, lo cubre
el caso C3 de 5.4, no esta línea base.

### B1. Forma de los payloads

Valores **sintéticos** (mismo criterio que 01–16: forma real,
cero texto/rutas de una sesión del operador). Convención:

- Filename: `NN.<phase>.zcode.json`. `phase` sigue
  `prompt|session|tool|stop|auto`.
- Dual snake+camel en las claves que 5.1 midió y el hook
  lee o que 5.4 usa de fallback: `hook_event_name` **y**
  `hookEventName`; en PostToolUse también `tool_name` /
  `toolName`. No hace falta copiar `traceId` / `turnId` /
  `toolCallCount`.
- `permission_mode`: `"yolo"` (medido). `session_id`:
  `sess_zcode_<escenario>` (forma zcode, no UUID de Claude).
- `cwd`: `C:\\dev\\demo` (igual que el resto; escape `\\`).
- **`transcript_path` NO usa `__TRANSCRIPT__` del sandbox.**
  Si el fixture apunta al companion dentro del sandbox,
  `PROFILE_DIR` del arnés **es** el sandbox y A6 **acepta**:
  se grabaría el canal de Claude (tail del transcript), no
  el vivo de zcode (`last_assistant_message`, tmp fuera del
  perfil). Valor fijo **inexistente**:

  `C:\\Users\\nobody\\AppData\\Local\\Temp\\zcode-claude-hook-golden\\transcript.jsonl`

  Sin archivo companion. `[ -r ]` falla y
  `transcript_en_perfil` **no se llama** (`:1096`) — **no**
  es una reconfirmación de A6; es el mismo observable (tail
  vacío). Recibo y texto del Stop van en
  `last_assistant_message` (5.1: el campo está). A6 sigue
  siendo medición de 5.3. No se inventa un token
  `__TRANSCRIPT_FUERA__` en esta task.
- PostToolUse de delegación: `tool_name: "Agent"`, rol en
  `tool_input.subagent_type` (`implementer` / `verifier` /
  `reviewer`). En zcode esos eventos **llegan** (alias). No
  se construye el vector A9 de Claude.
- Bash del 24: `tool_response` trae `"exitCode": 0` (forma
  zcode) **y** el texto de fracaso. El 21 (pasa) usa un
  runner limpio (`1 passed`, sin señales de 3.8).
- LF, JSON válido (`test_fixtures_json.sh`). Cero
  credenciales, cero rutas de perfil real, cero payloads
  cosechados de `saikit-captura-zcode`.

Cada directorio trae un `README` de 3–6 líneas (se copia como
comentario a la línea base), igual que 01–16.

### B2. De dónde **no** se copian

- No se copian 12/13/14 (defectos A1/A3/A2 ya cerrados).
- No se copia 16 (eventos dentro de subagente / A9 Claude).
- No se copia 03/04 (cursor).
- No se reescribe `gate_cases.sh` para duplicar G1–G6 con
  `LAB_ZCODE_*`. El lab de 5.4 ya cubre TARGET-por-ZCODE,
  budget-exit-2 y Stop camel. Esta task afirma lo mismo en
  la **línea base**, que es lo que `--check` mira cada
  commit. Duplicar la batería G no está en la DoD.

---

## C) `--record` — disciplina, no “y ya”

`test_golden_baseline.sh` compara `n_base` contra el número
de directorios. El día que existan 17–25, `--check` falla
por conteo **y** por bloques nuevos. Orden:

1. A verde (token + falso).
2. B en disco (fixtures + README de fixtures).
3. `bash tests/test_fixtures_json.sh` verde.
4. `bash tools/golden-harness.sh --check` **rojo** (esperado).
   No se “arregla” el test para que ignore los nuevos.
5. `bash tools/golden-harness.sh --record` contra el hook
   **fuente** (`SAIKIT_HOOK_VIVO` apuntando a
   `hooks/summonaikit-harness.sh` de este repo, lección 3.5).
   Si se graba contra el vivo y el vivo aún no tiene 5.4,
   el 23 sale con exit 0 y se congela el defecto.
6. `diff` de `tests/golden/baseline.txt`:
   - bloques `=== escenario 01-` … `16-` **idénticos**;
   - aparecen `=== escenario 17-` … `25-`;
   - el 23, tercer Stop: `exit 2` (no `continue:false` con
     exit 0);
   - el 25, segundo Stop: `exit 0` y estado borrado;
   - cada paso `*.zcode.json` trae una línea
     `estado_host: zcode` (ver A4). 01–16 **no** la tienen.
7. `--check` verde. Dos `--print` seguidos byte-idénticos
   (reproducibilidad; si no, las constantes de A1 no
   alcanzaron).

El header de la línea base (sha/bytes/líneas del hook) **sí**
cambia si el hook cambió: está fuera de la comparación. No se
edita `baseline.txt` a mano.

TDD del *contenido* de 17–25: el rojo de `--check` post-B
es el rojo. No se inventa un `test_zcode_baseline.sh`
aparte. `test_golden_baseline.sh` es el oráculo.

---

## D) STOP vivo (después de A–C verdes y de 5.4 registrado)

No es el TDD. Es “ejecutar el registro, no leerlo” + “un
`-saikit` arma y uno pelado no” + el turno que **falla** el
gate (lo que 5.4 dejó explícito).

Preflight, GLM, **antes** de llamar al operador:

```
bash tools/check-hook-registration.sh --zcode-config "$HOME/.zcode/cli/config.json"
# silencio
# dest = NUESTRO_IDENTICO y tiene la linea 5.3
# cksum de SessionStart / tokentracker (vecinos) se anota
```

Si el verificador grita, esto no es 5.5: se vuelve a 5.4.
No se “completa” el registro desde acá.

Tarjeta:

```
STOP — Gon, no GLM.

Repo: C:\dev\saikit-captura-zcode (o cualquier git descartable).
NO glm. Cerrá zcode y abrí zcode de nuevo (fotografía los
hooks al arrancar).

1. Prompt PELADO (sin -saikit), corto.
   GLM afirma: no hay harness-state.env nuevo bajo
   ~/.claude/hooks/state/zcode/<key-de-ese-repo>/.

2. Prompt CORTO con -saikit. No hace falta delegar.
   GLM afirma: el estado cayó bajo state/zcode/… y el
   contrato se inyectó (oráculo 5.2: model-io, mensaje
   system "UserPromptSubmit hook additional context").
   **Dejar este estado vivo.** No seguir al 4 todavía.

3. (cierra 5.3 — AHORA, con el estado de zcode todavía
   en disco). En el MISMO repo, un prompt -saikit de
   Claude Code (o glm, que es exec claude). El estado de
   Claude cae bajo state/claude/… . El
   `harness-state.env` de zcode del paso 2 sigue intacto
   (mtime/cksum). Al revés también: un Stop de Claude no
   borra el de zcode. Medirlo DESPUÉS de quemar ciclos
   (paso 4) es vacuo: `cycle >= MAX_CYCLES` borra el
   archivo (`:1223-1228`).

4. Prompt con -saikit que NO lance el subagente verifier
   (implementer sí, reviewer si quiere; verifier no).
   En zcode los eventos Agent SÍ llegan (5.1), así que
   omitir verifier es un fallo de verdad, no el A9 de
   Claude. El Stop tiene que BLOQUEAR. Conteo del
   harness (no el del probe 5.2): 2× `emit_gate_failure`
   (exit 2, estado sigue) + 1× budget (exit 2, estado
   **borrado**). El Stop siguiente, sin estado, es
   `emit_allow`. No se exige "4 pasadas".
```

Oráculos, todos de ejecución, ninguno es “leí el JSON”:

- Path de estado (`find ~/.claude/hooks/state/zcode -name harness-state.env`).
- model-io de la sesión (inyección).
- Conteo de Stops / `decision:block` (bloqueo).
- Vecinos del user-config: cksum igual que el preflight.
- Claude `settings.json` y el dest del hook: **no** cambiaron
  (5.5 no los escribe; si cambiaron, alguien se equivocó).

`--quitar-zcode` **no** se corre. El registro se queda: es
la puesta en producción. Si el operador quiere rollback
después, 5.4 ya documentó el comando.

Si el operador no puede hacer el §D: A–C se commitean;
`Plans.md:101` se queda `cc:TODO` hasta el vivo. No se
cierra con “el golden ya cubre el fail-the-gate”. La DoD
pide el turno real.

### D2. Qué **no** se mide otra vez

- `hooks.enabled` / matcher / forma del wrapper: 5.4.
- Las 4 formas de stdout: 5.2.
- Diff de forma de payloads: 5.1.
- Que `gri` ignore `.zcode/config.json`: 5.1. No se vuelve
  a escribir ese archivo “para confirmar”.

---

## E) Entregables

### E1. Spec § El segundo host

Bloque “Medido, Task 5.5”: línea base con token `zcode`;
cada gate pasa+bloquea en este target; A6 fail-open
reconfirmado (fixtures sin transcript de perfil); budget
zcode grabado como exit 2; **no hay** staging de proyecto;
la puesta en producción se verificó ejecutando (turno
pelado / arma / omitir verifier). Sin diario.

### E2. `Plans.md:101`

La cláusula de staging se reescribe en el **commit 0** (el
texto de hoy miente; no se espera al cierre). `cc:完了 [<sha>]`
**solo** si: `--check` verde con los 9 bloques nuevos (17–25),
01–16 idénticos, y el STOP del §D (o `cc:TODO` explícito).
Convención 4.1.

Texto propuesto para el renglón (al cerrar, no ahora):

> Los escenarios de zcode tienen su bloque en la línea base
> y `--check` es reproducible; cada gate tiene al menos un
> caso que pasa y uno que bloquea **en este target**; la
> puesta en producción se verifica **ejecutando** un turno
> zcode (no leyendo `~/.zcode/cli/config.json` ni escribiendo
> `<repo>/.zcode/config.json` — ese override lo ignora este
> CLI); un turno `-saikit` real en zcode arma, uno pelado no,
> y uno que omite verifier bloquea.

### E3. `Plans.md:99` (5.3)

Si el paso 3 del §D (aislamiento con el estado de zcode
todavía en disco) se midió: 5.3 pasa a `cc:完了` en el
mismo cierre (o en un commit `docs` hermano). Si no se
midió, 5.3 se queda `cc:TODO` y se declara. No se cierra
5.3 con el lab otra vez.

### E4. README

Un párrafo bajo instalación o un sub-bloque de staging:
zcode no tiene override de proyecto; el install es
`bash tools/install-hook.sh --host zcode`; el rollback es
`--quitar-zcode`. No se promete un `stage-override` para
este host.

### E5. `tests/fixtures/README.md`

`target: claude | cursor | auto | zcode`, con la tabla de
A1 (qué env exporta cada uno) y la nota de que `zcode` **no**
es un valor de `SUMMONAIKIT_HOOK_TARGET`.

---

## F) Commits

0. `docs(5.5): Plans.md ya no pide staging .zcode/config.json`
   — E2 del renglón, **antes** de A–C (Codex r1.6). El
   status sigue `cc:TODO`.
1. `test(5.5): golden-harness entiende target zcode`
   — A: hook falso + `test_golden_harness.sh` + el cambio
   del arnés (`estado_host` incluido). Rojo luego verde.
   No toca la línea base real.
2. `test(5.5): escenarios zcode 17-25`
   — B: fixtures + README de fixtures. `--check` queda rojo
   (conteo). No se commitea una baseline a medias.
3. `test(5.5): linea base graba el bloque zcode`
   — C: `--record` revisado. Diff = header (si el hook
   cambió) + bloques 17–25. 01–16 idénticos.
4. **STOP** §D.
5. `docs(5.5): zcode en produccion, sin staging de proyecto`
   — E: spec + Plans 5.5 `cc:完了` (+ 5.3 si el paso 3 del
   §D) + README.

TDD en el archivo del test, no `run.sh`. Gate del commit 3:
`pre-commit run --files` de lo tocado, luego `--all-files`
+ `tests/run.sh`. Gate del commit 5: `pre-commit run
--files` de spec/Plans/README. **Al cierre** (después del
5) se repite `pre-commit run --all-files` sobre el estado
final; `run.sh` no se repite por un commit de docs. Nunca
`--no-verify`. WSL no es atajo (el hook es MSYS-dependiente;
A6/`cygpath` no se validan en WSL).

---

## Límites

1. Un solo archivo de hook. HOST lo separa (5.3).
2. No se escribe `<repo>/.zcode/config.json`.
3. No se crea `tools/stage-zcode.sh`.
4. No se pone `TARGET=zcode` ni se exporta como TARGET el
   token del filename.
5. No se clonan los 16 escenarios.
6. No se reescribe `json_string_field` ni A6.
7. No se cambia el budget de Claude.
8. No se toca el user-config (ni append ni `--quitar`).
9. No se cosechan payloads reales al árbol (forma sí,
   valores no; lección 1.4 / 5.1).
10. El gate sigue **advisory**.
11. `glm` ≠ `zcode`.
12. No se implementa A–C/`--record`/§D hasta los *hechos*
    de la tabla de arriba (no el checkbox de 5.3/5.4).

## Cross-review del PLAN

Ronda 1 hecha (3 altas + 4 medias, las 7 en el cuerpo).
**No hay 2ª** salvo que el operador la pida. 3ª sólo si
vos la ordenás.
