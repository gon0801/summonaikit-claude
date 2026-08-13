# Task 5.3 — Aislar el estado por host

`[Guardrail]` `[lane:gate]` `[tdd:required]`. Medido el **2026-08-12** en el lab
(banco de `tests/lib/hook_lab.sh`) sobre la fuente del repo, sin persona adelante.
El STOP vivo (§C del plan, medición 2.4-style sobre el mismo repo con los dos
hosts) queda **pendiente del operador**: requiere registrar el harness en el
user-config de zcode, y eso es alcance de la Task 5.4. Hasta que no exista, el
lab es la evidencia y `Plans.md` se queda en `cc:TODO` (no se reescribe la DoD).

## A0 — qué se compartía ANTES (medido, no supuesto)

El estado vive bajo `STATE_ROOT`, donde `STATE_ROOT="$(dirname $0)/state"`. Si el
harness se registra desde zcode apuntando al **mismo `$0`** que Claude
(`$HOME/.claude/hooks/summonaikit-harness.sh`, la forma `cbm-*` que el operador
ya usa), los dos hosts resuelven `STATE_ROOT` **idéntico**. Antes de esta task,
el path era:

```
STATE_ROOT/$PROJECT_KEY/$SESSION_KEY/harness-state.env
```

Re-medido en el lab: dos invocaciones del hook **actual** (HEAD pre-5.3), mismo
`$0`, mismo `PROJECT_ROOT`, **mismo `session_id`** — una como Claude
(`CLAUDECODE=1`), una como zcode (`ZCODE_SESSION_ID=sess_lab`) — escriben **el
mismo** `harness-state.env`. `RN_PENDING_PATH`
(`$PROJECT_DIR/review-notice-pending.log`) también se comparte, porque deriva de
`PROJECT_DIR` sin host. Es A4 (la sesión no aísla cuando la sesión es la misma)
en versión cross-host.

A4 ya separa por sesión; los `session_id` de Claude (UUID) y de zcode (`sess_…`)
no colisionan en la práctica. Pero **no se apostó el aislamiento a que nunca
coincidan**: el caso de esta task es "mismo `$0`, misma sesión" (dos hosts sobre
el mismo turno), que A4 no cubre. 5.3 **suma** host, no reemplaza la sesión.

## Mecanismo — llaveado explícito por host (no copia)

Dos opciones nombraba la DoD: copiar el binario bajo `~/.zcode/hooks/` (que el
`dirname $0` ya separa) o llavear `STATE_ROOT` por host. **Se elige llaveado
explícito.** Razones, en orden:

1. El caso que la DoD pide ("el que lo habría atrapado") solo es un rojo
   *nuevo* si dos invocaciones del **mismo** `$0` dejan de compartir. La copia ya
   está cubierta por 2.4 y no mueve el hook.
2. El patrón `cbm` —apuntar zcode a `$HOME/.claude/hooks/…`— es el que el
   operador **ya usa** y el que 5.4 va a querer copiar. Si 5.3 solo copiara el
   binario, un registro "como cbm" reabre el defecto en silencio.
3. Un solo archivo vivo (el de 2.2/4.1). No reintroducir un segundo dest que el
   heal tendría que sincronizar.
4. La señal `ZCODE_SESSION_ID` / `ZCODE_PROJECT_DIR` está **medida** (Task 5.1:
   las inyecta el host, no el comando registrado). No es fe.

Detección de host (espejo de la lógica del hook):

```
HOST = zcode    si $ZCODE_SESSION_ID o $ZCODE_PROJECT_DIR no vacío
     | claude   si no lo anterior y $CLAUDECODE = 1
     | other    en cualquier otro caso (cursor, lab, unknown)
```

`ZCODE_*` gana a `CLAUDECODE`. zcode setea `CLAUDE_SESSION_ID` /
`CLAUDE_PROJECT_DIR` pero **no** `CLAUDECODE` (5.1). `HOST=other` **nunca**
escribe en `claude` ni `zcode`: colapsar a `claude` reabre el defecto cuando la
señal falta (Core Rule 2). Cursor y el lab (que no exportan ninguna) caen en
`other`.

El path pasa a:

```
STATE_ROOT/$HOST/$PROJECT_KEY/$SESSION_KEY/harness-state.env
```

`RN_PENDING_PATH = $PROJECT_DIR/review-notice-pending.log` se **mueve con el
host** (hereda `HOST` vía `PROJECT_DIR`). Si se dejara en `STATE_ROOT/$PROJECT_KEY/…`
(sin host), un Stop de zcode podría tomar/borrar el aviso pendiente de Claude —
el defecto 2 que el caso G1 atrapa.

