# Cleanup — como dejar todo como estaba

El Drive no deja servidores ni procesos en segundo plano. Cada fixture usa
`TemporaryDirectory`: al terminar el test, incluso si falla una asercion, borra
su copia del hook, escenarios, HOME y TMPDIR. `monkeypatch` restaura las
variables de entorno. El harness tambien tiene un trap EXIT que elimina su
sandbox por escenario; el bloque manual de Launch.md limpia su temporal al
salir.

Si se preparo el venv opcional de Doctor.md, desactivarlo y borrar solo ese
directorio creado para la prueba:

```bash
deactivate
case "${verify_venv:-}" in
  "${TMPDIR:-/tmp}"/saikit-drive-venv-??????)
    test -f "$verify_venv/pyvenv.cfg" && rm -rf -- "$verify_venv"
    ;;
  *) printf '%s\n' 'No se borra: ruta de venv no reconocida.' ;;
esac
unset verify_venv
```

Una terminacion forzada del proceso puede impedir los traps. En ese caso,
identificar primero el temporal exacto `saikit-drive-*` o `saikit-verify-*`
de esa corrida y confirmar que ningun proceso lo usa. No borrar por un glob
amplio: puede haber otras sesiones trabajando. Las caches locales de pytest
(`.pytest_cache/`, `verify/__pycache__/`) se pueden conservar.

Conservar `verify/Evidence.txt`, las guias, el test y el sello de `LEEME.md`:
son la entrega, no basura temporal. Conservar tambien
`.cursor/skills/verify-summonaikit/` y sus artefactos; su feature map es
complementario. No hay nada que desinstalar en `~/.claude`, `~/.grok`,
`~/.dsh` ni `~/.codex`: las mediciones nunca deben tocar esos perfiles vivos.
