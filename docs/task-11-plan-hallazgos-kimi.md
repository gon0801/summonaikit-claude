# Phase 11 — Plan: hallazgos del run de campo con Kimi (2026-08-16)

Plan para ejecutar por un agente externo (GLM/zcode). El lead de esta sesión
(Claude) solo revisa; no implementa. Origen: un run real del harness bajo el
host Kimi devolvió 4 hallazgos; el análisis (sesión 2026-08-16, solo lectura)
clasificó 2 como accionables. Los otros 2 quedaron declarados como trade-offs
aceptados (interrupción de turno = costo del fix A4; sugerencia automática de
fast lane = contradice la decisión medida de la Task 10.1 de retirar la
inferencia de trivialidad).

Reglas de ejecución que aplican a TODO el plan:

- Cada task va en su PROPIA rama creada desde `origin/master` con `git fetch`
  previo (la 11.1 convierte esto en regla del harness; no la violes al
  implementarla).
- Batería completa UNA vez por task, en CI vía PR (`git push` + `gh pr create`).
  Localmente, red/green SOLO del archivo de test que tocas. No correr
  `tests/run.sh` completo en la máquina local.
- Pre-commit instalado: si un candado falla se arregla el problema, JAMÁS
  `--no-verify`.
- Cada task actualiza su fila en Plans.md (append de la Phase 11 en la
  primera task que aterrice; ver "Filas para Plans.md" abajo).
- `not_observed != absent`: lo que no puedas medir se declara `unknown`.

---

## Task 11.1 — Regla de higiene de base de rama

`[Guardrail]` `[lane:fast]` `[tdd:required]`. Depends: 10.9 (toca el mismo
heredoc de reglas permanentes que la 10.9 está extendiendo a otros hosts;
serializar para no chocar).

### Qué falló en el campo

Kimi creó la rama de una task desde el `master` LOCAL, que traía un commit
local no pusheado. Ese commit se coló al PR sin que nadie lo decidiera. Ni las
reglas permanentes ni el contrato dicen nada de higiene de base de rama, aunque
la instrucción de abrir PR vive exactamente ahí.

### Cambios (solo texto, dos puntos)

1. **`hooks/summonaikit-harness.sh` — `standing_rules()` (heredoc :1049-1056).**
   Agregar un bullet nuevo después del bullet de la batería/PR:

   ```
   - Create the task branch from origin/<default> (git fetch first), NEVER from your local default branch. Before opening the PR, verify `git log origin/<default>..HEAD` lists ONLY this task's commits; anything else means your base was dirty — rebase onto origin/<default> before the PR. Measured failure mode: a branch cut from a local master carried an unpushed local commit straight into the PR without anyone deciding it.
   ```

2. **`hooks/summonaikit-harness.sh` — `harness_context()`, spec del recibo,
   línea `Close:` (:999).** Extender con la misma verificación:

   ```
   ...; if you pushed a branch or opened a PR, state that git log origin/<default>..HEAD contains only this task's commits.
   ```

   (Conservar el contenido actual de la línea; esto se AGREGA.)

### Tests (TDD: rojo primero)

- Caso nuevo en `tests/lib/gate_cases.sh`, mismo patrón que
  `caso_g1_reglas_nombran_donde_correr_la_bateria` (Task 10.16):
  `caso_g1_reglas_exigen_base_de_rama_limpia` — un `SessionStart` sin sentinel
  con `TARGET=claude` emite reglas permanentes que contienen
  `git log origin/<default>..HEAD` y `NEVER from your local default branch`.
- Mutación nueva en `tests/test_gate_mutations.sh`: quitar el bullet nuevo del
  heredoc ⇒ el caso de arriba da rojo. Acreditar la mutación a SU caso en la
  declaración de la corrida, como hacen las 28 existentes.

### Verificación y cierre

- Red/green local SOLO de los archivos de test tocados.
- `tools/golden-harness.sh --check`: los escenarios que capturan `SessionStart`
  (Task 10.8) van a divergir porque el texto de las reglas cambió — regrabar
  SOLO esos escenarios, auditar el diff y declarar cero veredictos movidos en
  el resto (mismo procedimiento que la fila 10.17 documenta).
- `tools/install-hook.sh` para llevar el cambio al hook vivo (con backup, como
  en las tasks 3.x).
- Declarar en el cierre: `summonaikit-kimi` hereda este texto vía su extracción
  del hook instalado (`SAIKIT-CLAUDE-OWNED`, Task 4.2); su `check_drift.sh` va
  a reportar AVISO hasta el re-pin. El re-pin es parte de la Task 11.3, no de
  esta.

---

## Task 11.2 — Guardia `!recibo` en la escotilla PAUSED

`[Guardrail]` `[lane:gate]` `[tdd:required]`. Depends: -.

### Qué falló en el campo

