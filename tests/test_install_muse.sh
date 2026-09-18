#!/usr/bin/env bash
# 23.3/23.4 — --host muse: registro Claude-like en settings de usuario + perfiles.
# HOME y los cuatro XDG_* aislados. SAIKIT_MUSE_BIN apunta al Muse falso.
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
. "$here/lib/sandbox.sh"
sandbox_init || exit 1

tool="${SAIKIT_INSTALL_TOOL:-$repo/tools/install-hook.sh}"
fuente="$repo/hooks/summonaikit-harness.sh"
falso="$repo/tests/fixtures/muse/muse-falso.sh"
herramientas="$repo/tests/fixtures/muse/herramientas-muse.txt"

fail=0
caso() { printf '  caso: %s\n' "$1"; }
malo() { printf '    FAIL: %s\n' "$1" >&2; fail=1; }

SAIKIT_PY="$(command -v python3 || command -v python || true)"
if [ -z "$SAIKIT_PY" ]; then
  echo "test_install_muse: unknown — no hay python3 ni python." >&2
  exit 3
fi
if [ ! -f "$falso" ]; then
  echo "test_install_muse: FAIL — falta $falso" >&2
  exit 1
fi
command -v jq >/dev/null 2>&1 || {
  echo "test_install_muse: unknown — no hay jq." >&2
  exit 3
}

# bash >= 4: el de macOS /bin/bash es 3.2 y Muse bloquearia cada prompt.
muse_bash=''
for cand in /opt/homebrew/bin/bash /usr/local/bin/bash "$(command -v bash)"; do
  [ -n "$cand" ] && [ -x "$cand" ] || continue
  if "$cand" -c '[ "${BASH_VERSINFO[0]}" -ge 4 ]' 2>/dev/null; then
    muse_bash="$cand"
    break
  fi
done
if [ -z "$muse_bash" ]; then
  echo "test_install_muse: unknown — no hay bash >= 4 para SAIKIT_MUSE_BASH." >&2
  exit 3
fi

export XDG_CONFIG_HOME="$SANDBOX/xdg"
export XDG_DATA_HOME="$SANDBOX/data"
export XDG_STATE_HOME="$SANDBOX/state"
export XDG_CACHE_HOME="$SANDBOX/cache"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"

dest="$HOME/.claude/hooks/summonaikit-harness.sh"
mkdir -p "$(dirname "$dest")"
cp "$fuente" "$dest"

muse_dir="$XDG_CONFIG_HOME/muse"
settings="$muse_dir/settings.json"
agents="$muse_dir/agents"

host_muse() {
  SAIKIT_MUSE_BIN="$falso" SAIKIT_MUSE_BASH="$muse_bash" \
    bash "$tool" --host muse "$@"
}

reset_muse() {
  rm -rf "$muse_dir"
  mkdir -p "$muse_dir"
  cp "$fuente" "$dest"
}

# --- --check --host muse afirma el MENSAJE de la guarda de --check, no el de --host ---
caso "--check --host muse sale 2 y el mensaje nombra muse"
out="$(bash "$tool" --check --host muse 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || malo "--check --host muse salio $rc, se esperaba 2: $out"
printf '%s' "$out" | grep -Fq -- '--check --host solo acepta' \
  || malo "debia ser el mensaje de --check, no el de --host: $out"
printf '%s' "$out" | grep -qi 'muse' \
  || malo "el mensaje de --check --host debe nombrar muse: $out"
printf '%s' "$out" | grep -Fq 'solo acepta "zcode"' \
  && malo "salio el mensaje de --host desconocido, no el de --check: $out"

# --- --check sin host: fila REGISTRO muse solo si existe el dir ---
caso "--check sin host no emite fila muse si el dir no existe"
reset_muse
rmdir "$muse_dir" 2>/dev/null || rm -rf "$muse_dir"
out="$(bash "$tool" --check 2>&1)"; rc=$?
printf '%s' "$out" | grep -Fq 'host=muse' \
  && malo "--check sin dir muse no debe emitir fila muse: $out"
printf '%s' "$out" | grep -Fq 'host=zcode' \
  && malo "--check no debe emitir fila zcode: $out"

caso "--check sin host suma fila REGISTRO muse si el dir existe"
reset_muse
out="$(bash "$tool" --check 2>&1)"
printf '%s' "$out" | grep -Fq 'host=muse' \
  || malo "con dir muse, --check sin host debe emitir fila muse: $out"
printf '%s' "$out" | grep -Fq 'host=zcode' \
  && malo "zcode no tiene fila de registro: $out"

