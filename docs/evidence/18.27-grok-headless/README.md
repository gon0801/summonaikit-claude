# 18.27 — Grok headless puede terminar sin recibo tras delegar (hallazgo E, smoke 18.9)

Medido 2026-09-05/06, macOS (darwin 25.6.0 arm64), grok **1.0.13 (5e9a58528b76)**
headless (`-p` vía `--prompt-file`, `--always-approve`), hook de master `99e8486`
antes del fix y hook del worktree tras el fix. 11 corridas vivas: 8 contra el hook
de master (m2-r1..r3, m1-r1..r4, m1b-r1) y 3 contra el hook corregido
(m1f-sync, m1f-async, m1bf-r1).

## Aislamiento

- Worktree propio `/private/tmp/saikit-fix1827-1788675753-42359`, rama
  `fix/grok-headless-recibo-1827` desde `origin/master` (`99e8486`). El checkout
  compartido no se tocó (sigue en `master`) ni el worktree de 18.26.
- Laboratorio `/private/tmp/saikit-1827-lab-48220`: **HOME aislado** con copia
  del perfil grok (auth incluida; el perfil vivo `~/.grok` solo se leyó, jamás
  se escribió — la registration global vive EN LA COPIA), `USERPROFILE` y
  `TMPDIR` aislados, repo descartable `repo/` (git init propio).
- El hook se registró como global **de la copia** (`<MH>/.grok/hooks/`), la
  misma forma canónica del instalador (los 5 eventos, env
  `SUMMONAIKIT_HOOK_TARGET=grok`, Stop timeout 600), apuntando a un wrapper
  que guarda payload→stdout/stderr→rc de CADA evento y re-emite byte-identico.
  El perfil vivo tiene su propio hook registrado: no corrió ninguna de estas
  sesiones (todo quedó bajo el HOME aislado).
- Estado del hook observado en `<MH>/.grok/hooks/state/grok/<hash>/<session>/`
  y capturas en `<MH>/.grok/hooks/capturas/` (index.tsv + payloads + salidas).

## Las preguntas de la fila, separadas

**¿Grok invocó el hook Stop?** Sí, en las 11 corridas. Cada turno dispara el
par medido en 7.1/7.3: `reason=end_turn` (con `promptId` y
`lastAssistantMessage`) y `reason=shutdown` (sin ninguno de los dos). Además,
cada bloqueo genera un Stop de continuación con `stopHookActive=true` — la
señal de que el host CORRIÓ otra ronda del mismo turno.

**¿Qué payload y sesión llegaron?** Payload camel de Grok con `sessionId` del
padre, `backgroundTasks` (vacío u ocupado según hubiera trabajo en vuelo) y
`lastAssistantMessage`. Los eventos internos del hijo llegan con su PROPIA
sesión y `subagentType` de primer nivel (consistente con 18.26). El auto-wake
de subagente completado llega como `UserPromptSubmit` de la sesión PADRE cuyo
`prompt` es un sobre del sistema (ver `autowake-padre.payload.json`).

**¿El hook permitió o bloqueó?** Ambos, según el caso, y siempre con la
semántica diseñada: `{"decision":"block","reason":...}` + exit 0 (7.4) cuando
faltaba recibo; allow mudo cuando la escotilla aplicaba; y
`{"continue":false,"stopReason":...}` al agotarse el presupuesto (2 ciclos).

**¿Qué hizo Grok después de recibir ese resultado?** Tras cada `decision:block`
el modelo corriÓ otra ronda del mismo turno y respondió al reason — 5/5
bloqueos sostenidos (m2-r1: 2, m2-r2: 1, m2-r3: 2, m1b-r1: 1; en m1b-r1 el
agente corrío ceremonia completa y escribió el recibo 6/6). Tras cada allow el
turno terminó y el proceso salió RC=0. **El host NO ignora bloqueos en
headless**: el reclamo del smoke («no hay nadie a quien re-preguntar y el
proceso sale igual») queda refutado para el camino del bloqueo — el modelo es
el re-interrogado y contesta.

**¿La salida final tuvo las seis etiquetas?** Solo cuando el agente pasó por
el bloqueo y colaboró: m1b-r1 y m1bf-r1 cerraron con recibo completo (el
«esc1» del smoke). Las otras 9 corridas terminaron 0/6 — por escotilla (4),
presupuesto agotado (2) o desarme del wake borrando el estado (3).

**¿Qué estado quedó en disco y con qué exit code?** RC=0 en TODAS (proceso
headless sano). El estado difirió por mecanismo de salida: limpio por
presupuesto (m2-r1/r3), limpio por cierre limpio (m1b-r1, m1bf-r1), HUERFANO
armado tras escotilla sync (m1-r1/r2: `cycle=0, agents_seen=implementer`),
y BORRADO por el auto-wake (m2-r2, m1-r3, m1-r4 — la observación «estado
limpiado» del smoke).

