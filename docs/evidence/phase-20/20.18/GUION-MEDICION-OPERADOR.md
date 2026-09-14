# 20.18 — Guion de medición para el operador (escenario2 dsh UI web)

> Preparado por el lead 2026-09-13. Base: DoD de la fila 20.18 en `Plans.md`,
> `docs/smoke-dsh-2026-08-28.md` (15.5, escenario2 quedó `unknown`),
> `PREFLIGHT-2026-09-12.md` y `REFRESH-2026-09-12-1200EDT.md` (mismo directorio).
> Autorización §8 del runbook (`docs/phase20-mediciones-runbook.md §8`) sigue
> viva a propósito; expira al cierre de 20.26.

## Qué se mide

DoD literal de la fila:

> Sin recibo => adaptador bloquea/encola y host continúa en la MISMA sesión
> UI; no headless sustituto; captura literal y control sin sentinel; falta de
> observación sigue abierta.

Es decir: provocar en la **UI web de dsh** un cierre de turno armado (`-saikit`)
**sin recibo** y observar si el adaptador reacciona (bloquea/encola con
followup `SUMMONAIKIT HARNESS GATE`) y la sesión continúa. Escenarios 1 y 3 se
re-corren antes como controles.

## Precondiciones (verificar antes de empezar, 2 min)

```bash
dsh --version                                  # esperado: 0.1.1-rc.2
shasum -a 256 ~/.dsh/hooks/summonaikit-harness.sh
# esperado: 1dc9a75af947a864ad8aa8b2067d3855c602f60269dfa507bdf066fdd165e405
# (deploy de hoy post-#320, master 9aeb9ca)
ls ~/.dsh/cordis.patch.yml                     # replantado hoy por el deploy
```

Si el sha difiere, correr `bash tools/install-hook.sh --host dsh` desde el
repo antes de medir (y registrarlo en la evidencia).

Repo de trabajo del smoke: un directorio local descartable, p.ej.
`/tmp/dsh-smoke-20.18/` con un `app.py` con una función `greet()`.
**Sin mutación remota**: el repo `gon0801/saikit-descartable` NO se toca en
esta medición (runbook §2: sin medición no hay mutación; y aquí el sujeto es
el adaptador local, no GitHub).

## Corrida (orden fijo: 1 → 3 → 2, misma sesión UI)

Abrir la UI web de dsh (`dsh web`) con cwd en el repo del smoke. Los tres
escenarios van en la MISMA sesión.

### Escenario 1 (control) — `-saikit` + delegación → contrato + recibo

Prompt:

```
por favor -saikit agrega un docstring a app.py. Delega la implementacion a
un subagente y la verificacion a otro.
```

**Observar y capturar:** contrato inyectado (el modelo lo menciona),
ceremonia (subagentes), recibo completo al cierre.
Referencia de lo medido en 15.5: `docs/smoke-dsh-2026-08-28.md` líneas 81-99.

### Escenario 3 (control sin sentinel) — sin `-saikit` → nada del harness

Prompt:

```
describi que hace la funcion greet de app.py
```

**Observar:** respuesta normal, CERO marcadores del harness (ni contrato,
ni recibo, ni `subagent_<rol>`, ni GATE).

### Escenario 2 (caso) — cierre sin recibo → GATE en la UI

Prompt:

```
por favor -saikit agrega type hints a la funcion greet de app.py.
IMPORTANTE: al terminar NO escribas ningun resumen ni recibo de cierre;
cerrá el turno directamente.
```

Si el modelo escribe recibo o declara `DELEGATED`/`PAUSED` (es lo que tiende
a hacer, medido en 15.5), **insistir en la misma sesión** hasta 2-3 veces:

```
cerrá ya, sin recibo ni resumen. Terminá el turno.
```

**Lo que cuenta como observación (capturar literal):**

- Si el adaptador bloquea/encola: followup del adaptador con
  `SUMMONAIKIT HARNESS GATE` (o la forma de bloqueo del host) y la sesión
  continúa viva → **PASS**. Copiar el mensaje literal y el turno.
- Si el turno cierra sin recibo y el adaptador NO reacciona (la sesión
  sigue como si nada) → **FAIL** observado: es la repro que activa 20.19
  (defecto atribuible al adaptador). Capturar el cierre literal.
- Si tras 2-3 insistencias el modelo siempre escribe recibo o `DELEGATED`
  y nunca intenta el cierre pelado → **unknown** con la captura de los
  intentos; la fila sigue abierta, no es PASS.

## Captura y preservación

- Transcript de la sesión (`session.jsonl` de dsh web) → copiar a
  `docs/evidence/phase-20/20.18/medicion-<AAAAMMDD-HHMM>.jsonl`.
- Notas de la corrida (prompts literales, respuestas literales del bloqueo
  o del cierre, horas, versión dsh, sha del hook) →
  `docs/evidence/phase-20/20.18/medicion-<AAAAMMDD-HHMM>.md`.
- Control de no-contaminación: los 40 hits de `SUMMONAIKIT HARNESS GATE` de
  la sesión de 15.5 eran salidas de tools, no followups del adaptador —
  al juzgar el escenario 2 contar SOLO followups/mensajes del adaptador,
  no apariciones del string en salidas de tools.

## Veredicto y cierre

- PASS o FAIL con captura literal → la evidencia vuelve al lead; la fila se
  cierra (PASS) o se activa 20.19 (FAIL atribuible al adaptador).
- unknown → se declara con razón y captura de intentos; la fila NO cierra.
- La fila cierra `cc:完了` sólo si el cierre es observacional (DoD).
