---
saikit_owned: summonaikit-claude
nombre: refactor
titulo: Reorganizar sin cambiar el comportamiento
carril: full
cuando: ["reorganiza", "limpia", "ordena el código", "refactoriza"]
adversary: opcional
---

## Pasos
1. Pinea el comportamiento con un test de caracterización ANTES de mover nada. El typecheck no es pin.
2. Nombra la estructura que falta.
3. Resta antes de sumar: borra código muerto, wrappers de un solo llamador.
4. Mueve en pasos chicos con el pin verde; migra todos los llamadores y borra la API vieja en la misma ola. Sin shims. Si la API es pública (consumidores fuera del repo): deprecación + versión + plan de migración en vez de borrar.
5. Prueba que el comportamiento no cambió en el artefacto real.
6. Si el diff no baja la carga de lectura, revierte.
7. PR.

## Qué le dices al usuario
El comportamiento es el mismo, el código queda más simple y más fácil de tocar.

## Recibo
Understand: … Receta: refactor
Verify: el test de caracterización sigue verde sobre el artefacto real
