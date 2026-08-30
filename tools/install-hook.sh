#!/usr/bin/env bash
# install-hook.sh — instala el hook por REEMPLAZO, con tres estados (Task 2.2).
#
# El problema que resuelve: el archivo que gatea cada turno vive en
# `~/.claude/hooks/`, fuera del repo. Sincronizarlo con un `cp` tiene dos modos
# de falla graves y silenciosos:
#
#   1. Pisa un cambio legitimo que alguien mas hizo en el destino. Un `cp` no
#      sabe distinguir "el archivo de siempre" de "un archivo que no vimos
#      nunca". Por eso hay TRES estados y no dos:
#
#        NUESTRO         (marcador en la linea 2) => verificar; reparar si difiere
#        VENDOR CONOCIDO (sha256 en el manifiesto) => archivar y reemplazar
#        DESCONOCIDO     (ninguna de las dos)      => NO TOCAR y reportar fuerte
#
#   2. Deja el destino a medio escribir. `cp` no es atomico: un hook truncado no
#      rompe el turno que lo instalo, rompe TODOS los siguientes. Por eso se
#      escribe a un temporal EN EL MISMO DIRECTORIO, se valida ahi (`bash -n`
#      mas igualdad byte a byte con la fuente) y recien entonces `mv`.
#
# Politica ante lo no observable: este script es la UNICA excepcion declarada al
# fail-open del spec (Core Rule 1). El hook deja pasar lo que no puede medir
# porque corre en cada turno; escribir sobre el a ciegas no admite esa politica.
# Aca lo no observable falla CERRADO: no escribe y sale != 0. Y se reporta como
# `unknown`, nunca como "el destino es raro" (Core Rule 2): no haber podido
# consultar el manifiesto no es lo mismo que haber visto que el hash no esta.
#
# La vuelta atras (--restore-vendor, Task 2.4) tiene los MISMOS modos de falla
# que la ida, asi que se le exige la misma disciplina y no un `cp`: elige el
# backup del vendor mas reciente, valida el archivo que va a quedar, archiva
# antes lo que habia —volver atras tiene que ser reversible— y recien ahi `mv`.
# Un destino DESCONOCIDO no se pisa ni para deshacer: que el comando se llame
# "restaurar" no lo habilita a destruir el cambio de otro.
#
# Uso:
#   bash tools/install-hook.sh [--dry-run]
#   bash tools/install-hook.sh --dest <path> --source <path> --manifest <path>
#   bash tools/install-hook.sh --restore-vendor [--dest <path>] [--dry-run]
#   bash tools/install-hook.sh --host zcode [--quitar-zcode]
#   bash tools/install-hook.sh --host codex
#   bash tools/install-hook.sh --host grok [--quitar-grok]
#   bash tools/install-hook.sh --host kimi [--dry-run]
#   bash tools/install-hook.sh --host claude [--dry-run]
#   bash tools/install-hook.sh --host dsh [--dry-run] [--quitar-dsh]
#   bash tools/install-hook.sh --host claude --refrescar-manifiesto
#   bash tools/install-hook.sh --host kimi --refrescar-manifiesto
#
# Exit codes (cualquier != 0 significa que el destino quedo INTACTO):
#   0  instalado / reparado / restaurado / ya estaba al dia
#   2  invocacion o fuente invalida
#   3  destino DESCONOCIDO: no se toco
#   4  no observable (unknown): no se toco
#   5  la escritura no se pudo completar: no se toco
#   6  se MIRO y no hay backup del vendor para restaurar (solo --restore-vendor).
#      Es un hecho observado, y por eso no comparte codigo con el 4: confundirlos
#      dejaria al operador sin saber si buscar el archivo o arreglar permisos.
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"

DEST="${HOME:-}/.claude/hooks/summonaikit-harness.sh"
SOURCE="$repo/hooks/summonaikit-harness.sh"
MANIFEST="$repo/hooks/vendor-manifest.sha256"
DRY_RUN=0
CHECK_REGISTRO=1
RESTORE=0
# Task 5.4: --host zcode es append-only al user-config de zcode (no toca DEST).
# Task 5.6: ademas instala implementer/verifier/reviewer en ~/.zcode/agents
# (el runtime de zcode solo conoce tipos registrados ahi; sin ellos el
# candado de secuencia es inalcanzable). No toca DEST.
# Task 13.8: adversary se suma como cuarto perfil instalado (zcode, grok,
# claude y kimi via CLAUDE_AGENT_ROLES).
HOST=''
QUITAR_ZCODE=0
# Task 7.5: --quitar-grok es la vuelta atras del host grok (JSON propio + hook
# + agentes con marca); requiere --host grok, como --quitar-zcode con zcode.
QUITAR_GROK=0
# Phase 15 (D5): --quitar-dsh es la vuelta atras del host dsh (hook + plugin +
# patch del profile + personas con marca); requiere --host dsh.
QUITAR_DSH=0
# Task 16.5 (D1): --quitar-recetas retira SOLO lo nuestro de <hookdir>/recetas/
# y ~/.claude/skills/sencillo (marca saikit_owned; el manifiesto se juzga por
# las marcas de las recetas que nombra); requiere el flujo claude.
QUITAR_RECETAS=0
# Task 6.5: --host codex escribe la SEGUNDA copia (~/.codex/hooks) por el flujo
# NORMAL de DEST; VIO_DEST distingue "el operador eligio ruta" de "usar la que
# el host declara".
VIO_DEST=0
# Task 12.6: --host claude instala implementer/verifier/reviewer en
# ~/.claude/agents (adversary desde la 13.8) con la via de adopcion del
# CUARTO estado (VENDOR_CONOCIDO por hash en agents/vendor-manifest.sha256).
# No toca DEST: el hook global ya vive ahi por el flujo normal (sin --host).
# --refrescar-manifiesto REPORTA (hash + diff), JAMAS adopta: adoptar es un
# commit propio que pega el hash nuevo en el manifiesto, con el diff a la
# vista en la revision.
REFRESCAR_MANIFIESTO=0

# Posicion y formato fijos, como los declara el spec (§ La adopcion). La linea 1
# es el shebang: un marcador antes de el rompe la ejecucion. Se lee UNA linea,
# que es justo lo que necesita tambien el skip de quality-kit (Task 2.3).
MARCADOR_LINEA=2
MARCADOR_PREFIJO='# SAIKIT-CLAUDE-OWNED '
MARCADOR_RE='^# SAIKIT-CLAUDE-OWNED summonaikit-claude [^[:space:]]+$'

while [ $# -gt 0 ]; do
  case "$1" in
    --dest)     DEST="${2:-}"; VIO_DEST=1; shift 2 ;;
    --source)   SOURCE="${2:-}"; shift 2 ;;
    --manifest) MANIFEST="${2:-}"; shift 2 ;;
    --dry-run)  DRY_RUN=1; shift ;;
    --restore-vendor) RESTORE=1; shift ;;
    --no-registration-check) CHECK_REGISTRO=0; shift ;;
    --host)     HOST="${2:-}"; shift 2 ;;
    --quitar-zcode) QUITAR_ZCODE=1; shift ;;
    --quitar-grok) QUITAR_GROK=1; shift ;;
    --quitar-dsh) QUITAR_DSH=1; shift ;;
    --quitar-recetas) QUITAR_RECETAS=1; shift ;;
    --refrescar-manifiesto) REFRESCAR_MANIFIESTO=1; shift ;;
    -h|--help)  sed -n '2,50p' "$0"; exit 0 ;;
    *)
      printf '[summonaikit] instalador: opcion desconocida: %s\n' "$1" >&2
      exit 2
      ;;
  esac
done

# Task 5.4 / 6.5 / 7.5 / 12.6 / 12.7: --host acepta zcode (registro-only, no
# toca DEST), codex (instala la SEGUNDA copia en ~/.codex/hooks por el flujo
# normal de DEST), grok (TERCERA copia en ~/.grok/hooks + JSON propio +
# agentes), claude (agentes en ~/.claude/agents, no toca DEST) y kimi
# (agentes en ~/.agents/agents, no toca DEST; la 12.3 midio que el host no
# acepta model:/effort: por agente, asi que --host kimi NO instala ruteo).
# Phase 15: dsh (hook + plugin + patch del profile + personas; D5 compone a
# nivel home).
# Otro valor no se acepta: falla antes de tocar el archivo o el config.
if [ -n "$HOST" ] && [ "$HOST" != "zcode" ] && [ "$HOST" != "codex" ] && [ "$HOST" != "grok" ] && [ "$HOST" != "claude" ] && [ "$HOST" != "kimi" ] && [ "$HOST" != "dsh" ]; then
  printf '[summonaikit] instalador: --host solo acepta "zcode", "codex", "grok", "claude", "kimi" o "dsh" (recibido: %s)\n' "$HOST" >&2
  exit 2
fi
# Task 12.9 (hallazgo #6, grok): kimi reusa el MISMO manifiesto
# (agents/vendor-manifest.sha256 no es por-host, mapea hash -> rol) pero antes
# no tenia via de refresco -- un saikit-update que cambiara los perfiles de
# kimi los dejaba DESCONOCIDO para siempre sin el procedimiento que el propio
# --refrescar-manifiesto promete. Mismo modo reporta-jamas-adopta que claude.
if [ "$REFRESCAR_MANIFIESTO" -eq 1 ] && [ "$HOST" != "claude" ] && [ "$HOST" != "kimi" ]; then
  printf '[summonaikit] instalador: --refrescar-manifiesto requiere --host claude o --host kimi\n' >&2
  exit 2
fi
if [ "$QUITAR_ZCODE" -eq 1 ] && [ "$HOST" != "zcode" ]; then
  printf '[summonaikit] instalador: --quitar-zcode requiere --host zcode\n' >&2
  exit 2
fi
if [ "$QUITAR_GROK" -eq 1 ] && [ "$HOST" != "grok" ]; then
  printf '[summonaikit] instalador: --quitar-grok requiere --host grok\n' >&2
  exit 2
fi
if [ "$QUITAR_DSH" -eq 1 ] && [ "$HOST" != "dsh" ]; then
  printf '[summonaikit] instalador: --quitar-dsh requiere --host dsh\n' >&2
  exit 2
fi
# Task 16.5: --quitar-recetas despacha a quitar_recetas_claude y solo tiene
# sentido en el flujo claude (el recetario y /sencillo son de ese host).
if [ "$QUITAR_RECETAS" -eq 1 ] && [ -n "$HOST" ] && [ "$HOST" != "claude" ]; then
  printf '[summonaikit] instalador: --quitar-recetas requiere --host claude\n' >&2
  exit 2
fi

# Task 6.5 (D1): el destino lo decide --host, y cada host declara su ruta.
# Sin --dest explicito, --host codex instala en la ruta que el wrapper .ps1 ya
# lee como fallback (~/.codex/hooks). La copia NO se inventa: existe desde
# antes y es carga estructural del .ps1 — la unica via por la que el TARGET
# llega en Codex (6.1). El instalador es el UNICO escritor de ambas rutas y
# las compara byte a byte contra la misma fuente: no divergen sin que grite.
if [ "$HOST" = "codex" ] && [ "$VIO_DEST" -eq 0 ]; then
  DEST="${HOME:-}/.codex/hooks/summonaikit-harness.sh"
fi

# Task 7.5 (D1): grok declara su propia ruta (~/.grok/hooks). A diferencia de
# zcode, --host grok SI escribe el archivo: PROFILE_DIR sale de dirname del
# hook, y solo con la copia en ~/.grok la contencion de A6 cubre
# ~/.grok/sessions (design D1, razon 1). Override de test: SAIKIT_GROK_HOOKS_DIR
# (misma costura que SAIKIT_ZCODE_*).
if [ "$HOST" = "grok" ] && [ "$VIO_DEST" -eq 0 ]; then
  DEST="${SAIKIT_GROK_HOOKS_DIR:-${HOME:-}/.grok/hooks}/summonaikit-harness.sh"
fi

# Phase 15 (D5): dsh declara su propia ruta (~/.dsh/hooks/). Override de test:
# SAIKIT_DSH_HOME (misma costura que SAIKIT_GROK_HOOKS_DIR / SAIKIT_ZCODE_*).
if [ "$HOST" = "dsh" ] && [ "$VIO_DEST" -eq 0 ]; then
  DEST="${SAIKIT_DSH_HOME:-${HOME:-}/.dsh}/hooks/summonaikit-harness.sh"
fi

