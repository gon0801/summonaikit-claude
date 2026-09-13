# 20.26 — matriz de cobertura final (DRAFT, 2026-09-13 — NO cierra)

DRAFT del bloque 6: el cierre del ledger NO se aplica en este bloque
(decisión orquestador+operador: bloques 7–9 necesitan la §8 viva; 20.25 y
20.26 quedan cc:TODO con su decisión escrita). Deploy y ledger, a cargo del
líder al cerrar de verdad.

## Required — observados y gate del PR verde

20.1, 20.2, 20.3, 20.4, 20.5, 20.6, 20.7, 20.8, 20.9, 20.10, 20.11, 20.12,
20.15, 20.16, 20.17, 20.20, 20.23, 20.24, 20.27: cc:完了 con PR y gate verde
(ver Status en Plans.md). **20.18: ABIERTA** con decisión escrita (R35):
escenario2 dsh sin medir = unknown pendiente, nunca PASS; no bloquea 20.25/20.26.

## Recommended — ejecutados o retirados con decisión explícita

Ejecutados: 20.20, 20.21, 20.28 (corrió: no hay que retirarla), 20.29.
**20.25: ejecutado parcial** — veredicto `changed` (matriz en
`docs/evidence/phase-20/20.25/matriz.md`); gaps no ocultos (R34 + unknowns);
fila queda cc:TODO con decisión escrita, no PASS.

## Conditional — habilitados ejecutados; descartados cancelados sin PASS

Habilitados y ejecutados: 20.13 (canal 20.12 positivo), 20.14, 20.16.
**20.19: descartado sin PASS** con decisión explícita: su activación exige
repro FAIL atribuible al adaptador desde 20.18, que no existe (20.18 sin
medir); sin activación no hay ejecución pendiente.

## Optional — con decisión registrada

- 20.22: adopción PREPARADA, SIN ACTIVAR (opt-in; solo el proyecto autoriza).
- 16.7: APLAZADA por 20.21 con criterio de reactivación (medición pareada).

## Mantenimiento 20.25

Ejecutado parcial (`changed`): 10 PASS, 5 FAIL de entorno con causa única
(R34), 2 unknown declarados. Gaps no ocultos (R34 reportado aparte).

## Auditoría docs / deploy-log / ledger

- Docs: reconciliados en 20.23 (guía, README, spec, adversary, skill).
- Deploy-log: 20.27 + entradas NO-OP posteriores; sin horas inventadas.
- Ledger (Plans.md): 20.23 cc:完了; 20.25/20.26 cc:TODO con decisión;
  20.18 abierta con decisión; 20.19 cancelada sin PASS. **Cierre pendiente.**

## Unknowns que mantienen filas pendientes

20.18 (escenario2), 20.25 (R34 + unknowns de la pasada), 20.26 (este DRAFT),
atribución dsh, check-secrets fuerte sin gitleaks, merge-happy-path live sin
alcance ejercido, respuestas de adopción 20.22. Ninguno declarado PASS.
