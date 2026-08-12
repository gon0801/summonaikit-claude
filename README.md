# summonaikit-claude

Dueño del hook que gatea cada turno de Claude Code. La fuente vive acá
(`hooks/summonaikit-harness.sh`); el archivo que de verdad corre es
`~/.claude/hooks/summonaikit-harness.sh`, instalado entero con el marcador
`# SAIKIT-CLAUDE-OWNED`. El port de Kimi (`summonaikit-kimi`) extrae de ese
archivo vivo el contrato que le inyecta al modelo.

El contrato de producto está en `docs/spec/00-project-spec.md`. El ledger de
tareas, en `Plans.md`.

## Instalación

El archivo que gatea cada turno vive **fuera** del repo. No se sincroniza con
`cp`: un `cp` no distingue "el archivo de siempre" de "un cambio que nadie
miró", y no es atómico — un hook a medio escribir no rompe el turno que lo
instaló, rompe todos los siguientes.

```bash
bash tools/install-hook.sh              # instala en ~/.claude/hooks/summonaikit-harness.sh
bash tools/install-hook.sh --dry-run    # dice qué haría; no escribe
```

Tres estados, no dos (`tools/install-hook.sh`):

| Destino | Qué hace |
|---|---|
| **Nuestro** (línea 2 = `# SAIKIT-CLAUDE-OWNED …`) | Si es byte a byte la fuente, no reescribe. Si difiere, archiva y repara. |
| **Vendor conocido** (su sha256 está en `hooks/vendor-manifest.sha256`) | Archiva y reemplaza. |
| **Desconocido** (ninguna de las dos) | **No toca nada** y sale ≠ 0. "No es nuestro ⇒ sobrescribir" es cómo se destruye en silencio el cambio de otro. |

Cualquier exit ≠ 0 significa lo mismo: **el destino quedó intacto**. El
instalador es la excepción declarada al fail-open del spec: escribir a ciegas
sobre el archivo que gatea cada turno no admite "dejar pasar".

Después de instalar, el script corre `tools/check-hook-registration.sh` contra
el `settings.json` hermano del destino. Ese aviso es **advisory**: un archivo
perfecto con el registro roto deja el gate inexistente, y el verificador no
cambia el exit code del instalador.

`quality-kit` ya **no** parchea `.claude` (Task 4.1). Los parches del sentinel
y del aviso de revisión van adentro de la fuente de este repo.

## Staging por override

Estrenar una versión nueva en `~/.claude/hooks/` es estrenarla en producción,
en todos los repos a la vez. El staging pone esa versión en **un** repo
descartable y deja el resto del sistema como estaba.

```bash
bash tools/stage-override.sh <repo-descartable>
```

No es una preferencia del host. El comando **registrado** en `settings.json`
elige un solo hook por turno:

```bash
h="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/.claude/hooks/summonaikit-harness.sh"
[ -f "$h" ] || h="$HOME/.claude/hooks/summonaikit-harness.sh"
```

Consecuencias que importan (`tools/stage-override.sh`):

1. Corre **un** hook, no dos. Si existe el del repo, el global no corre.
2. El estado también queda aislado: el hook deriva `STATE_ROOT` de
   `dirname "$0"`, así que escribe en `<repo>/.claude/hooks/state/` y no toca
   el estado del perfil.
3. **Tiene que ser un repo git.** Sin `git rev-parse --show-toplevel` el
   archivo queda puesto y no corre nunca — un staging que miente. La
   herramienta lo rechaza (exit 2).
4. **No lee el registro para creerle: lo ejecuta.** Un `settings.json` al que
   le sacaron el fallback al proyecto se ve igual de bien en una lectura y
   deja el staging como ilusión (archivo puesto, turno gateado por el global).
   Si la medición no ve al override, exit 3 y no se afirma que funcione.
5. El hook global se mide antes y después. Si cambió, aborta.

Claude Code fotografía los hooks al **arrancar** la sesión. Después de un
staging limpio:

1. Abrí una sesión nueva de Claude Code **en ese repo**.
2. Un prompt con `-saikit` tiene que armar el harness; uno pelado, no.
3. El estado aparece en `<repo>/.claude/hooks/state/`. El global
   (`~/.claude/hooks/summonaikit-harness.sh`) tiene que seguir intacto.

Para sacar el staging: borra `<repo>/.claude/hooks/`, o
`bash tools/install-hook.sh --dest '<repo>/.claude/hooks/summonaikit-harness.sh' --restore-vendor`.

## `--restore-vendor`

La vuelta atrás vive en el **mismo** instalador, no en un script aparte: tiene
los mismos modos de falla que la ida.

```bash
bash tools/install-hook.sh --restore-vendor
bash tools/install-hook.sh --restore-vendor --dry-run
bash tools/install-hook.sh --dest <path> --restore-vendor   # p. ej. un staging
```

Elige el backup del vendor **más reciente** por el sello del nombre
(`<destdir>/saikit-backups/summonaikit-harness.sh.vendor.<YYYYmmdd-HHMMSS>.bak`),
no por orden alfabético. Valida ese archivo contra `hooks/vendor-manifest.sha256`,
archiva lo que había (deshacer tiene que ser reversible) y recién ahí publica.

Lo que se niega a hacer:

- No hay backup del vendor ⇒ exit **6**, no toca nada. Eso no es lo mismo que
  "no pude listar el directorio" (exit 4, `unknown`).
- Un destino **desconocido** no se pisa ni para deshacer. Que el comando se
  llame "restaurar" no lo habilita a destruir el cambio de otro.
- Un backup cuyo hash no está en el manifiesto no se restaura (sería instalar
  en la ruta que gatea cada turno un archivo que nadie miró).
- Si el destino ya es byte a byte ese backup, no reescribe.

`--restore-vendor` no inventa un vendor: solo pone de vuelta un backup que
**este** instalador archivó en una ida anterior. Si nunca se instaló encima de
un vendor conocido, no hay nada que restaurar.

## El gate es advisory — no es un control de seguridad

El hook **no es un control de seguridad**. Aun corregidos A1 (ya no se inventa
un rol desde el *resultado* de una herramienta) y A2 (ya no cuenta un recibo o
una pausa que viven adentro de un `tool_result`), **quien controla el texto
del turno puede influirlo**.

Concretamente, sigue pudiendo:

- Nombrar el rol que quiera en el `tool_input` de un evento de delegación. A1
  cerró que lo haga desde el resultado; no cerró que lo haga desde el input.
- Escribir un recibo que cite un runner (`pytest`, `tsc`, …) sin haberlo
  corrido. El gate acredita palabras, no procesos.
- Omitir un subagente de solo lectura: esos eventos no llegan y su rol no se
  registra.

Si el hook no puede medir algo, **deja pasar** (fail-open). Un gate que
bloquea sin evidencia es peor que ninguno. No lo uses como si impidiera a un
adversario — ni al modelo que escribe el turno — hacer lo que quiera con el
texto. Se documenta. No se promete lo contrario.

El detalle de cada agujero cerrado y de los que quedan está en
`docs/spec/00-project-spec.md` (Non-Goals y la tabla de defectos).

## Verificación

```bash
bash tests/run.sh                         # suite del repo (gate final)
pre-commit run --all-files                # candados; jamás --no-verify
bash tools/check-hook-registration.sh     # ¿settings.json todavía nombra al hook?
```

El TDD rojo/verde se hace sobre **un** archivo de test, no sobre `tests/run.sh`.
`run.sh` es el gate final. Sin `SAIKIT_HOOK_VIVO` apuntando a la fuente, la
suite mide el hook **instalado**, no el que estás editando.

## Relacionados

- `docs/spec/00-project-spec.md` — contrato de producto
- `Plans.md` — ledger
- `gon0801/summonaikit-kimi` — port a Kimi CLI; lee el contrato de este hook vivo
- `gon0801/quality-kit` — candados y heal del sentinel de Codex/Cursor/`.agents`
  (Claude ya no: este repo instala el hook entero)
