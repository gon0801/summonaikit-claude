# Task 5.4 — Registro e instalación en zcode (plan para GLM, **después** de 5.3)

`[Setup]` `[lane:gate]` `[tdd:required]`.
**DoD íntegra en `Plans.md:100`:** (1) el hook queda registrado en las 3
fases de `~/.zcode/cli/config.json` **sin matcher** donde el match
value no es el nombre de la herramienta; (2) `hooks.enabled` verificado
en `true`; (3) `tools/install-hook.sh` y
`tools/check-hook-registration.sh` aprenden la **segunda** forma de
registro (`hooks.events.*`) sin perder la primera (`hooks.*`), con el
mismo criterio de tres estados y de `unknown` ≠ ausente; (4) un
registro con matcher equivocado se reporta fuerte en vez de darse por
bueno. **Depende de:** 5.3.

> **Esto SÍ registra el harness en zcode** (a diferencia de 5.1/5.2,
> que eran medición). No es un port: 5.2 declaró `TARGET=claude`
> alcanza. Es el cableado + los dos arreglos que 5.2 dejó explícitos
> (`budget` no corta; `CLAUDECODE` ausente ⇒ la secuencia no corre).

## Este plan se escribe en paralelo a 5.3 — no se implementa todavía

Hasta que `Plans.md:99` no esté `cc:完了` (aislamiento por HOST
medido), **cero append al user-config vivo**. Registrar el harness
en `~/.claude/hooks/` desde zcode *antes* de 5.3 reabre A4-cross-host
(RN_PENDING / `sin-session`). El commit de tests+código del
verificador/instalador **sí** puede ir en sandbox; `--host zcode`
contra el HOME real espera 5.3.

## Cross-review del PLAN con Codex (3 rondas, 2026-08-12 — 3ª pedida)

Ronda 1: 4 altas + 3 medias. Ronda 2: 2 altas + 2 medias. Ronda 3
(esta, pedida): 2 altas + 1 media. Todas incorporadas.
**Listo para GLM después de 5.3.**

### Ronda 3 (sobre el texto post-ronda-2)

1. **[alta] ACEPTADO+verificado** — `matcher` vive en el **grupo**
   (`{matcher, hooks:[…]}`), no en la entrada de `hooks[]`.
   Reemplazar solo la entrada no repara un matcher mal puesto, y
   tocar el matcher del grupo pisa vecinos del mismo array.
   **Fix:** cada 5.4 es un **grupo propio** (un solo hook).
   Bien-formada mira el matcher del grupo. Reparar = sacar ese
   grupo y poner uno limpio. Nunca se edita un grupo que tenga
   hooks ajenos.
2. **[alta] ACEPTADO** — “el command *contiene* bash.exe + DEST +
   id” acepta `echo …bash.exe…DEST…--saikit-harness-id 5.4`.
   **Fix:** igualdad **canónica exacta** del string que emite
   `zcode_hook_cmd`. Test: command con esos textos pero que no
   es el canónico ⇒ se repara.
3. **[media] ACEPTADO** — el preflight “antes de cualquier write”
   aplicado a `--quitar` bloquearía la limpieza si `enabled` no
   es true o DEST está ausente/viejo. **Fix:** `--quitar-zcode`
   no corre ese preflight. Basta user-config existente y JSON;
   saca las entradas 5.4 aunque DEST no esté.

### Ronda 2 (sobre el texto post-ronda-1)

1. **[alta] ACEPTADO** — Grep de una línea 5.3 en DEST acepta un
   archivo modificado o plantado. **Fix:** reusar la clasificación
   de `install-hook.sh`. DEST tiene que ser `NUESTRO_IDENTICO`
   (`cmp` con `$SOURCE`) **y** contener la asignación 5.3.
   `NUESTRO_DISTINTO` / vendor / desconocido ⇒ exit 2, no se
   cablea.
