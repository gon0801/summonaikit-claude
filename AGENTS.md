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
   `run.sh` es el gate FINAL pre-commit: se corre una sola vez por cambio, al
   final. Para rojo/verde durante el desarrollo, correr el test suelto en su
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
