---
saikit_owned: summonaikit-claude
nombre: bug
titulo: Arreglar algo que no funciona
carril: full
cuando: ["no funciona", "se rompió", "da error", "está mal"]
adversary: opcional
---

## Pasos
1. Reprodúcelo tú, en la misma superficie (app real o comando). Si no reproduce, fuerza el disparador o instrumenta hasta que dispare. Un bug que no reproduces no lo puedes dar por arreglado.
2. Busca la causa por bisección: hipótesis → evidencia en ejecución → descarta. No adivines.
3. El test que falla ANTES del fix (regla de hierro del repo), commit aparte.
4. El cambio más chico que la evidencia justifica. Nada "por si acaso".
5. Verifica en la misma superficie: el repro original ya pasa. "Inconcluso" no es PASS.
6. PR con Why/Scope/Verification y el repro rojo→verde pegado.

## Qué le dices al usuario
Qué estaba roto, la causa en una frase, qué cambia para él.

## Recibo
Understand: … Receta: bug
Verify: el comando del repro, del rojo al verde