# Task 5.4 (hallazgo 6) / 6.5: ~/.zcode se niega SIEMPRE — ahi el estado se
# separa por HOST y una copia seria inventada. ~/.codex se habilita SOLO con
# --host codex: la regla nueva es que el destino lo decide --host, no que haya
# una sola copia (D1 declaro la segunda para Codex).
_zc_prefix="$(printf '%s/.zcode' "${HOME:-}")"
case "$DEST" in
  "$_zc_prefix"|"$_zc_prefix"/*)
    printf '[summonaikit] instalador: --dest (%s) cae bajo ~/.zcode: rechazado.\n' "$DEST" >&2
    printf '             El destino lo decide --host y zcode no declara copia propia: su estado\n' >&2
    printf '             se separa por HOST sobre la copia de ~/.claude/hooks (5.3/5.4).\n' >&2
    exit 2
    ;;
esac
_cx_prefix="$(printf '%s/.codex' "${HOME:-}")"
if [ "$HOST" != "codex" ]; then
  case "$DEST" in
    "$_cx_prefix"|"$_cx_prefix"/*)
      printf '[summonaikit] instalador: --dest (%s) cae bajo ~/.codex: rechazado sin --host codex.\n' "$DEST" >&2
      printf '             El destino lo decide --host y cada host declara su ruta (6.5/D1).\n' >&2
      exit 2
      ;;
  esac
fi
# Task 7.5: ~/.grok se habilita SOLO con --host grok (misma guardia de prefijo
# que codex): el JSON de registro y los agentes de ese host los escribe este
# instalador, y un --dest perdido ahi dejaria cableado cruzado entre hosts.
_gk_prefix="$(printf '%s/.grok' "${HOME:-}")"
if [ "$HOST" != "grok" ]; then
  case "$DEST" in
    "$_gk_prefix"|"$_gk_prefix"/*)
      printf '[summonaikit] instalador: --dest (%s) cae bajo ~/.grok: rechazado sin --host grok.\n' "$DEST" >&2
      printf '             El destino lo decide --host y cada host declara su ruta (7.5/D1).\n' >&2
      exit 2
      ;;
  esac
fi
# Phase 15 (D5): ~/.dsh se habilita SOLO con --host dsh (misma guardia de
# prefijo que codex/grok): el hook, el plugin y el patch del profile de ese
# host los escribe este instalador, y un --dest perdido ahi dejaria cableado
# cruzado entre hosts.
_dh_prefix="$(printf '%s/.dsh' "${HOME:-}")"
if [ "$HOST" != "dsh" ]; then
  case "$DEST" in
    "$_dh_prefix"|"$_dh_prefix"/*)
      printf '[summonaikit] instalador: --dest (%s) cae bajo ~/.dsh: rechazado sin --host dsh.\n' "$DEST" >&2
      printf '             El destino lo decide --host y cada host declara su ruta (15/D5).\n' >&2
      exit 2
      ;;
  esac
fi

decir() { printf '%s\n' "$*"; }

# El aviso del REGISTRO (Task 0.3) es el otro requisito del spec para instalar:
# el archivo puede quedar perfecto y el gate no existir si `settings.json` dejo
# de nombrarlo. Es ADVISORY — ese verificador es fail-open y su resultado no
# mueve el exit code de este script. Se le pasa el settings HERMANO del destino
# y no el del HOME real, para que apuntar `--dest` a un fixture no termine
# mirando el perfil vivo (Core Rule 4).
avisar_registro() {
  [ "$CHECK_REGISTRO" -eq 1 ] || return 0
  local verificador settings
  verificador="$here/check-hook-registration.sh"
  [ -r "$verificador" ] || return 0
  # Task 6.5: en codex el registro no nombra al hook sino al wrapper .ps1, y
  # vive en hooks.json (hermano del dir de hooks). La forma codex del
  # verificador hace las DOS afirmaciones (registro->wrapper, wrapper->hook).
  if [ "$HOST" = "codex" ]; then
    bash "$verificador" --codex-hooks-json "$(dirname "$(dirname "$DEST")")/hooks.json" || true
    return 0
  fi
  # Task 7.5: en grok el registro es el JSON hermano del hook
  # (<dir del hook>/summonaikit.json); el verificador hace sus TRES
  # afirmaciones (JSON->hook, existencia+marca, matcher de delegacion).
  if [ "$HOST" = "grok" ]; then
    bash "$verificador" --grok-hooks-dir "$(dirname "$DEST")" || true
    return 0
  fi
  # Phase 15: en dsh el registro del plugin vive en <dsh-home>/cordis.patch.yml
  # (el plugin compuesto no se registra por archivo de hooks). El verificador de
  # dsh hace sus afirmaciones (hook + plugin + patch con personas).
  if [ "$HOST" = "dsh" ]; then
    bash "$verificador" --dsh-home "$(dsh_home)" || true
    return 0
  fi
  settings="$(dirname "$(dirname "$DEST")")/settings.json"
  bash "$verificador" --settings "$settings" --hook-name "$(basename "$DEST")" || true
}

# ----------------------------------------------------------- Task 5.4: zcode
# La SEGUNDA forma de registro (hooks.events.*) vive en el user-config de zcode
# (~/.zcode/cli/config.json). --host zcode es append-only a ese archivo: NO toca
# DEST (el archivo del hook). El archivo se instala antes, con la invocacion sin
# --host. Asi el contrato "exit != 0 => DEST intacto" se conserva: esta rama no
# escribe DEST.
#
# zcode_bash_win es duplicado intencional de capture-payloads.sh (5.1): aca el
# command apunta al HARNESS, no al capturador. Extraer a una lib comun es otra
# task. NUNCA persistir /usr/bin/bash: en MSYS es una ruta virtual que Node
# resuelve con ENOENT (R2.5 del plan 5.1).
zcode_bash_win() {
  local cand b bw
  # Override de test (Task 5.6 / hallazgo 3): si la variable ESTA seteada,
  # no se busca en disco. Vacia o ruta inexistente => fallo. Asi se puede
  # medir "sin bash.exe no se escriben agentes" sin mentir sobre PATH.
  if [ "${SAIKIT_ZCODE_BASH_WIN+set}" = "set" ]; then
    if [ -n "$SAIKIT_ZCODE_BASH_WIN" ] && [ -f "$SAIKIT_ZCODE_BASH_WIN" ]; then
      printf '%s' "$SAIKIT_ZCODE_BASH_WIN"; return 0
    fi
    return 1
  fi
  for cand in \
    "C:/Program Files/Git/bin/bash.exe" \
    "C:/Program Files (x86)/Git/bin/bash.exe" \
    "C:/Program Files/Git/usr/bin/bash.exe"; do
    if [ -f "$cand" ]; then printf '%s' "$cand"; return 0; fi
  done
  if b="$(command -v bash 2>/dev/null)" && [ -n "$b" ] && command -v cygpath >/dev/null 2>&1; then
    bw="$(cygpath -w "$b" 2>/dev/null)" && [ -n "$bw" ] && { printf '%s' "$bw"; return 0; }
  fi
  return 1
}

# El command registrado para el harness en zcode: bash.exe + DEST + marker 5.4.
# Sin SUMMONAIKIT_HOOK_TARGET (A10: el host no propaga VAR=val; el hook detecta
# zcode por ZCODE_*). Sin --only-cwd (no es un probe: el gate corre en todos los
# repos; HOST+proyecto+sesion separan el estado, Task 5.3/3.4).
zcode_harness_cmd() {  # $1=bash_win
  printf '"%s" "%s" --saikit-harness-id 5.4' "$1" "$DEST"
}

zcode_user_config() {
  printf '%s' "${SAIKIT_ZCODE_USER_CONFIG:-${HOME:-}/.zcode/cli/config.json}"
}

# Task 5.6: perfiles de subagente. zcode (3.7.5-11) carga:
#   {storageRoot}/agents/*.md          → ~/.zcode/agents/<name>.md
#   {cwd}/.zcode/agents/*.md           → project (Settings Beta no lo edita)
# Built-ins fijos: general-purpose, Explore. Sin los perfiles del kit
# registrados, Agent type 'implementer' not found y el Stop no puede pasar.
# Fuente = agents/ del repo (no ~/.claude/agents: Core Rule 4). Destino
# overrideable para tests. Tres estados, igual que DEST: AUSENTE instala,
# NUESTRO_IDENTICO no reescribe, NUESTRO_DISTINTO repara con backup,
# DESCONOCIDO no se toca (el tipo ya existe; el hook igual se registra —
# no es "no se puede satisfacer la ceremonia", es un perfil de otro).
ZCODE_AGENT_ROLES='implementer verifier reviewer adversary'
ZCODE_AGENT_MARCA_RE='^saikit_owned:[[:space:]]*summonaikit-claude[[:space:]]*$'

# Trads que quedan pendientes de limpiar entre la clasificacion y la
# publicacion (bucles two-phase de zcode y de instalar_agentes_con_vendor).
# Global (no local a la funcion) a proposito: no es reentrante ni recursiva,
# y asi limpiar_trads_vendor() puede llamarse desde cualquier punto de salida
# sin depender de scoping dinamico de bash. VIVE ACA (antes del dispatch de
# zcode) porque bash resuelve funciones al LLAMARLAS: declarado mas abajo, el
# dispatch de zcode lo usaba antes de que existiera — `command not found`
# atrapado en vivo por el deploy de 13.9, invisible para los tests porque no
# movia ningun veredicto (solo ensuciaba stderr y dejaba trads sin limpiar).
TRADS_VENDOR_PENDIENTES=()
limpiar_trads_vendor() {
  local t
  for t in "${TRADS_VENDOR_PENDIENTES[@]:-}"; do
    [ -n "$t" ] && rm -f "$t"
  done
  TRADS_VENDOR_PENDIENTES=()
}

zcode_agents_source() {
  printf '%s' "${SAIKIT_ZCODE_AGENTS_SOURCE:-$repo/agents}"
}
zcode_agents_dir() {
  printf '%s' "${SAIKIT_ZCODE_AGENTS_DIR:-${HOME:-}/.zcode/agents}"
}

# Solo el primer bloque --- ... ---. Una marca en el body (ejemplo, cita)
# no cuenta: seria NUESTRO_DISTINTO y --quitar la borraria (hallazgo 5).
# tr -d '\r' para que una plantilla CRLF no falle la validacion (hallazgo 11).
zcode_agente_frontmatter() {
  awk 'BEGIN{n=0} /^---[[:space:]]*\r?$/{n++; if(n==2) exit; next} n==1{print}' "$1" | tr -d '\r'
}

zcode_agente_tiene_marca() {
  zcode_agente_frontmatter "$1" | grep -Eq "$ZCODE_AGENT_MARCA_RE"
}

zcode_agente_estado() {
  local dest="$1" fuente="$2"
  if [ ! -e "$dest" ]; then printf 'AUSENTE'; return 0; fi
  if [ ! -f "$dest" ] || [ ! -r "$dest" ]; then printf 'NO_OBSERVABLE'; return 0; fi
  if zcode_agente_tiene_marca "$dest"; then
    if cmp -s "$dest" "$fuente"; then printf 'NUESTRO_IDENTICO'; else printf 'NUESTRO_DISTINTO'; fi
  else
    printf 'DESCONOCIDO'
  fi
}

# Publica una plantilla con la misma disciplina atomica que DEST: temporal
# en el mismo dir, igualdad byte a byte, luego mv.
zcode_publicar_agente() {
  local fuente="$1" dest="$2" dir tmp
  dir="$(dirname "$dest")"
  mkdir -p "$dir" || return 1
  tmp="$(mktemp "$dir/.saikit-agent-XXXXXX")" || return 1
  if ! cat "$fuente" > "$tmp" || ! cmp -s "$tmp" "$fuente"; then
    rm -f "$tmp"; return 1
  fi
  if ! mv -f "$tmp" "$dest"; then
    rm -f "$tmp"; return 1
  fi
  return 0
}

zcode_archivar_agente() {
  local dest="$1" backup_dir sello n backup
  dir="$(dirname "$dest")"
  backup_dir="$dir/saikit-backups"
  mkdir -p "$backup_dir" || return 1
  sello="$(date +%Y%m%d-%H%M%S)"
  backup="$backup_dir/$(basename "$dest").nuestro.$sello.bak"
  n=2
  while [ -e "$backup" ]; do
    backup="$backup_dir/$(basename "$dest").nuestro.$sello-$n.bak"
    n=$((n + 1))
  done
  cp "$dest" "$backup" || return 1
  cmp -s "$backup" "$dest" || return 1
  # Task 7.5: expone DONDE quedo el backup para que el rollback de grok pueda
  # restaurar el estado pre-corrida de un agente reparado en esta corrida.
  zcode_agent_backup="$backup"
  return 0
}
zcode_agent_backup=''

# Valida plantillas y aplica los tres estados. Corre DESPUES de encontrar
# bash.exe y ANTES de appendear el user-config: si faltan las plantillas
# no se cablea. DESCONOCIDO avisa y sigue (el tipo ya existe en el host;
# no se aborta el registro — un implementer.md custom sigue siendo el tipo).
zcode_instalar_agentes() {
  local src dest_dir rol fuente dest estado trad
  src="$(zcode_agents_source)"
  dest_dir="$(zcode_agents_dir)"
  for rol in $ZCODE_AGENT_ROLES; do
    fuente="$src/$rol.md"
    if [ ! -f "$fuente" ] || [ ! -r "$fuente" ]; then
      decir "[summonaikit] instalador: falta la plantilla de agente $fuente"
      decir "              --host zcode no cablea un host sin los perfiles del kit."
      exit 2
    fi
    if ! zcode_agente_tiene_marca "$fuente"; then
      decir "[summonaikit] instalador: la plantilla $fuente no lleva saikit_owned."
      decir "              Instalarla dejaria un archivo que el proximo install no reconoce."
      exit 2
    fi
    if ! zcode_agente_frontmatter "$fuente" | grep -q "^name: ${rol}$"; then
      decir "[summonaikit] instalador: la plantilla $fuente no declara name: $rol."
      exit 2
    fi
  done
  mkdir -p "$dest_dir" || {
    decir "[summonaikit] instalador: no se pudo crear $dest_dir"; exit 5; }
  # grok r1 #1 / codex r1 #1 (cross-review del PR #66): clasificar TODOS los
  # destinos ANTES de publicar cualquiera — el mismo 12.9 #1 que claude/kimi
  # ya cierran en instalar_agentes_con_vendor. Antes, cada rol se clasificaba
  # y publicaba en la MISMA vuelta: un adversary.md NO_OBSERVABLE (ultimo rol)
  # salia exit 5 con implementer/verifier/reviewer YA escritos — instalacion a
  # medias que el exit != 0 ademas desmiente. Misma ventana TOCTOU declarada
  # que la version vendor (CLI local de un solo operador, sin concurrencia
  # esperada sobre el mismo dest_dir).
  local -a z_roles=() z_dests=() z_trads=() z_estados=()
  local i
  limpiar_trads_vendor
  for rol in $ZCODE_AGENT_ROLES; do
    fuente="$src/$rol.md"
    dest="$dest_dir/$rol.md"
    # Task 12.5: clasifica y publica contra la TRADUCIDA, no la cruda. Con
    # inyeccion de model:/effort: por host, comparar contra la cruda daria
    # NUESTRO_DISTINTO en cada corrida y reescribiria el perfil siempre.
    trad="$(mktemp "${TMPDIR:-/tmp}/.saikit-trad-XXXXXX")" || { limpiar_trads_vendor; exit 5; }
    TRADS_VENDOR_PENDIENTES+=("$trad")
    agente_traducido zcode "$fuente" > "$trad" || { limpiar_trads_vendor; exit 2; }
    estado="$(zcode_agente_estado "$dest" "$trad")"
    if [ "$estado" = 'NO_OBSERVABLE' ]; then
      limpiar_trads_vendor
      decir "[summonaikit] instalador: no se pudo clasificar $dest (no es un archivo legible)."
      exit 5
    fi
    z_roles+=("$rol"); z_dests+=("$dest"); z_trads+=("$trad"); z_estados+=("$estado")
  done
  for i in "${!z_roles[@]}"; do
    rol="${z_roles[$i]}"; dest="${z_dests[$i]}"; trad="${z_trads[$i]}"; estado="${z_estados[$i]}"
    case "$estado" in
      AUSENTE)
        zcode_publicar_agente "$trad" "$dest" || {
          limpiar_trads_vendor
          decir "[summonaikit] instalador: no se pudo escribir $dest"; exit 5; }
        decir "[summonaikit] AGENTE ZCODE INSTALADO: $rol"
        decir "              destino: $dest"
        ;;
      NUESTRO_IDENTICO)
        : ;;
      NUESTRO_DISTINTO)
        zcode_archivar_agente "$dest" || {
          limpiar_trads_vendor
          decir "[summonaikit] instalador: no se pudo respaldar $dest"; exit 5; }
        zcode_publicar_agente "$trad" "$dest" || {
          limpiar_trads_vendor
          decir "[summonaikit] instalador: no se pudo reparar $dest"; exit 5; }
        decir "[summonaikit] AGENTE ZCODE REPARADO: $rol"
        decir "              destino: $dest"
        ;;
      DESCONOCIDO)
        decir "[summonaikit] AGENTE ZCODE DESCONOCIDO: $rol — no se toco."
        decir "              destino: $dest"
        decir "              No lleva saikit_owned. Puede ser un cambio legitimo."
        ;;
    esac
  done
  limpiar_trads_vendor
}

# Solo borra los que llevan nuestra marca. Un implementer.md de otro se queda.
zcode_quitar_agentes() {
  local dest_dir rol dest
  dest_dir="$(zcode_agents_dir)"
  [ -d "$dest_dir" ] || return 0
  for rol in $ZCODE_AGENT_ROLES; do
    dest="$dest_dir/$rol.md"
    [ -f "$dest" ] || continue
    if zcode_agente_tiene_marca "$dest"; then
      zcode_archivar_agente "$dest" || {
        decir "[summonaikit] instalador: no se pudo respaldar $dest antes de quitarlo"; exit 5; }
      rm -f "$dest" || {
        decir "[summonaikit] instalador: no se pudo borrar $dest"; exit 5; }
      decir "[summonaikit] AGENTE ZCODE QUITADO: $rol"
    else
      decir "[summonaikit] AGENTE ZCODE DESCONOCIDO: $rol — no se quito."
      decir "              destino: $dest"
    fi
  done
}

# Idempotente: para cada fase, si ya existe la entrada canonica (type command +
# command exacto + timeout 15) la deja; si existe el id pero mal formada la
# reemplaza; si falta la anyade. r2.2: nivel entrada (el grupo ajeno sobrevive).
zcode_instalar() {
  command -v jq >/dev/null 2>&1 || {
    decir "[summonaikit] instalador: --host zcode requiere jq (no encontrado)."; exit 2; }
  local user_config bash_win canon uc_dir tmp_new bak
  user_config="$(zcode_user_config)"
  [ -f "$user_config" ] || {
    decir "[summonaikit] instalador: no existe el user-config de zcode ($user_config)."
    decir "              No lo creo de cero: el operador ya tiene uno."; exit 2; }
  if ! jq -e . "$user_config" >/dev/null 2>&1; then
    decir "[summonaikit] instalador: el user-config de zcode no es JSON valido ($user_config)."; exit 2; fi
  if ! jq -e '.hooks.enabled == true' "$user_config" >/dev/null 2>&1; then
    decir "[summonaikit] instalador: hooks.enabled no es true en $user_config."
    decir "              Los hooks de archivo no corren sin enabled:true. No se cablea nada."; exit 2; fi
  # Preflight (r1.3): DEST tiene que ser NUESTRO_IDENTICO + contener el codigo de
  # 5.3. No se cablea un dest que solo MENCIONA host: se exige la linea literal.
  case "$estado" in
    NUESTRO_IDENTICO) : ;;
    *)
      decir "[summonaikit] instalador: el DEST ($DEST) no es nuestro e identico a la fuente ($estado)."
      decir "              --host zcode NO instala el archivo: instalalo primero (sin --host)."
      decir "              No se cablea un dest que no se controla."; exit 2 ;;
  esac
  if ! grep -q 'PROJECT_DIR="$STATE_ROOT/$HOST/$PROJECT_KEY"' "$DEST" 2>/dev/null; then
    decir "[summonaikit] instalador: el DEST no tiene el aislamiento por host de 5.3."
    decir '              Falta: PROJECT_DIR="$STATE_ROOT/$HOST/$PROJECT_KEY" en '"$DEST"
    decir "              No se cablea un dest que solo menciona HOST."; exit 2; fi

  # bash.exe ANTES de escribir agentes (hallazgo 3): si no hay bash no
  # quedan perfiles huerfanos con el hook sin registrar.
  bash_win="$(zcode_bash_win)" || {
    decir "[summonaikit] instalador: no encontre un bash.exe de Windows para el command."; exit 2; }
  # 13.9 (adversary r1 EN VIVO): --dry-run tambien vale para --host zcode — el
  # dispatch nunca miraba DRY_RUN y una corrida de verificacion "sin escribir"
  # dejo un backup REAL del user-config (config.json.zcode.20260825-102205.bak).
  # Los preflights de arriba son read-only y se conservan (un dry-run que no
  # valida miente por omision). Aca se REPORTA lo que se haria — clasificacion
  # real por rol, como el dry-run de claude/kimi (12.9 #4) — y se sale sin
  # tocar agentes, config ni backups.
  if [ "$DRY_RUN" -eq 1 ]; then
    local dr_src dr_dest_dir dr_rol dr_fuente dr_dest dr_trad dr_estado dr_padre
    dr_src="$(zcode_agents_source)"
    dr_dest_dir="$(zcode_agents_dir)"
    # Greptile P1 del PR #67: sin esta sonda, un dest_dir inexistente cuyo
    # padre no es escribible clasificaba todo AUSENTE y el dry-run prometia
    # un plan que la corrida real (mkdir -p || exit 5) no puede ejecutar.
    # Sonda READ-ONLY: -d/-w, sin crear nada.
    if [ ! -d "$dr_dest_dir" ]; then
      dr_padre="$(dirname "$dr_dest_dir")"
      if [ ! -d "$dr_padre" ] || [ ! -w "$dr_padre" ]; then
        decir "[summonaikit] dry-run: el dir de agentes no existe y no se podria crear ($dr_dest_dir); la corrida real fallaria (exit 5)."
        exit 5
      fi
      decir "[summonaikit] dry-run: crearia el dir de agentes $dr_dest_dir."
    fi
    for dr_rol in $ZCODE_AGENT_ROLES; do
      dr_fuente="$dr_src/$dr_rol.md"
      dr_dest="$dr_dest_dir/$dr_rol.md"
      # Reviewer 13.9 #4: las MISMAS validaciones de fuente del camino real
      # (plantilla legible, marca, name:), con los mismos exit 2 — "un
      # dry-run que no valida miente por omision".
      if [ ! -f "$dr_fuente" ] || [ ! -r "$dr_fuente" ]; then
        decir "[summonaikit] instalador: falta la plantilla de agente $dr_fuente"; exit 2; fi
      zcode_agente_tiene_marca "$dr_fuente" || {
        decir "[summonaikit] instalador: la plantilla $dr_fuente no lleva saikit_owned."; exit 2; }
      zcode_agente_frontmatter "$dr_fuente" | grep -q "^name: ${dr_rol}$" || {
        decir "[summonaikit] instalador: la plantilla $dr_fuente no declara name: $dr_rol."; exit 2; }
      dr_trad="$(mktemp "${TMPDIR:-/tmp}/.saikit-trad-XXXXXX")" || {
        decir "[summonaikit] instalador: no se pudo crear el temporal del dry-run."; exit 5; }
      if ! agente_traducido zcode "$dr_fuente" > "$dr_trad"; then
        rm -f "$dr_trad"
        decir "[summonaikit] instalador: agente_traducido fallo en dry-run ($dr_rol)."; exit 2
      fi
      dr_estado="$(zcode_agente_estado "$dr_dest" "$dr_trad")"
      rm -f "$dr_trad"
      # NO_OBSERVABLE: mismo exit 5 del camino real — pintarlo como un estado
      # mas prometeria una corrida real que va a fallar.
      if [ "$dr_estado" = 'NO_OBSERVABLE' ]; then
        decir "[summonaikit] instalador: no se pudo clasificar $dr_dest (no es un archivo legible)."; exit 5; fi
      # Formato del patron 12.9 #4 (como claude/kimi), no el estado crudo.
      case "$dr_estado" in
        AUSENTE)          decir "[summonaikit] dry-run: AGENTE ZCODE AUSENTE: $dr_rol; se instalaria." ;;
        NUESTRO_IDENTICO) decir "[summonaikit] dry-run: AGENTE ZCODE ya al dia: $dr_rol." ;;
        NUESTRO_DISTINTO) decir "[summonaikit] dry-run: AGENTE ZCODE NUESTRO distinto: $dr_rol; se repararia (con backup)." ;;
        DESCONOCIDO)      decir "[summonaikit] dry-run: AGENTE ZCODE DESCONOCIDO: $dr_rol; no se tocaria." ;;
      esac
      decir "              destino: $dr_dest"
    done
    decir "[summonaikit] dry-run: registraria el harness en el user-config de zcode (4 fases, id 5.4); no se escribio nada."
    return 0
  fi

  # Task 5.6: perfiles ANTES del append al config. Si faltan las plantillas
  # no se cablea un host que no puede satisfacer implementer→verifier→reviewer.
  zcode_instalar_agentes
  canon="$(zcode_harness_cmd "$bash_win")"

  uc_dir="$(dirname "$user_config")"
  umask 077
  tmp_new="$(mktemp "$uc_dir/.saikit-zcode-XXXXXX")" || {
    decir "[summonaikit] instalador: no se pudo crear el temporal en $uc_dir."; exit 5; }
  bak="$uc_dir/saikit-backups/$(basename "$user_config").zcode.$(date +%Y%m%d-%H%M%S).bak"
  if ! mkdir -p "$(dirname "$bak")"; then
    rm -f "$tmp_new"; decir "[summonaikit] instalador: no se pudo crear el dir de backups."; exit 5; fi
  if ! cp "$user_config" "$bak"; then
    rm -f "$tmp_new"; decir "[summonaikit] instalador: no se pudo respaldar el user-config."; exit 5; fi

  # jq: quitar entradas 5.4 mal formadas (conservar canonicas + ajenas), luego
  # asegurar las 3 fases con un grupo propio cada una si falta la canonica.
  # Constructivo (. + {hooks:...}), no path-assign: el .hooks=X dentro de map
  # anidado en with_entries(.value|=) no se comporta con 2+ fases en jq 1.8.
  if ! jq --arg canon "$canon" '
    def canon_entrada: {type: "command", command: $canon, timeout: 15};
    def limpiar_grupos(arr):
      [ (arr // [])[] | select(. | type == "object")
        | . + {hooks: [ (.hooks // [])[] | select(
            ((.command // "") | test("saikit-harness-id 5[.]4") | not)
            or (. == canon_entrada) ) ]} ]
      | map(select((.hooks | length) > 0));
    def purgar:
      if (.hooks | type) == "object" and ((.hooks.events // {}) | type) == "object"
      then .hooks.events = (.hooks.events | with_entries(.value |= limpiar_grupos(.)))
      else . end;
    def fase_tiene_canon(fase):
      any( (.hooks.events[ fase ] // [])[];
           . as $g | any( ($g.hooks // [])[]; . == canon_entrada ) );
    def asegurar(fase; matcher):
      if fase_tiene_canon(fase) then .
      else .hooks.events[ fase ] = ( ((.hooks.events[ fase ]) // []) +
        [ (if matcher == "" then {} else {matcher: matcher} end) + {hooks: [canon_entrada]} ] )
      end;
    purgar
    | asegurar("UserPromptSubmit"; "")
    | asegurar("PostToolUse"; "Bash|Edit|Write|Read|apply_patch|Task|Agent")
    | asegurar("Stop"; "")
    | asegurar("SessionStart"; "")
  ' "$user_config" > "$tmp_new"; then
    rm -f "$tmp_new"
    decir "[summonaikit] instalador: jq fallo al appendear; el config original queda intacto."; exit 5; fi
  if ! jq -e . "$tmp_new" >/dev/null 2>&1; then
    rm -f "$tmp_new"
    decir "[summonaikit] instalador: el resultado de jq no es JSON valido; config intacto."; exit 5; fi
  if ! mv -f "$tmp_new" "$user_config"; then
    rm -f "$tmp_new"
    decir "[summonaikit] instalador: el mv final fallo; config intacto."; exit 5; fi
  decir "[summonaikit] REGISTRADO: harness en el user-config de zcode (4 fases, id 5.4)."
  decir "              config:  $user_config"
  decir "              backup:  $bak"
}

# --quitar-zcode: saca TODAS las entradas con saikit-harness-id 5.4 (canonicas o
# no) y los grupos que quedan vacios. Los grupos ajenos sobreviven (r2.2). NO
# corre el preflight de DEST/enabled (r3.3): la limpieza tiene que correr aunque
# el dest ya no exista o enabled este apagado.
zcode_quitar() {
  command -v jq >/dev/null 2>&1 || {
    decir "[summonaikit] instalador: --quitar-zcode requiere jq (no encontrado)."; exit 2; }
  local user_config uc_dir tmp_new bak
  user_config="$(zcode_user_config)"
  [ -f "$user_config" ] || {
    decir "[summonaikit] instalador: no existe el user-config de zcode ($user_config)."; exit 2; }
  if ! jq -e . "$user_config" >/dev/null 2>&1; then
    decir "[summonaikit] instalador: el user-config no es JSON valido; --quitar-zcode no procede."; exit 2; fi
  uc_dir="$(dirname "$user_config")"
  umask 077
  tmp_new="$(mktemp "$uc_dir/.saikit-zcode-XXXXXX")" || {
    decir "[summonaikit] instalador: no se pudo crear el temporal en $uc_dir."; exit 5; }
  bak="$uc_dir/saikit-backups/$(basename "$user_config").zcode.$(date +%Y%m%d-%H%M%S).bak"
  if ! mkdir -p "$(dirname "$bak")"; then
    rm -f "$tmp_new"; decir "[summonaikit] instalador: no se pudo crear el dir de backups."; exit 5; fi
  if ! cp "$user_config" "$bak"; then
    rm -f "$tmp_new"; decir "[summonaikit] instalador: no se pudo respaldar el user-config."; exit 5; fi
  if ! jq '
    def quitar_grupos(arr):
      [ (arr // [])[] | select(. | type == "object")
        | . + {hooks: [ (.hooks // [])[] | select(
            ((.command // "") | test("saikit-harness-id 5[.]4") | not) ) ]} ]
      | map(select((.hooks | length) > 0));
    if (.hooks | type) == "object" and ((.hooks.events // {}) | type) == "object"
    then .hooks.events = (.hooks.events | with_entries(.value |= quitar_grupos(.)))
    else . end
  ' "$user_config" > "$tmp_new"; then
    rm -f "$tmp_new"
    decir "[summonaikit] instalador: jq fallo al quitar; config intacto."; exit 5; fi
  if ! jq -e . "$tmp_new" >/dev/null 2>&1; then
    rm -f "$tmp_new"
    decir "[summonaikit] instalador: el resultado de jq no es JSON valido; config intacto."; exit 5; fi
  if ! mv -f "$tmp_new" "$user_config"; then
    rm -f "$tmp_new"
    decir "[summonaikit] instalador: el mv final fallo; config intacto."; exit 5; fi
  decir "[summonaikit] QUITADO: entradas 5.4 del user-config de zcode."
  decir "              config:  $user_config"
  decir "              backup:  $bak"
  # Task 5.6: despues del config, para que un fallo al borrar agentes no
  # deje el harness registrado sin poder deshacer el cableado.
  zcode_quitar_agentes
}

# ---------------------------------------------------------------- Task 7.5: grok
# D1/7.5: --host grok publica TRES cosas, en este orden y con PREFLIGHT antes
# de la primera escritura:
#   1. el hook (~/.grok/hooks/summonaikit-harness.sh) por el flujo COMUN de
#      tres estados y escritura atomica que sigue mas abajo;
#   2. el JSON de registro (<dir del hook>/summonaikit.json), archivo ENTERO
#      propio de este repo: ausente o nuestro => publicar el canonico;
#      desconocido => PLANTARSE sin tocar nada (preflight, cero cambios);
#   3. los perfiles en ~/.grok/agents con el frontmatter TRADUCIDO.
# Un agente desconocido NO aborta (D7): se instala el resto y se reporta.
# Si una publicacion posterior falla, se hace rollback con los backups de esta
# corrida (design D1).
GROK_AGENT_ROLES='implementer verifier reviewer adversary'
GROK_BASH_WIN=''
GROK_JSON_ESTADO=''
GROK_JSON_BACKUP=''
GROK_JSON_PUBLICADO=0
GROK_HOOK_PUBLICADO=0
# Lo publicado en ESTA corrida, para el rollback (r2/CodeRabbit): un agente
# que ya se publico cuando otro falla tambien vuelve a su estado pre-corrida.
GROK_AGENT_DESTS=()
GROK_AGENT_BACKUPS=()

grok_agents_dir() {
  printf '%s' "${SAIKIT_GROK_AGENTS_DIR:-${HOME:-}/.grok/agents}"
}

grok_json_path() { printf '%s/summonaikit.json' "$(dirname "$DEST")"; }

# bash.exe con override propio (misma semantica que SAIKIT_ZCODE_BASH_WIN: si
# la variable ESTA seteada no se busca en disco; vacia o inexistente => fallo).
grok_bash_win() {
  if [ "${SAIKIT_GROK_BASH_WIN+set}" = "set" ]; then
    if [ -n "$SAIKIT_GROK_BASH_WIN" ] && [ -f "$SAIKIT_GROK_BASH_WIN" ]; then
      printf '%s' "$SAIKIT_GROK_BASH_WIN"; return 0
    fi
    return 1
  fi
  zcode_bash_win
}

grok_json_esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

# 7.1 midio que el shell de hooks de Grok en Windows es powershell.exe: la
# forma zcode ('"exe" "script"') muere con exit 1 porque un string quoted es
# una expresion, no una invocacion. La forma que invoca sin depender del PATH
# es el call operator: & "<bash.exe>" "<hook>". bash.exe viene en forma
# forward-slashes de zcode_bash_win y el hook va con su ruta tal cual (la misma
# forma verificada en los 37 payloads de la 7.1 via capture-payloads.sh).
grok_hook_cmd() {  # $1=bash_win
  printf '& "%s" "%s"' "$1" "$DEST"
}

# El JSON canonico completo (design D1): entero y a proposito repetitivo, sin
# abreviaturas — es la plantilla que se publica tal cual. saikit_owned
# top-level es tolerado por el loader (medido 7.1). PostToolUseFailure se
# registra aunque 7.1 midio que no dispara (D5): cuesta cero y si un release
# futuro lo emite, la evidencia aparece. Matcher SOLO en PTU/PTUF; sin matcher
# en SubagentStart (vacuo = todos los subagentes) ni en UPS/Stop (Grok lo
# ignora con warning). Stop timeout 600, el resto 30.
grok_json_canonico() {  # $1=bash_win → stdout
  local cmd
  cmd="$(grok_json_esc "$(grok_hook_cmd "$1")")"
  cat <<JSON
{
  "saikit_owned": "summonaikit-claude",
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$cmd",
            "timeout": 30,
            "env": { "SUMMONAIKIT_HOOK_TARGET": "grok" }
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Bash|Edit|Write|apply_patch|Task|Agent|spawn_subagent|run_terminal_command|search_replace|write",
        "hooks": [
          {
            "type": "command",
            "command": "$cmd",
            "timeout": 30,
            "env": { "SUMMONAIKIT_HOOK_TARGET": "grok" }
          }
        ]
      }
    ],
    "PostToolUseFailure": [
      {
        "matcher": "Bash|run_terminal_command",
        "hooks": [
          {
            "type": "command",
            "command": "$cmd",
            "timeout": 30,
            "env": { "SUMMONAIKIT_HOOK_TARGET": "grok" }
          }
        ]
      }
    ],
    "SubagentStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$cmd",
            "timeout": 30,
            "env": { "SUMMONAIKIT_HOOK_TARGET": "grok" }
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$cmd",
            "timeout": 600,
            "env": { "SUMMONAIKIT_HOOK_TARGET": "grok" }
          }
        ]
      }
    ]
  }
}
JSON
}

# Identidad del JSON (design D1): el archivo se llama summonaikit.json Y lleva
# saikit_owned:"summonaikit-claude" en el objeto raiz. jq decide exacto: un
# saikit_owned anidado en un archivo ajeno NO cuenta como nuestro (la direccion
# peligrosa del grep seria pisar un registro de otro). Un archivo que existe y
# no parsea se miro y no es nuestro: DESCONOCIDO, no unknown.
grok_json_estado() {  # $1=json  $2=canonico
  if [ ! -e "$1" ]; then printf 'AUSENTE'; return 0; fi
  if [ ! -f "$1" ] || [ ! -r "$1" ]; then printf 'NO_OBSERVABLE'; return 0; fi
  if ! jq -e '(.saikit_owned? // "") == "summonaikit-claude"' "$1" >/dev/null 2>&1; then
    printf 'DESCONOCIDO'; return 0
  fi
  if [ "$(cat "$1")" = "$2" ]; then printf 'NUESTRO_IDENTICO'; else printf 'NUESTRO_DISTINTO'; fi
}

# Traduccion de frontmatter por host (D7 + 7.1, generalizada en la Task 12.5).
# Dos operaciones, en este orden:
#
#   1. OMITIR claves que el host no acepta. Medido en la 7.1: el loader de
#      Grok espera `skills:` como secuencia y la fuente lo declara como string
#      (error medido: `skills: invalid type: string ..., expected a sequence`).
#   2. INYECTAR model:/effort: del router (Task 12.4, tools/model-routing.sh).
#      Una fila de host sin medir no inyecta nada, y el agente hereda del
#      padre — que es como zcode se comporta desde la 5.6.
#
# Solo el PRIMER bloque frontmatter: una linea `skills:` o `model:` en el body
# es contenido, no configuracion. La fuente del repo queda intacta: una sola
# fuente, sin dos sabores.
agente_traducido() {  # $1=host  $2=fuente → stdout
  local host="$1" fuente="$2" rol inyectar router effort_key desechar
  rol="$(zcode_agente_frontmatter "$fuente" | sed -n 's/^name: //p' | head -1)"
  if [ -z "$rol" ]; then
    # `decir` imprime por STDOUT (install-hook.sh:176). Los llamadores redirigen
    # el stdout de esta funcion a un temporal que borran ante el error, asi que
    # un `decir` aca desaparece y el operador ve un exit 2 sin razon. Va a
    # stderr explicito.
    printf '[summonaikit] instalador: %s no declara name: en el frontmatter\n' "$fuente" >&2
    return 1
  fi
  # Costura de test, mismo mecanismo que SAIKIT_INSTALL_TOOL: la suite apunta el
  # router a un stub con las filas llenas y asi prueba la INYECCION aunque las
  # mediciones 12.1/12.2/12.3 hayan dejado alguna fila vacia.
  router="${SAIKIT_MODEL_ROUTING_TOOL:-$repo/tools/model-routing.sh}"
  # `bash "$router"`, NO "$router" a secas: los 7 scripts de tools/ estan
  # versionados 100644, sin bit de ejecucion (git ls-files -s tools/*.sh), asi
  # que la invocacion directa muere con "Permission denied" en Linux -- que es
  # donde corre el CI.
  inyectar="$(bash "$router" --host "$host" --role "$rol" --format frontmatter)" || return 1
  # El NOMBRE de la clave del effort no es 'effort:' para todos los hosts
  # (Task 12.1: zcode lee thoughtLevel:, nunca effort: -- escribir effort:
  # seria texto muerto). El router ya emite --format frontmatter con la clave
  # correcta (arriba); esto es SOLO para saber que linea preexistente de la
  # FUENTE hay que descartar mas abajo. Si el router falla aca (no deberia,
  # ya se valido host/rol arriba), 'effort' es un fallback seguro: como mucho
  # deja de descartar una linea que hoy ninguna fuente tiene.
  effort_key="$(bash "$router" --host "$host" --role "$rol" --field effort-key 2>/dev/null)" \
    || effort_key='effort'
  [ -z "$effort_key" ] && effort_key='effort'

  # `^$` NO sirve como "regex que no matchea nada": matchea las lineas vacias y
  # se las comeria del frontmatter, y ahi el instalado dejaria de ser la fuente
  # traducida. `a^` no matchea nunca.
  local omitir='a^'
  [ "$host" = 'grok' ] && omitir='^skills:'

  # Claves nuestras que ya vinieran en la fuente se descartan: manda el
  # router. `model`/`effort` siempre; el nombre de clave especifico del host
  # (thoughtLevel en zcode) se suma solo si es distinto de 'effort', para no
  # armar una alternancia vacia en el regex.
  desechar='model|effort'
  [ "$effort_key" != 'effort' ] && desechar="$desechar|$effort_key"

  awk -v omitir="$omitir" -v inyectar="$inyectar" -v desechar="$desechar" '
    /^---[[:space:]]*\r?$/ {
      n++
      # El cierre del primer bloque: inyectar JUSTO ANTES.
      if (n == 2 && inyectar != "") print inyectar
      print; next
    }
    n == 1 && $0 ~ omitir { next }
    n == 1 && $0 ~ ("^(" desechar "):") { next }
    { print }
  ' "$fuente"
}

grok_agente_estado() {  # $1=dest  $2=contenido traducido
  if [ ! -e "$1" ]; then printf 'AUSENTE'; return 0; fi
  if [ ! -f "$1" ] || [ ! -r "$1" ]; then printf 'NO_OBSERVABLE'; return 0; fi
  if ! zcode_agente_tiene_marca "$1"; then printf 'DESCONOCIDO'; return 0; fi
  if [ "$(cat "$1")" = "$2" ]; then printf 'NUESTRO_IDENTICO'; else printf 'NUESTRO_DISTINTO'; fi
}

# Misma disciplina atomica que DEST: temporal en el mismo dir, igualdad byte a
# byte contra lo que se quizo escribir, recien entonces mv.
grok_escribir_agente() {  # $1=contenido  $2=dest
  local dir tmp
  dir="$(dirname "$2")"
  mkdir -p "$dir" || return 1
  tmp="$(mktemp "$dir/.saikit-agent-XXXXXX")" || return 1
  if ! printf '%s\n' "$1" > "$tmp" || ! printf '%s\n' "$1" | cmp -s - "$tmp"; then
    rm -f "$tmp"; return 1
  fi
  mv -f "$tmp" "$2" || { rm -f "$tmp"; return 1; }
  return 0
}

grok_archivar_json() {  # $1=json (mismo contrato de nombre que el hook)
  local dir backup_dir sello n backup
  dir="$(dirname "$1")"
  backup_dir="$dir/saikit-backups"
  mkdir -p "$backup_dir" || return 1
  sello="$(date +%Y%m%d-%H%M%S)"
  backup="$backup_dir/$(basename "$1").nuestro.$sello.bak"
  n=2
  while [ -e "$backup" ]; do
    backup="$backup_dir/$(basename "$1").nuestro.$sello-$n.bak"
    n=$((n + 1))
  done
  cp "$1" "$backup" || return 1
  cmp -s "$backup" "$1" || return 1
  GROK_JSON_BACKUP="$backup"
  return 0
}

# PREFLIGHT (D1): clasifica TODO sin escribir. Se planta ANTES de tocar
# cualquier destino si el JSON es desconocido/no observable, si falta jq o
# bash.exe, o si una plantilla no valida. Un agente DESCONOCIDO no planta
# (D7); NO_OBSERVABLE si: no se escribe alrededor de lo que no se pudo mirar.
grok_preflight() {
  local json canon estado_json rol fuente src dest_agente trad_probe
  command -v jq >/dev/null 2>&1 || {
    decir "[summonaikit] instalador: --host grok requiere jq (no encontrado)."; exit 2; }
  GROK_BASH_WIN="$(grok_bash_win)" || {
    decir "[summonaikit] instalador: no encontre un bash.exe de Windows para el command del JSON de grok."
    decir "              Sin el no existe la forma PowerShell '& \"bash.exe\" \"hook\"' que 7.1 midio."; exit 2; }
  json="$(grok_json_path)"
  canon="$(grok_json_canonico "$GROK_BASH_WIN")"
  estado_json="$(grok_json_estado "$json" "$canon")"
  case "$estado_json" in
    DESCONOCIDO)
      decir "[summonaikit] JSON DE GROK DESCONOCIDO — no se toco nada (el hook incluido)."
      decir "              json: $json"
      decir "              Existe y no lleva saikit_owned: summonaikit-claude en el objeto raiz."
      decir "              Puede ser un registro de otro: revisarlo antes de instalar."
      exit 3
      ;;
    NO_OBSERVABLE)
      decir "[summonaikit] unknown — no se pudo clasificar el JSON de grok; no se escribio nada."
      decir "              json: $json"
      exit 4
      ;;
  esac
  GROK_JSON_ESTADO="$estado_json"
  src="$repo/agents"
  for rol in $GROK_AGENT_ROLES; do
    fuente="$src/$rol.md"
    if [ ! -f "$fuente" ] || [ ! -r "$fuente" ]; then
      decir "[summonaikit] instalador: falta la plantilla de agente $fuente"
      decir "              --host grok no cablea un host sin los perfiles del kit."
      exit 2
    fi
    if ! zcode_agente_tiene_marca "$fuente"; then
      decir "[summonaikit] instalador: la plantilla $fuente no lleva saikit_owned."
      decir "              Instalarla dejaria un archivo que el proximo install no reconoce."
      exit 2
    fi
    if ! zcode_agente_frontmatter "$fuente" | grep -q "^name: ${rol}$"; then
      decir "[summonaikit] instalador: la plantilla $fuente no declara name: $rol."
      exit 2
    fi
    dest_agente="$(grok_agents_dir)/$rol.md"
    # Task 12.9 (hallazgo #5, grok): el rc de agente_traducido NO se puede
    # ignorar -- si el router falla (p. ej. tools/model-routing.sh roto),
    # `agente_traducido` imprimia stdout vacio y esta linea lo tomaba como
    # traduccion valida. Con un perfil grok existente eso clasificaba
    # NUESTRO_DISTINTO contra "casi nada" y grok_publicar_agentes terminaba
    # archivando el perfil real para pisarlo con contenido vacio.
    trad_probe="$(agente_traducido grok "$fuente")" || {
      decir "[summonaikit] instalador: fallo agente_traducido para grok/$rol; no se toco nada."
      exit 2
    }
    estado_json="$(grok_agente_estado "$dest_agente" "$trad_probe")"
    if [ "$estado_json" = 'NO_OBSERVABLE' ]; then
      decir "[summonaikit] unknown — no se pudo clasificar el agente $dest_agente; no se escribio nada."
      exit 4
    fi
  done
}

grok_publicar_json() {
  local json dir canon tmp
  [ "$GROK_JSON_ESTADO" = 'NUESTRO_IDENTICO' ] && return 0
  json="$(grok_json_path)"
  dir="$(dirname "$json")"
  # Sin umask global (r3/Greptile minor): mktemp ya crea el temporal 0600 y el
  # mv preserva el modo, asi que el JSON publicado no queda legible por otros
  # sin cambiar el umask del resto de la corrida (los agentes de abajo).
  canon="$(grok_json_canonico "$GROK_BASH_WIN")"
  tmp="$(mktemp "$dir/.saikit-grok-XXXXXX")" || return 1
  if ! printf '%s\n' "$canon" > "$tmp"; then rm -f "$tmp"; return 1; fi
  if ! jq -e . "$tmp" >/dev/null 2>&1; then
    rm -f "$tmp"
    decir "[summonaikit] instalador: el JSON canonico de grok no parsea; no se publico nada."
    return 1
  fi
  if ! printf '%s\n' "$canon" | cmp -s - "$tmp"; then
    rm -f "$tmp"; return 1
  fi
  if [ "$GROK_JSON_ESTADO" = 'NUESTRO_DISTINTO' ]; then
    grok_archivar_json "$json" || { rm -f "$tmp"; return 1; }
  fi
  if ! mv -f "$tmp" "$json"; then rm -f "$tmp"; return 1; fi
  GROK_JSON_PUBLICADO=1
  decir "[summonaikit] REGISTRO GROK PUBLICADO: $json"
  decir "              command: & \"<bash.exe>\" \"<hook>\" (PowerShell; shell medido en 7.1)"
  [ -n "$GROK_JSON_BACKUP" ] && decir "              backup:  $GROK_JSON_BACKUP"
  return 0
}

grok_publicar_agentes() {
  local src dir rol fuente trad dest estado bak
  src="$repo/agents"
  dir="$(grok_agents_dir)"
  for rol in $GROK_AGENT_ROLES; do
    fuente="$src/$rol.md"
    # Task 12.9 (hallazgo #5, grok): mismo bug que en grok_preflight, ahora en
    # el punto que SI escribe. Sin el `|| return 1`, un router roto entre el
    # preflight y esta publicacion (o si el preflight se saltea) pisaria un
    # perfil real con casi-nada; con el `|| return 1` el llamador
    # (grok_publicar) hace el ROLLBACK completo de esta corrida, como ya hace
    # zcode (linea ~383) y el bucle vendor unificado.
    #
    # Guard DEFENSIVO, declarado (revision interna del PR #62): grok_preflight
    # ya llama a agente_traducido para el MISMO rol/fuente antes de que el
    # flujo normal llegue aca, asi que un router que falla sale por ahi
    # primero (exit 2) y este `|| return 1` no es ejercitable con un caso de
    # test que pase por el camino normal (--host grok completo). Queda igual
    # a proposito -- defensa en profundidad si algun llamador futuro invoca
    # grok_publicar_agentes sin pasar antes por grok_preflight -- y es la
    # razon por la que el caso "12.9 #5" de la suite prueba el sintoma
    # observable (el perfil no se pisa, exit != 0), no esta linea puntual.
    trad="$(agente_traducido grok "$fuente")" || return 1
    dest="$dir/$rol.md"
    estado="$(grok_agente_estado "$dest" "$trad")"
    case "$estado" in
      AUSENTE)
        grok_escribir_agente "$trad" "$dest" || return 1
        # Se registra DESPUES de escribir: si la escritura fallo, el archivo
        # quedo intacto y no hay nada que revertir para este rol.
        GROK_AGENT_DESTS+=("$dest")
        GROK_AGENT_BACKUPS+=('')
        decir "[summonaikit] AGENTE GROK INSTALADO: $rol"
        decir "              destino: $dest (frontmatter traducido: sin la clave skills:)"
        ;;
      NUESTRO_IDENTICO)
        : ;;
      NUESTRO_DISTINTO)
        zcode_archivar_agente "$dest" || return 1
        bak="$zcode_agent_backup"
        grok_escribir_agente "$trad" "$dest" || return 1
        GROK_AGENT_DESTS+=("$dest")
        GROK_AGENT_BACKUPS+=("$bak")
        decir "[summonaikit] AGENTE GROK REPARADO: $rol"
        decir "              destino: $dest"
        ;;
      DESCONOCIDO)
        decir "[summonaikit] AGENTE GROK DESCONOCIDO: $rol — no se toco."
        decir "              destino: $dest"
        decir "              No lleva saikit_owned. Puede ser un cambio legitimo (D7)."
        ;;
    esac
  done
  return 0
}

# Vuelve atras lo publicado en ESTA corrida (design D1): cada destino vuelve al
# estado pre-corrida — backup si lo habia, eliminacion si la corrida lo creo.
# Incluye los AGENTES ya publicados cuando uno posterior falla (r2/CodeRabbit:
# dejarlos seria un estado a medio cablear que ningun flujo vuelve a mirar).
# r3/Greptile P1: un cp/rm que FALLE no se disfraza de exito — el mensaje final
# solo afirma "queda como estaba" si TODO volvio; si no, lo dice y senala los
# backups, que siguen en disco para restaurar a mano.
grok_rollback() {
  decir "[summonaikit] instalador: fallo publicar $1 — ROLLBACK de lo publicado en esta corrida."
  local i dest bak fallo=0
  i=0
  while [ "$i" -lt "${#GROK_AGENT_DESTS[@]}" ]; do
    dest="${GROK_AGENT_DESTS[$i]}"
    bak="${GROK_AGENT_BACKUPS[$i]}"
    if [ -n "$bak" ] && [ -f "$bak" ]; then
      if cp "$bak" "$dest" 2>/dev/null; then
        decir "              agente restaurado desde $bak"
      else
        fallo=1
        decir "              ROLLBACK INCOMPLETO: no se pudo restaurar $dest desde $bak"
      fi
    else
      if rm -f "$dest" 2>/dev/null; then
        decir "              agente retirado (esta corrida lo habia creado): $dest"
      else
        fallo=1
        decir "              ROLLBACK INCOMPLETO: no se pudo retirar $dest"
      fi
    fi
    i=$((i + 1))
  done
  if [ "$GROK_JSON_PUBLICADO" -eq 1 ]; then
    if [ -n "$GROK_JSON_BACKUP" ] && [ -f "$GROK_JSON_BACKUP" ]; then
      if cp "$GROK_JSON_BACKUP" "$(grok_json_path)" 2>/dev/null; then
        decir "              JSON restaurado desde $GROK_JSON_BACKUP"
      else
        fallo=1
        decir "              ROLLBACK INCOMPLETO: no se pudo restaurar $(grok_json_path)"
      fi
    else
      if rm -f "$(grok_json_path)" 2>/dev/null; then
        decir "              JSON retirado (esta corrida lo habia creado)"
      else
        fallo=1
        decir "              ROLLBACK INCOMPLETO: no se pudo retirar $(grok_json_path)"
      fi
    fi
  fi
  if [ "$GROK_HOOK_PUBLICADO" -eq 1 ]; then
    if [ -n "${backup:-}" ] && [ -f "$backup" ]; then
      if cp "$backup" "$DEST" 2>/dev/null; then
        decir "              hook restaurado desde $backup"
      else
        fallo=1
        decir "              ROLLBACK INCOMPLETO: no se pudo restaurar $DEST desde $backup"
      fi
    else
      if rm -f "$DEST" 2>/dev/null; then
        decir "              hook retirado (esta corrida lo habia creado)"
      else
        fallo=1
        decir "              ROLLBACK INCOMPLETO: no se pudo retirar $DEST"
      fi
    fi
  fi
  if [ "$fallo" -eq 0 ]; then
    decir "              El perfil queda como estaba antes de la corrida."
  else
    decir "              ROLLBACK INCOMPLETO: algo quedo a medias — los backups de esta corrida"
    decir "              siguen en <dir>/saikit-backups para restaurar a mano."
  fi
}

grok_publicar() {
  grok_publicar_json || { grok_rollback "el JSON de registro"; exit 5; }
  grok_publicar_agentes || { grok_rollback "los agentes de grok"; exit 5; }
}

# --quitar-grok (design D1): saca JSON nuestro + hook nuestro + agentes con
# marca, cada uno con backup. Lo ajeno (el verifier.md del operador, un JSON de
# otro) sobrevive y se reporta. Sin preflight: la limpieza tiene que correr
# aunque el resto ya no este.
grok_quitar() {
  local json rol dest dir
  command -v jq >/dev/null 2>&1 || {
    decir "[summonaikit] instalador: --quitar-grok requiere jq (no encontrado)."; exit 2; }
  json="$(grok_json_path)"
  if [ -e "$json" ]; then
    if [ ! -f "$json" ] || [ ! -r "$json" ]; then
      decir "[summonaikit] unknown — no se pudo clasificar el JSON ($json); no se quito."
    elif jq -e '(.saikit_owned? // "") == "summonaikit-claude"' "$json" >/dev/null 2>&1; then
      grok_archivar_json "$json" || {
        decir "[summonaikit] instalador: no se pudo respaldar $json"; exit 5; }
      rm -f "$json" || {
        decir "[summonaikit] instalador: no se pudo borrar $json"; exit 5; }
      decir "[summonaikit] JSON DE GROK QUITADO: $json"
      decir "              backup:  $GROK_JSON_BACKUP"
    else
      decir "[summonaikit] JSON DE GROK DESCONOCIDO — no se quito ($json)."
    fi
  else
    decir "[summonaikit] JSON DE GROK: no existe ($json)."
  fi
  if [ -e "$DEST" ]; then
    if [ ! -f "$DEST" ] || [ ! -r "$DEST" ]; then
      decir "[summonaikit] unknown — no se pudo clasificar el hook ($DEST); no se quito."
    elif sed -n "${MARCADOR_LINEA}p" "$DEST" | grep -Eq "$MARCADOR_RE"; then
      archivar_destino "nuestro" || exit 5
      rm -f "$DEST" || {
        decir "[summonaikit] instalador: no se pudo borrar $DEST"; exit 5; }
      decir "[summonaikit] HOOK DE GROK QUITADO: $DEST"
      decir "              backup:  $backup"
    else
      decir "[summonaikit] HOOK DE GROK DESCONOCIDO — no se quito ($DEST)."
    fi
  else
    decir "[summonaikit] HOOK DE GROK: no existe ($DEST)."
  fi
  dir="$(grok_agents_dir)"
  [ -d "$dir" ] || return 0
  for rol in $GROK_AGENT_ROLES; do
    dest="$dir/$rol.md"
    [ -f "$dest" ] || continue
    if zcode_agente_tiene_marca "$dest"; then
      zcode_archivar_agente "$dest" || {
        decir "[summonaikit] instalador: no se pudo respaldar $dest antes de quitarlo"; exit 5; }
      rm -f "$dest" || {
        decir "[summonaikit] instalador: no se pudo borrar $dest"; exit 5; }
      decir "[summonaikit] AGENTE GROK QUITADO: $rol"
    else
      decir "[summonaikit] AGENTE GROK DESCONOCIDO: $rol — no se quito."
      decir "              destino: $dest"
    fi
  done
  return 0
}

# ----------------------------------------------------------------- Phase 15: dsh
# dsh (DeepSeek Harness) no tiene hooks de shell: su superficie de extension es un
# plugin cordis compuesto en el arbol del profile. `--host dsh` publica CUATRO
# cosas (D5):
#   (1) el hook bash en <dsh-home>/hooks/ (DEST, por el flujo normal de abajo);
#   (2) el paquete adaptador <dsh-home>/plugins/summonaikit-dsh-gate/ (los 4
#       archivos de hosts/dsh/);
#   (3) la entrada del plugin SUMMONAIKIT en <dsh-home>/cordis.patch.yml, entre
#       marcas propias (id-targeted: `- insert:` sobre el id del plugin);
#   (4) las 4 personas de rol como INSTANCIAS dsh-tool-subagent en la MISMA
#       entrada del patch (diseno D4, medido en 15.4: dsh NO tiene archivos de
#       persona, la persona es `config.persona` inline aplicada al hijo; el tool
#       subagent solo toma {description,prompt}, asi que cada rol exige un tool
#       distinto `subagent_<rol>` con su propia persona).
# Overrides de test: SAIKIT_DSH_HOME (raiz dsh, como SAIKIT_GROK_HOOKS_DIR),
# SAIKIT_DSH_BASH_WIN (bash.exe), SAIKIT_DSH_AGENTS_SOURCE (dir de agentes).
DSH_AGENT_ROLES='implementer verifier reviewer adversary'

dsh_home() { printf '%s' "${SAIKIT_DSH_HOME:-${HOME:-}/.dsh}"; }
# dsh resuelve los plugins custom por NOMBRE de paquete via el flat module
# fallback `$DSH_HOME/profiles/node_modules/<pkg>` (Node-walk desde cualquier
# profile). El plugin se instala como DIR REAL ahi (no symlink: en MSYS/Windows
# `ln -s` no crea symlinks reales solos). El `name:` del patch lo referencia.
dsh_plugin_dir() { printf '%s/profiles/node_modules/@summonaikit/dsh-gate' "$(dsh_home)"; }
dsh_patch() { printf '%s/cordis.patch.yml' "$(dsh_home)"; }
dsh_agents_source() { printf '%s' "${SAIKIT_DSH_AGENTS_SOURCE:-$repo/agents}"; }
# Estado de lo publicado en ESTA corrida (rollback del install dsh): archivos de
# plugin escritos (y su backup si eran NUESTRO_DISTINTO) + si el patch se toco.
# Globales a proposito (no `declare` local): dsh_rollback_publicar los lee.
DSH_PLUGIN_DESTS=()
DSH_PLUGIN_BACKUPS=()
DSH_PATCH_ESCRITO=0
dsh_bash_win() {
  if [ "${SAIKIT_DSH_BASH_WIN+set}" = "set" ]; then
    if [ -n "$SAIKIT_DSH_BASH_WIN" ] && [ -f "$SAIKIT_DSH_BASH_WIN" ]; then printf '%s' "$SAIKIT_DSH_BASH_WIN"; return 0; fi
    return 1
  fi
  # Sin override propio: reusa el mismo cilindro que zcode/grok (Git for Windows).
  zcode_bash_win
}

# Cuerpo del agente (sin el frontmatter ---): la persona de dsh es ese texto.
# Se imprime todo lo que sigue a la SEGUNDA linea '---' (el cierre del
# frontmatter), incluidas las '---' posteriores del cuerpo (separadores markdown,
# L2/codex r1 PR #88). Si el fuente no tiene cierre (una sola '---'), se falla
# con 1 y NO se devuelve un cuerpo vacio en silencio (L1).
dsh_persona_body() {  # $1=rol
  local rol="$1" fuente n_cierre
  fuente="$(dsh_agents_source)/$rol.md"
  if [ ! -r "$fuente" ]; then return 1; fi
  n_cierre="$(awk '/^---[[:space:]]*\r?$/{c++} END{print c+0}' "$fuente")"
  [ "$n_cierre" -ge 2 ] || { printf '[summonaikit] instalador: %s no tiene cierre de frontmatter (---)\n' "$fuente" >&2; return 1; }
  awk 'BEGIN{n=0; in_body=0}
    /^---[[:space:]]*\r?$/ {
      if (in_body) { print; next }   # '---' del CUERPO (separador markdown) se conserva
      n++
      if (n == 2) { in_body=1; next }
      next
    }
    in_body { print }
  ' "$fuente"
}

# Convierte una ruta a forma Windows con barra normal (C:/...). En MSYS/Git
# Bash `$HOME` es una ruta POSIX (/c/Users/...), y el `name:`/`hook:` del patch
# los lee Node (dsh), que necesita `C:/Users/...`. `cygpath -m` (barra adelante)
# es la forma canonica y consistente (tanto para el plugin dir como para el
# hook), y Node la acepta. Si no hay cygpath o la ruta ya es Windows adelante,
# se deja como llega (el test con SAIKIT_DSH_HOME Windows no se rompe).
dsh_win_path() {  # $1=ruta
  local ruta="$1"
  if command -v cygpath >/dev/null 2>&1; then
    case "$ruta" in
      [A-Za-z]:/*) printf '%s' "$ruta" ;;  # ya es Windows con barra adelante
      [A-Za-z]:\\*) printf '%s' "$(printf '%s' "$ruta" | sed 's|\\|/|g')" ;;  # Windows con backslash -> adelante
      *) printf '%s' "$(cygpath -m "$ruta" 2>/dev/null || printf '%s' "$ruta")" ;;
    esac
  else
    printf '%s' "$ruta"
  fi
}

# El bloque de Marcas (id-targeted insert) que el patch del profile lleva entre
# `# >>> summonaikit-gate START` / `# <<< summonaikit-gate END`. Salida por
# stdout. Si no se pudo leer un cuerpo de persona => return 1 (rollback).
#
# Forma id-targeted: `- insert:` en el id `summonaikit-gate` NO alcanza (el
# plugin gate y los 4 tool-subagent viven en el root del arbol, no en un grupo
# `summonaikit-gate`). La forma que dsh-app-boot aplica es un `- insert:` con la
# LISTA de entradas, insertado en el ROOT (id del target = ''). Por eso el bloque
# es una lista plana de 5 entradas (gate + 4 roles) bajo UN `- insert:`.
dsh_patch_nuestro_bloque() {
  local rol cuerpo win_hook
  win_hook="$(dsh_win_path "$DEST")"
  printf '%s\n' "# >>> summonaikit-gate START -- managed by summonaikit-claude tools/install-hook.sh"
  printf '%s\n' "- insert:"
  printf '%s\n' "    - id: summonaikit-gate"
  printf '%s\n' "      name: '@summonaikit/dsh-gate'"
  printf '%s\n' "      config:"
  printf '%s\n' "        hook: '$win_hook'"
  printf '%s\n' "        bash: '$(dsh_bash_win)'"
  for rol in $DSH_AGENT_ROLES; do
    cuerpo="$(dsh_persona_body "$rol")" || {
      printf '[summonaikit] instalador: no pude leer la persona de %s (falla el bloque dsh)\n' "$rol" >&2
      return 1
    }
    printf '%s\n' "    - id: subagent_$rol"
    printf '%s\n' "      name: '@deepseek-ai/dsh-tool-subagent'"
    printf '%s\n' "      config:"
    printf '%s\n' "        provider: spawn"
    printf '%s\n' "        toolName: subagent_$rol"
    printf '%s\n' "        backgroundMode: continuable"
    printf '%s\n' "        persona: |-"
    printf '%s' "$cuerpo" | sed 's/^/          /'
    printf '\n'
  done
  printf '%s\n' "# <<< summonaikit-gate END"
}

# Estado del patch del profile: AUSENTE / NUESTRO_IDENTICO / NUESTRO_DISTINTO /
# DESCONOCIDO / NO_OBSERVABLE. El bloque nuestro es id-targeted en el root, asi
# que comparamos el ARCHIVO COMPLETO contra el que producimos (si el operador
# puso algo fuera de nuestras marcas, el archivo difiere => NUESTRO_DISTINTO y se
# repara respetando lo ajeno con el splice de abajo).
dsh_patch_estado() {  # $1=bloque
  local patch="$1" bloque="$2"
  if [ ! -e "$patch" ]; then printf 'AUSENTE'; return 0; fi
  if [ ! -f "$patch" ] || [ ! -r "$patch" ]; then printf 'NO_OBSERVABLE'; return 0; fi
  if [ "$(cat "$patch")" = "$bloque" ]; then printf 'NUESTRO_IDENTICO'; else printf 'NUESTRO_DISTINTO'; fi
}

# Inserta el bloque nuestro ENTRE marcas, preservando byte a byte lo ajeno fuera
# de `# >>> summonaikit-gate START` / `# <<< summonaikit-gate END`. Atomico:
# temporal en el mismo dir + igualdad + mv. Si el archivo no existe, se crea.
dsh_patch_insertar() {  # $1=patch  $2=bloque
  local patch="$1" bloque="$2" dir tmp start end actual
  dir="$(dirname "$patch")"
  mkdir -p "$dir" || return 1
  tmp="$(mktemp "$dir/.saikit-dsh-patch-XXXXXX")" || return 1
  # Se escribe directo al temporal (no a variables) para no perder newlines: la
  # sustitucion `$(...)` elimina los saltos finales y pegaria lineas en las
  # fronteras (HIGH codex+glm r1 PR #88), corrompiendo el contenido ajeno que el
  # DoD manda respetar byte a byte.
  : > "$tmp"
  if [ -e "$patch" ]; then
    start="$(grep -n '^# >>> summonaikit-gate START' "$patch" | head -1 | cut -d: -f1)"
    end="$(grep -n '^# <<< summonaikit-gate END' "$patch" | head -1 | cut -d: -f1)"
    if [ -n "$start" ] && [ -n "$end" ] && [ "$start" -ge 1 ] && [ "$end" -gt "$start" ]; then
      # Splice: conserva lo anterior, inserta el bloque, re-appendee lo posterior.
      if [ "$start" -gt 1 ]; then sed -n "1,$((start - 1))p" "$patch" >> "$tmp"; fi
      # El bloque debe quedar a continuacion; si lo anterior no termino con \n, se repone.
      printf '%s' "$bloque" >> "$tmp"
      if [ "$(tail -c1 "$tmp" | od -An -tuC | tr -d ' ')" != "10" ]; then printf '\n' >> "$tmp"; fi
      # UNA linea despues del END (puede ser vacia) re-appendee lo posterior.
      sed -n "$((end + 1)),\$p" "$patch" >> "$tmp"
      if [ "$(tail -c1 "$tmp" | od -An -tuC | tr -d ' ')" != "10" ]; then printf '\n' >> "$tmp"; fi
      mv -f "$tmp" "$patch" || { rm -f "$tmp"; return 1; }
      return 0
    fi
    # Sin marcas validas: appendear el bloque al final (respeta lo que ya habia).
    actual="$(cat "$patch")"
    case "$(printf '%s' "$actual" | tr -d '[:space:]')" in
      '') true ;;
      '[]') : ;;
      *) printf '%s' "$actual" >> "$tmp"
         [ "$(tail -c1 "$tmp" | od -An -tuC | tr -d ' ')" != "10" ] && printf '\n' >> "$tmp" ;;
    esac
  fi
  printf '%s' "$bloque" >> "$tmp"
  [ "$(tail -c1 "$tmp" | od -An -tuC | tr -d ' ')" != "10" ] && printf '\n' >> "$tmp"
  mv -f "$tmp" "$patch" || { rm -f "$tmp"; return 1; }
  return 0
}

# Publica los 4 archivos del paquete adaptador en <dsh-home>/plugins/
# summonaikit-dsh-gate/, respetando la disciplina de tres estados (marcador en
# package.json: `"saikit_owned": "summonaikit-claude"`). Compara sha por archivo,
# repara con backup NUESTRO_DISTINTO, AUSENTE instala.
#
# IMPORTANTE (HIGH codex r1 PR #88): la propiedad la DECIDE package.json y se
# clasifica ANTES de escribir UN solo byte. Antes se procesaba index.js etc. y
# recien al final se miraba package.json: un dir ajeno (package sin marcador)
# podia quedar pisado archivo por archivo antes de detectarse. Ahora:
#   - dir no existe                -> AUSENTE (instalar los 4)
#   - dir existe + package sin marcador -> DESCONOCIDO completo: NO se toca
#   - dir existe + package nuestro  -> por archivo: NUESTRO_IDENTICO / NUESTRO_DISTINTO
dsh_publicar_plugin() {
  local srdir="$repo/hosts/dsh" ddir="$(dsh_plugin_dir)" file
  local f dirstado bak dir_estado
  DSH_PLUGIN_DESTS=(); DSH_PLUGIN_BACKUPS=()
  # Clasificar el DIRECTORIO (no cada archivo) por el package.json de destino.
  # Un dir que EXISTE y no lleva nuestro package.json es de otro o quedó a medias
  # de un install que no escribió el package (se copia ÚLTIMO): NO se escribe
  # dentro (M4/qwen r1 PR #88) — se clasifica DESCONOCIDO, intocable entero.
  if [ -d "$ddir" ] && [ ! -e "$ddir/package.json" ]; then
    dir_estado='DESCONOCIDO'
  elif [ ! -e "$ddir/package.json" ]; then
    dir_estado='AUSENTE'
  elif [ ! -f "$ddir/package.json" ] || [ ! -r "$ddir/package.json" ]; then
    dir_estado='NO_OBSERVABLE'
  elif grep -q '"saikit_owned"[[:space:]]*:[[:space:]]*"summonaikit-claude"' "$ddir/package.json" 2>/dev/null; then
    dir_estado='NUESTRO'
  else
    dir_estado='DESCONOCIDO'
  fi
  case "$dir_estado" in
    DESCONOCIDO)
      decir "[summonaikit] PLUGIN DSH DESCONOCIDO — no se toco nada ($ddir)."
      decir "              El dir del plugin existe y su package.json no lleva saikit_owned: puede ser de otro."
      return 1
      ;;
    NO_OBSERVABLE)
      decir "[summonaikit] unknown — no se pudo clasificar el plugin dsh ($ddir)."
      return 1
      ;;
  esac
  # AUSENTE o NUESTRO: crear el dir si falta y procesar archivo por archivo.
  mkdir -p "$ddir" || return 1
  for file in index.js translate.js spawn-hook.js package.json; do
    f="$srdir/$file"
    [ -r "$f" ] || { decir "[summonaikit] instalador: falta $f en hosts/dsh"; return 1; }
    if [ ! -e "$ddir/$file" ]; then dirstado='AUSENTE'
    elif cmp -s "$f" "$ddir/$file"; then dirstado='NUESTRO_IDENTICO'; else dirstado='NUESTRO_DISTINTO'; fi
    case "$dirstado" in
      NUESTRO_IDENTICO) : ;;
      AUSENTE)
        cp "$f" "$ddir/$file" || return 1
        DSH_PLUGIN_DESTS+=("$ddir/$file"); DSH_PLUGIN_BACKUPS+=('')
        ;;
      NUESTRO_DISTINTO)
        zcode_archivar_agente "$ddir/$file" || return 1
        bak="$zcode_agent_backup"
        cp "$f" "$ddir/$file" || return 1
        DSH_PLUGIN_DESTS+=("$ddir/$file"); DSH_PLUGIN_BACKUPS+=("$bak")
        ;;
    esac
  done
  return 0
}

dsh_publicar_patch() {
  local patch="$(dsh_patch)" bloque
  bloque="$(dsh_patch_nuestro_bloque)" || return 1
  DSH_PATCH_ESCRITO=0
  local estado="$(dsh_patch_estado "$patch" "$bloque")"
  case "$estado" in
    AUSENTE|NUESTRO_DISTINTO)
      dsh_patch_insertar "$patch" "$bloque" || return 1
      DSH_PATCH_ESCRITO=1
      decir "[summonaikit] PATCH DSH INSTALADO: $patch"
      ;;
    NUESTRO_IDENTICO) : ;;
    DESCONOCIDO|NO_OBSERVABLE)
      decir "[summonaikit] PATCH DSH DESCONOCIDO — no se toco: $patch"
      return 1
      ;;
  esac
  return 0
}

dsh_publicar() {
  dsh_publicar_plugin || return 5
  dsh_publicar_patch || return 5
  return 0
}

# Quita SOLO la entrada nuestra del patch (entre marcas), preservando lo ajeno
# fuera de ellas. Backup fechado + escritura atomica. La usan dsh_quitar (con su
# backup y mensaje) y dsh_rollback_publicar (para revertir un install fallido).
dsh_quitar_patch_solo() {
  local patch="$(dsh_patch)" start end dir tmp bak
  [ -f "$patch" ] || { decir "[summonaikit] PATCH DSH: no existe ($patch)."; return 1; }
  start="$(grep -n '^# >>> summonaikit-gate START' "$patch" | head -1 | cut -d: -f1)"
  end="$(grep -n '^# <<< summonaikit-gate END' "$patch" | head -1 | cut -d: -f1)"
  if [ -z "$start" ] || [ -z "$end" ] || [ "$start" -lt 1 ] || [ "$end" -le "$start" ]; then
    decir "[summonaikit] PATCH DSH: no hay entrada entre marcas ($patch)."
    return 1
  fi
  dir="$(dirname "$patch")"
  bak="$(mktemp "$dir/cordis.patch.yml.saikit-backup-XXXXXX")" || return 1
  cp "$patch" "$bak" && cmp -s "$bak" "$patch" || { rm -f "$bak"; return 1; }
  tmp="$(mktemp "$dir/.saikit-dsh-patch-XXXXXX")" || { rm -f "$bak"; return 1; }
  if [ "$start" -gt 1 ]; then sed -n "1,$((start - 1))p" "$patch" >> "$tmp"; fi
  [ -s "$tmp" ] && [ "$(tail -c1 "$tmp" | od -An -tuC | tr -d ' ')" != "10" ] && printf '\n' >> "$tmp"
  sed -n "$((end + 1)),\$p" "$patch" >> "$tmp"
  [ -s "$tmp" ] && [ "$(tail -c1 "$tmp" | od -An -tuC | tr -d ' ')" != "10" ] && printf '\n' >> "$tmp"
  if [ "$(cat "$tmp" | tr -d '[:space:]')" = '' ]; then printf '[]\n' > "$tmp"; fi
  mv -f "$tmp" "$patch" || { rm -f "$tmp" "$bak"; return 1; }
  DSH_PATCH_BACKUP="$bak"
  return 0
}
DSH_PATCH_BACKUP=''

# Revierte lo publicado por el install dsh en ESTA corrida (HIGH grok r1 PR #88):
# el patch (si se toco) y los archivos de plugin escritos. Se llama ANTES de
# revertir el hook, asi el profile vuelve a su estado pre-corrida. `DSH_PATCH_ESCRITO`
# y `DSH_PLUGIN_DESTS`/`DSH_PLUGIN_BACKUPS` son globales (llenados por dsh_publicar_patch/
# dsh_publicar_plugin).
dsh_rollback_publicar() {
  decir "[summonaikit] instalador: fallo publicar el plugin/patch dsh — ROLLBACK."
  local i dest bak
  # 1) Patch: si se toco, quitar la entrada nuestra entre marcas.
  if [ "$DSH_PATCH_ESCRITO" -eq 1 ]; then
    dsh_quitar_patch_solo >/dev/null 2>&1 || decir "              ROLLBACK INCOMPLETO: no se revirtio el patch"
  fi
  # 2) Archivos de plugin: restaurar desde backup o retirar los creados.
  i=0
  while [ "$i" -lt "${#DSH_PLUGIN_DESTS[@]}" ]; do
    dest="${DSH_PLUGIN_DESTS[$i]}"; bak="${DSH_PLUGIN_BACKUPS[$i]}"
    if [ -n "$bak" ] && [ -f "$bak" ]; then
      cp "$bak" "$dest" 2>/dev/null && decir "              plugin restaurado desde $bak" || decir "              ROLLBACK INCOMPLETO: no se pudo restaurar $dest"
    else
      rm -f "$dest" 2>/dev/null && decir "              plugin retirado (creado en esta corrida): $dest" || decir "              ROLLBACK INCOMPLETO: no se pudo retirar $dest"
    fi
    i=$((i + 1))
  done
}

# Preflight del install dsh (D3: solo el instalador falla cerrado). Sin bash.exe
# el command del patch seria 'bash: '\'''\'' -> el plugin no correria; sin el se
# aborta ANTES de tocar DEST (igual que grok_preflight). La version de dsh se
# REPORTA si difiere de la medida; no se aborta -- una version distinta no es
# incompatible por definicion, solo se avisa (diseno §6). La version medida se
# lee de hosts/dsh/package.json (`summonaikit.measuredAgainst`), NO hardcodeada
# (M5/CODE r1 PR #88): comparar cadenas con grep de subcadena aceptaba
# '0.1.1-rc.20' como igual a '0.1.1-rc.2'.
dsh_preflight() {
  local medida esperada
  if ! dsh_bash_win >/dev/null 2>&1; then
    decir "[summonaikit] instalador: --host dsh requiere bash.exe (no encontrado); nada se escribio."
    exit 2
  fi
  esperada="$(sed -n 's/.*"measuredAgainst"[[:space:]]*:[[:space:]]*"@deepseek-ai\/dsh@\([^"]*\)".*/\1/p' "$repo/hosts/dsh/package.json" | head -1)"
  if command -v dsh >/dev/null 2>&1; then
    medida="$(dsh --version 2>/dev/null | head -1)"
    if [ -n "$medida" ] && [ -n "$esperada" ] && [ "$(printf '%s' "$medida" | tr -d '[:space:]')" != "$(printf '%s' "$esperada" | tr -d '[:space:]')" ]; then
      decir "[summonaikit] version de dsh ($medida) distinta de la medida ($esperada); no se aborta, revisar en 15.5."
    fi
  fi
  return 0
}

