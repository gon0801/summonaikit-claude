#!/usr/bin/env bash
# Runner de tests del repo (Task 1.1).
#
#   1) Gate de sintaxis: `bash -n` sobre todo *.sh del arbol — el hook incluido
#      cuando exista (la Phase 2 lo trae a `hooks/`). Un hook que no parsea
#      rompe TODOS los turnos siguientes, no solo el propio: por eso este gate
#      corre siempre, aunque no haya un solo test.
#   2) Cada `tests/test_*.sh` en su propio proceso, con HOME y temporal
#      redirigidos a un directorio por test (Core Rule 4).
#   3) Guardia de fuga: el arbol del repo tiene que quedar identico despues de
#      cada test. Un test que escribe adentro del repo se reporta y rompe la
#      corrida, aunque el test en si haya pasado.
#
# Sale 0 solo si el gate y todos los tests pasan. Con el repo vacio de logica
# (sin hook y sin tests) sale 0.
#
# Uso: run.sh [repo_root]
# El argumento existe para que el propio runner sea testeable contra repos
# sinteticos (ver tests/test_runner_guards.sh); por defecto es el repo que lo
# contiene. Las libs se resuelven siempre junto a ESTE archivo, no a la raiz
# recibida.
set -u

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ "$#" -ge 1 ] && [ -n "$1" ]; then
  repo_root="$(cd "$1" && pwd)" || exit 1
else
  repo_root="$(cd "$script_dir/.." && pwd)"
fi
fail=0
unknown=0
corridos=0
pasaron=0
sin_ejecutados=0
skips=0
# Mismo codigo que usan los tests para "no se pudo verificar" (ver
# `tests/lib/hook_bajo_prueba.sh`). Se define aca tambien porque el runner no
# carga esa lib: la cargan los tests, en sus propios procesos.
SAIKIT_EXIT_UNKNOWN_RUNNER=3

# ------------------------------------------- particion de la bateria (2026-08-28)
# El job `suite` del CI tarda ~7 min y `test_gate_mutations` es 4.8 de esos
# minutos (medido en el run 33231405475). `SAIKIT_PARTICION` deja correr la
# bateria en DOS jobs paralelos — `lentos` y `rapidos` — y baja el reloj a
# ~2.5 min SIN saltear un solo test: no es un skip, es un reparto.
#
# La lista vive ACA y no en el workflow a proposito: asi
# `tests/test_runner_guards.sh` puede candar la propiedad que vuelve segura la
# particion — la union de las dos mitades es la bateria ENTERA. Una particion
# que pierde un archivo es un test que deja de correr sin que nadie se entere,
# la misma falla silenciosa que el conteo de `unknown` existe para evitar.
#
# `lentos` es una lista EXPLICITA; `rapidos` es "todo lo demas". Un test nuevo
# que nadie liste corre igual, en la mitad rapida: el default cae del lado
# seguro, nunca en el limbo. Sin la variable, la bateria corre entera como
# siempre (el modo local y el de una sola maquina no cambian).
SAIKIT_TESTS_LENTOS='test_gate_mutations'

es_lento() {  # $1 = nombre del test, sin .sh
  case " $SAIKIT_TESTS_LENTOS " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

# Task 18.16: declaracion de tests SIN EJECUTOR (nadie los corre en ningun
# entorno). Vacio por defecto; ver el comentario del bucle para la razon de
# cada ausencia. Mismo mecanismo de lista que SAIKIT_TESTS_LENTOS para que
# test_runner_guards pueda candarlo con nombres sinteticos.
SAIKIT_TESTS_SIN_EJECUTOR="${SAIKIT_TESTS_SIN_EJECUTOR:-}"
sin_ejecutor_de() {  # $1 = nombre del test, sin .sh
  case " $SAIKIT_TESTS_SIN_EJECUTOR " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

particion="${SAIKIT_PARTICION:-}"
case "$particion" in
  ''|lentos|rapidos) ;;
  *)
    echo "tests/run.sh: SAIKIT_PARTICION invalida: [$particion] — vacia, 'lentos' o 'rapidos'" >&2
    exit 2 ;;
esac

# Huella del arbol: rutas + checksum. Detecta creado, borrado y modificado.
#
# Se podan los directorios que NO son contenido del repo: `.git` y los que el
# `.gitignore` ya declara ajenos (`.claude`, `.harness-mem`, `out`, `sandbox`,
# `node_modules`), la misma lista que usa `lib/check_syntax.sh`. El tooling del
# host los reescribe solo mientras la suite corre — el tablero de progreso, el
# registro de eventos de la sesion, la memoria de continuidad del harness — y sin
# podarlos las dos baterias mas largas reportaban fuga con TODOS sus casos en
# verde. Un guard que grita en falso entrena al operador a ignorarlo, que es
# exactamente lo que este guard existe para evitar.
#
# Se poda por NOMBRE y solo si es directorio: por ruta exacta solo taparia la
# raiz (hay un `.claude/` anidado en el arbol de fixtures), y sin `-type d` un
# archivo que se llamara `out` dejaria de vigilarse.
manifiesto() {
  ( cd "$1" 2>/dev/null || return 0
    # 18.22: .DS_Store es metadata de Finder en macOS: el host la reescribe al
    # navegar el arbol mientras la suite corre (medido: LEAK falso apuntando a
    # .cursor/skills/.../.DS_Store); misma razon que los directorios podados
    # de arriba.
    find . -type d \( -name .git -o -name .claude -o -name .harness-mem -o -name out \
                      -o -name sandbox -o -name node_modules \) -prune -o \
         -type f ! -name .DS_Store -print0 2>/dev/null \
      | sort -z | xargs -0 -r cksum 2>/dev/null )
}

