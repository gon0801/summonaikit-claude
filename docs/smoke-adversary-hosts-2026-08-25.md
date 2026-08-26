# Smoke vivo del rol adversary por host — 2026-08-25

Post-merge de la Phase 13 (PR #67) y deploy a los vivos, se corrió UN turno
real armado por host pidiendo el rol (`… -saikit: agrega un docstring … y
ataca el cambio con adversary`) sobre repos descartables. Registro de lo
OBSERVADO — cada afirmación con su evidencia; lo no observado queda `unknown`
(Core Rule 2). Complementa la sección del rol en
`docs/spec/00-project-spec.md` (los "casos por target" del gate son de
laboratorio; esto es lo vivo).

## grok — el mecanismo del rol completo, EN VIVO

Host: grok 1.0.5 (5115b46bc9). Turno headless
`grok --cwd <repo> --always-approve --single="Tarea -saikit: …"` (la forma
exacta que corrió — ver el gotcha de invocación abajo).
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

**Límite observado EN ESTA EJECUCIÓN (del host, no del hook):** `--single` no
reanudó el loop del modelo cuando el subagente terminó — la notificación llegó
como evento sintético de usuario SIN sentinel, el gate se desarmó POR DISEÑO
(A5: prompt sin `-saikit` = stand down; el estado quedó con la firma exacta
del desarme A4-c2: archivos borrados, dir vacío en
`~/.grok/hooks/state/grok/1747054581/01a03a8e-…/`) y la sesión terminó sin
recibo final. El transcript no contiene `ADVERSARY:` fuera del contrato
inyectado, consistente con ese corte. **Una sola corrida: generalizarlo a
regla de `--single` queda `unknown`** — la vía con recibo que sí se conoce es
la sesión interactiva/multi-turn.

## zcode — el hook armó en vivo; el turno murió en el host

Host: zcode 0.16.1. Turno headless
`zcode --cwd <repo> --prompt="Tarea -saikit: …"`.

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
  registered zcode:// callback"). La 12.1 ya había visto fallar un headless
  SIN `-saikit` (`--prompt "/model"`) con el MISMO error genérico, pero sin
  establecer la causa; **la causa (la key) se estableció recién acá con
  `--verbose`**. Esta ejecución no alcanza para atribuir el fallo al kit ni
  para descartarlo por completo: el control "headless con causa medida y sin
  `-saikit`" queda `not_observed`.
- **Pendiente que esto dejó — YA RESUELTO el mismo día** (ver la subsección
  siguiente, no repitas la prueba): la ceremonia viva en zcode requería o la
  API key de Z.AI en `/login` del TUI, o un turno interactivo del operador;
  el headless quedó saltado por decisión del operador y el operador corrió el
  turno en su TUI.

### Actualización mismo día: pendiente anterior RESUELTO — ceremonia viva COMPLETADA por el operador (TUI)

El operador corrió el turno en su sesión zcode interactiva sobre
`C:\dev\saikit-captura` (sesión `sess_3ba37f4b…`, transcript en
`~/.zcode/cli/rollout/`). Lo observado:

- **El adversary corrió y encontró un hallazgo REAL** (ADV-1, low: `.pyc`
  residual sin gitignore — irónico: lo halló porque ese dir NO es repo git),
  archivado en `.saikit/findings/adversary-app-docstring.json`; la **capa 3**
  creó el `.gitignore` con `*` igual (inofensivo sin git, idempotente ✓).
- **Recibo aceptado al TERCER intento, aceptación REAL** (0 eventos de
  presupuesto agotado en el transcript): 2 bloqueos del gate en los ciclos
  1 y 2. **Los motivos NO fueron del rol nuevo** (0 rechazos por línea
  `ADVERSARY:` u orden): fueron la fricción YA conocida de zcode —
  `Missing SUMMONAIKIT HARNESS RECEIPT` (forma/marcador del recibo no
  detectado) y `Missing verification evidence` (su prosa de evidencia no
  acredita — la familia de VERIFY_SKIP_RE, medida desde 2026-08-13).
- **Mecanismo exacto de los 3 intentos** (del transcript, literal):
  1. Intento 1: `**Understand (leído por mí, el lead):**` — sin marcador y con
     texto entre la etiqueta y los dos puntos ⇒ ninguna etiqueta contó.
  2. Intento 2: las 6 etiquetas + `ADVERSARY:` en la forma `**Etiqueta:**`
     (que SÍ cuenta) pero **sin la línea marcador** ⇒
     `Missing SUMMONAIKIT HARNESS RECEIPT`. Causa: el ejemplo de la
     instrucción global del operador (`## FORMATO DE RECEIPTS Y REPORTES`)
     muestra el patrón de etiquetas sin el marcador.
  3. Intento 3: marcador + etiquetas, y aun así rechazado —
     `Missing verification evidence`: el Verify decía la verdad ("El verifier
     corrió la batería aplicable… `python -m py_compile app.py` exit 0"),
     pero **los comandos del verifier DELEGADO son invisibles para el hook en
     zcode** (canal interno `unknown`, el mismo que deja ciego al candado), así
     que `verified` siguió en 0 y la prosa no traía skip-phrase.
  4. Intento 4 (aceptado): `**Verify:** Corrí yo mismo, contra el archivo
     final, los checks…` — el LEAD re-corrió los comandos, sus eventos SÍ
     llegaron al hook y `verified` se encendió.
  **Consecuencia estructural**: en hosts con canal interno `unknown`, delegar
  la verificación y reportarla con honestidad NO satisface el gate; la
  ceremonia paga el trabajo dos veces. Levantado como Phase 14 en `Plans.md`.
- **Desviaciones menores del artefacto** (label-only, el gate no las juzga;
  el reviewer sí): esquema no canónico (`title`/`detail` en vez de
  `claim`/`trigger`/`evidence`/`confirmed`; sin `attacked`) y
  `generated_at_utc` inventado por el modelo (no corresponde a la hora
  real). Nota para el perfil instalado en zcode y para la adjudicación.

## kimi — medición por LECTURA CRUZADA del port (sin turno nuevo)

La medición pendiente ("¿qué campo lleva la identidad del subagente en los
payloads de kimi?") resultó ya respondida por evidencia existente: el port
`summonaikit-kimi` capturó los payloads CRUDOS de kimi-code 0.34.0 el
2026-08-07 (una sesión `kimi -p` real, hook de captura registrado en el
`config.toml` del sandbox, stdin sin retocar —
`summonaikit-kimi/tests/fixtures/*.json` + su README de procedencia).

- **Despacho**: el `PostToolUse` del tool `Agent` lleva
  **`tool_input.subagent_type`** (`"explore"` en la captura) — la MISMA forma
  snake que claude/zcode: el lector actual de este repo lo acreditaría sin
  cambio alguno.
- **Eventos internos**: `SubagentStart`/`SubagentStop` llevan **`agent_name`**
  (no `agent_type` ni `subagentType`); los tool-events DE ADENTRO del
  subagente **no aparecen en la captura** (el explore leyó un archivo y ningún
  `PostToolUse` suyo llegó al hook) — si kimi entrega esos eventos, y con qué
  identidad, queda `not_observed`.
- **La consecuencia que reencuadra el pendiente**: kimi no corre ESTE hook —
  corre el del port (`summonaikit-kimi/hooks/summonaikit-harness-kimi.sh`);
  este repo solo le instala PERFILES (12.7). "Candado ciego en kimi" es
  trivialmente cierto (el candado no está ahí), y encender el rol adversary
  en kimi = **portar D4–D6 + el candado al port**, con el gate acreditando
  por despacho (canal medido ✓) y el candado de escrituras declarado
  best-effort/ciego para internos hasta observar esos eventos.

## Gotcha de invocación (para el que repita esto)

Un prompt que EMPIEZA con `-saikit` es tratado como flag por los parsers de
ambos CLIs. Formas OBSERVADAS (por CLI y versión; lo no probado queda
`unknown`, no se afirma):

| CLI | Falló | Funcionó | No observado |
|---|---|---|---|
| grok 1.0.5 | `-p '-saikit …'` (espacio + valor con guión inicial → "a value is required for '--single <PROMPT>'") | `--single="Tarea -saikit: …"` (igual + sin guión inicial) | espacio + sin guión inicial; `=` + guión inicial |
| zcode 0.16.1 | `--prompt '-saikit …'` (espacio + guión inicial → imprime el help) | `--prompt="Tarea -saikit: …"` (igual + sin guión inicial; llegó al host) | espacio + sin guión inicial; `=` + guión inicial |

El sentinel a mitad del prompt arma igual: la frontera del regex está fijada
por golden.

## Cobertura viva acumulada del rol, por host

| Host | Vivo probado | Queda |
|---|---|---|
| claude | Turno completo (estreno del cierre 13.9: HIGH real hallado + candado mordiendo en vivo) | — |
| grok | Mecanismo completo del rol (artefacto, capa 3, gate, escotillas, candado) | recibo final — en esta ejecución `--single` no reanudó tras subagentes (regla general `unknown`); va por sesión interactiva |
| zcode | **Ceremonia viva completa** (TUI del operador, mismo día): adversary con hallazgo real, capa 3, recibo aceptado al 3er intento — fricción de la familia vieja del recibo/evidencia, 0 rechazos por el rol nuevo | afinar la fricción del recibo en zcode (preexistente); esquema del artefacto no canónico anotado |
| kimi | canales MEDIDOS por lectura cruzada del port: despacho con `tool_input.subagent_type` ✓; internos `agent_name` solo en SubagentStart/Stop | portar el rol al hook del port `summonaikit-kimi` (D4–D6 + candado); tool-events internos `not_observed` |
| codex | no aplica (sin costura de perfiles) | decisión futura de costura |
