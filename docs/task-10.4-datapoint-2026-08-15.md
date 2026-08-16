# Task 10.4 — primer datapoint post-Phase 10 (2026-08-15)

NO es la medición de cierre de la 10.4: eso exige UNA task real comparable
corrida con `-saikit` (ceremonia completa) y UNA con `-saikit:fast`,
cronometradas con el método del transcript (gaps por evento, como la medición
2026-08-13). Esto es lo medible HOY, registrado para que la medición limpia
tenga contra qué compararse. La fila 10.4 queda `cc:TODO`.

## Costos medidos en las sesiones reales que ejecutaron la Phase 10 (zcode)

Ceremonia completa (carril full), tareas multi-repo con cambio de contrato:

- Ejecución de la Phase 10 (10.1–10.3, un implementer): **100 min / ~18.5M
  tokens / 122 tool uses**. Incluye la suite de 18 min UNA vez (regla de la
  fase respetada) y las auditorías de línea base.
- P0–P3 del retro (9.10 + 10.5, un implementer): **103 min / ~23.9M tokens /
  92 tool uses**, incluyendo la iteración del CI (3 corridas de `gh pr checks`).
- El turn de la Phase 7 de kimi + absorciones de drift + paridades 6.3–6.5
  (7 dispatches con 2 ciclos de revisión): **~88 min / ~14M tokens** sólo el
  implementer; verifier ~30 min (3 rondas), reviewer ~13 min (2 rondas).
- Lectura del patrón: el costo dominante sigue siendo el implementer que
  reconstruye contexto (la regla de briefings quirúrgicos del lado kimi
  ataca exactamente esto; su efecto se medirá cuando se use).

Contra el baseline 2026-08-13 (task unitaria ≈ 4 h: implementer 2h19 + verifier
58 m + reviewer 32 m; suite ×3): las sesiones de arriba NO son comparables
limpio (multi-repo, ciclos de revisión con hallazgos reales), pero ninguna
superó ~2h15 de suma de roles — y los hallazgos del reviewer eran defectos
reales (escotilla DELEGATED, ROLE FALLBACK, VERIFY_SKIP_RE, deploy viejo), no
ruido. La ceremonia encontró defectos en TODAS las rondas; el problema medido
era el costo, no el valor.

## Wins medidos duros (no estimados)