2. **[alta] ACEPTADO+verificado** — `JQ_QUITAR` de 5.1/5.2 hace
   `map(select(ours | not))` sobre el **grupo**: si tokentracker y
   el harness viven en el mismo `{ hooks: [...] }`, se borra el
   grupo entero. El test solo ponía vecinos en **otro** grupo.
   **Fix:** `--quitar` saca la **entrada** (`hooks[]`) con el id;
   el grupo sobrevive si le queda algo. Test: mismo array, dummy +
   5.4 → dummy queda.
3. **[media] ACEPTADO** — `has_tag` por id da por buena una 5.4
   malformada (`type: process`, `timeout: 500`, matcher en UPS).
   **Fix:** una entrada cuenta solo si está **bien formada** (type
   command, timeout 15, command con bash.exe+DEST+id, UPS/Stop sin
   matcher, PTU cubre Task|Agent). Si está el id pero mal ⇒ se
   reemplaza, no se salta.
4. **[media] ACEPTADO** — faltaban casos de `enabled: "yes"` /
   `1` y de `"matcher": ""`. Truthiness los dejaría verdes.
   **Fix:** tests explícitos.

### Ronda 1 (resumen; ya en el cuerpo)

1. **[alta] ACEPTADO+verificado** — Stop camel-only **sin** estado:
   `stop_gate` (`:1066`) y `record_tool_evidence` (sin
   `task_hash`/estado) terminan los dos en `emit_allow`. El caso 3
   era vacuo y ninguna mutación quitaba el fallback camel. **Fix:**
   sembrar estado armado; camel-only Stop debe **bloquear** (recibo
   ausente). `mut_phase_sin_camel` anula el fallback → el mismo
   payload cae a `tool` y **no** bloquea.
2. **[alta] ACEPTADO** — DoD: matcher equivocado se reporta **en el
   verificador**, no solo en el test del instalador. Un registro
   manual con matcher en UPS/Stop tiene que gritar. **Fix:** modo
   zcode reporta UPS/Stop **con** matcher.
3. **[alta] ACEPTADO** — Grep de comentario / `HOST=zcode` en la
   fuente (o `--no-file` sin mirar el vivo) registra un dest viejo
   que aún comparte estado. **Fix:** se exige en el **DEST vivo**
   (no solo la fuente) la línea de código
   `PROJECT_DIR="$STATE_ROOT/$HOST/$PROJECT_KEY"` (o la que 5.3
   deje). `--host zcode` **no escribe el archivo** (append-only).
4. **[alta] ACEPTADO+verificado** — `install-hook.sh` promete que
   todo exit ≠ 0 deja `DEST` intacto (`:229`). Instalar el archivo
   y fallar después en el user-config rompe ese contrato. **Fix:**
   `--host zcode` es **solo append** al user-config. El archivo se
   instala con la invocación Claude de siempre, antes. Preflight
   (config existe, enabled true, dest tiene 5.3) **antes** de
   cualquier write.
5. **[media] ACEPTADO** — `enabled` ausente o no-bool, si el
   archivo **se leyó**, no es `true` ⇒ los hooks no corren (spec).
   Reportar fuerte, no `unknown`. `unknown` queda para ilegible.
6. **[media] ACEPTADO+verificado** — `install-hook.sh` **no** tiene
   el filtro de perfil de `capture-payloads`. `--dest
   $HOME/.zcode/hooks/summonaikit-harness.sh` pasaría y crearía la
   segunda copia que 5.3 prohibió. **Fix:** `--host zcode` y
   `--dest` se niegan si el dest resuelve a `$HOME/.zcode*`.
7. **[media] ACEPTADO** — En zcode, matcher `Task` **sí** ve
   `Agent` (5.1). Gritar “no cubre Agent” es alarma falsa. **Fix:**
   en modo zcode, `_matcher_cubre` acepta si el regex pega `Agent`
   **o** `Task`. Ni uno ni otro ⇒ uncovered. Claude no cambia.

| 5.3 | 5.4 |
|---|---|
| `cc:TODO` | No `--instalar` vivo. Tests contra `SAIKIT_ZCODE_USER_CONFIG` de sandbox sí |
| `cc:完了` + HOST en el hook | Este plan se ejecuta tal cual |
| Replan / no se aisló | No se registra. Este doc queda como evidencia |

