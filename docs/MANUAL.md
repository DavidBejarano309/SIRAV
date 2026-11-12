# Manual de los siete módulos

## 1. Usuarios y perfiles

El registro público crea únicamente CLIENTE. ADMIN abre **Usuarios y perfiles** para crear cuentas, seleccionar uno o varios roles y activar/desactivar sin borrar historial. Una cuenta con rol CLIENTE requiere documento y licencia. Debe quedar al menos un administrador activo. Cambiar permisos o estado revoca las sesiones anteriores.

Todos pueden abrir **Mi perfil** para editar nombre/apellido; un cliente también modifica teléfono y licencia. Los nombres/correo del cliente con cuenta proceden únicamente de USUARIO (3FN). El cambio de contraseña requiere la actual, cierra las sesiones y permite ingresar con la nueva. No hay recuperación por SMS/correo ni verificación externa de licencia.

## 2. Catálogo

**Nuestra flota** muestra inicialmente 25 vehículos de cinco categorías ficticias en una sede. Filtra por categoría/fechas y revisa la cotización. Un vehículo inactivo, ocupado o bloqueado por mantenimiento en esas fechas no es reservable. No se cotiza sin tarifa válida. ADMIN crea/edita vehículos y accede a **Tarifas y categorías**. Una tarifa utilizada conserva su valor histórico: cierra su vigencia sin afectar reservas existentes y crea la siguiente. No se editan vehículos con reservas vigentes.

## 3. Reservas

Desde el catálogo selecciona vehículo y fechas. El cliente reserva para sí mismo; el personal selecciona un cliente. En **Reservas → Clientes** se crean clientes de mostrador sin cuenta web. La solicitud queda SOLICITADA hasta que ADMIN/OPERADOR confirme. El titular o personal puede cancelar SOLICITADA/CONFIRMADA con motivo, conservando historial.

Las fechas usan [inicio,fin): el fin es exclusivo y permite reservas consecutivas. Se rechazan inicios pasados; el historial cargado deliberadamente es una excepción de demostración. Para reprogramar se cancela y crea otra reserva. La disponibilidad se valida de nuevo en PostgreSQL al guardar, incluso con concurrencia.

## 4. Alquileres e inspecciones

1. El personal confirma la reserva y, dentro del período, abre **Registrar entrega**.
2. Registra kilometraje, combustible, observaciones y daños (pueden ser cero).
3. Adjunta opcionalmente PNG/JPEG de hasta 5 MB; espera a que termine la carga. **Descargar evidencia** recupera el archivo con autenticación.
4. Desde una reserva ACTIVA o **Alquileres e inspecciones**, abre **Registrar devolución** y completa la inspección final.
5. El cierre liquida y genera un pago SIMULADO. Un segundo cierre es rechazado y no duplica valores.

La inspección se conserva en MongoDB mediante outbox. El detalle distingue sincronización pendiente de una inspección faltante y señala anulaciones. Si MongoDB falla, SQL conserva el documento pendiente para reintentar; no se inventa una inspección. Las imágenes están en archivos locales (.runtime/evidencias) o en el volumen Docker; las bases guardan referencias. Las referencias antiguas sin archivo accesible deben sustituirse desde la corrección.

En **Alquileres e inspecciones → Inspecciones**, el personal filtra daños altos y corrige daños, observaciones/evidencias con control de versión e historial. ADMIN puede anular con motivo. Una anulación conserva el documento como antecedente. No hay sensores, firmas jurídicas ni contratos reales.

## 5. Mantenimiento

ADMIN/OPERADOR programa vehículo, motivo, inicio y fin. Se rechazan cruces con reservas vigentes y otros mantenimientos programados. En el detalle edita fechas/motivo mientras sea PROGRAMADO, o marca **Finalizar o cancelar**. Los registros anteriores permanecen consultables y la disponibilidad considera las demás reservas y bloqueos.

## 6. Cobros simulados

**Cobros simulados** muestra base, cargos, total y pago generado. El detalle muestra pagos/cargos del alquiler. Todos los valores son COP con dos decimales. La base es días por tarifa asociada. Cada día calendario de retraso en Bogotá añade 50% de la tarifa diaria; el siguiente día comienza a las 00:00. PostgreSQL redondea a dos decimales, incluido medio centavo. No hay cargo automático por daños, descuentos, pasarelas, conciliación, financiación o facturas fiscales.

## 7. Historial y reportes

ADMIN/OPERADOR consulta seis reportes SQL: ocupación, ingresos simulados, ranking (con empates), actividad de clientes, devoluciones tardías y disponibilidad. Selecciona desde/hasta exclusivo, entre 1 y 366 días. Se muestran tres agregaciones MongoDB: promedios por categoría, zonas de daño por mes e incidencias por vehículo. Estas agregaciones son globales y no se filtran por el rango de SQL.

En **Historial** se consulta auditoría de reservas por fechas. ADMIN también ve la bitácora de accesos y administración y puede filtrar una acción exacta (por ejemplo LOGIN). Cada consulta devuelve hasta 200 eventos recientes; las bases conservan los registros. CLIENTE solo ve sus reservas, alquileres, cobros, inspecciones e historial individual. No ve reportes globales ni bitácoras de terceros.
