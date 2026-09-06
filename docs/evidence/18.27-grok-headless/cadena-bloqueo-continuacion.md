# 18.27 — cadena correlacionada bloqueo → continuación → resultado (R27-2)

Respuesta al hallazgo R27-2 de la revisión del 2026-09-06: la cadena que la DoD
exige, sesión por sesión, con la decisión literal del hook, la continuación
correlacionada y el resultado/estado. Todo sale de las capturas del laboratorio
(`/private/tmp/saikit-1827-lab-48220/runs/<corrida>/`: `hook-index.tsv`,
`payloads/*-payload.json` + `*-hook.out`, `stdout.txt`, `rc.txt`,
`state-after/`); nada reconstruido de memoria ni inventado.

## Identidad del hook por fase

| Fase | Corridas | hook (sha256, primeros 16) |
|---|---|---|
| pre-fix (master) | m2-r1..r3, m1-r1..r4, m1b-r1 | `f760fbbd33bb24da` (= `git show 99e8486:hooks/summonaikit-harness.sh`) |
| post-fix ronda 1 | m1f-sync, m1f-async, m1bf-r1 | `425581d82dc5a644` (build medida en vivo; la fuente de la rama en esa ronda era `8df77d3`) |
| fuente tras review r2 | — | `8d13c9a0f34b3998` (sin medición viva nueva: los cambios r2 — retiro de la laxa y patrón positivo — no alteran ninguna de las formas que estas corridas ejercitan; su cobertura es la batería del laboratorio) |

Cada corrida vivió en su propia sesión grok (`sessionId` propio, estado por
sesión); el env aislado y el wrapper instrumentado son los del README.

## Las 11 corridas, una línea cada una

«decisiones stop» es la secuencia literal de decisiones del hook para los Stops
de la sesión (block = `{"decision":"block",...}`; budget =
`{"continue":false,...}` del presupuesto; allow = stdout vacío exit 0).
«etiquetas» cuenta las 6 etiquetas del recibo en el stdout final del proceso.

| Corrida | Sesión | Secuencia (abreviada) | Decisiones stop | etiquetas | RC | Estado final |
|---|---|---|---|---|---|---|
| m2-r1 | 01a07568 | UPS → stop(LISTO) → stop → stop → shutdown | block → block → budget → allow | 0 | 0 | limpio (presupuesto) |
| m2-r2 | 01a07569 | UPS → stop(LISTO) → spawn async → stop(bg=1, DELEGATED) → WAKE → shutdown | block → allow → allow | 0 | 0 | limpio (desarme del wake) |
| m2-r3 | 01a0756d | UPS → stop(LISTO) → stop → stop → shutdown | block → block → budget → allow | 0 | 0 | limpio (presupuesto) |
| m1-r1 | 01a0756e | UPS → spawn sync → stop(bg=0, DELEGATED) → shutdown | allow → allow | 0 | 0 | huérfano (cycle=0, agents=implementer) |
| m1-r2 | 01a07570 | ídem m1-r1 | allow → allow | 0 | 0 | huérfano |
| m1-r3 | 01a07571-0b76 | UPS → spawn async → stop(bg=1, DELEGATED) → WAKE → shutdown | allow → allow | 0 | 0 | limpio (desarme del wake) |
| m1-r4 | 01a07577 | ídem m1-r3 (hijo con sleep 20) | allow → allow | 0 | 0 | limpio (desarme del wake) |
| m1b-r1 | 01a07571-85a4 | UPS → spawn async → stop(LISTO) → spawn v/r → stop(recibo) → shutdown | block → allow → allow | 6 | 0 | limpio (cierre limpio) |
| m1f-sync | 01a07587 | UPS → spawn sync → stop(bg=0, DELEGATED) → spawn async verifier → stop(bg=1) → WAKE → shutdown | block → allow → allow | 0 | 0 | sobrevive (cycle=1, agents=implementer,verifier) |
| m1f-async | 01a07589-7f13 | UPS → spawn async → stop(bg=1, DELEGATED) → WAKE → shutdown | allow → allow | 0 | 0 | sobrevive (cycle=0, agents=implementer) |
| m1bf-r1 | 01a0758a | UPS → spawn async → stop(LISTO) → spawn v/r → stop(recibo v1) → stop(recibo final) → shutdown | block → block → allow → allow | 12 (dos recibos: intermedio y final) | 0 | limpio (cierre limpio) |

## Conteos corregidos (los que la revisión marcó contradictorios)

- **Bloqueos emitidos y sostenidos: 9/9.** Pre-fix: 6 (m2-r1: 2, m2-r2: 1,
  m2-r3: 2, m1b-r1: 1). Post-fix: 3 (m1f-sync: 1, m1bf-r1: 2). En los nueve
  casos la continuación está correlacionada: el Stop siguiente llega con
  `stopHookActive=true` y actividad posterior del agente, y el proceso no
  terminó por ignorar el bloqueo sino por las salidas de diseño (presupuesto,
  cierre limpio) o por permiso explícito (escotilla con trabajo en vuelo).
  El «5/5» anterior era un error de conteo del README.
- **Stop de fin de turno de la ronda del wake no emitido (teardown): 5
  observaciones** — pre-fix: m2-r2, m1-r3, m1-r4; post-fix: m1f-sync,
  m1f-async (2/2 de las corridas post-fix que llegaron al wake con el turno
  principal ya terminado). En las cinco, el WAKE aparece como UPS y el
  siguiente Stop es `shutdown`; la ronda despertada produce salida en el
  stdout del padre pero su Stop end_turn no se emite. El «3/3 con el fix»
  anterior mezclaba corridas pre-fix (m1-r3/r4) con post-fix.