## Premisas medidas (no re-litigar)

De **5.1** (entrada):

- Este CLI (3.7.5-11) **ignora** `<repo>/.zcode/config.json` (`gri`).
  Registro = append al **user-config**. 5.5 no puede copiar el staging
  de 2.4 a ese override — fuera de esta task, pero no se implementa
  un “staging de proyecto” acá.
- Alias `Task`↔`Agent` **sí** transporta. Matcher `Task` ve `Agent`.
- `CLAUDECODE` **ausente**. `ZCODE_SESSION_ID` / `ZCODE_PROJECT_DIR`
  las inyecta zcode (`bzt()`). No es el prefijo `VAR=val` de A10.
- `type: command` + `timeout` en **segundos** + bash.exe Windows:
  stdin llega (medido).
- UPS/Stop: el matcher se prueba contra el **texto** / la **preview**.
  Un matcher copiado de Claude no pega. **Omitir matcher** en esas
  dos.

De **5.2** (salida):

- Forma 1 (`additionalContext`) **aceptada**. `decision:block`+exit 0
  **aceptada**. `exit 2` en Stop **aceptada** (4 pasadas).
- Esquema **no** estricto (`extra` aceptada).
- `notice` ignorada (RN fail-open).
- `budget` (`continue:false`+exit 0) **ignorada**. El vivo
  (`emit_budget_exhausted :995`) **no** suma exit 2. Tras 2 ciclos el
  Stop cierra como allow. **Esta task lo cambia**, y **solo** en
  zcode: en Claude esa forma sí es el corte.
- `TARGET=claude` alcanza las formas. **No** se inventa
  `TARGET=zcode` ni un emit distinto por host, salvo el `exit` del
  budget.

De **5.3** (estado, plan post-Codex):

- Un solo archivo vivo: `~/.claude/hooks/summonaikit-harness.sh`.
  HOST sale del env (`ZCODE_*` → `zcode`, `CLAUDECODE=1` → `claude`).
  Apuntar zcode a ese path **está bien**.
- `lab_run` ya hace `-u ZCODE_*` (r2.1). No reabrir eso.

## A10 en zcode — el hueco que esta task cierra

Hoy (`:34`):

```
if [ -z "$TARGET" ] && [ "$CLAUDECODE" = "1" ]; then TARGET="claude"; fi
```

La secuencia (`:1132`, implementer→verifier→reviewer) solo corre si
`TARGET=claude`. En zcode `CLAUDECODE` no está ⇒ `TARGET` vacío ⇒ el
hook **inyecta y puede bloquear**, pero **no exige** la ceremonia.
Registrar sin este fallback instala un gate decorativo en la mitad
que más importa. 5.1 lo dejó para 5.4.

**No** se pone `SUMMONAIKIT_HOOK_TARGET=claude` en el `command` del
user-config: A10 midió que el host **no propaga** el prefijo
`VAR=val`. La señal es `ZCODE_*`, que sí llega.

```
# Después del fallback CLAUDECODE (y del HOST de 5.3):
if [ -z "$TARGET" ] && [ -n "${ZCODE_SESSION_ID:-}${ZCODE_PROJECT_DIR:-}" ]; then
  TARGET="claude"
fi
```

`glm` (`exec claude`) sigue por `CLAUDECODE=1`. Si algún día zcode
setea los dos, HOST=`zcode` (5.3) y TARGET=`claude` (esta). No se
crea `TARGET=zcode`.

## budget — solo el path zcode

`emit_budget_exhausted` hoy: JSON `continue:false` + **exit 0**.
Claude se apoya en eso. zcode lo ignora (5.2).

**No** cambiar el exit de Claude a 2: en Claude eso puede convertirse
en 4 pasadas (`p3i`) en vez de cortar.

```
# al final de emit_budget_exhausted, rama no-cursor:
if [ -n "${ZCODE_SESSION_ID:-}${ZCODE_PROJECT_DIR:-}" ]; then
  printf '%s\n' "$message" >&2
  exit 2          # 5.2: exit 2 en Stop SÍ bloquea
fi
printf '{"continue":false,"stopReason":"%s"}\n' "$escaped"
printf '%s\n' "$message" >&2
exit 0            # Claude, intacto
```

