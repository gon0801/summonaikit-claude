#!/usr/bin/env bash
# Task 14.3 (respuesta CodeRabbit qwen r2 #5) — regresion del CONTRATO del
# artefacto adversary. El hook NO parsea el JSON del artefacto (label-only), asi
# que el contrato vive en dos lugares: el PERFIL (agents/adversary.md) que lo
# enseña, y el REVIEWER (agents/reviewer.md) que lo adjudica. Este test ata que
# ese contrato no se caiga en silencio:
#   1) el perfil documenta la forma del contrato (las claves exactas);
#   2) el timestamp que enseña el perfil es WINDOWS-SAFE (sin ':' — el ':' es
#      ilegal en un filename de Windows, y el timestamp va en el nombre del
#      archivo `adversary-<timestamp-UTC>.json`);
#   3) el reviewer declara MALFORMADO un artefacto ilegible O de esquema no
#      contrato (un `title`/`detail`, sin `attacked`, o un `generated_at_utc`).
# Solo lectura sobre el repo real (Core Rule 4).
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
# Los casos sinteticos de la fila 14.3 escriben fixtures en el sandbox, nunca
# en el arbol del repo (Core Rule 4), igual que test_plans_ledger.sh.
. "$here/lib/sandbox.sh"
sandbox_init

fail=0
unknown=0
malo() { printf '    FAIL: %s\n' "$1" >&2; fail=1; }
caso() { printf '  caso: %s\n' "$1"; }

# fila_143 ARCHIVO... -> imprime la(s) linea(s) de la fila de tarea 14.3 de los
# ledgers dados (una fila de tarea es UNA linea fisica, test_plans_ledger.sh lo
# candea). Vacio si ningun ledger la trae.
fila_143() { cat "$@" 2>/dev/null | grep -E '^\| *14\.3 '; }

# chequear_fila_143 ARCHIVO... -> 0 si la fila 14.3 existe y ensena SOLO la
# forma Windows-safe; imprime el motivo y devuelve 1 si no. Mira la FILA, no el
# ledger entero: un ejemplo seguro suelto en otra fila o en un apendice no
# puede dar por buena una 14.3 ausente o insegura (CodeRabbit, PR #95).
chequear_fila_143() {
  local fila
  fila="$(fila_143 "$@")"
  if [ -z "$fila" ]; then
    echo "la fila 14.3 no existe en el ledger"; return 1
  fi
  if printf '%s\n' "$fila" | grep -Fq 'date -u +%Y-%m-%dT%H:%M:%SZ'; then
    echo "la fila 14.3 ensena como comando un timestamp con dos puntos (invalido en un filename de Windows)"; return 1
  fi
  if ! printf '%s\n' "$fila" | grep -Fq 'date -u +%Y%m%dT%H%M%SZ'; then
    echo "la fila 14.3 no nombra la forma Windows-safe (date -u +%Y%m%dT%H%M%SZ)"; return 1
  fi
  return 0
}

perfil="$repo/agents/adversary.md"
reviewer="$repo/agents/reviewer.md"
plans="$repo/Plans.md"
# El ledger es Plans.md MAS su archivo: la higiene del tope de 200 lineas mueve
# fases cerradas a docs/plans-archivo.md (Phase 14 movida el 2026-08-28), y una
# ancla que solo mira Plans.md se pone roja por un archivado legitimo (PR #95).
archivo="$repo/docs/plans-archivo.md"

caso "el perfil documenta la forma del contrato (claves exactas)"
if [ -r "$perfil" ]; then
  for k in '"role"' '"attacked"' '"findings"' '"severity"' '"location"' '"claim"' '"trigger"' '"evidence"' '"confirmed"'; do
    grep -Fq "$k" "$perfil" || malo "el perfil no documenta la clave del contrato $k"
  done
  # (CodeRabbit, PR #72) no alcanza con que las claves aparezcan sueltas: el
  # perfil tiene que declarar el esquema como contrato EXACTO y la estructura.
  grep -Fq 'Use exactly the keys below' "$perfil" || malo "el perfil no declara el esquema como contrato exacto"
  grep -Fq 'findings[]' "$perfil" || malo "el perfil no documenta la estructura findings[]"
  grep -Fq 'Do NOT invent a different shape' "$perfil" || malo "el perfil no prohibe una forma distinta"
else
  echo "  UNKNOWN: no se puede leer agents/adversary.md" >&2; unknown=1
fi

caso "el timestamp del perfil es WINDOWS-SAFE (sin ':' en el comando)"
if [ -r "$perfil" ]; then
  # El timestamp va en el FILENAME; en Windows ':' es ilegal en un filename. La
  # forma ENSEÑADA tiene que ser SIN dos puntos (date -u +%Y%m%dT%H%M%SZ). El
  # anti-patrón solo se menciona para explicar por qué NO (parentesis), nunca
  # como comando a correr: por eso se detecta el COMANDO con dos puntos
  # `date -u +%Y-%m-%dT%H:%M:%SZ`, no la mera cadena %H:%M:%S.
  if grep -Fq 'date -u +%Y-%m-%dT%H:%M:%SZ' "$perfil"; then
    malo "el perfil enseña como comando un timestamp con dos puntos (invalido en un filename de Windows)"
  fi
  grep -Fq 'date -u +%Y%m%dT%H%M%SZ' "$perfil" || malo "el perfil no enseña la forma Windows-safe (date -u +%Y%m%dT%H%M%SZ)"
  # Regla "se OBTIENE con Bash o se OMITE — jamas se inventa" (CodeRabbit, PR #72):
  # las dos mitades tienen que estar escritas, no solo la forma del comando.
  grep -Fq 'OMIT the timestamp' "$perfil" || malo "el perfil no enseña la omision honesta del timestamp (sin Bash, se omite)"
  grep -Fq 'NEVER invent a timestamp' "$perfil" || malo "el perfil no prohibe inventar el timestamp"