**No se migra** el árbol viejo `state/$PROJECT_KEY/$SESSION_KEY/`: queda huérfano,
el hook ya no lo lee. Migrar sería un rename a ciegas que reabriría A4.

## Las dos rutas-tipo (medido en el lab)

| Host | Señal | Ruta de `harness-state.env` |
|---|---|---|
| Claude | `CLAUDECODE=1` | `state/claude/<PROJECT_KEY>/<SESSION>/harness-state.env` |
| zcode | `ZCODE_SESSION_ID` (o `ZCODE_PROJECT_DIR`) | `state/zcode/<PROJECT_KEY>/<SESSION>/harness-state.env` |
| otro (cursor, lab) | ninguna | `state/other/<PROJECT_KEY>/<SESSION>/harness-state.env` |

El caso G1 (`caso_g1_dos_hosts_mismo_repo_no_comparten_estado`) arma A (Claude) y
B (zcode) sobre el mismo `$0` y la misma sesión, siembra el aviso RN de A, y
afirma las **dos** mitades: B no ve el estado de A (rutas distintas) **y** el
estado + el aviso de A sobreviven al armado de B. Contra el hook pre-5.3, A y B
colapsan al mismo path y B se come el aviso de A (rojo medido antes del arreglo).

## A6 en zcode — se declara, no se agranda

`PROFILE_DIR="$(cd "$HOOK_DIR/.." && pwd)"`. Con el harness en `~/.claude/hooks`,
el `transcript_path` de zcode es un **temp efímero**
(`%TEMP%/zcode-claude-hook-<rand>/…`) que zcode borra al terminar el hook; está
**fuera** del perfil. La contención de A6 (Task 3.6) lo rechaza: fail-open,
`transcript=unknown` por stderr, el gate corre con `last_assistant_message`
(presente en Stop, medido 5.1). Es el mismo desenlace que el staging de 2.4.

**No** se añade `%TEMP%/zcode-claude-hook-*` a la allowlist de A6: sería una
primitiva de lectura nueva, controlada por el payload, en un tmp que cualquier
proceso puede plantar. Fuera de esta task. El caso existente
`caso_g4_transcript_fuera_de_perfil_se_ignora` ya cubre "fuera del perfil"; el
tmp de zcode es otra forma de "fuera", no un caso nuevo.

## Tests

- **Caso G1 (el catch):** `caso_g1_dos_hosts_mismo_repo_no_comparten_estado` —
  dos hosts, mismo `$0`/sesión, dos mitades + RN. Atrapa el defecto.
- **Control de detección:** `caso_g1_host_segun_senal` — sin mutación propia;
  afirma que el segmento sale de la señal correcta (`claude` / `zcode` vía
  session-id / `zcode` vía project-dir / `other`). Sin el control de
  `ZCODE_PROJECT_DIR`-only, una implementación que leyera solo
  `ZCODE_SESSION_ID` pasaría la batería entera.
- **Mutación:** `mut_host_sin_llave` (revierte `PROJECT_DIR` a
  `STATE_ROOT/$PROJECT_KEY`, sin `HOST`) — acreditada al catch case.
- **Lab:** `lab_run` unsetea siempre `ZCODE_SESSION_ID` / `ZCODE_PROJECT_DIR`
  (junto a `CLAUDECODE`) y repone solo si el caso las pide. Determinismo: si la
  suite corre dentro de zcode, el lado "Claude" no hereda `ZCODE_*`.
- **Baseline dorada:** `tools/golden-harness.sh` unsetea `ZCODE_*` y su
  `normalizar` entiende `state/<host>/<key>/…`. Diff de la baseline = **solo el
  header** (sha/bytes/líneas); ningún veredicto se movió.

## Límites declarados

- No se toca el contrato de salida, `emit_*`, `TARGET` (5.2 / 5.4).
- No se registra el harness en producción (el STOP vivo del §C es alcance 5.4).
- No se agranda A6.
- No se migra el árbol de estado viejo.
- No se setea `TARGET=zcode` por `ZCODE_*` (eso lo cablea 5.4, si 5.2 lo pidiera;
  5.2 dijo `TARGET=claude` alcanza).
- El gate sigue **advisory**.
- `glm` ≠ `zcode` (`glm` ya está gateado: es Claude).
