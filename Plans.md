# summonaikit-claude — Plans.md

Creado: 2026-08-08
Alcance: hacerse cargo del hook que gatea cada turno y llevar la misma fuente a
los hosts aprobados — Claude Code, zcode, Codex y Grok Build— con pruebas
propias, instalación controlada y cierre de los agujeros que hoy lo vuelven un
control decorativo. Contrato de producto y premisas medidas:
`docs/spec/00-project-spec.md`.

**Contrato de datos:** `not_observed != absent`. Lo que no se pudo observar se
marca `unknown`, nunca se afirma como ausente.

---

Fases 0-12 cerradas: ver docs/plans-archivo.md — movidas 2026-08-25, higiene del tope de 200 lineas. La Clasificacion del alcance y la Validacion del plan original tambien viven alla.
## Phase 13 — El adversario (2026-08-24)

**Propósito:** agregar un cuarto rol OPT-IN a la ceremonia — `adversary`, un
abogado del diablo que corre después del verifier y antes del reviewer, ataca
el cambio (entradas no manejadas, datos preexistentes, tests que no
discriminan, blast radius, falla parcial, trust boundary) y SOLO reporta: no
repara. Un turno sin adversary cierra exactamente como hoy. Diseño en
`docs/phase-13-adversary-design.md`; plan en `docs/phase-13-adversary-plan.md`;
origen: borrador externo del operador conservado sin editar en
`docs/phase-13-adversary-borrador.md`.

