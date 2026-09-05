#!/usr/bin/env bash
# 18.20 — el instalador DECLARA la procedencia git de lo que instala y --check
# la vuelve verificable por maquina sobre TODAS las copias cableadas.
#
# Por que declarar y no negar: la guarda propuesta (negar salvo HEAD ==
# origin/master) habria bloqueado el arreglo correctivo del 2026-09-04, que se
# corrio desde una rama y saco a grok/dsh de cinco filas de atraso. El defecto
# no es que se PUEDA desplegar desde una rama: es que nadie se ENTERA.
#
# Tres decisiones cerradas por esta entrega (ver el bloque de procedencia en
# tools/install-hook.sh):
#   - "perfil real" no se distingue por ruta (el sandbox es indistinguible):
#     se declara SIEMPRE, en toda corrida que pasa validacion. Reportar no
#     bloquea, asi que desinstalar/reparar siguen andando rotos o no.
#   - sin git o fuera de un repo: "procedencia: desconocida", nunca silencio;
#     en --check eso es FALLO (fail-closed), no unknown.
#   - "coincide con origin/master" se juzga contra el ref LOCAL, sin fetch.
#
# Core Rule 4: todo contra tmpdirs. Ningun caso mira ni escribe el perfil real.
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
# Misma costura que test_install_hook.sh: permite correr esta bateria contra
# una copia MUTADA del instalador y exigir que se de cuenta.
tool="${SAIKIT_INSTALL_TOOL:-$repo/tools/install-hook.sh}"
fuente="$repo/hooks/summonaikit-harness.sh"

fail=0
caso() { printf '  caso: %s\n' "$1"; }
malo() { printf '    FAIL: %s\n' "$1" >&2; fail=1; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/saikit-18-20-XXXXXX")" || exit 1
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/casa"
export USERPROFILE="$tmp/casa"
mkdir -p "$HOME/.claude/skills"

if [ ! -f "$tool" ]; then
  echo "    FAIL: no existe el instalador en $tool" >&2
  echo "test_install_provenance: FAIL" >&2
  exit 1
fi
if ! command -v git >/dev/null 2>&1; then
  echo "test_install_provenance: unknown — no hay git en este host; la procedencia no se puede medir." >&2
  exit 3
fi

# Un hook fixture minimo con marcador valido en la linea 2 (lo exige la
# validacion de fuente del instalador). $1 = path destino.
fixture_hook() {
  mkdir -p "$(dirname "$1")"
  printf '#!/usr/bin/env bash\n# SAIKIT-CLAUDE-OWNED summonaikit-claude fixture\nsalida_fixture=1\n' > "$1"
}

# Arma un repo git sandbox con el hook fixture commiteado en
# hooks/summonaikit-harness.sh, origin/master apuntando a HEAD, y una COPIA del
# instalador en tools/. Imprime la raiz. Es la unica forma hermetica de juzgar
# valores de procedencia (el checkout real va en rama y sucio durante el dev).
# $1 = nombre del sandbox.
repo_sandbox() {
  local r="$tmp/$1"
  mkdir -p "$r/tools" "$r/hooks"
  fixture_hook "$r/hooks/summonaikit-harness.sh"
  cp "$tool" "$r/tools/install-hook.sh"
  ( cd "$r" && git init -q \
    && git -c user.email=t@t -c user.name=t add hooks/summonaikit-harness.sh \
    && git -c user.email=t@t -c user.name=t commit -qm fixture \
    && git update-ref refs/remotes/origin/master HEAD ) >/dev/null 2>&1
  printf '%s' "$r"
}

# Stub minimo parseable. --check exige el archivo (ausente = falta-registro);
# no afirma que nombre al hook. No crear dirs de hosts ajenos: eso los mete
# al conjunto.
plantar_registro() {
  case "$1" in
    claude)
      mkdir -p "$HOME/.claude"
      printf '%s\n' '{}' > "$HOME/.claude/settings.json" ;;
    grok)
      mkdir -p "$HOME/.grok/hooks"
      printf '%s\n' '{}' > "$HOME/.grok/hooks/summonaikit.json" ;;
    dsh)
      mkdir -p "$HOME/.dsh"
      printf '%s\n' 'summonaikit:' > "$HOME/.dsh/cordis.patch.yml" ;;
    codex)
      mkdir -p "$HOME/.codex"
      printf '%s\n' '{}' > "$HOME/.codex/hooks.json" ;;
    *)
      malo "plantar_registro: host desconocido $1"
      return 1 ;;
  esac
}

