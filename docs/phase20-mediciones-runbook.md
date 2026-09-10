# Runbook de preparación — mediciones vivas Phase 20 (fila 20.8)

Estado: **preparación**. Ninguna medición viva corre al escribir este documento;
solo fija versiones, destinos, aislamiento, credenciales, presupuesto y el
paquete de autorización que las filas 20.9–20.25 consumen. Sin autorización
vigente o sin cuota => **bloqueado sin mutación** (DoD de 20.8).

---

## 1. Identidad de la medición

Versiones/ejecutables medidos el **2026-09-08** (macOS 26.6, arm64):

| Ejecutable | Versión |
|---|---|
| claude (Claude Code) | 2.1.266 |
| gh | 2.98.0 |
| git | 2.55.0 |
| node | v26.8.1 |
| zsh | 5.9 |

Checkout previsto del kit: worktree limpio de `origin/master`, SHA re-fijado
el 2026-09-09 (tras el merge de 20.13, que tocó el hook; el pin original de
preparación fue `f4a8dbe`):

```
e0f7a2518e6983025d0c19a501a01138c8a730d8
```

Hook previsto: `hooks/summonaikit-harness.sh` de `origin/master`:

```
sha256 37e55640003afaff6d4a54cf6495afc73bec5799b86323fb7a317889fec78680
4345 líneas
```

**Re-verificación OBLIGATORIA al ejecutar cada medición** (no vale la palabra de
este documento si el repo avanzó):

```bash
git fetch origin
git rev-parse HEAD; git rev-parse origin/master      # DEBEN coincidir
git status --porcelain | wc -l                        # debe ser 0
shasum -a 256 hooks/summonaikit-harness.sh
wc -l hooks/summonaikit-harness.sh
```

Condición de paso: `git rev-parse HEAD` == `git rev-parse origin/master`
(worktree actualizado) y árbol limpio. Si NO coinciden o `origin/master`
avanzó respecto de e0f7a25…: **re-fijar y re-declarar** el
nuevo SHA del checkout y del hook en la evidencia de la medición. La evidencia
20.x de una fila solo se reutiliza en otra si coincide checkout y hook SHA
(misma regla que exige 20.25).

## 2. Destinos

### 2.1 Repo descartable remoto: `gon0801/saikit-descartable` (privado)

Verificado el 2026-09-08 en modo **read-only**: topic `saikit-descartable`
presente Y marcador `SAIKIT-ORIGEN.md` presente (contenido Phase 18). El plan
de fase 18 decía borrarlo en 18.10; **sigue vivo y se reutiliza**.

**Verificación topic+marcador OBLIGATORIA inmediatamente ANTES de cada
mutación remota** (cualquier `git push`, `gh pr create`, `gh pr merge`,
`gh api` con escritura):

```bash
gh repo view gon0801/saikit-descartable --json repositoryTopics --jq '.repositoryTopics[].name'
gh api repos/gon0801/saikit-descartable/contents/SAIKIT-ORIGEN.md --jq '.content' | base64 -d
```

Condición de paso: el topic `saikit-descartable` está en la lista Y el marcador
se lee y menciona el origen Phase 18. **Cualquier divergencia (topic ausente,
marcador ausente o cambiado, repo renombrado/borrado) => bloqueado, sin
mutación, fila reportada como bloqueada.**

Filas que consumen este destino: 20.10, 20.11 (hilos/PR de prueba), 20.14,
20.21 (viaja sobre 20.10/20.11), y cualquier 20.22/20.25 que conduzca autopilot
vivo.

### 2.2 Clone local aislado

```bash
RM="$TMPDIR/saikit-descartable-$$"        # directorio desechable, jamás dentro de ~
git clone https://github.com/gon0801/saikit-descartable.git "$RM"
```

Patrón de fase 18 (docs/smoke-autopilot-2026-09-05.md): los tools del kit se
copian a `tools/` del descartable con **commit explícito** (precedente 17.5),
`saikit-setup-autopilot.sh` por flags (`merge=true, despliega=no`), y el CI del
descartable es **1 job bash** (`saikit-ci-minimo.sh`). Consumen: 20.10, 20.14,
20.21.

### 2.3 Worktree del kit

Worktree limpio del kit en el SHA de la sección 1. Consumen: todas las filas
20.9–20.25 (es la fuente del hook vía `SAIKIT_HOOK_VIVO` y de los tools).

## 3. Aislamiento

