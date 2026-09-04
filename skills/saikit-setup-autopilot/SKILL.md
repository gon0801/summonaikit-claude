---
name: saikit-setup-autopilot
description: Prepara un repo para el autopilot con 5 preguntas en español (¿mergear solo?, ¿publica la app?, ¿URL de salud?, ¿sin prueba mergeo?, ¿aviso por Telegram?). Usar cuando el operador pida "prepara el autopilot", "configura el merge" o antes del primer turno con -saikit:autopilot en un repo nuevo.
saikit_owned: summonaikit-claude
---

# Preparar el autopilot de un repo

Corre el asistente en el repo del usuario y compromete su respuesta:

```
bash tools/saikit-setup-autopilot.sh
```

Hace 5 preguntas en español, una por una, y escribe `.saikit/autopilot.json`
(`merge`, `merge_despliega` que nace `unknown`, `salud_url`, `sin_verify_app`
y `telegram` que nacen en falso, `rama` y `revert_si_rojo` con default).
También toma el lock del repo y asegura el `.gitignore` de `veredictos/`.

## Lo que el operador tiene que saber

- Sin commitear y pushear a `origin/<rama>`, el setup no existe: el merge lee
  la config de ahí, nunca del disco. Dile que haga commit + push.
- `merge_despliega: unknown` (nadie contestó) NO mergea: es distinto de "no".
- Un solo setup a la vez por repo (lock compartido entre worktrees). Si otro
  lo tiene, se reporta y se espera; solo `--liberar-lock` lo quita a mano.
- Cada respuesta también llega por flag (`--merge si`, `--despliega no`,
  `--salud-url -`, `--sin-verify-app no`, `--telegram no`, `--rama master`,
  `--pr 7`); con todas por flag no pregunta nada.