(El JSON de `continue:false` en zcode sobra: con exit 2 no se parsea.
No hace falta emitirlo ahí.)

Caso G1/G4: con `LAB_ZCODE_SESSION_ID` sembrado, presupuesto agotado
⇒ exit 2. Sin `ZCODE_*`, sigue exit 0 + `continue:false`. El caso
viejo de presupuesto **no se invierte**.

## PHASE camel — el Stop que 5.2 vio

5.1: Stop trae `hook_event_name` **y** `hookEventName`. 5.2: un Stop
realista trajo **solo camel**. El hook (`:1216`) lee
`json_string_field hook_event_name`. Si falta, `PHASE` cae a `tool` y
`stop_gate` no corre.

```
event="$(json_top_level_string hook_event_name)"
[ -n "$event" ] || event="$(json_top_level_string hookEventName)"
```

`json_top_level_string`, no el `sed` greedy (mismo UTF-8 que rompió
el probe). Caso: payload Stop **solo** camel ⇒ `PHASE=stop` (el Stop
evalúa el gate, no `record_tool_evidence`).

No se reescribe `json_string_field` entero acá. Residual declarado:
`last_assistant_message` sigue por el walker de 3.2 + este campo;
si un Stop camel-only rompe otro lector, se declara, no se agranda
el alcance.

## Qué cambia y qué NO

**NO cambia:**

- El dest del **archivo**: sigue `~/.claude/hooks/summonaikit-harness.sh`.
  No hay segunda copia bajo `~/.zcode/hooks/`.
- La forma Claude de `hooks.*` en `settings.json`.
- `emit_gate_failure` / forma 1 / `notice`.
- `hooks.enabled` del operador: si no es `true`, se **avisa y se
  aborta** el append. No se flippea en silencio.
- Override de proyecto (sigue muerto).
- 5.5 (línea base / turno que arma y uno que no).

**Cambia:**

- `hooks/summonaikit-harness.sh`: fallback TARGET por `ZCODE_*`;
  budget zcode → exit 2; PHASE lee camel.
- `tools/check-hook-registration.sh`: `--zcode-config <path>` lee
  `hooks.events.*`. Sin el flag, comportamiento Claude **idéntico**.
- `tools/install-hook.sh`: `--host zcode` es **append-only** al
  user-config (no toca `DEST`). `--quitar-zcode` saca solo id
  `5.4`. Se niega dest/`--dest` bajo `$HOME/.zcode*`.
- Tests: `test_hook_registration.sh` (forma zcode + regresión
  Claude), `test_install_hook.sh` (append/quitar sandbox),
  `gate_cases.sh` (TARGET por ZCODE, budget zcode, Stop camel).
- Spec § segundo host: bloque “Medido, Task 5.4”.
- `Plans.md:100` → `cc:完了` solo con registro vivo + verificador
  en silencio (o matcher reportado si se dejó el hueco a propósito).

---

## A) `check-hook-registration.sh` (TDD primero)

El verificador hoy asume `data["hooks"][fase] = [ grupos ]` (forma
Claude). Un user-config de zcode tiene `hooks.events.fase`. Pasarle
el config de zcode **sin** este cambio reporta
`INCOMPLETO — el gate NO corre en: UserPromptSubmit PostToolUse Stop`
aunque las tres estén. Alarma falsa (dirección de A10 / 0.4).

### A1. Flag

```
bash tools/check-hook-registration.sh
bash tools/check-hook-registration.sh --settings <claude-settings>
bash tools/check-hook-registration.sh --zcode-config <user-config>
```

- `--zcode-config` solo. No se mezcla con `--settings` en la misma
  invocación (exit 0 + `unknown`, fail-open: corre en SessionStart).
- Default de `--zcode-config` si el flag va **sin path**: no. Flag
  sin valor = `unknown` (lección 0.4, ya implementada).
