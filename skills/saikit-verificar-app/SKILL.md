---
name: saikit-verificar-app
description: Arma y corre un `verify/` en el repo del usuario: un mapa en español de 3 a 5 funciones de la app y un Drive e2e que la prueba como la usa un usuario (no sus internos). Usar cuando haya que "verificar la app", "dejar la prueba de la app", o antes de cerrar una tarea que toca superficie de usuario.
saikit_owned: summonaikit-claude
---

# verificar-app

Deja en el repo del usuario un `verify/` que se pueda volver a correr y que un
humano entienda sin leer código. Se corre UNA vez antes de entregar.

## 1. Generar el `verify/`

```
bash <directorio_de_esta_skill>/verificar.sh generar <repo>
```

El generador escribe `verify/` con `LEEME.md` (sello `generado: <fecha> · <sha>`
en el frontmatter), `Launch.md`, `Doctor.md`, `Drive.md`, `Evidence.txt` y
`Cleanup.md`. **El sello es el compromiso**: un mapa viejo describe una app que
ya no existe y da confianza falsa. Por eso:

- **Si la salida dice `PROPONGO: ...`**, el repo NO tiene framework de test
  configurado. El `verify/` quedó con el Drive "manual, pendiente" y
  `verify_app: n/a`, y **no se instaló nada**. Preguntale al usuario en
  palabras simples si quiere que instales el framework propuesto. **Instalalo
  SOLO con su sí explícito**, con versión pinneada (en el lockfile del repo),
  **nunca `npx <pkg>@latest`**. Si no acepta, dejá el Drive manual/pendiente y
  `verify_app: n/a` — un `n/a` honesto vale más que un Drive inventado. En
  autopilot, `n/a` solo autoriza el merge si el usuario aceptó `sin_verify_app`.
- **Si la salida dice `GENERADO: ... con Drive acreditable (...)`**, el repo ya
  tiene framework y el Drive quedó listo para completar.

## 2. Completar el mapa (LEEME.md)

El generador deja `LEEME.md` con un lugar para completar. Leé la app y escribí
**3 a 5 funciones principales, en español**, para alguien que no lee código
(p.ej. "entrar", "crear X", "ver la lista", "cerrar sesión"). No describas
internos ni nombres de archivo.

## 3. Completar el Drive (la prueba de superficie)

El `Drive.md` trae el `COMANDO_DRIVE` y el archivo de test e2e bajo `verify/`
(`drive.test.js` para node, `test_drive.py` para pytest). **El Drive ejercita la
superficie de usuario — la app como la usa un usuario (CLI o navegador) —, no los
internos.** Reglas que no se aflojan:

- El comando de Drive **incluye la ruta `verify/`** y lo acredita `TEST_RUNNER_RE`
  (lo lee el generador del hook; por eso `node --test` solo se envuelve como
  `npm test -- verify/`).
- **La suite unitaria del repo NO es el Drive.** Si el comando corriera la suite
  del repo y no el `verify/`, no cuenta.
- Completá los `_ENTRADA_` y los `test(...)` con lo que la app realmente responde.
  El esqueleto ya lanza la app; agregá las funciones del mapa con su salida
  esperada. Si no podés completar algo con honestidad, dejalo pendiente y
  declaralo.

Después corré el Drive una vez (antes de entregar) y pegá la salida en
`Evidence.txt`.

## 4. Reportar el estado del mapa

```
bash <directorio_de_esta_skill>/verificar.sh estado <repo>
```

Devuelve `al_dia` | `desactualizado` | `viejo` | `unknown` | `sin_mapa`.
**Sin el sello `generado:` en el frontmatter de `LEEME.md` SIEMPRE dice `unknown`,
nunca "al día".** Reportá en el recibo el estado y, si no es `al_dia`, la
antigüedad: un mapa viejo no comprueba que la app siga siendo la que describe,
solo avisa que envejeció.

## Qué NO hacer

- No instales nada sin el sí explícito del usuario; nunca `@latest`; siempre
  pinneado.
- No inventes un Drive ni funciones del mapa: lo que no queda comprobado se
  declara pendiente.
- No regrabes un `verify/LEEME.md` que ya existe (el generador se niega): la
  skill corre una vez.
- El repo necesita al menos un commit (git) para sellar el mapa. Si no es un
  repo git, avisá y no generes un mapa sin sello: un mapa sin `generado:` es
  `unknown`, no confianza.
