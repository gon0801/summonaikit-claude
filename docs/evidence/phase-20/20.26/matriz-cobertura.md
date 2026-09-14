# 20.26 — matriz de cobertura FINAL (2026-09-13)

Sucesora de `matriz-cobertura-draft.md` (DRAFT del bloque 6, renombrada en
este cierre). Estados verificados contra `Plans.md` de `origin/master` al
2026-09-13 (post-#323). La autorización §8 EXPIRA con este cierre, como
estaba pactado (`docs/phase20-mediciones-runbook.md` §8).

## Required — observados y gate del PR verde

20.1, 20.2, 20.3, 20.4, 20.5, 20.8, 20.9, 20.10, 20.11, 20.12, 20.15,
20.23, 20.24, 20.27: `cc:完了` con PR y gate verde (Status en `Plans.md`).

**20.18: `cc:完了` (PR #323)** — el último Required con unknown pendiente
cerró observed-PASS: medición viva del operador en dsh UI web (2026-09-13),
los tres escenarios en la MISMA sesión, escenario2 (cierre sin recibo ⇒
adaptador bloquea y el host continúa) observado por primera vez en UI viva
(`docs/evidence/phase-20/20.18/medicion-2026-09-13.md`).

(20.26 es esta misma fila: cierra con este documento y el PR de cierre.)

## Recommended — ejecutados o retirados con decisión explícita

Ejecutados: 20.6, 20.7, 20.20, 20.21, 20.25, 20.28, 20.29 — todos `cc:完了`.

20.25 cerró con veredicto `changed` y **residuales declarados, no ocultos**:
5 FAIL de entorno con causa única (R34: el bash 3.2 del sistema no parsea el
hook, preexistente) y 2 unknown en `docs/evidence/phase-20/20.25/matriz.md`.
**Aceptados en este cierre** como residuales de la fase (R34 sigue en
`docs/phase-20-residuales.md`; no hay fila de fix aprobada para él).

## Conditional — habilitados ejecutados; descartados cancelados sin PASS

Habilitados y ejecutados: 20.13 (canal 20.12 positivo), 20.14, 20.16, 20.17.

**20.19: cancelada sin PASS con decisión explícita** — su activación exigía
repro FAIL atribuible al adaptador desde 20.18; la medición cerró PASS, así
que no hay activación posible. Confirmada la descartación anticipada del
bloque 6: ahora con medición, no solo con decisión.

## Optional — con decisión registrada

- 20.22: adopción PREPARADA, SIN ACTIVAR (opt-in; solo el proyecto autoriza).
- 16.7: APLAZADA por 20.21 con criterio de reactivación (medición pareada
  mismo-caso/dos-tiers).

## Mantenimiento 20.25

Ejecutado (`changed`): 10 PASS, 5 FAIL de entorno (R34), 2 unknown
declarados; gap G1 corregido con regresión+mutante+re-conducción en el mismo
PR (#316). Gaps no ocultos; aceptados como residuales (arriba).

## Auditoría docs / deploy-log / ledger

- Docs: reconciliados en 20.23 (guía, README, spec, adversary, skill).
- Deploy-log: `bash tools/check-deploy-log.sh` → OK (50 entradas, ordenadas,
  sin PR duplicado) al 2026-09-13; la entrada no-op de #323+#324 viaja en el
  PR de este cierre.
- Ledger: `bash tools/audita-ledger.sh` → OK (ninguna fila `cc:TODO` con
  trabajo ya mergeado) al 2026-09-13. Con este PR no queda ninguna fila de
  Phase 20 abierta.

## Residuales aceptados en este cierre (ninguno convertido en PASS)

- R34 (bash 3.2 del sistema no parsea el hook, preexistente; 5 FAIL de
  entorno de la pasada 20.25) y los 2 unknown de la pasada.
- R1–R37 de `docs/phase-20-residuales.md`, cada uno enlazado a su
  tarea/decisión; los cuatro hallazgos de las mediciones 20.9–20.11 ya son
  filas de Phase 22 (22.1–22.4, con plan en `docs/phase-22-plan.md`).
- Unknowns declarados que quedan como límites, no como pendientes de fase:
  check-secrets fuerte sin gitleaks en Linux, merge-happy-path live en
  claude sin alcance ejercido (18.9), respuestas de adopción 20.22 (opt-in).

## Expiración de la autorización §8

Con el cierre de esta fila EXPIRA el paquete §8 aprobado el 2026-09-09
(external-send acotado a `gon0801/saikit-descartable`), registrado en el
ledger 事前確認 de `Plans.md`. Cualquier medición viva futura requiere un
paquete nuevo aprobado por el operador.