dsh_quitar() {
  local patch="$(dsh_patch)" ddir="$(dsh_plugin_dir)" file
  # Quita la entrada del patch entre marcas; lo ajeno fuera de ellas sobrevive.
  if [ -e "$patch" ]; then
    if [ ! -r "$patch" ]; then
      decir "[summonaikit] unknown — no se pudo clasificar el patch dsh ($patch); no se quito."
    elif dsh_quitar_patch_solo; then
      decir "[summonaikit] PATCH DSH QUITADO: $patch"
      [ -n "$DSH_PATCH_BACKUP" ] && decir "              backup:  $DSH_PATCH_BACKUP"
    fi
  else
    decir "[summonaikit] PATCH DSH: no existe ($patch)."
  fi
  # Quita los archivos del plugin que llevan nuestra marca (package.json), con
  # backup del dir entero (M5/qwen r1 PR #88: "volver atras tiene que ser
  # reversible"; no un rm -rf a pelo que pierde archivos extra del dir).
  if [ -e "$ddir/package.json" ] && grep -q '"saikit_owned"[[:space:]]*:[[:space:]]*"summonaikit-claude"' "$ddir/package.json" 2>/dev/null; then
    local pdir pbackup
    pdir="$(dirname "$ddir")"
    mkdir -p "$pdir/saikit-backups" 2>/dev/null || { decir "[summonaikit] instalador: no se pudo crear el dir de backups"; exit 5; }
    pbackup="$pdir/saikit-backups/summonaikit-dsh-gate.nuestro.$$.bak"
    if [ -d "$ddir" ]; then
      cp -R "$ddir" "$pbackup" 2>/dev/null && cmp -s "$ddir/package.json" "$pbackup/package.json" || {
        decir "[summonaikit] instalador: no se pudo respaldar el plugin $ddir"; exit 5; }
    fi
    rm -rf "$ddir" 2>/dev/null || { decir "[summonaikit] instalador: no se pudo borrar $ddir"; exit 5; }
    decir "[summonaikit] PLUGIN DSH QUITADO: $ddir"
    decir "              backup:  $pbackup"
  else
    decir "[summonaikit] PLUGIN DSH: no existe o no es nuestro ($ddir)."
  fi
  # Quita el hook nuestro (DEST), con backup, salvo que ya no exista.
  if [ -e "$DEST" ]; then
    if [ ! -f "$DEST" ] || [ ! -r "$DEST" ]; then
      decir "[summonaikit] unknown — no se pudo clasificar el hook dsh ($DEST); no se quito."
    elif sed -n "${MARCADOR_LINEA}p" "$DEST" | grep -Eq "$MARCADOR_RE"; then
      archivar_destino "nuestro" || exit 5
      rm -f "$DEST" || { decir "[summonaikit] instalador: no se pudo borrar $DEST"; exit 5; }
      decir "[summonaikit] HOOK DSH QUITADO: $DEST"
      decir "              backup:  $backup"
    else
      decir "[summonaikit] HOOK DSH DESCONOCIDO — no se quito ($DEST)."
    fi
  else
    decir "[summonaikit] HOOK DSH: no existe ($DEST)."
  fi
  return 0
}