# P1: instalar por defecto declara procedencia con los cuatro campos. Acepta la
# forma shallow (rama+sha conocidos, coincide unknown): en CI no hay ref remoto.
caso "P1: install por defecto imprime procedencia (rama, sha, sucio, coincide)"
out="$(bash "$tool" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "install por defecto salio $rc: $out"
case "$out" in
  *'procedencia: rama='*' sha='*' sucio='*'coincide_origin_master='*) ;;
  *) malo "falta la linea de procedencia: [$out]" ;;
esac

# P2: --dry-run tambien declara (es lo que SE instalaria).
caso "P2: --dry-run imprime procedencia sin escribir"
rm -rf "$HOME/.claude/hooks"
out="$(bash "$tool" --dry-run 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "--dry-run salio $rc: $out"
case "$out" in
  *'procedencia: rama='*) ;;
  *) malo "dry-run no declaro procedencia: [$out]" ;;
esac
[ -e "$HOME/.claude/hooks/summonaikit-harness.sh" ] \
  && malo "dry-run escribio el destino"

# P3: un flujo de quite (mutacion del perfil) tambien declara.
caso "P3: --host dsh --quitar-dsh imprime procedencia"
out="$(bash "$tool" --host dsh --quitar-dsh 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "quitar-dsh salio $rc: $out"
case "$out" in
  *'procedencia: rama='*|*'procedencia: desconocida'*) ;;
  *) malo "quitar-dsh no declaro procedencia: [$out]" ;;
esac

# P4: la segunda corrida (YA AL DIA) declara igual que la primera.
caso "P4: YA AL DIA declara procedencia"
bash "$tool" >/dev/null 2>&1
out="$(bash "$tool" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "segunda corrida salio $rc"
case "$out" in
  *'YA AL DIA'*) ;;
  *) malo "la segunda corrida no dijo YA AL DIA: [$out]" ;;
esac
case "$out" in
  *'procedencia: rama='*|*'procedencia: desconocida'*) ;;
  *) malo "YA AL DIA no declaro procedencia: [$out]" ;;
esac

# P5: checkout que no es git — se reporta desconocida, no se calla. En --dry-run
# a proposito: el flujo real instalaria ademas el recetario desde $repo/recetas,
# que no existe en la copia no-git, y saldria 5 por eso (ajeno a procedencia).
caso "P5: fuera de un repo git => procedencia desconocida (no silencio)"
nogit="$tmp/nogit"
mkdir -p "$nogit/tools"
cp "$tool" "$nogit/tools/install-hook.sh"
fixture_hook "$tmp/fuente-nogit.sh"
out="$(bash "$nogit/tools/install-hook.sh" --dry-run --source "$tmp/fuente-nogit.sh" --dest "$tmp/dest-nogit.sh" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "dry-run nogit salio $rc: $out"
case "$out" in
  *'procedencia: desconocida'*) ;;
  *) malo "checkout no-git no reporto desconocida: [$out]" ;;
esac

# P6: sin git disponible => desconocida, y el exit NO se mueve (reportar no
# bloquea: desinstalar/reparar andan igual con git roto).
caso "P6: SAIKIT_GIT_BIN inexistente => desconocida y exit intacto"
out="$(SAIKIT_GIT_BIN="$tmp/no-hay-git" bash "$tool" --source "$fuente" --dest "$tmp/dest-singit.sh" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "install sin git salio $rc: $out"
case "$out" in
  *'procedencia: desconocida'*) ;;
  *) malo "sin git no reporto desconocida: [$out]" ;;
esac