- El path por defecto **no** se adivina en el modo Claude: un
  SessionStart de Claude no debe ir a leer `~/.zcode` y afirmar
  cosas del segundo host. Quien quiera zcode **pasa el flag**.
- `install-hook --host zcode` es quien lo invoca con
  `$SAIKIT_ZCODE_USER_CONFIG` / `~/.zcode/cli/config.json`.

### A2. Lector

En el python embebido, si el 4º argv es `zcode`:

```
hooks_root = data.get("hooks") or {}
events = hooks_root.get("events") if isinstance(hooks_root, dict) else None
if not isinstance(events, dict):
    # no hay events => cero fases observadas (no unknown: se leyó)
    events = {}
# iterar events, no hooks_root
```

También se observa `hooks_root.get("enabled")`. Si el archivo se
**leyó** y `enabled` no es JSON `true` (ausente, `false`, string,
lo que sea) ⇒ se reporta fuerte (hallazgo 5):

```
[summonaikit] REGISTRO DEL HOOK: hooks.enabled no es true en el user-config de zcode.
              Los hooks de archivo no corren.
```

`unknown` de enabled **solo** si el archivo es ilegible (ya cubierto
por el `unknown` de siempre).

UPS o Stop **con** clave `matcher` (aunque sea `""`): se reporta
fuerte (hallazgo 2). El match value ahí es el texto del prompt /
la preview; cualquier matcher es el error que la DoD nombra.

`_matcher_cubre` en modo zcode: cubre si el regex pega `"Agent"`
**o** `"Task"` (alias medido 5.1; hallazgo 7). Ni uno ni otro ⇒
`uncovered`. Regex que no compila ⇒ `unknown`. Modo Claude: sin
cambios (solo `"Agent"`).

El registro que **esta** task escribe igual lleva `Task|Agent`
(redundante, barato, el verificador calla).

### A3. Tests (`tests/test_hook_registration.sh`)

Sandbox. No toca HOME.

1. Fixture zcode **completo**: `hooks.enabled: true`,
   `events.{UserPromptSubmit,PostToolUse,Stop}`, UPS/Stop **sin**
   matcher, PTU `Bash|Edit|Write|Read|apply_patch|Task|Agent`,
   command nombra el harness. `--zcode-config` ⇒ **silencio**,
   exit 0.
2. Mismo fixture **sin** Stop ⇒ `INCOMPLETO` + `Stop`.
3. Fixture zcode con UPS (o Stop) que **tiene** matcher `"Task"`
   ⇒ el **verificador** reporta fuerte. Igual con `"matcher": ""`
   (clave presente, valor vacío — hallazgo r2.4). Exit 0.
4. PTU matcher `Task` solo (sin `Agent`) ⇒ **silencio** en modo
   zcode (el alias cubre). PTU matcher `Bash` solo ⇒ `uncovered`.
   Claude con `Task` solo sigue gritando (regresión).
5. User-config ilegible ⇒ `unknown`, no `INCOMPLETO`.
   `enabled: "yes"` o `enabled: 1` (se leyó, no es `true`) ⇒
   reporta fuerte, no silencio ni `unknown`.
6. `--zcode-config` + `--settings` juntos ⇒ `unknown`.
7. **Regresión:** los casos Claude existentes (completo / real sin
   Agent / echo-no-cuenta / flag sin valor) siguen iguales.
   `--settings` no lee zcode.

```
bash tests/test_hook_registration.sh
```

---

## B) `install-hook.sh --host zcode`

Misma disciplina que `capture-payloads` / `probe-zcode-output`.

### B1. Contrato

```
bash tools/install-hook.sh                  # Claude: solo el ARCHIVO (igual que hoy)
bash tools/install-hook.sh --host zcode     # SOLO append al user-config (no toca DEST)
bash tools/install-hook.sh --host zcode --quitar-zcode
```

- `--host` solo vale `zcode`. Otro valor ⇒ exit 2, no escribe
  **ni** el archivo **ni** el config.