# ------------------------------------------------------------------ la fuente
# En `--restore-vendor` la fuente no interviene: el archivo que va a quedar es un
# backup, y el backup del vendor por definicion NO lleva nuestro marcador. Pedirle
# los mismos requisitos que a la fuente haria imposible deshacer.
if [ "$RESTORE" -eq 0 ] && { [ ! -f "$SOURCE" ] || [ ! -r "$SOURCE" ]; }; then
  decir "[summonaikit] instalador: no hay fuente legible en $SOURCE"
  exit 2
fi

# Sin marcador, lo que instalemos hoy se clasifica DESCONOCIDO manana y el
# proximo install se planta. La identidad se declara en el archivo (Core Rule 5)
# o no se declara.
if [ "$RESTORE" -eq 0 ] && ! sed -n "${MARCADOR_LINEA}p" "$SOURCE" | grep -Eq "$MARCADOR_RE"; then
  decir "[summonaikit] instalador: la fuente no lleva el marcador de propiedad en la linea $MARCADOR_LINEA."
  decir "              Instalarla dejaria un archivo que el proximo install no puede reconocer."
  decir "              fuente: $SOURCE"
  exit 2
fi

sha_bin=''
for c in sha256sum shasum; do
  if command -v "$c" >/dev/null 2>&1; then sha_bin="$c"; break; fi
