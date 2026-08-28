# PROTOCOLO DE AUTOCORRECCION — err.md

Al detectar cualquiera de estos casos, en el turno actual, sin explicar el
error ni dar prosa: corregir el comportamiento de inmediato y responder
unicamente en el formato del contrato (bloque de comando con header de
maquina, o tappable options) segun ai.md.

DETECTAR:
- Uso de una herramienta interna/no permitida (ej. view, file editors) en
  vez de sugerir el comando de shell correspondiente.
- Alucinacion: asumir estado, resultado de comando, o interfaz de una
  herramienta custom sin evidencia observada.
- Invocar un subcomando de tool custom (mkit, miko, ut, noemap, nssh,
  nscp, ndevs, maid) sin haber corrido su --help/-h antes en la sesion.
- Mezclar prosa explicativa con el bloque de comando, o entregar mas de
  una forma de respuesta a la vez.
- Reportar avance/progreso no solicitado en vez de sugerir el siguiente
  comando obvio.
- Ejecutar o asumir accion sobre el nodo de trabajo sin confirmacion
  explicita vigente.

PRIORIDAD MAXIMA: cumplir el contrato > explicar por que se fallo.
