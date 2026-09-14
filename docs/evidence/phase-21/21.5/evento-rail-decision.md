# 21.5 — Decisión sobre los residuales del raíl de EVENTO (20.28)

Candidatas heredadas de 20.28: las dos formas del raíl de EVENTO
(`VAR=… bash tests/run.sh` no acredita por el ancla `^`;
`bash tests/run.sh | tail` acredita con el exit del `tail`).

**Decisión: EXCLUIDAS de 21.5.**

Motivo medido, no supuesto: el preflight y su corpus escriben evidencia
directa a archivo (`> log 2>&1`) y nunca por pipe; ninguna de sus
aserciones depende de la forma de invocación de `tests/run.sh`. El raíl
afecta por igual a todos los tests del repo y su corrección pertenece a
una fila propia (sigue en `evento-rail-residuales.md` de 20.28). No se
tapa: queda declarado aquí y en el PR.
