#!/usr/bin/env bash
# Repite los 14 eventos del turno vivo de la 23.6 contra un hook, en una caja
# aislada (HOME, state y repo propios; entorno limpio como Muse).
#   bash docs/evidence/phase-23/23.9/reproduccion/reproducir.sh <hook> [--con-label]
# Sin --con-label usa el recibo tal como lo escribio el modelo; con --con-label
# le agrega la linea VERIFIED BY SUBAGENT antes de Review en el primer Stop.
set -u
aqui="$(cd "$(dirname "$0")" && pwd)"
raiz="$(cd "$aqui/../../../../.." && pwd)"
hook="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
con_label="${2:-}"
caja="$(mktemp -d "${TMPDIR:-/tmp}/saikit-repro-239-XXXXXX")"
trap 'rm -rf "$caja"' EXIT
mkdir -p "$caja/hooks" "$caja/home" "$caja/repo"
cp "$hook" "$caja/hooks/summonaikit-harness.sh"
cp -R "$raiz/recetas" "$caja/hooks/recetas"
cp -R "$aqui/semilla/." "$caja/repo/"
git -C "$caja/repo" init -q && git -C "$caja/repo" add -A \
  && git -C "$caja/repo" -c user.name=lab -c user.email=lab@local commit -q -m semilla
repo="$(cd "$caja/repo" && pwd -P)"
for p in "$aqui"/eventos/*.json; do
  f="$(basename "$p" .json)"; fase="${f#*-}"
  sed "s|__REPO__|$repo|g" "$p" > "$caja/evento.json"
  if [ "$con_label" = "--con-label" ] && [ "$f" = "12-stop" ]; then
    jq '.last_assistant_message |= sub("\n\nReview:"; "\n\nVERIFIED BY SUBAGENT: bash tests/run.sh OK, exit 0\n\nReview:")' \
      "$caja/evento.json" > "$caja/evento2.json" && mv "$caja/evento2.json" "$caja/evento.json"
  fi
  env -i HOME="$caja/home" PATH="$PATH" SUMMONAIKIT_HOOK_TARGET=muse SUMMONAIKIT_HOOK_PHASE="$fase" \
    bash -c 'cd "$1" && exec bash "$2" --saikit-harness-id 23.3' _ "$repo" "$caja/hooks/summonaikit-harness.sh" \
    < "$caja/evento.json" > "$caja/$f.out" 2> "$caja/$f.err"
  rc=$?
  est="$(find "$caja/hooks/state" -name harness-state.env 2>/dev/null | head -n 1)"
  printf '%s rc=%s agents_seen=%s pending=%s\n' "$f" "$rc" \
    "$( [ -n "$est" ] && grep '^agents_seen=' "$est" | tail -n 1 | cut -d= -f2-)" \
    "$( [ -n "$est" ] && grep '^muse_pending=' "$est" | tail -n 1 | cut -d= -f2-)"
  if [ "$fase" = stop ]; then
    grep -E '^- Missing|BUDGET' "$caja/$f.err" | sed 's/\\n- /\n- /g' | cut -c1-60 | sed 's/^/    /'
  fi
  if [ "$con_label" = "--con-label" ] && [ "$f" = "12-stop" ]; then break; fi
done
