---
saikit_owned: summonaikit-claude
nombre: cuidar-pr
titulo: Cuidar un PR hasta dejarlo listo
carril: full
cuando: ["cuidar el PR", "revisar el PR", "contestar los hilos", "el CI está rojo"]
adversary: opcional
---

## Pasos

1. Declara el modo **revisar** (leer y opinar, sin tocar) · **cuidar** (arreglar y dejar listo, pero nunca mergear) · **solo-hilos** (responder a los bots, no tocar código). En **cuidar** y **solo-hilos** la regla madre no cambia: dejar listo no es publicar.
2. Orden fijo: **conflictos → hilos de bots → CI**. No saltes a CI si hay conflictos de merge sin resolver.
3. **Conflictos**: si la rama quedó atrás de la base, hacé `git fetch origin <base>` primero, confirmá con `git merge-base --is-ancestor origin/<base> <rama>` (rc **1** ⇒ quedó atrás ⇒ mergeá `origin/<base>`; rc **0** ⇒ al día ⇒ no toques la rama), y recién entonces mergeá `origin/<base>` en la rama — nunca rebases a ciegas — y dejá que CI corra de nuevo. Un conflicto real se resuelve a mano, no forzando.
4. **CI rojo**: clasificalo ANTES de tocar nada.
   - **flake** (inestable; pasó en un rebuild): re-corre UNA sola build. Si vuelve a fallar, ya no es flake.
   - **base vieja** (falló porque la base avanzó): mergeá la base en la rama, NO edites el código.
   - **real** (tu cambio lo rompió): fix + la prueba que falla antes del fix (regla de hierro del repo), commit aparte.
5. **Hilos de bots** (Greptile, CodeRabbit y similares): evalúa cada hallazgo con la rúbrica **fix / dismiss / ask** y los patrones aprendidos en `.saikit/triage-patrones.md`:
   - **fix**: el hallazgo es válido y toca lo que se está construyendo → lo arreglás.
   - **dismiss**: el hallazgo es inválido (lo refutaste midiendo) → lo descartás y explicás por qué, con la evidencia pegada.
   - **ask**: no alcanza a decidir → preguntás al operador. Ni arreglás ni descartás a ciegas.
6. **Esperas sin bloquear**: antes de esperar a CI o a un bot, comprobá si YA terminó (no re-polies en loop). Si tenés que esperar, usá un heartbeat largo, nunca un segundo sleep-loop.
7. **Tope**: máximo **2 rondas** de fix+CI por turno. Si a la segunda no está verde, parás y reportás — no inventás un fix infinito.
8. **Descubrimientos se reportan, no se hacen.** Si descubrís algo que está mal pero quedó FUERA del alcance del PR, lo reportás al operador y no ampliás el PR por tu cuenta.
9. **cuidar nunca mergea.** Dejar listo no es publicar: el merge es del operador y solo por `tools/saikit-merge.sh`.

## Qué le dices al usuario

En qué quedó el PR — qué se arregló, qué se descartó y por qué (con su evidencia), qué quedó a la espera de CI o de un bot — y que está listo para que lo revises. Nunca digas "ya está mergeado".

## Recibo

Understand: … Receta: cuidar-pr
Verify: cada decisión de triage (fix/dismiss/ask) con su evidencia; el estado del CI; qué quedó a la espera; la frase "cuidar nunca mergea" cumplida
