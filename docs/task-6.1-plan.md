# Task 6.1 — Capturar payloads reales de Codex CLI (plan de implementación)

> **Para quien lo ejecute:** los pasos llevan checkbox (`- [ ]`). El TDD
> rojo/verde se hace sobre **un** archivo de test, no sobre `tests/run.sh`
> (~18 min, es el gate final). Copiá el env de `tests/run.sh`: `HOME`, `TMPDIR`,
> `USERPROFILE` y `SAIKIT_HOOK_VIVO="$PWD/hooks/summonaikit-harness.sh"`.

**Goal:** capturar los payloads crudos de las 3 fases de un turno `-saikit` real
en Codex CLI 0.147.0, en un repo descartable, sin tocar el perfil del operador.

**Arquitectura:** el wrapper `~/.codex/hooks/summonaikit-harness.ps1` resuelve su
hook así (medido, no supuesto):

```powershell
$repoRoot = (& git rev-parse --show-toplevel 2>$null | Select-Object -First 1)
if ($repoRoot) {
    $projectHook = Join-Path $repoRoot ".codex\hooks\summonaikit-harness.sh"
    if (Test-Path -LiteralPath $projectHook) { $hookPath = $projectHook }
}
if (-not $hookPath) { $hookPath = Join-Path $env:USERPROFILE ".codex\hooks\summonaikit-harness.sh" }
```

Por eso la captura es **colocación de archivo**, no mutación de config: se deja
un shim en `<repo>/.codex/hooks/summonaikit-harness.sh` y el registro que ya
existe en `~/.codex/hooks.json` lo invoca. **Diferencia con la 5.1**, que tuvo
que appendear al user-config real de zcode y después `--quitar`: acá
`~/.codex/hooks.json` no se toca en ningún momento, y su cksum es parte de la
evidencia.

**Tech stack:** bash (MSYS2 / Git Bash), `tools/capture-payloads.sh`. **Sin
`jq`** — a diferencia de `--host zcode`, que lo exige para editar JSON.

---

## Global Constraints

- **Fail-open siempre en modo hook.** El shim corre en cada turno del repo
  descartable; si no puede escribir, sale 0 y calla. Un capturador que rompe el
  turno destruye la captura que existe para hacer.
- **Nunca se escribe en `~/.codex/`.** Ni el hook, ni `hooks.json`, ni el `.ps1`.
  El único destino es `<repo descartable>/.codex/hooks/`.
- **`umask 077`** en todo lo que se escriba: el payload crudo trae el texto del
  prompt y rutas del perfil.
- **LF puro.** `.gitattributes` ya fuerza `*.sh text eol=lf`; el shim se escribe
  con LF o el `bash.exe` del `.ps1` puede romper.
- **`not_observed != absent`** (Core Rule 2): lo que no se pudo mirar se reporta
  `unknown`, nunca como ausencia.
- El repo descartable **tiene que ser un repo git**. El `.ps1` resuelve la ruta
  con `git rev-parse --show-toplevel`; en un directorio suelto el shim queda
  puesto y no corre nunca — una captura que miente. Misma lección que
  `tools/stage-override.sh`, que lo rechaza con exit 2.

---

## Premisas medidas (2026-08-12/13) — no re-medir

De `docs/phase-6-codex-design.md` (`599be48`):

| Hecho | Dónde se midió |
|---|---|
| Codex CLI 0.147.0, `hooks = true` en `config.toml:136` | `config.toml` |
| `~/.codex/hooks.json` registra el `.ps1` en `UserPromptSubmit`, `PostToolUse` y `Stop`. **`SessionStart` NO invoca al `.ps1`** (ahí van un `echo` y harness-mem) | `hooks.json` |
| El matcher de `PostToolUse` es `Bash\|Edit\|Write\|apply_patch\|Task\|exec\|local_shell_call\|shell_command\|commandExecution` | `hooks.json` |
| El `.ps1` setea `SUMMONAIKIT_HOOK_TARGET=codex` y `SUMMONAIKIT_HOOK_PHASE=<prompt\|tool\|stop>` como env **del proceso** | `summonaikit-harness.ps1` |
| El `.ps1` pasa el payload por stdin: `$payload \| & $bashPath $hookPath` | idem |
| El allowlist del env dump de `capture-payloads.sh` ya incluye `SUMMONAIKIT` | `tools/capture-payloads.sh:110` |

