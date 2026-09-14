# 21.2 — Consumo de roles delegados de Codex (canal nativo)

Fila `[Conditional]` `[lane:gate]` `[tdd:required]`, activada por la
re-corrida de 21.1 (señal estable `SubagentStart`/`SubagentStop` con
`agent_id`). Condicional de 21.1: **ACTIVADA**.

## Identidad de ESTA evidencia

| Campo | Valor |
|---|---|
| Fecha | 2026-09-13 |
| Base | `origin/master` = `30b3418` (merge de PR #317, CI 15/15 verde en el head `57018f0`) |
| Payload observado | fixtures de la re-corrida 21.1 (`docs/evidence/phase-21/21.1/`, corrida A: 10–24; sonda de fallo: 25–32-FALLO) |
| Host bajo cambio | SOLO `HOST=codex` (`SUMMONAIKIT_HOOK_TARGET=codex`); los demás hosts intactos |
| Batería | roja contra la fuente base (`git show origin/master:hooks/…`, `/tmp/hook-base-21.2.sh`), verde contra la fuente parcheada; logs a archivo completo en este dir |

## Qué implementó el gate

En `hooks/summonaikit-harness.sh`, la zona de registro de roles (`record_tool_evidence`)
ramifica para codex:

- **SubagentStart** con `agent_id` + `agent_type` de primer nivel: registra el
  agente como EN CURSO (`codex_children` en el estado). NO acredita rol.
- **SubagentStop** del MISMO `agent_id` (alta previa obligatoria, replay
  ignorado, `agent_transcript_path` exigido): marca cierre
  (`codex_children_done`) y acredita el rol en `agents_seen` al cierre.
- **Internos y despacho** en una sesión con canal nativo activo: NO acreditan
  (corren en fase running). Postura declarada en Plans 21.2: sin
  `SubagentStop` = running = no acreditado.
- **Fallback legado (6.1)**: en una sesión SIN señal nativa (hooks.json del
  host sin `SubagentStart`/`SubagentStop` registrados), el crédito histórico
  por `agent_type` de eventos internos sigue vivo — un deploy codex viejo no
  pierde la ceremonia. Pin: `caso_g3_codex_legacy_interno_acredita`.
- El cierre NO emite veredicto de éxito (R2): `verified` no lo toca; la
  evidencia de verificación sigue viniendo del carril de evento o del label
  en los hosts que corresponden. `VERIFIED BY SUBAGENT` conserva su contrato
  zcode.
- Ni `task_name`, ni prompt, ni prosa, ni ruta acreditan (R1/21.1): el rol
  viaja en el `agent_type` del PROPIO evento nativo.

Estado nuevo: `codex_children` (ids en curso) y `codex_children_done`
(cerrados), preservados por `write_state` con el patrón grep-keep de
`linked_children` (20.13). Ausentes sin eventos nativos: la forma del estado
de los demás turnos no cambia.

## Negativos y mutantes

| Caso | Afirma |
|---|---|
| `caso_g3_codex_nativo_cierre_acredita` | positivo con el payload observado: Start+Stop del mismo `agent_id` acreditan al cierre, no antes |
| `caso_g3_codex_en_curso_no_acredita` | Start sin Stop: running no acredita |
| `caso_g3_codex_interno_no_acredita` | interno de otro subagente en sesión nativa-activa: no acredita |
| `caso_g3_codex_stop_huerfano_no_acredita` | Stop sin Start previo: no acredita (R1: el despacho no da identidad) |
| `caso_g3_codex_stop_replay_no_duplica` | segundo Stop: idempotente |
| `caso_g3_codex_stop_otro_rol` | un implementer que cierra acredita implementer, nunca verifier (no se equipara todo worker) |
| `caso_g3_codex_stop_sin_transcript_no_acredita` | Stop sin `agent_transcript_path` (forma no observada): no acredita |
| `caso_g3_codex_stop_no_emite_veredicto` | el cierre deja `verified` en 0 (R2) |
| `caso_g3_codex_nativo_ceremonia_cierra` | ceremonia completa por cierres + carril de evento: cierra limpio |
| `caso_g3_codex_legacy_interno_acredita` | sin señal nativa: el crédito legado sigue vivo |

Mutantes (battery `test_gate_mutations.sh`, catálogo G3): `codex_interno_credita`,
`codex_cierre_sin_start`, `codex_cierre_sin_transcript` — los tres matados por
sus casos (log `mutantes-casos.log`).

## Residuales

- **R1** (despacho sin identidad): el gate NO exige correlación con el
  despacho — la acreditan el bracket nativo Start→Stop del propio agente.
- **R2** (sin estado máquina en el Stop): el cierre acredita rol+cierre+
  transcript, jamás éxito/fallo del trabajo.
- **R3** (fallo duro sin Stop): agente matado queda running = no acreditado;
  la escotilla `ROLE FALLBACK` sigue disponible.
- Despliegue: el canal nativo exige que el `hooks.json` de codex registre
  `SubagentStart` y `SubagentStop`. Sin ellos, la sesión cae al fallback
  legado (comportamiento pre-21.2). Requiere re-deploy del hook
  (`install-hook.sh`); el vivo se actualiza con el merge.