# P8: con sha256 roto, lo no-calculable se reporta como no-calculable, NUNCA
# como DESCONOCIDO (Core Rule 2): esa palabra es el tercer estado del
# instalador. Lo atrapo la regresion del caso 12.9 #2 al agregar la linea.
caso "P8: sha roto => procedencia sin la palabra DESCONOCIDO"
fake_sha="$tmp/fake-sha-p8"
mkdir -p "$fake_sha"
printf '#!/usr/bin/env bash\nexit 1\n' > "$fake_sha/sha256sum"
chmod +x "$fake_sha/sha256sum"
out="$(PATH="$fake_sha:$PATH" bash "$tool" --dry-run --source "$fuente" --dest "$tmp/dest-p8.sh" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "dry-run con sha roto salio $rc: $out"
case "$out" in
  *'procedencia: rama='*) ;;
  *) malo "con sha roto no declaro procedencia: [$out]" ;;
esac
case "$out" in
  *'fuente_sha256=no-calculable'*) ;;
  *) malo "el sha no-calculable no se nombro como tal: [$out]" ;;
esac
printf '%s' "$out" | grep -qi 'desconocid' && malo "con sha roto se colgo DESCONOCIDO: [$out]"

# P9: repo SIN ref origin/master (checkout shallow de CI, clone --depth 1):
# rama y sha se conocen igual; el coincide lleva la razon (sin-ref), no el
# estado. Antes caia en un "sin-commits" falso (el rev-parse en par vaciaba
# HEAD tambien). La segunda corrida suma sha roto: la forma exacta de 12.9 #2
# en CI. Ninguna de las dos puede contener ni unknown (restore_vendor:
# Core Rule 2 al reves) ni desconocid (12.9 #2).
caso "P9: sin ref remoto => rama+sha conocidos, coincide sin-ref, exit 0"
r9noref="$(repo_sandbox repo-p9)"
git -C "$r9noref" update-ref -d refs/remotes/origin/master
export HOME="$tmp/casa-p9"
mkdir -p "$HOME"
out="$(bash "$r9noref/tools/install-hook.sh" --dry-run 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "dry-run sin ref salio $rc: $out"
case "$out" in
  *'procedencia: rama='*' sha='*'coincide_origin_master=sin-ref'*) ;;
  *) malo "sin ref no dio rama+sha conocidos con coincide sin-ref: [$out]" ;;
esac
sha40="$(printf '%s' "$out" | grep -oE 'sha=[0-9a-f]*' | head -n1 | cut -c5-)"
[ "${#sha40}" -eq 40 ] || malo "sin ref: sha no es 40 hex: [$sha40]"
printf '%s' "$out" | grep -qi 'desconocid' && malo "sin ref emitio la palabra: [$out]"
printf '%s' "$out" | grep -qi 'unknown' && malo "sin ref emitio unknown: [$out]"
out="$(PATH="$fake_sha:$PATH" bash "$r9noref/tools/install-hook.sh" --dry-run 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "dry-run sin ref y sha roto salio $rc: $out"
case "$out" in
  *'coincide_origin_master=sin-ref'*'fuente_sha256=no-calculable'*) ;;
  *) malo "sin ref + sha roto no dio sin-ref/no-calculable: [$out]" ;;
esac
printf '%s' "$out" | grep -qi 'desconocid' && malo "sin ref + sha roto colgo DESCONOCIDO: [$out]"
printf '%s' "$out" | grep -qi 'unknown' && malo "sin ref + sha roto colgo UNKNOWN: [$out]"

# P7: error de validacion (fuente mala) => exit 2 y SIN procedencia: no hay
# nada instalado que declarar, y el error queda limpio.
caso "P7: fuente invalida => exit 2 sin linea de procedencia"
out="$(bash "$tool" --source "$tmp/no-existe.sh" --dest "$tmp/dest-malo.sh" 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || malo "fuente mala salio $rc, se esperaba 2: $out"
case "$out" in
  *'procedencia: '*) malo "el error de validacion declaro procedencia: [$out]" ;;
esac

# Clase Task 0.4 (`shift 2` con un solo argumento gira para siempre): cada
# flag con valor exige su $2 o sale 2. Acotado con timeout like
# flag_sin_valor_sale_2_no_gira: 124 es bucle, 2 es fix. Discrimina porque el
# cuelgue es el comportamiento real pre-fix (medido: 124 en los cuatro).
caso "P10: flag sin valor sale 2, no gira"
for _f in --dest --source --manifest --host; do
  out="$(timeout 5 bash "$tool" "$_f" 2>&1)"; rc=$?
  [ "$rc" -eq 2 ] || malo "$_f sin valor dio $rc, se esperaba 2 (124=cuelgue)"
  case "$out" in
    *'exige un valor'*) ;;
    *) malo "$_f sin valor no nombro la falta: [$out]" ;;
  esac