# --- dir ausente => exit 2 ---
caso "sin directorio muse => exit 2, no escribe"
rm -rf "$muse_dir"
antes="$(find "$XDG_CONFIG_HOME" -mindepth 1 2>/dev/null | wc -l | tr -d ' ')"
out="$(host_muse 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || malo "sin dir muse salio $rc: $out"
printf '%s' "$out" | grep -qi 'muse' || malo "debe decir que Muse no esta instalado: $out"
despues="$(find "$XDG_CONFIG_HOME" -mindepth 1 2>/dev/null | wc -l | tr -d ' ')"
[ "$antes" = "$despues" ] || malo "sin dir muse no debe escribir bajo XDG_CONFIG_HOME"

# --- Windows/MSYS (cygpath presente) => unknown exit 4, no escribe ---
caso "cygpath en PATH => unknown exit 4, no escribe"
reset_muse
mkdir -p "$SANDBOX/binwin"
printf '#!/bin/sh\nexit 0\n' > "$SANDBOX/binwin/cygpath"
chmod +x "$SANDBOX/binwin/cygpath"
out="$(PATH="$SANDBOX/binwin:$PATH" host_muse 2>&1)"; rc=$?
[ "$rc" -eq 4 ] || malo "con cygpath salio $rc, se esperaba 4: $out"
printf '%s' "$out" | grep -qi 'unknown' || malo "con cygpath debe decir unknown: $out"
[ ! -f "$settings" ] || malo "con cygpath no debe escribir settings"

# --- sin binario => unknown exit 4, incluso dry-run ---
caso "sin binario (SAIKIT_MUSE_BIN vacia) => unknown 4, dry-run tampoco escribe"
reset_muse
out="$(SAIKIT_MUSE_BIN= SAIKIT_MUSE_BASH="$muse_bash" bash "$tool" --host muse --dry-run 2>&1)"; rc=$?
[ "$rc" -eq 4 ] || malo "sin binario dry-run salio $rc: $out"
printf '%s' "$out" | grep -qi 'unknown' || malo "sin binario debe decir unknown: $out"
[ ! -f "$settings" ] || malo "dry-run sin binario escribio settings"
[ ! -d "$agents" ] || malo "dry-run sin binario escribio agents"

# --- DEST no identico => exit 2 ---
caso "DEST no NUESTRO_IDENTICO => exit 2"
reset_muse
printf 'no nuestro\n' > "$dest"
out="$(host_muse 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || malo "DEST ajeno salio $rc: $out"
[ ! -f "$settings" ] || malo "no debe escribir settings si DEST no es identico"
cp "$fuente" "$dest"

# --- instalacion: cinco eventos, TARGET=muse, forma Claude-like ---
caso "instala cinco eventos Claude-like con TARGET=muse y id 23.3"
reset_muse
out="$(host_muse 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "install salio $rc: $out"
[ -f "$settings" ] || malo "no escribio $settings"
sv="$(jq -r '.schema_version' "$settings")"
[ "$sv" = "1" ] || malo "schema_version=$sv"
jq -e '.hooks.events' "$settings" >/dev/null 2>&1 \
  && malo "no debe usar hooks.events (forma zcode): $(cat "$settings")"
for ev in SessionStart UserPromptSubmit PreToolUse PostToolUse Stop; do
  jq -e --arg e "$ev" '.hooks[$e] | type == "array"' "$settings" >/dev/null \
    || malo "falta .hooks.$ev"
done
jq -e '.hooks.SubagentStart' "$settings" >/dev/null 2>&1 \
  && malo "no debe registrar SubagentStart"
n_target="$(grep -c 'SUMMONAIKIT_HOOK_TARGET=muse' "$settings" || true)"
[ "$n_target" -ge 5 ] || malo "cada comando debe setear TARGET=muse, hay $n_target"
grep -q 'saikit-harness-id 23.3' "$settings" || malo "falta --saikit-harness-id 23.3"
printf '%s' "$(jq -r '.hooks.PreToolUse[0].matcher' "$settings")" | grep -Fxq 'bash' \
  || malo "PreToolUse matcher debe ser bash: $(jq -r '.hooks.PreToolUse[0].matcher' "$settings")"
ptu="$(jq -r '.hooks.PostToolUse[] | select(.hooks[]?.command? | strings | test("saikit-harness-id 23[.]3")) | .matcher' "$settings")"
[ "$ptu" = 'bash|edit_file|write_file|subagent_spawn|subagent_wait' ] \
  || malo "PostToolUse matcher distinto: [$ptu]"