Kimi terminó el trabajo, escribió el recibo completo y agregó la línea PAUSED
al final para preguntar si hacía deploy. Hoy la escotilla PAUSED
(`hooks/summonaikit-harness.sh:1786-1788`) dispara ANTES de evaluar el recibo y
sale con `emit_allow` SIN limpiar estado. Dos consecuencias:

- Un recibo completo + PAUSED se salta la validación y el cierre NO es limpio
  (estado queda en disco; lo borra recién el desarme del siguiente prompt).
- Un recibo ROTO + PAUSED cierra en silencio — exactamente la clase de bug ya
  arreglada para DELEGATED (ver el comentario largo en :1798-1810: la escotilla
  hermana exige `!recibo` desde la cross-review ciclo 1).

La corrección resuelve además la ambigüedad semántica que Kimi reportó
("pausado para poder trabajar" vs "terminado, esperando decisión") SIN sentinel
nuevo: los dos estados quedan distinguidos por recibo-ausente vs
recibo-presente.

### Cambios

1. **Gate** (`hooks/summonaikit-harness.sh:1786`): la escotilla PAUSED gana la
   misma segunda cláusula que DELEGATED (:1818-1819), usando la constante
   existente `RECEIPT_MARKER_RE` (:1721):

   ```sh
   if printf '%s' "$text_hatch" | grep -Eiq 'SUMMONAIKIT HARNESS PAUSED' \
      && ! printf '%s' "$text_hatch" | grep -Eiq "$RECEIPT_MARKER_RE"; then
     emit_allow
   fi
   ```

   Con recibo presente, el turno cae al gate normal: recibo completo ⇒ cierre
   limpio con estado borrado; recibo roto ⇒ feedback de etiquetas faltantes,
   como cualquier turno.

2. **Contrato** (`harness_context()`, bloque "Asking is not failing",
   :908-911): agregar una línea:

   ```
   - PAUSED is ONLY for when you cannot proceed yet. If the work is DONE and you are asking for a decision (deploy? merge?), write the full receipt and put your question after it — do NOT add the PAUSED line: the receipt closes the gate cleanly and your question stands on its own.
   ```

3. **Comentario del código**: actualizar el comentario de la escotilla PAUSED y
   la frase "Unlike PAUSED above" del comentario de DELEGATED (:1792), que deja
   de ser cierta en su mitad del recibo (sigue siendo cierta en la mitad del
   rol). Dejar la razón: datapoint de campo Kimi 2026-08-16.

### Tests (TDD: rojo primero)

Casos nuevos en `tests/lib/gate_cases.sh`:

- `caso_g4_recibo_completo_mas_paused_cierra_limpio` — recibo completo con las
  6 etiquetas + línea PAUSED al final ⇒ exit 0 Y estado borrado (la diferencia
  observable contra la escotilla vieja, que salía allow con estado vivo).
- `caso_g4_recibo_roto_mas_paused_sigue_exigiendo` — marcador
  `SUMMONAIKIT HARNESS RECEIPT` presente pero etiquetas faltantes + PAUSED ⇒
  exit 2 con los motivos del gate (hoy: allow silencioso).
- La pausa legítima (pregunta sin recibo) ya está cubierta por el escenario
  dorado `09-pausa-declarada` — NO debe moverse.

Mutaciones nuevas en `tests/test_gate_mutations.sh` (28 → 30):

- `paused_sin_guardia_de_recibo` (quitar la cláusula nueva) ⇒ atrapada por
  `caso_g4_recibo_roto_mas_paused_sigue_exigiendo`.
- `paused_exige_recibo` (invertir la cláusula: exigir recibo presente) ⇒
  atrapada por el caso existente de la pausa sin recibo (o uno propio si no lo
  hay con esa forma exacta).

### Verificación y cierre

- Red/green local SOLO de los archivos de test tocados.
- `tools/golden-harness.sh --check`: expectativa medida ANTES de declarar —
  `09-pausa-declarada` (pausa sin recibo) y `14-defecto-a2-pausa-en-resultado`
  (PAUSED solo dentro de un tool_result, que ya NO cuenta desde la 3.2) no
  deberían divergir. Si algún escenario diverge, auditar y declarar el diff
  como hizo la 3.2; si ninguno diverge, declarar que la baseline no cubre
  recibo+PAUSED y que esa cobertura queda en los casos G4 nuevos.
- `tools/install-hook.sh` (con backup).
- **Límite declarado** (heredado de la escotilla hermana, :1812-1817): el match
  del marcador sigue siendo subcadena sin anclar — una pausa legítima que CITE
  la frase "SUMMONAIKIT HARNESS RECEIPT" caerá al gate normal y puede bloquear.
  Mismo trade-off aceptado que DELEGATED; se declara, no se arregla.

---

## Task 11.3 — Espejo de 11.2 en `summonaikit-kimi`

`[Guardrail]` `[lane:gate]` `[tdd:required]`. Depends: 11.1, 11.2 (necesita el
hook vivo ya instalado con ambos textos para la extracción y el re-pin).
**El código vive en `C:\dev\summonaikit-kimi`** (precedente: Task 4.2 — acá
queda el plan y el puntero al commit de allá).

