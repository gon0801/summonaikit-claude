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

caso "el perfil documenta la forma del contrato (claves exactas)"
if [ -r "$perfil" ]; then
  for k in '"role"' '"attacked"' '"findings"' '"severity"' '"location"' '"claim"' '"trigger"' '"evidence"' '"confirmed"'; do
    grep -Fq "$k" "$perfil" || malo "el perfil no documenta la clave del contrato $k"
  done
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
else
  echo "  UNKNOWN: no se puede leer agents/adversary.md" >&2; unknown=1
fi

caso "el reviewer declara MALFORMADO un esquema no contrato"
if [ -r "$reviewer" ]; then
  grep -Eiq 'malform' "$reviewer" || malo "el reviewer no declara malformado"
  grep -Fq 'generated_at_utc' "$reviewer" || malo "el reviewer no cubre el esquema ajeno (campo 'generated_at_utc')"
else
  echo "  UNKNOWN: no se puede leer agents/reviewer.md" >&2; unknown=1
fi

caso "Plans.md fila 14.3 usa el timestamp Windows-safe (sin ':' en el comando)"
if [ -r "$plans" ]; then
  if grep -Fq 'date -u +%Y-%m-%dT%H:%M:%SZ' "$plans"; then
    malo "Plans.md (fila 14.3) enseña como comando un timestamp con dos puntos (invalido en un filename de Windows)"
  fi
else
  echo "  UNKNOWN: no se puede leer Plans.md" >&2; unknown=1
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