done

# C1: sandbox vacio — claude FALTA (es el ancla: siempre exigida), los demas
# hosts no aplican (ni dir ni copia), veredicto fallo. Nada de silencio.
caso "C1: --check en vacio => fallo, claude falta, resto no-aplica"
export HOME="$tmp/casa-c1"
mkdir -p "$HOME"
out="$(bash "$tool" --check 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || malo "--check en vacio salio $rc, se esperaba 1: $out"
case "$out" in
  *'host=claude'*'resultado=falta'*) ;;
  *) malo "falta la fila claude=falta: [$out]" ;;
esac
case "$out" in
  *'host=grok'*'resultado=no-aplica'*'host=dsh'*'resultado=no-aplica'*'host=codex'*'resultado=no-aplica'*) ;;
  *) malo "faltan filas no-aplica por host: [$out]" ;;
esac
case "$out" in
  *'veredicto=fallo'*) ;;
  *) malo "falta veredicto=fallo: [$out]" ;;
esac

# C2: las tres copias iguales a la fuente y la fuente igual al blob de
# origin/master => 0, una fila al-dia por host.
caso "C2: todo al dia => 0 con fila por host"
r2="$(repo_sandbox repo-c2)"
export HOME="$tmp/casa-c2"
mkdir -p "$HOME/.claude/hooks" "$HOME/.grok/hooks" "$HOME/.dsh/hooks"
cp "$r2/hooks/summonaikit-harness.sh" "$HOME/.claude/hooks/summonaikit-harness.sh"
cp "$r2/hooks/summonaikit-harness.sh" "$HOME/.grok/hooks/summonaikit-harness.sh"
cp "$r2/hooks/summonaikit-harness.sh" "$HOME/.dsh/hooks/summonaikit-harness.sh"
plantar_registro claude
plantar_registro grok
plantar_registro dsh
out="$(bash "$r2/tools/install-hook.sh" --check 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "--check al dia salio $rc: $out"
for h in claude grok dsh; do
  case "$out" in
    *'host='"$h"*'resultado=al-dia'*) ;;
    *) malo "falta la fila $h=al-dia: [$out]" ;;
  esac
done
case "$out" in *'veredicto=ok'*) ;; *) malo "falta veredicto=ok: [$out]" ;; esac

# C3: la forma del incidente del 2026-09-04 — grok existe pero atrasado.
caso "C3: copia atrasada => fallo con fila difiere (incidente 09-04)"
r3="$(repo_sandbox repo-c3)"
export HOME="$tmp/casa-c3"
mkdir -p "$HOME/.claude/hooks" "$HOME/.grok/hooks" "$HOME/.dsh/hooks"
cp "$r3/hooks/summonaikit-harness.sh" "$HOME/.claude/hooks/summonaikit-harness.sh"
cp "$r3/hooks/summonaikit-harness.sh" "$HOME/.grok/hooks/summonaikit-harness.sh"
cp "$r3/hooks/summonaikit-harness.sh" "$HOME/.dsh/hooks/summonaikit-harness.sh"
printf '# cambio ajeno\n' >> "$HOME/.grok/hooks/summonaikit-harness.sh"
out="$(bash "$r3/tools/install-hook.sh" --check 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || malo "--check con grok atrasado salio $rc, se esperaba 1: $out"
case "$out" in
  *'host=grok'*'resultado=difiere'*) ;;
  *) malo "falta la fila grok=difiere: [$out]" ;;
esac
case "$out" in *'veredicto=fallo'*) ;; *) malo "falta veredicto=fallo: [$out]" ;; esac

