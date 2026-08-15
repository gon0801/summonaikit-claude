<!-- >>> QUALITY-KIT CALIDAD SECTION START -- managed by quality-kit's init-repo.ps1. Do not hand-edit between these markers; re-running init-repo.ps1 will refresh this block cleanly. -->
## Calidad (quality-kit)

Candados de commit instalados (pre-commit):
- base (limpieza de archivos)

Comandos para correr los candados a mano:
- `pre-commit run --all-files` (todos los candados de commit)

Reglas de hierro:
1. Si un candado falla, se arregla el problema real -- JAMAS se usa `--no-verify` ni se saltea un candado.
2. Cada bug arreglado incluye, en el mismo cambio, una prueba que lo habria atrapado.
<!-- >>> QUALITY-KIT CALIDAD SECTION END -->

## Reglas de eficiencia (loop de tests)

La suite completa (`tests/run.sh`) tarda ~18 min en Git Bash porque el hook
lanza ~40-80 forks por evento (sed/awk/grep/cksum/tail/tr/cut encadenados) y cada
fork cuesta ~28 ms en MSYS2 (en Linux nativo el mismo fork es ~0.1 ms). El cuello
es el fork de MSYS, no la logica del hook.

1. **El TDD rojo/verde se hace sobre UN archivo de test, no sobre `tests/run.sh`.**
   Para rojo/verde durante el desarrollo, correr el test suelto en su
   sandbox (copia el env de `tests/run.sh`: `HOME`, `TMPDIR`, `USERPROFILE` y
   `SAIKIT_HOOK_VIVO="$PWD/hooks/summonaikit-harness.sh"`). Sin `SAIKIT_HOOK_VIVO`
   apuntando a la fuente, el runner mide el hook **instalado** y no el que estas
   editando (leccion de la Task 3.5, CORRECCION 4).
2. **`pre-commit`: staged-only durante la iteracion, `--all-files` para el gate
   final.** Durante el dev, `pre-commit run` (solo staged) o
   `pre-commit run --files <los que tocaste>`; `--all-files` escanea el repo
   entero y sobra salvo en el gate final. `--no-verify` jamas (regla de hierro).
3. **WSL NO es una regla global para este repo.** El hook es MSYS-dependiente
   (`cygpath`, el mount virtual `/tmp`, la normalizacion `cd "C:\..." && pwd` ->
   `/c/...` que es lo que cierra A6/Task 3.6): correr la suite en WSL validaria los
   tests POSIX pero NO la forma Windows de los paths, y la baseline `--check` no lo
   atrapa — los escenarios usan rutas POSIX del sandbox, asi que WSL daria limpio
   sin divergencia y se pierde cobertura sin enterarse. Si algun dia se usa WSL, es
   por caso especifico POSIX-only con la salvedad declarada, no como atajo general.

## Gate final: CI Linux, no la suite local (politica 2026-08-15)

El job `suite` del CI (Task 10.5) corre `tests/run.sh` COMPLETO en ubuntu en
~1m32s, en CADA push/PR. Correr ademas la suite completa en local (~20 min por
el fork de MSYS) es pagar dos veces lo mismo — medido 2026-08-15: dos sesiones
paralelas gastaron ~2 h de pared en suites locales serializadas por el candado.

1. **Local, por cambio: SOLO lo acotado.** Rojo/verde con el driver suelto
   (regla 1 de arriba) + la bateria de mutaciones ACOTADA a las lineas tocadas
   (`SAIKIT_MUTACIONES='...' bash tests/test_gate_mutations.sh`). ~1-3 min.
2. **El gate final de una task/PR es el job `suite` del CI en verde.** El
   cierre en Plans.md cita ese run de Actions donde antes citaba la corrida
   local. La suite completa local queda como opcion (medir la forma Windows
   entera), no como requisito.
3. **Excepcion Windows-bound:** si el cambio toca lo que el CI saltea con
   `SAIKIT_CI_LINUX=1` (install/capture/probe/hook-acl — el runner los NOMBRA
   en su output), correr ESOS archivos de test sueltos en local, ademas del CI.
4. **Candado de una-sola-suite** (sesiones paralelas): aplica a corridas
   locales pesadas. Antes de declarar "ocupado", distinguir corredor REAL de
   huerfano: fecha de inicio del proceso y que el arbol de su command line
   exista. Un stop de tarea NO mata el arbol de procesos — al abortar una
   suite, matar explicitamente el `bash tests/run.sh` hijo, o el zombi hereda
   el candado (medido 2026-08-15: una hora de espera detras de un huerfano).

## Deploy tras merge

El artefacto de produccion de este repo es el **gate hook** instalado en el
perfil vivo (`~/.claude/hooks/summonaikit-harness.sh`), no una app. Tras cada
merge a `master` (cierre de task o PR), **siempre**:

1. Sincronizar master local: `git checkout master && git pull --ff-only`.
2. **Deployar:** `bash tools/install-hook.sh` (garantiza vivo == master; tres
   estados, no pisa nada ajeno) y `bash tools/check-hook-registration.sh`
   (verifica registro en las 3 fases; fail-open, reporta por texto).
3. **Apuntarlo:** agregar entrada a `docs/deploy-log.md` (fecha, que se mergeo,
   resultado del deploy, si el hook cambio o fue no-op).

Si el merge NO toco `hooks/summonaikit-harness.sh`, el deploy es no-op ("YA AL
DIA") — igual se corre y se registra, para no perder la costumbre y detectar
deriva del vivo respecto a master.
