---
generado: 2026-09-05 · 28cd19f9a0be5081d4f65e2231e7e513c73f7250
verify_app: drive
---
# Mapa de funciones de la app

Estas son las funciones principales y su comprobacion local en `verify/`.

1. **Vigilar el trabajo de la IA**: cada vez que una IA trabaja en la compu, el
   guardian revisa que cierre bien su turno (con un recibo legible) antes de
   soltarla; si falta, bloquea el cierre.
   El Drive mide el armado: sin `-saikit`, tres pasos sin contrato ni estado;
   con `-saikit`, contrato inyectado y estado persistido. Usa los escenarios
   golden `01-sin-armar` y `02-armado-contrato` con copias y HOME desechables.
   El rechazo de un cierre armado sin recibo queda en la bateria completa del
   gate; estos dos escenarios no lo ejercitan.
2. **Instalar o actualizar el guardian** en los perfiles de las IAs, de forma
   segura: nunca pisa un archivo que no reconoce y siempre deja respaldo.
3. **Revisar que la libreta de tareas este al dia**: avisa si hay tareas
   anotadas como pendientes cuyo trabajo ya se mergeo.
4. **Revisar el registro de puestas en produccion** (deploys): que este
   ordenado, con formato correcto y un registro por cambio.
5. **Generar este mapa y la prueba de la app** (la carpeta `verify/`) para
   poder volver a comprobar que todo sigue andando.

> Este mapa se sello el dia que se genero (fecha) y con el sha del commit. Si la
> codigo, los tests o el contenido del mapa cambian, el verifier lo reporta.
> Guardar solamente el sello, Evidence.txt o el log de deploy no invalida la
> medicion: se compara el contenido versionado contra el SHA medido.
