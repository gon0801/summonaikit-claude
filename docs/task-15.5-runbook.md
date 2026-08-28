# Runbook — Task 15.5: turno vivo de dsh (DeepSeek Harness)

Documenta el procedimiento para ejecutar y capturar el **turno vivo** del gate en
dsh y completar las partes de la Task 15.5 que dependen de ese turno (el deploy
anotado en `docs/deploy-log.md` y la evidencia en `docs/smoke-dsh-<fecha>.md`).

> **Estado:** la sección de documentación de 15.5 (spec § Host dsh, README, fila
> de `agents/adversary.md`) ya está escrita y es coherente con lo que el
> instalador hace. Este runbook es el paso que falta para la evidencia real.
> **Precondición dura:** la rama `HOST=dsh` del hook (Task 15.2 / PR #85) debe
> estar **mergeada** — sin ella el hook corre como `other` y la ceremonia de
> secuencia no se exige. Verificar antes de empezar:

```bash
git show origin/master:hooks/summonaikit-harness.sh | grep -n 'HOST=dsh'
# debe listar la rama elif [ "${SUMMONAIKIT_HOOK_TARGET:-}" = "dsh" ]
```

## 1) Deploy (después de mergear 15.2 + 15.4 a master)

```bash
# Sincronizar master y desplegar el gate de dsh
git checkout master && git pull --ff-only
bash tools/install-hook.sh --host dsh
bash tools/check-hook-registration.sh --dsh-home ~/.dsh   # SILENCIO esperado
dsh --dump-config 2>&1 | grep summonaikit-gate            # debe aparecer el plugin
```

Esperado: hook en `~/.dsh/hooks/`, adaptador en
`~/.dsh/profiles/node_modules/@summonaikit/dsh-gate/` (el flat module fallback de
dsh — ahí es donde dsh resuelve los plugins custom por nombre; se copia como dir
real, no symlink), entrada del patch en `~/.dsh/cordis.patch.yml` (bloque entre
marcas con el gate `name: '@summonaikit/dsh-gate'` + las 4 personas
`subagent_<rol>`).

## 2) Turno vivo en la UI web de dsh

Sobre un repo desechable (p. ej. una copia con un `app.py`), tres escenarios,
cada uno con el transcript guardado:

1. **`-saikit agrega un docstring a app.py`** → debe aparecer el contrato
   (`SUMMONAIKIT HARNESS REQUIRED`), el lead delega por la tool
   `subagent_<rol>` (implementer, verifier, reviewer) y el recibo cierra.
   Anotar: ¿apareció el contrato? ¿los roles se registraron? ¿el recibo cerró?
2. **Cerrar SIN recibo** → el turno debe volver con `SUMMONAIKIT HARNESS GATE`
   y seguir hasta que aparezca el recibo.
3. **Sin `-saikit`** → nada del harness debe aparecer (byte-idéntico a un dsh
   sin el plugin).

Para capturar: reusar el **plugin espía** de la Task 15.1
(`hosts/dsh/spy/`, composición en un profile desechable) si se quiere el JSONL
de eventos; o el transcript de la UI. Guardar los 3 transcripts como evidencia.

## 3) Spec / perfil / README — ya escritos

La spec § Host dsh, el README (fila dsh + cómo se instala) y la fila de
`agents/adversary.md` ya están en esta rama. **Revisar** que sigan siendo
coherentes con lo que se mida en el turno (en particular el `unknown` de la forma
exacta del `source:{kind:"plugin"}` y si el candado anti-fuga de
`.saikit/findings/` funciona en dsh como el adaptador asume).

## 4) Deploy-log

Después del deploy + turno, anotar en `docs/deploy-log.md`: fecha, sha del hook,
salida del checker (silencio), versión de dsh, y qué pasó en los 3 escenarios.

## 5) Commit + PR

`docs(15.5): turno vivo de dsh, spec § host dsh, perfil por host, deploy anotado`.

---

### Coherencia con lo ya documentado (para no re-auditar)

- Personas = instancias `dsh-tool-subagent` con `config.persona` inline (no
  archivos de persona — dsh no los tiene; medido contra el fuente de 15.1).
- El `--dsh-home` del checker valida hook + plugin (4 archivos) + bloque del
  patch (id del gate, name del plugin, hook:, 4 roles con persona:).
- La fila `dsh` del router está vacía (hereda el modelo de la sesión).
- dsh no entra en la lista de ciegos (`saikit_host_ciego()` no cambia): el canal
  interno (tools/*) deja rastro — **pendiente de confirmar en el turno vivo**.
