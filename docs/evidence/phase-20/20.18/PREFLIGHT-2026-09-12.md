# 20.18 — Preflight 2026-09-12 (preflight ejecutable completo; medición diferida)

> Equivalente al `run-identity.txt` en prosa, con el detalle de cada gate y el
> motivo explícito del host impediment declarado.

## Resumen ejecutivo

La fila 20.18 (`Bloqueo dsh en UI web: Completar escenario 2 pendiente de 15.5,
conservando escenarios 1/3 como controles`) requiere **medición observacional
en UI web del host dsh** con captura literal. Todas las precondiciones
verificables desde el lado agente están satisfechas; la medición misma
queda **bloqueada por impediment de host**, declarado conforme a la propia
DoD de la fila ("falta de observación sigue abierta").

## 1. Identidad y presupuesto (verificado)

| Elemento | Estado | Notas |
|---|---|---|
| HEAD | `76e92bb7a757ae45f6faa5d242a0b3bcbbf2cba9` | clean |
| `HEAD == origin/master` | sí | `0` ahead / `0` behind |
| Árbol limpio | sí | `git status --porcelain` = 0, 0 stash, 0 untracked |
| Branch para trabajo | `work/20.18-20.19-preflight` | worktree `/Users/dn/dev/summonaikit-claude-wt-2018-19` |
| Hook real SHA | `37e55640003afaff6d4a54cf6495afc73bec5799b86323fb7a317889fec78680` | MATCH pin runbook §1 |
| Pin `e0f7a25` | alcanzable en log local | commit `e0f7a25 docs(plans): close 20.12 and 20.13 …` |
| Drift de pin (`e0f7a25` ← `76e92bb`) | declarado no-bloqueante | brief |
| Drift de hook real | declarado no-bloqueante | `docs/evidence/phase-20/20.20/run-identity.txt` cita `54ab7475…20 lineas shim pre-commit.com`; runbook §1 cita `37e55640/4345 lineas`. Brief autoriza drift declarado |
| Versión host 2.1.267 vs pin 2.1.266 | declarado no-bloqueante | brief |

## 2. §8 autorización y descartable (verificado vía gh API)

