# Drive e2e de superficie de usuario: la app como la ve el usuario, NO sus
# internos. Se corre con el COMANDO_DRIVE del Drive.md. Reutiliza el framework
# de test que el repo YA tiene (pytest) y lo apunta SOLO a `verify/`; NO es la
# suite unitaria del repo.
#
# La superficie de usuario de ESTA app es su linea de comandos (herramientas
# bash bajo tools/). Cada test usa una herramienta como la usaria el operador.
import os
import subprocess

app_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def corre(*args):
    return subprocess.run(['bash'] + list(args), cwd=app_root,
                          capture_output=True, text=True)


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