- `--host zcode` **no instala el archivo**. El contrato “exit ≠ 0
  ⇒ DEST intacto” se conserva porque esta invocación no escribe
  DEST (hallazgo 4). El archivo se pone antes, con la invocación
  sin `--host`.
- `--dest` bajo `$HOME/.zcode*` (o que `pwd -P` resuelva ahí) ⇒
  exit 2, también **sin** `--host` (hallazgo 6). Una sola copia:
  `~/.claude/hooks/…`.
- User-config: `$SAIKIT_ZCODE_USER_CONFIG` (default
  `~/.zcode/cli/config.json`). No existe ⇒ exit 2, no crear de
  cero.
- Tests: sandbox. Core Rule 4.

### B2. Qué appendea (3 fases, id `5.4`)

`type: command`, `timeout: 15`, bash.exe Windows (misma
`zcode_bash_win` que 5.1/5.2). Marker `--saikit-harness-id 5.4`
en `args` del command (el verificador no lo necesita; `--quitar`
sí).

```
UserPromptSubmit   sin matcher
PostToolUse        matcher: Bash|Edit|Write|Read|apply_patch|Task|Agent
Stop               sin matcher
```

Command (un string, como el resto del user-config):

```
"<bash-win>" "<dest-del-hook>" --saikit-harness-id 5.4
```

**Sin** `SUMMONAIKIT_HOOK_TARGET=…` (A10). **Sin** `--only-cwd`
(este no es un probe: el gate corre en todos los repos, el estado
lo separa HOST+proyecto+sesión).

Idempotente por **grupo propio bien formado** (r2.3 + r3.1/r3.2),
no por substring del id. Cuenta si el grupo:

- tiene **un solo** hook en `hooks[]` (grupo propio; no se comparte);
- UPS/Stop: **sin** clave `matcher` en el grupo;
- PTU: `matcher` del **grupo** cubre Task|Agent;
- la entrada: `type=="command"`, `timeout==15`;
- `command` es **igual** (string exacto) al que emite
  `zcode_hook_cmd` (bash.exe + DEST + `--saikit-harness-id 5.4`).
  Contener esos textos no basta.

Si el id está y falla alguno ⇒ se **saca el grupo entero** (es
nuestro: un solo hook) y se pone uno limpio. Si el id aparece
dentro de un grupo **con** hooks ajenos: se saca **solo** nuestra
entrada (r2.2); no se toca el matcher del grupo (ajeno); se
**añade** un grupo propio limpio. Si faltan 1 o 2 fases ⇒
completa. Backup + `cmp`. jq a temp + validar + `mv`.

**Preflight, en este orden, antes de cualquier write:**

1. User-config existe y es JSON.
2. `hooks.enabled == true` (estricto: JSON boolean true; `"yes"`
   / `1` / ausente ⇒ exit 2, nada escrito).
3. DEST se clasifica con la **misma** función que el instalador
   Claude: tiene que ser `NUESTRO_IDENTICO` (`cmp -s` con
   `$SOURCE`) **y** contener la asignación 5.3
   `PROJECT_DIR="$STATE_ROOT/$HOST/$PROJECT_KEY"` (literal de
   código, no comentario). `NUESTRO_DISTINTO`, vendor,
   desconocido o ausente ⇒ exit 2: “instalá/repará el archivo
   primero”. No se cablea un dest que solo *menciona* HOST.

`--quitar-zcode`: **no** corre el preflight de DEST/`enabled`
(r3.3). Basta user-config existente y JSON parseable. Saca la
entrada cuyo command lleva el id; si el grupo queda vacío, se
borra el grupo; si le quedan ajenos, el grupo (y su matcher)
sigue. SessionStart / RTK / tokentracker / 5.1 / 5.2 intactos.
DEST ausente o `enabled: false` no impide el quitar.

### B3. Tests (`tests/test_install_hook.sh` o hermano)

`SAIKIT_ZCODE_USER_CONFIG` de sandbox, config mínimo con
SessionStart dummy + Stop tokentracker + `enabled: true`.

1. `--host zcode` appendea 3 fases, UPS/Stop sin matcher, PTU con
   `Agent` y `Task`, type command, timeout 15. **No toca** el
   archivo DEST (mtime/cksum iguales). Backup del user-config
   fuera del dest git.
