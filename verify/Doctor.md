# Doctor — como saber que el entorno esta sano

Desde la raiz del repo, comprobar las herramientas locales:

```bash
command -v bash git python3 pytest mktemp sha256sum cksum \
  awk sed grep find sort cut tr wc tail head cmp cp env date
python3 --version
pytest --version
bash -n tools/golden-harness.sh
bash -n hooks/summonaikit-harness.sh
git rev-parse --show-toplevel
git rev-parse --verify origin/master
git rev-parse --is-shallow-repository
test -r tests/fixtures/escenarios/01-sin-armar/01.prompt.claude.json
test -r tests/fixtures/escenarios/01-sin-armar/02.tool.claude.json
test -r tests/fixtures/escenarios/01-sin-armar/03.stop.claude.json
test -r tests/fixtures/escenarios/02-armado-contrato/01.prompt.claude.json
```

Se necesita Python 3.9 o posterior y pytest (medido con pytest 8.4.2). En macOS,
`sha256sum` viene de coreutils. No se necesita una IA conectada, credenciales,
base de datos ni perfiles instalados. La auditoria del ledger necesita
`origin/master` y un clon completo: el ultimo comando de git debe dar `false`.
Sin esa referencia o en un clon shallow, la auditoria sale 3 (`unknown`);
eso no cuenta como PASS.

Si falta pytest, preparar un venv desechable sin instalar paquetes globales:

```bash
verify_venv="$(mktemp -d "${TMPDIR:-/tmp}/saikit-drive-venv-XXXXXX")"
python3 -m venv "$verify_venv"
. "$verify_venv/bin/activate"
python -m pip install pytest==8.4.2
pytest --version
```

La instalacion de dependencias requiere acceso al indice de paquetes; correr
el Drive luego es local. Con el venv activo, `pytest verify/` es el comando de
Drive.md. No hace falta generar un `pytest.ini` ni desactivar la configuracion
del repo. Si pytest no puede recolectar los tests, resolver ese error antes de
afirmar cobertura.

El aislamiento es automatico en `test_drive.py`: HOME y USERPROFILE apuntan a
`home/` del temporal y TMPDIR a `tmp/`. El gate exige un `--hook` explicito
dentro del sandbox antes de invocar el harness. Para una corrida manual usar
el bloque completo de Launch.md; no exportar el HOME real como destino de
medicion y nunca apuntar a `~/.claude`, `~/.grok`, `~/.dsh` o `~/.codex`.

Exito esperado: cinco tests aprobados, incluidos ambos escenarios del gate.
Una asercion fallida es FAIL, aunque el CLI haya salido 0. El Drive es acotado;
la bateria completa y el job agregado `gate` corresponden al CI del PR.
