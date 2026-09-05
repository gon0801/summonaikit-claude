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

# 18.19 — sed in place PORTABLE (mismo patron de test_recetas.sh): `sed -i`
# sin sufijo es GNU-only; temporal + mv es identico en GNU, BSD y MSYS2.
sed_i() {  # $1 = script sed, $2 = archivo a editar en el lugar
  sed "$1" "$2" > "$2.saikit-new" || { rm -f "$2.saikit-new"; return 1; }
  mv "$2.saikit-new" "$2"
}

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
[ -f "$node_repo/verify/drive.test.cjs" ] || malo "falta verify/drive.test.cjs (node)"

caso "repo node: Drive incluye verify/ y matchea TEST_RUNNER_RE (grep -o del hook)"
node_cmd="$(sed -n 's/^COMANDO_DRIVE:[[:space:]]*//p' "$node_repo/verify/Drive.md" | head -n 1)"
[ "$node_cmd" = "npm test -- verify/drive.test.cjs" ] || malo "comando de Drive distinto en node: [$node_cmd]"
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
[ -f "$none_repo/verify/drive.test.cjs" ] && malo "sin framework no debe haber drive node (.cjs)"
[ -f "$none_repo/verify/drive.test.js" ] && malo "sin framework no debe haber drive node"
[ -f "$none_repo/verify/test_drive.py" ] && malo "sin framework no debe haber drive python"

# -------------------------------------------- sello ausente => unknown (jamas al_dia)
caso "sello ausente => verifier declara unknown, nunca 'al dia'"
# estado lee SIEMPRE verify/LEEME.md; para probar el caso, quitamos el sello del
# que estado va a leer y comprobamos que diga unknown (y jamas al_dia).
sed_i '/^generado:/d' "$node_repo/verify/LEEME.md"
estado="$(SAIKIT_HOOK_VIVO="$hook_vivo" bash "$script" estado "$node_repo")"
[ "$estado" = "unknown" ] || malo "sin sello el estado debe ser 'unknown', da $estado"
[ "$estado" != "al_dia" ] || malo "sin sello NUNCA puede decir 'al dia'"

# ---------------------- test falso (echo ok) NO es un Drive acreditable (CodeRabbit #1)
caso "repo con test falso (echo ok): NO publica COMANDO_DRIVE ni ESTADO_DRIVE: drive"
fake_repo="$SANDBOX/app-fake"; mkdir -p "$fake_repo"
printf 'console.log("Entraste. Bienvenido.");\n' > "$fake_repo/app.js"
cat > "$fake_repo/package.json" <<'EOF'
{ "name": "app-fake", "scripts": { "test": "echo ok" } }
EOF
hacer_repo "$fake_repo" >/dev/null || malo "no pudo crear el repo con test falso"
gen_out="$(generar "$fake_repo")" || malo "generar fallo en test-falso: $gen_out"
# un "echo ok" no invoca ningun runner admitido => el Drive NO se acredita.
necesita "$(cat "$fake_repo/verify/Drive.md")" "manual, pendiente" "Drive con test falso no queda manual/pendiente"
if grep -q 'COMANDO_DRIVE:' "$fake_repo/verify/Drive.md"; then
  malo "test falso NO debe publicar COMANDO_DRIVE"
fi
necesita "$(cat "$fake_repo/verify/LEEME.md")" "verify_app: n/a" "test falso no declara verify_app: n/a"
[ -f "$fake_repo/verify/drive.test.cjs" ] && malo "test falso no debe generar drive.test.cjs"
[ -f "$fake_repo/verify/drive.test.js" ] && malo "test falso no debe generar drive.test.js"

# ---------------------- ESM (type: module): el Drive corre de verdad (CodeRabbit #2)
caso "repo ESM (type: module): el Drive corre de verdad (drive.test.cjs)"
esm_repo="$SANDBOX/app-esm"; mkdir -p "$esm_repo"
printf 'console.log("Entraste. Bienvenido.");\n' > "$esm_repo/app.js"
cat > "$esm_repo/package.json" <<'EOF'
{ "name": "app-esm", "type": "module", "scripts": { "test": "node --test" } }
EOF
hacer_repo "$esm_repo" >/dev/null || malo "no pudo crear el repo ESM"
gen_out="$(generar "$esm_repo")" || malo "generar fallo en ESM: $gen_out"
[ -f "$esm_repo/verify/drive.test.cjs" ] || malo "repo ESM: falta verify/drive.test.cjs"
esm_cmd="$(sed -n 's/^COMANDO_DRIVE:[[:space:]]*//p' "$esm_repo/verify/Drive.md" | head -n 1)"
[ "$esm_cmd" = "npm test -- verify/drive.test.cjs" ] || malo "comando de Drive ESM distinto: [$esm_cmd]"
# el COMANDO_DRIVE corre DE VERDAD en un package ESM (drive.test.cjs se carga como CJS)
if ! bash -c "export APP_ENTRADA=app.js; cd '$esm_repo' && $esm_cmd" >/dev/null 2>&1; then
  malo "el COMANDO_DRIVE NO corrió de verdad en el repo ESM"
