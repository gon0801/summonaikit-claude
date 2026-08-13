# Task 5.3 — Aislar el estado por host (plan para GLM, **después** de 5.2)

`[Guardrail]` `[lane:gate]` `[tdd:required]`.
**DoD íntegra en `Plans.md:99`:** (1) un turno de zcode y uno de Claude sobre
el **mismo repo** no comparten estado, medido antes y después (no "no lo
escribimos a propósito"); (2) el mecanismo queda declarado —copia bajo
`~/.zcode/hooks/` (el `dirname $0` ya separa) **o** llaveado explícito por
host— y se elige con su razón; (3) el caso que lo habría atrapado existe.
**Depende de:** 5.2.

> **Esto NO registra el harness en zcode (eso es 5.4) ni mide stdout (5.2).**
> Es A4 en versión cross-host: si el harness se registra como ya se registran
> `cbm-*` (`$HOME/.claude/hooks/...`), `STATE_ROOT` sale de `dirname $0` y
> los dos hosts escriben **el mismo árbol** `~/.claude/hooks/state/`.

## Este plan se escribe en paralelo a 5.2 — no se implementa todavía

GLM está midiendo el contrato de **salida**. 5.3 espera ese cierre:

| 5.2 declara | 5.3 |
|---|---|
| `exit2`/`block0` mueven el Stop (gate no decorativo) | Este plan se ejecuta tal cual |
| Gate decorativo (ambas ignored/rejected) | **No se implementa.** Phase 5 se re-planifica; este doc queda como evidencia de lo que se iba a aislar |
| `TARGET=claude` alcanza **o** hace falta `TARGET=zcode` | No cambia el aislamiento. `TARGET` es 5.4, no esta task |

Hasta que `Plans.md:98` no esté `cc:完了` (o declare replan), **cero
líneas al hook**. El commit 1 de 5.3 no arranca "porque el plan ya está".

## Cross-review del PLAN con Codex (2 rondas, 2026-08-12) — tope cumplido

Tope: 2ª solo con alta, **jamás 3ª**. Ronda 1: 4 altas + 2 medias,
incorporadas. Ronda 2 (esta): 2 altas + 2 medias, incorporadas.
**Listo para GLM después de 5.2. No hay 3ª.**

### Ronda 2 (sobre el texto post-ronda-1)

1. **[alta] ACEPTADO+verificado** — el residual de r1 mentía: la
   baseline **sí** lista `hooks/state/<PROJECT_KEY>/…/harness-state.env`
   (`tests/golden/baseline.txt`, decenas de hits).
   `golden-harness.sh:103` solo normaliza `state/[0-9]+`; con HOST
   el path es `state/other/12345/…` y el regex **no pega**. Además
   el arnés (`:257`) no hace `-u ZCODE_*`: corrido desde zcode, HOST
   queda `zcode` y `--check` depende del host. **Fix:** unset
   `ZCODE_*` en el arnés (como el lab); ampliar `normalizar`;
   regrabar la baseline (solo el segmento HOST; se declara).
2. **[alta] ACEPTADO+verificado** — `correr_caso` (`gate_cases.sh:76`)
   solo hace `lab_limpiar_estado` (disco). No restaura
   `LAB_CLAUDECODE` / `LAB_ZCODE_*`. El caso de A4 sí restaura
   `LAB_SESSION_ID=""`. Sin restore, los G1 siguientes buscan
   bajo `zcode/` y `LAB_ESTADO_PATH` sigue en `other/`. **Fix:**
   el caso restaura las tres vars al salir.
3. **[media] ACEPTADO+verificado** — `lab_init` descubre
   `LAB_ESTADO_PATH` con HOST=`other`. A arma en `claude/`. Usar
   `LAB_ESTADO_PATH` / `lab_hay_estado` mira el archivo equivocado.
   **Fix:** `find` de `ruta_A` y `ruta_B` **después de cada
   armado**. `lab_sembrar` de los casos viejos no se toca: siguen
   sin `LAB_CLAUDECODE` ⇒ siguen en `other/`.
4. **[media] ACEPTADO+verificado** — `rn_take_pending` **consume**
   el aviso en el UPS (`:735`). Un UPS normal **no lo crea** (lo
   escribe un Stop con secuencia mala, `:1173`). `find
   review-notice-pending.log` post-UPS da 0 siempre. **Fix:** el
   oráculo vivo de §C es solo `harness-state.env` post-UPS. RN se
   mide en el lab (A2). Si se quiere RN en vivo: plantarlo a mano
   bajo `state/claude/<key>/` *antes* del UPS de zcode y afirmar
   que sigue.

### Ronda 1 (resumen; ya en el cuerpo)

1. **[alta] ACEPTADO+verificado** — `lab_run` no hace `env -u
   ZCODE_SESSION_ID -u ZCODE_PROJECT_DIR`. Si la suite corre *dentro*
   de zcode, el lado "Claude" (`LAB_CLAUDECODE=1`) hereda `ZCODE_*` y
   `HOST` queda `zcode` en los dos. Es el mismo bug que
   `hook_lab.sh:133-138` ya cierra para `CLAUDECODE`. **Fix:** esas
   dos se *unsetean siempre* y solo se reponen desde `LAB_ZCODE_*`.
2. **[alta] ACEPTADO+verificado** — `stop_gate` con
   `STATE_PATH` ausente hace `emit_allow` en `:1066-1069` y **no
   llega** a RN. Un Stop de B sin estado no lee ni borra
   `RN_PENDING_PATH`; el catch de RN del draft era vacuo. **Fix:** B
   tiene que **armar** (`start_harness` → `rn_take_pending`).
3. **[alta] ACEPTADO+verificado** — cierre limpio (`:1196`) y
   presupuesto (`:1205`) **borran** `harness-state.env`. `find`
   después de "armar y cerrar" da 0 archivos y no prueba aislamiento.
   **Fix:** el oráculo vivo inspecciona **después del UPS** (armado),
   antes del Stop que limpia. O se deja el primer Stop bloqueado a
   propósito y se mira entonces.
4. **[alta] ACEPTADO** — `Plans.md:99` exige medición viva antes y
   después. Aplazarla a 5.4 y marcar `cc:完了` incumple la DoD.
   **Fix:** sin medición viva, Plans se queda `cc:TODO`. No se
   reescribe la DoD en silencio.
5. **[media] ACEPTADO** — el contrato acepta `ZCODE_SESSION_ID` **o**
   `ZCODE_PROJECT_DIR`; el draft solo aislaba la primera. **Fix:**
   control con *solo* `ZCODE_PROJECT_DIR`.
6. **[media] ACEPTADO** — fuente en zcode + vivo en Claude ⇒ `$0`
   distinto ⇒ `STATE_ROOT` distinto ⇒ "aislados" sin haber llaveado
   HOST. **Fix:** los dos hosts corren **el mismo** hook actualizado
   (el vivo, post-install de esta task, o la fuente en los dos).

## Premisa que este plan NO da por cierta (lección 3.4)

El renglón de `Plans.md:99` se escribió **antes** de cerrar A4. Hoy el
estado **ya no** es `STATE_ROOT/$PROJECT_KEY/harness-state.env`. Es:

```
STATE_ROOT/$PROJECT_KEY/$SESSION_KEY/harness-state.env
```

`session_id` de Claude (UUID) y de zcode (`sess_…`, medido 5.1) no
colisionan. Dos hosts sobre el mismo `$0` **ya no pisan el mismo
`harness-state.env`**, salvo:

1. `session_id` vacío → ambos caen al slot `sin-session` (`:210`).
2. `RN_PENDING_PATH` vive en `$PROJECT_DIR` **sin** sesión (`:480`): un
   Stop de zcode puede escribir o **borrar** el aviso RN de Claude.
3. Defensa: no apostar el aislamiento a que los `session_id` nunca
   coincidan. A4 apostó a la sesión; 5.3 no reabre eso, **añade** host.

Re-medir el defecto es el primer paso de la implementación (A0), no un
párrafo que se da por bueno.

## Hallazgos de 5.1 que rigen el diseño (no re-litigar)

- Este CLI (3.7.5-11) **ignora** `<repo>/.zcode/config.json`. No hay
  staging por override de proyecto que separe estado (el de 2.4 no aplica).
- `CLAUDECODE` **ausente** en zcode. No sirve para detectar zcode. Sí
  sirve para Claude / `glm` (`exec claude`).
- `ZCODE_SESSION_ID` y `ZCODE_PROJECT_DIR` **llegan al env del hook**
  (allowlist de 5.1). No es el prefijo `VAR=val` de A10: el host los
  inyecta (`bzt()` del bundle). Esa es la señal de host.
- `transcript_path` es un tmp (`%TEMP%/zcode-claude-hook-<rand>/`) que
  zcode borra al terminar el hook. Durante el hook el archivo existe;
  A6 lo rechaza porque está fuera de `PROFILE_DIR`.
- `last_assistant_message` **sí** viene en Stop. El canal 1 del recibo
  vive; el canal 2 (tail del transcript) en zcode está muerto hoy.
- `glm` ≠ `zcode`. `glm` es Claude y ya está gateado.

## Decisión de mecanismo (se elige acá; 5.4 no la reabre)

Dos opciones que nombra la DoD:

| | Copia `~/.zcode/hooks/` | Llaveado explícito por host |
|---|---|---|
| Qué separa | `dirname $0` (ya existe) | `STATE_ROOT` incluye `HOST` |
| ¿El hook cambia? | No | Sí |
| ¿El caso "mismo `$0`, dos hosts" queda rojo hoy? | **No** (ya pasa: es el staging) | Sí, hasta implementar |
| Si 5.4 registra como `cbm` (`~/.claude/hooks/…`) | **Reabre el defecto** | Sigue aislado |
| Archivos vivos que install/heal deben sync | 2 | 1 (el de 2.2/4.1) |
| Detección de host | No hace falta | `ZCODE_*` / `CLAUDECODE` |
| A6 `PROFILE_DIR` | `~/.zcode` (tmp sigue fuera) | `~/.claude` (tmp sigue fuera) |

**Se elige llaveado explícito.** Razón, en este orden:

1. El caso que la DoD pide ("el que lo habría atrapado") solo es un
   rojo *nuevo* si dos invocaciones del **mismo** `$0` dejan de
   compartir. La copia ya está cubierta por 2.4 (`<repo>/.claude/hooks`
   vs perfil) y no mueve el hook.
2. El patrón `cbm` —apuntar zcode a `$HOME/.claude/hooks/…`— es el que
   el operador **ya usa**. 5.4 va a querer copiarlo. Si 5.3 solo copia
   el binario, un registro "como cbm" reabre A4-cross-host en silencio.
3. Un solo archivo vivo. 4.1 sacó `.claude` del heal; no reintroducir
   un segundo dest que hay que sincronizar a mano.
4. La señal `ZCODE_SESSION_ID` está medida (5.1). No es fe.

**No se elige las dos a la vez** (YAGNI). 5.4 puede *además* copiar el
binario si más adelante hace falta un `PROFILE_DIR=~/.zcode`; no es
esta task.

### Cómo se llavea

```
HOST = zcode    si $ZCODE_SESSION_ID o $ZCODE_PROJECT_DIR no vacío
     | claude   si no lo anterior y $CLAUDECODE = 1
     | other    en cualquier otro caso (cursor, lab, unknown)
```

`ZCODE_*` gana a `CLAUDECODE`. zcode setea `CLAUDE_SESSION_ID` /
`CLAUDE_PROJECT_DIR` pero **no** `CLAUDECODE` (5.1). Si algún día
setea los dos, zcode sigue ganando: la señal única es `ZCODE_*`.

```
STATE_ROOT="$HOOK_DIR/state"
PROJECT_DIR="$STATE_ROOT/$HOST/$PROJECT_KEY"   # HOST entra AQUÍ
STATE_DIR="$PROJECT_DIR/$SESSION_KEY"
RN_PENDING_PATH="$PROJECT_DIR/review-notice-pending.log"
```

`RN_PENDING` se mueve con el host. Si se deja en
`$STATE_ROOT/$PROJECT_KEY/…` (sin `HOST`), el defecto 2 sobrevive y
el caso de RN queda verde por el motivo equivocado.

`HOST=other` **nunca** escribe en `claude` ni `zcode`. Cursor y el lab
(que hoy no exportan ni `CLAUDECODE` ni `ZCODE_*`, ver
`hook_lab.sh:129`) caen en `other`. El lab **sigue encontrando** el
estado con `find … harness-state.env` (ya no asume la profundidad).

No migrar el árbol viejo `state/$PROJECT_KEY/$SESSION_KEY/`. Queda
huérfano. Un `-saikit` abandonado pre-5.3 no se cobra: el hook ya no
lo lee. Declarado. Migrar reabriría A4 (un rename a ciegas).

No se setea `TARGET=zcode` acá. Eso lo decide 5.2 y lo cablea 5.4.

## A6 en zcode — se **declara**, no se agranda

`PROFILE_DIR="$(cd "$HOOK_DIR/.." && pwd)"`. Con el hook en
`~/.claude/hooks`, el tmp de zcode queda **fuera**. Fail-open:
`transcript=unknown`, el gate corre con `last_assistant_message`
(presente, 5.1). Es el mismo desenlace que el staging de 2.4.

**No** se añade `%TEMP%/zcode-claude-hook-*` a la allowlist de A6:
sería una primitiva de lectura nueva, controlada por el payload, en
un tmp que cualquier proceso puede plantar. Fuera de esta task. Si
algún día se quiere el canal 2 en zcode, anclar a
`~/.zcode/cli/agents/` con el mismo `cd`+`pwd` — y eso es otra task,
después de 5.4, con su caso.

El caso de 5.3: un Stop con `transcript_path` en forma zcode (tmp
fuera del perfil) + recibo **solo** en el transcript ⇒ se ignora,
stderr trae `transcript=unknown`, el gate **no** se satisface por ese
canal. Control: el mismo recibo en `last_assistant_message` sí cierra
(ya existe, no se toca).

## A quién le toca qué

| Quién | Qué | Qué NO |
|---|---|---|
| **GLM** | A0 (re-medir), TDD, hook, mutación, spec/Plans | Abrir zcode/Claude para el STOP vivo; registrar el harness en el user-config (5.4) |
| **Operador** | STOP vivo **solo si** 5.2 cerró "gate no decorativo" y se pide medición en el descartable | Inventar que "no se compartió" sin `find`/`cmp` |

El STOP vivo **no** es el TDD. El caso que atrapa el defecto es de
laboratorio (mismo `$0`, dos env). El STOP es la medición 2.4-style
sobre el mismo repo, y puede esperar a 5.4 si registrar el harness
todavía no está permitido.

## Qué cambia y qué NO

**NO cambia:**
- Contrato de salida, `emit_*`, `TARGET` (5.2 / 5.4).
- `tools/install-hook.sh`, `check-hook-registration.sh` (5.4).
- User-config de zcode. **No** se appendea el harness acá.
- Override de proyecto (sigue muerto).
- `PROFILE_DIR` / la allowlist de A6.
- La semántica de A4 (sesión). HOST se **suma**, no reemplaza.
- Los hooks ajenos (cbm, RTK, tokentracker).

**Cambia:**
- `hooks/summonaikit-harness.sh`: `HOST` + `PROJECT_DIR`.
- `tests/lib/hook_lab.sh`: `-u ZCODE_*` siempre + reponer desde
  `LAB_ZCODE_*` (espejo de `LAB_CLAUDECODE`).
- `tests/lib/gate_cases.sh`: caso G1 nuevo (restore de vars +
  `find` post-armado).
- `tests/test_gate_mutations.sh`: 1 mutación nueva.
- `tools/golden-harness.sh`: `-u ZCODE_*` y `normalizar` entiende
  `state/<host>/<PROJECT_KEY>`.
- `tests/golden/baseline.txt`: regrabar (solo el segmento HOST;
  veredicto idéntico, como el diff de rutas de 3.4).
- Spec § El segundo host: mecanismo + A6 declarado.
- `Plans.md:99` → `cc:完了` solo si el caso existe, A0 confirmó
  qué se compartía antes, **y** hay medición viva.

---

## A0. Re-medir el defecto (GLM, sandbox, **antes** de escribir el arreglo)

No se toca el hook. Se corre el hook **actual** (HEAD) en el lab, dos
veces, **mismo** `$0`, mismo `PROJECT_ROOT`, **mismo** `session_id`:

```
# A: Claude
LAB_CLAUDECODE=1          (sin ZCODE_*)
# B: zcode
ZCODE_SESSION_ID=sess_lab  (sin CLAUDECODE)
```

Anotar las dos rutas de `harness-state.env` y la de
`review-notice-pending.log`.

Esperado **hoy** (si A4 es lo único que separa):

- `harness-state.env` de A y B son **el mismo path** (mismo
  `session_id` ⇒ mismo `SESSION_KEY`; `STATE_ROOT` idéntico).
- `RN_PENDING_PATH` es el mismo.

Si A y B ya divergen sin tocar el hook, **pará**: la premisa del
renglón cayó del todo y esta task se re-redacta (solo RN, o nada).
No se inventa un arreglo para un defecto que no está.

Eso se escribe en `docs/task-5.3-aislamiento.md` (A0, 10 líneas, sin
rutas de perfil). Recién ahí el TDD.

---

## A) TDD — el caso que lo habría atrapado

Rojo/verde sobre `tests/test_gate_behavior.sh` (carga `gate_cases.sh`),
**no** sobre `tests/run.sh`. El lab ya copia el hook al banco: el `$0`
es el mismo archivo para A y B.

### A1. Lab: inyectar señal de zcode

En `tests/lib/hook_lab.sh`, junto a `LAB_CLAUDECODE` (`:138`):

El `env` de `lab_run` **siempre** hace
`-u ZCODE_SESSION_ID -u ZCODE_PROJECT_DIR` (junto al `-u CLAUDECODE`
que ya tiene). Si la suite corre dentro de zcode, esas vars están en
el entorno padre y sin el unset el lado "Claude" también sale
`HOST=zcode` (hallazgo 1). Se reponen **solo** si el caso las pide:

```
lab_cmd=(env -u SUMMONAIKIT_INTERNAL_GENERATION -u SUMMONAIKIT_HOOK_PHASE
         -u SUMMONAIKIT_HOOK_TARGET -u CLAUDECODE
         -u ZCODE_SESSION_ID -u ZCODE_PROJECT_DIR
         HOME="$LAB/home" USERPROFILE="$LAB/home")
# ... y después, como LAB_CLAUDECODE:
[ -n "${LAB_ZCODE_SESSION_ID:-}" ] && lab_cmd+=(ZCODE_SESSION_ID="$LAB_ZCODE_SESSION_ID")
[ -n "${LAB_ZCODE_PROJECT_DIR:-}" ] && lab_cmd+=(ZCODE_PROJECT_DIR="$LAB_ZCODE_PROJECT_DIR")
```

No hace falta un `lab_init` distinto. `find` sigue descubriendo
`harness-state.env` bajo `state/`.

### A2. Caso G1 (el catch)

`caso_g1_dos_hosts_mismo_repo_no_comparten_estado` en
`tests/lib/gate_cases.sh`, al lado de
`caso_g1_dos_sesiones_no_comparten_estado`.

Contrato, las **dos** mitades (lección A4):

1. Mismo `$0`, mismo `PROJECT_ROOT`, **mismo** `session_id`
   (`LAB_SESSION_ID` fijo). A **arma** (`prompt` `-saikit`) con
   `LAB_CLAUDECODE=1` y sin `ZCODE_*`. Se anota `ruta_A`.
2. Sembrar / escribir `RN_PENDING_PATH` en el lado A (un archivo
   con el texto constante del aviso).
3. B **también arma** (`prompt` `-saikit`) con `LAB_CLAUDECODE=`
   y `LAB_ZCODE_SESSION_ID=sess_lab`. Un Stop de B **sin** estado
   propio no sirve: `stop_gate` con `STATE_PATH` ausente sale en
   `:1066` y nunca toca RN (hallazgo 2). El armado de B es el que
   corre `rn_take_pending`.
4. Mitad 1: B no ve el estado de A — `ruta_B != ruta_A`, y el
   `cycle` de A sigue en 0.
5. Mitad 2: el `harness-state.env` de A **sigue ahí** después del
   armado de B.
6. RN: el archivo pendiente de A **sigue** (B no lo tomó). Si HOST
   no aísla `PROJECT_DIR`, `rn_take_pending` de B se lo come y el
   caso falla. Eso es lo que atrapa el defecto 2.
7. **Redescubrir rutas** (hallazgo r2.3): `ruta_A="$(find
   "$LAB/hooks/state/claude" -name harness-state.env | head -1)"`
   **después** del armado de A. Igual `ruta_B` bajo `…/zcode`
   después del de B. **No** usar `LAB_ESTADO_PATH` (apunta a
   `other/`, lo que descubrió `lab_init`).
8. **Restaurar al salir** (hallazgo r2.2), igual que
   `caso_g1_dos_sesiones` restaura `LAB_SESSION_ID`:
   `LAB_CLAUDECODE=`; `LAB_ZCODE_SESSION_ID=`;
   `LAB_ZCODE_PROJECT_DIR=`. `correr_caso` no lo hace.

No usar el Stop de B como oráculo de "no bloquea por A": si B
armó, su Stop evalúa **su** estado, no el de A. El aislamiento se
afirma por **rutas distintas + archivo de A intacto**, no por el
exit code del Stop.

`CASOS_G1` suma el caso **al final** (la batería corta en el primer
rojo; el orden acredita mutaciones).

Rojo medido contra el hook **actual** (A y B comparten path). Después
el mínimo cambio (`HOST` + `PROJECT_DIR`).

### A3. Controles (no son el catch; no tienen mutación propia)

- `LAB_CLAUDECODE=1` sin `ZCODE_*` ⇒ path contiene `/claude/` (o el
  segmento que se elija). Regresión A10: `glm`/Claude siguen en
  `claude`.
- Solo `ZCODE_SESSION_ID` (sin `ZCODE_PROJECT_DIR`) ⇒ segmento `zcode`.
- Solo `ZCODE_PROJECT_DIR` (sin `ZCODE_SESSION_ID`) ⇒ segmento `zcode`.
  Sin este control, una implementación que ignore `ZCODE_PROJECT_DIR`
  pasa toda la batería (hallazgo 5).
- Las dos señales a la vez ⇒ `zcode` (gana `ZCODE_*`).
- Ninguna ⇒ `other`. Distinto de `claude` y de `zcode`.
- A6: Stop con `transcript_path` tipo
  `$TMPDIR/zcode-claude-hook-XXXX/transcript.jsonl` (archivo real con
  un recibo plantado) ⇒ `transcript=unknown` en stderr, **no** cierra
  el gate por ese canal. Se puede colgar de
  `caso_g4_transcript_fuera_de_perfil_se_ignora` (ya cubre "fuera");
  si el path de zcode es solo otra forma de "fuera", **no** se duplica
  el caso — se declara que A6 no se tocó y el caso viejo alcanza.

### A4. Mutación

`tests/test_gate_mutations.sh`:

```
G1|host_sin_llave|el estado se vuelve a llavear sin HOST (A y B colapsan)
```

```
mut_host_sin_llave() {
  # Anula el segmento HOST: PROJECT_DIR vuelve a STATE_ROOT/PROJECT_KEY.
  sed 's#PROJECT_DIR="\$STATE_ROOT/\$HOST/\$PROJECT_KEY"#PROJECT_DIR="$STATE_ROOT/$PROJECT_KEY"#'
}
```

Acreditada a `caso_g1_dos_hosts_mismo_repo_no_comparten_estado`.
Si la mutación no pone ese caso en rojo, el caso no atrapa el
defecto.

Conteo: G1 +1 mutación. El driver ya exige que cada mutación tenga
caso propio; no aflojar eso.

### A5. Verde y commit

```
bash tests/test_gate_behavior.sh     # TDD
# gate del commit 1 (una vez, al final):
pre-commit run --files hooks/summonaikit-harness.sh tests/lib/gate_cases.sh tests/lib/hook_lab.sh tests/test_gate_mutations.sh
```

`tests/run.sh` es el gate FINAL del commit 1, no el loop. Nunca
`--no-verify`. WSL no es atajo (el hook es MSYS-dependiente).

```
feat(5.3): STATE_ROOT llavea por host (claude/zcode/other)
```

### A6. Línea base dorada (r2.1 — no es opcional)

`tests/golden/baseline.txt` **sí** serializa rutas de estado
(`hooks/state/<PROJECT_KEY>/<session>/harness-state.env`). El
residual de r1 estaba mal.

1. En `tools/golden-harness.sh:257`, el `env -u` suma
   `ZCODE_SESSION_ID` y `ZCODE_PROJECT_DIR` (junto a `CLAUDECODE`).
   Sin eso, `--check` corrido desde zcode escribe `state/zcode/…`
   y desde Claude `state/other/…`.
2. `normalizar` (`:103`) hoy es `s|state/[0-9][0-9]*|…|`. Con HOST
   el path es `state/other/12345/…` y no pega. Queda:

```
-e 's|state/\(claude\|zcode\|other\)/[0-9][0-9]*|state/<PROJECT_KEY>|g' \
-e 's|state/[0-9][0-9]*|state/<PROJECT_KEY>|g'
```

   La segunda línea cubre cualquier residual pre-HOST.
3. Regrabar `tests/golden/baseline.txt`. El diff es **solo
   rutas** (aparece `/other/` o el segmento se come en el
   normalizador y las líneas vuelven a `state/<PROJECT_KEY>/…`).
   **Ningún veredicto se mueve.** Si `--check` cambia un exit o
   un stdout, pará: eso no es 5.3.

El TDD del caso G1 no espera a la baseline. El gate final
`tests/run.sh` sí: sin A6 el `test_golden_baseline.sh` queda rojo.

---

## B) El cambio mínimo en el hook

Después del `SESSION_KEY` y **antes** de `PROJECT_DIR` útil… hoy
`PROJECT_DIR` se define en `:204` *antes* de `SESSION_ID`. El HOST
no depende del payload: se puede resolver junto a `HOOK_DIR`,
arriba, sin esperar a los lectores JSON.

```bash
# Task 5.3: A4-cross-host. Mismo $0 (p.ej. ~/.claude/hooks/… registrado
# desde zcode como cbm) no debe compartir PROJECT_DIR con Claude.
# Senal medida (Task 5.1): ZCODE_SESSION_ID / ZCODE_PROJECT_DIR las
# inyecta zcode; CLAUDECODE=1 lo inyecta Claude/glm. ZCODE_* gana.
# unknown => other, NUNCA claude: colapsar a claude reabre el defecto
# cuando la senal falta (Core Rule 2).
if [ -n "${ZCODE_SESSION_ID:-}${ZCODE_PROJECT_DIR:-}" ]; then
  HOST=zcode
elif [ "${CLAUDECODE:-}" = "1" ]; then
  HOST=claude
else
  HOST=other
fi
```

Y:

```
PROJECT_DIR="$STATE_ROOT/$HOST/$PROJECT_KEY"
```

Un comentario de **una** línea en `RN_PENDING_PATH`: ahora hereda
HOST vía `PROJECT_DIR`; no volver a colgarlo de un path sin HOST.

No tocar `PROFILE_DIR`. No tocar `TARGET`. No tocar `emit_*`.

`bash -n` sobre el hook. El marcador `# SAIKIT-CLAUDE-OWNED` no se
mueve (línea 2).

---

## C) STOP vivo — solo si 5.2 dejó el gate en pie

No es el TDD. Es la cláusula "medido antes y después" de la DoD,
estilo 2.4.

**No registrar el harness en el user-config de zcode si 5.4 no
existe todavía** — 5.2 dijo que no se cablea producción acá, y
mezclar harness + probe ensucia la medición de 5.2.

Opciones, en este orden:

1. Si 5.2 **aún no** cerró: el STOP se aplaza. Plans.md 5.3 puede
   quedar en TODO hasta tener A0+TDD+spec, y el renglón **declara**
   "medición viva pendiente de 5.4" **solo si** el operador lo pide.
   La DoD pide la medición viva: el default es **hacerla** cuando
   5.2 cerró, en el descartable, **sin** dejar el harness
   registrado (append / un turno / `find` / `--quitar` en el mismo
   rato).
2. Si 5.2 cerró "gate no decorativo": GLM registra **temporalmente**
   **el mismo** hook actualizado en los dos hosts (hallazgo 6). No
   "fuente en zcode y vivo en Claude": eso cambia `$0` y
   `STATE_ROOT`, y el `find` mostraría aislamiento por directorio
   distinto sin haber llaveado HOST. Opciones válidas: (a) install
   al vivo (`~/.claude/hooks/summonaikit-harness.sh`) y los dos
   hosts apuntan a **ese** path; (b) los dos apuntan a la fuente
   del repo. Nunca mixto.
   Marker `--saikit-harness-id 5.3` en el user-config de zcode
   (UPS + Stop, `--only-cwd` del descartable, backup en
   `saikit-backups/`, `type: command`, bash.exe Windows). Claude
   ya corre el vivo. Un turno `-saikit` en **zcode** y uno en
   **Claude Code** sobre `C:\dev\saikit-captura-zcode`.
   **Oráculo (r1.3 + r2.4):** `find` de `harness-state.env`
   **después del UPS** (el armado), **antes** del Stop. El cierre
   limpio (`:1196`) y el presupuesto (`:1205`) borran el `.env`.
   **No** buscar `review-notice-pending.log` post-UPS: un UPS
   normal no lo crea, y si existía `rn_take_pending` lo consume
   (`:735`). RN se afirma en el lab (A2). Opcional en vivo:
   plantar el archivo a mano bajo `state/claude/<key>/` *antes*
   del UPS de zcode y afirmar que sigue. Las dos rutas
   `harness-state.env` deben ser `…/state/zcode/…` y
   `…/state/claude/…` bajo el **mismo** `HOOK_DIR/state`.
   `--quitar` id 5.3. Tokentracker intacto.

Tarjeta (solo si se hace 2):

```
STOP — Gon, no GLM.

1. Cerrá zcode y Claude sobre C:\dev\saikit-captura-zcode.
2. GLM te dice cuándo el harness quedó registrado (id 5.3)
   y que los DOS hosts apuntan al MISMO archivo.
3. Un turno -saikit en zcode (NO glm) en ese repo.
   Delegar no hace falta. PARÁ cuando arme (después del
   primer prompt), avisá a GLM, y recien ahí dejá que cierre.
   El estado se mira entre el UPS y el Stop: si cierra
   limpio, el archivo ya no está.
4. Lo mismo en Claude Code, mismo repo: armar, avisar, cerrar.
5. No borres ~/.claude/hooks/state.
```

Si el operador no puede ahora: el commit del hook+tests queda.
`Plans.md:99` se queda en **`cc:TODO`**. No se marca `cc:完了`
con un "aplazado a 5.4" (hallazgo 4: eso es reescribir la DoD
en silencio). El lab no sustituye la medición viva.

---

## D) Entregables

### D1. `docs/task-5.3-aislamiento.md`

A0 (qué se compartía **antes**), el mecanismo (llaveado, por qué no
copia), las dos rutas-tipo (`state/claude/…` vs `state/zcode/…`),
A6 declarado (tmp = unknown, no se agranda), RN_PENDING se mueve
con HOST. Cero crudos, cero prompts, cero rutas de perfil.

### D2. Spec § El segundo host

Bloque "Medido 2026-08-1X, Task 5.3": mecanismo, señal `ZCODE_*`,
A6 en zcode = fail-open por tmp. Sin diario.

### D3. `Plans.md:99`

`cc:完了 [<sha>]` **solo si** A0 está escrito, el caso G1 está
verde, la mutación lo atrapa, **y** la medición viva del §C
existe (dos `harness-state.env` bajo el mismo `HOOK_DIR/state`,
segmentos `claude/` y `zcode/`, inspeccionados post-UPS). Si falta
la medición viva: **`cc:TODO`**. SHA de este repo (convención 4.1).

---

## E) Commits

1. `test(5.3): dos hosts mismo $0 no deben compartir estado` —
   caso + lab + mutación, **rojo** (o el caso existe y el hook
   todavía falla; si se commitea rojo, el commit 2 es el verde en
  seguida; preferible un solo commit feat si el rojo se midió y no
   se dejó en `master`).
2. `feat(5.3): STATE_ROOT llavea por host (claude/zcode/other)` —
   hook + lab + mutación + `golden-harness` unset/`normalizar` +
   baseline regrabada (diff de rutas, veredicto igual).
3. **STOP** vivo si 5.2 lo permite.
4. `docs(5.3): aislamiento cross-host y A6 en zcode`.
5. `docs(5.3): cerrar Task 5.3 en Plans.md`.

Candados: TDD en `test_gate_behavior.sh`; `--files` de lo tocado;
gate final del feat: `pre-commit run --all-files` + `tests/run.sh`.
Nunca `--no-verify`.

---

## F) Qué le queda a 5.4 (no se hace acá)

- Append del harness al user-config (3 fases, sin matcher en UPS/Stop,
  matcher `Bash|Edit|Write|Read|Task` en PostToolUse — el alias
  funciona, 5.1).
- `install-hook.sh` / `check-hook-registration.sh` aprenden la forma
  `hooks.events.*`.
- Si el comando de zcode apunta al harness bajo `~/.claude/hooks/`,
  eso **está bien** (el llaveado lo cubre). Si apunta a otro path,
  HOST sigue saliendo del env, no del path.
- `TARGET=zcode` solo si 5.2 lo pidió.
- Reportar fuerte un registro con matcher que no cubre `Agent`/`Task`.

## Límites

1. No se toca el contrato de salida.
2. No se registra el harness en producción (salvo el STOP temporal
   del §C, y se quita).
3. No se agranda A6.
4. No se migra el árbol de estado viejo.
5. No se setea `TARGET` por `ZCODE_*`.
6. El gate sigue **advisory**.
7. `glm` ≠ `zcode`.
8. Workspace override sigue muerto.

## Cross-review del PLAN

**2 rondas hechas. No hay 3ª.** Este texto se le puede pasar a GLM
cuando 5.2 cierre (Depends).

Residual declarado (no se re-revisa): `lab_sembrar` de los casos
*viejos* sigue escribiendo bajo `state/other/…` porque no setean
`LAB_CLAUDECODE` — eso es correcto y no se migra. Si algún caso
viejo hardcodea la profundidad `state/$key/$sid` (sin HOST), se
arregla en esta task y se declara en el cierre. El residual de r1
("la baseline no lista rutas") **era falso**; quedó como hallazgo
r2.1 y el arreglo está en el cuerpo.
