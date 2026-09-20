#!/usr/bin/env bash
# Active instructions must not reintroduce obsolete review limits.
set -eu
cd "$(dirname "$0")/.."
python3 - <<'PY'
from pathlib import Path

paths = ('AGENTS.md', 'CLAUDE.md', 'recetas/cuidar-pr.md', 'recetas/00-lider.md', 'agents/reviewer.md')
obsolete = ('Cross-review: tope 1 ronda', 'Jamas una tercera',
            'máximo **2 rondas**', 'Claude = lead')
def invalid(text):
    return [rule for rule in obsolete if rule in text]

for rule in obsolete:
    assert invalid('Instrucción activa: ' + rule), rule
for path in paths:
    text = Path(path).read_text()
    assert not invalid(text), (path, invalid(text))
assert 'Revisión: política única' in Path('AGENTS.md').read_text()
assert 'autorización vigente' in Path('recetas/00-lider.md').read_text()
assert 'transitorio' in Path('agents/reviewer.md').read_text()
print('PASS: instrucciones sin topes caducos ni autoridad de modelo fija')
PY