- **Salidas sin recibo:** pre-fix 7/8 (cerró m1b-r1 con 6/6), post-fix 2/3
  (cerró m1bf-r1 con recibo final completo).

## Cuatro cadenas, extractos literales

### m2-r1 — bloqueo sostenido ×2, salida por presupuesto (pre-fix)

```text
20260905T232940  stop end_turn active=False bg=0 lastMsg='LISTO'
  hook stdout: {"decision":"block","reason":"SUMMONAIKIT HARNESS GATE\n\nFailed gates:\n- Missing SUMMONAIKIT HARNESS RECEIPT.\n- Missing Understand gate summary (each receipt label opens its own paragraph: ...
20260905T233018  stop end_turn active=True bg=0 lastMsg='LISTO'      <- continuación: otra ronda del MISMO turno
  hook stdout: {"decision":"block","reason":"SUMMONAIKIT HARNESS GATE\n\nFailed gates:\n...
20260905T233023  stop end_turn active=True bg=0 lastMsg='LISTO'
  hook stdout: {"continue":false,"stopReason":"SUMMONAIKIT HARNESS REVISION BUDGET EXHAUSTED\n\n...
20260905T233023  stop shutdown  -> allow (stdout vacío, exit 0)
resultado: RC=0, 0/6 etiquetas, estado limpiado por el presupuesto (salida declarada del diseño)
```

### m1b-r1 — bloqueo sostenido → ceremonia → recibo 6/6 y cierre limpio (pre-fix)

```text
20260905T233954  stop end_turn active=False bg=0 lastMsg='LISTO'
  hook stdout: {"decision":"block","reason":"...Missing SUMMONAIKIT HARNESS RECEIPT...
  continuación correlacionada: spawn_subagent verifier + reviewer, ceremonia completa
20260905T234414  stop end_turn active=True bg=0 lastMsg='LISTO\n\nSUMMONAIKIT HARNESS RECEIPT\n\nUnderstand: Pediste que un i...'
  hook stdout: (vacío, exit 0)  <- cierre limpio: recibo completo, estado borrado
20260905T234415  stop shutdown  -> allow
resultado: RC=0, 6/6 etiquetas, estado limpio por el cierre (el «esc1» del smoke)
```

### m1-r3 — la cadena del hallazgo E exacta (pre-fix)

```text
UPS padre arma (-saikit)
SPAWN(bg=True) + SubagentStart(implementer)
stop end_turn active=False bg=1 lastMsg='SUMMONAIKIT HARNESS DELEGATED - awaiting implementer.'
  hook: escotilla DELEGATED permite (bg=1: espera genuina) — stdout vacío, exit 0
WAKE: UPS de la sesión padre con prompt = <system-reminder>\nBackground subagent "..." (implementer: "Create deleg.txt file") completed successfully....
  hook pre-fix: sin sentinel y no reconocido como notificación => desarme A4-c2, estado BORRADO
  (el padre reporta el resultado del hijo en el stdout, pero su Stop end_turn no se emite: teardown)
stop shutdown -> allow
resultado: RC=0, 0/6 etiquetas, estado limpiado POR EL DESARME — la observación «estado limpio» del smoke 18.9 esc2
```

### m1f-sync — la misma forma, con el fix de la ronda 1 (post-fix)

```text
UPS padre arma
SPAWN(bg=False) + SubagentStart(implementer) — el hijo sync YA reportó
20260906T000353  stop end_turn active=False bg=0 lastMsg='SUMMONAIKIT HARNESS DELEGATED - awaiting implementer.'
  hook stdout: {"decision":"block","reason":"...Missing SUMMONAIKIT HARNESS RECEIPT...   <- guardia D-B: sin nada en vuelo no hay escotilla
  continuación correlacionada: el agente spawnea un verifier async y sigue la ceremonia
20260906T000514  stop end_turn active=True bg=1 lastMsg='El archivo ya está creado. El verifier está en curso...'
  hook: escotilla permite (bg=1 genuino) — stdout vacío
20260906T000515  WAKE del verifier: el estado ya NO se borra (fix D-A)
  stop shutdown -> allow
resultado: RC=0, etiquetas del recibo 0 en el stdout final (la ronda del wake se corta en el teardown — residual declarado),
           estado en disco SOBREVIVE: cycle=1, agents_seen=implementer,verifier (evidencia auditable)
```

## Qué NO afirma esta evidencia

- No afirma que el host ignore bloqueos: los nueve bloqueos tuvieron
  continuación correlacionada; las salidas sin recibo se explican por
  presupuesto (2), escotilla genuina (5 corridas con allow bg≥0 sin recibo:
  m1-r1/r2/r3/r4, m1f-async), desarme pre-fix (3) y teardown del wake (5
  observaciones, ver conteos arriba; m2-r2 y m1f-sync acumulan ambas).
- La fase post-fix se midió con la build `425581d8` (ronda 1). Los cambios de
  la ronda 2 (retiro de la vía laxa R27-1, patrón positivo R27-3) no tienen
  medición viva nueva: no alteran ninguna forma ejercitada por estas corridas
  (todos los wakes medidos matchean la forma estricta; ningún `[ ]`/null fue
  observado en vivo) y su cobertura vive en la batería del laboratorio
  (`test_gate_behavior` + mutaciones, ver README).
