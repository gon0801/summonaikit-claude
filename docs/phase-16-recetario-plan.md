# Phase 16 — El recetario: plan de implementación

> **Para workers (DeepSeek):** este plan **no requiere ningún plugin ni
> skill**. Una task por sesión, en UN turno armado con `-saikit` (el gate corre
> en la sesión `deepseek` y exige implementer → verifier → reviewer y el recibo;
> úsalo: delega los pasos de implementación al implementer, la corrida de
> tests al verifier, la lectura del diff al reviewer). Sigue los pasos `- [ ]`
> de la task EN ORDEN y sin saltarte ninguno; un paso que no puedas hacer se
> declara en el recibo con su razón, no se omite en silencio. Diseño aprobado:
> `docs/phase-16-18-recetario-autopilot-design.md` (leer ENTERO antes de la
> primera task; las decisiones D1–D10 son las de esta fase). Ledger:
> `Plans.md` § Phase 16 (16.2–16.9; la 16.1 ya cerró en el PR #95).
> Primera entrada de la sesión, literal:
> `-saikit Lee docs/phase-16-recetario-plan.md entero y ejecuta SOLO la Task 16.2 siguiendo sus pasos; abre el PR y para.`

**Objetivo:** que un turno `-saikit` en Claude Code reciba, además del
contrato de siempre, un **menú de recetas** por tipo de tarea; que el líder
elija una, copie sus pasos y la declare en el recibo; que los perfiles de rol
lleven los principios que les tocan; y que `-saikit:pregunta` / `-saikit:boceto`
bajen el carril **y** nombren su receta. **El Stop gate no cambia.**

**Arquitectura:** `recetas/*.md` (fuente, español, ≤80 líneas, frontmatter con
`saikit_owned`) + `recetas/MANIFEST.sha256` (TSV generado, hash por archivo). El
hook lee el manifiesto en `RECETAS_DIR` (override `SAIKIT_RECETAS_DIR`), ofrece
solo las recetas cuyo hash coincide, e inyecta el menú al contrato por
sustitución controlada (como `$TOOL_HINT`). El instalador planta `recetas/` y
`~/.claude/skills/sencillo/` con la máquina de estados por archivo que ya usan
los perfiles. Host de esta ola: `claude`.

**Stack:** bash (hook, instalador, tests con `tests/lib/hook_lab.sh` y
`tests/lib/sandbox.sh`), `sha256sum`, Markdown con frontmatter YAML plano
(sin `yq`: se parsea con `sed`/`grep` en el linter, NUNCA en el hook).

## Restricciones globales (aplican a cada task)

- `not_observed != absent`: lo no medido se escribe `unknown`, nunca se rellena.
- **Cada cambio del hook**: rojo medido pre-fix (el caso nuevo falla contra el
  hook sin el cambio), caso que acredita + caso que bloquea/omite, mutación
  `mut_*` acreditada a SU caso en `tests/test_gate_mutations.sh`, y línea base
  golden: `bash tools/golden-harness.sh --check` con 0 divergencias, o
  `--record` con el diff auditado y citado en el PR (precedente 11.1). Un test
  que pasa igual sin el fix se rechaza: correr la mutación ANTES de abrir el PR.
- **Local, SOLO lo acotado:** el archivo de test que tocas (con
  `SAIKIT_HOOK_VIVO="$PWD/hooks/summonaikit-harness.sh"` cuando el test corre el
  hook) y la batería de mutaciones acotada
  (`SAIKIT_MUTACIONES='...' bash tests/test_gate_mutations.sh`). **JAMÁS
  `bash tests/run.sh` completo en local**: la batería completa la corre el job
  `suite` del PR en CI (7–9 min). Regla de AGENTS.md; costó horas dos veces.
- **Proceso (retro de la Phase 15, no se re-litiga):** rama por task desde
  `origin/master` (`git fetch origin && git checkout -b phase-16/<task> origin/master
  && git branch --unset-upstream`); un PR por task; `git log origin/master..HEAD`
  solo con commits de la task; **el worker NO mergea, NO hace push a master, NO
  corre el deploy (`install-hook.sh` contra `~/.claude`), NO edita `Plans.md`
  ni el spec** (el lead cierra las filas y despliega); tope de **1 ronda** de
  cross-review por PR (una segunda solo si la primera halló severidad alta);
  CI verde ANTES de pedir revisión; ningún cambio de alcance sin decirlo en el
  PR. Push: `git push origin HEAD:refs/heads/phase-16/<task>` en un comando
  SOLO (sin `master` en la línea, sin `commit -F -` en la misma línea); el PR
  con `gh pr create --base master` en otro comando.
- Nada de secretos en fixtures; `.saikit/` no entra a la allowlist de gitleaks.
- Commits en Conventional Commits en español: `feat(16.2): …`, `test(16.4): …`.
- Baseline de lint bash: `tests/lib/check_syntax.sh` (`bash -n`); correrlo sobre
  cada `.sh` tocado.

---

### Task 16.2 — `recetas/` fuente, manifiesto y linter

**Archivos:**
- Crear: `tests/lib/recetas_lint.sh` (biblioteca: `lint_receta`, `manifest_linea`)
- Crear: `tests/test_recetas.sh`
- Crear: `tools/gen-recetas-manifest.sh`
- Crear: `recetas/00-lider.md`, `recetas/bug.md`, `recetas/funcion.md`,
  `recetas/refactor.md`, `recetas/lento.md`, `recetas/investigar.md`,
  `recetas/boceto.md`, `recetas/MANIFEST.sha256`, `recetas/pendientes/.gitkeep`
- Modificar: `.gitattributes` (dos líneas)

**Interfaces:**
- Produce: `MANIFEST.sha256` — una línea por archivo, campos separados por TAB:
  `sha256<TAB>tipo<TAB>nombre<TAB>carril<TAB>titulo` (`tipo` ∈ `receta|lider`;
  `carril` ∈ `full|fast|-` para lider; título al final, sin TAB ni salto),
  ordenado por `nombre`, LF. 16.4 lo lee con `IFS=$'\t' read -r`.
- Produce: `lint_receta <archivo>` → 0 si válida, 1 con motivo en stdout.

- [ ] **Paso 1: escribir la biblioteca del linter ANTES que las recetas**

```bash
# tests/lib/recetas_lint.sh — reglas de forma de una receta (D2). Se carga con
# `. tests/lib/recetas_lint.sh`. Sin dependencias fuera de coreutils/grep/sed.
# `gt` como token independiente (CodeRabbit, PR #97: 'gt ' matcheaba 'right ').
RECETAS_TERMINOS_PROHIBIDOS='(^|[^A-Za-z0-9_])gt([^A-Za-z0-9_]|$)|Graphite|Bugbot|AskQuestion|/loop|poteto'
RECETAS_TOPE_LINEAS=80

_rl_lineas() {  # $1=archivo → lineas LOGICAS (cuenta la ultima aunque no termine en \n; Greptile, PR #97)
  tr -d '\r' < "$1" | awk 'END{print NR}'
}

_rl_frontmatter() {  # $1=archivo → stdout: lineas entre el 1er y 2do '---'
  tr -d '\r' < "$1" | awk 'NR==1 && $0!="---"{exit 1} NR>1 && $0=="---"{exit} NR>1{print}'
}
_rl_campo() {  # $1=archivo $2=clave → valor (sin comillas) o vacio
  _rl_frontmatter "$1" | sed -n "s/^$2:[[:space:]]*//p" | head -n1 | sed 's/^"\(.*\)"$/\1/'
}

lint_receta() {  # $1=archivo → 0 ok; 1 con motivo(s) en stdout
  local f="$1" rc=0 n tipo nombre carril titulo base
  n="$(_rl_lineas "$f")"
  [ "$n" -le "$RECETAS_TOPE_LINEAS" ] || { echo "supera $RECETAS_TOPE_LINEAS lineas ($n)"; rc=1; }
  _rl_frontmatter "$f" >/dev/null 2>&1 || { echo "sin frontmatter (--- en la linea 1 y cierre)"; return 1; }
  [ "$(_rl_campo "$f" saikit_owned)" = "summonaikit-claude" ] || { echo "falta saikit_owned: summonaikit-claude"; rc=1; }
  tipo="$(_rl_campo "$f" tipo)"; [ -n "$tipo" ] || tipo=receta
  case "$tipo" in receta|lider) ;; *) echo "tipo invalido: $tipo"; rc=1 ;; esac
  nombre="$(_rl_campo "$f" nombre)"
  printf '%s' "$nombre" | grep -Eq '^[a-z][a-z0-9-]*$' || { echo "nombre invalido: [$nombre]"; rc=1; }
  # nombre == archivo (CodeRabbit, PR #97): el instalador y el hook resuelven
  # <nombre>.md; un desfase deja una receta en el manifiesto que no existe.
  base="$(basename "$f" .md)"
  if [ "$tipo" = lider ]; then
    [ "$base" = "00-lider" ] && [ "$nombre" = "lider" ] || { echo "el lider debe ser 00-lider.md con nombre: lider"; rc=1; }
  else
    [ "$base" = "$nombre" ] || { echo "nombre [$nombre] no coincide con el archivo [$base.md]"; rc=1; }
  fi
  titulo="$(_rl_campo "$f" titulo)"
  [ -n "$titulo" ] || { echo "falta titulo"; rc=1; }
  printf '%s' "$titulo" | grep -q "$(printf '\t')" && { echo "el titulo lleva TAB"; rc=1; }
  if [ "$tipo" = receta ]; then
    carril="$(_rl_campo "$f" carril)"
    case "$carril" in full|fast) ;; *) echo "carril invalido: [$carril]"; rc=1 ;; esac
    [ -n "$(_rl_campo "$f" cuando)" ] || { echo "falta cuando"; rc=1; }
    case "$(_rl_campo "$f" adversary)" in opcional|obligatorio) ;; *) echo "adversary invalido"; rc=1 ;; esac
    for sec in '## Pasos' '## Qué le dices al usuario' '## Recibo'; do
      grep -q "^$sec" "$f" || { echo "falta la seccion '$sec'"; rc=1; }
    done
  fi
  if grep -Eq "$RECETAS_TERMINOS_PROHIBIDOS" "$f"; then
    echo "termino prohibido: $(grep -Eo "$RECETAS_TERMINOS_PROHIBIDOS" "$f" | head -n1)"; rc=1
  fi
  # links relativos [texto](ruta) tienen que resolver desde recetas/
  for l in $(grep -Eo '\]\([^)#]+' "$f" | sed 's/^](//' | grep -Ev '^(https?:|mailto:)'); do
    [ -e "$(dirname "$f")/$l" ] || { echo "link roto: $l"; rc=1; }
  done
  return $rc
}

manifest_linea() {  # $1=archivo → "sha256\ttipo\tnombre\tcarril\ttitulo"
  local f="$1" tipo carril
  tipo="$(_rl_campo "$f" tipo)"; [ -n "$tipo" ] || tipo=receta
  carril="$(_rl_campo "$f" carril)"; [ -n "$carril" ] || carril=-
  printf '%s\t%s\t%s\t%s\t%s\n' "$(sha256sum "$f" | cut -c1-64)" "$tipo" \
    "$(_rl_campo "$f" nombre)" "$carril" "$(_rl_campo "$f" titulo)"
}
```

- [ ] **Paso 2: escribir el test del linter con fixtures en sandbox (rojo primero)**

```bash
#!/usr/bin/env bash
# tests/test_recetas.sh — Task 16.2: forma de las recetas + manifiesto candado.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
. "$here/lib/sandbox.sh"; sandbox_init
. "$here/lib/recetas_lint.sh"
fail=0; caso() { printf '  caso: %s\n' "$1"; }; malo() { printf '    FAIL: %s\n' "$1" >&2; fail=1; }

buena() {  # $1=ruta → escribe una receta valida minima
  cat > "$1" <<'EOF'
---
saikit_owned: summonaikit-claude
nombre: bug
titulo: Arreglar algo que no funciona
carril: full
cuando: ["no funciona", "da error"]
adversary: opcional
---
## Pasos
1. Reproducir.
## Qué le dices al usuario
Primero qué cambia para ti.
## Recibo
Understand: Receta: bug.
EOF
}

# Nota: `buena` escribe `nombre: bug`, y el linter exige nombre == archivo, asi
# que las fixtures que deben ser VALIDAS se llaman bug.md (en subdirs propios).
caso "receta valida => 0"
mkdir -p "$SANDBOX/ok"; buena "$SANDBOX/ok/bug.md"; lint_receta "$SANDBOX/ok/bug.md" >/dev/null || malo "rechazo una receta valida"

caso "termino prohibido => 1 con motivo"
mkdir -p "$SANDBOX/p"; buena "$SANDBOX/p/bug.md"; printf 'Usa Graphite para el stack.\n' >> "$SANDBOX/p/bug.md"
out="$(lint_receta "$SANDBOX/p/bug.md")" && malo "acepto 'Graphite'"; printf '%s' "$out" | grep -q prohibido || malo "motivo sin 'prohibido': $out"

caso "carril invalido => 1"
mkdir -p "$SANDBOX/c"; buena "$SANDBOX/c/bug.md"; sed -i 's/^carril: full/carril: rapido/' "$SANDBOX/c/bug.md"
lint_receta "$SANDBOX/c/bug.md" >/dev/null && malo "acepto carril: rapido"

caso "mas de 80 lineas => 1"
buena "$SANDBOX/l.md"; yes 'relleno' | head -n 80 >> "$SANDBOX/l.md"
lint_receta "$SANDBOX/l.md" >/dev/null && malo "acepto 90 lineas"

caso "81 lineas SIN salto final => 1 (wc -l las subcontaria)"
buena "$SANDBOX/l81.md"; yes 'relleno' | head -n 66 >> "$SANDBOX/l81.md"; printf 'ultima sin salto' >> "$SANDBOX/l81.md"
lint_receta "$SANDBOX/l81.md" >/dev/null && malo "acepto 81 lineas por falta de salto final"

caso "nombre distinto del archivo => 1; igual => 0"
buena "$SANDBOX/otro.md"     # nombre: bug pero archivo otro.md
lint_receta "$SANDBOX/otro.md" >/dev/null && malo "acepto nombre != archivo"
cp "$SANDBOX/otro.md" "$SANDBOX/bug.md"; lint_receta "$SANDBOX/bug.md" >/dev/null || malo "rechazo bug.md con nombre: bug"

caso "'right ' no es termino prohibido; 'gt ' si"
buena "$SANDBOX/r.md"; printf 'Mueve el boton a la right side.\n' >> "$SANDBOX/r.md"
lint_receta "$SANDBOX/r.md" >/dev/null || malo "rechazo 'right ' como si fuera 'gt '"

caso "TAB en el titulo => 1"
buena "$SANDBOX/t.md"; sed -i "s/^titulo: .*/titulo: Con\ttab/" "$SANDBOX/t.md"
lint_receta "$SANDBOX/t.md" >/dev/null && malo "acepto TAB en el titulo"

caso "CRLF se tolera en lectura"
buena "$SANDBOX/crlf.md"; sed -i 's/$/\r/' "$SANDBOX/crlf.md"
lint_receta "$SANDBOX/crlf.md" >/dev/null || malo "rechazo una receta CRLF"

caso "manifest_linea: 5 campos TAB y el titulo de varias palabras entero"
buena "$SANDBOX/m.md"
linea="$(manifest_linea "$SANDBOX/m.md")"
[ "$(printf '%s' "$linea" | awk -F'\t' '{print NF}')" = 5 ] || malo "no son 5 campos: $linea"
[ "$(printf '%s' "$linea" | cut -f5)" = "Arreglar algo que no funciona" ] || malo "titulo partido: $linea"

caso "00-lider marcado tipo: receta => 1 (no tiene Pasos/Recibo)"
printf -- '---\nsaikit_owned: summonaikit-claude\ntipo: receta\nnombre: lider\ntitulo: Lider\ncarril: full\ncuando: ["x"]\nadversary: opcional\n---\n## Principios\n' > "$SANDBOX/lider-mal.md"
lint_receta "$SANDBOX/lider-mal.md" >/dev/null && malo "acepto un lider marcado receta sin secciones de receta"

# ---------------------------------------------------------- el repo real
caso "todas las recetas del repo pasan el linter"
for f in "$repo"/recetas/*.md; do
  out="$(lint_receta "$f")" || malo "$(basename "$f"): $out"
done
caso "el manifiesto esta al dia (gen --check)"
bash "$repo/tools/gen-recetas-manifest.sh" --check >/dev/null || malo "MANIFEST.sha256 desactualizado: corre tools/gen-recetas-manifest.sh"

[ "$fail" -eq 0 ] && echo "test_recetas: OK" || { echo "test_recetas: FAIL" >&2; exit 1; }
```

- [ ] **Paso 3: correrlo y ver el rojo** — `bash tests/test_recetas.sh`.
  Esperado: FAIL (no existen `recetas/` ni el generador). Guardar la salida
  para citarla en el PR.

- [ ] **Paso 4: el generador del manifiesto**

```bash
#!/usr/bin/env bash
# tools/gen-recetas-manifest.sh — Task 16.2 (D1). Escribe recetas/MANIFEST.sha256
# (TSV, LF, ordenado por nombre). Corre el linter ANTES de incluir un archivo:
# un frontmatter roto no entra al manifiesto (la validez se garantiza aqui, no
# en el hook). `--check` compara sin escribir (exit 1 si difiere).
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; repo="$(cd "$here/.." && pwd)"
. "$repo/tests/lib/recetas_lint.sh"
dir="$repo/recetas"; out="$dir/MANIFEST.sha256"; modo="${1:-}"
tmp="$(mktemp "${TMPDIR:-/tmp}/saikit-manifest-XXXXXX")" || exit 5
rc=0
for f in "$dir"/*.md; do
  motivo="$(lint_receta "$f")" || { printf '[gen-recetas-manifest] %s: %s\n' "$(basename "$f")" "$motivo" >&2; rc=1; continue; }
  manifest_linea "$f" >> "$tmp"
done
[ "$rc" -eq 0 ] || { rm -f "$tmp"; exit 1; }
sort -t"$(printf '\t')" -k3,3 "$tmp" > "$tmp.sorted" || { rm -f "$tmp" "$tmp.sorted"; exit 5; }
if [ "$modo" = "--check" ]; then
  # cmp devuelve 2 si $out no existe: se normaliza a 1 (difiere) para que el
  # llamador no confunda "no hay manifiesto" con "ok" (CodeRabbit, PR #97).
  if [ -f "$out" ] && cmp -s "$tmp.sorted" "$out"; then rc=0; else rc=1; fi
  rm -f "$tmp" "$tmp.sorted"; exit $rc
fi
mv -f "$tmp.sorted" "$out" || { rm -f "$tmp" "$tmp.sorted"; exit 5; }
rm -f "$tmp"; printf '[gen-recetas-manifest] %s lineas -> %s\n' "$(awk 'END{print NR}' "$out")" "$out"
```

- [ ] **Paso 5: `.gitattributes`** — agregar al final:

```
recetas/** text eol=lf
recetas/MANIFEST.sha256 text eol=lf
```

- [ ] **Paso 6: `recetas/00-lider.md`** (`tipo: lider`, ≤80 líneas, español).
  Secciones y contenido mínimo:
  - frontmatter: `saikit_owned`, `tipo: lider`, `nombre: lider`, `titulo: Reglas del líder`.
  - `## Principios del líder` (uno por línea, cada uno con `Cuándo:`):
    Experiencia primero (elige el deleite del usuario sobre la comodidad de
    implementar; menos y mejor pulido). Agota el espacio de diseño (sin
    precedente ⇒ 2–3 bocetos antes de decidir; nunca preguntes "cómo"). No
    bloquees al humano (reversible/técnico ⇒ decide y presenta; irreversible
    — force-push, borrar datos, mensajes a terceros, deploy, pagos — ⇒ pregunta
    y `PAUSED`). Codifica la lección en estructura (si te sorprendes escribiendo
    la misma instrucción dos veces, vuélvela lint, test o script).
  - `## Brief para delegar` — plantilla de 8 campos: GOAL, SCOPE, CONTEXT,
    ACCEPTANCE, VERIFY, TIMEBOX, FORBIDDEN, REPORT (REPORT incluye "Lo que ves":
    el resultado observable en palabras simples). "Un campo que no puedes
    llenar es una unidad que no has acotado."
  - `## Regla de preguntar` — dos ramas (arriba) + "un hecho que se observa
    corriendo algo no es pregunta para el humano: boceto".
  - `## Descripción de un PR` — Why / Scope / Tradeoffs / Blast radius /
    Verification; nunca draft; 5 PRs chicos antes que 1 grande.
  - `## Cuando retomas trabajo ajeno` — el rastro previo es autoritativo; no
    rehagas; verifica lo heredado contra el artefacto real.
  - `## Voz` — 5 reglas: sin frases de chatbot, sin puffery, sin adulación,
    sin conclusiones genéricas, "di qué hace, no cómo se siente"; nunca
    inventes un link, cita o comando que no hayas producido o leído.

- [ ] **Paso 7: las 6 recetas** (cada una `tipo: receta`, ≤80 líneas, con
  `## Pasos` numerados copiables, `## Qué le dices al usuario`, `## Recibo`).
  Contenido mínimo por receta (adaptación en español; sin nombrar Cursor,
  Graphite ni Bugbot):
  - **`bug`** (`carril: full`, `adversary: opcional`, `cuando: ["no funciona",
    "se rompió", "da error", "está mal"]`). Pasos: (1) Reprodúcelo tú, en la
    misma superficie (app real o comando); si no reproduce, fuerza el
    disparador o instrumenta hasta que dispare — "un bug que no reproduces no
    lo puedes dar por arreglado". (2) Busca la causa por bisección: hipótesis
    → evidencia en ejecución → descarta; no adivines. (3) El test que falla
    ANTES del fix (regla de hierro del repo), commit aparte. (4) El cambio más
    chico que la evidencia justifica; nada "por si acaso". (5) Verifica en la
    misma superficie: el repro original ya pasa; "inconcluso" no es PASS.
    (6) PR con Why/Scope/Verification y el repro rojo→verde pegado.
    Qué le dices: qué estaba roto, la causa en una frase, qué cambia para él.
    Recibo: `Understand: … Receta: bug`; `Verify:` con el comando del repro.
  - **`funcion`** (`full`, `adversary: opcional`; obligatorio si toca auth,
    pagos, migraciones o datos preexistentes). Pasos: (1) Nombra los datos
    primero (qué entidades, qué forma, dónde viven) y su estructura (máquina
    de estados en vez de booleanos sueltos; tabla/registro en vez de
    if/else repetido). (2) Confirma que la fuente de datos existe; si no,
    decláralo y construye la rebanada completa (fuente, escritura, lectura,
    pantalla). (3) Escribe el brief y delega con él. (4) Cubre la matriz:
    cargando / vacío / error / éxito; accesibilidad básica. (5) Verifica en
    la superficie real. (6) Si cambia una interacción, el usuario la ve con
    captura antes de dar por hecho ("review gate"). (7) PR.
  - **`refactor`** (`full`, `opcional`). Pasos: (1) Pinea el comportamiento
    con un test de caracterización ANTES de mover nada (typecheck no es pin).
    (2) Nombra la estructura que falta. (3) Resta antes de sumar: borra código
    muerto, wrappers de un solo llamador. (4) Mueve en pasos chicos con el pin
    verde; migra todos los llamadores y borra la API vieja en la misma ola;
    sin shims. (5) Prueba que el comportamiento no cambió en el artefacto
    real. (6) Si el diff no baja la carga de lectura, revierte. (7) PR.
  - **`lento`** (`full`, `opcional`). Pasos: (1) Mide la línea base con un
    comando repetible (mediana de N). (2) Hipótesis desde la medición, no
    desde el código; familias: eliminar trabajo, dividir, cachear (nombra qué
    lo invalida), indirección, lotes, redundancia, perezoso, reprogramar.
    (3) Un cambio, una medición; se queda solo si mueve la aguja más que el
    ruido. (4) Mide después; cita antes/después/delta en el PR. (5) PR.
  - **`investigar`** (`fast`, `opcional`). Pasos: (1) Lee con el grafo del
    código (codebase-memory: `search_graph`, `trace_path`) y el historial
    (`git log`, docs, ledger). (2) Responde con evidencia citada: qué es /
    cómo funciona / dónde vive / con qué te vas a tropezar. (3) Distingue
    "es" de "parece que"; nombra los huecos; lo que no encontraste es
    evidencia, no ausencia. (4) Sin cambiar código; si la respuesta pide un
    cambio, dilo y para. Qué le dices: definición simple primero, luego cómo,
    luego por qué; diagrama si ayuda. Recibo: `Implement: sin cambio de
    código`; `Verify: no corrí tests — pregunta de solo lectura`.
  - **`boceto`** (`fast`, `opcional`). Pasos: (1) Nombra la decisión que el
    boceto va a resolver; sin decisión no hay boceto. (2) Construye 2–3
    variantes desechables en un directorio aparte (`boceto/`), con la pila
    más liviana; sin tests, sin abstracciones, **nunca en código de
    producción**. (3) Muéstralas juntas (un conmutador) y observa: captura o
    salida. (4) Recomienda una con tradeoffs; la real se construye con
    `funcion`. Recibo: `Implement: boceto desechable en boceto/, sin código de
    producción`; `Verify:` con la captura o salida observada.

- [ ] **Paso 8: generar el manifiesto y poner el test en verde**

```bash
mkdir -p recetas/pendientes && : > recetas/pendientes/.gitkeep
bash tools/gen-recetas-manifest.sh
bash tests/test_recetas.sh          # esperado: test_recetas: OK
bash -n tests/lib/recetas_lint.sh tests/test_recetas.sh tools/gen-recetas-manifest.sh   # solo lo tocado
```

- [ ] **Paso 9: rojo/verde del candado del manifiesto** — editar una línea de
  `recetas/bug.md`, correr `bash tools/gen-recetas-manifest.sh --check; echo $?`
  ⇒ `1`; regenerar ⇒ `0`. Anotar ambos en el PR.

- [ ] **Paso 10: commit y PR**

```bash
git add recetas tests/lib/recetas_lint.sh tests/test_recetas.sh tools/gen-recetas-manifest.sh .gitattributes
git commit -m "feat(16.2): recetario fuente (6 recetas + 00-lider), manifiesto TSV y linter"
```
Push en su comando, PR en otro (ver Restricciones). En el PR: salida del rojo
(paso 3), del verde (paso 8) y del candado (paso 9).

---

### Task 16.3 — Principios por rol en `agents/*.md`

**Archivos:**
- Modificar: `agents/implementer.md`, `agents/reviewer.md`, `agents/verifier.md`, `agents/adversary.md`
- Test existente que debe seguir verde: `tests/test_adversary_artifact_contract.sh` (lee `adversary.md` y `reviewer.md`); los del instalador (`test_install_hook.sh`) comparan plantillas — solo en local Windows.

**Interfaces:**
- Produce: en cada perfil, una sección `## Principios` con un bloque por
  principio: `**<Nombre>.** Cuándo: <una línea>. Regla: <1–2 líneas>.` — la
  línea `Cuándo:` es el ancla del DoD (`grep -c '^Cuándo:'` NO; se cuenta
  `grep -c 'Cuándo:'` porque va dentro del bloque).

- [ ] **Paso 1: implementer** — agregar `## Principios` con 12 bloques:
  Protocolo de pereza (borra primero; ≤3 capas; el cambio más chico),
  Pensamiento fundacional (tipos y datos antes que lógica), Resta antes de
  sumar, Modela el dominio (máquina de estados / registro / modelo tipado; la
  señal: "una rama más al if"), Disciplina de tipos (estados ilegales
  irrepresentables; parsea en la frontera; nada de `any`), Idempotencia (¿si
  corre dos veces? ¿si murió a la mitad?), Migra llamadores y borra lo viejo
  en la misma ola, Arregla la causa raíz (reproduce primero; nada de
  nil-checks que callan el crash), Unidades verificables (chico + check
  enfocado por unidad; ceremonia y batería UNA vez al final), y las 3 de
  `architect`: escribe primero cómo lo usa el llamador; señales rojas de
  diseño (parámetros que se pasan sin usarse, flags booleanos que se
  multiplican); fricción repetida = rediseña, no parches.
- [ ] **Paso 2: reviewer** — `## Principios` con 4 (Minimiza la carga del
  lector — el test de los 30 s: "¿de dónde sale X y quién lo cambia?" —,
  Resta antes de sumar, Modela el dominio, Migra y borra) + sección
  `## Comentarios y supresiones` (comentario narrativo, banner, código
  comentado, `eslint-disable`/`@ts-ignore` que tapan un bug real ⇒ hallazgo;
  excepciones: licencia, doc de API pública, link a issue, comportamiento
  forzado por dependencia externa) + sección `## Adjudicación en cuatro cubos`
  (Act on / Consider / Noted / Dismissed, cada hallazgo de adversary, blast o
  bot cae en uno con razón; consenso entre dos revisores independientes =
  alta confianza).
- [ ] **Paso 3: verifier** — `## Principios`: Demuéstralo (contra el artefacto
  real, no "compila"; si la verificación falla, sospecha primero del método
  de observación; artefactos, no autorreportes de subagentes), "Mejor ningún
  test que un test malo, y decláralo", y `## Redacción antes de escribir`
  (mismos patrones que `adversary.md` § redacción: valores de token/password/
  secret/api_key, `sk-…`, credenciales en URIs ⇒ `[REDACTED]` ANTES de
  escribir cualquier archivo).
- [ ] **Paso 4: adversary** — `## Principios`: Idempotencia (las 3 preguntas
  como ataque #5, falla parcial).
- [ ] **Paso 5: consolidar `Boundary Discipline`** — hoy la idea vive en el
  contrato ("Run guards before side effects"), en `implementer.md` ("Guards
  before side effects") y en `reviewer.md` ("validation/types align across
  the boundaries"). Dejar UNA sección `## Boundary Discipline` en
  `implementer.md` (guardas en la frontera, confía en los tipos adentro,
  lógica pura) y en `reviewer.md` solo una referencia de una línea a esa
  sección. La palabra `boundary` del ataque "trust boundary" de
  `adversary.md` NO se toca.
- [ ] **Paso 6: DoD por grep** (correr y pegar en el PR):

```bash
for r in implementer reviewer verifier adversary; do printf '%s: %s Cuándo\n' "$r" "$(grep -c 'Cuándo:' agents/$r.md)"; done
grep -l '^## Boundary Discipline' agents/*.md | wc -l      # esperado: 1
grep -c 'saikit_owned: summonaikit-claude' agents/*.md    # 1 por archivo
bash tests/test_adversary_artifact_contract.sh            # OK
```
Esperado: implementer 12, reviewer 4, verifier 2, adversary 1.

- [ ] **Paso 7: commit y PR** — `docs(16.3): principios por rol en los cuatro perfiles`.

---

### Task 16.4 — El menú de recetas en el contrato

**Archivos:**
- Modificar: `hooks/summonaikit-harness.sh` — junto a `HOOK_DIR` (línea ~67),
  antes de `harness_context()` (~1059), dentro del heredoc `HARNESS_CONTEXT`
  (regla de delegación ~1093, bloque "Missing-information rule" ~1148, línea
  `Close:` ~1175) y la sustitución final (~1179).
- Modificar: `tests/lib/gate_cases.sh` (3 casos + alta en `CASOS_G1`),
  `tests/test_gate_mutations.sh` (1 mutación), `tests/golden/baseline.txt`
  (regrabada con diff auditado).

**Interfaces:**
- Consume: `recetas/MANIFEST.sha256` (TSV de 16.2).
- Produce: en el estado del hook nada nuevo; en el contrato, el bloque
  `Recipes (recetario):` con el menú, o la línea fija
  `No recipe book on this host: follow this contract as usual.`

- [ ] **Paso 1: rojo — escribir los casos primero** (en `tests/lib/gate_cases.sh`,
  molde `caso_g1_contrato_muestra_forma_recibo`; agregar los tres nombres a
  `CASOS_G1`):

```bash
# Task 16.4 (D1/D4): el contrato ofrece SOLO las recetas cuyo sha256 instalado
# coincide con el manifiesto; sin manifiesto, linea fija y contrato identico.
_recetas_lab() {  # planta un recetario minimo en $LAB/hooks/recetas y exporta el override
  mkdir -p "$LAB/hooks/recetas"
  printf -- '---\nsaikit_owned: summonaikit-claude\nnombre: bug\ntitulo: Arreglar algo que no funciona\ncarril: full\ncuando: ["x"]\nadversary: opcional\n---\n## Pasos\n1. a\n## Qué le dices al usuario\nb\n## Recibo\nc\n' > "$LAB/hooks/recetas/bug.md"
  printf '%s\treceta\tbug\tfull\tArreglar algo que no funciona\n' "$(sha256sum "$LAB/hooks/recetas/bug.md" | cut -c1-64)" > "$LAB/hooks/recetas/MANIFEST.sha256"
  export SAIKIT_RECETAS_DIR="$LAB/hooks/recetas"
}
caso_g1_contrato_nombra_recetario() {
  _recetas_lab
  lab_run prompt claude "$(lab_payload_prompt '-saikit arregla el login')"
  unset SAIKIT_RECETAS_DIR
  _igual "exit code" "$LAB_RC" "0"
  _contiene "stdout" "$LAB_OUT" 'Recipes (recetario):'
  _contiene "stdout" "$LAB_OUT" 'bug — Arreglar algo que no funciona — full'
  _contiene "stdout" "$LAB_OUT" 'Receta: <nombre>'
  _contiene "stdout" "$LAB_OUT" 'skip: <razón>'
  _no_contiene "stdout" "$LAB_OUT" "$LAB/hooks/recetas"     # D1: sin ruta absoluta
}
caso_g1_sin_recetario_contrato_igual() {
  export SAIKIT_RECETAS_DIR="$LAB/hooks/no-existe"
  lab_run prompt claude "$(lab_payload_prompt '-saikit arregla el login')"
  unset SAIKIT_RECETAS_DIR
  _igual "exit code" "$LAB_RC" "0"
  _contiene "stdout" "$LAB_OUT" 'No recipe book on this host'
  _no_contiene "stdout" "$LAB_OUT" 'Recipes (recetario):'
}
caso_g1_receta_hash_distinto_se_omite() {
  _recetas_lab
  printf '\nlinea editada por alguien\n' >> "$LAB/hooks/recetas/bug.md"   # el hash ya no coincide
  lab_run prompt claude "$(lab_payload_prompt '-saikit arregla el login')"
  unset SAIKIT_RECETAS_DIR
  _no_contiene "stdout" "$LAB_OUT" 'bug — Arreglar'
  _contiene "stdout" "$LAB_OUT" 'omitted: hash mismatch (bug)'
}
```

- [ ] **Paso 2: correr los tres casos contra el hook de la rama y ver el rojo**

```bash
SAIKIT_HOOK_VIVO="$PWD/hooks/summonaikit-harness.sh" bash tests/test_gate_behavior.sh
```
(medido: el driver itera `casos_de_gate "$gate"` en su línea 67 y no acepta
una lista acotada por entorno; es UN archivo, 2–4 min en Windows, y es lo
único local que se corre. Sin `SAIKIT_HOOK_VIVO` mide el hook INSTALADO y da
rojo masivo falso.) Esperado: exactamente los 3 casos nuevos en FAIL.

- [ ] **Paso 3: el menú en el hook** — junto a `HOOK_DIR`:

```bash
# Task 16.4 (D1): recetario. Solo el manifiesto se lee en runtime (un cat +
# sha256sum por receta); NUNCA se parsea frontmatter aqui. Override de entorno
# para el lab/golden (la ruta real cambia por corrida y NO se imprime).
RECETAS_DIR="${SAIKIT_RECETAS_DIR:-$HOOK_DIR/recetas}"
recetas_menu() {  # stdout: bloque del contrato (menu o linea fija). Fail-open.
  local m="$RECETAS_DIR/MANIFEST.sha256" sha tipo nombre carril titulo real n=0 omit=""
  if [ ! -r "$m" ]; then printf '%s\n' 'No recipe book on this host: follow this contract as usual.'; return 0; fi
  while IFS="$(printf '\t')" read -r sha tipo nombre carril titulo; do
    [ "$tipo" = "receta" ] || continue
    real="$(sha256sum "$RECETAS_DIR/$nombre.md" 2>/dev/null | cut -c1-64)"
    if [ -n "$real" ] && [ "$real" = "$sha" ]; then
      [ "$n" -eq 0 ] && printf '%s\n' 'Recipes (recetario): pick ONE that matches the task, read it in full, copy its steps into your todolist before reasoning, and declare it in the receipt as "Understand: ... Receta: <nombre>". A step you skip stays listed as "skip: <razón>". If none matches, follow this contract as usual.'
      printf -- '- %s — %s — %s\n' "$nombre" "$titulo" "$carril"; n=$((n+1))
    else
      omit="$omit $nombre"
    fi
  done < "$m"
  [ "$n" -eq 0 ] && printf '%s\n' 'No recipe book on this host: follow this contract as usual.'
  [ -n "$omit" ] && for x in $omit; do printf '%s\n' "(recipe omitted: hash mismatch ($x) — reinstall with tools/install-hook.sh)"; done
  return 0
}
```

  En `harness_context()`: dentro del heredoc, justo ANTES de `Delegation rule:`,
  una línea `$RECETAS_MENU` sola; y la sustitución final pasa a:

```bash
  _menu="$(recetas_menu)"
  _hc="${_hc//\$TOOL_HINT/$TOOL_HINT}"
  printf '%s' "${_hc//\$RECETAS_MENU/$_menu}"
```

  Además, en la regla de delegación, tras la línea "Delegate the implement,
  verify, and review gates…": `- Write the brief with the 8 fields of
  recetas/00-lider.md (GOAL, SCOPE, CONTEXT, ACCEPTANCE, VERIFY, TIMEBOX,
  FORBIDDEN, REPORT) when the recipe book is present.`

- [ ] **Paso 4: la regla de preguntar (D7)** — reemplazar el segundo y tercer
  guion del bloque `Missing-information rule` por:

```
- Two branches, always: (a) technical or reversible → decide it yourself from the repo and present the result; (b) product, preference or IRREVERSIBLE (force-push, deleting data, messages to third parties, deploys, payments) → ask the smallest set of plain-language questions FIRST and end the turn with the PAUSED line. A fact you could observe by running something is never a question for the human: sketch it (recipe boceto) and let the result decide.
```

- [ ] **Paso 5: `Close:` (D8/D14)** — al final de la línea `Close:` del recibo
  agregar: `Say first what changes for the user, then how, then why; never
  invent a link, citation or command you did not produce or read this turn.`

- [ ] **Paso 6: verde** — repetir el comando del paso 2 ⇒ 3 OK. Correr también
  `caso_g1_contrato_muestra_forma_recibo` y `caso_g1_contrato_nombra_adversary`
  (siguen verdes) y `bash tests/test_hook_source.sh` (el caso 131 "misma salida
  con la fuente del repo" tiene que seguir verde sin recetario).

- [ ] **Paso 7: mutación** — en `tests/test_gate_mutations.sh`, línea en
  `MUTACIONES=`: `G1|menu_recetas_apagado|el menu del recetario se apaga y el contrato deja de ofrecer recetas aun con manifiesto valido`
  y la función:

```bash
mut_menu_recetas_apagado() { sed 's/^  if \[ ! -r "\$m" \]; then printf/  if true; then printf/'; }
```
  Correr acotado: `SAIKIT_MUTACIONES='menu_recetas_apagado' bash tests/test_gate_mutations.sh`
  ⇒ la mutación tiene que poner rojo a `caso_g1_contrato_nombra_recetario` y a
  NINGÚN otro. Pegar la línea de acreditación en el PR.

- [ ] **Paso 8: golden** — `bash tools/golden-harness.sh --hook "$PWD/hooks/summonaikit-harness.sh" --check`
  ⇒ divergencias SOLO en los escenarios que imprimen el contrato (la línea
  fija nueva y el párrafo de D7). Regrabar: `--record`, `git diff --stat
  tests/golden/baseline.txt` y `git diff tests/golden/baseline.txt | grep '^[-+]' | grep -v '^[-+][-+]' | sort | uniq -c | sort -rn | head -20`
  pegados en el PR: 0 veredictos movidos (solo texto del contrato).

- [ ] **Paso 9: commit y PR** — `feat(16.4): menú de recetas en el contrato por manifiesto (D1/D4), regla de preguntar en dos ramas (D7)`.

---

### Task 16.5 — El instalador planta `recetas/` y `/sencillo`; ACL y checker

**Archivos:**
- Modificar: `tools/install-hook.sh` (nueva función `instalar_recetas_claude`
  llamada desde el flujo por defecto — el que instala en `~/.claude/hooks` — y
  desde `--host claude`; respeta `DRY_RUN`), `tools/check-hook-registration.sh`
  (advisory nuevo), `tools/hook-acl.ps1` (acepta rutas extra),
  `tests/test_install_hook.sh` (5 casos), `tests/test_hook_registration.sh`
  (1 caso), `tests/test_hook_acl.sh` (1 caso).
- Crear: `skills/sencillo/SKILL.md` (fuente del kit; el instalador la copia a
  `~/.claude/skills/sencillo/SKILL.md`).

**Interfaces:**
- Consume: `agente_estado_con_vendor <dest> <fuente> <rol>` (devuelve `AUSENTE`
  / `NUESTRO_IDENTICO` / `NUESTRO_DISTINTO` / `VENDOR_CONOCIDO` / `DESCONOCIDO`
  / `NO_OBSERVABLE`); `zcode_agente_tiene_marca <archivo>` (busca
  `saikit_owned:` en el frontmatter — las recetas y la skill lo llevan).
- Produce: `<hookdir>/recetas/{*.md,MANIFEST.sha256}` y
  `~/.claude/skills/sencillo/SKILL.md` con la misma marca.

- [ ] **Paso 1: la skill** — `skills/sencillo/SKILL.md`:

```markdown
---
name: sencillo
description: Reformula tu último mensaje en palabras simples, sin jerga ni rutas, para alguien que no lee código. Usar cuando el usuario diga "explícamelo sencillo", "en cristiano" o "/sencillo".
saikit_owned: summonaikit-claude
---
Reescribe tu último mensaje para una persona que no lee código: primero qué cambia para ella, luego cómo, luego por qué. Sin nombres de archivos, sin comandos, sin siglas sin explicar. Máximo 8 líneas.
```

- [ ] **Paso 2: rojo — casos del instalador** (en `tests/test_install_hook.sh`,
  siguiendo el molde de los casos de `--host claude`; el sandbox del test ya
  simula `HOME`):
  1. limpio: tras instalar, `<hookdir>/recetas/MANIFEST.sha256` y las 7
     recetas existen y `cmp` con la fuente da idéntico; `skills/sencillo/SKILL.md`
     también.
  2. dos corridas seguidas: la segunda no reescribe (mtime igual, sin backup nuevo).
  3. archivo ajeno: `recetas/ajena.md` sin marca ⇒ queda intacto y el instalador
     lo reporta como `DESCONOCIDO`; las nuestras se instalan igual.
  4. `--dry-run`: no crea `recetas/` ni la skill; reporta por archivo.
  5. instalación a medias imposible: una receta fuente ilegible (chmod 000 en
     el sandbox) ⇒ exit ≠ 0 y NINGÚN archivo publicado (clasifica todo antes de
     publicar, precedente 12.9).
  6. `--quitar-recetas`: borra SOLO los archivos con marca `saikit_owned` (y
     el manifiesto) de `<hookdir>/recetas/` y `skills/sencillo/SKILL.md`; un
     archivo ajeno en `recetas/` queda intacto y el directorio también.
  Correr: `bash tests/test_install_hook.sh` ⇒ los 6 nuevos en FAIL.

- [ ] **Paso 3: la función — todo o nada POR DIRECTORIO** (Greptile + CodeRabbit,
  PR #97: publicar archivo por archivo dejaba una instalación a medias si
  fallaba el segundo, y el contrato del instalador promete "exit ≠ 0 ⇒ el
  destino quedó intacto"). Se arma el directorio nuevo COMPLETO en un temporal
  hermano (copia de lo ajeno que ya estaba + nuestros archivos) y se
  intercambia con dos `mv` al final; hasta el intercambio no se tocó nada.

```bash
# Task 16.5 (D1/D8): planta el recetario y la skill /sencillo con la maquina de
# estados POR ARCHIVO de los perfiles (marca saikit_owned; ajeno => DESCONOCIDO,
# no se toca). Clasifica TODO antes de escribir nada (12.9) y publica cada
# directorio de un solo golpe (dos renames); la ventana entre los dos mv se
# declara, no se esconde.
recetas_clasificar() {  # $1=dest $2=fuente → estado (el manifiesto no lleva frontmatter)
  if [ "$(basename "$2")" = "MANIFEST.sha256" ]; then
    if [ ! -e "$1" ]; then printf AUSENTE; elif cmp -s "$1" "$2"; then printf NUESTRO_IDENTICO; else printf NUESTRO_DISTINTO; fi
  else
    agente_estado_con_vendor "$1" "$2" "receta"
  fi
}
recetas_publicar_dir() {  # $1=dir_destino  $2..=fuentes → 0 ok / 5 nada tocado
  local destdir="$1"; shift
  local f dest est nuevo old cambios=0
  # 1) clasificar todo; cualquier NO_OBSERVABLE aborta sin escribir
  for f in "$@"; do
    dest="$destdir/$(basename "$f")"
    est="$(recetas_clasificar "$dest" "$f")"
    case "$est" in
      NO_OBSERVABLE) decir "[summonaikit] recetario: $dest no observable; no se publica nada"; return 5 ;;
      NUESTRO_IDENTICO) ;;
      DESCONOCIDO) decir "[summonaikit] recetario: DESCONOCIDO, no se toca: $dest" ;;
      *) decir "[summonaikit] recetario: $est -> $dest"; cambios=1 ;;
    esac
  done
  [ "$cambios" -eq 1 ] || return 0
  [ "$DRY_RUN" -eq 0 ] || return 0
  # 2) armar el directorio nuevo entero en un temporal hermano. Los respaldos
  #    de lo reemplazado van DENTRO del temporal (saikit-backups/), no al
  #    directorio vivo: escribirlos en el vivo rompia el todo-o-nada y el swap
  #    los borraba con $old (Greptile, PR #97).
  nuevo="$(mktemp -d "$(dirname "$destdir")/.saikit-recetas-XXXXXX")" || return 5
  if [ -d "$destdir" ]; then cp -p "$destdir"/. "$nuevo"/ 2>/dev/null || { rm -rf "$nuevo"; return 5; }; fi
  sello="$(date +%Y%m%d-%H%M%S)"
  for f in "$@"; do
    dest="$destdir/$(basename "$f")"
    case "$(recetas_clasificar "$dest" "$f")" in
      AUSENTE|NUESTRO_DISTINTO|VENDOR_CONOCIDO)
        if [ -e "$dest" ]; then
          mkdir -p "$nuevo/saikit-backups" && cp -p "$dest" "$nuevo/saikit-backups/$(basename "$dest").nuestro.$sello.bak" || { rm -rf "$nuevo"; return 5; }
        fi
        cp "$f" "$nuevo/$(basename "$f")" || { rm -rf "$nuevo"; return 5; } ;;
    esac
  done
  # 3) intercambio: hasta aqui $destdir esta intacto
  old="$destdir.saikit-old-$$"
  if [ -d "$destdir" ]; then mv "$destdir" "$old" || { rm -rf "$nuevo"; return 5; }; fi
  mv "$nuevo" "$destdir" || { [ -d "$old" ] && mv "$old" "$destdir"; return 5; }
  rm -rf "$old"
  return 0
}
instalar_recetas_claude() {  # $1=hookdir  $2=skills_dir
  local f
  for f in "$repo"/recetas/*.md "$repo/recetas/MANIFEST.sha256" "$repo/skills/sencillo/SKILL.md"; do
    [ -r "$f" ] || { decir "[summonaikit] instalador: fuente no observable: $f"; return 5; }
  done
  recetas_publicar_dir "$1/recetas" "$repo"/recetas/*.md "$repo/recetas/MANIFEST.sha256" || return $?
  recetas_publicar_dir "$2/sencillo" "$repo/skills/sencillo/SKILL.md" || return $?
  for f in "$1"/recetas/*.md; do   # ajenos: solo reportar
    [ -e "$f" ] || continue
    [ -e "$repo/recetas/$(basename "$f")" ] || decir "[summonaikit] recetario: archivo ajeno reportado, intacto: $f"
  done
  return 0
}
quitar_recetas_claude() {  # $1=hookdir  $2=skills_dir — borra SOLO lo nuestro
  local f
  for f in "$1"/recetas/*.md "$2/sencillo/SKILL.md"; do
    [ -f "$f" ] || continue
    if zcode_agente_tiene_marca "$f"; then
      [ "$DRY_RUN" -eq 0 ] && rm -f "$f"; decir "[summonaikit] recetario: quitado $f"
    else
      decir "[summonaikit] recetario: ajeno, intacto: $f"
    fi
  done
  # El manifiesto no lleva marca: es NUESTRO si cada receta que nombra lleva
  # la marca (o ya no existe). Comparar contra el manifiesto del repo no sirve
  # tras un upgrade del kit sin reinstalar (Greptile, PR #97): el instalado
  # viejo difiere del actual y seguiria siendo nuestro.
  local m="$1/recetas/MANIFEST.sha256" nuestro=1 sha tipo nombre carril titulo
  if [ -f "$m" ]; then
    while IFS="$(printf '\t')" read -r sha tipo nombre carril titulo; do
      [ -f "$1/recetas/$nombre.md" ] || continue
      zcode_agente_tiene_marca "$1/recetas/$nombre.md" || nuestro=0
    done < "$m"
    if [ "$nuestro" -eq 1 ]; then
      [ "$DRY_RUN" -eq 0 ] && rm -f "$m"; decir "[summonaikit] recetario: quitado el manifiesto"
    else
      decir "[summonaikit] recetario: el manifiesto nombra recetas ajenas, intacto: $m"
    fi
  fi
  return 0
}
```
  Nota de orden: `quitar_recetas_claude` evalúa el manifiesto ANTES de borrar
  las recetas (mueve el bloque del manifiesto arriba del bucle, o guarda la
  decisión en una variable antes del `rm`), porque después del borrado ya no
  puede leer las marcas.

  Llamar `instalar_recetas_claude "$(dirname "$DEST")" "$HOME/.claude/skills" || exit $?`
  en el flujo por defecto después de publicar el hook; `--quitar-recetas`
  despacha a `quitar_recetas_claude` (requiere el flujo claude, como
  `--quitar-zcode` requiere `--host zcode`). Si el segundo directorio falla
  después de que el primero ya se intercambió, se reporta cuál quedó publicado
  y cuál no (dos directorios = dos unidades atómicas; límite declarado).

- [ ] **Paso 4: checker** — en `tools/check-hook-registration.sh`, un
  `reportar` advisory (exit 0 siempre) si falta `<hookdir>/recetas/MANIFEST.sha256`
  o si `sha256sum` de alguna receta no coincide con su línea: texto
  `[summonaikit] recetario: ausente o con hash distinto en <ruta> — el contrato
  no ofrecera esa receta`. Caso en `tests/test_hook_registration.sh`.

- [ ] **Paso 5: ACL** — `tools/hook-acl.ps1`: parámetro `-RutasExtra` (lista)
  que se suma al árbol auditado; el instalador y el checker lo llaman con
  `~/.claude/hooks/recetas`, `~/.claude/skills/sencillo`,
  `~/.claude/skills/saikit-verificar-app`, `~/.claude/skills/saikit-setup-autopilot`
  (los dos últimos pueden no existir aún: se reporta `ausente`, no error). Un
  caso en `tests/test_hook_acl.sh` (Windows-bound).

- [ ] **Paso 6: verde local (Windows)** — `bash tests/test_install_hook.sh`,
  `bash tests/test_hook_registration.sh`, `bash tests/test_hook_acl.sh` ⇒ OK;
  pegar las salidas en el PR (CI los salta con `SAIKIT_CI_LINUX=1`).
- [ ] **Paso 7: commit y PR** — `feat(16.5): el instalador planta recetas/ y /sencillo; checker y ACL los cubren`.

---

### Task 16.6 — Alias `-saikit:pregunta` / `-saikit:boceto`

**Archivos:**
- Modificar: `hooks/summonaikit-harness.sh` (detección del carril ~1455;
  escritura de `receta_alias` en el estado; línea del contrato),
  `tests/lib/gate_cases.sh` (3 casos), `tests/test_gate_mutations.sh` (2),
  `tests/golden/baseline.txt` (regrabada).

**Interfaces:**
- Produce: archivo `$STATE_DIR/receta_alias` con `investigar` o `boceto`
  (no se toca `write_state`: sus 10 campos y todos sus llamadores quedan
  intactos); línea del contrato `Fast lane by alias: this turn is
  -saikit:<alias>; the recipe is <receta>. Do NOT touch production code.`

- [ ] **Paso 1: rojo — casos** (molde `caso_g1_fast_arma_con_lane`):

```bash
caso_g1_alias_pregunta_arma_fast_y_nombra_receta() {
  lab_run prompt claude "$(lab_payload_prompt '-saikit:pregunta cómo funciona el login')"
  _igual "lane" "$(lab_estado lane)" "fast"
  _igual "receta_alias" "$(cat "$(dirname "$LAB_ESTADO_PATH")/receta_alias" 2>/dev/null)" "investigar"
  _contiene "stdout" "$LAB_OUT" 'the recipe is investigar'
}
caso_g1_alias_boceto_arma_fast_y_nombra_receta() {
  lab_run prompt claude "$(lab_payload_prompt '-saikit:boceto del login')"
  _igual "lane" "$(lab_estado lane)" "fast"
  _igual "receta_alias" "$(cat "$(dirname "$LAB_ESTADO_PATH")/receta_alias" 2>/dev/null)" "boceto"
  _contiene "stdout" "$LAB_OUT" 'Do NOT touch production code'
}
caso_g1_alias_typo_arma_full_sin_receta() {
  lab_run prompt claude "$(lab_payload_prompt '-saikit:pregunt cómo funciona')"
  _igual "lane" "$(lab_estado lane)" "full"
  [ -e "$(dirname "$LAB_ESTADO_PATH")/receta_alias" ] && _mal "receta_alias no debe existir con un typo"
}
```
  Correr acotado (como en 16.4 paso 2) ⇒ 3 FAIL. `caso_g1_sufijo_desconocido_arma_full` sigue verde.

- [ ] **Paso 2: el hook** — tras la detección de `:fast`:

```bash
  receta_alias=""
  if printf '%s' "$prompt_text" | grep -Eq '(^|[^A-Za-z0-9_/-])-saikit:pregunta([^A-Za-z0-9_-]|$)'; then lane="fast"; receta_alias="investigar"; fi
  if printf '%s' "$prompt_text" | grep -Eq '(^|[^A-Za-z0-9_/-])-saikit:boceto([^A-Za-z0-9_-]|$)'; then lane="fast"; receta_alias="boceto"; fi
```
  Después de `write_state` en el armado: `rm -f "$STATE_DIR/receta_alias";
  [ -n "$receta_alias" ] && printf '%s\n' "$receta_alias" > "$STATE_DIR/receta_alias"`.
  En `harness_context()`: nueva sustitución `$ALIAS_LINEA` (línea sola bajo el
  bloque `Fast lane (-saikit:fast):`), con
  `_alias="$(cat "$STATE_DIR/receta_alias" 2>/dev/null)"` y
  `[ -n "$_alias" ] && _alias_linea="Fast lane by alias: this turn is -saikit:$( [ "$_alias" = investigar ] && echo pregunta || echo boceto ); the recipe is $_alias. Do NOT touch production code."`
  (vacío si no hay alias).
- [ ] **Paso 3: verde** — los 3 casos OK; `caso_g1_fast_arma_con_lane`,
  `caso_g1_pelado_arma_lane_full`, `caso_g1_sufijo_desconocido_arma_full` OK.
- [ ] **Paso 4: mutaciones** — `G1|alias_pregunta_apagado|el alias -saikit:pregunta deja de bajar el carril` con
  `mut_alias_pregunta_apagado() { sed 's/-saikit:pregunta(/-saikit:NUNCA(/'; }` y
  `G1|alias_sin_receta|el alias baja el carril pero no nombra la receta` con
  `mut_alias_sin_receta() { sed 's/receta_alias="investigar"/receta_alias=""/'; }`.
  Acotado: cada una pone rojo SOLO a su caso.
- [ ] **Paso 5: golden** — `--check`; regrabar con diff auditado (la línea
  del alias solo aparece en escenarios con alias; hoy no hay ninguno ⇒ 0
  divergencias esperadas; si hay, auditar y citar).
- [ ] **Paso 6: commit y PR** — `feat(16.6): alias -saikit:pregunta/-saikit:boceto ⇒ carril fast y receta nombrada (D3)`.

---

### Task 16.7 — `model-routing.sh --task <receta>` (Optional)

**Archivos:** `tools/model-routing.sh` (junto a `rol_a_tier`), `tests/test_model_routing.sh`.

- [ ] **Paso 1: rojo** — caso: `bash tools/model-routing.sh --task bug` imprime
  `standard`; `--task investigar` ⇒ `standard`; `--task refactor` ⇒ `review`;
  `--task lento` ⇒ `verify`; `--task inexistente` ⇒ exit 2 y nada en stdout.
- [ ] **Paso 2: implementar `tarea_a_tier()`** con un `case` de 6 entradas que
  devuelve un tier EXISTENTE y nunca un ID de modelo (el candado "IDs solo en
  el router" sigue verde porque no se agrega ningún ID).
- [ ] **Paso 3: verde + commit** — `feat(16.7): --task <receta> ⇒ tier (D9)`.

---

### Task 16.8 — Un turno vivo por receta (medición)

**Archivos:** `docs/smoke-recetas-<fecha>.md` (nuevo). No toca código.
**Precondición:** 16.4 + 16.5 + 16.6 mergeadas y desplegadas por el lead.

- [ ] **Paso 1: repo descartable + staging** — `C:/dev/saikit-recetas-lab`
  (repo git con un `app.py` de 30 líneas y un test `pytest`), `bash
  tools/stage-override.sh C:/dev/saikit-recetas-lab` (pone el hook de la rama
  en `<repo>/.claude/hooks/`; el global no se toca). Copiar `recetas/` +
  manifiesto a `<repo>/.claude/hooks/recetas/`.
- [ ] **Paso 2: seis turnos**, hasta 3 por sesión de Claude Code abierta en ese
  repo (el usuario los teclea; el worker prepara los prompts y lee los
  transcripts en `~/.claude/projects/<slug>/*.jsonl`):
  `-saikit el endpoint /health devuelve 500` (bug) · `-saikit agrega una lista
  de tareas con crear y borrar` (funcion) · `-saikit limpia app.py sin cambiar
  lo que hace` (refactor) · `-saikit /health tarda 2 segundos` (lento) ·
  `-saikit:pregunta cómo funciona /health` (investigar) · `-saikit:boceto de
  la pantalla de tareas` (boceto).
- [ ] **Paso 3: evidencia por receta** en el smoke doc: cita literal del
  transcript de (a) el menú en el contrato, (b) la receta elegida en
  `Understand: … Receta: <nombre>`, (c) los pasos copiados al todolist, (d) el
  recibo cerrado (o el GATE, con su razón). Lo no observado se escribe
  `unknown`, no se rellena.
- [ ] **Paso 4: regla de activación** — una receta sin las cuatro evidencias
  se mueve a `recetas/pendientes/` (y el manifiesto se regenera) en el PR de
  este smoke. Commit: `docs(16.8): smoke de las 6 recetas`.

---

### Task 16.9 — Cierre (la ejecuta el lead)

- README: guía de usuario en español (tres palabras: construir / preguntar /
  bocetar; qué hace cada receta; `/sencillo`); spec § final con límites
  medidos; deploy vía `install-hook.sh` anotado en `docs/deploy-log.md`;
  filas 16.2–16.8 cerradas con sha/PR; archivar Phase 15 si `Plans.md` pasa de
  200 líneas. DoD: `bash tests/test_recetas.sh` + `python
  tools/check_context_docs.py . --sweep` sin hallazgos nuevos.

---

## Auto-revisión del plan (hecha por el lead antes de entregarlo)

- Cobertura del diseño: D1 (16.4 + 16.5), D2 (16.2), D3 (16.6), D4 (16.4), D5
  (16.3), D6 (16.2 `00-lider.md`), D7 (16.4 paso 4), D8 (16.5 skill + 16.4
  paso 5 + receta investigar), D9 (16.7), D10 (16.8). Sin huecos.
- Sin placeholders: cada paso trae código o el comando exacto; lo único que
  el worker redacta desde un esquema son los textos en español de recetas y
  principios (16.2 pasos 6–7, 16.3), con el contenido mínimo listado.
- Nombres consistentes: `lint_receta`, `manifest_linea`, `recetas_menu`,
  `$RECETAS_MENU`, `$ALIAS_LINEA`, `receta_alias`, `instalar_recetas_claude`,
  `SAIKIT_RECETAS_DIR` — los mismos en todas las tasks.
- Verificado por el lead en el código antes de entregar: el driver de casos
  no acepta lista acotada (16.4 paso 2); `_mal` y `LAB_ESTADO_PATH` existen en
  `tests/lib/gate_cases.sh` (16.6 paso 1); la publicación de 16.5 ya no usa
  ningún helper por archivo — es todo-o-nada por directorio con dos `mv`
  (PR #97, hilos de Greptile y CodeRabbit). Lo que sigue `unknown` hasta
  medir: si el golden cambia en 16.6 (paso 5).
