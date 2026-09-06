# 18.12 — cierre de hallazgos de revision

Revision de `ca7a87f`; correcciones autorizadas por el operador el 2026-09-05.
La rama incorpora `origin/master` mediante `50ec183` antes de estos fixes.
No se modifica `Plans.md` ni se instala en perfiles vivos.

## Decisiones

- La limpieza no recorre `saikit-tools/lib` si `saikit-tools` es un enlace.
  El caso usa una copia desechable de `redactar.sh` fuera del destino y exige
  que quede byte a byte intacta.
- El gate compara el padre fisico del artefacto con `ADV_PROJECT_CANON`,
  que ya normaliza la raiz para Darwin/MSYS. No acredita archivos finales
  symlink; un directorio enlazado que siga dentro del proyecto si es valido.
- Codex y dsh publican los tres tools antes de publicar el hook. Se cubren
  instalacion fresca, no-op sin tools, dry-run y rechazo de destino enlazado.
  Cada host escribe un TSV y un blast con los comandos instalados reales.
- El preflight de symlinks de Claude sigue fallando cerrado. El hallazgo
  previo del adversary sobre ese rechazo no se convierte en permiso para
  atravesar enlaces ni publicar una instalacion aparentemente completa.

## Rojo medido antes del cambio de produccion

`SAIKIT_HOOK_VIVO="$PWD/hooks/summonaikit-harness.sh" bash tests/test_trail_gate.sh`
(el lab copia el hook y aisla HOME/USERPROFILE/temporal):

```text
FAIL: directorio enlazado afuera exit: esperaba [2], dio [0]
ROJO: full_cita_directorio_externo_bloquea
FAIL: archivo enlazado afuera exit: esperaba [2], dio [0]
ROJO: full_cita_archivo_externo_bloquea
test_trail_gate: FAIL
```

Exit 1. `bash tests/test_trail_install.sh` (HOME desechable propio):

```text
FAIL: codex: falta o difiere saikit-decision.sh
FAIL: codex: declaro exito sin poder plantar tools
FAIL: codex: publico hook con tools fallidos
FAIL: dsh: falta o difiere saikit-decision.sh
FAIL: dsh: declaro exito sin poder plantar tools
FAIL: dsh: publico hook con tools fallidos
FAIL: quitar borro o cambio el redactar externo a traves del enlace padre
test_trail_install: FAIL
```

Exit 1. Extractos literales de ambas corridas; se omiten aserciones repetidas.

## Verde y poder discriminante medidos

Los mismos dos comandos: exit 0, `test_trail_gate: OK` (20 casos) y
`test_trail_install: OK`.

```bash
SAIKIT_HOOK_VIVO="$PWD/hooks/summonaikit-harness.sh" \
  SAIKIT_MUTACIONES="$(rg '^G8\|' tests/test_gate_mutations.sh)" \
  bash tests/test_gate_mutations.sh
bash tests/test_trail_install_mutations.sh
bash tools/golden-harness.sh --check --hook "$PWD/hooks/summonaikit-harness.sh"
/tmp/saikit-drive-venv/bin/pytest verify/
```

Todos exit 0. G8: 15 mutaciones atrapadas; las dos nuevas por sus casos
`full_cita_directorio_externo_bloquea` y `full_cita_archivo_externo_bloquea`.
Salida literal del driver de mutaciones del instalador:

```text
ATRAPADA quitar_padre: quitar borro o cambio el redactar externo
ATRAPADA omitir_codex: codex: falta o difiere saikit-decision.sh
ATRAPADA omitir_dsh: dsh: falta o difiere saikit-decision.sh
ATRAPADA ignorar_error: codex: declaro exito sin poder plantar tools
test_trail_install_mutations: OK (4 mutaciones)
```

Golden: `golden-harness: OK — 57 escenarios se comportan igual que la linea base`.
Drive: `5 passed in 0.90s` en macOS, pytest 8.4.2 / Python 3.14.7.
`bash tests/test_install_hook.sh`: exit 0, `test_install_hook: OK`.
`golden-harness.sh --record --hook "$PWD/hooks/summonaikit-harness.sh"`:
57 escenarios grabados; el diff de este follow-up cambia solo las tres
lineas de identidad del hook, no el comportamiento grabado.
El gate agregado del CI sigue siendo la condicion de entrega del PR;
estas corridas locales no lo sustituyen.

## Revision independiente acotada

Una ronda sobre `50ec183..da88cb9`. Un hallazgo P2: el publisher generico
conservaba un tool individual `DESCONOCIDO` y devolvia 0. Medido por el reviewer:
symlink roto en decision -> install 0 / comando 127; en redactor -> install 0 /
comando 2. Sin otros hallazgos en el alcance revisado.

Se agregaron casos para cada uno de los tres destinos, con symlink roto y
archivo ajeno, tanto en Codex como en dsh. Rojo propio previo al fix (extracto):

```text
FAIL: codex: acepto tool enlace saikit-decision.sh
FAIL: codex: publico hook con tool enlace saikit-decision.sh
FAIL: codex: acepto tool ajeno saikit-decision.sh
FAIL: dsh: acepto tool enlace lib/redactar.sh
FAIL: dsh: publico hook con tool enlace lib/redactar.sh
test_trail_install: FAIL
```

Exit 1. El preflight compartido ahora rechaza `DESCONOCIDO`/`NO_OBSERVABLE`
antes de publicar cualquiera de los tres tools, preservando el conflicto.
Se agrega la mutacion `omitir_clasificacion` para exigir este rechazo.
Hubo cambio de codigo despues de la revision para cerrar ese hallazgo;
no se despacho otra ronda.

Verde posterior al fix: `test_trail_install: OK` (exit 0) y
`test_trail_install_mutations: OK (5 mutaciones)` (exit 0), incluida:

```text
ATRAPADA omitir_clasificacion: codex: acepto tool enlace saikit-decision.sh
```
