# 20.21 — Costo/latencia y decisión sobre 16.7

Medición reutilizada (tdd:skip:medición): NO se corrió nada vivo. Toda cifra
cita evidencia ya mergeada. Lo no observado queda `unknown` con su razón;
ningún `unknown` equivale a PASS.

## Identidad de ESTA evidencia

| Campo | Valor |
|---|---|
| Fecha | 2026-09-13 |
| Checkout kit (esta evidencia) | `76e92bb7a757ae45f6faa5d242a0b3bcbbf2cba9` (HEAD == origin/master, árbol limpio) |
| Hook | sha256 `37e55640003afaff6d4a54cf6495afc73bec5799b86323fb7a317889fec78680` (4345 líneas, sin drift) |
| Drift del checkout | DRIFT declarada: el pin de referencia era `e0f7a25`; master avanzó con merges docs-only (20.20, cierre 20.15–20.17 #311). Hook SIN drift. |

## Evidencias reutilizadas (con el checkout/hook SHA con el que SE MIDIERON)

Regla del runbook (docs/phase20-mediciones-runbook.md L51-52): la evidencia
20.x reutilizada en otra fila exige declarar el checkout/hook SHA original.

| Evidencia | Checkout original | Hook original | Versión host | Ejecutable |
|---|---|---|---|---|
| 20.9 (`docs/evidence/phase-20/20.9/`) | `8e7402e8990cad8ec0ef54a6f1cab21cfccc4e29` | `37e55640…` (4345 líneas) | Claude Code `2.1.267` (drift vs pin `2.1.266` del runbook, declarada) | `claude -p --permission-mode bypassPermissions --allowedTools Bash --output-format json` |
| 20.10 (`docs/evidence/phase-20/20.10/`) | `d89a4ad…` (master post-#293) | `37e55640…` (4345 líneas) | Claude Code `2.1.267` | mismo ejecutable, headless `-p`, conductor lead (patrón 18.9) |
| 20.11 (`docs/evidence/phase-20/20.11/`) | `60d1ee9…` (master post-#294) | `37e55640…` (4345 líneas) | Claude Code `2.1.267` | mismo ejecutable, headless `-p`, conductor lead |

n = 1 por recorrido (una sola corrida viva por modo; sin repeticiones, sin
estadística posible). Todas las cifras son UNA muestra.

## Comparación: costo y latencia por recorrido

Campos `total_cost_usd`, `duration_ms` (pared) y `duration_api_ms` (tiempo de
modelo) leídos de los `runs/*.json` de cada evidencia. `duration_ms −
duration_api_ms` es sobrecarga local (proceso, I/O), NO espera humana: la
espera humana (decisión del operador) no quedó temporizada en ninguna
evidencia y se declara `unknown` donde aplica.

### 20.9 — sondas de un solo comando (2 turnos, 2 muestras)

| Recorrido | Turnos | Costo (USD) | Pared | Tiempo de modelo | CI | Espera humana |
|---|---|---|---|---|---|---|
| deny (`gh pr merge` negado) | 2 | 0.2946 | 14.2 s | 13.8 s | n/a (sin PR tocado) | n/a |
| allow (`saikit-merge.sh --help`) | 2 | 0.2654 | 8.3 s | 7.8 s | n/a | n/a |

### 20.10 — autopilot completo, bump 1.1.1 → 1.1.2 (PRs #9 + #10)

| Recorrido | Turnos | Costo (USD) | Pared | Tiempo de modelo | CI | Espera humana |
|---|---|---|---|---|---|---|
| turno 1 (sentinel → LISTO, pregunta «¿Mergeo?») | 61 | 5.0997 | 12.6 min (754.7 s) | 12.0 min (721.0 s) | verde (2 runs `test` + CodeRabbit); duración de pared `unknown` (la evidencia no la temporizó) | `unknown` (el operador eligió opción (b) fuera del turno; sin temporizar) |
| turno 2 (wrapper #10 + 2 merges + postmerge) | 46 | 7.2972 | 18.9 min (1132.4 s) | 17.3 min (1037.2 s) | verde ambos PRs; duración de pared `unknown` | `unknown` (dos sí explícitos + decisión (b); sin temporizar) |
| TOTAL 20.10 | 107 | ≈ 12.40 | ≈ 31.5 min | ≈ 29.3 min | — | — |

### 20.11 — cuidar-pr, tres modos sobre casos controlados

| Recorrido | Turnos | Costo (USD) | Pared | Tiempo de modelo | CI | Espera humana |
|---|---|---|---|---|---|---|
| revisar (PR #4, no modifica) | 24 | 4.7979 | 18.1 min (1088.6 s) | 17.5 min (1052.6 s) | verde viejo reutilizado (3 días, base inexistente) | n/a |
| solo-hilos (PR #11, 2 hilos) | 25 | 4.3941 | 11.1 min (668.1 s) | 10.6 min (637.0 s) | n/a | `unknown` (el `ask` se contestó fuera del turno) |
| cuidar (PR #4 → MERGEABLE) | 22 | 4.1982 | 10.3 min (618.1 s) | 9.9 min (596.7 s) | verde re-corrido: `test` 6 s + 3 s (runs 34446791997, 34446794447, medido contra la API) | n/a |

### Lectura con cargas EQUIVALENTES (advertencia explícita)

Las cargas NO son equivalentes entre filas: 20.10 resuelve un bump con dos
merges y ceremonia completa (107 turnos); 20.11 atiende PRs ya abiertos
(22–25 turnos); 20.9 ejecuta UN comando (2 turnos). La comparación honesta
es INTRA-fila, donde la tarea sí es comparable:

- Intra-20.11 (misma receta, tres modos, mismo host y checkout): revisar
  4.80 / solo-hilos 4.39 / cuidar 4.20 USD; pared 18.1 / 11.1 / 10.3 min. El
  modo `revisar` costó MÁS pared con igual número de turnos (24 vs 22–25):
  la dispersión viene del CONTENIDO (conflicto real, CI viejo que analizar),
  no de un tier — no hay ruteo por receta que comprar aquí porque los tres
  modos ya corren bajo la misma receta `cuidar-pr` sin distinción de tier.
- Intra-20.10 (turno 1 vs turno 2): 5.10 vs 7.30 USD; el turno 2 (dos merges
  + gate re-corrido ×2) costó más que el turno 1 (ceremonia de 61 turnos).
  El costo sigue al TRABAJO (merges, re-verificación), no a una etiqueta.
- 20.9 confirma el piso: un comando aislado cuesta ~0.27–0.29 USD y ~10 s.
  Todo lo demás es razonamiento sobre el caso, no sobrecarga del harness.

Ninguna evidencia mide el MISMO caso en DOS tiers distintos: el delta
costo/latencia atribuible al ruteo por receta es `unknown` (razón: no existe
la medición pareada; n = 1 por recorrido y sin grupo de control).

## Decisión sobre 16.7: SE CONFIRMA EL APLAZAMIENTO

16.7 (`model-routing.sh --task <receta>` ⇒ tier existente, fila `[Ruteo]`,
`Optional`) NO está pendiente: está cc:NO EJECUTADA por decisión declarada
del lead con el operador en el cierre de 16.9 (la corrección del cross-review
del 2026-08-30 dejó asentado que 16.9 sí incluía 16.7 en el rango 16.2–16.8
y aun así se cerró sin ella; ninguna fila quedó bloqueada; la Phase 17 no la
menciona).

Criterio explícito (exigido por la DoD de esta fila): adoptar 16.7 SOLO si
una medición pareada del MISMO caso en DOS tiers muestra una mejora de costo
o latencia atribuible al tier que pague la pieza (código + candado + ficha).
Lo observado en 20.9/20.10/20.11:

1. La dispersión de costo (0.27 → 12.40 USD) y latencia (8 s → 31.5 min)
   se explica entera por el TAMAÑO DEL CASO (comando único vs PR atendido
   vs autopilot con dos merges), no por el tier: todo corrió en el mismo
   host y sin distinción de tier.
2. Intra-receta (20.11, tres modos de `cuidar-pr`) el costo varía ±14 %
   por contenido, sin que exista a dónde enrutar: un router no compra nada
   donde no hay dos destinos con precio distinto medido.
3. El delta pareado por tier es `unknown` (sin medición), y `unknown` no
   reactiva: FAIL conserva FAIL, y lo no medido no autoriza código.

Decisión: SE CONFIRMA EL APLAZAMIENTO de 16.7. Se reutiliza su fila
existente (sin duplicar, sin implementar, sin hardcodear modelos en ningún
script/análisis/DoD de esta evidencia). Reactivación futura: solo con la
medición pareada descrita en el criterio.

## Qué quedó `unknown` o FAIL (con razón)

- `unknown`: duración de pared del CI en 20.10 (la evidencia acredita verde
  sin temporizar; solo 20.11/cuidar trae 6 s + 3 s medidos contra la API).
- `unknown`: toda espera humana (decisión (b) y síes explícitos de 20.10;
  `ask` de 20.11/solo-hilos) — ningún turno la temporizó.
- `unknown`: delta costo/latencia atribuible al tier (sin medición pareada;
  n = 1 por recorrido, cargas no equivalentes entre filas).
- `unknown`: costo/latencia en otro host que no sea Claude Code 2.1.267
  (16.9 ya declaró `unknown` el funcionamiento en otros programas).
- Ningún FAIL: las tres evidencias reutilizadas cerraron con DoD completa.

## Veredicto de la fila

Costo y latencia comparados con versiones, ejecutable y n declarados, CI y
espera humana separados, cargas equivalentes tratadas intra-fila con la
no-equivalencia entre filas declarada. 16.7: aplazamiento CONFIRMADO con
criterio explícito de reactivación; fila existente reutilizada, sin
duplicado, sin implementación, sin modelos hardcodeados. DoD completa.
Lista para cierre del lead.
