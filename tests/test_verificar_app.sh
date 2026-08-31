#!/usr/bin/env bash
# tests/test_verificar_app.sh — Task 17.1: skill `saikit-verificar-app`.
#
# Portable y corre en CI (Linux) y en Git Bash (Windows). No toca el hook
# instalado: lee TEST_RUNNER_RE de la fuente vía SAIKIT_HOOK_VIVO. Ejercita el
# generador de la skill contra dos repos fixture (node con `node --test`,
# python con pytest) y un repo sin framework, todos en sandbox:
#   - los archivos esperados aparecen bajo `verify/`;
#   - el comando de Drive incluye `verify/` y matchea TEST_RUNNER_RE LEÍDO del
#     hook con `grep -o` (no una copia pegada);
#   - repo sin framework => propone y espera el sí, no instala;
#   - el `LEEME.md` generado trae el sello con el sha REAL del fixture;
#   - sin sello => el verifier lo declara `unknown`, nunca "al día".
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
. "$here/lib/sandbox.sh"; sandbox_init

script="$repo/skills/saikit-verificar-app/verificar.sh"
fail=0
caso() { printf '  caso: %s\n' "$1"; }
malo() { printf '    FAIL: %s\n' "$1" >&2; fail=1; }
necesita() { printf '%s' "$1" | grep -q "$2" || malo "$3"; }

# La fuente del hook que define TEST_RUNNER_RE (leccion de la Task 3.5: medir
# la fuente, no el instalado).
hook_vivo="${SAIKIT_HOOK_VIVO:-$HOME/.claude/hooks/summonaikit-harness.sh}"
[ -r "$hook_vivo" ] || hook_vivo="$repo/hooks/summonaikit-harness.sh"
test_runner_re="$(sed -n "s/^TEST_RUNNER_RE='//p" "$hook_vivo" | sed "s/'$//")"
[ -n "$test_runner_re" ] || { echo "test_verificar_app: UNKNOWN — no se leyo TEST_RUNNER_RE de $hook_vivo" >&2; exit 3; }

# Crea un repo git de fixture con un commit y los archivos dados.
hacer_repo() { # $1 dir
  git -C "$1" init -q
  git -C "$1" config user.email "test@local.example"
  git -C "$1" config user.name "test"
  git -C "$1" add -A
  git -C "$1" commit -qm "fixture"
  git -C "$1" rev-parse HEAD
}

generar() { # $1 repo -> corre el generador de la skill con el hook fuente
  SAIKIT_HOOK_VIVO="$hook_vivo" TMPDIR="$TMPDIR" bash "$script" generar "$1"
}

# ------------------------------------------------------ repo node (node --test)
caso "repo node: genera verify/ con los archivos esperados"
node_repo="$SANDBOX/app-node"; mkdir -p "$node_repo"
printf 'console.log("Entraste. Bienvenido.");\n' > "$node_repo/app.js"
cat > "$node_repo/package.json" <<'EOF'
{ "name": "app-node", "scripts": { "test": "node --test" } }
EOF
node_sha="$(hacer_repo "$node_repo")" || malo "no pudo crear el repo node"
gen_out="$(generar "$node_repo")" || malo "generar fallo en node: $gen_out"
for f in LEEME.md Launch.md Doctor.md Drive.md Evidence.txt Cleanup.md; do
  [ -f "$node_repo/verify/$f" ] || malo "falta verify/$f (node)"
done
[ -f "$node_repo/verify/drive.test.js" ] || malo "falta verify/drive.test.js (node)"

caso "repo node: Drive incluye verify/ y matchea TEST_RUNNER_RE (grep -o del hook)"
node_cmd="$(sed -n 's/^COMANDO_DRIVE:[[:space:]]*//p' "$node_repo/verify/Drive.md" | head -n 1)"
[ "$node_cmd" = "npm test -- verify/" ] || malo "comando de Drive distinto en node: [$node_cmd]"
printf '%s' "$node_cmd" | grep -Eo "$test_runner_re" >/dev/null || malo "comando de Drive NO acredita TEST_RUNNER_RE: [$node_cmd]"
printf '%s' "$node_cmd" | grep -Eo 'verify/' >/dev/null || malo "comando de Drive NO incluye verify/: [$node_cmd]"
[ "$(grep -q 'ESTADO_DRIVE: drive' "$node_repo/verify/Drive.md"; echo $?)" = 0 ] || malo "Drive no queda 'drive' en node"

