# 20.12 — Canal verificable Grok padre-hijo

Medición viva (spike). No transfer de sellos. No mutación remota.

## Identidad

| Campo | Valor |
|---|---|
| Fecha | 2026-09-09 (PDT) / 2026-09-10Z |
| Checkout kit | `71d31eb6e93c43aecf951005bcf1255cb7b078ab` (`HEAD` == `origin/master`, árbol limpio) |
| Hook fuente / vivo grok | sha256 `d83947668d004b447ef64922b74f208ae649eb5c200c999a5ac6afcf28b34d42` (4260 líneas; `install-hook.sh --check` al día en las 4 copias) |
| Grok | `1.0.24 (68e414c661e3) [stable]` |
| Dependencia 20.8 | Cumplida (PR #275). Autorización §8 vigente. Esta fila no usa el descartable remoto. |
| Laboratorio | HOME aislado bajo `/tmp/saikit-2012-*` (copia de perfil; gate de la copia sustituido por allow mudo). Perfil vivo `~/.grok` no escrito (`trusted_folders.toml` vivo vacío, cksum intacto). |
| Captura | `tools/capture-payloads.sh --host grok` en repo descartable local + trust TOML válido en la copia |

Re-verificación al medir (obligatoria por runbook 20.8):

```text
checkout_kit=71d31eb6e93c43aecf951005bcf1255cb7b078ab
hook_source_sha256=d83947668d004b447ef64922b74f208ae649eb5c200c999a5ac6afcf28b34d42
hook_vivo_grok_sha256=d83947668d004b447ef64922b74f208ae649eb5c200c999a5ac6afcf28b34d42
```

## Pregunta

¿El host emite una relación padre↔hijo usable como autoridad, distinta de mtime / ruta / task_hash, y discriminable con dos padres concurrentes?

## Matriz de canales (Grok 1.0.24)

| Canal | Quién lo ve | Señal de vínculo | ¿Autoridad? |
|---|---|---|---|
| `PostToolUse` write del hijo | sesión hija | `sessionId` = hijo; `subagentType`; **sin** `parent*` | No (atribuye rol, no padre) |
| env del hook del hijo | proceso hijo | `GROK_SESSION_ID` = hijo; sin padre | No |
| `SubagentStart` | sesión **padre** | `sessionId` = padre; `subagentId` = hijo; `subagentType`; `description` | **Sí** (anuncio host padre→hijo) |
| `PostToolUse` `spawn_subagent` | sesión **padre** | `toolResult.subagent_id` = hijo (= sessionId del write hijo) | **Sí** (mismo id host) |
| `Stop.backgroundTasks[].id` | padre (async) | id hijo en vuelo (precedente 18.27; esta corrida usó `background=false`) | Sí cuando hay async |
| Auto-wake UPS | padre | texto / `promptId` con id hijo (precedente 18.27; no observado en sync) | Sí cuando hay wake |
| `meta.json` bajo `sessions/<padre>/subagents/<hijo>/` | disco host | `parent_session_id` + `child_session_id` | Evidencia auxiliar; **no** se usa la ruta como autoridad |
| mtime / ruta de estado / `task_hash` | — | — | **Rechazados** (DoD + 18.26) |

## Dos padres concurrentes (PASS)

Misma cwd, dos `grok -p --always-approve` en paralelo, leader sockets distintos, nonces `A…X2` / `B…Y2`.

| Padre `sessionId` | Hijo anunciado (`SubagentStart.subagentId` = `toolResult.subagent_id`) | Marker escrito por el hijo |
|---|---|---|
| `01a088e9-e785-7162-9bc9-6c976112d92e` | `01a088e9-ffc1-7142-87bd-b3e26c741dfb` | `MARKER=A1789003425X2` |
| `01a088e9-e721-7603-be57-c36de7066081` | `01a088ea-0016-7110-83bd-d95d3baeb314` | `MARKER=B1789003425Y2` |

Comprobación discriminante (script sobre capturas): cada write de hijo tiene **exactamente un** padre que anunció ese `subagentId`; los ids no se cruzan.

Payloads redactados en `payloads/`. Metas host en `meta/`. Resumen máquina en `matrix-summary.json`.

## Relación con 18.26

18.26 midió que el write del reviewer hijo trae `subagentType` y session hija, sin id de padre en ese payload. Sigue vigente.

20.12 añade el lado padre. El host **sí** emite el vínculo al padre (`SubagentStart.subagentId` / `spawn` `toolResult.subagent_id`), igual al `sessionId` del hijo que sella. Eso no transfería sellos en esta medición.

## Decisión técnica

**Habilita 20.13.**

Contrato propuesto (implementación en 20.13, no aquí):

1. Autoridad del vínculo = id de hijo emitido por el host en la sesión padre (`SubagentStart.subagentId` y/o `toolResult.subagent_id` de `spawn_subagent`).
2. El sello sigue naciendo en la sesión emisora (aislamiento 18.26).
3. El consumo en padre solo admite veredicto/blast de un `sessionId` hijo previamente anunciado a **esa** sesión padre, más mismas ejecución/repo/HEAD del contrato 20.13.
4. Prohibido atribuir por mtime, ruta o `task_hash`.
5. Negativos obligatorios: otro padre, otro reviewer, replay, SHA cambiado, archivo reescrito, vínculo ausente.

## Condicionales

| Fila | Estado tras esta decisión |
|---|---|
| 20.13 | **Activada** (canal positivo). Implementar con TDD + mutantes + PR gate. |
| 20.14 | Sigue condicionada a merge+deploy del líder de 20.13. No se mide aquí. |

## Qué no se hizo

- No se copió sello entre sesiones.
- No se mutó remoto ni el perfil vivo.
- No se cerró nada como `unknown`. el canal padre→hijo se observó.