# C4: host configurado (dir presente) pero copia ausente => falta, FALLO.
caso "C4: host configurado sin copia => falta y fallo"
r4="$(repo_sandbox repo-c4)"
export HOME="$tmp/casa-c4"
mkdir -p "$HOME/.claude/hooks" "$HOME/.grok" "$HOME/.dsh/hooks"
cp "$r4/hooks/summonaikit-harness.sh" "$HOME/.claude/hooks/summonaikit-harness.sh"
cp "$r4/hooks/summonaikit-harness.sh" "$HOME/.dsh/hooks/summonaikit-harness.sh"
out="$(bash "$r4/tools/install-hook.sh" --check 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || malo "--check con grok sin copia salio $rc, se esperaba 1: $out"
case "$out" in
  *'host=grok'*'resultado=falta'*) ;;
  *) malo "grok configurado-sin-copia no dio falta: [$out]" ;;
esac

# C5: checkout no-git — las filas igual se emiten (los bytes se comparan),
# pero la procedencia desconocida cierra en FALLO, no en 0.
caso "C5: checkout no-git => filas + procedencia desconocida + fallo"
nogit5="$tmp/nogit5"
mkdir -p "$nogit5/tools"
cp "$tool" "$nogit5/tools/install-hook.sh"
fixture_hook "$tmp/fuente-c5.sh"
export HOME="$tmp/casa-c5"
mkdir -p "$HOME/.claude/hooks"
cp "$tmp/fuente-c5.sh" "$HOME/.claude/hooks/summonaikit-harness.sh"
out="$(bash "$nogit5/tools/install-hook.sh" --check --source "$tmp/fuente-c5.sh" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || malo "--check nogit salio $rc, se esperaba 1: $out"
case "$out" in
  *'procedencia: desconocida'*) ;;
  *) malo "nogit no reporto desconocida: [$out]" ;;
esac
case "$out" in
  *'host=claude'*'resultado=al-dia'*) ;;
  *) malo "nogit no emitio la fila de bytes: [$out]" ;;
esac
case "$out" in *'veredicto=fallo'*) ;; *) malo "nogit no cerro en fallo: [$out]" ;; esac

# C6: copias iguales a la fuente pero fuente distinta del blob de master —
# SOLO la guarda de bytes-master dispara (las de copia pasan). Es el caso
# que discrimina esa guarda: romperla deja este caso en verde.
caso "C6: fuente != blob de origin/master => fallo aunque copias al dia"
r6="$(repo_sandbox repo-c6)"
printf '# trabajo en rama\n' >> "$r6/hooks/summonaikit-harness.sh"
export HOME="$tmp/casa-c6"
mkdir -p "$HOME/.claude/hooks"
cp "$r6/hooks/summonaikit-harness.sh" "$HOME/.claude/hooks/summonaikit-harness.sh"
out="$(bash "$r6/tools/install-hook.sh" --check 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || malo "--check con fuente de rama salio $rc, se esperaba 1: $out"
case "$out" in
  *'host=claude'*'resultado=al-dia'*) ;;
  *) malo "la fila de copia debio seguir al-dia: [$out]" ;;
esac
case "$out" in
  *'fuente-difiere-de-origin/master'*) ;;
  *) malo "el veredicto no nombro la causa master: [$out]" ;;
esac

# C7: codex presente y al dia => fila al-dia (no se saltea por existir).
caso "C7: codex presente => fila al-dia"
r7="$(repo_sandbox repo-c7)"
export HOME="$tmp/casa-c7"
mkdir -p "$HOME/.claude/hooks" "$HOME/.codex/hooks"
cp "$r7/hooks/summonaikit-harness.sh" "$HOME/.claude/hooks/summonaikit-harness.sh"
cp "$r7/hooks/summonaikit-harness.sh" "$HOME/.codex/hooks/summonaikit-harness.sh"
plantar_registro claude
plantar_registro codex
out="$(bash "$r7/tools/install-hook.sh" --check 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "--check con codex al dia salio $rc: $out"
case "$out" in
  *'host=codex'*'resultado=al-dia'*) ;;
  *) malo "falta la fila codex=al-dia: [$out]" ;;
esac

# C8: --check de un solo host emite SOLO esa fila y juzga solo esa copia.
caso "C8: --check --host grok => una sola fila"
r8="$(repo_sandbox repo-c8)"
export HOME="$tmp/casa-c8"
mkdir -p "$HOME/.grok/hooks"
cp "$r8/hooks/summonaikit-harness.sh" "$HOME/.grok/hooks/summonaikit-harness.sh"
plantar_registro grok
out="$(bash "$r8/tools/install-hook.sh" --check --host grok 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "--check --host grok salio $rc: $out"
case "$out" in
  *'host=grok'*'resultado=al-dia'*) ;;
  *) malo "falta la fila grok: [$out]" ;;