else
  echo "  UNKNOWN: no se puede leer agents/adversary.md" >&2; unknown=1
fi

caso "el reviewer declara MALFORMADO un esquema no contrato"
if [ -r "$reviewer" ]; then
  grep -Eiq 'malform' "$reviewer" || malo "el reviewer no declara malformado"
  grep -Fq 'generated_at_utc' "$reviewer" || malo "el reviewer no cubre el esquema ajeno (campo 'generated_at_utc')"
  # (CodeRabbit, PR #72) cada regla de artefacto malformado documentada, por su
  # forma: title/detail, attacked ausente, ilegible, y artefacto inexistente.
  grep -Fq '`title`/`detail`' "$reviewer" || malo "el reviewer no cubre el esquema title/detail"
  grep -Fq 'missing `attacked`' "$reviewer" || malo "el reviewer no cubre el attacked ausente"
  grep -Fiq 'unreadable' "$reviewer" || malo "el reviewer no cubre el artefacto ilegible"
  grep -Fq 'no artifact exists' "$reviewer" || malo "el reviewer no cubre el artefacto inexistente"
else
  echo "  UNKNOWN: no se puede leer agents/reviewer.md" >&2; unknown=1
fi

# ---------------------------------------------------------------- sinteticos
# El detector se ejercita contra fixtures del sandbox ANTES de mirar el ledger
# real: sin estos casos, un `grep` sobre el ledger entero pasaba con un ejemplo
# seguro en cualquier otra fila (CodeRabbit, PR #95).
caso "sintetico: fila 14.3 con la forma segura => OK"
f="$SANDBOX/ok.md"
printf '| 14.3 | perfil con `date -u +%%Y%%m%%dT%%H%%M%%SZ` | DoD | — | cc:完了 |\n' > "$f"
out="$(chequear_fila_143 "$f")" || malo "fila segura rechazada: $out"

caso "sintetico: ledger SIN fila 14.3 pero con un ejemplo seguro suelto en otra fila => FAIL"
f="$SANDBOX/sin-fila.md"
printf '| 14.2 | otra fila que cita `date -u +%%Y%%m%%dT%%H%%M%%SZ` de paso | DoD | — | cc:完了 |\n' > "$f"
if chequear_fila_143 "$f" >/dev/null; then malo "acepto un ledger sin fila 14.3 por un ejemplo seguro en otra fila"; fi

caso "sintetico: fila 14.3 insegura + ejemplo seguro en un apendice => FAIL"
f="$SANDBOX/insegura.md"
{
  printf '| 14.3 | perfil con `date -u +%%Y-%%m-%%dT%%H:%%M:%%SZ` | DoD | — | cc:完了 |\n'
  printf 'Apendice: la forma buena seria `date -u +%%Y%%m%%dT%%H%%M%%SZ`.\n'
} > "$f"
if chequear_fila_143 "$f" >/dev/null; then malo "acepto una fila 14.3 insegura por un ejemplo seguro fuera de la fila"; fi

caso "sintetico: la fila 14.3 vive en el ARCHIVO, no en Plans.md => OK (el ledger es Plans.md + archivo)"
f1="$SANDBOX/plans-sin.md"; f2="$SANDBOX/archivo-con.md"
printf '| 16.1 | fila reciente | DoD | — | cc:WIP |\n' > "$f1"
printf '| 14.3 | archivada con `date -u +%%Y%%m%%dT%%H%%M%%SZ` | DoD | — | cc:完了 |\n' > "$f2"
out="$(chequear_fila_143 "$f1" "$f2")" || malo "no encontro la fila 14.3 en el archivo: $out"

# ------------------------------------------------------------ el ledger real
caso "la fila 14.3 del ledger real (Plans.md o su archivo) usa el timestamp Windows-safe (sin ':' en el comando)"
ledger_files=()
[ -r "$plans" ] && ledger_files+=("$plans")
[ -r "$archivo" ] && ledger_files+=("$archivo")
# Array, no string: un checkout en una ruta con espacios partiria la lista
# (cross-review codex, PR #95, hallazgo 8).
if [ "${#ledger_files[@]}" -gt 0 ]; then
  out="$(chequear_fila_143 "${ledger_files[@]}")" || malo "$out (Plans.md o docs/plans-archivo.md)"
else
  echo "  UNKNOWN: no se puede leer Plans.md ni docs/plans-archivo.md" >&2; unknown=1
fi

if [ "$fail" -ne 0 ]; then
  echo "test_adversary_artifact_contract: FAIL" >&2
  exit 1
fi
if [ "$unknown" -ne 0 ]; then
  echo "test_adversary_artifact_contract: UNKNOWN" >&2
  exit 3
fi
echo "test_adversary_artifact_contract: OK"
