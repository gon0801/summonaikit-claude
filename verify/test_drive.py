# Drive e2e de superficie de usuario: la app como la ve el usuario, NO sus
# internos. Se corre con el COMANDO_DRIVE del Drive.md. Reutiliza el framework
# de test que el repo YA tiene (pytest) y lo apunta SOLO a `verify/`; NO es la
# suite unitaria del repo.
#
# La superficie de usuario de ESTA app es su linea de comandos (herramientas
# bash bajo tools/). Cada test usa una herramienta como la usaria el operador.
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

import pytest

app_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


@pytest.fixture(autouse=True)
def sandbox(monkeypatch):
    # Todos los CLI reciben un HOME desechable, incluso el instalador en seco.
    # Quitar overrides heredados evita leer perfiles o fixtures del operador.
    with tempfile.TemporaryDirectory(prefix='saikit-drive-') as temporal:
        raiz = Path(temporal).resolve()
        for nombre in ('home', 'tmp'):
            (raiz / nombre).mkdir()
        for nombre in tuple(os.environ):
            if nombre.startswith(('SAIKIT_', 'SUMMONAIKIT_', 'CLAUDE',
                                  'GROK_', 'DSH_', 'ZCODE_', 'CODEX_')):
                monkeypatch.delenv(nombre)
        monkeypatch.setenv('HOME', str(raiz / 'home'))
        monkeypatch.setenv('USERPROFILE', str(raiz / 'home'))
        monkeypatch.setenv('TMPDIR', str(raiz / 'tmp'))
        yield raiz


def corre(*args):
    if args[0] == 'tools/golden-harness.sh':
        # Validar el argumento que realmente se ejecutara, no solo la copia.
        assert '--hook' in args, 'golden-harness exige --hook explicito'
        hook = Path(args[args.index('--hook') + 1]).resolve()
        raiz = Path(os.environ['HOME']).resolve().parent
        assert hook.is_relative_to(raiz), 'el hook debe estar en el sandbox'
    return subprocess.run(['bash'] + list(args), cwd=app_root,
                          capture_output=True, text=True, timeout=60)


def test_el_gate_sin_armar_y_armado(sandbox):
    # Unarmed que crea estado, armed sin contrato/estado, o cobertura recortada
    # deben fallar aunque golden-harness --print haya devuelto exit 0.
    fuente = Path(app_root) / 'hooks/summonaikit-harness.sh'
    hook = sandbox / 'hooks/summonaikit-harness.sh'
    assert hook.resolve().is_relative_to(sandbox), 'el hook debe estar en el sandbox'
    hook.parent.mkdir()
    shutil.copyfile(fuente, hook)
    escenarios = sandbox / 'escenarios'
    escenarios.mkdir()
    for nombre in ('01-sin-armar', '02-armado-contrato'):
        shutil.copytree(Path(app_root) / 'tests/fixtures/escenarios' / nombre,
                        escenarios / nombre)

    r = corre('tools/golden-harness.sh', '--print', '--hook', str(hook),
              '--scenarios', str(escenarios))
    assert r.returncode == 0, r.stdout + r.stderr
    assert not r.stderr, r.stderr
    sha = hashlib.sha256(fuente.read_bytes()).hexdigest()
    assert f'# hook_sha256: {sha}\n' in r.stdout, 'no se midio el hook fuente'
    bloques = re.split(r'^=== escenario ', r.stdout, flags=re.MULTILINE)[1:]
    nombres = [bloque.splitlines()[0] for bloque in bloques]
    assert nombres == ['01-sin-armar', '02-armado-contrato'], nombres
    sin_armar, armado = bloques

    pasos = re.split(r'^--- paso ', sin_armar, flags=re.MULTILINE)[1:]
    assert [paso.split()[0] for paso in pasos] == ['01', '02', '03']
    assert '--- estado tras el paso 01\n(sin estado)' in pasos[0]
    for paso in pasos:
        assert '\nexit 0\nstdout <vacio>\nstderr <vacio>\n' in paso, paso
        assert paso.strip().endswith(('(sin estado)', 'estado sin cambios')), paso
        assert not re.search(r'^hooks/', paso, re.MULTILINE), paso

    pasos = re.split(r'^--- paso ', armado, flags=re.MULTILINE)[1:]
    assert len(pasos) == 1, armado
    paso = pasos[0]
    assert paso.startswith('01  phase=prompt target=claude '), paso
    assert '\nexit 0\nstdout (sha ' in paso, paso
    salida, estado = paso.split('\nstderr <vacio>\n--- estado tras el paso 01\n')
    contrato = json.loads('\n'.join(linea[2:] for linea in salida.splitlines()
                                    if linea.startswith('| ')))
    contexto = contrato['hookSpecificOutput']
    assert contexto['hookEventName'] == 'UserPromptSubmit'
    assert contexto['additionalContext'].startswith('SUMMONAIKIT HARNESS REQUIRED')
    assert re.search(r'^hooks/state/<PROJECT_KEY>/[^/\n]+/harness-state\.env$',
                     estado, re.MULTILINE), estado
    assert re.search(r'^\| task_hash=[0-9]+$', estado, re.MULTILINE), estado


def test_instalar_en_seco_responde():
    # "Instalar o actualizar el guardian" — en seco: dice que haria, no escribe.
    r = corre('tools/install-hook.sh', '--dry-run')
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip(), 'el dry-run no produjo salida'


def test_la_libreta_de_tareas_esta_al_dia():
    # "Revisar que la libreta de tareas este al dia".
    r = corre('tools/audita-ledger.sh')
    assert r.returncode == 0, r.stdout + r.stderr
    assert 'AUDITORIA DEL LEDGER' in r.stdout


def test_el_registro_de_deploys_es_valido():
    # "Revisar el registro de puestas en produccion".
    r = corre('tools/check-deploy-log.sh')
    assert r.returncode == 0, r.stdout + r.stderr


def test_el_estado_del_mapa_se_reporta():
    # "Generar este mapa y la prueba de la app" — el estado sale por stdout.
    r = corre('skills/saikit-verificar-app/verificar.sh', 'estado', app_root)
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip().split()[0] in (
        'al_dia', 'desactualizado', 'viejo', 'unknown', 'sin_mapa'), r.stdout
