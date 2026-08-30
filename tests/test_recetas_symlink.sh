#!/usr/bin/env bash
# Task 16.5 — cobertura del symlink del recetario (archivo Y directorio) en un
# archivo PROPIO que corre en el CI de Linux.
#
# Por que un archivo aparte (cross-review, hilo "la cobertura no corre en ningun
# gate"): tests/test_install_hook.sh es Windows-bound y el CI Linux lo saltea
# ENTERO con SAIKIT_CI_LINUX=1, y este host Windows no crea symlinks reales (ln
# -s hace una copia), asi que los casos de symlink de ese archivo eran inertes en
# los DOS gates: no corrian en CI y aca daban SKIP. Este archivo NO esta en la
# lista de saltos Windows-bound (tests/run.sh la declara por nombre), asi que el
# job `suite` del CI lo corre como cualquier otro.
#
# Si el host no puede crear symlinks REALES, el archivo sale `unknown` (exit 3),
# no SKIP: asi en Windows la corrida declara que no pudo mirar (no es PASS) y en
# CI mide de verdad. Un `unknown` NO es un OK: tests/run.sh lo cuenta aparte.
set -u

SAIKIT_EXIT_UNKNOWN=3

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
tool="${SAIKIT_INSTALL_TOOL:-$repo/tools/install-hook.sh}"
fuente="$repo/hooks/summonaikit-harness.sh"
manifiesto="$repo/hooks/vendor-manifest.sha256"

