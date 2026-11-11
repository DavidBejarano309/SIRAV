# Manual de uso

## Cliente

Regístrate con documento y licencia, inicia sesión y abre Nuestra flota. Selecciona fechas y vehículo, revisa la cotización y solicita la reserva. En Reservas y alquileres puedes ver estado e historial y cancelar antes de la entrega con un motivo.

El registro crea USUARIO y un perfil CLIENTE enlazado, sin duplicar nombre ni correo. El cliente solo ve sus operaciones.

## Operador

En Clientes registra personas sin cuenta. Sus nombres y correo se guardan directamente en CLIENTE. Al reservar desde el catálogo selecciona el cliente correspondiente.

1. Abre una reserva SOLICITADA y confirma.
2. Durante el período reservado abre Registrar entrega, verifica kilometraje, combustible e inspección.
3. Para una ACTIVA elige Registrar devolución y completa su inspección.
4. El sistema calcula el costo, añade el retraso si corresponde y genera el pago SIMULADO.
5. Consulta el historial y las inspecciones desde el detalle. Pueden tardar unos segundos en sincronizarse.

El retraso se cobra por día calendario de Bogotá con 50% de la tarifa diaria. No hay cobros reales ni cargo automático por daños. Las evidencias son referencias, no archivos subidos.

Mantenimiento bloquea fechas y rechaza cruces con reservas vigentes. Se puede completar o cancelar. En Inspecciones se pueden consultar daños altos y corregir observaciones/daños con historial de versiones.

## Administrador

Además de operar, crea/edita vehículos, categorías y tarifas; puede anular inspecciones con motivo. Para una tarifa nueva, cierra la vigencia anterior sin afectar reservas existentes. No se editan vehículos con reservas vigentes.

Los roles de las cuentas de demostración son fijos. La versión sencilla no incluye edición de usuarios, perfil ni clientes.

## Reportes

Selecciona uno de los seis reportes SQL y un rango de fechas hasta exclusivo. Más abajo aparecen los tres resúmenes MongoDB: promedios por categoría, zonas de daños por mes e incidencias por vehículo. No hay exportación CSV.