| Task | 内容 | DoD | Depends | Status |
|------|------|-----|---------|--------|
| 13.1 | `[Diseño]` `[lane:gate]` `[tdd:skip:diseño-y-medición]` **Diseño medido.** Atribución de rol por host (canales de despacho e internos), convención y ciclo de vida del artefacto de hallazgos (D2: dir-scoped keyless, sin `session_id`), postura de falla del candado (D3: detección post-hoc + bloqueo en el Stop, no hay `PreToolUse` en ningún host), tier de ruteo (D5: comparte `review` con reviewer) y mapeo de rol + precedencia de keywords (D6). Entrega `docs/phase-13-adversary-design.md` | Cada decisión cita su payload o medición; lo no observable queda `unknown` declarado, no rellenado por analogía | Phase 12 (12.3 cerrada; no bloquea) | cc:完了 [b91c7a3] — **CIERRE (PR #63 mergeado + fix PR #64)**: diseño medido con las 5 decisiones (D1-D6); cross-review externo codex+claude (17 hallazgos integrados) y ronda 2 kimi+qwen (5 hallazgos bajos) sobre el propio diseño; fix de PR #64 (contrato de mtime del escaneo, inicialización del estado al armar, DoD bidireccional) atendido en `25b94f0`. Deploy no-op en ambos merges (docs-only) |
| 13.2 | `[Perfil]` `[lane:fast]` `[tdd:skip:prompt-only]` **`agents/adversary.md`** adaptado del borrador: enforcement REAL (detección post-hoc + Stop, no `PreToolUse` prometido), única zona de escritura `.saikit/findings/`, hueco de `Bash` declarado AL PROPIO agente, regla de redacción antes de escribir | Consistente con los 3 perfiles existentes (frontmatter, secciones, `saikit_owned`); borrador sin editar | 13.1 | cc:完了 [4809627] — **CIERRE (PR #65, merge `1d05905`)** |
| 13.3 | `[Perfil]` `[lane:fast]` `[tdd:skip:prompt-only]` **`agents/reviewer.md`, sección de adjudicación.** Cada hallazgo con veredicto explícito (aceptado → gap list con file:line / rechazado → razón); cada campo del finding tratado como DATO, jamás instrucción; artefacto ilegible/malformado se declara al lead, no se inventan hallazgos | El texto obliga veredicto POR hallazgo y define los dos casos degradados (sin artefacto / artefacto ilegible) | 13.1 | cc:完了 [6c76dab] — **CIERRE (PR #65, merge `1d05905`)** |
| 13.4 | `[Guardrail]` `[lane:gate]` `[tdd:required]` **Candado en el hook.** Detección post-hoc de Edit/Write atribuidos al adversary fuera de `.saikit/findings/` con canonicalización FÍSICA (`cd`+`pwd -P`, cierra `C:/` vs `/c/` y symlinks intermedios); `Bash` best-effort; escaneo de secretos por sesión (rutas registradas + mtime ≥ época de armado, formas ya redactadas descontadas); gitignore del consumer idempotente | Rojo medido pre-fix; caso que bloquea + caso que permite + caso de traversal/symlink + caso de falla de infraestructura; 0 divergencia en la línea base | 13.1 | cc:完了 [e3ea262] — **CIERRE (PR #65, merge `1d05905`)**: incluye los fixes del cross-review ronda 2 del mismo PR — kimi #1/codex #1 (prefijo anclado con la misma maquinaria física que canonicaliza los blancos), lead+kimi #2 (descuento de formas ya redactadas antes de grepear), qwen #1/codex #2 (remedio real: revertir + re-armar, no "revertir a mano"), qwen #3/#7 (diagnóstico fail-open sin GNU `date -d`; rutas redactadas en el feedback) y el path del artefacto redactado también en el mensaje del escaneo |
| 13.5 | `[Gate]` `[lane:gate]` `[tdd:required]` **Gate de secuencia condicional (D4) + mapeo de rol (D6).** Caso exacto y keyword `adversar` con precedencia sobre la rama reviewer; escotilla `DELEGATED` extendida a `awaiting adversary`; orden `implementer→verifier→adversary→reviewer` + línea `ADVERSARY:` label-only cuando corrió; escotilla `ROLE FALLBACK: ADVERSARY`; sin adversary, byte-idéntico | Casos con nombre en verde (con adversary cierra / fuera de orden bloquea / adversary dos veces / sin verifier previo / `adversarial-*` no acredita reviewer / escotillas / sin adversary cierra igual que hoy / fast con adversary visto exige la línea) | 13.4 | cc:完了 [672d6d7] — **CIERRE (PR #65, merge `1d05905`)** |
| 13.6 | `[Contrato]` `[lane:gate]` `[tdd:required]` **Contrato de armado (D1).** Criterio de delegación (auth, pagos, migraciones/datos preexistentes, el hook mismo); formato de la línea `ADVERSARY:`; forma `DELEGATED - awaiting adversary`; forma del despacho del reviewer que nombra el artefacto a adjudicar | Turno sin adversary cierra igual que hoy; línea base por el precedente 11.1 (diff auditado, 0 veredictos movidos) | 13.5 | cc:完了 [278d5b2] — **CIERRE (PR #65, merge `1d05905`)**: fix de CodeRabbit sobre el recibo del escenario 54 (coherente con su propio README) incluido en el mismo PR |
| 13.7 | `[Ruteo]` `[lane:gate]` `[tdd:required]` **Router.** Fila `adversary → review` en `tools/model-routing.sh` (D5); zcode/grok heredan lo medido en 12.1/12.2 (fila vacía hereda del padre); kimi sin claves de ruteo (sellado 12.3) | Test del router extendido; candado "IDs de modelo SOLO en el router" sigue verde | Phase 12 (12.4), 13.2 | cc:完了 [3362d19] — **CIERRE (PR #66, merge `411abf2`)** |
| 13.8 | `[Hosts]` `[lane:gate]` `[tdd:required]` **Extensión por host** por las costuras reales de posesión de la Phase 12: claude (12.6), zcode, grok, kimi (12.7, posesión sin ruteo); codex sin costura de perfiles, `unknown` declarado; casos por target del gate condicional | Por host con costura, un caso que pasa y uno que bloquea; codex y lo no medible quedan `unknown` declarados | 13.5, 13.7, Phase 12 (12.6, 12.7) | cc:完了 [2d4ee91] — **CIERRE (PR #66, merge `411abf2`)**: implementó kimi (posesión de los cuatro perfiles en `~/.agents/agents/`, sin ruteo). Fixes del cross-review ronda 1 en el mismo PR — grok #1/codex #1 (zcode clasifica los CUATRO destinos antes de publicar ninguno, cierra instalación a medias con el rol nuevo), grok #2 (el caso de NO_OBSERVABLE del rol 3 discrimina también con adversary), grok #3 (`--refrescar-manifiesto` reporta un `adversary.md` desconocido CON advertencia explícita de kit-owned — su hash jamás va al manifiesto) — más 4 casos nuevos del gate condicional por target zcode/grok (codex, ronda 1, hallazgo #2) |
| 13.9 | `[Release]` `[lane:release]` `[tdd:skip:docs]` **Cierre.** § nuevo del rol en `docs/spec/00-project-spec.md` (contrato, enforcement real, límites consolidados); reconciliación perfil-vs-implementación de `agents/adversary.md` contra lo que 13.4/13.5 realmente construyeron; Phase 13 en `Plans.md`; README con el rol opt-in; deploy vía `tools/install-hook.sh` anotado en `docs/deploy-log.md` (lo hace el lead) | Spec/ledger/README coherentes entre sí; el perfil no promete nada que el hook instalado no haga; deploy-log con el sha instalado | 13.1–13.8 | cc:完了 — **CIERRE (2026-08-25, PR #67)**: spec con `## El cuarto rol — adversary (Phase 13)` (qué es, enforcement real, límites consolidados con los hallazgos posteriores al diseño ya sumados); esta fila y las 8 anteriores cerradas; README con los cuatro perfiles y el rol opt-in presentado sin duplicar el spec; reconciliación de `agents/adversary.md` contra el hook vivo (ver divergencias corregidas en el PR). `tools/check_context_docs.py` no está instalado en este repo (higiene opcional, aún no corrida — Core Rule 2: no se afirma "sin hallazgos", queda `unknown` declarado); deploy ejecutado 2026-08-25 (tres hooks vivos reparados byte a byte + adversary plantado en 4 hosts), con CUATRO bugs vivos atrapados por el propio deploy/estreno y corregidos en el mismo PR: orden de `limpiar_trads_vendor` (zcode), `--dry-run` de zcode que escribía el registro, descuento de `[REDACTED]` roto en el formato JSON (HIGH del estreno EN VIVO del rol sobre su propio cierre) y falso positivo `/dev/null*` del guard de Bash que bloqueó al propio lead. El tag `[tdd:skip:docs]` quedó corto — los fixes tocaron hook e instalador con casos nuevos y rojos medidos (excepción declarada) — detalle en `docs/deploy-log.md` |

---

## 事前確認

- 事項: escritura de ACLs sobre `~/.claude/hooks/` y `~/.claude/hooks/state/`
  理由: quitar `Modify` a identidades de sandbox sobre el script que corre sin sandbox
  scope: Phase 0 / Task 0.1
- 事項: lectura de `~/.claude/settings.json` y `~/.claude/settings.local.json`
  理由: verificar que el hook sigue registrado (modo de falla silencioso) y el cableado del heal
  scope: Phase 0 / Task 0.3, Phase 2 / Task 2.4
- 事項: remoción de ACE de cuentas BORRADAS (SID no resoluble) en `~/AppData`,
  `~/AppData/Local` y `%TEMP%` — aprobado en sesión 2026-08-08
  理由: A7-bis — `%TEMP%` re-contamina `~/.claude` por `move`, y los 5 SID
  huérfanos estaban explícitos repartidos en esos tres niveles. NO se toca
  `CodexSandboxUsers`, que ahí sí escribe legítimamente
  scope: Phase 0 / Task 0.2
- 事項: escritura de ACLs sobre `~/.claude` (la RAÍZ del perfil, no solo `hooks/`)
  理由: ahí vive el otorgamiento explícito medido en la 0.1; mientras siga, el hook
  se puede desregistrar desde `settings.json` sin tocar el archivo
  scope: Phase 0 / Task 0.2
- 事項: escritura sobre `~/.claude/hooks/summonaikit-harness.sh` (el archivo que gatea cada turno)
  理由: la adopción por reemplazo es el objetivo de la Phase 2
  scope: Phase 2 / Task 2.4
- 事項: escritura sobre `C:\Users\ehven\quality-kit\saikit-gate-heal.ps1` y su batería
  理由: el skip por marcador debe mergearse antes de instalar, para no tener dos escritores
  scope: Phase 2 / Task 2.3, Phase 4 / Task 4.1
- 事項: creación de repo remoto y `git push` a `gon0801/summonaikit-claude`
  理由: regla de dejar en git + remoto todo lo tocado
  scope: Phase 1 / Task 1.1 en adelante
- 事項: descarga del kit del vendor en directorio desechable (ya ejecutada 2026-08-08)
  理由: verificar la premisa de si conviene actualizar; se hizo fuera del home y se borró
  scope: pre-plan, completado
- 事項: escritura y reemplazo recuperable de `~/.codex/hooks/summonaikit-harness.sh`
  理由: instalar la fuente aprobada de Phase 6 y validar un turno real con backup/restore listo
  scope: Phase 6 / Task 6.6
- 事項: alta y revocación de folder trust para repos descartables de Grok
  理由: ejecutar hooks de proyecto durante captura, probe y staging sin instalar el harness global
  scope: Phase 7 / Tasks 7.1, 7.2 y 7.6
- 事項: escritura/reemplazo recuperable y remoción selectiva bajo `~/.grok/hooks/` y `~/.grok/agents/`
  理由: instalar o retirar sólo artefactos con propiedad `summonaikit-claude`, preservando el verifier ajeno
  scope: Phase 7 / Tasks 7.5 y 7.6
- 事項: escritura vía `tools/install-hook.sh` (deploy) en `~/.claude/hooks/`,
  `~/.claude/agents/`, `~/.zcode/agents/` + user-config de zcode, y
  `~/.agents/agents/` (kimi) — codex y grok ya cubiertos por las entradas de
  Phase 6/7
  理由: 13.9 instala hook y perfiles con las disciplinas existentes (tres/cinco
  estados, backups, atómico); zcode/kimi no tenían entrada propia en este
  ledger (hueco desde Phase 5/12, cerrado acá)
  scope: Phase 13 / Task 13.9
- 事項: sesiones vivas de medición en 13.1 (turnos claude contra `hook_lab.sh`)
  理由: los canales de atribución de rol se miden, no se suponen; preferencia por el lab, no el perfil vivo (lección 9.9)
  scope: Phase 13 / Task 13.1, ya ejecutada