- El port reproduce la asimetría exacta: escotilla PAUSED en
  `hooks/summonaikit-harness-kimi.sh:1152` sin guardia, DELEGATED en :1156-1157
  CON guardia, `RECEIPT_MARKER_RE` en :312. Aplicar la misma cláusula
  `!recibo` que en 11.2.
- Tests espejo de los dos casos G4 en la suite de ese repo (usa su convención
  local de nombres).
- El texto de contrato (11.1 + 11.2) NO se edita a mano allá: correr su
  mecanismo de refresh/extracción contra el hook instalado y después su
  `check_drift.sh`; aceptar el DRIFT/AVISO con re-pin según el procedimiento
  documentado en ese repo.
- Batería de ese repo por su propio CI/PR si lo tiene; si no, la batería local
  de ese repo UNA vez al final.

---

## Filas para Plans.md (append, primera task que aterrice)

Insertar después de la tabla de Phase 10 (línea ~241, antes de
"## Clasificación del alcance"):

```markdown
## Phase 11 — Hallazgos del run de campo con Kimi (2026-08-16)

**Propósito:** un run real bajo el host Kimi devolvió 4 hallazgos; los 2
accionables se cierran acá (los otros 2 quedaron declarados como trade-offs
aceptados en `docs/task-11-plan-hallazgos-kimi.md`). Ejecuta GLM; revisa el
lead.

| Task | 内容 | DoD | Depends | Status |
|------|------|-----|---------|--------|
| 11.1 | `[Guardrail]` `[lane:fast]` `[tdd:required]` **Higiene de base de rama.** Kimi ramificó desde un master local con un commit no pusheado y el commit se coló al PR. Las reglas permanentes ganan el bullet "rama desde origin/<default> con fetch previo; antes del PR, `git log origin/<default>..HEAD` contiene SOLO los commits de esta task", y la línea Close del recibo pide declararlo. Detalle: `docs/task-11-plan-hallazgos-kimi.md` | Las reglas emitidas en SessionStart contienen la regla nueva (`caso_g1_reglas_exigen_base_de_rama_limpia`); 1 mutación nueva atrapada; escenarios SessionStart de la baseline regrabados con diff auditado y cero veredictos movidos en el resto; install corrido | 10.9 | cc:TODO |
| 11.2 | `[Guardrail]` `[lane:gate]` `[tdd:required]` **La escotilla PAUSED gana la guardia `!recibo` (paridad con DELEGATED).** Recibo completo + PAUSED hoy se salta la validación y no limpia estado; recibo ROTO + PAUSED cierra en silencio — la clase de bug ya arreglada en la escotilla hermana. Con la guardia, recibo presente cae al gate normal; el contrato aclara que PAUSED es solo para cuando NO se puede avanzar. Resuelve la ambigüedad reportada por Kimi sin sentinel nuevo. Detalle: `docs/task-11-plan-hallazgos-kimi.md` | `caso_g4_recibo_completo_mas_paused_cierra_limpio` (exit 0 + estado borrado) y `caso_g4_recibo_roto_mas_paused_sigue_exigiendo` (exit 2) en verde; 2 mutaciones nuevas atrapadas (28→30); escenario `09-pausa-declarada` sin moverse en `--check`; install corrido; límite de subcadena declarado | - | cc:TODO |
| 11.3 | `[Guardrail]` `[lane:gate]` `[tdd:required]` **Espejo de 11.2 en `summonaikit-kimi` + re-pin del drift.** El port reproduce la asimetría (`summonaikit-harness-kimi.sh:1152` sin guardia); misma cláusula, tests espejo, y el texto de contrato de 11.1/11.2 entra por su mecanismo de extracción (no a mano) con re-pin de `check_drift.sh`. El commit vive en ese repo; acá queda el puntero (precedente Task 4.2) | Los dos casos espejo en verde en la suite de ese repo; `check_drift.sh` exit 0 tras el re-pin; batería de ese repo corrida una vez; fila cerrada con el hash del commit de `summonaikit-kimi` | 11.1, 11.2 | cc:TODO |
```

## Qué NO se hace (declarado)

- Hallazgo 3 de Kimi (interrupciones): trade-off aceptado del fix A4 — se
  documenta, no se construye.
- Hallazgo 4 (sugerir fast lane): la inferencia de trivialidad se retiró a
  propósito en la 10.1; a lo sumo una línea opcional en Retro, fuera de este
  plan.
- Sentinel nuevo tipo "COMPLETE": rechazado — la guardia `!recibo` distingue
  los dos estados sin tocar el contrato de sentinels ni los parsers de los 4
  hosts.
- El datapoint "citar texto con `-saikit` arma el gate" (medido en esta misma
  sesión): queda anotado, sin task — la decisión vigente ("si lo escribiste, lo
  quieres") es deliberada y cambiarla pide su propia medición.
