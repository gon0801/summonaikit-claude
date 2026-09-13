# Phase 20 — matriz de residuales (20.23, 2026-09-13)

Cada residual observado en Phase 20 enlazado a su tarea o a su decisión.
Nada cae por omisión: lo aceptado dice por qué, lo pendiente dice dónde.
Estados históricos de fase 19 y 18.26/18.27 intactos (no se reabren).

| # | Residual | Origen | Destino |
|---|---|---|---|
| R1 | Hook ajeno `rtk hook claude` registrado antes que el del kit; no interfirió | 20.9 | Decisión: aceptado, no abre fila |
| R2 | claude 2.1.267 medido ≠ pin 2.1.266 del runbook | 20.9 | Decisión: drift declarado; pin re-fijado en 20.14 |
| R3 | Niveles 1-2 sobre copia `d8394766` pre-20.13, nivel 3 sobre `37e55640` | 20.9 | Decisión: declarado en la fila |
| R4 | La captura PreToolUse exigió entrada manual en el settings del clon | 20.9 | Decisión: procedimiento manual (operator-owned), no abre fila |
| R5 | El gate solo reconoce blast `tests/run.sh`/pytest/jest | 20.10 | Fila 22.1 |
| R6 | El test del descartable no discrimina el bump | 20.10 | Candidato sin fila abierta; declarado |
| R7 | El rastro dice «rebase» donde el mecanismo fue merge commit | 20.10 | Deriva del lab (descartable), no de este repo; declarado |
| R8 | Dos veredictos obsoletos sin trackear en el lab | 20.10 | Lab; declarado |
| R9 | Blast de 20.10 sobre wrapper local del lab nunca commiteado | 20.10 | Lab; declarado |
| R10 | El guard de merge niega lecturas que mencionan el script | 20.11 | Fila 22.2 |
| R11 | `ci_chequear` sin chequeo de frescura propio | 20.11 | Fila 22.3 |
| R12 | `recetas/cuidar-pr.md` remite a `.saikit/triage-patrones.md` inexistente | 20.11 | Fila 22.4 |
| R13 | CodeRabbit «Review rate limited» ≠ revisión | 20.11 | Decisión: declarado, no cuenta como revisión |
| R14 | Veredicto citado sobre PR #4 no corresponde al head actual | 20.11 | Decisión: re-sellar antes de cualquier merge |
| R15 | `identity.txt` con nonces de run1; script discriminante no adjunto | 20.12 | Decisión: discriminación verificable en payloads crudos; aceptado |
| R16 | Replay cubierto por composición, sin caso etiquetado | 20.13 | Decisión: aceptado, declarado |
| R17 | NO-MERGE grok no distingue sin-vínculo de stale | 20.13 | Candidato sin fila; declarado |
| R18 | Consumo no comprueba subagentType del hijo | 20.13 | Decisión: inofensivo (solo reviewer sella); aceptado |
| R19 | Hijo en cwd distinto queda fail-closed silencioso | 20.13 | Decisión: aceptado, declarado en la fila |
| R20 | Wrapper gh/git reentra al HOME del operador bajo HOME aislado | 20.14 | Decisión: aceptado (keyring no resuelve en el lab) |
| R21 | LISTO/`--confirmado` corridos por el operador fuera de Grok | 20.14 | Decisión: aceptado por el lead (contrato sí→tool cumplido) |
| R22 | Estado padre borrado post-merge (solo snapshot) | 20.14 | Declarado en la fila |
| R23 | Run1 de 20.14 sin sello (error de red API) no acredita nada | 20.14 | Declarado, no contó |
| R24 | Grok 3×`unknown` por 402 en 20.17 | 20.17 | `unknown` declarado (costo API, no producto) |
| R25 | Invocación directa del cierre, fuera de garantía | 20.15/contrato | Decisión de diseño; declarado |
| R26 | Frase «no sobrecarga del harness» (20.21 L105-106) | 20.21 | Decisión: residual no bloqueante |
| R27 | 2 hilos CodeRabbit obsoletos sin marcar resueltos | 20.21 | Higiene; no abre fila |
| R28 | Pared del CI en 20.10 y toda espera humana: `unknown` | 20.21 | `unknown` declarado |
| R29 | Respuestas definitivas de adopción = `unknown` | 20.22 | Estado: solo el proyecto autoriza |
| R30 | `run-identity.txt` cita `4878997`, punta `44469bb` (docs-only) | 20.28 | Declarado en la fila |
| R31 | Caso mutante de secrets replica la ramificación en vez de ejecutarla | 20.28 | Decisión: aceptado, declarado |
| R32 | Dos formas del raíl de EVENTO fuera de alcance | 20.28 | Candidato 21.5 |
| R33 | Round-robin sensible a N (re-medir si el reloj pasa ~10 min) | 20.29 | Decisión documentada en workflow y AGENTS.md § CI |
| R34 | Hook no parsea con bash 3.2 del sistema; instalador rehúsa en macOS | 20.25 | Gap reportado aparte; fix fuera del alcance skill/map/harness, sin fila abierta |
| R35 | 20.18/20.19 abiertas (escenario2 dsh sin medir) | 20.18/20.19 | Decisión bloque 6: documentadas, nunca PASS |
| R36 | 16.7 receta→tier aplazada | 20.21 | Decisión con criterio de reactivación explícito |
| R37 | Autopilot por proyecto preparado, sin activar | 20.22 | Decisión: opt-in; sin consentimiento no hay activación |

Mantenimiento del mapa (20.25): conserva `PASS`/`FAIL`/`unknown` por feature;
`clean`/`changed`/`blocked` reservados para el veredicto de la pasada.