- **HOME desechable**: cada medición corre con las variables del patrón de
  `tests/run.sh` del worktree (tests/run.sh:166-168):

  ```bash
  env HOME="$caja/home" USERPROFILE="$caja_userprofile" \
      TMPDIR="$caja/tmp" TMP="$caja/tmp" TEMP="$caja/tmp" \
      SAIKIT_HOOK_VIVO="$hook_vivo" …
  ```

  La ruta del hook VIVO se resuelve **antes** de entrar a la caja, con el HOME
  del invocador (tests/run.sh:113-118): adentro, `$HOME/.claude/hooks/…` ya no
  resolvería. `SAIKIT_HOOK_VIVO` apunta a la fuente del worktree (lección Task
  3.5: sin ella se mide el hook instalado, no el editado).
- **cwd aislado**: nunca dentro de `~`; clones y cajas bajo `$TMPDIR`.
- **PROHIBIDO** tocar perfiles de producción (`~/.claude`, `~/.zcode`,
  `~/.grok`, `~/.codex`) desde las mediciones.
- **Staging por override** para turnos `-saikit` en repos descartables locales:
  `tools/stage-override.sh` (Task 2.4) — pone el hook nuevo en UN repo
  descartable sin estrenarlo globalmente; el estado queda aislado porque el hook
  deriva `STATE_ROOT` de su propia ruta.
- **Excepción declarada**: las corridas que SOLO pueden hacerse contra el
  perfil real del operador (p.ej. 20.9, PreToolUse vivo en Claude con el hook
  registrado en su perfil) son del **LEAD**, no del implementador. El
  implementador para y lo reporta.

## 4. Credenciales por mecanismo del host

- Credencial `gh`: **keyring del sistema**, cuenta `gon0801`, scopes
  `gist/read:org/repo/workflow`, protocolo https. **PROHIBIDO** leer/mostrar
  tokens, exportar `GH_TOKEN`/`GITHUB_TOKEN`, o dejar credenciales en logs.
- Validación ANTES de toda operación de red, bajo el HOME aislado de la
  medición:

  ```bash
  env HOME="$caja/home" USERPROFILE="$caja_userprofile" TMPDIR="$caja/tmp" \
      gh auth status
  ```

- Si el keyring **no resuelve** bajo HOME aislado (auth status falla), la
  corrida de red **es del lead**: se reporta bloqueada, no se copian tokens al
  env como workaround.

## 5. Presupuesto

| Recurso | Tope | Regla |
|---|---|---|
| Cuota gh API core | ≤60 llamadas por medición, INCLUSO las dos de `gh api rate_limit` (antes/después) | Medir antes/después con `gh api rate_limit --jq '.resources.core'`. Cuota medida el 2026-09-08: 4904/5000 restantes (reset ~1h). |
| PRs/ramas de prueba en el descartable | ≤15 en TODA la fase | Contar `gh pr list --state all` + ramas antes de crear. |
| Actions del descartable | 1 job bash (ci-minimo) | Sin jobs extra ni matrices. |
| Tokens/tiempo por turno vivo | declarar n de turnos y tope por corrida en la evidencia de cada fila | Cada medición declara n y el tope con el que corrió; presupuesto excedido = corrida abortada. |

**Regla dura**: sin cuota o con presupuesto excedido => **bloqueado sin
mutación**. No se "estira" un tope a mitad de corrida; se reporta y se reagenda.

## 6. Operaciones por medición (release lane, alto nivel)

| Fila | Qué se ejecuta | Destino | Qué NO se ejecuta |
|---|---|---|---|
| 20.9 | PreToolUse vivo en Claude: intento controlado de merge directo negado + comando permitido llega al tool. **Lead** (perfil real). | Perfil del operador + repo de solo observación | Reinstalación de hook por suposición; mutación de rutas/HEAD remotos |
| 20.10 | Autopilot completo: sentinel → setup → PR → CI → reviewer → LISTO → sí → merge por tool (`saikit-merge.sh`), postmerge | Descartable (remoto + clone aislado) | `gh pr merge` a pelo; merge manual; merges en repos del usuario |
| 20.11 | `cuidar-pr` vivo: modos revisar / solo-hilos / cuidar, casos controlados | Descartable (hilos de PR de prueba) | Cambios de código en modo solo-hilos; merge en modo cuidar |
| 20.12 | Canal verificable Grok padre-hijo (spike, captura) | Entorno local aislado Grok | Transferencia de sellos; mutación remota |
| 20.14 | Autopilot completo en Grok (tras 20.13 positivo) | Descartable + Grok aislado | Merge manual sustituto; segunda sesión ajena |
| 20.15 | Spike cierre headless observable | Local aislado | Inferir `-p` del payload |
| 20.17 | Cierre headless vivo sync/async (tras 20.16) | Local aislado | Atribuir éxito a rc0 histórico |
| 20.18 | Bloqueo dsh en UI web, escenario2 (escenarios 1/3 control) | dsh UI local | Headless sustituto |
| 20.20 | Corepack/pnpm sin packageManager, fixture aislado | Fixture local | Prompt oculto; cambio global |
| 20.21 | Costo/latencia sobre recorridos ya corridos (20.10/20.11) | Descartable | Nueva implementación de ruteo |
| 20.22 | Adopción por proyecto del autopilot (documental + preguntas) | Este repo (docs) | Activación sin consentimiento; config publicada sin autorización |
| 20.25 | Mantenimiento del feature map (usa evidencia 20.x solo si coinciden checkout/hook SHA) | Worktree del kit | Convertir FAIL/unknown en PASS; reabrir 18.26/18.27 |