**Consecuencia de la fila 2 que hay que declarar en el análisis:** el harness
tiene 3 fases en Codex, no 4. No se captura `SessionStart` porque ahí no está
registrado — y eso **no** es un defecto a arreglar en esta tarea.

---

## Qué cambia y qué NO

**Cambia:** `tools/capture-payloads.sh` (acepta `--host codex`),
`tests/test_capture_payloads.sh` (casos nuevos).

**NO cambia:** `hooks/summonaikit-harness.sh`, `tools/install-hook.sh`,
`tests/golden/baseline.txt`, ni nada de `~/.codex/`. Si el diff toca alguno de
esos, algo se fue de alcance.

---

## A) `--host codex` en `tools/capture-payloads.sh` (TDD)

### A1. Contrato

```
tools/capture-payloads.sh --instalar <repo> --host codex
  → escribe <repo>/.codex/hooks/summonaikit-harness.sh (el shim)
  → exit 0 si quedó; 2 si <repo> no es git, es un perfil, o no se pudo escribir

tools/capture-payloads.sh --quitar <repo> --host codex
  → borra ese archivo SOLO si lleva el marcador de propiedad
  → exit 0 siempre que el destino quede sin shim nuestro

tools/capture-payloads.sh --cosechar <repo>
  → sin cambios: lista <repo>/capturas
```

El shim que se escribe:

```bash
#!/usr/bin/env bash
# --saikit-capture-id 6.1
# Shim de captura (Task 6.1). Lo invoca ~/.codex/hooks/summonaikit-harness.ps1,
# que prefiere esta ruta sobre la del perfil cuando el cwd es un repo git.
# Fail-open: cualquier problema sale 0 y calla, para no romper el turno.
exec bash "__CAPTURADOR__" \
  --tag "${SUMMONAIKIT_HOOK_PHASE:-sin-fase}" \
  --capture-dir "__REPO__/capturas" \
  --only-cwd "__REPO__"
```

`__CAPTURADOR__` y `__REPO__` se sustituyen con rutas absolutas en forma MSYS al
instalar. **`--tag` sale de `SUMMONAIKIT_HOOK_PHASE`** y no del payload: si Codex
no emite `hook_event_name`, el capturador nombra el archivo `sin-evento-*` y las
3 fases colisionarían en un solo prefijo. El tag las separa igual.

### A2. Por qué `--only-cwd` sigue puesto aunque la ruta ya sea del repo

El `.ps1` elige el shim cuando `git rev-parse --show-toplevel` da el repo
descartable. Si el operador abre Codex en un **subdirectorio** de ese repo, el
toplevel sigue siendo el mismo y el shim corre — correcto. Pero si por cualquier
vía el shim se ejecutara con otro cwd, `--only-cwd` evita escribir el turno
ajeno. Es defensa en profundidad, no la contención principal. **Límite
declarado:** `--only-cwd` compara `pwd -P` exacto, así que un turno lanzado
desde un subdirectorio **no** se captura. Para esta tarea alcanza (el operador
trabaja en la raíz); si hiciera falta, se cambia por comparación de prefijo y se
declara.

### A3. Rechazos, cada uno por un modo de falla real

| Condición | Exit | Razón |
|---|---|---|
| `<repo>` no es repo git | 2 | el `.ps1` no lo va a elegir: shim puesto que no corre nunca |
| `<repo>` es un directorio de perfil (`~/.codex`, `~/.claude`, …) | 2 | ahí vive el gate real; el filtro de perfil ya existe en el script |
| `<repo>/.codex/hooks/summonaikit-harness.sh` existe y **no** lleva el marcador | 2 | es de otro; "no es nuestro ⇒ sobrescribir" es cómo se destruye el cambio ajeno |
| no se pudo escribir | 2 | no se afirma una captura que no va a ocurrir |
| `--host` **sin valor** (`--instalar <repo> --host`) | 2 | hallazgo abierto de CodeRabbit, ver A4 |

### A4. Dos hallazgos de CodeRabbit (PR#2) que siguen abiertos — se cierran acá

Medido 2026-08-13: de los 9 PRs del repo, CodeRabbit alcanzó a revisar **uno**
(el #2, el único que quedó abierto más de 40 s; en los otros ocho el bot llegó
tarde y comentó *"Review failed — the pull request is closed"*). En esa única
pasada dejó 3 hallazgos y **ninguno se arregló**. Los dos Major viven en el
archivo que esta sección ya toca, así que se cierran acá con su test, como pide
la regla de hierro 2 del repo.