2. Segunda vez no duplica. Una 5.4 **malformada** se repara:
   timeout 500; type process; UPS con matcher **en el grupo**;
   command que *contiene* bash.exe+DEST+id pero no es el canónico
   (`echo "…bash.exe…DEST…--saikit-harness-id 5.4"`).
3. Parcial (falta Stop) ⇒ solo completa Stop.
4. `--dest` / dest que resuelve a `$HOME/.zcode` o
   `$HOME/.zcode/hooks/…` ⇒ exit 2, nada escrito.
5. `enabled: false`, `enabled` ausente, `enabled: "yes"` y
   `enabled: 1` ⇒ exit 2, config byte-igual.
6. DEST sin 5.3, o `NUESTRO_DISTINTO` (marcador pero `cmp` falla
   contra SOURCE) ⇒ exit 2, config intacto.
7. `--quitar-zcode` saca 5.4 y deja: dummy en **otro** grupo; **y**
   dummy en el **mismo** `hooks[]` (r2.2). También deja una 5.2.
   Corre con `enabled: false` y con DEST ausente (r3.3).
8. `--host inventado` ⇒ exit 2.
9. **Regresión:** sin `--host` no toca
   `SAIKIT_ZCODE_USER_CONFIG`. Un `--dest` Claude legal
   (`$HOME/.claude/hooks/…`) sigue igual.

Tras append, `check-hook-registration.sh --zcode-config $cfg`
calla (caso A3.1).

---

## C) Hook: TARGET, budget, PHASE

Rojo/verde en `tests/test_gate_behavior.sh` / casos nuevos. No
`run.sh` en el loop.

1. `LAB_ZCODE_SESSION_ID=sess_lab` (y `LAB_CLAUDECODE` vacío) +
   prompt `-saikit` + Stop **sin** subagentes ⇒ reclama
   implementer/verifier/reviewer (la rama `:1132` corrió).
   Control: sin `ZCODE_*` ni `CLAUDECODE`, ese Stop **no** reclama
   secuencia (sigue siendo “other”, como hoy el lab).
2. Presupuesto agotado + `LAB_ZCODE_SESSION_ID` ⇒ exit **2**.
   Mismo caso **sin** ZCODE ⇒ exit 0 y stdout con
   `continue:false` (regresión Claude).
3. Sembrar estado armado (`lab_sembrar` ciclo 0, sin recibo).
   Stop **solo** `hookEventName` (sin snake) ⇒ **bloquea** (exit
   2, reclama recibo): pasó por `stop_gate`. Si cayera a
   `record_tool_evidence`, no bloquearía por recibo (hallazgo 1).

Mutaciones (mínimo 3, cada una con su caso):

- `mut_zcode_sin_target` — anula el fallback `ZCODE_*` → el caso 1
  deja de reclamar secuencia.
- `mut_budget_zcode_sigue_0` — zcode también hace exit 0 → el
  caso 2 queda rojo.
- `mut_phase_sin_camel` — no lee `hookEventName` → el caso 3
  deja de bloquear.

`lab_run` **ya** unsetea `ZCODE_*` y repone desde `LAB_ZCODE_*` (5.3
aterrizó, commit `890ce96`): `hook_lab.sh` hace `-u ZCODE_SESSION_ID
-u ZCODE_PROJECT_DIR` y luego `[ -n "${LAB_ZCODE_SESSION_ID:-}" ] &&
lab_cmd+=(ZCODE_SESSION_ID=…)` (idem `LAB_ZCODE_PROJECT_DIR`). El caso
C1 usa `LAB_ZCODE_SESSION_ID` tal cual — **sin wiring nuevo** en esta
task. (Mi revisión inicial lo había marcado como hueco leyendo un HEAD
pre-5.3; 5.3 lo cerró.)

---

## D) STOP vivo (después de 5.3 y de A–C verdes)

No es el TDD. Es “el hook queda registrado” de la DoD, medido
antes/después del append (cksum de SessionStart / tokentracker +
`grep -c saikit-harness-id 5.4`).

