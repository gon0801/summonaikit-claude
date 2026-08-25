# Smoke vivo del rol adversary por host — 2026-08-25

Post-merge de la Phase 13 (PR #67) y deploy a los vivos, se corrió UN turno
real armado por host pidiendo el rol (`… -saikit: agrega un docstring … y
ataca el cambio con adversary`) sobre repos descartables. Registro de lo
OBSERVADO — cada afirmación con su evidencia; lo no observado queda `unknown`
(Core Rule 2). Complementa la sección del rol en
`docs/spec/00-project-spec.md` (los "casos por target" del gate son de
laboratorio; esto es lo vivo).

## grok — el mecanismo del rol completo, EN VIVO

Turno headless `grok --cwd <repo> --always-approve --single "Tarea -saikit: …"`.
Evidencia: stdout del turno + transcript
(`~/.grok/sessions/…smoke-adv-grok/01a03a8e-…/chat_history.jsonl`, 66 eventos)
+ el árbol del repo descartable.

- **El adversary CORRIÓ como subagente real** y escribió
  `.saikit/findings/adversary-20260825T000000Z.json` con la forma canónica del
  contrato — incluido el camino honesto de CERO hallazgos: `findings: []` con
  la lista `attacked` de 5 superficies (bordes de entrada, blast radius por
  grep, tests que no discriminan, forma del docstring, trust boundary).
- **Capa 3 en vivo**: `.saikit/findings/.gitignore` con `*` apareció solo, en
  un repo virgen, con el primer evento del rol.
- **El gate armó y BLOQUEÓ una vez** exigiendo la ceremonia (mensaje
  `cycle 1/2` en el transcript) y las escotillas `DELEGATED - awaiting …`
  perdonaron 2 Stops mid-delegación.
- **El candado no dio falsos positivos** sobre el Bash real del subagente
  (greps, `python -c`, timestamps) — el fix `/dev/null*` del PR #67 ejercitado
  en vivo.
- **Implementer real**: docstring aplicado con checkpoint medido
  (`python -c "…assert saluda.__doc__…"` → `ok`, exit 0).

**Límite del HOST descubierto (no del hook):** `grok --single` NO reanuda el
loop del modelo cuando un subagente termina — la notificación llega como
evento sintético de usuario SIN sentinel, el gate se desarma POR DISEÑO (A5:
prompt sin `-saikit` = stand down; el estado quedó con la firma exacta del
desarme A4-c2: archivos borrados, dir vacío en
`~/.grok/hooks/state/grok/1747054581/01a03a8e-…/`) y la sesión termina sin
recibo final. **La ceremonia completa con recibo en grok requiere sesión
interactiva/multi-turn, no `--single`.** El transcript no contiene
`ADVERSARY:` fuera del contrato inyectado, consistente con ese corte.

## zcode — el hook armó en vivo; el turno murió en el host

Turno headless `zcode --cwd <repo> --prompt="Tarea -saikit: …"`.

- **El hook ARMÓ sobre un payload real de zcode**: quedó
  `harness-state.env` con `lane=full`, `task_hash`, y los 4 campos del candado
  inicializados (`adv_epoch=2026-08-25T20:13:52Z`, resto vacío) — el
  `write_state` de 10 campos y la inicialización del armado funcionando con
  el host real (`~/.claude/hooks/state/zcode/99497468/sess_082716eb-…/`).
- **El turno murió host-side ANTES de despachar nada**:
  `Error: Turn execution failed` → con `--verbose`:
  `AiSdkModelAdapterError: Model provider is missing an API key: zai`. El
  modo headless de zcode no toma el login OAuth compartido (y
  `zcode login` por browser está capado en Windows: "requires macOS for the
  registered zcode:// callback"). Mismo síntoma que la 12.1 vio con
  `--prompt "/model"` — es del host, no del contrato del kit (falla igual sin
  `-saikit`).
- **Pendiente declarado**: ceremonia viva en zcode requiere o la API key de
  Z.AI en `/login` del TUI, o un turno interactivo del operador. Saltado por
  decisión del operador (2026-08-25).

## Gotcha de invocación (para el que repita esto)

Un prompt que EMPIEZA con `-saikit` es tratado como flag por los parsers de
ambos CLIs (clap de grok: "a value is required for '--single <PROMPT>'";
zcode: imprime el help). Forma que funciona: `--single="Tarea -saikit: …"` /
`--prompt="Tarea -saikit: …"` — sentinel a mitad del prompt (arma igual: la
frontera del regex está fijada por golden) y valor con `=`.

## Cobertura viva acumulada del rol, por host

| Host | Vivo probado | Queda |
|---|---|---|
| claude | Turno completo (estreno del cierre 13.9: HIGH real hallado + candado mordiendo en vivo) | — |
| grok | Mecanismo completo del rol (artefacto, capa 3, gate, escotillas, candado) | recibo final (límite de `--single`; va por sesión interactiva) |
| zcode | Armado + init del candado sobre payload real | ceremonia (bloqueada en auth del host, saltada por el operador) |
| kimi | nada — canales de payload sin medir | medición de payloads (siguiente tarea) |
| codex | no aplica (sin costura de perfiles) | decisión futura de costura |
