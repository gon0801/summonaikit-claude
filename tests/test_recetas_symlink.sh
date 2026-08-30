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
# cross-review grok r4 #9: no alcanza con que el DESTINO externo siga; el
# ENLACE tambien tiene que seguir en su lugar. "Intacto" es las dos cosas: un
# rm que se llevara el enlace y dejara el destino pasaba este caso igual.
[ -L "$recetas_dir" ] || malo "el enlace recetas/ no quedo intacto (se lo llevaron aunque el destino siga)"

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
# cross-review grok r4 #9: el enlace tambien tiene que seguir (ver arriba).
[ -L "$casa_recetas/.claude/skills/sencillo" ] || malo "el enlace /sencillo no quedo intacto (se lo llevaron aunque el destino siga)"

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
# cross-review grok r4 #1: el aviso dice "no se publica nada", y eso tiene que
# ser CIERTO tambien para el otro directorio. Antes recetas/ se publicaba
# ENTERO y despues abortaba al llegar a /sencillo: el operador leia "no se
# publica nada" con el recetario ya escrito. Ahora los dos destinos se miran
# antes de tocar ninguno.
[ ! -e "$(dirname "$dest")/recetas/bug.md" ] \
  || malo "dijo 'no se publica nada' pero recetas/ SI quedo publicado: $(dirname "$dest")/recetas/bug.md"
[ ! -e "$(dirname "$dest")/recetas/MANIFEST.sha256" ] \
  || malo "dijo 'no se publica nada' pero el manifiesto SI quedo publicado"

# cross-review grok r4 #8: el advisory del checker no puede afirmar integridad
# de contenido al que llega POR un enlace — no es del arbol gestionado. Es
# `unknown`, no "hash distinto" ni "ausente".
caso "checker: recetas/ como enlace => unknown, no un veredicto de integridad"
nuevo_destino; nuevo_casa_recetas
checker="$repo/tools/check-hook-registration.sh"
chk_dir="$casa_recetas/perfil-checker"
mkdir -p "$chk_dir/hooks" "$casa_recetas/recetario-externo"
escribir_receta_kit "$casa_recetas/recetario-externo/bug.md"
printf '%s\treceta\tbug\tfull\tTitulo\n' "$(printf 'a%.0s' $(seq 1 64))" \
  > "$casa_recetas/recetario-externo/MANIFEST.sha256"
ln -s "$casa_recetas/recetario-externo" "$chk_dir/hooks/recetas" 2>/dev/null
[ -L "$chk_dir/hooks/recetas" ] || { echo "    unknown: no se pudo crear el symlink de directorio"; exit "$SAIKIT_EXIT_UNKNOWN"; }
printf '{"hooks":{}}\n' > "$chk_dir/settings.json"
if out_c="$(bash "$checker" --settings "$chk_dir/settings.json" 2>&1)"; then rc_c=0; else rc_c=$?; fi
[ "$rc_c" -eq 0 ] || malo "el checker es fail-open: esperaba exit 0, dio $rc_c: $out_c"
printf '%s' "$out_c" | grep -q 'recetario: unknown' \
  || malo "con recetas/ como enlace debe decir 'recetario: unknown': $out_c"
printf '%s' "$out_c" | grep -q 'hash distinto' \
  && malo "no puede afirmar 'hash distinto' sobre contenido al que llega por un enlace: $out_c"

# CodeRabbit (PR #108): un enlace COLGANTE da `-e` FALSO y `-L` verdadero. Con
# el guard de enlace DESPUES del de existencia, el checker reportaba "ausente"
# algo que si esta — como enlace — y solo apunta a la nada. Los dos niveles
# (el directorio/manifiesto y la receta) tienen su caso.
caso "checker: recetas/ como enlace COLGANTE => unknown, nunca 'ausente'"
nuevo_destino; nuevo_casa_recetas
chk_dir="$casa_recetas/perfil-colgante"
mkdir -p "$chk_dir/hooks"
ln -s "$casa_recetas/no-existe-este-destino" "$chk_dir/hooks/recetas" 2>/dev/null
[ -L "$chk_dir/hooks/recetas" ] || { echo "    unknown: no se pudo crear el symlink"; exit "$SAIKIT_EXIT_UNKNOWN"; }
[ -e "$chk_dir/hooks/recetas" ] && malo "el enlace no quedo colgante; el caso no mide lo que dice"
printf '{"hooks":{}}\n' > "$chk_dir/settings.json"
out_d="$(bash "$repo/tools/check-hook-registration.sh" --settings "$chk_dir/settings.json" 2>&1)"
printf '%s' "$out_d" | grep -q 'recetario: unknown' \
  || malo "un enlace colgante debe dar 'recetario: unknown': $out_d"
printf '%s' "$out_d" | grep -q 'recetario: ausente' \
  && malo "un enlace colgante NO es 'ausente': esta ahi, apunta a la nada: $out_d"

caso "checker: una receta como enlace COLGANTE => unknown, nunca 'ausente'"
nuevo_destino; nuevo_casa_recetas
chk_dir="$casa_recetas/perfil-colgante-receta"
mkdir -p "$chk_dir/hooks/recetas"
printf '%s\treceta\tbug\tfull\tTitulo\n' "$(printf 'a%.0s' $(seq 1 64))" \
  > "$chk_dir/hooks/recetas/MANIFEST.sha256"
ln -s "$casa_recetas/no-existe-esta-receta" "$chk_dir/hooks/recetas/bug.md" 2>/dev/null
[ -L "$chk_dir/hooks/recetas/bug.md" ] || { echo "    unknown: no se pudo crear el symlink"; exit "$SAIKIT_EXIT_UNKNOWN"; }
[ -e "$chk_dir/hooks/recetas/bug.md" ] && malo "el enlace de la receta no quedo colgante"
printf '{"hooks":{}}\n' > "$chk_dir/settings.json"
out_e="$(bash "$repo/tools/check-hook-registration.sh" --settings "$chk_dir/settings.json" 2>&1)"
printf '%s' "$out_e" | grep -q 'recetario: unknown' \
  || malo "una receta con enlace colgante debe dar 'recetario: unknown': $out_e"
printf '%s' "$out_e" | grep -q 'recetario: ausente' \
  && malo "una receta con enlace colgante NO es 'ausente': $out_e"

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
