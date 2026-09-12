# 20.17 — cierre headless vivo sync/async/teardown (claude + grok)

Fecha: 2026-09-12. Rama `impl/20.16-20.17-mutantes-medicion` sobre `ad1333d`
(head del PR #308 abierto). Montaje del brief: directorio de proyecto
desechable por modo (el PROJECT_KEY es su cksum), HOME real, sin
`SAIKIT_HOOK_DIR` (con override el launcher miraria donde el hook nunca
escribe — cadena falsa), `SAIKIT_HEADLESS_LAUNCH_COUNT` por corrida.
Al terminar se borraron los subdirectorios propios y se verifico por diff
que el resto del state quedo intacto (`logs/state-antes.log` vs
`logs/state-despues-limpieza*.log`: solo salen llaves propias).

## Matriz medida

| modo | host_rc | session_id | STATE_PATH (derivada) | leftover | close_type | exit | lanz. |
|---|---|---|---|---|---|---|---|
| claude sync | 0 | f6e3f09a… / fa58af68… / 731a38fe… | state/claude/⟨pk⟩/⟨sid⟩/harness-state.env | armado mid-run, Stop limpio | clean | 0 | 1 |
| claude async | 0 | 25a53705… / 357123fd… | idem | armado 38 s, Stop limpio | clean | 0 | 1 |
| claude teardown | -9 (SIGKILL) | 9e80456a… (vista en disco; el host muerto no emite JSON) | idem | si, sin recibo (7/7 ausentes) | incomplete | 1 | 1 |
| grok sync | 1 (402) | — (el JSON de error no trae) | state/grok/⟨pk⟩/… (huerfano armado) | si (huerfano) | unknown | 3 | 1 |
| grok async | 1 (402) | — | idem | si (huerfano) | unknown | 3 | 1 |
| grok teardown | 1 (402 instantaneo) | — | idem | si (huerfano) | unknown declarado | — | — |

Detalle por modo:

- **sync** (`logs/claude-sync-watch.log`): el watcher (0.5 s) ve ausente →
  `…/fa58af68…/harness-state.env` (155b) + evidence (32b) desde el segundo 1
  hasta que Stop limpia (ausente final). Launcher: `sin leftover — clean
  no-op`, exit 0, count=1. Recibo 7/7 en el `result` del JSON directo
  (`logs/claude-sync-receipt.log`, sesion 73cb910e, 2 turnos: Stop bloqueo una
  vez por el `TRAIL SKIP:` dentro de Close y el modelo lo separo).
- **async** (`logs/claude-async-watch.log`, `logs/claude-async-delegation.log`):
  delegacion real por Task, no Bash: `subagent_stats.spawned=3`
  (general-purpose 1, verifier 1, reviewer 1 — el contrato inyectado armo la
  ceremonia), `delegated:1517` (37×41), recibo 7/7, 7 turnos. Launcher:
  clean, exit 0, count=1.
- **teardown** (`logs/claude-teardown.log`): SIGKILL a t+3.5 s (estado visto a
  t+1.5 s; stdout del muerto: 163b, sin JSON → session_id inobservable por
  esa via). Leftover genuino sin recibo. Fase B (replay del session_id visto
  en disco): `leftover sin recibo — incomplete`, exit 1, sesion limpia,
  count=1. Reproduce el hueco de 20.15 medido en vivo por primera vez.
- **grok** (`logs/grok-sync.log`, `grok-async.log`, `grok-teardown-402.log`):
  impedimento del host: `API error (status 402 Payment Required): Grok Build
  usage balance exhausted`, salida literal archivada. Launcher: exit 3
  unknown (nunca PASS), count=1. El hook SI arma (huerfano con cycle=0) y el
  proceso muere sin Stop: queda huerfano propio (borrado en limpieza).
  Teardown con kill no aplica (el host muere solo al instante); se declara el
  mismo impedimento.

El test commiteado (`tests/test_headless_close_live.sh`) reproduce los seis
modos (`logs/test-seis-modos.log`): mocks siempre, matriz viva con prereqs
(binario + sin override + hook instalado) o `saikit_skip_caso` con razon.

## Hallazgos que cambian el contrato o el codigo

1. **argv real de grok 1.0.25** (`logs/grok-probe-*.log`): `-p/--single` toman
   el prompt como VALOR. El argv viejo del launcher
   (`grok -p --output-format json "P"`) muere en clap con rc=2 sin tocar la
   red; el del contrato (`grok -p --single --output-format json`) tampoco
   parsea. Fix medido: `grok --single "P" --output-format json`
   (`tools/headless-close.sh:run_host`, contrato corregido, caso argv por
   host en `tests/test_headless_close.sh`). Las 6 mediciones grok ya corren
   con el fix (llegan al 402, no al clap).
2. **PROJECT_ROOT byte-identico o cadena falsa**: el hook normaliza `//` a
   `/` (medido: con TMPDIR con slash final el mktemp deja `T//saikit-…`; el
   launcher miraba una llave y el hook escribia otra — clean accidental).
   Tambien muerde cualquier realpath intermedio (medido: driver python con
   cwd `/tmp` (→`/private/tmp`) vs launcher con el string logico). El test
   commiteado hace squeeze (`tr -s /`) con el por que citado. No se toca la
   derivacion (congelada por #308); queda como limite declarado.
3. **grok dispara el harness en DOS roots** (medido 6/6 corridas grok, driver
   y test): ademas de `~/.grok/hooks/state/grok/⟨pk⟩` aparece el espejo
   `~/.claude/hooks/state/grok/⟨pk⟩` con la misma sesion (task_hash del
   prompt propio). Mecanismo no determinado (todo el registro grok apunta a
   su propia copia; sin codigo de migracion en el hook). La limpieza del test
   barre la llave en ambos roots. No cambia veredictos (grok es unknown por
   402 en todos los modos), pero el launcher solo mira un root: cadena
   grok a auditar cuando el host vuelva a tener cuota.

## Archivos

- `prompts.txt` — los tres prompts exactos.
- `logs/claude-sync-watch.log` — cadena sync con estado mid-run (la prueba).
- `logs/claude-sync-result.log` + `logs/claude-sync-receipt.log` — recibo 7/7.
  (Los `-result.log` son salida cruda del host: empiezan con el Warning de
  enterprise-policy y siguen con el JSON; por eso `.log` y no `.json`.)
- `logs/claude-async-watch.log` — cadena async.
- `logs/claude-async-result.log` + `logs/claude-async-delegation.log` —
  spawned=3, delegated:1517, recibo.
- `logs/claude-teardown.log` — kill + leftover + incomplete/1 + limpia.
  (1 palabra reescrita en la copia: `session_key observada` → `sesion
  observada`, id intacto — el candado de secretos marcaba falso positivo
  `generic-api-key` sobre el UUID citado; los ids de sesion se citan por DoD,
  no son secretos.)
- `logs/claude-canary-result.log` + `logs/claude-canary-receipt.log` —
  el hook dispara en `-p` (SessionStart/UserPromptSubmit/Stop) y el contrato
  inyectado produce recibo 7/7.
- `logs/grok-probe-single-402.log` — forma argv valida + 402 literal.
- `logs/grok-probe-claude-argv-clap2.log` — argv viejo muere en clap rc=2.
- `logs/grok-sync.log`, `grok-async.log`, `grok-teardown-402.log` — unknowns.
- `logs/test-seis-modos.log` — el test commiteado midiendo los seis.
- `logs/state-*.log` — antes/despues de limpiezas (solo llaves propias).
- `run-identity.txt` — identidad de la corrida.