ss_to="$(jq -r '.hooks.SessionStart[0].hooks[0].timeout' "$settings")"
stop_to="$(jq -r '.hooks.Stop[0].hooks[0].timeout' "$settings")"
[ "$ss_to" = "30" ] || malo "timeout SessionStart=$ss_to, se esperaba 30"
[ "$stop_to" = "600" ] || malo "timeout Stop=$stop_to, se esperaba 600"
cmd_ss="$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$settings")"
printf '%s' "$cmd_ss" | grep -q 'SUMMONAIKIT_HOOK_PHASE=session' \
  || malo "SessionStart debe llevar PHASE=session: $cmd_ss"
cmd_pre="$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$settings")"
printf '%s' "$cmd_pre" | grep -q 'SUMMONAIKIT_HOOK_PHASE=' \
  && malo "PreToolUse no debe llevar PHASE: $cmd_pre"
printf '%s' "$cmd_ss" | grep -Fq "$dest" \
  || malo "el command debe apuntar a la copia de claude: $cmd_ss"
[ ! -e "$HOME/.muse/hooks.json" ] && [ ! -e "$SANDBOX/work/.muse/hooks.json" ] \
  || malo "el kit no debe escribir .muse/hooks.json"

# --- idempotencia ---
caso "segunda corrida no duplica y perfiles ya al dia"
antes="$(cksum < "$settings")"
out="$(host_muse 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "segunda corrida salio $rc: $out"
[ "$antes" = "$(cksum < "$settings")" ] || malo "segunda corrida reescribio settings"
printf '%s' "$out" | grep -qi 'DESCONOCIDO' \
  && malo "segunda corrida no debe clasificar DESCONOCIDO: $out"
printf '%s' "$out" | grep -qi 'ya al dia\|AL DIA\|identico' \
  || malo "segunda corrida debe afirmar ya al dia: $out"

# --- aviso ajeno previo si instala ---
caso "aviso ajeno previo (evento inventado) si instala"
reset_muse
cat > "$settings" <<'JSON'
{"schema_version":1,"hooks":{"NoExiste":[{"hooks":[{"type":"command","command":"/usr/bin/true"}]}]}}
JSON
out="$(host_muse 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "aviso ajeno previo debia instalar, salio $rc: $out"
jq -e '.hooks.NoExiste' "$settings" >/dev/null || malo "debe preservar la clave ajena NoExiste"
jq -e '.hooks.SessionStart' "$settings" >/dev/null || malo "debia agregar SessionStart"

# --- grupo nuestro PreToolUse con campo desconocido NO instala ---
caso "PreToolUse nuestro con campo desconocido NO instala (compara avisos)"
reset_muse
host_muse >/dev/null 2>&1
ck="$(cksum < "$settings")"
out="$(SAIKIT_MUSE_PATCH_CANDIDATE='.hooks.PreToolUse |= map(if any(.hooks[]?; (.command // "") | test("saikit-harness-id 23[.]3")) then . + {comando_inventado: true} else . end)' \
  host_muse 2>&1)"; rc=$?
[ "$rc" -ne 0 ] || malo "campo desconocido en PreToolUse nuestro debia rechazar: $out"
[ "$ck" = "$(cksum < "$settings")" ] || malo "settings se reescribio tras rechazo por aviso nuevo"