**H1 — `--host` sin valor instala el host equivocado en silencio.** Severidad
Major. Reproducido en vivo:

```
$ bash tools/capture-payloads.sh --instalar <repo> --host
exit=0   (esperado 2)   →  escribio el settings de CLAUDE
```

Mecanismo: `:55` hace `host="${2:-}"`, que con el flag al final queda vacío, y
`:117` hace `host="${host:-claude}"`, que lo convierte en `claude`. **Afecta a
los tres hosts**, `codex` incluido. Es la misma clase de defecto que la Task 0.4
cerró en `check-hook-registration.sh` (el `shift 2` con flag sin valor, que ahí
colgaba el script). El daño concreto acá es distinto y peor de lo que parece: un
typo en el flag no falla, captura mal, y se descubre con la captura vacía — o
sea quemando una sesión con el operador adelante, el recurso más caro de la
fase.

Arreglo, en el propio branch del flag para que el error salga donde se cometió:

```bash
--host)
  { [ $# -ge 2 ] && [ -n "$2" ]; } || {
    echo "capture-payloads: --host requiere un valor ('claude', 'zcode' o 'codex')" >&2
    exit 2; }
  host="$2"; shift 2 ;;
```

Se exige `-n "$2"` además del conteo: `--host ""` también tiene que morir, y con
solo `[ $# -ge 2 ]` pasaría y volvería a caer en el default `claude`. El
`host="${host:-claude}"` de `:117` **se conserva**: sigue siendo correcto para el
caso "no se pasó el flag".

**H2 — `--quitar` de un repo borra los hooks vivos de otro.** Severidad Major.
`JQ_QUITAR` define `def ours` matcheando el literal `saikit-capture-id 5[.]1`, y
`has_tag` decide por evento+tag. Los dos ignoran el destino, y el user-config de
zcode es **compartido**. Consecuencias, las dos reales:

1. Instalás para el repo A y después para el B: `add_unless` ve el tag ya
   presente y **no agrega las entradas de B**. La captura de B nunca ocurre.
2. `--quitar B` matchea las entradas de A y **le borra a A sus hooks vivos**.

**Solo afecta al camino `zcode`.** El camino `codex` de esta tarea es inmune por
construcción: cada repo tiene su propio archivo en `<repo>/.codex/hooks/`, no
hay config compartida. Se arregla igual porque es un bug vivo en el archivo que
estamos tocando.

Arreglo: que las dos decisiones miren también el destino. El comando registrado
ya lo lleva embebido (`--only-cwd "<abs>"`), así que alcanza con compararlo. Se
usa `contains` y **no** `test`: `contains` es subcadena literal, así que una ruta
de Windows con metacaracteres de regex no rompe el match ni exige escaparla.

```jq
# antes:  def ours: any((.hooks // [])[]; ((.command // "") | test("saikit-capture-id 5[.]1")));
def ours: any((.hooks // [])[];
  ((.command // "") | contains("saikit-capture-id 5.1") and contains($destmark)));
```

con `--arg destmark "--only-cwd \"<abs del repo>\""` desde el shell, y el mismo
`$destmark` sumado a la condición de `has_tag` para que B sí se agregue estando
A. **Límite declarado:** si dos repos distintos resolvieran al mismo `pwd -P`,
seguirían colisionando. No es alcanzable en la práctica y no se cubre.

### A4-bis. La revisión cruzada (kimi, 1 ronda, 2026-08-13)

**Con codex no se pudo.** El prompt del script arranca con *"Actúa como revisor
de código externo…"* y eso dispara la skill `harness-review` del perfil de codex,
que abandona la tarea pedida y carga su propio workflow. Murió con exit 1 y
respuesta vacía, sin mirar el diff. Se reintentó con kimi, que no tiene esa
skill. **Queda anotado**: `cross-review.ps1 -Con codex` no sirve en esta máquina
mientras esa skill se auto-dispare.

**Cinco hallazgos, todos de severidad baja; ninguno alto ni medio**, así que el
tope de 1 ronda de la regla global se cumple sin segunda vuelta. Kimi además
corrió la suite por su cuenta y confirmó el verde.

Tres se arreglaron acá, cada uno con su caso:

| # | Qué | Dónde |
|---|---|---|
| 2 | `git rev-parse` falla igual sin git instalado que sin repo, y el mensaje acusaba al destino — Core Rule 2 en chiquito | `codex_install`, guarda `command -v git` |
| 3 | El shim moría con **127** en cada fase si el repo que lo instaló se movía: **el fail-open del modo hook no cubre al shim** | el shim gana `[ -f … ] \|\| exit 0` |
| 4 | `n_antes`/`n_despues` contaban sobre el config compartido entero, así que el resumen mentía justo en el caso multi-repo que H2 arregla | se cuenta por `saikit-dest` |

El 5 (el árbol `.codex/hooks/` queda vacío tras `--quitar`) es cosmético y no se
tocó.

**El hallazgo 1 no tiene arreglo limpio y se declara.** Las entradas instaladas
con la versión anterior —sin `--saikit-dest`— son invisibles para `mine`/`ours`:
un reinstall las duplicaría y `--quitar` no podría borrarlas. Hacer que `ours`
también matchee las entradas sin `dest` **reabre exactamente el bug H2**, porque
una entrada sin destino puede ser de cualquier repo. Verificado en el
user-config real (`~/.zcode/cli/config.json`): **no hay entradas saikit previas**,
así que hoy no es alcanzable en esta máquina. Sólo importaría contra una
instalación vieja en otro entorno, y el remedio ahí es editar el config a mano.

### A5. Tests — rojo primero

- [ ] **Paso 1: escribir los casos que fallan**

En `tests/test_capture_payloads.sh`, al final, **en el estilo del archivo**:
script plano con `caso` para etiquetar y `malo` para fallar; `$tool` es el
capturador y `$SANDBOX` lo da `sandbox_init` (ya cargado arriba). No hay
helpers `afirmar_*` ni función por caso — no inventar los que no existen.

