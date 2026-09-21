#!/usr/bin/env bash
# Active instructions must not reintroduce obsolete review limits.
set -eu
cd "$(dirname "$0")/.."
python3 - <<'PY'
from pathlib import Path

paths = ('AGENTS.md', 'CLAUDE.md', 'Plans.md', 'docs/spec/00-project-spec.md',
         'recetas/cuidar-pr.md', 'recetas/00-lider.md', 'agents/reviewer.md')
obsolete = ('Cross-review: tope 1 ronda', 'Jamas una tercera',
            'máximo **2 rondas**', 'Una ronda de revisión por bloque',
            'tope de 1 ronda: un', 'Claude = lead')
def invalid(text):
    normalized = ' '.join(text.split())
    return [rule for rule in obsolete if rule in normalized]

for rule in obsolete:
    assert invalid('Instrucción activa: ' + rule), rule
assert invalid('Una ronda\nde revisión por bloque')
for path in paths:
    text = Path(path).read_text()
    assert not invalid(text), (path, invalid(text))
assert 'Una sola politica de rondas' in Path('AGENTS.md').read_text()
assert 'autorización vigente' in Path('recetas/00-lider.md').read_text()
assert 'El recibo de entrega' in Path('agents/reviewer.md').read_text()
assert 'no escribes ningún archivo de veredicto' in Path('agents/reviewer.md').read_text()
print('PASS: instrucciones sin topes caducos ni autoridad de modelo fija')
PY