| Elemento | Estado |
|---|---|
| Repo destino | `gon0801/saikit-descartable` (default `main`) |
| Topic | `saikit-descartable` (verificado vía `/repos/{...}/topics`) |
| Marcador `SAIKIT-ORIGEN.md` | presente, `size=582`, `sha=ef1e4ce51bf98056a70019326271572d15bbbb90` |
| PRs del descartable | `11 / 15` phase budget (5 CLOSED, 6 MERGED, 0 OPEN) |
| §8 autorización | vigente — paquete §8 del runbook (`docs/phase20-mediciones-runbook.md §8`), aprobado "tal cual" por el operador el 2026-09-09, registrado en ledger 事前確認 (PR #279). Expira al cierre de 20.26; renueva D23 |
| gh auth | `gon0801` vía keyring, scopes: `gist, read:org, repo, workflow` |

**Conclusión de gates previos a mutación remota**: ✓ pasamos
todos los chequeos pre-mutación del runbook §2/§7/§8.
**Sin mutación remota se ha hecho y no se hará hasta que el host levante la medición.**

## 3. Triple check pre-mutación remota (procedimiento del runbook §2)

Conforme al runbook `docs/phase20-mediciones-runbook.md §2`, antes de cada
mutación remota se debe verificar topic + marcador contra `origin/<default>`
del descartable. Verificado aquí, read-only:

```
$ gh api repos/gon0801/saikit-descartable/topics
{"names":["saikit-descartable"]}

$ gh api repos/gon0801/saikit-descartable/contents/SAIKIT-ORIGEN.md
{"name":"SAIKIT-ORIGEN.md","path":"SAIKIT-ORIGEN.md",
 "sha":"ef1e4ce51bf98056a70019326271572d15bbbb90","size":582}
```

Divergencia con la última referencia del runbook (Phase 18 implementación
original, `ef1e4ce5…`/`582 bytes` — ver `docs/retro-phase-18.md:117`): **NO
hay divergencia**. Estado estable. Mutación remota: habilitada por marcador,
no ejercida porque la medición misma no se ha ejecutado (ver §4).

## 4. Estado de la medición (host impediment declarado)

La DoD de 20.18 exige:

> Sin recibo => adaptador bloquea/encola y host continúa en la MISMA sesión
> UI; no headless sustituto; captura literal y control sin sentinel;
> falta de observación sigue abierta.

Y referencia explícita al escenario 2 de la 15.5 (`Bloqueo sin recibo en
UI web, conservando 1/3 como controles`), declarado `unknown` en el cierre
de 15.5 (transcript `session.jsonl.zstd` 2026-08-28, leído por el lead;
"escenarios 1 y 3 ✅; el 2 (GATE por recibo ausente) NO se reprodujo.

UI web (2026-08-28 07:18, operador, leído por el lead del `session.jsonl.zstd`)"):
escenario 1 ✅ medido — contrato inyectado (el modelo lo dice literal en
su `reasoning`), `subagent_implementer` → `_verifier` → `_reviewer` →
`_adversary` (artefacto con esquema del contrato, 0 findings) → adjudicación →
recibo con `ADVERSARY:`; escenario 3 ✅ (turnos sin `-saikit` sin ningún
marcador); **escenario 2 (GATE en la UI) sigue `unknown`** — sin ningún
followup del adaptador en 28 turnos; cubierto por la suite del hook y el
banco del adaptador).

De aquí se sigue que:

- **Escenario 2 requiere UI web VIVA** operada por un host con dsh instalado
  y sesión Claude Code activa. Dicha sesión no existe actualmente en la Mac:
  ```
  $ pgrep -f claude | xargs -I{} lsof -p {} | awk '$4=="cwd"'
  /Users/dn/.claude/chrome            (chrome-native-host)
  /Users/dn                            (claude-mem MCP pids)
  /Users/dn/dev/goncloud-bridge-in-out (claude pid 34598)
  /Users/dn/dev/goncloud-Orbit          (claude pid 66171)
  ```
  Ningún proceso `claude` con cwd = `/Users/dn/dev/summonaikit-claude`.
- **Headless NO sustituye** según DoD 20.18 — y el brief lo reitera.
  El intento headless de 15.5 obtuvo `DELEGATED` (no fue el caso GATE exacto),
  por lo que la medición en headless es **explícitamente declarada como no
  atributable** por el row.
- **El adaptador / hook / cordis.patch.yml DE dsh está desplegado en la Mac**:
  ```
  $ dsh --version      # dsh 0.1.1-rc.2
  $ ls ~/.dsh/hooks/   # summonaikit-harness.sh 252356 bytes
                          (sha 37e55640, MATCH runbook §1)
  ```
  Falta sólo el actor host.

**Host impediment = explícito, tarea pendiente**: la medición del escenario
2 de 20.18 se mantiene `cc:TODO` con observación diferida. Esta es
exactamente la forma que el brief Delavida prescribe, no un bug.

## 5. Inventario de evidencia previa (escenarios 1/2/3 ya conocidos)

| Caso | Fuente | Estado |
|---|---|---|
| 1 — `-saikit` + delegación → contrato + recibo cierra | `docs/smoke-dsh-2026-08-28.md § Escenario 1` + transcript UI 23–28 | ✅ medido en UI web (operador 2026-08-28 07:18) |
| 2 — cerrar sin recibo → GATE | suite `tests/test_gate_behavior.sh` + banco adaptador | ✅ comportamiento bloqueante del hook PROBADO fuera de UI web. UI web viva: ❌ falta de observación (**HOST IMPEDIMENT**) |
| 3 — sin `-saikit` → byte-idéntico | `docs/smoke-dsh-2026-08-28.md § Escenario 3` + transcript UI | ✅ medido en UI web (misma sesión) |

Al cierre de la medición por un host, escenarios 1 y 3 vuelven a observarse
en vivo (controles) y el escenario 2 se observa en la misma sesión UI para
cerrar el DoD.

## 6. Catálogo de skills (discrepancia notificada)

El brief cita `mac-terminal-control` y `mac-agent-transcript` para la fase
final (revisión por Claude en la Mac, pestaña en cwd `summonaikit-claude`).
El catálogo de skills disponible para este agente (`ingenieria` en
OpenClaw) **NO contiene** esas skills; sólo está presente
`mac-node-ops` (`~/.openclaw/agents/ingenieria/agent/workshop-skills/mac-node-ops/SKILL.md`),
que cubre el lado de exec/file transfer/screenshots/UI verification
del nodo Mac. Si la revisión por Claude requiere skills adicionales,
corresponde al operador instalarlas o delegar la fase final a una sesión
Claude Code (no a este agente).

## 7. Qué se entregó en este commit (footprint)

- `docs/evidence/phase-20/20.18/PREFLIGHT-2026-09-12.md` (este archivo)
- `docs/evidence/phase-20/20.18/run-identity.txt`
- `docs/evidence/phase-20/20.19/PREFLIGHT-2026-09-12.md` (declarativo, gated)
- `docs/evidence/phase-20/20.19/run-identity.txt`

No se modifica código, no se commitea fix, no se abre PR contra
`gon0801/saikit-descartable` (no se muta remoto sin medición = gate del
runbook §2). Fila 20.18 sigue `cc:TODO` en `Plans.md`; fila 20.19 sigue
`cc:TODO` (gated por repro FAIL atribuible al adaptador, que requiere el
mismo host).

## 8. Siguiente paso para retomar la medición

Operador (David) levanta sesión Claude Code nativa en pestaña con cwd =
`/Users/dn/dev/summonaikit-claude/`, con `~/.dsh/cordis.patch.yml`
cargado y `dsh --profile <name>` ejecutándose en la misma ventana. Una vez
la sesión viva, los tres escenarios se corren en orden 1 → 3 (controles) → 2
(caso), con captura literal + control sin sentinel + breadcrumb para el
`verifier`. Evidencia se guarda como `docs/evidence/phase-20/20.18/<index>.txt`
o `.jsonl`. La fila cierra sólo si el cierre es observacional.