Nota: 20.13, 20.16, 20.19 son lane gate/tdd y no consumen el paquete de
autorización remota salvo lo que hereden de su condición; 20.23, 20.24, 20.26
son docs/gate/cierre.

**Nunca, en ninguna fila**: merge manual, `gh pr merge` a pelo (fuera de
`tools/saikit-merge.sh` del descartable), tocar perfiles de producción, ni
merge en repos del usuario.

## 7. Límites y limpieza

- Al final de cada medición: borrar clones desechables, cajas de HOME y
  worktrees temporales creados para esa corrida (`rm -rf` solo bajo `$TMPDIR`
  de la caja, nunca rutas del perfil).
- El repo descartable remoto **NO se borra por agente**: si el operador decide
  eliminarlo, lo hace a mano (recomendado al terminar la fase).
- **Sin deploy de hook en esta fase** salvo cambio merged: el protocolo de
  AGENTS.md (install-hook + check + deploy-log + audita-ledger) aplica solo tras
  merge a master que toque `hooks/summonaikit-harness.sh`.

## 8. Paquete de autorización a aprobar

Texto para el operador (aprobar o rechazar explícitamente; sin aprobación,
**20.8 queda abierta y no corre ninguna medición viva**):

> Autorizo envíos externos (external-send) **acotados al repo
> `gon0801/saikit-descartable`** (privado, topic `saikit-descartable`, marcador
> `SAIKIT-ORIGEN.md`), a favor de las filas 20.9–20.25 de Phase 20, para:
>
> - `git push` de ramas de prueba al descartable.
> - `gh pr create` en el descartable.
> - `gh pr merge --squash --match-head-commit` — **únicamente** vía
>   `tools/saikit-merge.sh` del descartable (nunca `gh pr merge` directo).
> - `gh api` de hilos (comentarios/reviews) en PRs del descartable.
>
> **EXPIRA** al cerrar la fila 20.26. `gh repo delete` queda FUERA: destructivo,
> solo manual por el operador. Si el descartable desaparece o diverge, se PARA y
> se re-aproba un paquete nuevo; nada queda pre-autorizado para recrearlo. NADA de merges en repos del usuario: esa
> autorización es por-repo con `autopilot.json` (D15/D18), no este paquete.

Registro de la aprobación: entrada en el ledger 事前確認 de `Plans.md` que hoy
NO existe (el alcance D23 de fase 18 expiró al cerrar 18.10). La escribe el
lead al aprobar; este runbook no la crea.

## 9. Condiciones de cierre de 20.8

Checklist contra la DoD literal de Plans.md:211 — *"Runbook con
operaciones/destino y autorización de ejecución; topic+marcador verificados
antes de mutar remoto; HOME/cwd aislados; sin autorización o cuota => bloqueado
sin mutación, ninguna prueba viva acreditada"*:

- [x] Runbook con operaciones/destino — este documento (secciones 2 y 6).
- [x] Autorización de ejecución — paquete de la sección 8 listo para aprobar.
- [x] topic+marcador verificados antes de mutar remoto — leídos el 2026-09-08
      read-only; verificación pre-mutación obligatoria en sección 2.1.
- [x] HOME/cwd aislados — sección 3 (patrón tests/run.sh).
- [x] "Sin autorización o cuota => bloqueado sin mutación" — secciones 4, 5 y 8.
- [x] Versiones/ejecutables fijados (sección 1), SHAs fijados y con
      re-verificación declarada, cuota gh medida el 2026-09-08.
- [x] **Autorización de la sesión** — aprobada por el operador el 2026-09-09;
      entrada escrita por el lead en el ledger 事前確認 de Plans.md vía PR #279
      (scope external-send fase 20; el paquete de la sección 8 se corresponde
      con esa entrada).
- [x] Renovación del alcance (entrada ledger fase 20) — la misma entrada del
      PR #279 reemplaza el alcance D23 de fase 18, que expiró al cerrar 18.10.

**Ninguna prueba viva corre ni se acredita en este documento**: es
preparación. Lo ya verificado el 2026-09-08 (versiones, SHAs, topic+marcador read-only,
cuota) es evidencia de preparación, no de mediciones.
