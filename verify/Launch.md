# Launch — como arranca la app

Esta app son herramientas bash y un hook; no levanta un servidor ni abre un
puerto. Desde la raiz del repo, con el entorno de Doctor.md listo:

```bash
pytest verify/
```

Cada test crea un HOME desechable, tambien usado como USERPROFILE, y un TMPDIR
propio. Descarta overrides heredados de SAIKIT y de los hosts. El test del gate
copia `hooks/summonaikit-harness.sh` y solo los escenarios `01-sin-armar` y
`02-armado-contrato` a ese sandbox. El harness vuelve a copiar el hook por
escenario y ejecuta cada payload con otro HOME aislado.

Para ver la grabacion del gate a mano, este bloque completo se corre desde la
raiz en bash. Crea y limpia su propio sandbox, incluso si un comando falla:

```bash
bash -eu <<'BASH'
verify_repo="$PWD"
for verify_var in "${!SAIKIT_@}" "${!SUMMONAIKIT_@}" "${!CLAUDE@}" \
  "${!GROK_@}" "${!DSH_@}" "${!ZCODE_@}" "${!CODEX_@}"; do
  if [ -n "$verify_var" ]; then unset "$verify_var"; fi
done
verify_sandbox="$(mktemp -d "${TMPDIR:-/tmp}/saikit-verify-XXXXXX")"
trap 'rm -rf -- "$verify_sandbox"' EXIT
mkdir -p "$verify_sandbox/home" "$verify_sandbox/tmp" \
  "$verify_sandbox/hooks" "$verify_sandbox/escenarios"
cp "$verify_repo/hooks/summonaikit-harness.sh" "$verify_sandbox/hooks/"
cp -R "$verify_repo/tests/fixtures/escenarios/01-sin-armar" \
  "$verify_repo/tests/fixtures/escenarios/02-armado-contrato" \
  "$verify_sandbox/escenarios/"
env HOME="$verify_sandbox/home" USERPROFILE="$verify_sandbox/home" \
  TMPDIR="$verify_sandbox/tmp" \
  bash "$verify_repo/tools/golden-harness.sh" --print \
    --hook "$verify_sandbox/hooks/summonaikit-harness.sh" \
    --scenarios "$verify_sandbox/escenarios"
BASH
```

`--print` graba el comportamiento; su exit 0 por si solo no lo aprueba. El Drive
verifica que unarmed no emita contrato ni cree estado en ninguno de sus tres
pasos, y que armed inyecte el contrato y deje `harness-state.env`.

Siempre pasar `--hook` con la copia desechable: por defecto `--print` elige el
hook del perfil. Nunca ejecutar ni instalar en los perfiles reales
`~/.claude`, `~/.grok`, `~/.dsh` o `~/.codex`. El instalador solo se ejercita
con `--dry-run` y HOME aislado; este Launch no requiere instalar el gate.