```bash
# ------------------------------------------------------- 6) --host codex
cdx="$SANDBOX/repo-codex"
mkdir -p "$cdx" && ( cd "$cdx" && git init -q )
shim="$cdx/.codex/hooks/summonaikit-harness.sh"

caso "--host codex deja el shim en la ruta que el .ps1 prefiere"
out="$(bash "$tool" --instalar "$cdx" --host codex 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc: $out"
[ -f "$shim" ] || malo "no escribio $shim"
grep -q -- '--saikit-capture-id 6.1' "$shim" || malo "el shim no lleva el marcador de propiedad"
bash -n "$shim" 2>/dev/null || malo "el shim no parsea: rompe todos los turnos siguientes"
grep -q '__REPO__\|__CAPTURADOR__' "$shim" && malo "quedaron placeholders sin sustituir"

caso "un directorio sin git se rechaza: el .ps1 no lo elegiria y el shim no correria nunca"
sing="$SANDBOX/sin-git"
mkdir -p "$sing"
out="$(bash "$tool" --instalar "$sing" --host codex 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || malo "esperaba exit 2, dio $rc: $out"
[ ! -e "$sing/.codex" ] || malo "rechazo pero dejo el arbol puesto"

caso "--host codex NO pisa un hook ajeno"
ajeno="$SANDBOX/repo-ajeno"
mkdir -p "$ajeno/.codex/hooks" && ( cd "$ajeno" && git init -q )
printf '#!/usr/bin/env bash\n# de otro\n' > "$ajeno/.codex/hooks/summonaikit-harness.sh"
antes="$(cksum < "$ajeno/.codex/hooks/summonaikit-harness.sh")"
out="$(bash "$tool" --instalar "$ajeno" --host codex 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || malo "pisar un hook ajeno debe fallar, dio $rc"
[ "$antes" = "$(cksum < "$ajeno/.codex/hooks/summonaikit-harness.sh")" ] \
  || malo "PISO el hook del usuario"

caso "la fase entra en el nombre aunque el payload no traiga hook_event_name"
# El env va sobre el `bash "$shim"`, NO sobre el printf: en un pipeline el
# prefijo VAR=val solo alcanza al comando que precede. Ponerlo del lado del
# printf deja al shim sin la fase — medido: el archivo salia 'sin-fase'.
( cd "$cdx" && printf '{"session_id":"x"}' | SUMMONAIKIT_HOOK_PHASE=stop bash "$shim" )
ls "$cdx"/capturas/*stop*.json >/dev/null 2>&1 \
  || malo "sin hook_event_name las 3 fases colisionarian en 'sin-evento': el --tag es lo que las separa"

caso "el env dump contesta la pregunta del TARGET que pide la DoD"
( cd "$cdx" && printf '{"hook_event_name":"UserPromptSubmit"}' \
    | SUMMONAIKIT_HOOK_PHASE=prompt SUMMONAIKIT_HOOK_TARGET=codex bash "$shim" )
grep -rq 'SUMMONAIKIT_HOOK_TARGET=codex' "$cdx"/capturas/ \
  || malo "el env dump no trae el TARGET; sin eso la DoD no se puede contestar"

caso "--quitar --host codex deja la ruta limpia"
out="$(bash "$tool" --quitar "$cdx" --host codex 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc: $out"
[ ! -f "$shim" ] || malo "no quito el shim propio"

caso "--quitar NO borra un shim ajeno"
out="$(bash "$tool" --quitar "$ajeno" --host codex 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || malo "borrar lo ajeno para 'limpiar' es el mismo error que pisarlo"
[ -f "$ajeno/.codex/hooks/summonaikit-harness.sh" ] || malo "BORRO el hook del usuario"

# ------------------------------ 7) H1: --host sin valor (CodeRabbit PR#2)
caso "H1: --host sin valor sale 2 y NO instala el host equivocado"
h1="$SANDBOX/repo-h1"
mkdir -p "$h1" && ( cd "$h1" && git init -q )
out="$(bash "$tool" --instalar "$h1" --host 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || malo "esperaba exit 2, dio $rc: un typo en el flag captura mal y quema una sesion con el operador adelante"
[ ! -f "$h1/.claude/settings.json" ] || malo "cayo al default 'claude' e instalo el host equivocado"

caso "H1: --host con valor vacio tambien sale 2"
out="$(bash "$tool" --instalar "$h1" --host '' 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || malo "esperaba exit 2, dio $rc: '' vuelve a caer en el default por \${host:-claude}"
[ ! -f "$h1/.claude/settings.json" ] || malo "instalo con host vacio"

# ------------------- 8) H2: dos repos, un user-config (CodeRabbit PR#2)
# Solo aplica al camino zcode: el de codex es inmune (archivo por repo).
caso "H2: instalar para B estando A agrega las entradas de B"
cfg="$SANDBOX/zcode-config.json"
printf '{}\n' > "$cfg"
rA="$SANDBOX/repo-A"; rB="$SANDBOX/repo-B"
mkdir -p "$rA" "$rB"
SAIKIT_ZCODE_USER_CONFIG="$cfg" bash "$tool" --instalar "$rA" --host zcode >/dev/null 2>&1
SAIKIT_ZCODE_USER_CONFIG="$cfg" bash "$tool" --instalar "$rB" --host zcode >/dev/null 2>&1
grep -q -- "--only-cwd \"$rB\"" "$cfg" \
  || malo "las entradas de B no se agregaron: has_tag decide por evento+tag y el tag ya estaba por A"

caso "H2: --quitar B NO se lleva las entradas vivas de A"
SAIKIT_ZCODE_USER_CONFIG="$cfg" bash "$tool" --quitar "$rB" --host zcode >/dev/null 2>&1
grep -q -- "--only-cwd \"$rA\"" "$cfg" \
  || malo "BORRO los hooks vivos de A: 'ours' matchea el capture-id sin mirar el destino"
grep -q -- "--only-cwd \"$rB\"" "$cfg" \
  && malo "no quito las entradas de B"
```

- [ ] **Paso 2: correrlos y verificar que fallan**

```bash
bash tests/test_capture_payloads.sh
```

Esperado: rojo. Los tres primeros por
`--host solo acepta 'zcode' (dio 'codex')` con exit 2, y los que ejercitan el
shim porque el archivo no existe.

- [ ] **Paso 3: implementar**

En `tools/capture-payloads.sh:118`, ampliar la validación (y de paso corregir el
mensaje, que hoy dice "solo acepta 'zcode'" pero también acepta `claude`):

```bash
case "$host" in
  claude|zcode|codex) ;;
  *) echo "capture-payloads: --host acepta 'claude', 'zcode' o 'codex' (dio '$host')" >&2
     exit 2 ;;
esac
```

Y la rama de instalación para `codex` (sin `jq`, a diferencia de zcode):

