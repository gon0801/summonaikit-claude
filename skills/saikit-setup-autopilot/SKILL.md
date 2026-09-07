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

Si el repo no tiene workflows de Actions, **después** de las 5 (no es una
pregunta 6/6 del JSON) ofrece un workflow mínimo (`saikit-ci-minimo.yml`)
que corre el test del repo y `verify/`. Sin terminal asume `no` y avisa
que sin CI el autopilot no mergea. Quien ya sabe que lo quiere pasa
`--ci-minimo si`.

## Actualizar los pins de las actions

El workflow mínimo usa actions pineadas por SHA de commit (el tag vive al
lado, en `PIN_*_TAG`, solo como referencia). Mantenimiento:

```
bash tools/bump-ci-pins.sh --check            # 0 = al día, 1 = obsoleto, 2 = no pudo consultar
bash tools/bump-ci-pins.sh --proponer actions/checkout v4.3.0
```

`--check` compara cada pin contra GitHub (o contra un fixture local con
`--fuente <archivo>` de líneas `owner/repo tag sha`); si no hay red sale 2
declarando que no pudo mirar, nunca inventa «al día». `--proponer` resuelve
el SHA real del tag e **imprime un diff para revisar y aplicar a mano**:
no escribe el generador ni ningún workflow, y el pin resultante sigue
siendo SHA — un tag flotante (`@v4`) no se adopta jamás.

## Lo que el operador tiene que saber

- Sin commitear y pushear a `origin/<rama>`, el setup no existe: el merge lee
  la config de ahí, nunca del disco. Si aceptó el CI mínimo, el commit tiene
  que incluir también `.github/workflows/saikit-ci-minimo.yml`; sin eso Actions
  no dispara y el merge sigue en `sin checks`.
- `merge_despliega: unknown` (nadie contestó) NO mergea: es distinto de "no".
- Un solo setup a la vez por repo (lock compartido entre worktrees). Si otro
  lo tiene, el comando lo reporta y sale con código 3 SIN esperar: el operador
  libera con `--liberar-lock` o reintenta cuando el otro termine.
- Cada respuesta también llega por flag (`--merge si`, `--despliega no`,
  `--salud-url -`, `--sin-verify-app no`, `--telegram no`, `--rama master`,
  `--pr 7`, `--ci-minimo si|no`); con las 5 de config por flag no pregunta
  esas. El offer de CI es aparte: `--ci-minimo` no entra al JSON.