```
bash tools/install-hook.sh --host zcode
bash tools/check-hook-registration.sh --zcode-config "$HOME/.zcode/cli/config.json"
# silencio (o solo el aviso de Agent si el matcher se dejó corto — no debe)
```

Tarjeta:

```
STOP — Gon, no GLM.

1. Cerrá zcode. Abrí zcode (NO glm) en C:\dev\saikit-captura-zcode
   o en cualquier repo git.
2. Un prompt CORTO con -saikit. No hace falta delegar.
3. Avisale a GLM. Él mira que el estado haya caído bajo
   …/hooks/state/zcode/… (5.3) y que el contrato se inyectó
   (mismo oráculo que 5.2: model-io / system msg).
4. Un prompt SIN -saikit en la misma sesión: no debe rearmar.
```

Un turno que **falle** el gate a propósito (omitir verifier) es
5.5, no esta. Acá basta: registrado + arma + no pisa vecinos.

Si el operador no puede: el código+tests se commitean;
`Plans.md:100` se queda `cc:TODO` hasta el registro vivo. No se
cierra con “lo dejamos para 5.5”.

`--quitar-zcode` **no** se corre al cerrar si 5.5 va a usar el
mismo registro. Se deja declarado. Si 5.5 tarda, el gate en zcode
queda activo (advisory) — eso **es** el objetivo.

---

## E) Entregables

### E1. Spec § El segundo host

Bloque “Medido, Task 5.4”: registro en user-config (3 fases, sin
matcher UPS/Stop, PTU cubre Agent); TARGET por `ZCODE_*` (A10
cerrado en zcode); budget zcode = exit 2; PHASE lee camel.
Sin diario.

### E2. `Plans.md:100`

`cc:完了 [<sha>]` solo si: verificador zcode en silencio sobre el
config **vivo**, vecinos intactos, casos G de C verdes, y el STOP
del §D o `cc:TODO` explícito. Convención 4.1.

### E3. 5.5 (no se hace)

El renglón de 5.5 sigue hablando de staging por
`<repo>/.zcode/config.json`. Esa premisa **ya cayó** (5.1). No se
reescribe 5.5 acá; se declara en el cierre para que 5.5 no copie
2.4 a un canal muerto.

---

## F) Commits

1. `test(5.4): check-hook-registration lee hooks.events de zcode`
   — A, rojo luego verde.
2. `feat(5.4): install-hook --host zcode appendea el harness`
   — B.
3. `fix(5.4): TARGET por ZCODE_*, budget zcode exit 2, PHASE camel`
   — C. Puede ir con 2 si el TDD cabe; no mezclar con el
   verificador.
4. **STOP** §D.
5. `docs(5.4): registro zcode y A10 cerrado` + cierre Plans.

TDD en el archivo del test, no `run.sh`. Gate final del feat:
`pre-commit run --files` de lo tocado, luego `--all-files` +
`tests/run.sh`. Nunca `--no-verify`. WSL no es atajo.

---

## Límites

1. Un solo archivo de hook (el de Claude). HOST lo separa (5.3).
2. No se flippea `hooks.enabled`.
3. No se pone `TARGET=zcode`.
4. No se cambia el budget de Claude.
5. No se reescribe `json_string_field`.
6. No se implementa staging de proyecto (muerto).
7. No se cablea el verificador zcode al SessionStart de Claude
   (ruido en cada arranque). `install-hook --host zcode` lo corre
   una vez. Si zcode algún día tiene heal, es otra task.
8. El gate sigue **advisory**.
9. `glm` ≠ `zcode`.

## Cross-review del PLAN

**3 rondas hechas** (la 3ª la pidió el operador). Este texto se le
puede pasar a GLM cuando 5.3 cierre (Depends).

Residual declarado: el close de 5.2 en `Plans.md:98` todavía dice
que el budget “se apoya en exit 2”; `docs/task-5.2-salida.md` ya
está corregido. El `--quitar` de 5.1/5.2 (grupo entero) **no** se
backporta.