# --- bloque Hooks: Muse no dispara, sin marcas, el instalador rechaza ---
caso "Muse falso: bloque Hooks no deja marcas"
caja_h="$(mktemp -d "$SANDBOX/hooks-XXXXXX")"
mkdir -p "$caja_h/xdg/muse" "$caja_h/work"
cat > "$caja_h/xdg/muse/settings.json" <<JSON
{"schema_version":1,"Hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"touch $caja_h/SessionStart"}]}],"UserPromptSubmit":[{"hooks":[{"type":"command","command":"touch $caja_h/UserPromptSubmit"}]}],"Stop":[{"hooks":[{"type":"command","command":"touch $caja_h/Stop"}]}]}}
JSON
( cd "$caja_h/work" && env HOME="$caja_h/home" XDG_CONFIG_HOME="$caja_h/xdg" \
    XDG_DATA_HOME="$caja_h/data" XDG_STATE_HOME="$caja_h/state" XDG_CACHE_HOME="$caja_h/cache" \
    bash "$falso" exec --no-session-log --provider echo ping >/dev/null 2>&1 ) || true
[ ! -e "$caja_h/SessionStart" ] || malo "Hooks no debe disparar SessionStart"
[ ! -e "$caja_h/UserPromptSubmit" ] || malo "Hooks no debe disparar UserPromptSubmit"

caso "Muse que no dispara (sin marcas) no instala"
reset_muse
mudo="$SANDBOX/muse-mudo.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$mudo"
chmod +x "$mudo"
out="$(SAIKIT_MUSE_BIN="$mudo" SAIKIT_MUSE_BASH="$muse_bash" bash "$tool" --host muse 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || malo "sin marcas debia rechazar con exit 2: $out"
printf '%s' "$out" | grep -qi 'marca' || malo "debe nombrar las marcas faltantes: $out"
[ ! -f "$settings" ] || malo "sin marcas no debe escribir settings"

# --- JSON roto se rechaza ---
caso "JSON roto se rechaza y no se toca"
reset_muse
printf '{ no json\n' > "$settings"
out="$(host_muse 2>&1)"; rc=$?
[ "$rc" -ne 0 ] || malo "JSON roto debia rechazar: $out"
grep -q '{ no json' "$settings" || malo "JSON roto no debe reescribirse"

# --- estructura: candidato sucio se rechaza; actual sucio se repara ---
caso "candidato sin PreToolUse no instala"
reset_muse
out="$(SAIKIT_MUSE_PATCH_CANDIDATE='del(.hooks.PreToolUse)' host_muse 2>&1)"; rc=$?
[ "$rc" -ne 0 ] || malo "candidato sin PreToolUse debia rechazar: $out"
printf '%s' "$out" | grep -qi 'canonicas' \
  || malo "sin PreToolUse debe fallar la estructura: $out"
[ ! -f "$settings" ] || malo "sin PreToolUse no debe escribir settings"

caso "candidato con matcher PostToolUse distinto no instala"
reset_muse
host_muse >/dev/null 2>&1
ck="$(cksum < "$settings")"
out="$(SAIKIT_MUSE_PATCH_CANDIDATE='.hooks.PostToolUse |= map(.matcher = "Bash|Edit")' \
  host_muse 2>&1)"; rc=$?
[ "$rc" -ne 0 ] || malo "matcher PostToolUse distinto en candidato debia rechazar: $out"
[ "$ck" = "$(cksum < "$settings")" ] || malo "settings se reescribio con matcher sucio"

caso "re-install repara matcher PostToolUse sucio en el actual"
reset_muse
host_muse >/dev/null 2>&1
"$SAIKIT_PY" - "$settings" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p, encoding="utf-8"))
for g in d["hooks"]["PostToolUse"]:
    cmd = (g.get("hooks") or [{}])[0].get("command", "")
    if "saikit-harness-id 23.3" in cmd:
        g["matcher"] = "Bash|Edit"
json.dump(d, open(p, "w"), indent=2)
PY
out="$(host_muse 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "re-install debia reparar matcher: $out"
ptu="$(jq -r '.hooks.PostToolUse[] | select(.hooks[]?.command? | strings | test("saikit-harness-id 23[.]3")) | .matcher' "$settings")"
[ "$ptu" = 'bash|edit_file|write_file|subagent_spawn|subagent_wait' ] \
  || malo "no restauro matcher PostToolUse: [$ptu]"

# --- --dest bajo muse config sin --host muse ---
caso "--dest bajo el dir muse sin --host muse => exit 2"
bad="$muse_dir/hooks/x.sh"
mkdir -p "$(dirname "$bad")"
out="$(bash "$tool" --dest "$bad" 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || malo "--dest bajo muse sin --host salio $rc: $out"
printf '%s' "$out" | grep -qi 'muse' || malo "debe nombrar muse: $out"

# --- --quitar-muse ---
caso "--quitar-muse saca 23.3, deja ajenos, no necesita binario"
reset_muse
host_muse >/dev/null 2>&1
"$SAIKIT_PY" - "$settings" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p, encoding="utf-8"))
d["hooks"]["Notification"] = [{"hooks":[{"type":"command","command":"/usr/bin/true"}]}]
json.dump(d, open(p, "w"), indent=2)
PY
out="$(SAIKIT_MUSE_BASH="$muse_bash" bash "$tool" --host muse --quitar-muse 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "--quitar-muse salio $rc: $out"
grep -q 'saikit-harness-id 23.3' "$settings" && malo "quitar dejo entradas 23.3"
jq -e '.hooks.Notification' "$settings" >/dev/null || malo "quitar borro el hook ajeno"

