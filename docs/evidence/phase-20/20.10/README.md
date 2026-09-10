# 20.10 — Autopilot completo en Claude

Medición viva. Destino: `gon0801/saikit-descartable`. Host: Claude Code
`2.1.267` (headless `-p`, `bypassPermissions`). Conductor: el lead (sesión
kimi), patrón 18.9. Caso: bump `app.sh` 1.1.1 → 1.1.2, desde sentinel
`-saikit:autopilot` hasta merge por tool y postmerge. Setup pre-existente
(18.9/20.14): `tools/` del kit + `.saikit/autopilot.json`
(`merge=true, despliega=no, sin_verify_app=si, rama=main`), re-verificado.

## Identidad

| Campo | Valor |
|---|---|
| Fecha | 2026-09-09 (PDT) |
| Checkout kit | `d89a4ad…` (master post-#293; hook sin cambios desde `37e55640…`, 4345 líneas) |
| Hook vivo claude | sha256 `37e55640003afaff6d4a54cf6495afc73bec5799b86323fb7a317889fec78680` |
| Lab | clone aislado `/tmp/saikit-20.10-20260909-223318/repo` |
| Sesión Claude | `906437b6-a254-4df9-94a9-7f2785ebb4cf` (2 turnos, `--resume`) |

## Cadena observada

| Paso | Evidencia | Resultado |
|---|---|---|
| Sentinel → ceremonia | `runs/turn1.json` | `-saikit:autopilot` armó la ceremonia completa: implementer → verifier → reviewer (61 turnos, 12.6 min, USD 5.10) |
| PR + CI | PR **#9** `chore/bump-1.1.2` | OPEN, CI verde (2 runs `test` + CodeRabbit) |
| Sello | `.saikit/veredictos/f40cbdce…json` (turno 1), re-sellado `7397859d…` (turno 2) | `veredicto_validar` rc=0; `reviewer: clean` |
| LISTO no publica | `runs/turn1.json` result | el agente **paró y preguntó** «¿Mergeo el PR #9?» con dry-run NO-MERGE reportado literal |
| Hallazgo del gate | `runs/turn1.json` result | NO-MERGE: el blast `bash tests/test_app.sh` no figura `verified:` en el evidence log (el hook solo reconoce `tests/run.sh` / pytest / jest) |
| Decisión del operador | opción **(b)** | wrapper `tests/run.sh` en PR aparte primero |
| Candado anti-force-push | `runs/turn2-denials.txt` | el harness negó `git push --force` («History-destroying operations are forbidden»); el agente NO lo esquivó: integró la base con merge commit y lo declaró |
| PR wrapper | PR **#10** `chore: tests/run.sh…` | APPROVE sellado (`e0347274…`), CI verde |
| sí → merge (×2) | `runs/turn2.json` | ambos merges SOLO por `tools/saikit-merge.sh --confirmado`, tras sí explícito del operador; sin `gh pr merge` |
| SHA exacto + trailer | `runs/remote-verify.txt` | PR #10 → `9158e44c…` trailer `Saikit-Merge: e0347274…`; PR #9 → `8011fc2f…` trailer `Saikit-Merge: 7397859d…` — los trailers son los sha sellados |
| Postmerge | `runs/turn2.json` result | VERDE en ambos (exit 0; sin URL de salud; nada que deshacer) |
| Remoto final | `runs/remote-verify.txt` (API) | `main` = `8011fc2f…`, `app.sh` = 1.1.2, `tests/run.sh` presente, PRs #9/#10 MERGED |

Costo total medido: turno 1 USD 5.10 (61 turnos) + turno 2 USD 7.30 (46
turnos) ≈ USD 12.40, ~31.5 min de pared. Autorización §8 vigente citada en el
preflight de 20.9 (mismo bloque); rastro en `.saikit/decisiones/*.tsv` y
`.saikit/findings/blast-*.json` de cada PR (commiteados en el descartable);
blast con poder discriminante medido (wrapper roto a propósito → exit 1);
adjudicación del hallazgo del gate: opción (b) del operador.

## Qué NO se hizo

- Sin merge manual ni `gh pr merge` a pelo (los dos merges los hizo la tool
  con `--confirmado`, tras re-correr el gate completo).
- Sin force-push ni reescritura de historia (el candado lo negó y no se evadió).
- Unknown no cierra: los dos turnos terminaron `subtype: success` con recibo
  completo; no hubo tramo no observado.

## Residuales declarados

1. **Hallazgo (fila candidata)**: el gate de merge exige el blast como
   `verified:` en el evidence log y el hook solo reconoce `tests/run.sh` /
   pytest / jest — un repo con otro nombre de batería no puede mergear nunca.
   Resuelto en el descartable con el wrapper (PR #10); queda la pregunta de
   diseño para el kit (¿documentar la convención o ampliar el reconocimiento?).
2. **El test del descartable no discrimina el bump** (`grep '^app v1'` pasa
   con 1.1.1 y 1.1.2): declarado por los tres reviewers; el poder
   discriminante se midió aparte (`grep -qx 'app v1.1.2'`).
3. El rastro/blast del PR #9 dice «rebase» donde el mecanismo fue merge
   commit (el harness prohíbe force-push): los hechos son ciertos, lo
   impreciso es el nombre; declarado por el reviewer, no corregido porque el
   blast se copia literal al veredicto sellado.
4. Dos veredictos obsoletos (`f40cbdce…`, `f238b176…`) quedaron sin trackear
   en `.saikit/veredictos/` del lab; el gate los recorrería si no encontrara
   veredicto para el HEAD (comportamiento a conocer, no ejercido).
5. Contexto 20.14: su blast `bash tests/run.sh` corrió sobre un wrapper
   **local del lab** que nunca se commiteó (`implemented: …/tests/run.sh` en
   `parent-evidence.log.observed`); el gate pasó legítimamente en el lab.
6. Denials del turno 1: dos escrituras a `~/.claude/…/memory` fuera del cwd
   (permisos del host, no del kit) y un grep compuesto; el agente las rodeó
   declarando, sin impacto en la cadena.

## Veredicto de la fila

Cadena completa observada y verificada contra la API: sentinel → setup →
PR → CI → sello → LISTO (sin publicar) → sí explícito → merge por tool con
SHA exacto y trailer (×2) → postmerge VERDE. DoD completa. Lista para cierre
del lead.
