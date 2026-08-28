---
saikit_owned: summonaikit-claude
nombre: investigar
titulo: Explicar cómo funciona algo
carril: fast
cuando: ["cómo funciona", "dónde vive", "por qué"]
adversary: opcional
---

## Pasos
1. Lee con el grafo del código y el historial.
2. Responde con evidencia citada: qué es, cómo funciona, dónde vive, con qué te vas a tropezar.
3. Distingue "es" de "parece que". Nombra los huecos. Lo que no encontraste es evidencia, no ausencia.
4. Sin cambiar código. Si la respuesta pide un cambio, dilo y para.

## Qué le dices al usuario
Definición simple primero, luego cómo, luego por qué. Diagrama si ayuda.

## Recibo
Understand: … Receta: investigar
Implement: sin cambio de código
Verify: no corrí tests; es una pregunta de solo lectura
