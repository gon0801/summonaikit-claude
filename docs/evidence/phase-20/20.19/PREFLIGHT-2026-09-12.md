# 20.19 — Preflight 2026-09-12 (declarativo, gated por 20.18)

La fila 20.19 (`Corrección dsh derivada del escenario 2`) es **condicional**
sobre 20.18. Conforme a su DoD:

> Repro antes del fix, regresión node/hook y mutante; escenarios 1/3 no
> regresan; repetir UI demuestra 2; si depende del host dejar impedimento
> explícito, no inventar fix.

Y su columna Dep:

> 20.18 (repro FAIL atribuible al adaptador, no exige cierre)

Estado actual: 20.18 está **cc:TODO con host impediment declarado**
(`docs/evidence/phase-20/20.18/PREFLIGHT-2026-09-12.md §4`).

Por lo tanto la fila 20.19 se mantiene **cc:TODO sin activación**:

- No hay repro de defecto (la medición no se ha ejecutado).
- El contrato del fix NO puede acotarse al evento observado (no hay evento).
- El gate `repro FAIL atribuible al adaptador` no se cumple.
- Activar 20.19 sin repro violaría el brief ("Activa 20.19 solo si 20.18
  reproduce defecto atribuible al adaptador").

Las verificaciones de identidad, presupuesto y §8 que aplicarían a 20.19
están recogidas en `docs/evidence/phase-20/20.18/PREFLIGHT-2026-09-12.md`
(mismas precondiciones: HEAD limpio, pin match, marcador OK, PR 11/15,
§8 vigente).

Próximo movimiento, una vez 20.18 produzca repro FAIL atribuible al
adaptador:

1. Branch separado para el fix (no se mezcla con preflight):
   `work/20.19-fix-<descriptor>` desde `origin/master` actualizado.
2. Repro previo + mutantes del fix + regresión de 1/3.
3. PR con gate verde mergeado por el líder y desplegado en dsh.
4. Re-medición UI del escenario 2.
5. Cierre `cc:完了` (o permanece TODO con impediment si la corrección
   depende del host).
