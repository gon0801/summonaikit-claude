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

fail=0
unknown=0
malo() { printf '    FAIL: %s\n' "$1" >&2; fail=1; }
caso() { printf '  caso: %s\n' "$1"; }

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

caso "la fila 14.3 del ledger (Plans.md o su archivo) usa el timestamp Windows-safe (sin ':' en el comando)"
ledger_files=""
[ -r "$plans" ] && ledger_files="$plans"
[ -r "$archivo" ] && ledger_files="$ledger_files $archivo"
if [ -n "$ledger_files" ]; then
  # shellcheck disable=SC2086  # lista de rutas sin espacios, a proposito
  if cat $ledger_files | grep -Fq 'date -u +%Y-%m-%dT%H:%M:%SZ'; then
    malo "el ledger (fila 14.3) enseña como comando un timestamp con dos puntos (invalido en un filename de Windows)"
  fi
  # (CodeRabbit, PR #72) ademas de rechazar la forma insegura, exigir la segura.
  # shellcheck disable=SC2086
  cat $ledger_files | grep -Fq 'date -u +%Y%m%dT%H%M%SZ' || malo "el ledger (fila 14.3, Plans.md o docs/plans-archivo.md) no nombra la forma Windows-safe (date -u +%Y%m%dT%H%M%SZ)"
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