## La cadena del esc2, reproducida y explicada (m1-r3)

1. UPS padre arma (`-saikit`).
2. `spawn_subagent` async (`background:true`) + `SubagentStart implementer`.
3. El padre corta con la línea DELEGATED: Stop `end_turn` con
   `backgroundTasks` ocupado (1 en vuelo) → la escotilla permite — CORRECTO,
   la espera es genuina y el proceso queda vivo esperando al hijo.
4. El hijo completa → **auto-wake**: `UserPromptSubmit` del padre cuyo prompt
   es `<system-reminder>\nBackground subagent "<id>" (implementer: "<desc>")
   completed successfully....</system-reminder>` (sin sentinel).
5. El detector de notificaciones solo conocía la forma claude
   (`<task-notification>`): el wake caía en el desarme A4-c2 y **borraba el
   estado de la ceremonia a mitad de turno**.
6. La ronda del wake produce salida (el padre reporta el resultado del hijo)
   pero su Stop de fin de turno se corta en el teardown del proceso `-p`
   (documentado por grok: teardown espera medio segundo y dropea lo
   encolado) → shutdown Stop sin estado → RC=0, 0/6 etiquetas, estado limpio.
   Exactamente el hallazgo E del smoke, ahora con el mecanismo completo.

Segundo agujero medido (m1-r1/m1-r2): delegación **síncrona** — el hijo ya
reportó, el padre igual escribe la línea DELEGATED y el Stop llega con
`backgroundTasks` VACÍO; la escotilla de solo-texto permitía igual y el
proceso salía sin recibo ni wake que lo reabra (estado huérfano en disco).

## Decisión

Mecanismo que sostiene el cierre (fix mínimo, grok-only) + límites declarados.
No se debilita ningún gate: el de merge no depende del recibo y no se toca.

**D-A — el auto-wake de grok no arma ni desarma.** `start_harness` aprende la
forma grok con la misma disciplina de dos marcas de 10.14/PR#30: skip estricto
(primera línea = `<system-reminder>` Y contenido `Background subagent` en el
texto) ANTES del gate del sentinel — un evento del sistema no arma ni desarma
(la descripción del subagente la escribe el agente padre y puede llevar
`-saikit`); y veto laxo al desarme (etiqueta + contenido). Acotado a
`TARGET=grok`.

**D-B — la escotilla DELEGATED en grok exige trabajo en vuelo.** El Stop con
la línea DELEGATED y `backgroundTasks` vacío ya no permite: cae al gate normal
y BLOQUEA — bloqueo que el host sostiene (m1f-sync lo muestra vivo: bloqueo →
el agente continuó la ceremonia). Con `backgroundTasks` ocupado la escotilla
sigue permitiendo (m1f-async): la espera genuina no se rompe. Solo grok: es el
único host con ese canal medido; los demás quedan byte-idénticos.

## Re-verificación viva con el fix (3 corridas)

- **m1f-sync** (delegación sync + línea DELEGATED): el Stop `bg=0` ahora
  **bloquea**; el host lo sostiene; el agente continúa (spawnea un verifier
  async) y su siguiente Stop `bg=1` sale por la escotilla (espera genuina);
  el auto-wake siguiente **ya no borra el estado** (queda `cycle=1,
  agents_seen=implementer,verifier`).
- **m1f-async** (delegación async + línea DELEGATED): escotilla permite con
  `bg=1` (correcto) y el wake conserva el estado (`cycle=0,
  agents_seen=implementer` — antes lo borraba).
- **m1bf-r1** (sin palabras de escotilla): bloqueo sostenido → ceremonia →
  **recibo 6/6** → cierre limpio (estado borrado por el cierre, RC=0). El
  camino verde del smoke esc1 no cambió.

## Límites declarados (residuales)

1. **Teardown del `-p` sobre la ronda del wake**: con trabajo genuinamente en
   vuelo, la escotilla permite (correcto en sesión viva), pero el proceso
   headless puede dropear el Stop de fin de turno de la ronda que despierta el
   subagente (medido 3/3 con el fix: m1f-sync/m1f-async/m1-r3-r4 — la salida
   del padre existe, su Stop no se emite). Ese recorrido puede salir sin
   recibo; lo cubre el presupuesto cuando la ronda llega a correr, y queda el
   estado sobreviviente como evidencia cuando no. No se detecta `-p` desde el
   payload (nada medido lo distingue de una sesión interactiva).
2. **Presupuesto agotado** (2 ciclos, MAX_CYCLES): sigue siendo la salida
   declarada del diseño para un agente que se niega a escribir el recibo
   (m2-r1/m2-r3: bloqueo, bloqueo, force-stop, RC=0, 0/6).