fi

# ---------------------- sello con fecha rota => unknown, nunca al dia (CodeRabbit #3)
caso "sello con fecha rota: el verifier declara unknown, jamas 'al dia'"
bad_repo="$SANDBOX/app-badfecha"; mkdir -p "$bad_repo"
printf '# App\n' > "$bad_repo/README.md"
bad_sha="$(hacer_repo "$bad_repo")" || malo "no pudo crear el repo de fecha rota"
mkdir -p "$bad_repo/verify"
printf 'generado: fecha-invalida · %s\n' "$bad_sha" > "$bad_repo/verify/LEEME.md"
es_bad="$(SAIKIT_HOOK_VIVO="$hook_vivo" bash "$script" estado "$bad_repo")"
[ "$es_bad" = "unknown" ] || malo "fecha rota debe ser 'unknown', da $es_bad"
[ "$es_bad" != "al_dia" ] || malo "fecha rota NUNCA puede decir 'al dia' (el sello no se pudo datar)"

# ---------------------- date BSD (sin -d): el sello se interpreta igual ----------
# Rojo medido 2026-09-05 en macOS: `date -d` es GNU-only y sin el fallback
# `-j -f` TODO sello databa `unknown` aun estando al dia. El shim simula BSD:
# rechaza -d; en -j/-r delega al date real BSD si lo entiende (macOS) o lo
# emula con -d si el real es GNU (CI Linux: ojo, en GNU `-r` es mtime de
# archivo, NO epoch — sin la emulacion el round-trip de fecha_epoch falla).
caso "date sin -d (BSD): el sello databa y estado == al_dia"
bsd_bin="$SANDBOX/bin-bsd"; mkdir -p "$bsd_bin"
date_real="$(command -v date)"
cat > "$bsd_bin/date" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do
  if [ "\$a" = "-d" ]; then echo "date: illegal option -- d" >&2; exit 1; fi
done
if [ "\$1" = "-j" ]; then
  "$date_real" -j -f "\$3" "\$4" "\$5" 2>/dev/null && exit 0
  [ "\$3" = "%Y-%m-%d" ] && [ "\$5" = "+%s" ] || exit 1
  exec "$date_real" -d "\$4" "+%s"
fi
if [ "\$1" = "-r" ]; then
  "$date_real" -r "\$2" "\$3" 2>/dev/null && exit 0
  exec "$date_real" -d "@\$2" "\$3"
fi
exec "$date_real" "\$@"
EOF
chmod +x "$bsd_bin/date"
es_bsd="$(PATH="$bsd_bin:$PATH" SAIKIT_HOOK_VIVO="$hook_vivo" bash "$script" estado "$py_repo")"
[ "$es_bsd" = "al_dia" ] || malo "con date BSD (sin -d) el estado debe ser al_dia, da $es_bsd"

# ---------------------- dia de calendario invalido => unknown en GNU y BSD -------
# Adversary 2026-09-05 (medido): BSD DESBORDA `2026-09-31` al 1 de octubre y
# `estado` daba al_dia; GNU lo rechaza. El round-trip de fecha_epoch nivela:
# una fecha que no existe es un sello que no se pudo datar => unknown.
caso "sello con dia inexistente (2026-09-31) => unknown con date real y con shim BSD"
cal_repo="$SANDBOX/app-maldia"; mkdir -p "$cal_repo"
printf '# App\n' > "$cal_repo/README.md"
cal_sha="$(hacer_repo "$cal_repo")" || malo "no pudo crear el repo de dia invalido"
mkdir -p "$cal_repo/verify"
printf 'generado: 2026-09-31 · %s\n' "$cal_sha" > "$cal_repo/verify/LEEME.md"
es_cal="$(SAIKIT_HOOK_VIVO="$hook_vivo" bash "$script" estado "$cal_repo")"
[ "$es_cal" = "unknown" ] || malo "dia inexistente debe ser 'unknown' con date real, da $es_cal"
es_cal_bsd="$(PATH="$bsd_bin:$PATH" SAIKIT_HOOK_VIVO="$hook_vivo" bash "$script" estado "$cal_repo")"
[ "$es_cal_bsd" = "unknown" ] || malo "dia inexistente debe ser 'unknown' con shim BSD, da $es_cal_bsd"

[ "$fail" -eq 0 ] && echo "test_verificar_app: OK" || { echo "test_verificar_app: FAIL" >&2; exit 1; }