esac
case "$out" in
  *'host=claude'*) malo "el check de un host emitio fila claude: [$out]" ;;
esac

# C9: el conjunto autoritativo no se achica: --dest, kimi y zcode se rechazan.
caso "C9: --check rechaza --dest, --host kimi y --host zcode"
r9="$(repo_sandbox repo-c9)"
export HOME="$tmp/casa-c9"
mkdir -p "$HOME"
out="$(bash "$r9/tools/install-hook.sh" --check --dest "$tmp/x.sh" 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || malo "--check --dest salio $rc, se esperaba 2: $out"
out="$(bash "$r9/tools/install-hook.sh" --check --host kimi 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || malo "--check --host kimi salio $rc, se esperaba 2: $out"
out="$(bash "$r9/tools/install-hook.sh" --check --host zcode 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || malo "--check --host zcode salio $rc, se esperaba 2: $out"

# C10: --check no escribe nada: ni copias, ni dirs, ni backups.
caso "C10: --check no crea ni un archivo bajo HOME"
r10="$(repo_sandbox repo-c10)"
export HOME="$tmp/casa-c10"
mkdir -p "$HOME"
out="$(bash "$r10/tools/install-hook.sh" --check 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || malo "--check en vacio (c10) salio $rc: $out"
restos="$(find "$HOME" -mindepth 1 2>/dev/null | head -5)"
[ -z "$restos" ] || malo "--check escribio bajo HOME: [$restos]"

# C11: --check sin ref remoto — las filas siguen al-dia (las copias SE miran),
# pero el juicio contra master no se puede hacer y eso es FALLO con causa
# nombrada. La causa lleva vocabulario no-observable (el del manifiesto):
# ni unknown (restore_vendor) ni desconocid (12.9 #2) en la salida.
caso "C11: --check sin ref => fallo nombrado, sin unknown ni desconocid"
r11="$(repo_sandbox repo-c11)"
git -C "$r11" update-ref -d refs/remotes/origin/master
export HOME="$tmp/casa-c11"
mkdir -p "$HOME/.claude/hooks"
cp "$r11/hooks/summonaikit-harness.sh" "$HOME/.claude/hooks/summonaikit-harness.sh"
out="$(bash "$r11/tools/install-hook.sh" --check 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || malo "--check sin ref salio $rc, se esperaba 1: $out"
case "$out" in
  *'host=claude'*'resultado=al-dia'*) ;;
  *) malo "la fila debio seguir al-dia: [$out]" ;;
esac
case "$out" in
  *'juicio-master-no-observable'*) ;;
  *) malo "el veredicto no nombro la causa: [$out]" ;;
esac
printf '%s' "$out" | grep -qi 'unknown' && malo "--check sin ref colgo UNKNOWN: [$out]"
printf '%s' "$out" | grep -qi 'desconocid' && malo "--check sin ref colgo DESCONOCIDO: [$out]"

# C12: el hueco de 18.21(a). Cuatro copias al dia, registros parseables en
# claude/grok/dsh, SIN ~/.codex/hooks.json. Antes: veredicto=ok. Ahora: fallo
# con registro=falta-registro y causa registro-codex-falta-registro.
caso "C12: cuatro copias al dia, registro codex ausente => fallo"
r12="$(repo_sandbox repo-c12)"
export HOME="$tmp/casa-c12"
mkdir -p "$HOME/.claude/hooks" "$HOME/.grok/hooks" "$HOME/.dsh/hooks" "$HOME/.codex/hooks"
for _hd in "$HOME/.claude/hooks" "$HOME/.grok/hooks" "$HOME/.dsh/hooks" "$HOME/.codex/hooks"; do
  cp "$r12/hooks/summonaikit-harness.sh" "$_hd/summonaikit-harness.sh"
