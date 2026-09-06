# Drive — como probar la app como usuario

El Drive corre la app por su superficie de usuario (e2e) bajo `verify/`, en el
framework que el repo YA tiene. NO es la suite unitaria del repo.

COMANDO_DRIVE: pytest verify/
ESTADO_DRIVE: drive

Desde la raiz, con pytest disponible segun Doctor.md. Son cinco tests: el gate
(ambos escenarios golden, copia del hook y HOME aislado), instalacion en seco,
auditoria del ledger, registro de deploys y consulta del estado del mapa.
Launch.md incluye la ejecucion manual del gate; Cleanup.md explica la limpieza.

Pegar la salida real y el exit del Drive en Evidence.txt. El caso del gate
comprueba nombres y pasos observados, identidad del hook fuente, contrato JSON
y estado; ni exit 0 del harness ni solo `01-sin-armar` alcanzan para aprobar.

Para renovar el sello de un mapa existente, tras una corrida verde actualizar
solo `generado:` en LEEME.md con `date +%F` y `git rev-parse HEAD`, manteniendo
`verify_app: drive`; comprobar con:

```bash
bash skills/saikit-verificar-app/verificar.sh estado "$PWD"
```

Debe responder `al_dia`. `verificar.sh generar` es para la primera generacion:
rechaza un LEEME existente. No borrar `verify/` para forzar la regeneracion,
porque se perderian estas guias y tests. El sello conserva el SHA que se midio.
Commitear solamente `generado:`, Evidence.txt o docs/deploy-log.md mantiene
`al_dia` si ese SHA es un ancestro y el resto del contenido versionado coincide.
Cambios en codigo, tests o contenido del mapa lo desactualizan; la fecha sigue
siendo obligatoria y envejece a los 30 dias. Asi se puede guardar la evidencia
sin dejar una modificacion local del sello despues de cada commit.