done
sha_de() {
  case "$sha_bin" in
    sha256sum) sha256sum < "$1" | cut -d' ' -f1 ;;
    shasum)    shasum -a 256 < "$1" | cut -d' ' -f1 ;;
    *)         return 1 ;;
  esac
}

# La consulta al manifiesto, en UN solo lugar, porque la usan las dos
# direcciones: clasificar el destino antes de instalar, y decidir si el backup
# que se va a restaurar es algo que alguien miro alguna vez.
#
#   0 = el hash figura (etiqueta en $detalle_manifiesto)
#   1 = se miro y NO figura
#   2 = no se pudo mirar (Core Rule 2: eso no es lo mismo que 1)
#
# El `\r` se saca antes de comparar: en un checkout Windows el manifiesto puede
# llegar con CRLF, y ahi una linea que tenga SOLO el hash dejaria el `\r` pegado
# al campo 1. El vendor conocido pasaria a "desconocido" y el instalador se
# plantaria en una maquina y no en otra — la peor forma de romperse.
# `.gitattributes` ya lo fuerza a LF; esto cubre el archivo que llegue editado
# por otra herramienta.
detalle_manifiesto=''
motivo_manifiesto=''
hash_en_manifiesto() {
  local archivo="$1" sha
  detalle_manifiesto=''
  motivo_manifiesto=''
  if [ -z "$sha_bin" ]; then
    motivo_manifiesto="no hay sha256sum ni shasum para comparar contra el manifiesto"
    return 2
  fi
  if [ ! -r "$MANIFEST" ]; then
    motivo_manifiesto="el manifiesto no se puede leer: $MANIFEST"
    return 2
  fi
  sha="$(sha_de "$archivo")" || sha=''
  if [ -z "$sha" ]; then
    motivo_manifiesto="no se pudo calcular el sha256 de $archivo"
    return 2
  fi
  if awk -v h="$sha" '
        { sub(/\r$/, "") }
        /^[[:space:]]*(#|$)/ { next }
        $1 == h { found = 1; exit }
        END { exit found ? 0 : 1 }' "$MANIFEST"; then
    detalle_manifiesto="$(awk -v h="$sha" '
        { sub(/\r$/, "") }
        $1 == h { $1 = ""; sub(/^[[:space:]]+/, ""); print; exit }' "$MANIFEST")"
    return 0
  fi
  detalle_manifiesto="sha256 $sha, que no figura en el manifiesto"
  return 1
}

# ------------------------------------------------------- clasificar el destino
dest_dir="$(dirname "$DEST")"

estado=''
detalle=''

if [ ! -e "$DEST" ]; then
  estado='AUSENTE'
elif [ ! -f "$DEST" ]; then
  # Un directorio o un dispositivo donde deberia haber un script: no se sabe que
  # es ni que se rompe al moverlo.
  estado='NO_OBSERVABLE'
  detalle="el destino existe pero no es un archivo regular"
elif [ ! -r "$DEST" ]; then
  estado='NO_OBSERVABLE'
  detalle="el destino existe pero no se puede leer"
elif sed -n "${MARCADOR_LINEA}p" "$DEST" | grep -Eq "$MARCADOR_RE"; then
  if cmp -s "$DEST" "$SOURCE"; then
    estado='NUESTRO_IDENTICO'
  else
    estado='NUESTRO_DISTINTO'
  fi
elif grep -q "^$MARCADOR_PREFIJO" "$DEST"; then
  # Lleva la marca pero no donde ni como se declaro. Puede ser una version
  # futura, otra herramienta, o alguien editando a mano: ninguna de las tres
  # habilita a pisarlo.
  estado='DESCONOCIDO'
  detalle="tiene el marcador fuera de la linea $MARCADOR_LINEA o con otro formato"
else
  # Core Rule 2: no poder consultar el manifiesto NO es haber visto que el hash
  # falta. En ese caso el destino no queda acusado de nada.
  hash_en_manifiesto "$DEST"
  case $? in
    0) estado='VENDOR_CONOCIDO'; detalle="$detalle_manifiesto" ;;
    1) estado='DESCONOCIDO';     detalle="$detalle_manifiesto" ;;
    *) estado='NO_OBSERVABLE';   detalle="$motivo_manifiesto" ;;
  esac