# --- perfiles 23.4 ---
caso "perfiles: skills lista, sin model, marca comentario, tools de Muse"
reset_muse
out="$(host_muse 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "install perfiles salio $rc: $out"
for rol in implementer verifier reviewer adversary; do
  f="$agents/$rol.md"
  [ -f "$f" ] || { malo "falta $f"; continue; }
  grep -qE '^#[[:space:]]*saikit_owned:[[:space:]]*summonaikit-claude[[:space:]]*$' "$f" \
    || malo "$rol: falta marca comentario YAML"
  grep -qE '^saikit_owned:' "$f" \
    && malo "$rol: la clave saikit_owned tumbaria el perfil"
  grep -qE '^model:' "$f" && malo "$rol: no debe llevar model:"
  grep -qE '^effort:' "$f" && malo "$rol: no debe llevar effort:"
  awk 'BEGIN{n=0} /^---/{n++; next} n==1 && $0 ~ /^skills:[[:space:]]*$/{ok=1} n==1 && $0 ~ /^  - /{lista=1} n==2{exit} END{exit (ok && lista)?0:1}' "$f" \
    || malo "$rol: skills no es lista YAML"
  grep -qE '^tools:.*Read|, Read|, Edit|, Write|, Glob|, Grep|, Bash' "$f" \
    && malo "$rol: tools conserva nombres de Claude"
  nombres="$(awk 'BEGIN{n=0} /^---/{n++; next} n==1 && $0 ~ /^tools:/{sub(/^tools:[[:space:]]*/,""); print; exit}' "$f")"
  old_ifs="$IFS"
  IFS=', '
  # shellcheck disable=SC2086
  set -- $nombres
  IFS="$old_ifs"
  seen=''
  for t in "$@"; do
    t="${t#"${t%%[![:space:]]*}"}"
    t="${t%"${t##*[![:space:]]}"}"
    [ -n "$t" ] || continue
    printf '%s' "$seen" | grep -Fxq "$t" && { malo "$rol: tools duplicado: $t"; }
    seen="$seen$t"$'\n'
    tail -n +2 "$herramientas" | grep -Fxq "$t" \
      || malo "$rol: tool $t no esta en herramientas-muse.txt"
  done
done

caso "perfil editado a mano es NUESTRO_DISTINTO y se repara con backup"
reset_muse
host_muse >/dev/null 2>&1
printf '\neditado a mano\n' >> "$agents/implementer.md"
out="$(host_muse 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "reparar perfil salio $rc: $out"
grep -q 'editado a mano' "$agents/implementer.md" \
  && malo "no repara el perfil editado"
ls "$agents/saikit-backups/"implementer.md.nuestro.*.bak >/dev/null 2>&1 \
  || malo "no dejo backup al reparar"

caso "archivo sin marca es DESCONOCIDO"
reset_muse
host_muse >/dev/null 2>&1
printf -- '---\nname: reviewer\ndescription: ajeno\n---\ncambio\n' > "$agents/reviewer.md"
antes="$(cksum < "$agents/reviewer.md")"
out="$(host_muse 2>&1)"
[ "$antes" = "$(cksum < "$agents/reviewer.md")" ] || malo "un perfil sin marca no se debe tocar"
printf '%s' "$out" | grep -qi 'DESCONOCIDO' || malo "debe reportar DESCONOCIDO: $out"

caso "--dry-run valida y no escribe el perfil"
reset_muse
out="$(host_muse --dry-run 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "dry-run salio $rc: $out"
[ ! -f "$settings" ] || malo "dry-run escribio settings"
[ ! -e "$agents/implementer.md" ] || malo "dry-run escribio perfiles"

caso "schema_version 2 no se soporta y no se escribe"
reset_muse
printf '%s\n' '{"schema_version":2,"hooks":{"Notification":[{"hooks":[{"type":"command","command":"/usr/bin/true"}]}]}}' > "$settings"
out="$(host_muse 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || malo "schema_version 2 debia rechazar con exit 2, salio $rc: $out"
printf '%s' "$out" | grep -qi 'schema_version' || malo "debe nombrar schema_version: $out"
sv="$(jq -r '.schema_version' "$settings")"
[ "$sv" = "2" ] || malo "no debe reescribir schema_version=$sv"
jq -e '.hooks.SessionStart' "$settings" >/dev/null \
  && malo "schema_version 2 no debe instalar SessionStart"

caso "hooks como array no se tira ni se instala"
reset_muse
printf '%s\n' '{"schema_version":1,"hooks":[{"type":"command","command":"/usr/bin/true","note":"USER_DATA"}]}' > "$settings"
out="$(host_muse 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || malo "hooks array debia rechazar con exit 2, salio $rc: $out"
grep -q 'USER_DATA' "$settings" || malo "no debe tirar el array del usuario"

caso "--dest con metacaracteres de shell se rechaza y no queda en el command"
reset_muse
pwned="$SANDBOX/PWNED_DEST"
evil_dir="$SANDBOX/tmp/foo\$(touch $pwned)bar"
mkdir -p "$evil_dir"
cp "$fuente" "$evil_dir/summonaikit-harness.sh"
out="$(host_muse --dest "$evil_dir/summonaikit-harness.sh" 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || malo "DEST con \$() debia rechazar con exit 2, salio $rc: $out"
[ ! -f "$pwned" ] || malo "no debe expandir DEST durante el install"
[ ! -f "$settings" ] || malo "DEST hostil no debe escribir settings"

caso "settings.json convertido en directorio antes del mv no reporta REGISTRADO"
reset_muse
printf '%s\n' '{"schema_version":1,"hooks":{}}' > "$settings"
trap_bin="$SANDBOX/muse-trap-dir.sh"
cat > "$trap_bin" <<TRAP
#!/usr/bin/env bash
nfile="$SANDBOX/val-count"
n=0
[ -f "\$nfile" ] && n=\$(cat "\$nfile")
n=\$((n+1))
printf '%s' "\$n" > "\$nfile"
if [ "\$n" -ge 2 ]; then
  rm -f "$settings"
  mkdir "$settings"
fi
exec bash "$falso" "\$@"
TRAP
chmod +x "$trap_bin"
out="$(SAIKIT_MUSE_BIN="$trap_bin" SAIKIT_MUSE_BASH="$muse_bash" bash "$tool" --host muse 2>&1)"; rc=$?
[ "$rc" -eq 5 ] || malo "settings directorio debia rechazar con exit 5, salio $rc: $out"
printf '%s' "$out" | grep -qi 'directorio' || malo "settings directorio debia rechazar: $out"
printf '%s' "$out" | grep -qi 'REGISTRADO' && malo "no debe imprimir REGISTRADO si settings es directorio: $out"
if [ -d "$settings" ]; then
  nested="$(find "$settings" -maxdepth 1 -type f \( -name 'saikit-muse-cand-*' -o -name '.saikit-muse-*' \) 2>/dev/null | head -n 1)"
  [ -z "$nested" ] || malo "mv anido el candidato dentro del directorio: $nested"
fi

caso "TMPDIR dentro de un clone git no hace unknown 4 y Muse no ve git"
reset_muse
git_tmp="$(mktemp -d "$repo/tests/.saikit-muse-tmpdir-XXXXXX")" || exit 1
spy="$SANDBOX/muse-spy-git.sh"
spy_log="$SANDBOX/muse-spy-git.log"
: > "$spy_log"
cat > "$spy" <<SPY
#!/usr/bin/env bash
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  printf 'GIT_VISIBLE\n' >> "$spy_log"
else
  printf 'GIT_AUSENTE\n' >> "$spy_log"
fi
exec bash "$falso" "\$@"
SPY
chmod +x "$spy"
out="$(TMPDIR="$git_tmp" TMP="$git_tmp" TEMP="$git_tmp" \
  SAIKIT_MUSE_BIN="$spy" SAIKIT_MUSE_BASH="$muse_bash" bash "$tool" --host muse 2>&1)"; rc=$?
rm -rf "$git_tmp"
[ "$rc" -eq 0 ] || malo "TMPDIR bajo el clone debia instalar, salio $rc: $out"
printf '%s' "$out" | grep -Fq 'REGISTRADO' || malo "TMPDIR bajo clone debe registrar: $out"
grep -Fq 'GIT_VISIBLE' "$spy_log" \
  && malo "Muse no debe ver git en la caja de validacion: $(cat "$spy_log")"
grep -Fq 'GIT_AUSENTE' "$spy_log" \
  || malo "el espia debe observar caja fuera de git: $(cat "$spy_log")"

caso "candidato con eventos bajo Hooks (mayuscula) no instala"
reset_muse
out="$(SAIKIT_MUSE_PATCH_CANDIDATE='.Hooks = .hooks | del(.hooks)' host_muse 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || malo "candidato Hooks debia rechazar con exit 2, salio $rc: $out"
[ ! -f "$settings" ] || malo "candidato Hooks no debe escribir settings"

caso "catalogo sin binario real se declara unknown"
# El Muse falso no exporta session log. El instalador no debe fingir catalogo.
reset_muse
out="$(host_muse 2>&1)"
printf '%s' "$out" | grep -Fq 'unknown — catalogo muse: la aceptacion del despacho con modelo real la mide el lead.' \
  || malo "el catalogo debe nombrar solo la aceptacion del despacho con modelo real: $out"

caso "purga SubagentStart 23.3 y deja un solo Stop canonico"
reset_muse
host_muse >/dev/null 2>&1
"$SAIKIT_PY" - "$settings" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p, encoding="utf-8"))
cmd = d["hooks"]["Stop"][0]["hooks"][0]["command"]
d["hooks"]["SubagentStart"] = [{"hooks":[{"type":"command","command":cmd,"timeout":30}]}]
d["hooks"]["Stop"].append({"hooks":[{"type":"command","command":cmd,"timeout":600}]})
json.dump(d, open(p, "w"), indent=2)
PY
out="$(host_muse 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "reinstall con SubagentStart/Stop duplicado salio $rc: $out"
n_ss="$(jq '(.hooks.SubagentStart // []) | length' "$settings")"
[ "$n_ss" = "0" ] || malo "SubagentStart debia quedar en 0 entradas, hay $n_ss"
n_stop="$(jq '[.hooks.Stop[]? | select(any(.hooks[]?; (.command // "") | test("saikit-harness-id 23[.]3")))] | length' "$settings")"
[ "$n_stop" = "1" ] || malo "Stop debia quedar con 1 grupo canonico, hay $n_stop"