- **Suite en CI Linux (10.5, PR #18): ~18 min → 1m32s–1m38s** (−86%), checks
  verde. Local MSYS2 sigue siendo ~18 min; el CI corta el ciclo de revisión
  post-PR.
- **El gate de verificación vuelve a ser satisfible en hosts sin transcript**
  (9.10, PR #17): `bash tests/run.sh` ahora acredita `verified` — las dos
  sesiones de arriba cerraron sus turns con skip declarado por regex que no
  conocía el runner; ese camino muerto se cerró.
- **Roles acreditables en zcode**: matcher de PostToolUse con `Agent` (acción
  de operador, 2026-08-15, backup en settings) — los ROLE FALLBACK declarados
  en los receipts anteriores ya no deberían hacer falta.

## Pendiente para el cierre honesto de la 10.4

1. Task real comparable con `-saikit` (full) cronometrada por gaps de eventos.
2. Task real chica con `-saikit:fast` — todavía corrió NINGUNA: el carril se
   deployó el 2026-08-14 y no hubo uso real todavía. Objetivo: ≤ 15 min.
3. Objetivo full: ≤ 1 h. Con el CI en ~1.5 min y la suite una-vez-por-cambio
   ya en el contrato, la parte mecánica dejó de ser la excusa.

---

# Datapoint 2: carril `fast` — Task 10.10 (2026-08-15)

Primer uso real del carril `-saikit:fast`. Prompt que armó el turno:
`-saikit:fast implementá la task 10.10 del plan`. Medido con el mismo método de
gaps por evento sobre el transcript de la sesión, acotado a la ventana de la
task (15:43:29 → 17:16:00 local).

| Métrica | Valor |
|---|---|
| Span | **92.4 min** (objetivo del DoD: ≤ 15 min) |
| Modelo pensando | 3.6 min — **4%** |
| Herramientas | 88.9 min — 96% |
| Llamadas a herramienta | 21 |
| **Espera pura bloqueado** (`TaskOutput`) | **60.1 min — 68% del tiempo de herramientas** |

Las diez llamadas de más de 1 minuto son 85.3 min, el 96% del tiempo de
herramientas. Seis de ellas son `TaskOutput` de 10 min clavados: **una sola
corrida de la batería completa, poleada seis veces**. Las otras cuatro (5.6 a
6.8 min) son las corridas de red/green del archivo de casos — el trabajo real.

## Qué dice el número (y qué NO dice)

**La ceremonia no es el costo.** Con el modelo pensando 4% del span, no queda
lugar donde esconder un sobrecosto de ceremonia: el carril `fast` hizo lo que
prometía — cero subagentes, cero ciclos de revisión extra. Descontando la
espera de la batería, el trabajo entero (entender la fila, escribir el fixture,
el caso y la mutación, medir las dos direcciones, corregir dos veces) fue
**~25 min**. Eso sí está en el orden del objetivo.

**El costo es la batería local, y ya tiene arreglo.** La 10.5 dejó la suite
corriendo en CI Linux en ~1m32s. Esta task la corrió **local**, donde tarda
~10 min y además compitió por CPU con la corrida concurrente de la sesión de
GLM (contención medida: 3×). El objetivo de 15 min no es inalcanzable — es
inalcanzable *corriendo la batería local y esperándola*.

## Evidencia directa para la fila 10.11

Esta es la primera task ejecutada **después** de que la 10.6 empezara a
inyectar las reglas permanentes en cada `SessionStart`. De las tres reglas:

- **Regla 1** (batería completa UNA vez por tarea, al final; red/green sobre el
  archivo que tocás) — **se cumplió**. Hubo una sola corrida completa; las
  cuatro corridas intermedias fueron del archivo de casos.
- **Regla 2** (no quedarse bloqueado esperando un job en background) — **se
  violó**, y esa violación sola es el **65% del reloj de pared**.

O sea: el texto alcanzó para la regla que cambia *qué* corrés, y no alcanzó
para la que cambia *qué hacés mientras corre*. Ese es exactamente el dato que
la 10.11 pedía antes de decidir si se construye un candado duro — con la
lectura extra de que el candado no haría falta si la batería corriera en CI,
que es donde la 10.5 ya la puso. **Antes de diseñar `PreToolUse`, la palanca
barata es usar el CI que ya existe.**

## Estado del cierre de la 10.4

1. Task con `-saikit` (full) cronometrada — **sigue pendiente**: necesita que el
   operador mande un turno armado sin `:fast` (candidata: 10.8).
2. Task con `-saikit:fast` — **hecha**: 92.4 min, desglosada arriba.
3. Objetivo full ≤ 1 h: no medido todavía.

---

# Datapoint 3: carril `full` — Task 10.8 (2026-08-15)

Prompt que armó el turno: `-saikit implementá la task 10.8 del plan`. Mismo
método de gaps por evento, ventana 17:39:50 → 20:14 local.

| Métrica | Carril `fast` (10.10) | Carril `full` (10.8) |
|---|---|---|
| Span | 92.4 min | **154.2 min** |
| Objetivo del DoD | ≤ 15 min | ≤ 60 min |
| Modelo pensando | 3.6 min (4%) | **24.8 min (16%)** |
| Herramientas del lead | 85 min (92%) | 35.9 min (23%) |
| Subagentes | 0 | **3** (implementer, verifier, reviewer) |

## Los dos carriles fallan su objetivo por motivos OPUESTOS

En el carril `fast` el 68% del reloj era espera bloqueada sobre **una corrida
de la batería local**. En el `full` las herramientas del lead bajan a 23% y lo
que domina es otra cosa: el ~61% restante del span es **tiempo de pared de los
subagentes**, que corren asincrónicos.

Duraciones medidas de cada uno: implementer **52.5 min**, reviewer **23.7 min**,
verifier ~24 min (lo maté yo, ver abajo). Los dos que rindieron suman **76 min**
de pared. Ese es el piso de la ceremonia, y **ningún CI lo arregla**: no es
cómputo esperando, es razonamiento de otro agente.

Consecuencia directa para el objetivo: **≤ 1 h es inalcanzable mientras cada
subagente tarde 25-50 min.** O se mueve el número, o se acota el alcance que se
le delega a cada rol. Fingir que el objetivo se cumple sería el error que el
propio DoD prohíbe ("si no se cumple, el residuo se mide y se decide").

## Desglose honesto del residuo (154 min − 60 de objetivo = 94 de exceso)

1. **Ceremonia propiamente dicha: ~76 min.** Es el costo real del carril.
2. **Colisión entre sesiones: ~35-40 min, y NO es culpa del carril.** A mitad
   de la task la otra sesión mergeó el PR #27 y **redeployó el hook vivo**. Eso
   obligó a: mergear master, regrabar la línea base entera contra el hook nuevo
   (6.5 min), re-auditar el diff, y **tirar los ~24 min del primer verifier**,
   que estaba comparando una copia rota de MI hook contra el hook vivo de la
   otra sesión — resultados inconsistentes por construcción.
3. **Prueba negativa: 10 min.** No es residuo, es la evidencia que distingue un
   escenario que sirve de red de uno decorativo.

## Lo que el carril `full` compró por ese tiempo

Esto es lo que el `fast` no habría dado, y conviene medirlo antes de decidir
que la ceremonia "sobra":

- El **implementer encontró un bug real** que yo no había previsto: en fase
  `session` el `task_hash` es un cksum del input entero, así que el token
  `__TRANSCRIPT__` metía una ruta de sandbox distinta por corrida y rompía la
  reproducibilidad de `--check`. Lo detectó con un FAIL real, no por intuición.
- El **reviewer refutó una objeción mía con evidencia**: yo sostenía que omitir
  `transcript_path` dejaba al escenario 34 como única excepción; los escenarios
  03 y 04 y el constructor canónico `hook_lab.sh:232` tampoco lo llevan. Mi
  cambio propuesto habría *creado* la inconsistencia que yo creía evitar.
- El pensamiento del lead sube de 3.6 a 24.8 min. No es desperdicio: ahí está
  la auditoría del regrabado y la detección de la colisión.

## Estado del cierre de la 10.4

Las tres mediciones que la fila pedía están hechas: contrato (medido antes),
carril `fast` (Datapoint 2) y carril `full` (este). Lo que queda es **una
decisión, no otra medición**: mover los objetivos del DoD a números alcanzables
o acotar lo que se delega. Con el dato en la mano, la lectura es que el `fast`
se arregla con el CI de la 10.5 y el `full` no se arregla con infraestructura.
