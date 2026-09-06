#!/usr/bin/env bash
# Regresiones 18.12: tools en cada host y limpieza sin atravesar enlaces.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
tool="${SAIKIT_INSTALL_TOOL:-$repo/tools/install-hook.sh}"
. "$here/lib/sandbox.sh"
sandbox_init || exit 1
fail=0
mal() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
install_host() {
  HOME="$host_home" USERPROFILE="$host_home" bash "$tool" --host "$host" --no-registration-check "$@"
}
check_tools() {
  local rel
  for rel in saikit-decision.sh saikit-blast.sh lib/redactar.sh; do
    cmp -s "$host_home/.claude/saikit-tools/$rel" "$repo/tools/$rel" \
      || mal "$host: falta o difiere $rel"
  done
  HOME="$host_home" USERPROFILE="$host_home" bash "$host_home/.claude/saikit-tools/saikit-decision.sh" \
    --append --task t --etapa verify --decision d --por-que p --evidencia e --resultado ok \
    --dir "$host_home/project/.saikit/decisiones" >/dev/null 2>&1 || mal "$host: decision no corre"
  HOME="$host_home" USERPROFILE="$host_home" bash "$host_home/.claude/saikit-tools/saikit-blast.sh" \
    --write --task t --hecho h --comando c --salida s --nivel 4 \
    --dir "$host_home/project/.saikit/findings" >/dev/null 2>&1 || mal "$host: blast no corre"
  [ -s "$host_home/project/.saikit/decisiones/t.tsv" ] || mal "$host: no hay tsv escrito"
  [ -s "$host_home/project/.saikit/findings/blast-t.json" ] || mal "$host: no hay blast escrito"
}

for host in codex dsh; do
  printf 'caso: %s — fresh, dry-run, no-op y fallo de tools\n' "$host"
  host_home="$SANDBOX/$host"
  mkdir -p "$host_home/project"
  install_host --dry-run >/dev/null 2>&1 || mal "$host: dry-run fallo"
  [ ! -e "$host_home/.claude/saikit-tools" ] || mal "$host: dry-run escribio tools"
  install_host >/dev/null 2>&1 || mal "$host: instalacion fallo"
  check_tools
  [ -f "$host_home/.$host/hooks/summonaikit-harness.sh" ] || mal "$host: falta el hook"
  if [ -d "$host_home/.claude/saikit-tools" ]; then
    mv "$host_home/.claude/saikit-tools" "$host_home/tools-previos"
  fi
  install_host --dry-run >/dev/null 2>&1 || mal "$host: dry-run de no-op fallo"
  [ ! -e "$host_home/.claude/saikit-tools" ] || mal "$host: dry-run de no-op escribio tools"
  install_host >/dev/null 2>&1 || mal "$host: no-op fallo"
  check_tools

  host_home="$SANDBOX/$host-fallo"
  mkdir -p "$host_home/.claude" "$host_home/externo"
  ln -s "$host_home/externo" "$host_home/.claude/saikit-tools"
  if install_host >/dev/null 2>&1; then mal "$host: declaro exito sin poder plantar tools"; fi
  [ ! -e "$host_home/.$host/hooks/summonaikit-harness.sh" ] || mal "$host: publico hook con tools fallidos"
  for rel in saikit-decision.sh saikit-blast.sh lib/redactar.sh; do
    for kind in enlace ajeno; do
      host_home="$SANDBOX/$host-$kind-${rel//\//-}"
      dest="$host_home/.claude/saikit-tools/$rel"
      mkdir -p "$(dirname "$dest")"
      if [ "$kind" = enlace ]; then
        ln -s "$host_home/no-existe" "$dest"
      else
        printf '# archivo del operador, no del kit\n' > "$dest"
        cp "$dest" "$host_home/original"
      fi
      if install_host >/dev/null 2>&1; then mal "$host: acepto tool $kind $rel"; fi
      [ ! -e "$host_home/.$host/hooks/summonaikit-harness.sh" ] \
        || mal "$host: publico hook con tool $kind $rel"
      if [ "$kind" = enlace ]; then
        [ -L "$dest" ] && [ "$(readlink "$dest")" = "$host_home/no-existe" ] \
          || mal "$host: altero tool enlazado $rel"
      else
        cmp -s "$dest" "$host_home/original" || mal "$host: altero tool ajeno $rel"
      fi
    done
  done
done

printf 'caso: quitar no atraviesa el symlink padre de lib\n'
remove_home="$SANDBOX/quitar"
mkdir -p "$remove_home/.claude" "$SANDBOX/externo/lib"
cp "$repo/tools/lib/redactar.sh" "$SANDBOX/externo/lib/redactar.sh"
ln -s "$SANDBOX/externo" "$remove_home/.claude/saikit-tools"
HOME="$remove_home" USERPROFILE="$remove_home" bash "$tool" --quitar-recetas --no-registration-check \
  >/dev/null 2>&1 || mal "quitar fallo"
cmp -s "$SANDBOX/externo/lib/redactar.sh" "$repo/tools/lib/redactar.sh" \
  || mal "quitar borro o cambio el redactar externo a traves del enlace padre"
[ -L "$remove_home/.claude/saikit-tools" ] || mal "quitar borro el enlace padre"

[ "$fail" -eq 0 ] || { printf 'test_trail_install: FAIL\n'; exit 1; }
printf 'test_trail_install: OK\n'
