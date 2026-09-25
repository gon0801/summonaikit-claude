---
saikit_owned: summonaikit-claude
nombre: cuidar-pr
titulo: Cuidar un PR hasta dejarlo listo
carril: full
cuando: ["cuidar el PR", "revisar el PR", "contestar los hilos", "el CI está rojo"]
adversary: opcional
---

## Pasos

1. Declara el modo **revisar** (leer y opinar, sin tocar) · **cuidar** (arreglar, verificar y cerrar el PR dentro del alcance autorizado) · **solo-hilos** (responder a los bots, no tocar código ni mergear).
2. Orden fijo: **conflictos → hilos de bots → CI**. No saltes a CI si hay conflictos de merge sin resolver.
3. **Conflictos**: si la rama quedó atrás de la base, haz `git fetch origin <base>` primero, confirma con `git merge-base --is-ancestor origin/<base> <rama>` (rc **1** ⇒ quedó atrás ⇒ mergea `origin/<base>`; rc **0** ⇒ al día ⇒ no toques la rama), y recién entonces mergea `origin/<base>` en la rama — nunca rebases a ciegas — y deja que CI corra de nuevo. Un conflicto real se resuelve a mano, no forzando.
4. **Hilos de bots** (Greptile, CodeRabbit y similares): evalúa cada hallazgo con la rúbrica **fix / dismiss / ask**; si el repo trae `.saikit/triage-patrones.md` (opt-in), aplica también los patrones aprendidos ahí (si no existe, la rúbrica de este paso alcanza):
   - **fix**: el hallazgo es válido y toca lo que se está construyendo → lo arreglas.
   - **dismiss**: el hallazgo es inválido (lo refutaste midiendo) → lo descartas y explicas por qué, con la evidencia pegada.
   - **ask**: no alcanza a decidir → preguntas al operador. Ni arreglas ni descartas a ciegas.
5. **CI rojo**: clasifícalo ANTES de tocar nada.
   - **flake** (inestable; pasó en un rebuild): re-corre UNA sola build. Si vuelve a fallar, ya no es flake.
   - **base vieja** (falló porque la base avanzó): mergea la base en la rama, NO edites el código.
   - **real** (tu cambio lo rompió): fix + la prueba que falla antes del fix (regla de hierro del repo), commit aparte.
6. **Esperas sin bloquear**: antes de esperar a CI o a un bot, comprueba si YA terminó (no re-polies en loop). Si tienes que esperar, usa un heartbeat largo, nunca un segundo sleep-loop.
7. **Rondas**: sigue la política de revisión de `AGENTS.md`: otra ronda solo por un bloqueante reproducible y sobre los arreglos de la anterior. Si el mismo bloqueante vuelve en dos rondas seguidas, detén ese bloque y presenta el diagnóstico al operador. Lo no bloqueante no reabre el ciclo. No repitas CI del mismo SHA ya validado.
8. **Descubrimientos se reportan, no se hacen.** Si descubres algo que está mal pero quedó FUERA del alcance del PR, lo reportas al operador y no amplías el PR por tu cuenta.
9. **Cierre en modo cuidar:** con CI verde y revisión efectiva de CodeRabbit sin bloqueantes, mergea el PR por el flujo normal del repositorio dentro del alcance autorizado y despliega según `AGENTS.md`. No pidas otro permiso por PR. Si falta una condición, reporta cuál y deja el PR abierto.

## Qué le dices al usuario

En qué quedó el PR — qué se arregló, qué se descartó y por qué (con su evidencia), el estado de CI y CodeRabbit, y el SHA mergeado o la razón concreta por la que sigue abierto.

## Recibo

Understand: … Receta: cuidar-pr
Verify: cada decisión de triage (fix/dismiss/ask) con su evidencia; CI y CodeRabbit del head; SHA mergeado y despliegue, o razón concreta de no merge