caso "grupo ajeno vacio se conserva"
reset_muse
printf '%s\n' '{"schema_version":1,"hooks":{"Notification":[{"hooks":[]}]}}' > "$settings"
out="$(host_muse 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "grupo ajeno vacio debia instalar, salio $rc: $out"
jq -e '.hooks.Notification[0].hooks == []' "$settings" >/dev/null \
  || malo "no debe borrar el grupo ajeno vacio: $(cat "$settings")"

caso "mcpServers y hook ajeno no se ejecutan y se conservan"
reset_muse
marca_mcp="$SANDBOX/MARCA_MCP"
marca_ajena="$SANDBOX/MARCA_AJENA"
printf '%s\n' "{\"schema_version\":1,\"mcpServers\":{\"x\":{\"command\":\"touch $marca_mcp\"}},\"hooks\":{\"SessionStart\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"touch $marca_ajena\"}]}]}}" > "$settings"
out="$(host_muse 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "con mcpServers/hook ajeno debia instalar, salio $rc: $out"
[ ! -e "$marca_mcp" ] || malo "mcpServers.command no debe ejecutarse al validar"
[ ! -e "$marca_ajena" ] || malo "el hook ajeno no debe ejecutarse al validar"
jq -e '.mcpServers.x.command' "$settings" >/dev/null || malo "debe conservar mcpServers"
jq -e --arg cmd "touch $marca_ajena" 'any(.hooks.SessionStart[]?.hooks[]?; .command == $cmd)' "$settings" >/dev/null \
  || malo "debe conservar el hook ajeno de SessionStart"

