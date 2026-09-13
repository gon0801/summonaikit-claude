# Review RONDA 2 — 20.21 (PR #312, commit cb10e2e) — reviewer kimi/k3, 2026-09-13

Diff revisado: 893d10d..cb10e2e (origin/docs-20.21-costo-latencia-16.7).
20.22: APPROVE de ronda 1, NO re-revisado. NO se re-midio nada, NO se aplico fix.

## Alcance
git diff --name-only 76e92bb..origin/docs-20.21-costo-latencia-16.7:
  docs/evidence/phase-20/20.21/README.md
  docs/evidence/phase-20/20.21/api-fresca-ci-runs-34446791997-34446794447.txt
Solo 20.21 (2 archivos). Plans.md intacto. PR #313 (20.22) no tocado.

## Veredicto por hallazgo de ronda 1

M1 (tokens/roles) — RESUELTO DE VERDAD. Columna "Tokens in / caché / out (tot)"
en las 3 tablas (README L59/66/74). Verifiqué los 7 JSON primarios (no muestra:
TODOS) con jq '.usage':
- deny:    4 / 24859+44137=68996 / 955  → tot 69955   == README ✓
- allow:   4 / 22867+46942=69809 / 528  → tot 70341   == README ✓
- t1:    106 / 98665+3978730=4077395 / 37224 → 4114725 == README ✓
- t2:     86 / 64754+6287716=6352470 / 42451 → 6395007 == README ✓
- TOTAL 20.10: 192 / 10429865 / 79675 (10509732) — sumas exactas ✓
- revisar:    34 / 91312+1052638=1143950 / 31260 → 1175244 ✓
- solo-hilos: 356 / 83375+795716=879091 / 34344 → 913791 ✓
- cuidar:     548 / 81458+1096541=1177999 / 27344 → 1205891 ✓
Unknown por rol y por etapa declarado con razon REAL: verifiqué que
usage.iterations tiene length 1 en cada JSON y no suma al total (deny:
1 entrada input=2 vs total 4/68996). Replicado en L150-151 y veredicto
L158-160. Convencion cache = cache_creation + cache_read declarada en L49-55.

M2 (API fresca) — RESUELTO. Artifact nuevo existe en la rama y contiene la
salida de gh api …/actions/runs/<id>/jobs de AMBOS runs. Duraciones contra el
propio artifact: run 34446791997 started 06:47:16 → completed 06:47:22 = 6 s;
run 34446794447 06:47:18 → 06:47:21 = 3 s. Encabezado con fecha 2026-09-13 y
comando. Coincide con ../20.11/runs/pr4-after-cuidar.txt ya mergeado (mismos
run IDs, 6s/3s, head df8b9b1). Encabezado L4-7 declara la UNA excepcion a la
regla de reutilizacion. Citado en L78 y L142-145.

M3 (contradiccion 20.11) — RESUELTO. NOTA en L80-86 declara ~7/~7/~8 del
README de 20.11 (verificado: L61-63 de ese README) vs 18.1/11.1/10.3 de los
primarios, dice que 20.21 usa primarios y que costos 4.80/4.39/4.20 coinciden
en ambas fuentes (verificado en 20.11 README L61-63).

m1 (spread) — RESUELTO. L129-131: "spread máx-mín 14,3 %". Verificado:
4.7979260/4.1981789 = 1.1429 → 14,3 % max-a-min. Redaccion correcta.

m2 (cita literal runbook) — RESUELTO. L22-30 cita literal: "La evidencia 20.x
de una fila solo se reutiliza en otra si coincide checkout y hook SHA (misma
regla que exige 20.25)" — coincide palabra por palabra con
docs/phase20-mediciones-runbook.md (el texto vive en L51-53 del runbook: la
frase arranca al final de L51). EXCEPCION DECLARADA: checkout no coincide
(8e7402e/d89a4ad/60d1ee9), solo hook; justificacion explicita (hook identico
= mecanismo medido, drift declarada por evidencia).

## Chequeo de regresion
- Consistencia interna: la excepcion del encabezado (L4-7), la cita en tabla
  (L78) y el unknown (L142-145) nombran el mismo artifact; TOTAL 20.10 de
  tokens suma; ninguna cifra nueva sin fuente.
- Alcance limpio (ver arriba); base 76e92bb; PR #312 = docs-only.

## Observaciones menores (NOTED, no bloquean)
n1. El puntero "runbook L51-52" (README L22) queda corto: la cita literal
    ocupa L51-53 (el parentesis "(misma regla que exige 20.25)" esta en L53).
    La CITA es verbatim; solo el rango de lineas quedo en 2 en vez de 3.
    (Yo mismo pase ese rango en ronda 1.) Cosmetico.
n2. El encabezado del artifact declara un comando con --jq que proyecta
    {name, conclusion, started_at, completed_at}, pero el contenido preservado
    es el JSON COMPLETO sin filtrar. Re-correr el comando tal cual no
    reproduce el artifact byte a byte (produce un subconjunto). El artifact
    preserva MAS que el comando: evidencia intacta, trazabilidad cosmetica.

## VEREDICTO RONDA 2: 20.21 — APPROVE
Los 5 hallazgos resueltos de verdad, cifras exactas contra primarios, sin
regresion, alcance limpio.