fi

# Task 5.4: --host zcode termina aca. Append-only al user-config de zcode; NO
# toca DEST (el archivo se instala antes, sin --host). Task 5.6: ademas
# instala/quita los perfiles en ~/.zcode/agents (no es DEST; DEST sigue
# siendo una sola copia en ~/.claude/hooks). Toda la maquinaria de
# escritura atomica de DEST que sigue es del flujo Claude y no aplica.
if [ "$HOST" = "zcode" ]; then
  if [ "$QUITAR_ZCODE" -eq 1 ]; then
    zcode_quitar
    exit $?
  fi
  zcode_instalar
  exit $?
fi

# ------------------------------------------------- Task 12.6: --host claude
# El problema: ~/.claude/agents/ lo escribe el CLI del kit y esos perfiles NO
# llevan saikit_owned, asi que la maquina de tres estados los deja DESCONOCIDO
# para siempre. La via de adopcion es el CUARTO estado, VENDOR_CONOCIDO, por
# hash contra agents/vendor-manifest.sha256 (fixtures congelados de
# tests/fixtures/vendor-agents/, generados desde el perfil vivo del CLI).
# DESCONOCIDO (ni marca ni hash) => no se toca, se reporta.
# Task 13.8: adversary se suma como cuarto rol. Es kit-owned (lleva
# saikit_owned en la fuente) y NO tiene entrada en el manifiesto de vendor:
# un adversary.md sin marca es DESCONOCIDO y no se toca -- adoptarlo
# exigiria una entrada en el manifiesto, que adversary no tiene por ser
# kit-owned (--refrescar-manifiesto solo REPORTARIA su hash, jamas adopta).
CLAUDE_AGENT_ROLES='implementer verifier reviewer adversary'

claude_agents_dir() {
  printf '%s' "${SAIKIT_CLAUDE_AGENTS_DIR:-${HOME:-}/.claude/agents}"
}

# Cuarto estado, solo para los directorios del vendor (claude/kimi). El hash
# del manifiesto es la UNICA via de adopcion: sin el, un perfil sin marca es
# DESCONOCIDO y no se toca.
#
# Task 12.9 (hallazgos #2 y #3, codex+grok): reusa sha_de()/hash_en_manifiesto()
# ya definidos mas arriba (linea ~1123/1147) en vez de un `sha256sum "$1"`
# suelto -- mismo binario, mismo strip de `\r`, y sobre todo distingue
# "no se pudo mirar" (Core Rule 2) de "se miro y no esta": antes, un
# manifiesto ilegible o un sha256 que fallara devolvia `return 1` a secas, que
# el llamador leia como DESCONOCIDO. Y el lookup ahora compara hash Y rol
# LINEA POR LINEA con awk, no concatenando todo `$2 == r {print $1}` en una
# sola variable multilinea: eso rompia la igualdad en cuanto el manifiesto
# tenia DOS hashes para el mismo rol (el propio `--refrescar-manifiesto`
# invita a agregar hashes, asi que dos entradas por rol es el caso normal de
# uso, no un borde).
#
#   0 = el hash figura para ESE rol
#   1 = se miro y NO figura para ese rol
#   2 = no se pudo mirar (manifiesto ilegible o sha256 no calculable)
agente_hash_en_manifiesto() {  # $1=archivo  $2=rol
  local archivo="$1" rol="$2" manifiesto sha
  manifiesto="$repo/agents/vendor-manifest.sha256"
  if [ -z "$sha_bin" ]; then
    motivo_manifiesto="no hay sha256sum ni shasum para comparar contra el manifiesto de agentes"
    return 2
  fi
  if [ ! -r "$manifiesto" ]; then
    motivo_manifiesto="el manifiesto de agentes no se puede leer: $manifiesto"
    return 2
  fi
  sha="$(sha_de "$archivo")" || sha=''
  if [ -z "$sha" ]; then
    motivo_manifiesto="no se pudo calcular el sha256 de $archivo"
    return 2
  fi
  if awk -v h="$sha" -v r="${rol}.md" '
        { sub(/\r$/, "") }
        /^[[:space:]]*(#|$)/ { next }
        $1 == h && $2 == r { found = 1; exit }
        END { exit found ? 0 : 1 }' "$manifiesto"; then
    return 0
  fi
  motivo_manifiesto="sha256 $sha, que no figura en el manifiesto para $rol"
  return 1
}

# Retrocompatibilidad de nombre para quien ya llame a la version booleana.
agente_es_vendor_conocido() {  # $1=dest  $2=rol
  agente_hash_en_manifiesto "$1" "$2"
}

# Como zcode_agente_estado, mas el estado VENDOR_CONOCIDO. Task 12.9
# (hallazgo #2): el NO_OBSERVABLE del manifiesto/sha ya no cae en DESCONOCIDO
# -- se propaga tal cual para que el llamador lo trate como "no se pudo
# clasificar" (exit 5), no como "se miro y no esta" (exit 0, DESCONOCIDO).
agente_estado_con_vendor() {  # $1=dest  $2=traducida  $3=rol
  local dest="$1" trad="$2" rol="$3" rc
  if [ ! -e "$dest" ]; then printf 'AUSENTE'; return 0; fi
  if [ ! -f "$dest" ] || [ ! -r "$dest" ]; then printf 'NO_OBSERVABLE'; return 0; fi
  if zcode_agente_tiene_marca "$dest"; then
    if cmp -s "$dest" "$trad"; then printf 'NUESTRO_IDENTICO'; else printf 'NUESTRO_DISTINTO'; fi
    return 0
  fi
  agente_hash_en_manifiesto "$dest" "$rol"
  rc=$?
  case "$rc" in
    0) printf 'VENDOR_CONOCIDO' ;;
    1) printf 'DESCONOCIDO' ;;
    *) printf 'NO_OBSERVABLE' ;;
  esac
}

# El sello `.vendor.` distingue el backup de adopcion del de reparacion
# (`.nuestro.`), igual que hace el instalador del hook.
claude_archivar_vendor() {  # $1=dest
  local dest="$1" dir backup_dir sello backup n
  dir="$(dirname "$dest")"
  backup_dir="$dir/saikit-backups"
  mkdir -p "$backup_dir" || return 1
  sello="$(date +%Y%m%d-%H%M%S)"
  backup="$backup_dir/$(basename "$dest").vendor.$sello.bak"
  n=2
  while [ -e "$backup" ]; do
    backup="$backup_dir/$(basename "$dest").vendor.$sello-$n.bak"
    n=$((n + 1))
  done
  cp "$dest" "$backup" || return 1
  cmp -s "$backup" "$dest" || return 1
  return 0
}

# (TRADS_VENDOR_PENDIENTES y limpiar_trads_vendor viven ARRIBA, junto a
# ZCODE_AGENT_ROLES: el bucle two-phase de zcode tambien los usa y su dispatch
# corre ANTES de esta seccion — el deploy de 13.9 atrapo en vivo el
# `command not found` de tenerlos declarados aca.)

