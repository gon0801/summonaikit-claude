# Contrato de cierre headless observable (20.15)

## Problema

El hook de summonaikit corre dentro del proceso de Claude Code / Grok / Codex.
Cuando una sesión headless (`-p`) termina sin disparar el evento Stop, el hook
no puede observar la muerte ni limpiar el estado. Evidencia medida:

- **18.27 (grok, 11 corridas)**: auto-wake de subagente → sesión padre se
  desarma → Stop de fin de turno se corta en teardown → RC=0, 0/6 etiquetas,
  estado huérfano en disco (hallazgo E, smoke 18.9).
- **20.14 (grok)**: run2 colgó tras sello (API fail). Estado padre borrado por
  TTL (14 días), no por cierre limpio.
- **20.10 (claude)**: ceremonia completa, merge exitoso. El turno cierra limpio
  y el Stop dispara normalmente.

## Mecanismos de cierre existentes

| Mecanismo | Cuándo | Alcance |
|-----------|--------|---------|
| `stop_gate()` | Stop event del host | Valida recibo, limpia estado, cierra zona |
| Desarme por prompt sin sentinel | Primer turno humano post-sesión | `adv_limpiar_zona` + `rm -f STATE_PATH` + `podar_dir_sesion` |
| `barrer_estado_viejo()` | Al armar nueva sesión | TTL 14 días sobre `.saikit/*/harness-state.env` |
| Escotilla DELEGATED | Stop con trabajo en vuelo | Permite sin recibo si hay subagente activo (grok: + backgroundTasks) |

**Hueco**: si la sesión headless muere sin Stop y nadie vuelve a abrir el
proyecto, el estado persiste indefinidamente (hasta TTL).

## Contrato del launcher opt-in

### Qué es

Un script wrapper (`tools/headless-close.sh`) que envuelve `claude -p` (o
`grok -p`). Sabe que inició la sesión headless. Al terminar:

1. Captura el exit code del proceso hijo.
2. Lee el estado del harness (`.saikit/*/harness-state.env`).
3. Si el estado tiene recibo completo → limpieza normal (como `stop_gate`).
4. Si el estado NO tiene recibo → limpia estado + zona (como desarme por
   prompt sin sentinel).
5. Si el proceso murió sin estado → no-op (no hay nada que limpiar).

### Flujo

```
headless-close.sh <prompt>
  ├─ Preparar: verificar HEAD == origin/master, registrar SHA
  ├─ Ejecutar: claude -p <prompt> (con hooks activos)
  ├─ Capturar: RC del proceso hijo
  ├─ Leer: STATE_PATH del harness
  ├─ Si STATE existe Y tiene recibo completo:
  │   └─ Limpieza normal (adv_limpiar_zona + podar_dir_sesion)
  ├─ Si STATE existe Y NO tiene recibo:
  │   └─ Limpieza forzada (adv_limpiar_zona + rm STATE + podar_dir_sesion)
  ├─ Si STATE no existe:
  │   └─ No-op (el host ya limpió o nunca armó)
  └─ Reportar: RC, estado final, limpieza aplicada
```

### Escenarios de salida

| Escenario | RC proceso | Estado en disco | Acción del launcher |
|-----------|-----------|-----------------|---------------------|
| Ceremonia completa, Stop dispara | 0 | Limpio (stop_gate lo borró) | No-op |
| Ceremonia completa, Stop NO dispara | 0 | Persiste con recibo | Limpieza normal |
| Subagente wake, teardown sin Stop | 0 | Persiste sin recibo | Limpieza forzada |
| Timeout del host | ≠0 | Persiste o limpio | Según estado |
| Kill (SIGTERM/SIGKILL) | ≠0 | Persiste | Limpieza forzada |
| Error de API | ≠0 | Persiste sin recibo | Limpieza forzada |

### Limitaciones declaradas

1. **Opt-in**: solo funciona cuando la sesión se inicia vía el launcher.
   `claude -p` directo no tiene la protección.
2. **No es trap**: el launcher no intercepta señales del proceso hijo. Si el
   hijo muere con SIGKILL, el launcher no corre su cleanup. El mecanismo
   reactivo (desarme por prompt sin sentinel) sigue siendo el respaldo.
3. **No es Stop**: el launcher no sustituye el evento Stop del host. Si el
   host dispara Stop, el hook maneja el cierre normalmente; el launcher
   detecta que el estado ya fue limpiado y hace no-op.
4. **Estado de sesiones concurrentes**: si múltiples sesiones headless corren
   en paralelo, el launcher solo limpia la suya (keyed por SESSION_KEY).

## Resultado

**Decisión: implementable.** El launcher es un script thin que agrega
observabilidad al cierre headless sin tocar el hook. Los mecanismos existentes
(desarme por prompt, TTL) son el respaldo; el launcher es el cierre proactivo.

20.16 puede implementar la superficie de observación sobre este contrato.
20.17 puede medir la cadena completa.

## Evidencia citada

- `docs/evidence/18.27-grok-headless/README.md` (11 corridas, hallazgo E)
- `docs/evidence/phase-20/20.10/README.md` (autopilot Claude, ceremonia completa)
- `docs/evidence/phase-20/20.14/README.md` (autopilot Grok, API fail)
- `hooks/summonaikit-harness.sh` (4345 líneas, sin trap)
