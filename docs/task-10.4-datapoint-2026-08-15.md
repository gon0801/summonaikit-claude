# Task 10.4 — primer datapoint post-Phase 10 (2026-08-15)

NO es la medición de cierre de la 10.4: eso exige UNA task real comparable
corrida con `-saikit` (ceremonia completa) y UNA con `-saikit:fast`,
cronometradas con el método del transcript (gaps por evento, como la medición
2026-08-13). Esto es lo medible HOY, registrado para que la medición limpia
tenga contra qué compararse. La fila 10.4 queda `cc:TODO`.

## Costos medidos en las sesiones reales que ejecutaron la Phase 10 (zcode)

Ceremonia completa (carril full), tareas multi-repo con cambio de contrato:

- Ejecución de la Phase 10 (10.1–10.3, un implementer): **100 min / ~18.5M
  tokens / 122 tool uses**. Incluye la suite de 18 min UNA vez (regla de la
  fase respetada) y las auditorías de línea base.
- P0–P3 del retro (9.10 + 10.5, un implementer): **103 min / ~23.9M tokens /
  92 tool uses**, incluyendo la iteración del CI (3 corridas de `gh pr checks`).
- El turn de la Phase 7 de kimi + absorciones de drift + paridades 6.3–6.5
  (7 dispatches con 2 ciclos de revisión): **~88 min / ~14M tokens** sólo el
  implementer; verifier ~30 min (3 rondas), reviewer ~13 min (2 rondas).
- Lectura del patrón: el costo dominante sigue siendo el implementer que
  reconstruye contexto (la regla de briefings quirúrgicos del lado kimi
  ataca exactamente esto; su efecto se medirá cuando se use).

Contra el baseline 2026-08-13 (task unitaria ≈ 4 h: implementer 2h19 + verifier
58 m + reviewer 32 m; suite ×3): las sesiones de arriba NO son comparables
limpio (multi-repo, ciclos de revisión con hallazgos reales), pero ninguna
superó ~2h15 de suma de roles — y los hallazgos del reviewer eran defectos
reales (escotilla DELEGATED, ROLE FALLBACK, VERIFY_SKIP_RE, deploy viejo), no
ruido. La ceremonia encontró defectos en TODAS las rondas; el problema medido
era el costo, no el valor.

## Wins medidos duros (no estimados)

- **Suite en CI Linux (10.5, PR #18): ~18 min → 1m32s–1m38s** (−86%), checks
  verde. Local MSYS2 sigue siendo ~18 min; el CI corta el ciclo de revisión
  post-PR.
- **El gate de verificación vuelve a ser satisfible en hosts sin transcript**
  (9.10, PR #17): `bash tests/run.sh` ahora acredita `verified` — las dos
  sesiones de arriba cerraron sus turns con skip declarado por regex que no
  conocía el runner; ese camino muerto se cerró.
- **Roles acreditables en zcode**: matcher de PostToolUse con `Agent` (acción
  de operador, 2026-08-15, backup en settings) — los ROLE FALLBACK declarados
  en los receipts anteriores ya no deberían hacer falta.

## Pendiente para el cierre honesto de la 10.4

1. Task real comparable con `-saikit` (full) cronometrada por gaps de eventos.
2. Task real chica con `-saikit:fast` — todavía corrió NINGUNA: el carril se
   deployó el 2026-08-14 y no hubo uso real todavía. Objetivo: ≤ 15 min.
3. Objetivo full: ≤ 1 h. Con el CI en ~1.5 min y la suite una-vez-por-cambio
   ya en el contrato, la parte mecánica dejó de ser la excusa.