if ! bash "$script_dir/lib/check_syntax.sh" "$repo_root"; then
  fail=1
fi

run_root="$(mktemp -d "${TMPDIR:-/tmp}/saikit-run-XXXXXX")"
trap 'rm -rf "$run_root"' EXIT

# La ruta del hook VIVO se resuelve ACA, con el HOME del invocador, y se pasa a
# los tests como referencia. Adentro del test el HOME ya es el del sandbox, asi
# que `$HOME/.claude/hooks/...` no lo encontraria — y el arnes de salida dorada
# (Task 1.2) justamente necesita leerlo. Leerlo, no escribirle: lo copia a su
# propio tmpdir antes de correrlo (Core Rule 4).
hook_vivo="${SAIKIT_HOOK_VIVO:-$HOME/.claude/hooks/summonaikit-harness.sh}"

shopt -s nullglob
for t in "$repo_root"/tests/test_*.sh; do
  nombre="$(basename "$t" .sh)"

  # Reparto por particion. Va ANTES del skip por plataforma para que cada mitad
  # cuente y liste SOLO lo suyo: un Windows-bound de la mitad rapida se salta
  # con listado ahi, y no aparece como skip fantasma en la mitad lenta.
  if [ "$particion" = lentos ] && ! es_lento "$nombre"; then continue; fi
  if [ "$particion" = rapidos ] && es_lento "$nombre"; then continue; fi

  # Task 18.16 — el skip de plataforma era una PROMESA muerta: "los corre
  # Windows" ya no lo cumple nadie (el operador dejo Windows). Un skip ya no
  # puede declarar cobertura ajena; lo unico que puede declarar honestamente
  # es que NADIE corre ese test, y eso es exactamente un `unknown`: se lista,
  # se cuenta aparte y vuelve a cerrar en exit 3 si no queda nada verificado —
  # nunca se publica como PASS, y "no lo corre NADIE" ya no es un verde.
  # La lista vive en SAIKIT_TESTS_SIN_EJECUTOR (nombres separados por espacio)
  # y hoy esta VACIA a proposito: los tres ex-Windows-bound (capture-payloads,
  # install-hook, probe-zcode-output) corren en POSIX desde 18.15/18.16, y
  # test_hook_acl fue RETIRADO — su objeto eran las ACLs/SIDs de Windows
  # (tools/hook-acl.ps1, S-1-5-18), que en macOS no existen como concepto;
  # portarlo a permisos de macOS seria inventar cobertura de una herramienta
  # muerta. La variable existe para que test_runner_guards canda el mecanismo
  # con un repo sintetico aunque la lista real este vacia.
  if sin_ejecutor_de "$nombre"; then
    echo "SKIP (sin ejecutor): $nombre — no lo corre NADIE en ningun entorno; cuenta como unknown"
    unknown=$((unknown + 1))
    sin_ejecutados=$((sin_ejecutados + 1))
    continue
  fi

  caja="$run_root/$nombre"
  mkdir -p "$caja/home/.claude/hooks/state" "$caja/tmp"
  # 18.19 — canal de skip POR CASO: el archivo vive en la caja del test y la
  # lib tests/lib/skip_caso.sh le appendea un marcador por caso declarado. Se
  # cuenta aparte (ni PASS, ni FAIL, ni el unknown por exit 3) y JAMAS altera
  # exit codes; los casos de test_runner_guards.sh candan este contrato.
  skips_caja="$caja/skips"
  : > "$skips_caja"
  if command -v cygpath >/dev/null 2>&1; then
    caja_userprofile="$(cygpath -w "$caja/home")"
  else
    caja_userprofile="$caja/home"
  fi

  antes="$(manifiesto "$repo_root")"
  env HOME="$caja/home" USERPROFILE="$caja_userprofile" \
      TMPDIR="$caja/tmp" TMP="$caja/tmp" TEMP="$caja/tmp" \
      SAIKIT_HOOK_VIVO="$hook_vivo" SAIKIT_SKIPS="$skips_caja" \
      bash "$t"
  rc=$?
  n_skips="$(grep -c '^SAIKIT_SKIP_CASO: ' "$skips_caja" 2>/dev/null)" || n_skips=0
  skips=$((skips + n_skips))
  nota_skip=''
  if [ "$n_skips" -gt 0 ]; then
    nota_skip=" con $n_skips skip"
    [ "$n_skips" -eq 1 ] || nota_skip=" con $n_skips skips"
  fi
  # Exit 3 = `unknown`: el test no fallo, pero tampoco verifico nada. Antes
  # esto salia 0 y se publicaba como PASS, asi que una maquina sin el archivo
  # bajo prueba quedaba ENTERA en verde sin haber probado una sola linea de
  # semantica (revision cruzada de la Phase 1, Task 1.5). Contarlo aparte es lo
  # que vuelve visible la diferencia entre verificado y no observado.
  case "$rc" in
    0) echo "PASS$nota_skip: $nombre"; pasaron=$((pasaron + 1)) ;;
    3) echo "UNKNOWN$nota_skip: $nombre — no se pudo verificar (no es PASS)"; unknown=$((unknown + 1)) ;;
    *) echo "FAIL$nota_skip: $nombre" >&2; fail=1 ;;
  esac
  corridos=$((corridos + 1))
  despues="$(manifiesto "$repo_root")"

  if [ "$antes" != "$despues" ]; then
    echo "LEAK: $nombre escribio dentro del repo (Core Rule 4)" >&2
    diff <(printf '%s\n' "$antes") <(printf '%s\n' "$despues") >&2 || true
    fail=1
  fi
