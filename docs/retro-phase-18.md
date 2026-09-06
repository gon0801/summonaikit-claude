# Retro Phase 18 — el autopilot (cierre documental, 2026-09-06)

La fase que le puso botón al gate: recetario completo (`cuidar-pr`), veredicto
sellado, gate de merge fail-closed, aviso post-merge y setup por repo. Diseño
en `docs/phase-16-18-recetario-autopilot-design.md`, medición viva en
`docs/smoke-autopilot-2026-09-05.md`, límites en el spec § Límites MEDIDOS de
la Phase 18. Esta nota es la retro: qué cambió en el camino, qué dolió y qué
queda pendiente sin fingir que cerró.

## La decisión que partió la fase (2026-08-30)

El diseño original mergeaba solo con un permiso general. El 2026-08-30, sobre
~15 PRs de un día con una veintena de hallazgos de bots —varios válidos,
otros refutados midiendo—, el operador decidió: **el autopilot prepara y
para**. El merge exige el sí explícito del turno (`--confirmado`, que repite
el gate), el sentinel sigue siendo por turno, y el revert automático SE CAE:
D19 queda reducida a aviso con el comando listo. Si el operador no mira el
aviso, nada deshace el cambio solo — pérdida declarada, no bug escondido.
La D24/18.11 (negar el merge a pelo) pasó a valer más: ya no protege un
automatismo, protege el punto donde el humano decide.

## Lo que la medición viva enseñó (18.9)

Tres escenarios en `gon0801/saikit-descartable` con Actions reales, sesiones
grok headless, midió el lead:

- **esc1 (verde ⇒ merge): NO observado — y se cierra declarándolo.** El gate
  cortó en cadena con 4 razones nombradas y debajo quedó el gap real (sello
  ciego en grok). El comportamiento del agente fue exactamente el pedido:
  ceremonia completa, parar y preguntar, merge solo por la vía autorizada,
  NO-MERGE literal, sin atajos.
- **esc2 y esc3: observados completos.** Frenar ante CI rojo (PR cerrado sin
  mergear, razón literal) y avisar tras un merge rojo (ROJO exit 1, nada
  ejecutado, revert por receta + `--revert-de` hasta MERGE-OK).
- **Costo medido:** ~120-230k tokens y 8-18 min de pared por PR.
- Cada hueco medido abrió su fila con su evidencia (18.25 parse de `gh`,
  18.26 sello, 18.27 recibo headless) en vez de parchearse en caliente.

## Choques por checkout compartido (y la corrección)