```bash
codex_shim_path() { printf '%s/.codex/hooks/summonaikit-harness.sh' "$1"; }

codex_instalar() {
  repo="$1"
  ( cd "$repo" 2>/dev/null && git rev-parse --show-toplevel >/dev/null 2>&1 ) || {
    echo "capture-payloads: <repo> tiene que ser un repo git — el .ps1 resuelve por git rev-parse y si no, el shim no corre nunca" >&2
    return 2; }
  shim="$(codex_shim_path "$repo")"
  if [ -e "$shim" ] && ! grep -q -- '--saikit-capture-id 6.1' "$shim" 2>/dev/null; then
    echo "capture-payloads: $shim existe y no es nuestro — no se toca" >&2
    return 2; fi
  mkdir -p "$(dirname "$shim")" 2>/dev/null || return 2
  cap="$(cd "$(dirname "$0")" && pwd)/capture-payloads.sh"
  abs="$(cd "$repo" && pwd)"
  umask 077
  {
    printf '#!/usr/bin/env bash\n'
    printf '# --saikit-capture-id 6.1\n'
    printf '# Shim de captura (Task 6.1). Lo invoca ~/.codex/hooks/summonaikit-harness.ps1,\n'
    printf '# que prefiere esta ruta sobre la del perfil cuando el cwd es un repo git.\n'
    printf '# Fail-open: cualquier problema sale 0 y calla, para no romper el turno.\n'
    printf '# El fail-open del modo hook NO cubre a este shim: si el repo que lo instalo\n'
    printf '# se mueve o se borra, `exec` moriria con 127 en CADA fase. El guard de\n'
    printf '# abajo es lo que hace fail-open al shim POR SI MISMO (hallazgo H-3).\n'
    printf '[ -f "%s" ] || exit 0\n' "$cap"
    printf 'exec bash "%s" \\\n' "$cap"
    printf '  --tag "${SUMMONAIKIT_HOOK_PHASE:-sin-fase}" \\\n'
    printf '  --capture-dir "%s/capturas" \\\n' "$abs"
    printf '  --only-cwd "%s"\n' "$abs"
  } > "$shim" 2>/dev/null || return 2
  bash -n "$shim" 2>/dev/null || { rm -f "$shim"; return 2; }
  return 0
}

codex_quitar() {
  shim="$(codex_shim_path "$1")"
  [ -e "$shim" ] || return 0
  grep -q -- '--saikit-capture-id 6.1' "$shim" 2>/dev/null || {
    echo "capture-payloads: $shim no es nuestro — no se borra" >&2; return 2; }
  rm -f "$shim"
}
```

- [ ] **Paso 4: correr y verificar que pasan**

```bash
bash tests/test_capture_payloads.sh
```

Esperado: los 7 casos nuevos en verde, y **los preexistentes de `claude` y
`zcode` siguen verdes** — si alguno se movió, la validación del host rompió
algo que ya funcionaba.

- [ ] **Paso 5: commit**

```bash
git add tools/capture-payloads.sh tests/test_capture_payloads.sh
git commit -m "feat(6.1): capture-payloads --host codex por colocacion de shim"
```

---

## B) Preparar el repo descartable (todo en Git Bash)

- [ ] **Paso 6**

```bash
d=/c/dev/saikit-captura-codex
mkdir -p "$d" && cd "$d" && git init -q
printf 'capturas/\n.codex/\n' > .gitignore
git add .gitignore && git commit -q -m "init"
bash /c/dev/summonaikit-claude/tools/capture-payloads.sh --instalar "$d" --host codex
```

- [ ] **Paso 7: preflight — el cksum que es evidencia**

```bash
cksum < ~/.codex/hooks.json                       # anotar
cksum < ~/.codex/hooks/summonaikit-harness.sh     # anotar
cksum < ~/.codex/hooks/summonaikit-harness.ps1    # anotar
```

Los tres tienen que ser **idénticos al final**. Es lo que sostiene la cláusula
"el config del operador no se toca" de la DoD.

---

## C) STOP — persona adelante

**No se puede automatizar.** Requiere una sesión real de Codex.

- [ ] **Paso 8**

1. Abrí **Codex** en `/c/dev/saikit-captura-codex` (sesión nueva: los hooks se
   fotografían al arrancar).