done

# Task 10.5 / codex r1 (hallazgo 3), reencarnado para la semantica de 18.16:
# el resumen de skips imprime SIEMPRE que haya skips, ANTES de ramificar la
# salida — antes vivia al final y con UNKNOWN y SKIP a la vez la rama de
# UNKNOWN salia antes: los omitidos no se nombraban nunca, contradiciendo la
# garantia declarada.
if [ "$sin_ejecutados" -gt 0 ]; then
  echo "tests/run.sh: $sin_ejecutados SKIP (sin ejecutor) declarados — nadie los corre; cuentan como unknown (ver arriba)"
fi

# 18.19 — resumen del canal de skip POR CASO: imprime SIEMPRE que hubo skips,
# antes de ramificar la salida (misma garantia que el resumen de sin-ejecutor).
# Categoria APARTE: ni PASS, ni FAIL, ni unknown. Un skip no cambia ningun
# exit code; lo que cambia es que ya no existe el verde silencioso de
# 'printf SKIP...; return 0' publicado como PASS liso.
if [ "$skips" -gt 0 ]; then
  if [ "$skips" -eq 1 ]; then
    echo "tests/run.sh: 1 caso en SKIP declarado — categoria aparte: ni PASS, ni FAIL, ni unknown (ver arriba)"
  else
    echo "tests/run.sh: $skips casos en SKIP declarado — categoria aparte: ni PASS, ni FAIL, ni unknown (ver arriba)"
  fi
fi

# Una mitad que no corrio NINGUN test es un job verde que no probo nada: es la
# falla que esta particion podria introducir (renombrar un test lento deja la
# lista huerfana). Se rompe la corrida en vez de publicar un OK vacio.
#
# Se mira SOLO `corridos`, no `sin_ejecutados` (Greptile, PR #101, cuando los
# skips eran de plataforma): una mitad cuyos tests se saltan todos, con el
# contador de skips en la guardia no disparaba — el job cerraba `OK (0
# tests)`, que es exactamente el verde vacio que esto existe para impedir.
# Los skips se siguen listando arriba.
if [ -n "$particion" ] && [ "$corridos" -eq 0 ]; then
  echo "tests/run.sh: la particion '$particion' no corrio NINGUN test — lista huerfana o glob vacio" >&2
  echo "              (lentos declarados: $SAIKIT_TESTS_LENTOS)" >&2
  exit 1
fi

if [ "$fail" -ne 0 ]; then
  echo "tests/run.sh: FAIL" >&2
  exit 1
fi

# Un `unknown` NO es un OK. Se dice cuantos hubo, siempre, para que el resumen
# no afirme mas de lo que se midio.
if [ "$unknown" -gt 0 ]; then
  # 18.16: con skips-sin-ejecutor sumando a `unknown`, "nada se verifico" ya
  # no se lee de unknown-vs-corridos sino de pasaron==0 — ningun test hizo una
  # observacion que valga. (Sin skips era equivalente: unknown>=corridos
  # solo cuando ningun corrido pasaba.)
  if [ "$pasaron" -eq 0 ]; then
    # Nada se verifico: cerrar con OK seria la afirmacion mas falsa que este
    # runner puede emitir — verde entero sin haber probado nada. El conteo
    # incluye los SKIP (sin ejecutor): nadie los corre, y eso tambien es no
    # haber verificado (18.16).
    echo "tests/run.sh: UNKNOWN — $unknown sin verificar de $corridos corridos (incluye los SKIP sin ejecutor)." >&2
    echo "              No se afirma que el repo este sano: no se pudo mirar." >&2
    exit "$SAIKIT_EXIT_UNKNOWN_RUNNER"
  fi
  echo "tests/run.sh: OK con $unknown de $corridos en unknown (ver arriba cuales)"
  exit 0
fi
echo "tests/run.sh: OK ($corridos tests)"
