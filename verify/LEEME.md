---
generado: 2026-09-05 · 7d506c5d38f040bc8be797c1137e40428a99d9c6
verify_app: drive
---
# Mapa de funciones de la app

Describe aca las 3 a 5 funciones principales de la app, EN ESPANOL, para alguien
que no lee codigo (p.ej. "entrar", "crear X", "ver la lista", "cerrar sesion").

1. **Vigilar el trabajo de la IA**: cada vez que una IA trabaja en la compu, el
   guardian revisa que cierre bien su turno (con un recibo legible) antes de
   soltarla; si falta, bloquea el cierre.
2. **Instalar o actualizar el guardian** en los perfiles de las IAs, de forma
   segura: nunca pisa un archivo que no reconoce y siempre deja respaldo.
3. **Revisar que la libreta de tareas este al dia**: avisa si hay tareas
   anotadas como pendientes cuyo trabajo ya se mergeo.
4. **Revisar el registro de puestas en produccion** (deploys): que este
   ordenado, con formato correcto y un registro por cambio.
5. **Generar este mapa y la prueba de la app** (la carpeta `verify/`) para
   poder volver a comprobar que todo sigue andando.

> Este mapa se sello el dia que se genero (fecha) y con el sha del commit. Si la
> app cambia, el sello queda viejo y el verifier lo reporta. No confies en un
> mapa que no coincide con el commit actual.
