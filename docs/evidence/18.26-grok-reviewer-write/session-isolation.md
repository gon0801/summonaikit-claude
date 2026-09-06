# Corrección: no transferir el sello entre sesiones

Medición 2026-09-06, macOS. Base del PR: `02e15c4`.
Worktree aislado: `/private/tmp/saikit-fix1826-A5k8LJ/worktree`.
No se ejecutó el hook vivo ni se modificaron perfiles del operador.

El driver copia el hook al laboratorio. Los casos nuevos usan la señal
`GROK_HOOK_EVENT` mediante `LAB_GROK_HOOK_EVENT`, no solo un payload con
forma de Grok. El estado y log de A se comparan byte a byte después del
Write/Stop del reviewer B, sin vínculo entre las sesiones.

Comando usado para baseline, rojo y verde, desde el worktree:

```sh
env HOME=/private/tmp/saikit-fix1826-A5k8LJ/home \
  USERPROFILE=/private/tmp/saikit-fix1826-A5k8LJ/home \
  TMPDIR=/private/tmp/saikit-fix1826-A5k8LJ/tmp \
  SAIKIT_HOOK_VIVO=/private/tmp/saikit-fix1826-A5k8LJ/worktree/hooks/summonaikit-harness.sh \
  bash tests/test_veredicto_contract.sh
```

Baseline sin cambios: exit 0, `test_veredicto_contract: OK`.

## Rojo antes del fix

Solo se cambiaron los casos del test. Exit 1. Extracto literal:

```text
  caso: verdict_unarmed_no_toca_sesion_verificada
      FAIL: falta sello local en la sesion B
      FAIL: Write B altero estado de A sin vinculo padre-hijo
      FAIL: Write B acredito reviewer en log de A sin vinculo
      FAIL: Stop B altero estado de A
      FAIL: Stop B altero log de A
    ROJO: verdict_unarmed_no_toca_sesion_verificada
  caso: verdict_unarmed_no_toca_sesion_armada
      FAIL: falta sello local en la sesion B
      FAIL: Write B altero estado de A sin vinculo padre-hijo
      FAIL: Write B acredito reviewer en log de A sin vinculo
      FAIL: Stop B altero estado de A
      FAIL: Stop B altero log de A
    ROJO: verdict_unarmed_no_toca_sesion_armada
```

## Verde y poder discriminante

Tras retirar la escritura entre sesiones, exit 0. Extractos literales:

```text
  caso: verdict_unarmed_no_toca_sesion_verificada
    ok: verdict_unarmed_no_toca_sesion_verificada
  caso: verdict_unarmed_no_toca_sesion_armada
    ok: verdict_unarmed_no_toca_sesion_armada
    mutacion sello_cruza_sesion atrapada por verdict_unarmed_no_toca_sesion_verificada
test_veredicto_contract: OK
```

La mutación redirige la escritura a un estado ajeno existente; el caso exige
que la sesión A no cambie y que B conserve su propio sello. No depende de
que se mantengan las funciones retiradas ni de buscar texto en producción.

Esto acredita aislamiento y sellado local, **no** un merge automático vivo
de Grok. La captura disponible no acredita parentesco: el límite queda en
el contrato D18 y en el README de esta evidencia.
