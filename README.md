# summonaikit-claude

Dueño del hook que gatea cada turno de Claude Code. La fuente vive acá
(`hooks/summonaikit-harness.sh`); el archivo que de verdad corre es
`~/.claude/hooks/summonaikit-harness.sh`, instalado entero con el marcador
`# SAIKIT-CLAUDE-OWNED`. El port de Kimi (`summonaikit-kimi`) extrae de ese
archivo vivo el contrato que le inyecta al modelo.

El contrato de producto está en `docs/spec/00-project-spec.md`. El ledger de
tareas, en `Plans.md`.

**Si no vas a leer código:** `docs/guia-usuario.html` explica en palabras
normales qué se escribe y qué hace el sistema solo — las palabras que lo
activan, las recetas, quién revisa y hasta dónde llega. Este README es para
quien lee código; la guía es para quien lo usa. No se duplican a propósito: si
las dos explican lo mismo, una de las dos va a envejecer mal.

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

### Perfiles de agente por rol (Phase 12)

Además del hook, el instalador también puede plantar los cuatro perfiles de rol
(`implementer`, `verifier`, `reviewer`, `adversary`) con el modelo y el
`effort` que le corresponden por rol, resueltos en `tools/model-routing.sh`.

`adversary` es un cuarto rol opt-in: solo corre cuando el lead lo despacha a
propósito, en cambios delicados (autenticación, pagos, datos ya existentes, o
el propio hook). Cuando corre, escribe lo que encuentra en un archivo aparte
— dentro del repo pero invisible para git, nunca en el código — y es el
reviewer, no él mismo, quien decide si cada hallazgo cuenta de verdad. Sin
invocación, nada cambia.

```bash
bash tools/install-hook.sh --host claude   # perfiles de agente en ~/.claude/agents
bash tools/install-hook.sh --host kimi     # perfiles de agente en ~/.agents/agents
bash tools/install-hook.sh --host claude --dry-run   # dice que HARIA por rol; no escribe
bash tools/install-hook.sh --host kimi --dry-run     # idem, sobre ~/.agents/agents
bash tools/install-hook.sh --host dsh       # gate en el DeepSeek Harness (Phase 15)
bash tools/install-hook.sh --host dsh --dry-run --quitar-dsh   # dice que HARIA al quitar
```

`--host dsh` publica el gate en el **DeepSeek Harness** (`@deepseek-ai/dsh`),
que no tiene hooks de shell: el gate se compone como un **plugin cordis** en
`~/.dsh/cordis.patch.yml` entre marcas propias. El instalador escribe:

1. el hook bash en `~/.dsh/hooks/`;
2. el paquete adaptador `@summonaikit/dsh-gate` en
   `~/.dsh/profiles/node_modules/@summonaikit/dsh-gate/` (el flat module fallback
   de dsh: ahí es donde dsh resuelve los plugins custom por nombre. Los 4
   archivos de `hosts/dsh/` se copian como dir real, no symlink — en MSYS `ln -s`
   no crea symlinks reales y dsh falla con `ERR_UNSUPPORTED_ESM_URL_SCHEME` si se
   referencia el plugin por ruta `C:/...` en Windows);
3. la entrada del plugin en `~/.dsh/cordis.patch.yml` (bloque entre marcas) con
   `name: '@summonaikit/dsh-gate'` (nombre de paquete, no ruta);
4. las 4 personas de rol como **instancias `@deepseek-ai/dsh-tool-subagent`** en
   la MISMA entrada del patch. dsh **no** tiene archivos de persona: la persona
   es `config.persona` (texto) aplicada al hijo, así que cada rol es una
   instancia `subagent_<rol>` con su propia persona.
5. La versión de dsh (si difiere de `summonaikit.measuredAgainst`) se reporta;
   no se aborta.

`--quitar-dsh` retira hook + plugin + entrada del patch (con backup, respetando
contenido ajeno fuera de marcas). El verificador de ese host es
`bash tools/check-hook-registration.sh --dsh-home ~/.dsh` (silencio = completo;
el registro en dsh no es un archivo de hooks, es la entrada del patch).

Estos dos hosts no llevan la marca `saikit_owned` en los perfiles del vendor,
así que la máquina de tres estados de arriba se amplía a un **cuarto
estado**, `VENDOR_CONOCIDO`, con la misma vía de adopción que ya tiene el
hook (`agents/vendor-manifest.sha256`):

| Estado | Qué hace |
|---|---|
| **Ausente** | Instala el perfil ruteado y lo marca `saikit_owned`. |
| **Nuestro, idéntico** | No reescribe. |
| **Nuestro, distinto** | Archiva y repara. |
| **Vendor conocido** (su sha256 está en `agents/vendor-manifest.sha256`) | Archiva y **reemplaza**. |
| **Desconocido** (ni marca ni hash de vendor conocido) | **No toca nada** y reporta — puede ser un cambio legítimo. **Esto no es un error**: el comando reporta y sale 0 por diseño (no tocar el cambio de otro no es un fallo del comando). Auditar la salida (o correr `--refrescar-manifiesto`) es el paso humano que sigue. |

Los CUATRO perfiles se clasifican ANTES de escribir ninguno: si cualquiera de
`implementer`/`verifier`/`reviewer`/`adversary` no se puede clasificar
(manifiesto o destino no observables), la corrida entera sale sin tocar nada —
nunca deja una instalación a medias (Task 12.9). `adversary` es kit-owned y no
tiene entrada propia en el manifiesto de vendor: un archivo ajeno con ese
nombre siempre clasifica `DESCONOCIDO` (Task 13.8).

