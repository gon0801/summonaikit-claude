# Smoke verificación real — 2026-08-31 (Task 17.5, medición viva)

Medición viva de la **lane de app real** (17.1–17.4): dos turnos `-saikit`
tecleados por el **operador** (quien escribió la skill y los perfiles no es
quien los mide) en dos repos laboratorio descartables. El lead preparó los
labs y adjudicó la evidencia leyendo los transcripts como **UTF-8**.

- Lab node: `C:/dev/saikit-verif-lab-node` — sesión `d2959d1d`
- Lab python: `C:/dev/saikit-verif-lab-py` — sesión `07fdabb0`

## Parte A — Laboratorios (estado ANTES de los turnos)

- **Apps:** node (`app.js` http sin dependencias, `/health` + `/sumar`,
  `npm test` = `node --test test/app.test.cjs`, commit `5fc077e`); python
  (`app.py` stdlib http.server, `/health` + `/tasks`, pytest 2 passed,
  commit `c070bf4`).
- **Hook stageado por override** (`bash tools/stage-override.sh <lab>`,
  exit 0 en ambos = instalado y MEDIDO que el registro prefiere el override;
  el global quedó intacto). Fuente: master en `bdf8db2d`.
- **Skill `saikit-verificar-app` a nivel PROYECTO** (`<lab>/.claude/skills/`),
  no en el perfil — instalarla al perfil es de 17.6.
- **Tools del rastro/blast copiados A MANO** a `<lab>/tools/`
  (`saikit-decision.sh`, `saikit-blast.sh`, `lib/redactar.sh`).
  **Gap declarado:** `install-hook.sh` no los planta en repos de usuario
  (0 referencias, medido con grep) — sin este copiado manual, el comando
  `bash tools/saikit-blast.sh` que enseña `agents/verifier.md` no existe
  en el repo de un usuario. Va a 17.6.
- Todo verificado **byte a byte** contra el repo antes de los turnos
  (hook, SKILL.md, tools: diff vacío en ambos labs).
- **Prompts del operador:** piden la función nueva + generar `verify/` con la
  skill "y deja su evidencia". **A propósito NO mencionan rastro ni blast**:
  si aparecen, los jalaron los perfiles; si no aparecen, esa maquinaria no
  se dispara sola — eso es lo que se mide.

## Parte B — Evidencia de los dos turnos

### Lo que SÍ pasó (los dos turnos, citas de transcript y disco)

- **Receta declarada:** `Receta: funcion` en el Understand de ambos recibos.
- **Carril full con los tres roles:** implementer, verifier y reviewer
  despachados en ambos (eventos de `subagent_type` en el transcript);
  adversary no (opt-in, cambios sin su umbral — correcto).
- **`verify/` generado por la skill en ambos labs** (7 archivos: LEEME,
  Launch, Doctor, Drive, Evidence, Cleanup + el test del Drive), con
  **sello real**: node `generado: 2026-08-31 · 05942cd…` (el sha del commit
  de staging del lab, el último al generar), python `generado: 2026-08-31 ·
  af556b8…` (commit propio del turno). `verify_app: drive` en ambos.
- **El Drive corrió y el hook lo acreditó como verificación** (evento de
  prosa en el recibo, DoD):
  - node — recibo: «Verify: Verifier subagent, real commands: …
    `npm test -- verify/drive.test.cjs` → 8/8 pass, output pasted into
    `verify/Evidence.txt`; live surface with the app running on PORT=3998
    via curl». El comando envuelve `node --test` en `npm test` e incluye
    `verify/` — exactamente la regla de la skill. Nivel de superficie REAL
    además del Drive (curl a la app viva).
  - python — recibo: «Verify: VERIFIED BY SUBAGENT: `python -m pytest -q` →
    "Pytest: 14 passed" … (8 unitarios + 6 del Drive) corrida UNA vez por el
    subagente verifier». `COMANDO_DRIVE: pytest verify/` (acreditable por
    `TEST_RUNNER_RE`), `Evidence.txt` con la corrida (`Pytest: 6 passed`) y
    la **nota honesta** de que el canal de esta máquina comprime la salida.
- **El sello se reporta vivo:** el recibo python declara «`estado` del mapa:
  `desactualizado` con antigüedad de 0 días y exactamente 1 commit — el
  sello (af556b8) apunta al último commit de código» — el reporte de
  antigüedad de 17.1 funciona en un turno real.
- Ambos turnos cerraron limpio (recibo completo, candados pre-commit verdes
  declarados en el Close del lab python).

### Lo que NO pasó (medido como AUSENTE, no unknown)

- **Ni rastro ni blast en ningún lab:** `.saikit/` no existe en ninguno de
  los dos repos (verificado en disco tras los turnos).
- **Los tools jamás se invocaron:** `saikit-decision` y `saikit-blast`
  aparecen exactamente 1 vez por transcript, y esa mención es un LISTADO de
  archivos del repo (evento user), no una invocación ni texto de perfil
  leído. Nadie los corrió; nadie lo declaró como skip.
- Consecuencia directa: el punto de la DoD «el tsv y el blast existen y el
  reviewer los adjudicó» **NO se cumplió**. Los perfiles desplegados
  (`verifier.md` con el paso del hecho único, el contrato de 17.3 con el
  `Close:` citando la ruta del tsv) no bastaron para que la maquinaria se
  disparara sola en un turno vivo: el hook es advisory y nada del contrato
  inyectado EXIGE esos artefactos hoy.

## Veredicto de la medición

La **lane de app real (17.1 + 17.2) funciona en vivo de punta a punta**:
skill → `verify/` con sello real → Drive acreditable corrido → evidencia en
el recibo → sello reportado. Los dos hallazgos estructurales son:

1. **El rastro (17.3) y el blast (17.4) no se disparan solos** en un turno
   vivo — perfiles y contrato los describen, nada los jala. Sin esto, el
   autopilot de la Phase 18 no tendrá el hecho único (D13) que su
   adjudicación necesita.
2. **El instalador no planta los tools** en el repo del usuario — sin el
   copiado manual del lab ni siquiera se PUEDEN correr.

Lo no observado en esta medición queda `unknown`; lo de arriba no es
unknown — es ausencia medida.