# Unifica claude_instalar_agentes y kimi_instalar_agentes (Task 12.7): mismo
# bucle de validar+publicar con el CUARTO estado (VENDOR_CONOCIDO), solo
# cambia el host que agente_traducido() traduce, el directorio destino y la
# etiqueta de los mensajes. El manifiesto (agents/vendor-manifest.sha256) NO
# es por-host: mapea hash -> rol, asi que agente_es_vendor_conocido() ya sirve
# tal cual para cualquier vendor cuyo perfil vivo coincida byte a byte con el
# fixture congelado. Dos copias del mismo bucle es como se arregla una sola.
instalar_agentes_con_vendor() {  # $1=host  $2=dest_dir  $3=etiqueta (log)
  local host="$1" dest_dir="$2" etiqueta="$3"
  local rol fuente dest trad estado i
  local -a roles=() dests=() trads=() estados=()

  # PRIMERO valida TODAS las plantillas, DESPUES escribe. Es el orden que
  # zcode_instalar_agentes ya usa (dos bucles separados) y no es estilo:
  # validando y escribiendo en el mismo bucle, una plantilla invalida en el
  # ultimo rol deja los anteriores ya publicados -- una instalacion a medias.
  # La validacion de name: va aca tambien: sin ella, un reviewer.md cuyo
  # frontmatter diga name: implementer se publicaria como reviewer con el
  # modelo del implementer.
  for rol in $CLAUDE_AGENT_ROLES; do
    fuente="$repo/agents/$rol.md"
    if [ ! -f "$fuente" ] || [ ! -r "$fuente" ]; then
      decir "[summonaikit] instalador: falta la plantilla de agente $fuente"
      exit 2
    fi
    zcode_agente_tiene_marca "$fuente" || {
      decir "[summonaikit] instalador: la plantilla $fuente no lleva saikit_owned."; exit 2; }
    zcode_agente_frontmatter "$fuente" | grep -q "^name: ${rol}$" || {
      decir "[summonaikit] instalador: la plantilla $fuente no declara name: $rol."; exit 2; }
  done

  [ "$DRY_RUN" -eq 1 ] || mkdir -p "$dest_dir" || {
    decir "[summonaikit] instalador: no se pudo crear $dest_dir"; exit 5; }

  # Task 12.9 (hallazgo #1, codex): clasificar TODOS los destinos ANTES de
  # publicar cualquiera de ellos. Antes, cada rol se clasificaba Y se
  # publicaba en la MISMA vuelta del bucle: un NO_OBSERVABLE en el ultimo rol
  # (p. ej. un permiso raro en reviewer.md) salia exit 5 con los anteriores
  # YA escritos -- una instalacion a medias que ademas afirma,
  # con el exit != 0, que "el destino quedo intacto" (la promesa del header
  # de este archivo). Dos bucles separados, como ya hace la validacion de
  # fuentes arriba: si CUALQUIER rol da NO_OBSERVABLE, se sale sin publicar
  # nada de nada.
  #
  # Ventana TOCTOU declarada (revision interna del PR #62): entre este bucle
  # de clasificacion y el de publicacion mas abajo, otro proceso podria
  # escribir $dest_dir y invalidar el estado ya leido. Aceptada por el
  # modelo de amenaza de esta herramienta: CLI local de un solo operador,
  # invocada a mano o desde un install de un solo host, sin concurrencia
  # esperada sobre el MISMO dest_dir. Igual que el resto de este archivo
  # declara sus supuestos en vez de dejarlos implicitos.
  limpiar_trads_vendor
  for rol in $CLAUDE_AGENT_ROLES; do
    fuente="$repo/agents/$rol.md"
    dest="$dest_dir/$rol.md"
    trad="$(mktemp "${TMPDIR:-/tmp}/.saikit-trad-XXXXXX")" || { limpiar_trads_vendor; exit 5; }
    TRADS_VENDOR_PENDIENTES+=("$trad")
    agente_traducido "$host" "$fuente" > "$trad" || { limpiar_trads_vendor; exit 2; }
    estado="$(agente_estado_con_vendor "$dest" "$trad" "$rol")"
    if [ "$estado" = 'NO_OBSERVABLE' ]; then
      limpiar_trads_vendor
      decir "[summonaikit] instalador: no se pudo clasificar $dest."; exit 5
    fi
    roles+=("$rol"); dests+=("$dest"); trads+=("$trad"); estados+=("$estado")
  done

  # Task 12.9 (hallazgo #4, grok): --dry-run tambien vale para --host
  # claude/--host kimi -- antes solo se consultaba en el flujo del hook, y
  # esta funcion escribia igual pese al README prometer "no escribe". Reporta
  # la clasificacion YA hecha arriba, sin volver a tocar el destino.
  if [ "$DRY_RUN" -eq 1 ]; then
    for i in "${!roles[@]}"; do
      rol="${roles[$i]}"; dest="${dests[$i]}"; estado="${estados[$i]}"
      case "$estado" in
        AUSENTE)          decir "[summonaikit] dry-run: AGENTE ${etiqueta} AUSENTE: $rol; se instalaria." ;;
        NUESTRO_IDENTICO) decir "[summonaikit] dry-run: AGENTE ${etiqueta} ya al dia: $rol." ;;
        NUESTRO_DISTINTO) decir "[summonaikit] dry-run: AGENTE ${etiqueta} NUESTRO distinto: $rol; se repararia (con backup)." ;;
        VENDOR_CONOCIDO)  decir "[summonaikit] dry-run: AGENTE ${etiqueta} VENDOR CONOCIDO: $rol; se archivaria y reemplazaria." ;;
        DESCONOCIDO)      decir "[summonaikit] dry-run: AGENTE ${etiqueta} DESCONOCIDO: $rol; no se tocaria." ;;
      esac
      decir "              destino: $dest"
    done
    limpiar_trads_vendor
    return 0
  fi

  for i in "${!roles[@]}"; do
    rol="${roles[$i]}"; dest="${dests[$i]}"; trad="${trads[$i]}"; estado="${estados[$i]}"
    case "$estado" in
      AUSENTE)
        zcode_publicar_agente "$trad" "$dest" || { limpiar_trads_vendor; exit 5; }
        decir "[summonaikit] AGENTE ${etiqueta} INSTALADO: $rol"
        ;;
      NUESTRO_IDENTICO) : ;;
      NUESTRO_DISTINTO)
        zcode_archivar_agente "$dest" || { limpiar_trads_vendor; exit 5; }
        zcode_publicar_agente "$trad" "$dest" || { limpiar_trads_vendor; exit 5; }
        decir "[summonaikit] AGENTE ${etiqueta} REPARADO: $rol"
        ;;
      VENDOR_CONOCIDO)
        claude_archivar_vendor "$dest" || { limpiar_trads_vendor; exit 5; }
        zcode_publicar_agente "$trad" "$dest" || { limpiar_trads_vendor; exit 5; }
        decir "[summonaikit] AGENTE ${etiqueta} ADOPTADO (vendor conocido): $rol"
        ;;
      DESCONOCIDO)
        decir "[summonaikit] AGENTE ${etiqueta} DESCONOCIDO: $rol — no se toco."
        decir "              destino: $dest"
        decir "              Ni marca ni hash de vendor conocido. Puede ser un cambio legitimo."
        ;;
    esac
  done
  limpiar_trads_vendor
}

claude_instalar_agentes() {
  instalar_agentes_con_vendor claude "$(claude_agents_dir)" CLAUDE
}

# ------------------------------------------------------- Task 12.7: --host kimi
# ~/.agents/agents es la convencion COMPARTIDA del kit (hooks/, plugins/,
# skills/ al lado): el guard es estricto, solo se tocan los <rol>.md de
# CLAUDE_AGENT_ROLES, y eso ya lo garantiza instalar_agentes_con_vendor (no
# itera el directorio
# padre, solo escribe dest_dir/$rol.md). Alcance reducido por la 12.3: kimi no
# acepta model:/effort: por agente, asi que agente_traducido() no inyecta nada
# (fila vacia del router) -- esta llamada solo posesiona + saca el model:
# inerte del vendor.
kimi_agents_dir() {
  printf '%s' "${SAIKIT_KIMI_AGENTS_DIR:-${HOME:-}/.agents/agents}"
}

kimi_instalar_agentes() {
  instalar_agentes_con_vendor kimi "$(kimi_agents_dir)" KIMI
}

# --refrescar-manifiesto: REPORTA (hash + diff), JAMAS adopta. Es
# deliberadamente manual -- un --force que adopte cualquier hash convertiria
# el cuarto estado en el bypass que la maquina de tres estados existe para
# evitar. Adoptar es pegar el hash reportado en agents/vendor-manifest.sha256
# en un commit propio, con el diff a la vista en la revision.
#
# Task 12.9 (hallazgo #6, grok): generalizada de claude_refrescar_manifiesto a
# refrescar_manifiesto_vendor(dest_dir, etiqueta) para que --host kimi tenga
# la MISMA via de refresco que claude. kimi reusa el mismo manifiesto
# (agents/vendor-manifest.sha256 no es por-host), asi que sin esto un
# saikit-update que cambiara los perfiles de kimi los dejaba DESCONOCIDO para
# siempre sin el procedimiento que el propio flag promete.
refrescar_manifiesto_vendor() {  # $1=dest_dir  $2=etiqueta
  local dest_dir="$1" etiqueta="$2" rol dest hash
  for rol in $CLAUDE_AGENT_ROLES; do
    dest="$dest_dir/$rol.md"
    [ -f "$dest" ] && [ -r "$dest" ] || continue
    zcode_agente_tiene_marca "$dest" && continue
    agente_es_vendor_conocido "$dest" "$rol" && continue
    # Hallazgo inline de Greptile en el PR #62, sobre el mismo defecto que el
    # fix #2 ya cerro en la adopcion (agente_hash_en_manifiesto), pero aca en
    # el path de REFRESCO: un `sha256sum "$dest"` suelto, sin pasar por
    # sha_de()/sha_bin, es el mismo salto silencioso en un sistema con
    # `shasum` y sin `sha256sum` (o sin ninguno de los dos). La correccion
    # LITERAL de "cambiar a sha_de() pero seguir con `|| hash=''; continue`"
    # preserva el defecto de fondo: --refrescar-manifiesto existe para que un
    # humano VEA el hash de un DESCONOCIDO, y saltarlo mudo cuando el calculo
    # falla es exactamente lo que Core Rule 2 prohibe (no observable != no
    # esta). Se reporta el rol como no observable (con el motivo) y se sigue
    # con el resto de los roles -- el procedimiento entero sigue devolviendo
    # 0 porque --refrescar-manifiesto es puramente advisory.
    hash="$(sha_de "$dest")" || hash=''
    if [ -z "$hash" ]; then
      decir "[summonaikit] unknown — REFRESCAR MANIFIESTO (${etiqueta}) — $rol: no se pudo calcular el hash."
      decir "              destino: $dest"
      decir "              No se afirma que sea DESCONOCIDO: no se pudo mirar (Core Rule 2)."
      continue
    fi
    decir "[summonaikit] REFRESCAR MANIFIESTO (${etiqueta}) — $rol: DESCONOCIDO"
    decir "              destino: $dest"
    decir "              sha256: $hash"
    # grok r1 #3 (cross-review del PR #66): adversary es kit-owned y NO tiene
    # ni debe tener entrada de vendor — reportarlo en el mismo formato que los
    # candidatos legitimos invitaba al operador a pegar un hash que, adoptado,
    # dejaria al kit pisar un adversary.md ajeno como VENDOR_CONOCIDO.
    if [ "$rol" = "adversary" ]; then
      decir "              OJO: adversary es kit-owned y NO tiene entrada de vendor:"
      decir "              este hash NO va al manifiesto (pegado, el kit pisaria este archivo como VENDOR_CONOCIDO)."
    fi
    decir "              diff contra la plantilla del repo:"
    diff -u "$repo/agents/$rol.md" "$dest" 2>&1 | while IFS= read -r linea; do
      decir "              $linea"
    done
    decir "              No se adopto nada: --refrescar-manifiesto solo reporta."
  done
  return 0
}

# Task 16.5 (D1/D8): planta el recetario y la skill /sencillo con la maquina de
# estados POR ARCHIVO de los perfiles (marca saikit_owned; ajeno => DESCONOCIDO,
# no se toca). Clasifica TODO antes de escribir nada (12.9) y publica cada
# directorio de un solo golpe (dos renames); la ventana entre los dos mv se
# declara, no se esconde.
recetas_clasificar() {  # $1=dest $2=fuente → estado (el manifiesto no lleva frontmatter)
  # 16.5 (cross-review, hilo symlink): un $dest que sea symlink NO es nuestro —
  # nunca lo plantamos asi — y no se toca. Antes agente_estado_con_vendor lo
  # clasificaba por el CONTENIDO del archivo que el symlink apunta y podia
  # reemplazarlo, y el cp del staging (que replica el symlink como symlink) lo
  # seguia y escribia FUERA de recetas/. Esto lo saca del juego antes de eso.
  if [ -L "$1" ]; then printf DESCONOCIDO; return 0; fi
  # 16.5 (cross-review, hilo manifiesto ajeno): el manifiesto no lleva marca de
  # propiedad y aca se reemplaza SIEMPRE que difiera (NUESTRO_DISTINTO), SIN la
  # prueba de propiedad que si aplica quitar_recetas_claude. La asimetria es
  # DELIBERADA y se declara, no se esconde:
  #   - al INSTALAR, el manifiesto es parte del recetario que plantamos: si gana
  #     un manifiesto viejo/ajeno, nuestras recetas recien plantadas NO aparecen
  #     en el menu (recetas_menu lee el manifiesto). Para que el recetario nuevo
  #     funcione, el manifiesto sale reemplazado por el nuestro; el anterior queda
  #     respaldado en saikit-backups/ dentro del staging (nunca se pierde).
  #   - al QUITAR (quitar_recetas_claude) somos cuidadosos: el manifiesto es
  #     nuestro solo si cada receta que nombra lleva la marca; si no, intacto.
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
  # 16.5: crear el PADRE del destino si no existe (p. ej. ~/.claude/skills en un
  #    perfil fresco); mktemp -d con un prefijo que no existe falla, y eso dejaba
  #    la skill sin publicar en la instalacion nueva — el caso de uso principal.
  mkdir -p "$(dirname "$destdir")" 2>/dev/null || return 5
  nuevo="$(mktemp -d "$(dirname "$destdir")/.saikit-recetas-XXXXXX")" || return 5
  if [ -d "$destdir" ]; then cp -p -r "$destdir"/. "$nuevo"/ 2>/dev/null || { rm -rf "$nuevo"; return 5; }; fi
  sello="$(date +%Y%m%d-%H%M%S)"
  for f in "$@"; do
    dest="$destdir/$(basename "$f")"
    case "$(recetas_clasificar "$dest" "$f")" in
      AUSENTE|NUESTRO_DISTINTO|VENDOR_CONOCIDO)
        if [ -e "$dest" ]; then
          mkdir -p "$nuevo/saikit-backups" && cp -p "$dest" "$nuevo/saikit-backups/$(basename "$dest").nuestro.$sello.bak" || { rm -rf "$nuevo"; return 5; }
        fi
        # defensa en profundidad (hilo symlink): borrar la ruta en el staging
        # antes de copiar, para que `cp` no pueda seguir nada. El `cp -r` inicial
        # replico cualquier symlink del destino ASI como llego; seguirlo en el
        # `cp` de aca escribiria encima del archivo que el symlink apunta (fuera
        # de recetas/).
        rm -f "$nuevo/$(basename "$f")" 2>/dev/null
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
      # dry-run NO borra y NO debe decirlo como hecho (12.9 #4 / 13.9): un aviso
      # "quitado" que no borro entrena a confiar en un dry-run que miente.
      if [ "$DRY_RUN" -eq 1 ]; then
        decir "[summonaikit] recetario: se quitara $f (dry-run)"
      else
        rm -f "$f" || { decir "[summonaikit] recetario: no se pudo borrar $f"; return 1; }
        decir "[summonaikit] recetario: quitado $f"
      fi
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
      if [ "$DRY_RUN" -eq 1 ]; then
        decir "[summonaikit] recetario: se quitara el manifiesto (dry-run)"
      else
        rm -f "$m" || { decir "[summonaikit] recetario: no se pudo borrar el manifiesto $m"; return 1; }
        decir "[summonaikit] recetario: quitado el manifiesto"
      fi
    else
      decir "[summonaikit] recetario: el manifiesto nombra recetas ajenas, intacto: $m"
    fi
  fi
  return 0
}

if [ "$HOST" = "claude" ]; then
  if [ "$REFRESCAR_MANIFIESTO" -eq 1 ]; then
    refrescar_manifiesto_vendor "$(claude_agents_dir)" CLAUDE
    exit $?
  fi
  if [ "$QUITAR_RECETAS" -eq 1 ]; then
    quitar_recetas_claude "$(dirname "$DEST")" "$HOME/.claude/skills"
    exit $?
  fi
  claude_instalar_agentes
  instalar_recetas_claude "$(dirname "$DEST")" "$HOME/.claude/skills" || exit $?
  exit $?
fi
# Task 16.5 (revision, MEDIUM): --quitar-recetas en el flujo POR DEFECTO (HOST
# vacio = el flujo del hook claude) tambien despacha a quitar_recetas_claude.
# Antes solo lo hacian en la rama --host claude, asi que sin --host el flag caia
# al camino de instalacion y REINSTALABA el recetario en vez de quitarlo.
if [ "$QUITAR_RECETAS" -eq 1 ] && [ -z "$HOST" ]; then
  quitar_recetas_claude "$(dirname "$DEST")" "$HOME/.claude/skills"
  exit $?
fi

# Task 12.7: --host kimi termina aca, igual que --host claude: solo posesiona
# los perfiles en ~/.agents/agents (via SAIKIT_KIMI_AGENTS_DIR en tests).
# No toca DEST -- el hook global de kimi-code se instala por el flujo normal
# (sin --host), igual que claude.
if [ "$HOST" = "kimi" ]; then
  if [ "$REFRESCAR_MANIFIESTO" -eq 1 ]; then
    refrescar_manifiesto_vendor "$(kimi_agents_dir)" KIMI
    exit $?
  fi
  kimi_instalar_agentes
  exit $?
fi

# Phase 15: --host dsh. Para el install NO se sale temprano: el hook se publica
# por el flujo normal de DEST (que sigue), y dsh_publicar (el plugin + el patch
# del profile) se inyecta en los desenlaces verdes de abajo. --quitar-dsh se
# despacha MAS ABAJO, junto a grok, cuando las funciones de escritura atomica
# que dsh_quitar usa ya estan definidas (archivar_destino, a la que tambien
# llama la vuelta atras del hook).

# --------------------------------------------- escritura atomica y archivado
# Las dos operaciones que TOCAN el destino viven en una funcion cada una, y las
# comparten la ida (instalar) y la vuelta (--restore-vendor). No es estilo: dos
# copias de la misma politica divergen, y cuando divergen lo hacen en silencio —
# es exactamente lo que la Task 0.5 encontro en `hook-acl.ps1`, donde la raiz y
# los descendientes terminaron decidiendo distinto sobre el mismo caso.
tmp_dest=''
limpiar_temporal() { [ -n "$tmp_dest" ] && rm -f "$tmp_dest"; }

abortar() {
  decir "[summonaikit] instalador: $1"
  decir "              El destino quedo INTACTO: $DEST"
  exit 5
}