caso "repo node: LEEME.md trae el sello con el sha REAL del fixture"
node_sello="$(sed -n 's/^generado:[[:space:]]*//p' "$node_repo/verify/LEEME.md" | head -n 1)"
node_sello_sha="$(printf '%s' "${node_sello##*·}" | sed 's/[[:space:]]//g')"
[ "$node_sello_sha" = "$node_sha" ] || malo "el sello NO lleva el sha real (esperado $node_sha, got $node_sello_sha)"
necesita "$(cat "$node_repo/verify/LEEME.md")" "verify_app: drive" "LEEME.md node sin verify_app: drive"

caso "repo node: estado == al_dia"
[ "$(SAIKIT_HOOK_VIVO="$hook_vivo" bash "$script" estado "$node_repo")" = "al_dia" ] \
  || malo "estado del mapa node no es al_dia"

caso "repo node: regenerar un verify/ existente no lo pisa (corre UNA vez)"
node_leeme_cksum="$(cksum "$node_repo/verify/LEEME.md")"
SAIKIT_HOOK_VIVO="$hook_vivo" bash "$script" generar "$node_repo" >/dev/null 2>&1; rc=$?
[ "$rc" -ne 0 ] || malo "regenerar un verify/ existente deberia negarse (se corre una vez)"
[ "$(cksum "$node_repo/verify/LEEME.md")" = "$node_leeme_cksum" ] || malo "regenerar piso el LEEME.md (una sola vez)"

# ---------------------------------------------------- repo python (pytest)
caso "repo python: genera verify/ con los archivos esperados"
py_repo="$SANDBOX/app-py"; mkdir -p "$py_repo"
printf 'print("Entraste. Bienvenido.")\n' > "$py_repo/app.py"
cat > "$py_repo/pyproject.toml" <<'EOF'
[project]
name = "app-py"
[tool.pytest.ini_options]
testpaths = ["verify"]
EOF
py_sha="$(hacer_repo "$py_repo")" || malo "no pudo crear el repo py"
gen_out="$(generar "$py_repo")" || malo "generar fallo en py: $gen_out"
for f in LEEME.md Launch.md Doctor.md Drive.md Evidence.txt Cleanup.md; do
  [ -f "$py_repo/verify/$f" ] || malo "falta verify/$f (py)"
done
[ -f "$py_repo/verify/test_drive.py" ] || malo "falta verify/test_drive.py (py)"

caso "repo python: Drive incluye verify/ y matchea TEST_RUNNER_RE (grep -o del hook)"
py_cmd="$(sed -n 's/^COMANDO_DRIVE:[[:space:]]*//p' "$py_repo/verify/Drive.md" | head -n 1)"
[ "$py_cmd" = "pytest verify/" ] || malo "comando de Drive distinto en py: [$py_cmd]"
printf '%s' "$py_cmd" | grep -Eo "$test_runner_re" >/dev/null || malo "comando de Drive NO acredita TEST_RUNNER_RE: [$py_cmd]"
printf '%s' "$py_cmd" | grep -Eo 'verify/' >/dev/null || malo "comando de Drive NO incluye verify/: [$py_cmd]"

caso "repo python: LEEME.md trae el sello con el sha REAL del fixture"
py_sello="$(sed -n 's/^generado:[[:space:]]*//p' "$py_repo/verify/LEEME.md" | head -n 1)"
py_sello_sha="$(printf '%s' "${py_sello##*·}" | sed 's/[[:space:]]//g')"
[ "$py_sello_sha" = "$py_sha" ] || malo "el sello NO lleva el sha real (esperado $py_sha, got $py_sello_sha)"

caso "repo python: estado == al_dia"
[ "$(SAIKIT_HOOK_VIVO="$hook_vivo" bash "$script" estado "$py_repo")" = "al_dia" ] \
  || malo "estado del mapa py no es al_dia"

# ------------------------------------------------ repo sin framework (propone)
caso "repo sin framework: propone y espera el sí, NO instala"
none_repo="$SANDBOX/app-none"; mkdir -p "$none_repo"
printf '# App sin framework\n' > "$none_repo/README.md"
printf 'print("hola")\n' > "$none_repo/main.py"
hacer_repo "$none_repo" >/dev/null || malo "no pudo crear el repo sin framework"
gen_out="$(generar "$none_repo")" || malo "generar fallo en sin-framework: $gen_out"
necesita "$gen_out" "PROPONGO:" "no propone un framework"
# no instala: no crea node_modules, ni lockfile, ni venv
if find "$none_repo" -maxdepth 2 \( -name node_modules -o -name package-lock.json \
     -o -name '*.venv*' -o -name .venv \) | grep -q .; then
  malo "instaló algo en el repo sin framework"
fi
for f in LEEME.md Launch.md Doctor.md Drive.md Evidence.txt Cleanup.md; do
  [ -f "$none_repo/verify/$f" ] || malo "falta verify/$f (sin framework)"
done
necesita "$(cat "$none_repo/verify/Drive.md")" "manual, pendiente" "Drive sin framework no queda manual, pendiente"
necesita "$(cat "$none_repo/verify/LEEME.md")" "verify_app: n/a" "sin framework no declara verify_app: n/a"
[ -f "$none_repo/verify/drive.test.js" ] && malo "sin framework no debe haber drive node"
[ -f "$none_repo/verify/test_drive.py" ] && malo "sin framework no debe haber drive python"

# -------------------------------------------- sello ausente => unknown (jamas al_dia)
caso "sello ausente => verifier declara unknown, nunca 'al dia'"
# estado lee SIEMPRE verify/LEEME.md; para probar el caso, quitamos el sello del
# que estado va a leer y comprobamos que diga unknown (y jamas al_dia).
sed -i '/^generado:/d' "$node_repo/verify/LEEME.md"
estado="$(SAIKIT_HOOK_VIVO="$hook_vivo" bash "$script" estado "$node_repo")"
[ "$estado" = "unknown" ] || malo "sin sello el estado debe ser 'unknown', da $estado"
[ "$estado" != "al_dia" ] || malo "sin sello NUNCA puede decir 'al dia'"

[ "$fail" -eq 0 ] && echo "test_verificar_app: OK" || { echo "test_verificar_app: FAIL" >&2; exit 1; }
