# 20.15 — Diseño de cierre headless observable

Spike/decisión. No es implementación medible; es investigación + contrato.

## Investigación realizada

Leído completo: `hooks/summonaikit-harness.sh` (4345 líneas).

### Mecanismos de cierre del harness

| Mecanismo | Línea | Cuándo | Alcance |
|-----------|-------|--------|---------|
| `stop_gate()` | 3607 | Stop event del host | Valida recibo, limpia estado, cierra zona |
| Desarme por prompt sin sentinel | 2018 | Primer turno humano post-sesión | `adv_limpiar_zona` + `rm -f STATE_PATH` + `podar_dir_sesion` |
| `barrer_estado_viejo()` | 955 | Al armar nueva sesión | TTL 14 días (20160 min) |
| Escotilla DELEGATED | 3770 | Stop con trabajo en vuelo | Permite sin recibo si hay subagente activo |
| `adv_limpiar_zona()` | 2685 | Teardown adversary | Borra `.saikit/scratch/adversary/<session>` |

### Hallazgo clave

El harness **no tiene `trap` ni signal handlers**. No puede observar la muerte
del proceso padre. La limpieza es reactiva: o el Stop dispara, o el siguiente
turno humano limpia, o el TTL barre.

### Hueco medido (18.27, 11 corridas grok headless)

Auto-wake de subagente → sesión padre se desarma → Stop de fin de turno se
corta en teardown → RC=0, 0/6 etiquetas, estado huérfano. Fix aplicado (D-A,
D-B) pero el hueco estructural persiste: sin Stop = sin limpieza inmediata.

## Decisión

**Contrato implementable.** El hook no puede observar la muerte sin Stop, pero
un launcher opt-in (`tools/headless-close.sh`) sí puede capturar el RC y
asegurar limpieza.

## Entregables

| Artefacto | Ruta | Estado |
|-----------|------|--------|
| Contrato | `docs/spec/headless-close-contract.md` | Escrito |
| Launcher | `tools/headless-close.sh` | Escrito, 9/9 tests pasan |
| Tests | `tests/test_headless_close.sh` | 9 PASS / 0 FAIL / 0 SKIP |

## Tests ejecutados

```
PASS: launcher existe y es ejecutable
PASS: sin argumentos → exit 2
PASS: host fake → exit 2
PASS: binario inexistente → exit 2
PASS: cleanup sin recibo: estado borrado
PASS: cleanup con recibo: estado borrado
PASS: adversary zone: limpiada
PASS: RC propagation: exit 42 propagado
PASS: sin .saikit/: no-op
```

## Limitaciones declaradas

1. **Opt-in**: solo protege sesiones iniciadas vía el launcher.
2. **No es trap**: SIGKILL escapa. El mecanismo reactivo (desarme por prompt)
   sigue siendo respaldo.
3. **No es Stop**: si el host dispara Stop, el hook maneja el cierre; el
   launcher detecta estado limpio y hace no-op.
4. **Sesiones concurrentes**: solo limpia la propia (keyed por SESSION_KEY).

## Cómo midió 20.16

20.16 implementa la superficie de observación sobre este contrato: el launcher
reporta si el cierre fue limpio (Stop disparó) o forzado (launcher limpió).
Eso es el "recibo de cierre" que 20.16 valida con TDD.