done
plantar_registro claude
plantar_registro grok
plantar_registro dsh
[ ! -e "$HOME/.codex/hooks.json" ] || malo "C12 no debio plantar hooks.json de codex"
out="$(bash "$r12/tools/install-hook.sh" --check 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || malo "--check C12 salio $rc, se esperaba 1: $out"
case "$out" in
  *'host=codex'*'resultado=al-dia'*'registro=falta-registro'*) ;;
  *) malo "C12 no mostro registro=falta-registro en codex: [$out]" ;;
esac
case "$out" in
  *'registro-codex-falta-registro'*) ;;
  *) malo "C12 no nombro la causa registro-codex-falta-registro: [$out]" ;;
esac
case "$out" in *'veredicto=fallo'*) ;; *) malo "C12 no cerro en fallo: [$out]" ;; esac

# C13: [ -L ] antes de cmp. Un symlink a los mismos bytes pasaba al-dia
# porque -f sigue el enlace.
caso "C13: dest symlink => no-observable"
r13="$(repo_sandbox repo-c13)"
export HOME="$tmp/casa-c13"
mkdir -p "$HOME/.claude/hooks"
ln -s "$r13/hooks/summonaikit-harness.sh" "$HOME/.claude/hooks/summonaikit-harness.sh"
plantar_registro claude
out="$(bash "$r13/tools/install-hook.sh" --check 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || malo "--check C13 salio $rc, se esperaba 1: $out"
case "$out" in
  *'host=claude'*'resultado=no-observable'*) ;;
  *) malo "C13 no marco dest symlink como no-observable: [$out]" ;;
esac

# ------------------------------------------------------- bloque de mutaciones
# Cada mutante rompe UNA guarda; su caso rojo tiene que atraparlo (flip de rc
# exacto: otro rc es mutante invalido, no kill). Guarda anti-sed-obsoleto,
# patron de test_autopilot_config.sh: si el sed no cambia bytes o el mutante
# no parsea, FAIL (ya no prueba nada). BASE es la copia pristina DENTRO del
# repo sandbox: ahi resuelven los defaults del tool.
mut_base=""; mutado=""
mut_preparar() { # $1=repo-sandbox $2=sed-expr $3=nombre -> 0 listo / 1 FAIL
  mut_base="$1/tools/install-hook.sh"
  mutado="$1/tools/install-mutado.sh"
  sed "$2" "$mut_base" > "$mutado"
  if cmp -s "$mut_base" "$mutado"; then
    malo "mutacion $3 no cambio nada — el sed quedo obsoleto"
    return 1
  fi
  if ! bash -n "$mutado" 2>/dev/null; then
    malo "mutacion $3 no parsea; asi no prueba nada"
    return 1
  fi
  return 0
}

caso "mutacion: copia ausente tratada como no-aplica => C4 la atrapa"
rmut3="$(repo_sandbox repo-mut3)"
if mut_preparar "$rmut3" "s/_res='falta'/_res='no-aplica'/" "falta->no-aplica"; then
  export HOME="$tmp/casa-mut3"
  mkdir -p "$HOME/.claude/hooks" "$HOME/.grok" "$HOME/.dsh/hooks"
  cp "$rmut3/hooks/summonaikit-harness.sh" "$HOME/.claude/hooks/summonaikit-harness.sh"
  cp "$rmut3/hooks/summonaikit-harness.sh" "$HOME/.dsh/hooks/summonaikit-harness.sh"
  plantar_registro claude
  plantar_registro dsh
  out="$(bash "$mutado" --check 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then
    printf '    mutacion falta->no-aplica atrapada (C4 en rojo)\n'
  elif [ "$rc" -eq 1 ]; then
    malo "mutacion falta->no-aplica SOBREVIVIO: C4 dio verde con la guarda rota"
  else
    malo "mutacion falta->no-aplica invalida (rc=$rc, se esperaba el flip 1->0)"
  fi
fi