fail=0
caso() { printf '  caso: %s\n' "$1"; }
malo() { printf '    FAIL: %s\n' "$1" >&2; fail=1; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/saikit-rec-symlink-XXXXXX")" || exit 1
export HOME="$tmp"
export USERPROFILE="$tmp"
mkdir -p "$tmp/.claude/skills"
trap 'rm -rf "$tmp"' EXIT

if [ ! -f "$tool" ]; then
  echo "    FAIL: no existe el instalador en $tool" >&2
  echo "test_recetas_symlink: FAIL" >&2
  exit 1
fi

# ¿Puede este host crear symlinks REALES? (en MSYS sin privilegio/Developer
# Mode, `ln -s` hace una COPIA y `[ -L ]` es false). Si no, salimos `unknown`:
# el caso es inerte aca pero corre en el CI de Linux, que NO saltea este archivo.
probe_t="$tmp/symlink-probe-target"; probe_l="$tmp/symlink-probe-link"
printf 'probe\n' > "$probe_t"
if ln -s "$probe_t" "$probe_l" 2>/dev/null && [ -L "$probe_l" ]; then
  :  # el host crea symlinks reales — los casos corren
else
  echo "  unknown: este host no crea symlinks reales (ln -s -> copia; requiere privilegio/Developer Mode)."
  echo "            El archivo corre en el CI de Linux, que NO lo saltea; aca no se pudo mirar (no es PASS ni FAIL)."
  exit "$SAIKIT_EXIT_UNKNOWN"
fi

# Cada caso estrena su propio destino y su propio HOME (igual que
# test_install_hook.sh): recetas/ y la skill /sencillo se publican a directorios
# por-caso, y "limpio"/"ajeno" miden el estado real y no contagio.
n_rc=0
casa_recetas=''
nuevo_casa_recetas() {
  n_rc=$((n_rc + 1))
  casa_recetas="$tmp/casa-recetas-$n_rc"
}
n_destino=0
dest=''
nuevo_destino() {
  n_destino=$((n_destino + 1))
  local d="$tmp/destino-$n_destino/.claude/hooks"
  mkdir -p "$d"
  dest="$d/summonaikit-harness.sh"
}
host_claude_recetas() {
  HOME="$casa_recetas" USERPROFILE="$casa_recetas" \
  SAIKIT_CLAUDE_AGENTS_DIR="$casa_recetas/agents" \
    bash "$tool" --host claude --dest "$dest" --source "$fuente" --manifest "$manifiesto" "$@"
}

# Un archivo con la marca del kit (reconocible por zcode_agente_tiene_marca):
# frontmatter YAML con `saikit_owned: summonaikit-claude`, como una receta real.
escribir_receta_kit() {
  { printf '%s\n' '---'
    printf '%s\n' 'saikit_owned: summonaikit-claude'
    printf '%s\n' 'nombre: bug'
    printf '%s\n' 'titulo: Titulo'
    printf '%s\n' 'carril: full'
    printf '%s\n' '---'
    printf '%s\n' '## Pasos'
    printf '%s\n' '1. Paso.'; } > "$1"
}

# ============================================================================
# INSTALAR — un symlink del DESTINO no se sigue ni se importa
# ============================================================================
# 16.5 (cross-review, hilo symlink): un symlink plantado en el destino (recetas/)
# no es nuestro — nunca lo plantamos asi — y no se sigue: el archivo externo
# queda INTACTO. El `cp -r` del staging replicaba el symlink como symlink y el
# `cp` siguiente lo seguia y escribia encima del archivo externo.
caso "recetario: un symlink de ARCHIVO no se sigue al instalar (externo intacto y se reporta)"
nuevo_destino; nuevo_casa_recetas
recetas_dir="$(dirname "$dest")/recetas"
mkdir -p "$recetas_dir" "$casa_recetas"
printf 'contenido externo, ajeno al kit\n' > "$casa_recetas/externo.md"
ln -s "$casa_recetas/externo.md" "$recetas_dir/bug.md" 2>/dev/null
[ -L "$recetas_dir/bug.md" ] || { echo "    unknown: no se pudo crear el symlink de archivo"; exit "$SAIKIT_EXIT_UNKNOWN"; }
antes="$(cksum < "$casa_recetas/externo.md")"
out="$(host_claude_recetas 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "un symlink no debe abortar la instalacion, dio $rc: $out"
[ "$antes" = "$(cksum < "$casa_recetas/externo.md")" ] || malo "se escribio sobre el archivo externo via el symlink"
printf '%s' "$out" | grep -qi 'desconocid\|no se toca' || malo "no reporto el symlink como no-tocado: $out"
[ -L "$recetas_dir/bug.md" ] || malo "se reemplazo el symlink que no era nuestro"

# 16.5 (cross-review, hilo symlink de DIRECTORIO): el guard `-L` de
# recetas_clasificar mira el ARCHIVO, no al directorio. Si recetas/ MISMO es un
# symlink a un dir externo, el swap del instalador lo seguia ([ -d ]), copiaba el
# contenido ajeno al staging y dejaba un DIRECTORIO REAL en lugar del enlace —
# importando contenido cuya propiedad nunca se clasifico. Se rechaza ANTES.
caso "recetario: un symlink de DIRECTORIO no se publica al instalar (externo intacto)"
nuevo_destino; nuevo_casa_recetas
recetas_dir="$(dirname "$dest")/recetas"
externo="$casa_recetas/recetas-externas"
mkdir -p "$externo"
escribir_receta_kit "$externo/bug.md"
ln -s "$externo" "$recetas_dir" 2>/dev/null
[ -L "$recetas_dir" ] || { echo "    unknown: no se pudo crear el symlink de directorio"; exit "$SAIKIT_EXIT_UNKNOWN"; }
antes="$(cksum < "$externo/bug.md")"
out="$(host_claude_recetas 2>&1)"; rc=$?
[ "$rc" -ne 0 ] || malo "instalar sobre un recetario-symlink debe salir != 0 (fail-closed), dio 0: $out"
[ -L "$recetas_dir" ] || malo "el instalador reemplazo el symlink de directorio (lo importo en un dir real)"
[ "$antes" = "$(cksum < "$externo/bug.md")" ] || malo "se toco el contenido externo via el symlink de directorio"
printf '%s' "$out" | grep -qi 'enlace, no se publica nada' || malo "debe reportar 'enlace, no se publica nada': $out"

# ============================================================================
# QUITAR — un symlink del DESTINO no se borra ni se atraviesa
# ============================================================================
# 16.5 (cross-review codex-16.5-r2): un symlink en recetas/ no se toca tampoco al
# QUITAR, por consistencia con el instalador. rm -f des-enlaza (no borra el
# destinatario), pero se trata como ajeno.
caso "recetario: un symlink de ARCHIVO no se borra al quitar (externo intacto)"
nuevo_destino; nuevo_casa_recetas
recetas_dir="$(dirname "$dest")/recetas"
mkdir -p "$recetas_dir" "$casa_recetas"
printf 'contenido externo, ajeno al kit\n' > "$casa_recetas/externo.md"
ln -s "$casa_recetas/externo.md" "$recetas_dir/bug.md" 2>/dev/null
[ -L "$recetas_dir/bug.md" ] || { echo "    unknown: no se pudo crear el symlink de archivo"; exit "$SAIKIT_EXIT_UNKNOWN"; }
antes="$(cksum < "$casa_recetas/externo.md")"
out="$(host_claude_recetas --quitar-recetas 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "--quitar-recetas con symlink deberia salir 0, dio $rc: $out"
[ "$antes" = "$(cksum < "$casa_recetas/externo.md")" ] || malo "el symlink hizo que se borrara el archivo externo"
[ -L "$recetas_dir/bug.md" ] || malo "se borro el symlink que no era nuestro"
printf '%s' "$out" | grep -qi 'enlace, intacto' || malo "debe reportar el symlink como 'enlace, intacto': $out"

# 16.5 (cross-review, hilo symlink de DIRECTORIO): si recetas/ MISMO es un
# symlink a un dir externo, el glob "$1/recetas/*.md" lo atravesaba y `rm -f`
# borraba archivos EXTERNOS (que llevan la marca del kit), y el manifiesto leido
# a traves del symlink podia atribuirle la propiedad a uno externo. Se rechaza
# antes del glob y de la lectura del manifiesto.
caso "recetario: un symlink de DIRECTORIO no se borra al quitar (externo intacto)"
nuevo_destino; nuevo_casa_recetas
recetas_dir="$(dirname "$dest")/recetas"
externo="$casa_recetas/recetas-externas"
mkdir -p "$externo"
escribir_receta_kit "$externo/bug.md"
printf 'deadbeef\treceta\tbug\tfull\tTitulo externo\n' > "$externo/MANIFEST.sha256"
ln -s "$externo" "$recetas_dir" 2>/dev/null
[ -L "$recetas_dir" ] || { echo "    unknown: no se pudo crear el symlink de directorio"; exit "$SAIKIT_EXIT_UNKNOWN"; }
out="$(host_claude_recetas --quitar-recetas 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "--quitar-recetas con directorio-symlink deberia salir 0, dio $rc: $out"
[ -e "$externo/bug.md" ] || malo "el symlink de directorio hizo que se borrara el archivo externo (CON marca): $externo/bug.md"
[ -e "$externo/MANIFEST.sha256" ] || malo "el symlink de directorio hizo que se borrara el manifiesto externo"
printf '%s' "$out" | grep -qi 'enlace, intacto' || malo "debe reportar el symlink de directorio como 'enlace, intacto': $out"

# 16.5 (cross-review, hilo symlink de DIRECTORIO): lo mismo aplica a la skill
# /sencillo — "$2/sencillo/SKILL.md" atravesaba un symlink de directorio en
# sencillo/ y podia borrar el SKILL.md externo.
caso "recetario: un symlink de DIRECTORIO en /sencillo no se borra al quitar (externo intacto)"
nuevo_destino; nuevo_casa_recetas
mkdir -p "$casa_recetas/.claude/skills"
externo="$casa_recetas/skill-externa"
mkdir -p "$externo"
escribir_receta_kit "$externo/SKILL.md"
ln -s "$externo" "$casa_recetas/.claude/skills/sencillo" 2>/dev/null
[ -L "$casa_recetas/.claude/skills/sencillo" ] || { echo "    unknown: no se pudo crear el symlink de directorio"; exit "$SAIKIT_EXIT_UNKNOWN"; }
out="$(host_claude_recetas --quitar-recetas 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "--quitar-recetas con /sencillo-symlink deberia salir 0, dio $rc: $out"
[ -e "$externo/SKILL.md" ] || malo "el symlink de /sencillo hizo que se borrara la skill externa"
printf '%s' "$out" | grep -qi 'enlace, intacto' || malo "debe reportar el symlink de /sencillo como 'enlace, intacto': $out"

# 16.5 (cross-review Codex, P3-2): el guard de `recetas_publicar_dir` es
# compartido por recetas y /sencillo, pero el lado INSTALAR solo se probaba con
# recetas/ symlink. Falta el caso de /sencillo symlink al instalar: fail-closed
# (exit != 0), sin tocar el externo ni reemplazar el enlace.
caso "recetario: un symlink de DIRECTORIO en /sencillo no se publica al instalar (externo intacto)"
nuevo_destino; nuevo_casa_recetas
mkdir -p "$casa_recetas/.claude/skills"
externo="$casa_recetas/skill-externa"
mkdir -p "$externo"
escribir_receta_kit "$externo/SKILL.md"
ln -s "$externo" "$casa_recetas/.claude/skills/sencillo" 2>/dev/null
[ -L "$casa_recetas/.claude/skills/sencillo" ] || { echo "    unknown: no se pudo crear el symlink de directorio"; exit "$SAIKIT_EXIT_UNKNOWN"; }
antes="$(cksum < "$externo/SKILL.md")"
out="$(host_claude_recetas 2>&1)"; rc=$?
[ "$rc" -ne 0 ] || malo "instalar con /sencillo-symlink debe salir != 0 (fail-closed), dio 0: $out"
[ -L "$casa_recetas/.claude/skills/sencillo" ] || malo "el instalador reemplazo el symlink de /sencillo (lo importo en un dir real)"
[ "$antes" = "$(cksum < "$externo/SKILL.md")" ] || malo "se toco el SKILL.md externo via el symlink de /sencillo"
printf '%s' "$out" | grep -qi 'enlace, no se publica nada' || malo "debe reportar 'enlace, no se publica nada': $out"

# 16.5 (cross-review Codex, P3-3): el guard NO debe sobreproteger. Si recetas/
# es symlink (r_enlace=1) pero /sencillo es un dir REAL con contenido nuestro,
# al quitar se deja intacta recetas y SI se borra el SKILL.md nuestro de sencillo
# (independencia de los dos flags).
caso "recetario: recetas/ symlink + /sencillo REAL — al quitar solo se borra lo nuestro de /sencillo"
nuevo_destino; nuevo_casa_recetas
recetas_dir="$(dirname "$dest")/recetas"
externo_recetas="$casa_recetas/recetas-externas"
mkdir -p "$externo_recetas" "$casa_recetas/.claude/skills/sencillo"
escribir_receta_kit "$externo_recetas/bug.md"
escribir_receta_kit "$casa_recetas/.claude/skills/sencillo/SKILL.md"
ln -s "$externo_recetas" "$recetas_dir" 2>/dev/null
[ -L "$recetas_dir" ] || { echo "    unknown: no se pudo crear el symlink de directorio"; exit "$SAIKIT_EXIT_UNKNOWN"; }
out="$(host_claude_recetas --quitar-recetas 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "deberia salir 0, dio $rc: $out"
[ -e "$externo_recetas/bug.md" ] || malo "recetas/ symlink NO debe tocar el externo (sobreprotege): $externo_recetas/bug.md"
[ ! -e "$casa_recetas/.claude/skills/sencillo/SKILL.md" ] || malo "el SKILL.md nuestro de /sencillo REAL deberia BORRARSE (independencia de s_enlace)"
printf '%s' "$out" | grep -qi 'enlace, intacto' || malo "debe reportar recetas/ como 'enlace, intacto': $out"

# 16.5 (cross-review codex/grok, P3): el manifiesto es un symlink de ARCHIVO —
# no es nuestro y no se lee al quitar (rm -f solo des-enlazaria, pero se trata
# como ajeno, igual que las recetas symlink).
caso "recetario: un symlink de ARCHIVO en el MANIFEST no se lee al quitar (externo intacto)"
nuevo_destino; nuevo_casa_recetas
recetas_dir="$(dirname "$dest")/recetas"
mkdir -p "$recetas_dir" "$casa_recetas"
printf 'deadbeef\treceta\tbug\tfull\tTitulo externo\n' > "$casa_recetas/manifiesto-externo.sha256"
ln -s "$casa_recetas/manifiesto-externo.sha256" "$recetas_dir/MANIFEST.sha256" 2>/dev/null
[ -L "$recetas_dir/MANIFEST.sha256" ] || { echo "    unknown: no se pudo crear el symlink de archivo"; exit "$SAIKIT_EXIT_UNKNOWN"; }
out="$(host_claude_recetas --quitar-recetas 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "deberia salir 0, dio $rc: $out"
[ -e "$casa_recetas/manifiesto-externo.sha256" ] || malo "se borro el manifiesto externo via el symlink de archivo"
[ -L "$recetas_dir/MANIFEST.sha256" ] || malo "se reemplazo el symlink del manifiesto"
printf '%s' "$out" | grep -qi 'enlace, intacto' || malo "debe reportar el manifiesto-symlink como 'enlace, intacto': $out"

if [ "$fail" -ne 0 ]; then
  echo "test_recetas_symlink: FAIL" >&2
  exit 1
fi
echo "test_recetas_symlink: OK"
exit 0
