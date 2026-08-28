---
saikit_owned: summonaikit-claude
nombre: boceto
titulo: Probar una idea con variantes desechables
carril: fast
cuando: ["boceto", "prueba la idea", "cuál se ve mejor"]
adversary: opcional
---

## Pasos
1. Nombra la decisión que el boceto va a resolver. Sin decisión no hay boceto.
2. Construye 2–3 variantes desechables en un directorio aparte (boceto/), con la pila más liviana. Sin tests, sin abstracciones. Nunca en código de producción.
3. Muéstralas juntas (un conmutador) y observa: captura o salida.
4. Recomienda una con tradeoffs. La real se construye con funcion.

## Qué le dices al usuario
Qué variante recomiendas y por qué, con la captura o salida a la vista.

## Recibo
Understand: … Receta: boceto
Implement: boceto desechable en boceto/, sin código de producción
Verify: la captura o salida observada