2. Un prompt **con `-saikit`** que provoque las 3 fases y **al menos un
   despacho de subagente**. Ejemplo:
   *"-saikit agregá un archivo `hola.txt` con la palabra hola, verificá que
   existe, y delegá la revisión a un subagente reviewer."*
3. Dejalo terminar el turno.
4. Un segundo prompt **sin** `-saikit`, para tener el contraste.

---

## D) Cosechar y analizar

- [ ] **Paso 9: verificar que el perfil quedó intacto — primero**

```bash
cksum < ~/.codex/hooks.json
cksum < ~/.codex/hooks/summonaikit-harness.sh
cksum < ~/.codex/hooks/summonaikit-harness.ps1
```

Si alguno cambió, **la captura no se declara válida** hasta explicar por qué.

- [ ] **Paso 10: cosechar**

```bash
bash /c/dev/summonaikit-claude/tools/capture-payloads.sh --cosechar /c/dev/saikit-captura-codex
ls -1 /c/dev/saikit-captura-codex/capturas/
```

- [ ] **Paso 11: contestar las cinco preguntas de la DoD, con el comando al lado**

```bash
cd /c/dev/saikit-captura-codex/capturas

# 1. Las 3 fases llegaron?
ls *prompt*.json *tool*.json *stop*.json 2>/dev/null | wc -l

# 2. Como se llama la herramienta de subagentes y donde viaja el rol?
grep -l 'subagent_type\|agent_type' *.json
grep -o '"tool_name"[^,]*' *.json | sort -u

# 3. El matcher real atrapa la delegacion?
#    (si el paso 2 no encuentra ningun evento con el rol, la respuesta es NO
#     y D3 del diseño NO se prende)

# 4. transcript_path cae adentro de ~/.codex/sessions/ ?
grep -o '"transcript_path"[^,]*' *.json | sort -u

# 5. SUMMONAIKIT_HOOK_TARGET=codex esta en el env?
grep -h 'SUMMONAIKIT' *.env | sort -u
```

**Cómo se escribe cada respuesta:** medido / no observado. Un `grep` vacío es
"no lo vi", y eso es `unknown` salvo que se pueda afirmar que se miró todo.

---

## E) Entregables

- [ ] **Paso 12: `docs/task-6.1-captura.md`**

Espeja a `docs/task-5.1-captura.md`. Tiene que traer: el diff de forma contra
los payloads de Claude (campos presentes/ausentes, anidamiento), las cinco
respuestas con su evidencia, y **el veredicto sobre D3** — si la rama de
ceremonia se puede prender o no. Los payloads crudos **no se commitean**.

- [ ] **Paso 13: si una premisa del diseño cae**

Se re-redacta `docs/phase-6-codex-design.md` **antes** de escribir una línea de
6.3–6.6, igual que la 5.1 tenía escrito. Es el punto entero de medir primero.

- [ ] **Paso 14: `Plans.md` fila 6.1 → `cc:完了 [<sha>]`**, solo si las 3 fases
      están capturadas. Con menos, la fila queda `cc:TODO` con lo medido escrito.

- [ ] **Paso 15: limpieza**

```bash
bash /c/dev/summonaikit-claude/tools/capture-payloads.sh --quitar /c/dev/saikit-captura-codex --host codex
# y el cksum de los 3 archivos del perfil, otra vez
```

- [ ] **Paso 16: gates y commit**

```bash
pre-commit run --files tools/capture-payloads.sh tests/test_capture_payloads.sh docs/task-6.1-captura.md Plans.md
bash tests/run.sh     # gate final, ~18 min — no tocar el repo mientras corre
git add tools/capture-payloads.sh tests/test_capture_payloads.sh docs/task-6.1-captura.md Plans.md
git commit -m "docs(6.1): captura de payloads de codex — las 5 preguntas medidas"
```

---

## Lo que esta tarea NO afirma

- **No mide el contrato de salida.** Eso es 6.2. Que un payload llegue no dice
  que la respuesta del hook se respete.
- **No prende ninguna rama.** `HOST=codex` y la ceremonia son 6.4, y dependen de
  lo que esta tarea mida.
- **No captura `SessionStart`**, porque `hooks.json` no registra el `.ps1` ahí.
  Es un hecho del registro de Codex, no una omisión del capturador.
- **No prueba que el shim sea equivalente al hook real.** Es un capturador: su
  trabajo es guardar stdin y salir 0.
