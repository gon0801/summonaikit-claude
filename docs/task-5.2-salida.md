# Task 5.2 — Contrato de SALIDA de zcode: veredictos y decisión TARGET

`[Test]` `[lane:gate]`. Medido el **2026-08-12** en zcode (CLI `zcode-app-cli`
3.7.5-11), sesiones nuevas sobre el repo descartable, con
`tools/probe-zcode-output.sh` registrado en el user-config
(`~/.zcode/cli/config.json`) en `UserPromptSubmit` + `Stop`. Un modo por turno,
operador adelante; GLM lee el side-channel `probe-ran/<nonce>.ok` y el model-io
de la sesión.

**DoD cumplida:** las 4 formas de stdout + `exit 2` en Stop tienen veredicto
MEDIDO (aceptada / rechazada / ignorada); el rechazo se distingue del silencio
por el side-channel y el model-io; y la decisión `TARGET=claude` vs
`TARGET=zcode` queda declarada con su evidencia. **Cero payloads crudos, cero
prompts, cero rutas de perfil** del operador en este documento.

## Cómo se leyó cada señal

1. **¿Corrió?** `<dest>/probe-ran/<nonce>.ok`. Sin ese archivo ⇒ `unknown`. El
   log diario de zcode **no** es oráculo de "corrió": un hook OK no deja
   stdout/stderr ahí (medido en 5.1, `hook.run.completed` sin salida).
2. **Inyección (UPS):** el nonce `PROBE-<mode>-<nonce>` se busca en el
   `~/.zcode/cli/rollout/model-io-sess_*.jsonl` de la sesión del operador (el
   request que se le manda al modelo). Hallado dentro de un mensaje
   `{"role":"system",...}` ⇒ `accepted`.
3. **Bloqueo (Stop):** el conteo de `.ok` con `event=Stop`. El control `empty`
   dispara **1 Stop** por turno; un modo que bloquea dispara **varios** (zcode
   vuelve a llamar al modelo). Timestamps separados por segundos descartan
   "reintento interno" (sub-segundo) y confirman pasadas del modelo.

## Tabla de veredictos

| # | forma (fuente en el hook) | evento | stdout | exit | Señal medida | Veredicto |
|---|---|---|---|---|---|---|
| 1 | `empty` (control; `emit_allow` no-cursor no imprime) | ambos | — | 0 | 1 Stop/turno | **control** (sin señal) |
| 2 | `exit 2` pelado | Stop | — | 2 | 4 Stops, gaps 4-7 s | ✅ **aceptada** (bloquea / pide continuación) |
| 3 | `decision:block` (`emit_gate_failure :990`) | Stop | `{"decision":"block","reason":…}` | 0 | 4 Stops, gaps 3-4 s | ✅ **aceptada** (bloquea vía JSON) |
| 4 | `continue:false`+`stopReason` (`emit_budget_exhausted :1012`) | Stop | `{"continue":false,"stopReason":…}` | 0 | 1 Stop (= empty) | ⚪ **ignorada** (indistinguible del control) |
| 5 | `hookSpecificOutput.additionalContext` (`inject_contract :762`) | UPS | `{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":…}}` | 0 | nonce en el request del modelo | ✅ **aceptada** (inyectada como system msg) |
| 6 | forma 1 + clave extra `"saikitProbe":true` | UPS | forma 1 + `"saikitProbe":true` | 0 | nonce en el request **pese a** la clave extra | ✅ **aceptada** ⇒ **esquema NO estricto** |
| 7 | `systemMessage` (aviso RN `:1193`) | Stop | `{"systemMessage":…}` | 0 | 1 Stop, nonce ausente, no visible | ⚪ **ignorada** (no se muestra; RN fail-open) |

Cita de log **redactada** (inyección, formas 5 y 6): el nonce aparece en el
request del modelo dentro de
`{"role":"system","content":"UserPromptSubmit hook additional context: \n#1\nPROBE-CONTEXT-<nonce>"}`.
Para `extra`, idéntico con `PROBE-EXTRA-<nonce>` pese a la clave añadida. Para
bloqueo (formas 2 y 3), la señal es el conteo de `.ok` `event=Stop` (4, separados
por segundos) contra el control (1).

## Decisión: `TARGET=claude` alcanza

- Forma 1 **aceptada** (el contrato se inyecta al modelo) **Y** tanto
  `decision:block` como `exit 2` mueven el Stop (las dos mitades del bloqueo del
  vivo operan).
- El hook vivo (`emit_gate_failure` = JSON `decision:block` + `exit 2` + stderr)
  funciona en zcode tal cual: la inyección del contrato llega al modelo y el
  bloqueo fuerza pasadas de revisión (4, luego zcode corta con un tope interno).
- `budget` y `notice` ignoradas son **inocuas**: el presupuesto-agotado se
  apoya en `exit 2` (que sí bloquea), y el aviso RN es cortesía fail-open.
- 5.3–5.5 son **adaptación del hook existente, no un port** (coincide con 5.1).

## Premisa tumbada (corregida en el spec, F2)

- **Esquema estricto:** el spec § "El segundo host" afirmaba que una clave extra
  invalida la salida entera. `extra` lo **desmiente**: la clave `saikitProbe:true`
  NO invalidó la salida y el `additionalContext` se inyectó igual. El esquema de
  3.7.5-11 **tolera claves extra** (coincide con la doc oficial zcode.z.ai, no
  con la guía `diagnosing-hooks`).
- **`exit 2` en Stop:** la guía vieja decía que Stop "pide continuación" (no
  bloquea). La medición muestra que **sí bloquea** (4 pasadas). Es la medición
  que más pesaba y salió a favor del gate.

## Datos nuevos para 5.3–5.5

- `budget` (`continue:false`) es **ignorado**: el corte por presupuesto no se
  puede expresar con esa forma sola en zcode — el vivo ya suma `exit 2`, que sí
  bloquea, así que no hace falta cambiarlo. Lo declara 5.4.
- El `additionalContext` viaja como **mensaje `system`** (no `user`) con prefijo
  `UserPromptSubmit hook additional context:` y numeración `#1`. Inofensivo para
  el hook (lee el payload, no el contexto inyectado); registrado para 5.5.
- El esquema **no** estricto significa que las 4 formas del vivo no van a ser
  tumbadas por una clave de más — robustez que el spec no asumía.

## Cómo se midió / fuente

- Probe: `tools/probe-zcode-output.sh` (commits `feat(5.2)` `3343fb6` +
  `fix(5.2)` `29ef5f4`), 2 entradas (UPS+Stop, `type:command`) en el user-config
  con backup en `saikit-backups/`. Limpieza: `--quitar` (verificado: 0 entradas
  5.2, vecinos intactos).
- Sesión del operador: zcode 3.7.5-11 sobre repo descartable, un modo por turno.
- Oráculo "corrió": `probe-ran/<nonce>.ok`. Oráculo de inyección:
  `~/.zcode/cli/rollout/model-io-sess_*.jsonl` (request al modelo). Oráculo de
  bloqueo: conteo de `.ok` `event=Stop` + timestamps.
- Defecto propio corregido en el camino: la extracción del evento con `sed`
  greedy rompía en UTF-8 multibyte del `responseText` de zcode (C.UTF-8 + GNU sed
  4.9, `[^\"]*` cruzaba comillas); fix con `grep -o` + test de regresión.
