# 20.9 — PreToolUse vivo en Claude (nivel 3: deny del host)

Medición viva del lead sobre el perfil real del operador. Repo de observación:
clone aislado del descartable en `/tmp/saikit-20.9-20260909-222732/repo`.
**No se reinstaló el hook** (niveles 1-2 ya acreditados en la corrida bloqueada
del 2026-09-09, `docs/smoke-20.9-20.11-blocked-2026-09-09.md`: registro en
`~/.claude/settings.json` + la copia desplegada emite deny/allow por pipe).

## Identidad

| Campo | Valor |
|---|---|
| Fecha | 2026-09-09 (PDT) |
| Checkout kit | `8e7402e8990cad8ec0ef54a6f1cab21cfccc4e29` (`HEAD` == `origin/master`, árbol limpio) |
| Hook fuente / vivo claude | sha256 `37e55640003afaff6d4a54cf6495afc73bec5799b86323fb7a317889fec78680` (4345 líneas; idénticos) |
| Claude Code | `2.1.267` (runbook §1 fijó `2.1.266`; drift declarada, misma que la corrida bloqueada) |
| gh / cuota | 2.98.0; core remaining 4987 al preflight |
| Destino | `gon0801/saikit-descartable` (topic + marcador re-verificados read-only) |

## Cadena observada (payload ↔ decisión ↔ ejecución, por `tool_use_id`)

| Paso | Evidencia | Resultado |
|---|---|---|
| Deny — payload host | `payloads/pretooluse-deny.json` | PreToolUse Bash `gh pr merge 4 --squash`, sesión `0510fea4-…`, `toolu_01B5Ar1n9nkyQctVspxWyRmw` |
| Deny — decisión | `runs/deny-run.json` → `permission_denials[0]` | **mismo `tool_use_id`**: el host negó ANTES de ejecutar; mensaje del hook llegó al turno (`merge denied: use tools/saikit-merge.sh (not gh pr merge)`) |
| Deny — no-ejecución | `runs/deny-run.json` + remotos | sin PostToolUse para ese `tool_use_id`; `main` = `6e095023…` antes/después; PR #4 sigue OPEN |
| Allow — payload host | `payloads/pretooluse-allow.json` | PreToolUse Bash `bash tools/saikit-merge.sh --help`, sesión `09b44b33-…`, `toolu_01BN9tNiRjJRM3odrVSbJ2uQ` |
| Allow — ejecución | `runs/allow-run.json` + `payloads/posttooluse-allow.json` | `permission_denials: []`; PostToolUse con el **mismo `tool_use_id`**; el turno vio la salida real del `--help` |

Comando de cada corrida (literal):

```text
claude -p --permission-mode bypassPermissions --allowedTools Bash --output-format json \
  "Run EXACTLY one Bash command and nothing else, then stop: <comando>"
```

El deny se produjo con `bypassPermissions`: la decisión vino del hook, no del
modo de permisos — es lo que la fila quería demostrar.

## Captura de payloads

`tools/capture-payloads.sh --instalar` sobre el **clone** (jamás el perfil) +
entrada PreToolUse/Bash agregada a mano al `.claude/settings.json` del clone
(el instalador no registra PreToolUse; mismo mecanismo, fail-open). Quitada con
`--quitar` al terminar (el `.claude/settings.json` del clone quedó eliminado,
verificado). Los `.env` capturados se revisaron: sin credenciales.

## Qué NO se hizo

- No se reinstaló ni se tocó el hook del perfil (`~/.claude`).
- No hubo mutación remota: el intento de merge fue negado antes de ejecutar;
  `main` y el PR #4 quedaron intactos (verificado por API después de la corrida).

## Residuales declarados

1. El perfil tiene un hook PreToolUse/Bash ajeno (`rtk hook claude`) registrado
   antes que el del kit; no interfirió (el deny llegó con el mensaje del kit).
2. Versión de Claude Code `2.1.267` ≠ pin del runbook (`2.1.266`): drift
   declarada, no se re-fijó el runbook (sección de versiones de preparación).
3. `main` del descartable ya estaba en `6e095023…` (merge de 20.14), no en el
   `48aee6f…` de la corrida bloqueada; la integridad se midió contra el valor
   vigente antes/después del intento.
4. Niveles 1-2 no se repitieron: se reutiliza la evidencia de la corrida
   bloqueada. Salvedad: esa corrida midió la copia `d8394766…` (4260 líneas) y
   desde entonces 20.13 rotó el hook a `37e55640…` (4345). El nivel 3 (esta
   evidencia) se midió contra la copia vigente `37e55640…`, que es la que el
   gate usa hoy; el nivel 1 (registro en settings) no depende del contenido
   del hook.

## Veredicto de la fila

Nivel 3 observado y correlacionado: deny del host antes de ejecutar + allow que
llega al tool + remotos intactos. DoD completa. Lista para cierre del lead.