3. Formas de auto-wake no medidas (subagente FALLIDO, tareas shell, crons):
   el detector cubre la forma medida; una forma distinta que no matchee vuelve
   a desarmar. La laxa de dos marcas deja citar el sobre entero como residual
   (mismo trade-off que PR#30).
4. `backgroundTasks` ausente del payload (nunca medido): se lee como «sin
   evidencia de trabajo en vuelo» y la escotilla no aplica (fail-closed al
   gate normal). Un ECO de la clave con array poblado citado en otro campo
   de texto del propio payload (p.ej. en `lastAssistantMessage`) contaría
   como en vuelo — misma clase de trade-off textual ya declarada de la
   escotilla (review r1, hallazgo bajo; el array vacío real sí está en el
   payload y el grep lo ve). El array vacío se detecta tolerando espacios
   EN LA MISMA LÍNEA; un pretty-print que ponga el array en la línea
   siguiente seguiría sin matchear (grep es por línea) y reabriría el
   hueco — forma no medida, declarada.

## Regresiones y mutaciones

Casos nuevos (`tests/lib/gate_cases.sh`, builders en `tests/lib/hook_lab.sh`):

- `caso_g1_grok_autowake_no_desarma`, `caso_g1_grok_autowake_con_sentinel_no_rearma`
  (D-A; el segundo con `-saikit` dentro de la descripción del subagente),
  `caso_g1_grok_mencion_humana_del_wake_si_desarma` (contracara PR#30),
  `caso_g4_grok_delegado_sin_bg_bloquea` y `caso_g4_grok_delegado_con_bg_permite`
  (D-B y su contracara).

Rojo medido ANTES del verde, contra el hook prístino de `origin/master`
(`SAIKIT_HOOK_VIVO` a la copia prístina, HOME/TMPDIR aislados):

```text
      FAIL: el auto-wake de subagente grok NO debe desarmar el turno armado — 18.27
      FAIL: cycle conservado tras el auto-wake: esperaba [0], dio []
    ROJO: caso_g1_grok_autowake_no_desarma
      FAIL: cycle conservado (un re-armado lo resetearia a 0): esperaba [1], dio [0]
    ROJO: caso_g1_grok_autowake_con_sentinel_no_rearma
    ok: caso_g1_grok_mencion_humana_del_wake_si_desarma
...
      FAIL: Stop grok delegado SIN trabajo en vuelo bloquea (18.27): no contiene ["decision":"block"]
    ROJO: caso_g4_grok_delegado_sin_bg_bloquea
    ok: caso_g4_grok_delegado_con_bg_permite
```

Verde con el fix (`bash tests/test_gate_behavior.sh`, env aislado): el resto
de la batería sin cambios y los cinco casos nuevos en ok
(`test_gate_behavior: OK`).

Mutaciones (`SAIKIT_MUTACIONES=... bash tests/test_gate_mutations.sh`, una por
protección, 3/3 atrapadas):

```text
  G1  el skip estricto del auto-wake grok se neutraliza [...] (18.27)
      lo atrapa: caso_g1_grok_autowake_con_sentinel_no_rearma
  G1  la laxa grok vuelve a vetar el desarme con la etiqueta sola [...] (18.27)
      lo atrapa: caso_g1_grok_mencion_humana_del_wake_si_desarma
  G4  la guardia de backgroundTasks de la escotilla grok se neutraliza [...] (18.27)
      lo atrapa: caso_g4_grok_delegado_sin_bg_bloquea
test_gate_mutations: OK
```

## Archivos

- `autowake-padre.payload.json` — el UPS del wake que borraba el estado (m1-r3).
- `stop-delegado-bg-vacio.payload.json` — Stop sync con línea DELEGATED y nada
  en vuelo (el agujero de la escotilla, m1-r1).
- `stop-delegado-bg-ocupado.payload.json` — Stop async con 1 subagent en vuelo
  (la espera genuina que la escotilla debe seguir permitiendo, m2-r2).

## Nota para el documento compartido (GLM)

Texto propuesto para integrar donde corresponda (no lo edito yo): «18.27
midió el hallazgo E en vivo (11 corridas headless, grok 1.0.13, evidencia en
`docs/evidence/18.27-grok-headless/`): el host SOSTIENE los bloqueos del Stop
en headless (5/5; `stopHookActive=true` y rondas de continuación); las salidas
sin recibo venían de la escotilla DELEGATED sin trabajo en vuelo y del
auto-wake de subagente borrando el estado armado (detector solo-claude). Fix
grok-only: el wake ya no arma ni desarma, y la escotilla exige
`backgroundTasks` no vacío. Residual declarado: el teardown de `-p` puede
cortar la ronda del wake (recibo pendiente, estado sobreviviente como
evidencia) y el presupuesto agotado sigue siendo la salida de diseño. La
ceremonia de cierre en headless ya no es best-effort silencioso: cada salida
sin recibo es o un bloqueo sostenido agotado (declarado) o una espera genuina
documentada.»
