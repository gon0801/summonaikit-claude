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
HOST=''
QUITAR_ZCODE=0
# Task 7.5: --quitar-grok es la vuelta atras del host grok (JSON propio + hook
# + agentes con marca); requiere --host grok, como --quitar-zcode con zcode.
QUITAR_GROK=0
# Task 6.5: --host codex escribe la SEGUNDA copia (~/.codex/hooks) por el flujo
# NORMAL de DEST; VIO_DEST distingue "el operador eligio ruta" de "usar la que
# el host declara".
VIO_DEST=0

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
    -h|--help)  sed -n '2,50p' "$0"; exit 0 ;;
    *)
      printf '[summonaikit] instalador: opcion desconocida: %s\n' "$1" >&2
      exit 2
      ;;
  esac
done

# Task 5.4 / 6.5 / 7.5: --host acepta zcode (registro-only, no toca DEST),
# codex (instala la SEGUNDA copia en ~/.codex/hooks por el flujo normal de
# DEST) y grok (TERCERA copia en ~/.grok/hooks + JSON propio + agentes).
# Otro valor no se acepta: falla antes de tocar el archivo o el config.
if [ -n "$HOST" ] && [ "$HOST" != "zcode" ] && [ "$HOST" != "codex" ] && [ "$HOST" != "grok" ]; then
  printf '[summonaikit] instalador: --host solo acepta "zcode", "codex" o "grok" (recibido: %s)\n' "$HOST" >&2
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
# Built-ins fijos: general-purpose, Explore. Sin implementer/verifier/reviewer
# registrados, Agent type 'implementer' not found y el Stop no puede pasar.
# Fuente = agents/ del repo (no ~/.claude/agents: Core Rule 4). Destino
# overrideable para tests. Tres estados, igual que DEST: AUSENTE instala,
# NUESTRO_IDENTICO no reescribe, NUESTRO_DISTINTO repara con backup,
# DESCONOCIDO no se toca (el tipo ya existe; el hook igual se registra —
# no es "no se puede satisfacer la ceremonia", es un perfil de otro).
ZCODE_AGENT_ROLES='implementer verifier reviewer'
ZCODE_AGENT_MARCA_RE='^saikit_owned:[[:space:]]*summonaikit-claude[[:space:]]*$'

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
      decir "              --host zcode no cablea un host sin implementer/verifier/reviewer."
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
  for rol in $ZCODE_AGENT_ROLES; do
    fuente="$src/$rol.md"
    dest="$dest_dir/$rol.md"
    # Task 12.5: clasifica y publica contra la TRADUCIDA, no la cruda. Con
    # inyeccion de model:/effort: por host, comparar contra la cruda daria
    # NUESTRO_DISTINTO en cada corrida y reescribiria el perfil siempre.
    trad="$(mktemp "${TMPDIR:-/tmp}/.saikit-trad-XXXXXX")" || exit 5
    agente_traducido zcode "$fuente" > "$trad" || { rm -f "$trad"; exit 2; }
    estado="$(zcode_agente_estado "$dest" "$trad")"
    case "$estado" in
      AUSENTE)
        zcode_publicar_agente "$trad" "$dest" || {
          rm -f "$trad"
          decir "[summonaikit] instalador: no se pudo escribir $dest"; exit 5; }
        decir "[summonaikit] AGENTE ZCODE INSTALADO: $rol"
        decir "              destino: $dest"
        ;;
      NUESTRO_IDENTICO)
        : ;;
      NUESTRO_DISTINTO)
        zcode_archivar_agente "$dest" || {
          rm -f "$trad"
          decir "[summonaikit] instalador: no se pudo respaldar $dest"; exit 5; }
        zcode_publicar_agente "$trad" "$dest" || {
          rm -f "$trad"
          decir "[summonaikit] instalador: no se pudo reparar $dest"; exit 5; }
        decir "[summonaikit] AGENTE ZCODE REPARADO: $rol"
        decir "              destino: $dest"
        ;;
      DESCONOCIDO)
        decir "[summonaikit] AGENTE ZCODE DESCONOCIDO: $rol — no se toco."
        decir "              destino: $dest"
        decir "              No lleva saikit_owned. Puede ser un cambio legitimo."
        ;;
      NO_OBSERVABLE)
        rm -f "$trad"
        decir "[summonaikit] instalador: no se pudo clasificar $dest (no es un archivo legible)."
        exit 5
        ;;
    esac
    rm -f "$trad"
  done
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
GROK_AGENT_ROLES='implementer verifier reviewer'
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
  local host="$1" fuente="$2" rol inyectar router
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

  # `^$` NO sirve como "regex que no matchea nada": matchea las lineas vacias y
  # se las comeria del frontmatter, y ahi el instalado dejaria de ser la fuente
  # traducida. `a^` no matchea nunca.
  local omitir='a^'
  [ "$host" = 'grok' ] && omitir='^skills:'

  awk -v omitir="$omitir" -v inyectar="$inyectar" '
    /^---[[:space:]]*\r?$/ {
      n++
      # El cierre del primer bloque: inyectar JUSTO ANTES.
      if (n == 2 && inyectar != "") print inyectar
      print; next
    }
    n == 1 && $0 ~ omitir { next }
    # Una clave nuestra que ya viniera en la fuente se descarta: manda el router.
    n == 1 && /^(model|effort):/ { next }
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
  local json canon estado_json rol fuente src dest_agente
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
      decir "              --host grok no cablea un host sin implementer/verifier/reviewer."
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
    estado_json="$(grok_agente_estado "$dest_agente" "$(agente_traducido grok "$fuente")")"
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
    trad="$(agente_traducido grok "$fuente")"
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

case "$estado" in
  AUSENTE)          decir "[summonaikit] INSTALADO: el destino no existia." ;;
  NUESTRO_DISTINTO) decir "[summonaikit] REPARADO: el destino era nuestro y difiere de la fuente." ;;
  VENDOR_CONOCIDO)  decir "[summonaikit] REEMPLAZADO: el destino era un vendor conocido ($detalle)." ;;
esac
decir "              destino: $DEST"
[ -n "$backup" ] && decir "              backup:  $backup"
avisar_registro
exit 0