`--host kimi` **no** instala ruteo de modelo ni de `effort`: kimi no acepta
esas claves por agente (medido en la Task 12.3, ver `docs/spec/00-project-spec.md`
§Ampliación de propiedad — Phase 12), así que ese `--host` sólo posesiona el
archivo y saca el `model: sonnet` inerte del vendor. `closer` y `retro` no
están cubiertos por ninguno de los dos `--host`: siguen con el `model: sonnet`
del vendor.

`--refrescar-manifiesto` (requiere `--host claude` o `--host kimi`) **reporta**
hash y diff de cada perfil `DESCONOCIDO` contra la fuente del repo; **jamás
adopta por sí mismo**. Adoptar un hash nuevo del vendor es pegarlo a mano en
`agents/vendor-manifest.sha256`, en un commit propio, con el diff a la vista
en la revisión. El manifiesto no es por-host (mapea hash → rol), así que
puede llevar más de un hash para el mismo rol — por ejemplo, dos versiones
vivas distintas del `reviewer.md` del vendor — y cualquiera de los dos se
adopta.

Después de instalar, el script corre `tools/check-hook-registration.sh` contra
el `settings.json` hermano del destino. Ese aviso es **advisory**: un archivo
perfecto con el registro roto deja el gate inexistente, y el verificador no
cambia el exit code del instalador.

`quality-kit` ya **no** parchea `.claude` (Task 4.1). Los parches del sentinel
y del aviso de revisión van adentro de la fuente de este repo.

### Recetario y skills (Phases 16-18)

`--host claude` (y el flujo por defecto) planta además el recetario, tres
skills de usuario y los tools del rastro, cada uno con la **misma máquina de
estados por archivo** que los perfiles — nuestro idéntico no se reescribe,
nuestro distinto se repara con backup, ajeno no se toca:

| Qué | Dónde |
|---|---|
| `recetas/*.md` + `MANIFEST.sha256` | `<hookdir>/recetas/` |
| skill `/sencillo` | `~/.claude/skills/sencillo/` |
| skill `saikit-verificar-app` | `~/.claude/skills/saikit-verificar-app/` |
| skill `saikit-setup-autopilot` | `~/.claude/skills/saikit-setup-autopilot/` |
| tools del rastro (`saikit-decision.sh`, `saikit-blast.sh`, `lib/redactar.sh`) | `~/.claude/saikit-tools/` |

`saikit-verificar-app` son DOS archivos (`SKILL.md` y el generador
`verificar.sh`). El generador lleva la marca de propiedad en un bloque no-op al
inicio: la marca se lee del primer bloque `---` del archivo, y sin ella un
`.sh` que el kit mismo plantó se clasificaba **DESCONOCIDO** y no se
actualizaba nunca.

El todo-o-nada es **por directorio**, no entre los tres: si falla el tercero,
los dos anteriores ya quedaron publicados y el mensaje lo dice en vez de
afirmar que no se tocó nada. `--quitar-recetas` borra solo lo que lleva la
marca.

### Autopilot (Phase 18)

El autopilot **prepara y para** (decisión del operador del 2026-08-30, que
manda sobre el diseño original): `-saikit:autopilot` arma el carril full con
el flag en el estado, el contrato pide preparar todo — código, verificación,
revisión, PR — y **parar a preguntar antes de publicar**. No hay permiso
permanente: el sentinel es por turno y cada merge exige el sí explícito.

```bash
bash tools/saikit-setup-autopilot.sh        # 5 preguntas => .saikit/autopilot.json (se commitea a origin/<rama>)
bash tools/saikit-merge.sh                  # gate completo; en verde reporta LISTO y termina, NO mergea
bash tools/saikit-merge.sh --confirmado     # el sí: repite el gate y recién entonces mergea
bash tools/saikit-postmerge.sh --merge-commit <sha> --rama <rama>   # VERDE/ROJO/UNKNOWN; ROJO trae PARA REVERTIR
bash tools/saikit-merge.sh --revert-de <sha> --confirmado           # merge del PR de revert (modo sin estado)
```

Qué NUNCA hace: mergear sin el sí, sin CI verde del head exacto, sin
veredicto sellado (`veredicto_sha256` del estado == sha256 del archivo), ni
leyendo la config de otro lado que `origin/<rama>`; revertir solo (el
postmerge avisa con el comando listo y no ejecuta nada); `--admin`, force, ni
`--delete-branch` (el borrado remoto es paso aparte).

Límites medidos (detalle en el spec § Límites MEDIDOS de la Phase 18 y en
`docs/smoke-autopilot-2026-09-05.md`): el camino verde completo no se ha
observado en vivo; en el recorrido medido de Grok el merge es manual (el
sello queda en la sesión emisora, 18.26); la guardia `PreToolUse` contra el
merge a pelo nace inerte hasta que el operador la registra; el cierre
headless quedó corregido con límites (18.27): el auto-wake conserva el
estado y la espera delegada exige trabajo en vuelo. Se observaron 9/9
bloqueos sostenidos; el teardown de la ronda del wake y el presupuesto de
ciclos todavía permiten salidas sin recibo. Evidencia y alcance en
[la medición de 18.27](docs/evidence/18.27-grok-headless/cadena-bloqueo-continuacion.md).
La versión para quien no lee código — qué hace solo, qué NUNCA hace y cómo deshacerlo —
está en `docs/guia-usuario.html`, no acá.

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