# El mutante vive en un repo git, asi que la procedencia desconocida se induce
# por SAIKIT_GIT_BIN (git-missing) en vez de checkout no-git: ambas caen en la
# misma rama del veredicto, que es lo que este sed toca.
caso "mutacion: veredicto sin fallo por procedencia desconocida => C5 la atrapa"
rmut4="$(repo_sandbox repo-mut4)"
if mut_preparar "$rmut4" 's/_fallo=1\(; _causas="[^"]*procedencia-desconocida"\)/_fallo=0\1/' "veredicto-sin-fallo"; then
  export HOME="$tmp/casa-mut4"
  mkdir -p "$HOME/.claude/hooks"
  cp "$rmut4/hooks/summonaikit-harness.sh" "$HOME/.claude/hooks/summonaikit-harness.sh"
  out="$(SAIKIT_GIT_BIN="$tmp/no-hay-git" bash "$mutado" --check 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then
    printf '    mutacion veredicto-sin-fallo atrapada (C5 en rojo)\n'
  elif [ "$rc" -eq 1 ]; then
    malo "mutacion veredicto-sin-fallo SOBREVIVIO"
  else
    malo "mutacion veredicto-sin-fallo invalida (rc=$rc, se esperaba el flip 1->0)"
  fi
fi

caso "mutacion: coincide con estado unknown => P9 la atrapa"
rmut9="$(repo_sandbox repo-mut9)"
git -C "$rmut9" update-ref -d refs/remotes/origin/master
if mut_preparar "$rmut9" "s/PROC_COINCIDE='sin-ref'/PROC_COINCIDE='unknown'/" "coincide-unknown"; then
  export HOME="$tmp/casa-mut9"
  mkdir -p "$HOME"
  out="$(bash "$mutado" --dry-run 2>&1)"; rc=$?
  if [ "$rc" -ne 0 ]; then
    malo "mutacion coincide-unknown invalida (rc=$rc, el dry-run debio salir 0)"
  elif printf '%s' "$out" | grep -qi 'unknown'; then
    printf '    mutacion coincide-unknown atrapada (P9 en rojo)\n'
  else
    malo "mutacion coincide-unknown SOBREVIVIO: P9 no vio el unknown"
  fi
fi

caso "mutacion: ausente como ok => C12 la atrapa"
rmut12="$(repo_sandbox repo-mut12)"
if mut_preparar "$rmut12" 's/ausente) printf falta-registro/ausente) printf ok/' "ausente-como-ok"; then
  export HOME="$tmp/casa-mut12"
  mkdir -p "$HOME/.claude/hooks" "$HOME/.grok/hooks" "$HOME/.dsh/hooks" "$HOME/.codex/hooks"
  for _hd in "$HOME/.claude/hooks" "$HOME/.grok/hooks" "$HOME/.dsh/hooks" "$HOME/.codex/hooks"; do
    cp "$rmut12/hooks/summonaikit-harness.sh" "$_hd/summonaikit-harness.sh"
  done
  plantar_registro claude
  plantar_registro grok
  plantar_registro dsh
  out="$(bash "$mutado" --check 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then
    printf '    mutacion ausente-como-ok atrapada (C12 en rojo)\n'
  elif [ "$rc" -eq 1 ]; then
    malo "mutacion ausente-como-ok SOBREVIVIO: C12 dio fallo con ausente=ok"
  else
    malo "mutacion ausente-como-ok invalida (rc=$rc, se esperaba el flip 1->0)"
  fi
fi

caso "mutacion: sin guarda -L => C13 la atrapa"
rmut13="$(repo_sandbox repo-mut13)"
if mut_preparar "$rmut13" 's/\[ -L /[ ! -L /' "sin-guarda-L"; then
  export HOME="$tmp/casa-mut13"
  mkdir -p "$HOME/.claude/hooks"
  ln -s "$rmut13/hooks/summonaikit-harness.sh" "$HOME/.claude/hooks/summonaikit-harness.sh"
  plantar_registro claude
  out="$(bash "$mutado" --check 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then
    printf '    mutacion sin-guarda-L atrapada (C13 en rojo)\n'
  elif [ "$rc" -eq 1 ]; then
    malo "mutacion sin-guarda-L SOBREVIVIO: C13 dio fallo sin [ -L ]"
  else
    malo "mutacion sin-guarda-L invalida (rc=$rc, se esperaba el flip 1->0)"
  fi
fi

if [ "$fail" -ne 0 ]; then
  echo "test_install_provenance: FAIL" >&2
  exit 1
fi
echo "test_install_provenance: OK"