caso "SAIKIT_MUSE_BASH vacia, inexistente, menor a 4 y que falla bash -n salen 2"
reset_muse
out="$(SAIKIT_MUSE_BIN="$falso" SAIKIT_MUSE_BASH= bash "$tool" --host muse 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || malo "SAIKIT_MUSE_BASH vacia salio $rc: $out"
out="$(SAIKIT_MUSE_BIN="$falso" SAIKIT_MUSE_BASH="$SANDBOX/no-existe-bash" bash "$tool" --host muse 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || malo "SAIKIT_MUSE_BASH inexistente salio $rc: $out"
fake3="$SANDBOX/bash3.sh"
printf '%s\n' '#!/bin/sh' 'if [ "$1" = "-c" ]; then eval "$2"; exit $?; fi' 'exit 0' > "$fake3"
chmod +x "$fake3"
out="$(SAIKIT_MUSE_BIN="$falso" SAIKIT_MUSE_BASH="$fake3" bash "$tool" --host muse 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || malo "bash menor a 4 salio $rc: $out"
faken="$SANDBOX/bash-n-fail.sh"
printf '%s\n' '#!/usr/bin/env bash' 'if [ "$1" = "-n" ]; then exit 1; fi' "exec \"$muse_bash\" \"\$@\"" > "$faken"
chmod +x "$faken"
out="$(SAIKIT_MUSE_BIN="$falso" SAIKIT_MUSE_BASH="$faken" bash "$tool" --host muse 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || malo "bash -n fallido salio $rc: $out"

caso "SAIKIT_MUSE_BIN inexistente termina en 4"
reset_muse
out="$(SAIKIT_MUSE_BIN="$SANDBOX/no-existe-muse" SAIKIT_MUSE_BASH="$muse_bash" bash "$tool" --host muse 2>&1)"; rc=$?
[ "$rc" -eq 4 ] || malo "BIN inexistente salio $rc: $out"
printf '%s' "$out" | grep -qi 'unknown' || malo "BIN inexistente debe decir unknown: $out"

