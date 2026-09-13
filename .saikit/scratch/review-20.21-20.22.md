# Review 20.21 (PR #312) / 20.22 (PR #313) — reviewer kimi/k3, 2026-09-13

Segunda mirada independiente. Verificacion propia contra los artefactos
primarios (runs/*.json, tools, hook, Plans.md); NO se re-midio nada, NO se
corrio gh (no instalado en el nodo: evidencia queda local en scratch, sin PR
comment posible).

## Verificado OK (contra primarios)

- Cifras de 20.21 vs runs/*.json — EXACTAS: 20.9 deny 0.2945535 USD/14205/13828 ms;
  allow 0.265361/8276/7787. 20.10 t1 5.0997373/754686/721012/61 turnos;
  t2 7.2971747/1132390/1037167/46. 20.11 revisar 4.7979260/1088559/1052604/24;
  solo-hilos 4.3940663/668078/636995/25; cuidar 4.1981789/618109/596661/22.
  Totales 20.10 (12.40 USD / 31.5 / 29.3 min) cuadran.
- Checkout SHAs citados (8e7402e…, d89a4ad…, 60d1ee9…) coinciden con los README
  de 20.9/20.10/20.11; hook 37e55640…/4345 lineas verificado EN VIVO en master
  (shasum -a 256 + wc -l). Drift 2.1.267 vs pin 2.1.266 declarada en 20.9.
- 16.7 en Plans.md L49: cc:NO EJECUTADA con la correccion del cross-review
  2026-08-30 exactamente como la narra 20.21.
- 20.22 vs tools/saikit-setup-autopilot.sh: cinco preguntas/claves, defaults
  rama=master + revert_si_rojo=true inerte (comentario L16-17), lock mkdir +
  exit 3 + --liberar-lock (L28-29,132,158-159). saikit-merge.sh lee la config
  SOLO de origin/<rama> (L271-275) y un PR que toca autopilot.json JAMAS se
  auto-mergea (L417-418). .saikit/autopilot.json ABSENTE en vivo (test -f).
- Juicio de 20.21: la lectura intra-fila es honesta; la dispersion se explica
  por tamano del caso; el criterio de reactivacion (medicion pareada
  mismo-caso/dos-tiers) es accionable y medible. Decision bien fundada.
- Estilo: misma estructura identidad/drift/unknowns/veredicto que 20.9-20.11.

## Hallazgos 20.21 (REQUEST_CHANGES)

M1. docs/evidence/phase-20/20.21/README.md L32 (seccion Comparacion) + L113
    (unknowns) — MAYOR: la DoD de la fila (Plans.md L224) exige "Tokens/tiempo
    por etapa y rol" como primer elemento. La evidencia no reporta TOKENS en
    ninguna parte (grep "token" = 0 coincidencias), no desglosa nada por
    etapa/rol, y TAMPOCO declara ese elemento como unknown con su razon,
    violando su propia regla ("lo no observado queda unknown"). Los runs/*.json
    traen usage/token counts (observables en agregado); el desglose por rol si
    seria unknown declarable (cada JSON agrega la corrida entera). Que hacer:
    reportar tokens por corrida desde los campos usage y/o declarar
    "tokens/tiempo por etapa y rol: unknown (la evidencia reutilizada agrega
    por corrida, no por rol)".

M2. docs/evidence/phase-20/20.21/README.md L59 y L116 — MAYOR: la cifra
    "test 6 s + 3 s (medido contra la API)" NO existe en la evidencia mergeada
    citada: docs/evidence/phase-20/20.11/README.md L49 menciona los runs
    34446794447/34446791997 pero NO contiene ninguna duracion. El documento
    declara arriba "Toda cifra cita evidencia ya mergeada" y el encabezado de
    la tabla dice que los campos se leen de los runs/*.json — esta cifra fue
    consultada fresca a la API durante ESTA tarea y no quedo preservada en
    ningun artefacto. Que hacer: preservar la salida de la API como artefacto
    (p.ej. runs/ci-duration-20.11.txt en esta evidencia) o declararla como
    medicion fresca fuera de la regla de reutilizacion, con su comando.

M3. docs/evidence/phase-20/20.21/README.md L59 (fila cuidar: pared 10.3 min) —
    MAYOR: contradiccion NO declarada con la evidencia fuente. El README
    mergeado de 20.11 (seccion Costos, L57-63) tabula "revisar ~7 min,
    solo-hilos ~7 min, cuidar ~8 min", mientras los JSON primarios (y 20.21)
    dicen 18.1/11.1/10.3 min de pared. Las cifras de 20.21 son las correctas
    contra el primario, pero un lector que cruce con 20.11 encuentra otra cifra
    y 20.21 no lo declara. Que hacer: una linea declarando la discrepancia
    (y su origen probable: la tabla de 20.11 no traza a duration_ms).

m1. docs/evidence/phase-20/20.21/README.md L102 — MENOR: "varia ±14 %" — el
    spread real es 14.3 % max-a-min (4.1982→4.7979), o sea ±6.7 % alrededor de
    la media. Redondeo asimetrico; no cambia la conclusion.

m2. docs/evidence/phase-20/20.21/README.md L18-19 — MENOR: parafrasea la regla
    del runbook. El texto literal (docs/phase20-mediciones-runbook.md L51-52)
    dice "solo se reutiliza en otra si COINCIDE checkout y hook SHA"; el
    checkout de las evidencias reutilizadas (8e7402e/d89a4ad/60d1ee9) NO
    coincide con el de esta evidencia (76e92bb) — coincide solo el hook. 20.21
    reescribe la regla como "exige declarar el SHA original". La reutilizacion
    es defendible (hook identico, drift docs-only declarada, las cifras son
    propiedad de las corridas), pero la defensa debio hacerse citando la regla
    literal y justificando la excepcion, no suavizandola.

## Hallazgos 20.22 — ninguno (APPROVE)

Las cinco decisiones coinciden pregunta-por-pregunta con el tool; efecto de
merge explicito y correcto (merge=false = no-op; publicar merge=true exige
autorizacion); rollback reversible verificable contra origin; lock y
--liberar-lock descritos con fidelidad; .saikit/autopilot.json ausente;
distincion lab/kit correcta; unknowns honestos (las propuestas NO se
presentan como definitivas).