# Deja en $tmp_dest el archivo que va a quedar: copiado EN EL MISMO DIRECTORIO
# del destino (`mv` solo es atomico dentro del mismo sistema de archivos),
# validado con `bash -n` y byte a byte igual al origen. Se valida la COPIA y no
# el origen: es el unico chequeo que cubre tambien la escritura (truncada, con
# permisos raros, o traducida a CRLF).
preparar_temporal() {
  local origen="$1" parse_err
  mkdir -p "$dest_dir" 2>/dev/null || {
    decir "[summonaikit] instalador: no se pudo crear $dest_dir"
    exit 5
  }
  tmp_dest="$(mktemp "$dest_dir/.saikit-install-XXXXXX")" || {
    decir "[summonaikit] instalador: no se pudo crear el temporal en $dest_dir"
    exit 5
  }
  trap 'limpiar_temporal' EXIT
  cat "$origen" > "$tmp_dest" || abortar "fallo la copia a $tmp_dest"
  # El error de bash se conserva y se imprime: un "no parsea" a secas obliga a
  # reproducir a mano lo que el instalador ya sabia.
  if ! parse_err="$(bash -n "$tmp_dest" 2>&1)"; then
    [ -n "$parse_err" ] && decir "$parse_err" >&2
    abortar "el archivo a instalar no parsea (bash -n); no se instala un hook roto"
  fi
  # El spec mide que el archivo vivo es LF puro; una escritura que traduzca los
  # saltos rompe la igualdad byte a byte en la primera corrida y el proximo
  # install ya no reconoceria lo suyo. `cmp` lo dice sin depender de la causa.
  cmp -s "$tmp_dest" "$origen" \
    || abortar "la copia no quedo byte a byte igual al origen (saltos de linea traducidos?)"
  chmod 0755 "$tmp_dest" 2>/dev/null || true
}

# Archiva el destino actual antes de pisarlo. Vale para las dos direcciones: si
# la vuelta atras pisa lo nuestro sin archivarlo, deshacer es un camino de una
# sola direccion y el operador que se arrepiente no tiene a que volver.
backup=''
archivar_destino() {
  local etiqueta="$1" backup_dir sello n
  backup_dir="$dest_dir/saikit-backups"
  mkdir -p "$backup_dir" || abortar "no se pudo crear $backup_dir"
  sello="$(date +%Y%m%d-%H%M%S)"
  backup="$backup_dir/$(basename "$DEST").$etiqueta.$sello.bak"
  # Dos corridas dentro del mismo segundo no se pisan el backup: el segundo
  # archivo seria el que se quiere conservar y lo perderia.
  n=2
  while [ -e "$backup" ]; do
    backup="$backup_dir/$(basename "$DEST").$etiqueta.$sello-$n.bak"
    n=$((n + 1))
  done
  cp "$DEST" "$backup" || abortar "no se pudo archivar el destino en $backup"
  cmp -s "$backup" "$DEST" || abortar "el backup no reproduce el destino; no se reemplaza sin respaldo"
}

publicar_temporal() {
  mv -f "$tmp_dest" "$DEST" || abortar "el mv final fallo (destino en uso o sin permiso)"
  tmp_dest=''
  trap - EXIT
}

# La etiqueta del backup describe QUE se archiva, no que operacion lo archiva.
etiqueta_del_estado() {
  case "$estado" in
    VENDOR_CONOCIDO) printf 'vendor' ;;
    *)               printf 'nuestro' ;;
  esac
}

# Task 7.5: --host grok. --quitar-grok termina aca (sin preflight: la limpieza
# corre aunque falten piezas). Para el install, el PREFLIGHT va ANTES de
# cualquier escritura — incluida la del --restore-vendor y la del flujo comun
# que sigue — para que un JSON desconocido deje TODO intacto. La publicacion
# del JSON y de los agentes se inyecta en los desenlaces verdes de abajo.
if [ "$HOST" = "grok" ]; then
  if [ "$QUITAR_GROK" -eq 1 ]; then
    grok_quitar
    exit $?
  fi
  grok_preflight
fi

# Phase 15: --host dsh. --quitar-dsh termina aca (sin preflight: la limpieza corre
# aunque falten piezas, como --quitar-grok). Se despacha despues de que
# archivar_destino (definida arriba) exista: dsh_quitar la usa para respaldar el
# hook al retirarlo. El install de dsh NO sale temprano: reusa el flujo de DEST.
if [ "$HOST" = "dsh" ] && [ "$QUITAR_DSH" -eq 1 ]; then
  if [ "$DRY_RUN" -eq 1 ]; then
    # HIGH codex r1 PR #88: --dry-run --quitar-dsh NO debe borrar nada.
    decir "[summonaikit] dry-run: --quitar-dsh no borraria nada (solo reporta)."
    decir "              (hook $DEST, plugin $(dsh_plugin_dir), patch $(dsh_patch))"
    exit 0
  fi
  dsh_quitar
  exit $?
fi
# Phase 15: preflight del install dsh (bash.exe + version). Sin bash.exe se
# aborta ANTES de tocar DEST (fail-closed, unica excepcion del instalador). Corre
# tambien en --dry-run: el command del patch que el dry-run reporta necesita la
# ruta de bash.exe.
if [ "$HOST" = "dsh" ]; then
  dsh_preflight
fi

# ------------------------------------------------- la vuelta: --restore-vendor
if [ "$RESTORE" -eq 1 ]; then
  bdir="$dest_dir/saikit-backups"
  base_dest="$(basename "$DEST")"

  # Core Rule 2 en el unico comando cuyo proposito es deshacer: no poder LISTAR
  # los backups no es haber visto que no hay ninguno.
  if [ -e "$bdir" ] && [ ! -d "$bdir" ]; then
    decir "[summonaikit] unknown — hay algo en la ruta de backups que no es un directorio."
    decir "              backups: $bdir"
    decir "              No se afirma que no haya backup del vendor: no se pudo mirar adentro."
    exit 4
  fi
  if [ -d "$bdir" ] && { [ ! -r "$bdir" ] || [ ! -x "$bdir" ]; }; then
    decir "[summonaikit] unknown — el directorio de backups no se puede listar."
    decir "              backups: $bdir"
    decir "              No se afirma que no haya backup del vendor: no se pudo mirar."
    exit 4
  fi

  # Se elige por el SELLO del nombre, que es el contrato que dejo la Task 2.2, y
  # no por orden alfabetico: el desempate `-N` del mismo segundo cae ANTES que el
  # que no lo lleva ('-' es 0x2D y '.' es 0x2E), asi que ordenar por nombre a
  # secas restaura el mas VIEJO de los dos, en silencio.
  elegido=''
  mejor_clave=''
  if [ -d "$bdir" ]; then
    for b in "$bdir/$base_dest".vendor.*.bak; do
      [ -f "$b" ] || continue
      resto="${b##*/}"
      resto="${resto#"$base_dest".vendor.}"
      resto="${resto%.bak}"
      case "$resto" in
        *-*-*) sello="${resto%-*}"; idx="${resto##*-}" ;;
        *-*)   sello="$resto";      idx=1 ;;
        *)     sello='';            idx=0 ;;
      esac
      case "$sello" in
        [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9]) : ;;
        *) sello='' ;;
      esac
      case "$idx" in ''|*[!0-9]*) idx=0 ;; esac
      if [ -n "$sello" ]; then
        clave="$(printf '%s%s%06d' "${sello%%-*}" "${sello##*-}" "$idx")"
      else
        # Nombre fuera del contrato: no se puede fechar, asi que solo gana si no
        # hay ningun candidato bien formado. Se toma igual antes que dejar al
        # operador sin restaurar teniendo el archivo delante.
        clave='0'
      fi
      if [ -z "$mejor_clave" ] || [ "$clave" \> "$mejor_clave" ]; then
        mejor_clave="$clave"
        elegido="$b"
      fi
    done
  fi

  if [ -z "$elegido" ]; then
    # Se miro y no hay. Es un hecho OBSERVADO y por eso no comparte codigo con el
    # 4: el operador tiene que poder distinguir "busca el archivo en otro lado"
    # de "arregla los permisos".
    decir "[summonaikit] NO HAY BACKUP DEL VENDOR para restaurar — no se toco nada."
    decir "              destino: $DEST"
    decir "              backups: $bdir"
    decir "              Se busco $base_dest.vendor.<fecha>.bak, que es el nombre que deja este instalador."
    exit 6
  fi

  if [ ! -r "$elegido" ]; then
    decir "[summonaikit] unknown — el backup elegido no se puede leer."
    decir "              backup: $elegido"
    exit 4
  fi

  # El backup tambien tiene que ser CONOCIDO, y va antes que todo lo demas.
  # Hallazgo de la revision cruzada (Codex, 2026-08-10): el instalador se niega a
  # tocar un destino desconocido y su vuelta atras instalaba cualquier archivo
  # que llevara el nombre correcto y parseara. Lo que se escribe es la ruta que
  # gatea CADA turno, asi que "no lo miramos, no lo escribimos" vale para las dos
  # direcciones. Un backup legitimo siempre pasa: solo se etiqueta `vendor` lo
  # que el instalador ya habia clasificado como vendor conocido.
  hash_en_manifiesto "$elegido"
  case $? in
    0) : ;;
    1)
      decir "[summonaikit] BACKUP DESCONOCIDO — no se restauro nada."
      decir "              backup: $elegido"
      decir "              $detalle_manifiesto"
      decir "              Lleva el nombre de un backup del vendor, pero su contenido no es ninguno"
      decir "              de los que este repo ya miro. Restaurarlo instalaria en la ruta que gatea"
      decir "              cada turno un archivo que nadie reviso: revisalo, y si corresponde agrega"
      decir "              su sha256 a $MANIFEST con una etiqueta que diga que es."
      exit 3
      ;;
    *)
      decir "[summonaikit] unknown — no se pudo comprobar el backup contra el manifiesto."
      decir "              backup: $elegido"
      decir "              $motivo_manifiesto"
      decir "              No se afirma que el backup sea desconocido: no se pudo mirar (Core Rule 2)."
      exit 4
      ;;
  esac

  # Idempotencia, y va ANTES de juzgar el destino: si ya es byte a byte el backup
  # que ibamos a poner, no hay nada que pisar ni nada que decidir. Sin esto, una
  # segunda restauracion clasificaria el vendor recien puesto como DESCONOCIDO
  # (no lleva marcador, y su hash no tiene por que estar en el manifiesto) y
  # abortaria acusando al archivo que ella misma dejo.
  if [ -f "$DEST" ] && cmp -s "$DEST" "$elegido"; then
    decir "[summonaikit] YA RESTAURADO: el destino ya es byte a byte ese backup."
    decir "              destino: $DEST"
    decir "              backup:  $elegido"
    avisar_registro
    exit 0
  fi

  case "$estado" in
    DESCONOCIDO)
      decir "[summonaikit] DESTINO DESCONOCIDO — no se toco nada, tampoco para restaurar."
      decir "              destino: $DEST"
      decir "              $detalle"
      decir "              Volver atras no habilita a destruir un cambio que nadie miro."
      exit 3
      ;;
    NO_OBSERVABLE)
      decir "[summonaikit] unknown — no se pudo clasificar el destino, asi que no se escribio."
      decir "              destino: $DEST"
      decir "              $detalle"
      exit 4
      ;;
  esac

  if [ "$DRY_RUN" -eq 1 ]; then
    decir "[summonaikit] dry-run: se restauraria el backup del vendor."
    decir "              destino: $DEST"
    decir "              backup:  $elegido"
    avisar_registro
    exit 0
  fi

  preparar_temporal "$elegido"
  [ "$estado" != 'AUSENTE' ] && archivar_destino "$(etiqueta_del_estado)"
  publicar_temporal

  decir "[summonaikit] RESTAURADO: el destino volvio al backup del vendor."
  decir "              destino: $DEST"
  decir "              backup:  $elegido"
  [ -n "$backup" ] && decir "              lo anterior quedo archivado en: $backup"
  avisar_registro
  exit 0
fi

# --------------------------------------------------- los dos estados que paran
case "$estado" in
  DESCONOCIDO)
    decir "[summonaikit] DESTINO DESCONOCIDO — no se toco nada."
    decir "              destino: $DEST"
    decir "              $detalle"
    decir "              No lleva el marcador de propiedad y su contenido no esta en el manifiesto."
    decir "              Puede ser un cambio legitimo de otro: revisarlo, y si corresponde"
    decir "              agregar su sha256 a $MANIFEST con una etiqueta que diga que es."
    exit 3
    ;;
  NO_OBSERVABLE)
    decir "[summonaikit] unknown — no se pudo clasificar el destino, asi que no se escribio."
    decir "              destino: $DEST"
    decir "              $detalle"
    decir "              No se afirma que el destino sea desconocido: no se pudo mirar (Core Rule 2)."
    decir "              El instalador falla CERRADO: es la excepcion declarada al fail-open."
    exit 4
    ;;
esac

# ------------------------------------------------- el estado que no escribe nada
if [ "$estado" = 'NUESTRO_IDENTICO' ]; then
  # No se reescribe "por las dudas": un `mv` cambia el mtime y con el la unica
  # senal barata de cuando cambio de verdad el archivo que gatea cada turno.
  decir "[summonaikit] YA AL DIA: el destino es nuestro y byte a byte igual a la fuente."
  decir "              destino: $DEST"
  # Task 7.5: con el hook ya al dia igual faltan el JSON y los agentes de
  # grok (D1: las tres publicaciones son independientes del estado del hook).
  if [ "$HOST" = "grok" ]; then
    grok_publicar
  fi
  # Phase 15: idem para dsh (plugin + patch del profile; D1). Si falla, NO se
  # afirma "YA AL DIA" completo (HIGH codex+glm r1 PR #88) y se sale con error.
  if [ "$HOST" = "dsh" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      decir "[summonaikit] dry-run: (dsh) hook al dia; no se toca el plugin ni el patch."
    else
      if ! dsh_publicar; then
        decir "[summonaikit] instalador: fallo publicar el plugin/patch dsh — ROLLBACK de lo publicado."
        dsh_rollback_publicar
        exit 5
      fi
    fi
  fi
  # Task 16.5: el recetario y /sencillo son independientes del estado del hook —
  # pueden faltar aun con el hook al dia. Solo aplica al flujo por defecto (el
  # del hook claude, sin --host): recetas y skills son una feature de ese host.
  if [ -z "$HOST" ]; then
    instalar_recetas_claude "$(dirname "$DEST")" "$HOME/.claude/skills" || exit $?
  fi
  avisar_registro
  exit 0
fi

if [ "$DRY_RUN" -eq 1 ]; then
  case "$estado" in
    AUSENTE)         decir "[summonaikit] dry-run: el destino no existe; se instalaria la fuente." ;;
    NUESTRO_DISTINTO) decir "[summonaikit] dry-run: destino NUESTRO pero distinto; se repararia (con backup)." ;;
    VENDOR_CONOCIDO) decir "[summonaikit] dry-run: destino VENDOR CONOCIDO ($detalle); se archivaria y reemplazaria." ;;
  esac
  decir "              destino: $DEST"
  decir "              fuente:  $SOURCE"
  if [ "$HOST" = "grok" ]; then
    decir "              (grok: dry-run tampoco publica el JSON de registro ni los agentes)"
  fi
  if [ "$HOST" = "dsh" ]; then
    decir "              (dsh: dry-run tampoco publica el plugin ni el patch del profile)"
  fi
  avisar_registro
  exit 0
fi

# ------------------------------------------------------------ escritura atomica
# Las tres operaciones son las mismas que usa `--restore-vendor`, con el mismo
# orden: preparar y validar la copia, archivar lo que habia, y recien entonces
# publicar. Lo unico que cambia entre la ida y la vuelta es el ORIGEN.
preparar_temporal "$SOURCE"
[ "$estado" != 'AUSENTE' ] && archivar_destino "$(etiqueta_del_estado)"
publicar_temporal
# Task 7.5: hook publicado — el JSON y los agentes de grok salen DESPUES, y si
# fallan se hace rollback del hook con el backup de esta corrida (D1). Va antes
# de los mensajes de exito: con rollback no se afirma "INSTALADO".
if [ "$HOST" = "grok" ]; then
  GROK_HOOK_PUBLICADO=1
  grok_publicar
fi
# Phase 15: idem para dsh — el plugin y el patch salen justo despues de publicar
# el hook. Si fallan, NO se afirma "INSTALADO" ni se deja el hook sin plugin
# (HIGH codex+glm r1 PR #88): se hace rollback del hook con el backup de esta
# corrida y se sale con error, igual que grok.
if [ "$HOST" = "dsh" ]; then
  if ! dsh_publicar; then
    decir "[summonaikit] instalador: fallo publicar el plugin/patch dsh — ROLLBACK."
    # Revertir lo publicado (patch + archivos de plugin) antes de tocar el hook.
    dsh_rollback_publicar
    if [ -n "${backup:-}" ] && [ -f "$backup" ]; then
      if cp "$backup" "$DEST" 2>/dev/null; then
        decir "              hook restaurado desde $backup"
      else
        decir "              ROLLBACK INCOMPLETO: no se pudo restaurar $DEST desde $backup"
      fi
    else
      rm -f "$DEST" 2>/dev/null
      decir "              hook retirado (esta corrida lo habia creado)"
    fi
    exit 5
  fi
fi

# Task 16.5: el recetario y /sencillo se publican DESPUES del hook (o ya al dia)
# y son independientes de su estado. Solo aplica al flujo por defecto (el del
# hook claude, sin --host); si el segundo directorio falla tras el primero, se
# reporta cual quedo publicado y cual no (dos directorios = dos unidades).
if [ -z "$HOST" ]; then
  instalar_recetas_claude "$(dirname "$DEST")" "$HOME/.claude/skills" || exit $?
fi

case "$estado" in
  AUSENTE)          decir "[summonaikit] INSTALADO: el destino no existia." ;;
  NUESTRO_DISTINTO) decir "[summonaikit] REPARADO: el destino era nuestro y difiere de la fuente." ;;
  VENDOR_CONOCIDO)  decir "[summonaikit] REEMPLAZADO: el destino era un vendor conocido ($detalle)." ;;
esac
decir "              destino: $DEST"
[ -n "$backup" ] && decir "              backup:  $backup"
avisar_registro
exit 0
