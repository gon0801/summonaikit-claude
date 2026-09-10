# Mediciones 20.9–20.11 — bloqueadas (2026-09-09)

Estado: **ninguna fila PASS**. 20.9 = `unknown` (cuota Claude). 20.10 y 20.11
no se ejecutaron (dependencia / mismo bloqueo de host).

## Preflight (antes de mutar)

| Chequeo | Resultado |
|---|---|
| 20.8 | `cc:完了` (PR #275) |
| Deps 20.10 (20.2, 20.3, 20.5, 20.8) | `cc:完了` |
| Autorización §8 / ledger 事前確認 | vigente (2026-09-09, expira al cerrar 20.26) |
| `git rev-parse HEAD` == `origin/master` | `e630aca86fe58d494d5b1264fff45ad851ef2dc7` (re-fijado; runbook tenía `f4a8dbe`) |
| Árbol limpio | sí |
| Hook fuente + copia claude | `sha256 d83947668d004b447ef64922b74f208ae649eb5c200c999a5ac6afcf28b34d42`, 4260 líneas; `install-hook.sh --check` = al-día en claude/grok/dsh/codex |
| Destino | `gon0801/saikit-descartable`; topic `saikit-descartable`; marcador `SAIKIT-ORIGEN.md` Phase 18 |
| Presupuesto gh | core remaining 4965→4964 (≤60/medición); PRs en descartable = 7 (≤15 fase) |
| Versiones | claude **2.1.267** (runbook 2.1.266), gh 2.98.0, git 2.55.0, node v26.8.1 |

Artefactos crudos: `docs/evidence-20.9-blocked-2026-09-09/`.

## 20.9 PreToolUse vivo (Claude) — `unknown`

### Nivel 1 — registro (ya observado; reconfirmado)

`~/.claude/settings.json` tiene `PreToolUse` / matcher `Bash` apuntando al hook
de perfil (`SUMMONAIKIT_HOOK_TARGET=claude` → `$HOME/.claude/hooks/…`).
Snapshot: `pretooluse-registration.json`. **No se reinstaló** el hook.

### Nivel 2 — bytes del hook instalado (piped; no es deny del host)

Contra la copia viva `~/.claude/hooks/summonaikit-harness.sh` en cwd del clone
de observación `/tmp/saikit-20.9-preflight-*/repo`:

- Deny: `gh pr merge 4 --squash` → stdout
  `permissionDecision":"deny"` /
  `merge denied: use tools/saikit-merge.sh (not gh pr merge)` (`hook-piped-deny.out`).
- Allow: `bash tools/saikit-merge.sh --help` con `MANIFEST.sha256` coincidente
  (`11c97d7a…`) → stdout vacío rc0; el comando `--help` sí corrió después
  (`hook-piped-allow.out` vacío = allow Claude).

Esto acredita emisión del JSON en la copia desplegada. **No** acredita que
Claude Code invocara PreToolUse ni que el host negara la herramienta
(residual Phase 20: registro ≠ invocación ≠ deny ejecutado).

### Nivel 3 — deny ejecutado por el host — NO observado

Intento controlado (cwd = clone del descartable, sin `--bare`):

```text
claude -p --permission-mode bypassPermissions --allowedTools Bash \
  "… Run EXACTLY one Bash …: gh pr merge 4 --squash …"
```

Salida literal (`claude-deny-stdout.txt`):

```text
You've hit your weekly limit · resets 10pm (America/Vancouver)
```

Duración 3 s. Sin transcript de tool. Sin evento PreToolUse del host.
`main` del descartable intacto antes/después:
`48aee6f74eaa647d2c75061ca7b727a183259e14`. PR #4 sigue OPEN.

**Veredicto 20.9:** `unknown` — cuota semanal de Claude Code. La fila
permanece `cc:TODO`. FAIL/unknown no cierran.

## 20.10 Autopilot completo (Claude) — no ejecutado

Depende de 20.9. Mismo host Claude sin cuota. No se abrió recorrido
sentinel→LISTO→sí→`saikit-merge.sh`→postmerge. No se sustituyó con merge
manual. Fila `cc:TODO`.

## 20.11 cuidar-pr vivo — no ejecutado

Requiere turno vivo Claude (revisar / solo-hilos / cuidar). Bloqueado por la
misma cuota. Fila `cc:TODO`.

## Qué falta para reabrir

1. Cuota Claude Code disponible (reset declarado 22:00 America/Vancouver).
2. Re-verificar checkout/hook SHA (`HEAD` == `origin/master`, árbol limpio).
3. Re-verificar topic+marcador antes de cualquier mutación remota.
4. Medir 20.9 nivel 3 (deny host + allow que llega al tool + HEAD remoto
   intacto en el deny), luego 20.10, luego 20.11.
