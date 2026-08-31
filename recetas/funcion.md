---
saikit_owned: summonaikit-claude
nombre: funcion
titulo: Construir una función nueva
carril: full
cuando: ["agrega", "haz un", "crea un", "falta el"]
adversary: opcional
---

## Pasos
1. Nombra los datos primero: qué entidades, qué forma, dónde viven. Estructura en máquina de estados en vez de booleanos sueltos; tabla/registro en vez de if/else repetido.
2. Confirma que la fuente de datos existe. Si no, decláralo y construye la rebanada completa de lo pedido: fuente, escritura, lectura, pantalla.
3. Nombra y propón aparte lo que aparece de más (un bug, una mejora no pedida, deuda); no lo hagas en este turno. La propuesta va en el recibo.
4. Escribe el brief y delega con él.
5. Cubre la matriz: cargando / vacío / error / éxito; accesibilidad básica.
6. Verifica en la superficie real.
7. Si cambia una interacción, el usuario la ve con captura antes de dar por hecho (review gate).
8. PR.

## Qué le dices al usuario
Qué va a poder hacer, dónde lo ve, y qué cambia para él.

## Recibo
Understand: … Receta: funcion
Verify: pasos que prueban la función nueva en la superficie real
Fuera de alcance (propuesto aparte): <lo que apareció de más; si no hubo, ninguno>

Nota: si toca auth, pagos, migraciones o datos preexistentes, el adversary es obligatorio.