caso "el backup es byte a byte el settings anterior"
reset_muse
printf '%s\n' '{"schema_version":1,"hooks":{"Notification":[{"hooks":[{"type":"command","command":"/usr/bin/true"}]}]}}' > "$settings"
antes="$SANDBOX/settings-antes.json"
cp "$settings" "$antes"
out="$(host_muse 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "install para backup salio $rc: $out"
bak="$(ls -1t "$muse_dir/saikit-backups/"settings.json.muse.*.bak 2>/dev/null | head -n 1)"
[ -n "$bak" ] || malo "no dejo backup del settings"
cmp -s "$antes" "$bak" || malo "el backup no es byte-identico al settings anterior"

caso "--quitar-muse retira los perfiles con marca"
reset_muse
host_muse >/dev/null 2>&1
out="$(SAIKIT_MUSE_BASH="$muse_bash" bash "$tool" --host muse --quitar-muse 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "--quitar-muse salio $rc: $out"
for rol in implementer verifier reviewer adversary; do
  [ ! -e "$agents/$rol.md" ] || malo "quitar dejo el perfil $rol"
done

caso "fila --check distingue ok de falta-registro"
reset_muse
out="$(bash "$tool" --check 2>&1)"
printf '%s' "$out" | grep 'host=muse' | grep -Fq 'registro=falta-registro' \
  || malo "sin settings, --check debe decir falta-registro: $out"
host_muse >/dev/null 2>&1
out="$(bash "$tool" --check 2>&1)"
printf '%s' "$out" | grep 'host=muse' | grep -Fq 'registro=ok' \
  || malo "con registro, --check debe decir registro=ok: $out"

caso "--dry-run con Muse mudo se rechaza"
reset_muse
mudo="$SANDBOX/muse-mudo-dry.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$mudo"
chmod +x "$mudo"
out="$(SAIKIT_MUSE_BIN="$mudo" SAIKIT_MUSE_BASH="$muse_bash" bash "$tool" --host muse --dry-run 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || malo "dry-run mudo debia rechazar con exit 2, salio $rc: $out"
[ ! -f "$settings" ] || malo "dry-run mudo no debe escribir settings"

# Medido con Muse 1.3.0: estas cinco formas dan MalformedConfig y Muse apaga
# TODOS los hooks, tambien los nuestros. El instalador no las arregla por su
# cuenta (no pisa nada ajeno): se niega con exit 2 y el settings queda igual.
caso "hooks ajenos mal formados: instalar se niega y no toca el settings"
for ajeno in \
  '{"PreToolUse":[{"matcher":"ajeno"}]}' \
  '{"Notification":["x"]}' \
  '{"PreToolUse":[{"matcher":"bash","hooks":"str"}]}' \
  '{"Notification":{"hooks":[]}}' \
  '{"Notification":[{"hooks":["x"]}]}'
do
  reset_muse
  printf '{"schema_version":1,"hooks":%s}\n' "$ajeno" > "$settings"
  cp "$settings" "$SANDBOX/mal-formado-antes.json"
  out="$(host_muse 2>&1)"; rc=$?
  [ "$rc" -eq 2 ] || malo "mal formado $ajeno debia salir 2, salio $rc: $out"
  cmp -s "$settings" "$SANDBOX/mal-formado-antes.json" \
    || malo "mal formado $ajeno: el settings cambio: $(cat "$settings")"
  printf '%s' "$out" | grep -q 'mal formad' \
    || malo "mal formado $ajeno: el mensaje debe decir mal formado: $out"
done

caso "--quitar-muse deja byte a byte los hooks ajenos mal formados"
reset_muse
host_muse >/dev/null 2>&1
"$SAIKIT_PY" - "$settings" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p, encoding="utf-8"))
d["hooks"]["Notification"] = ["x", {"matcher": "sin-hooks"}, {"matcher": "m", "hooks": "str"}, {"hooks": ["y"]}]
d["hooks"]["PreToolUse"].append("z")
json.dump(d, open(p, "w"), indent=2)
PY
notif_antes="$(jq -c '.hooks.Notification' "$settings")"
out="$(SAIKIT_MUSE_BASH="$muse_bash" bash "$tool" --host muse --quitar-muse 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "--quitar-muse con ajenos mal formados salio $rc: $out"
grep -q 'saikit-harness-id 23.3' "$settings" && malo "quitar dejo entradas 23.3 con ajenos mal formados"
[ "$(jq -c '.hooks.Notification' "$settings")" = "$notif_antes" ] \
  || malo "quitar altero los ajenos mal formados: $(jq -c '.hooks.Notification' "$settings")"
jq -e '.hooks.PreToolUse == ["z"]' "$settings" >/dev/null \
  || malo "quitar debe dejar solo la entrada ajena z en PreToolUse: $(jq -c '.hooks.PreToolUse' "$settings")"

if [ "$fail" -ne 0 ]; then
  echo "test_install_muse: FAIL" >&2
  exit 1
fi
echo "test_install_muse: OK"