La ola paralela de las filas 18.5/18.6/18.7/18.17 partió los ARCHIVOS pero no
los DIRECTORIOS de trabajo: los cuatro diffs salieron disjuntos y los cuatro
PR mergeables, pero el reflog del checkout principal rebotó ocho veces entre
dos ramas y el rastro de la 18.6 registra que su WIP se perdió dos veces. Una
rama en curso quedó instalada en el perfil real, el vivo derivó de master y
el deploy posterior dio REPARADO donde se esperaba no-op
(`docs/deploy-log.md`, PR #163).

El mismo origen dio la doble lectura REAL vs NO-OP del deploy de la 18.18:
el implementador deployó desde SU rama para regrabar la golden (YA AL DIA) y
el lead, que había repuesto el vivo a master, obtuvo REPARADO con backup. Las
dos lecturas eran ciertas en su momento; el problema era que dos sesiones
deployaban el mismo artefacto en distinto orden. Regla que quedó: **el
deploy post-merge y su registro son del lead, uno solo por PR.**

**Corrección, ya en uso:** un `git worktree` por implementador, rama propia
desde `origin/master` actualizado, sin cambiar ramas en el checkout
compartido. La 18.26 lo documenta (`docs/evidence/18.26-grok-reviewer-write/
session-isolation.md`, worktree aislado, sin tocar perfiles del operador), la
18.27 corre en el suyo (`fix/grok-headless-recibo-1827`) y este cierre en el
propio (`docs/18.10-cierre-documental`).

## Lo que corrigió al lead (no a los implementadores)

Dos redacciones seguidas de la fila 18.18 desmentían —mal— a dos
implementadores que sí habían medido: la causa era el carril del label, no el
regex de evento ni `agents_seen`. Lo destapó el cross-review de kimi apuntado
a las conclusiones del lead, no a una entrega. El mismo patrón salvó la 18.6
(flag `autopilot` sin proteger en los rewrites de mitad de turno). Lección
para el resto del programa: **apuntar revisiones frescas a las conclusiones
del lead**, no solo a las entregas; el tope de 1 ronda se mantiene.

## Tests que discriminan, o no son tests

La debilidad común medida en todos los implementadores, otra vez: casos que
afirman el mensaje genérico (cuatro razones podían regresar en verde),
fixtures que usan todas `bash` delante (borrar la rama directa pasaba), y la
DoD de la 18.8 ampliada tras el adversario —la primera cubría solo el
generador y un implementador 100% conforme podía entregar un generador
huérfano que nadie llama con un autopilot que mergea igual. El verde se
audita por poder discriminante (mutación que sobrevive = hueco), no por
conteo de casos.

## Resultado de 18.27 y límites que permanecen

El PR #212 corrigió el auto-wake que borraba el estado y la espera DELEGATED
sin trabajo en vuelo. La revisión encontró además que una pregunta humana
podía heredar el gate y que `[ ]`/`null` contaban como trabajo: ambos casos
quedaron protegidos por regresiones. Las cuatro mutaciones pertinentes fueron
atrapadas. Las capturas de once corridas muestran 9/9 bloqueos sostenidos;
la tabla distingue los seis anteriores al fix de los tres posteriores.

El teardown de la ronda del wake sigue pudiendo omitir su Stop (2/2
recorridos post-fix observados); el presupuesto sigue limitado a dos ciclos.
El recibo no se garantiza en toda salida headless. El merge mantiene sus
protecciones independientes y el límite de sello de 18.26. La evidencia está
en `docs/evidence/18.27-grok-headless/cadena-bloqueo-continuacion.md`; no hubo
medición viva nueva para las correcciones r2.

Guía, README y spec incorporan esta conclusión. El cierre documental conserva
como límites el happy path de merge no observado y `cuidar-pr` sin medición
viva; no los convierte en éxitos. El despliegue de cada merge y su SHA se
registran en `docs/deploy-log.md`. El descartable queda entregado al operador.

## Entrega del descartable al operador (no se borra en este cierre)

La DoD permite borrarlo (topic + marcador verificados) o entregarlo al
operador. Se elige lo segundo: D23 recomienda el borrado a mano y este cierre
es documental. El líder integra los PR y despliega las copias del hook;
la entrega del descartable no ejecuta su borrado.

Estado observado el 2026-09-06 (API REST; GraphQL dio timeout):

```
repo:    gon0801/saikit-descartable (privado, rama main, pushed 2026-09-06T02:49:43Z)
topic:   ["saikit-descartable"]
marcador: SAIKIT-ORIGEN.md existe (582 bytes, blob ef1e4ce51bf98056a70019326271572d15bbbb90)
punta:   48aee6f74eaa647d2c75061ca7b727a183259e14 (Revert "feat: cambia el saludo..." (#7), 02:49:39Z)
PRs:     #7 closed+merged (revert) · #6 closed+merged (vía directa, declarado en esc3)
         #5 closed sin mergear (CI rojo, esc2) · #4 open · #3 open · #2 closed+merged (18.1)
         #1 open
```

La punta coincide con el MERGE-OK de esc3 y `main` quedó verde con los
commits de setup (tools + config): es el repo de medición, se declara. Los
PRs viejos #1, #3 y el #4 de esc1 quedan abiertos.

Para cuando el operador lo borre a mano, verificación previa (D23):

```bash
gh api repos/gon0801/saikit-descartable --jq '{rama: .default_branch, topics: .topics}'
gh api repos/gon0801/saikit-descartable/contents/SAIKIT-ORIGEN.md --jq '{marcador: .name}'
# y solo si topic y marcador verifican:
gh repo delete gon0801/saikit-descartable
```

El `gh repo delete` NO se ejecutó en este cierre: solo lecturas.
