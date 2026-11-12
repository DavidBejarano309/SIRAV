"""Regenera la trazabilidad desde la copia del documento entregado por el usuario."""
from pathlib import Path
from xml.etree import ElementTree as ET
from zipfile import ZipFile
import re

root = Path(__file__).resolve().parents[1]
source = root / 'docs/referencias/Supuestos_SIRAV.docx'
ns = {'w': 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'}
tree = ET.fromstring(ZipFile(source).read('word/document.xml'))
items = {}
for row in tree.findall('.//w:tr', ns):
    cells = [' '.join(''.join(p.itertext()) for p in c.findall('.//w:p', ns)) for c in row.findall('w:tc', ns)]
    if cells and re.fullmatch(r'(SG|US|CV|RE|AL|MA|CO|HR|ST)-\d{2}', cells[0]):
        items[cells[0]] = cells[1]

evidence = {
'US': [
'JWT y cuentas ADMIN/OPERADOR/CLIENTE; prueba authEnforcesRolesAndRevokesSessions.',
'Login local y cuentas ficticias en DemoSeed.',
'UNIQUE cliente.id_usuario y v_cliente_contacto; pruebas de clientes enlazados y sin cuenta.',
'@PreAuthorize y Access verifican cada petición; pruebas de accesos HTTP directos.',
'SecurityConfig con BCrypt; contraseña nunca se devuelve ni se incluye en la bitácora.',
'UserController y vista Users: alta, roles y estado; sin validación externa.',
'Registro público fuerza CLIENTE; prueba clientsCannotAssignPrivilegesOrReadOtherPeoplesData.',
'Access.reservation/rental y filtros de lectura; prueba de aislamiento HTTP.',
'usuario_rol y selección múltiple en Users; prueba usersSupportMultipleRolesProfileChangesAndRevocation.',
'Correo normalizado y UNIQUE; registro duplicado devuelve 409 en prueba.',
'Desactivación lógica y token_version; prueba conserva reserva del titular desactivado.',
'Mi perfil permite cambiar contraseña con la actual, sin correo ni SMS.',
'JWT con vencimiento, verificación de activo/versión y logout; prueba revoca sesiones.',
'AuditService + outbox hacia bitacora_operaciones; Historial de acceso visible al administrador.',
],
'CV': [
'04-views-seed.sql + 06-supuestos.sql: carga inicial de 25 vehículos y 5 categorías; prueba del volumen mínimo.',
'FK a categoría y UNIQUE placa en el esquema 3FN.',
'Tarifas con vigencias y exclusión de solapamiento; cotización por categoría.',
'fn_vehiculo_disponible consulta reservas y mantenimiento; sin estado reservado persistente.',
'Catalog muestra categoría, características, fechas y cotización desde la API.',
'Alcance de una sede; sin dependencia de GPS.',
'Scripts SQL locales e idempotencia de la ampliación; sin inventario externo.',
'Ficha Catalog con placa, marca, modelo, año, color y kilometraje.',
'Disponibilidad filtra INACTIVO y períodos de mantenimiento en PostgreSQL.',
'Bloqueo de vehículo y exclusión; concurrentReservationsHaveExactlyOneWinner.',
'Modelo de una sede sin proceso de traslados.',
'Cotización y procedimiento rechazan falta de tarifa para el período.',
'Creación/edición de vehículos solo ADMIN, verificada en backend.',
'Filtros por categoría, disponibilidad y fechas; sin proximidad geográfica.',
],
'RE': [
'FK obligatorias de cliente y vehículo; una unidad por solicitud.',
'CHECK fecha_fin>fecha_inicio y validación del intervalo.',
'Bloqueo FOR UPDATE y EXCLUDE; prueba concurrente con un único ganador.',
'sp_crear_reserva produce SOLICITADA y sp_confirmar_reserva confirma.',
'sp_cancelar_reserva y trigger solo permiten SOLICITADA/CONFIRMADA.',
'Trigger cruza mantenimiento; prueba adjacentDatesMaintenanceConflictsAndHalfCentRounding.',
'Confirmación local, sin pasarela ni firma.',
'FK a cliente, licencia requerida y Access.client para cliente autenticado.',
'Procedimiento rechaza inicio anterior a hoy en Bogotá; prueba de fecha pasada. Historial demo deliberado aparte.',
'POST confirm restringido a ADMIN/OPERADOR; creación no confirma.',
'Transacciones Spring/PostgreSQL; prueba de conflicto verifica ausencia de filas parciales.',
'Cancelación actualiza estado y genera auditoría, sin DELETE de reserva.',
'Política aplicada: cancelar y crear otra; trigger impide editar identidad/fechas.',
'Formulario y entidad de una reserva por vehículo; sin listas de espera.',
'Intervalos [inicio,fin); prueba admite reservas adyacentes y rechaza solapamiento.',
],
'AL': [
'FK UNIQUE id_reserva y sp_iniciar_alquiler valida CONFIRMADA.',
'Entrega/devolución manual, endpoints restringidos a personal.',
'DTO Handover + InspectionFields: km, combustible, observaciones y lista de daños vacía o no.',
'Access valida alquiler SQL antes de leer/corregir MongoDB; publisher usa alquiler creado en la misma transacción.',
'EvidenceService guarda imágenes en archivos; documentos contienen únicamente referencias.',
'DTO exige inspección no nula; procedimiento guarda devolución, outbox y pago en una transacción.',
'Flujo académico sin firma ni contrato comercial.',
'Procedimiento exige CONFIRMADA; no inicia SOLICITADA/CANCELADA/CERRADA.',
'Formulario manual con validaciones de combustible y kilometraje.',
'MongoDB índice único alquilerId+tipo; prueba verifica ENTREGA y DEVOLUCION.',
'Upload PNG/JPEG y descarga autenticada; prueba de API y de navegador con imagen real.',
'Corrección con versión optimista e historial; anulación lógica con motivo y administrador.',
'Historial demo puntual/tardío y función de retraso según devolución real.',
'Outbox transaccional y upsert idempotente; prueba simula fallo de transporte, retiene evento y reintenta.',
'Segundo cierre devuelve 409; prueba conserva un solo pago.',
],
'MA': [
'CatalogController restringe altas a personal; datos ingresados localmente.',
'FK vehículo, período requerido y bloqueo en disponibilidad.',
'Trigger serializa sobre vehículo y verifica reservas vigentes.',
'Módulo de fechas, motivo y estado; sin inventario de taller.',
'Política aplicada: rechazar cruce con reserva vigente (409), no desplazarla.',
'Disponibilidad vuelve a consultar reservas y otros bloqueos tras completar mantenimiento.',
'NOT NULL y CHECK fecha_fin>fecha_inicio.',
'Conflicto rechazado; prueba comprueba rollback del INSERT.',
'Restricción EXCLUDE para mantenimientos PROGRAMADOS; prueba de duplicado.',
'Descripción obligatoria en DTO y fechas obligatorias.',
'PUT permite editar fecha/motivo de PROGRAMADO; prueba consulta disponibilidad antes/después.',
'@PreAuthorize ADMIN/OPERADOR; cliente recibe 403.',
'PATCH completa/cancela y GET conserva el registro; prueba comprueba estado persistido.',
'Formularios manuales sin agendas ni telemetría.',
],
'CO': [
'Vista Cobros simulados y formato es-CO/COP con dos decimales.',
'fn_calcular_costo usa días del intervalo y tarifa asociada a la reserva.',
'fn_calcular_cargo_retraso aplica 50% diario; pruebas de fecha límite y medio centavo.',
'FK id_alquiler en pago/cargo_adicional; detalle de cobro consulta ambos.',
'sp_cerrar_alquiler liquida y deja pago SIMULADO en una transacción.',
'Sin conciliación ni facturación tributaria en endpoints o dependencias.',
'Fórmulas sin descuentos, cupones ni promociones.',
'NUMERIC, round(...,2) y money con dos decimales; prueba de 0.005 a 0.01.',
'Días calendario America/Bogota; pruebas 23:59:59 y 00:00 del siguiente día.',
'CHECK tipo=SIMULADO y vista explícita de pagos simulados.',
'Trigger protege tarifa ya utilizada; prueba rechaza cambio y conserva cálculo histórico.',
'Bloqueo de alquiler y estado ACTIVA; segundo cierre no duplica pago/cargos.',
'R2 ingresos_simulados y títulos explícitos de R2/R5 en Reports.',
'Sin medios de pago bancarios, financiación ni reembolsos.',
],
'HR': [
'PostgreSQL conserva dominio y auditoria_reserva; MongoDB es proyección documental.',
'inspecciones_vehiculo y bitacora_operaciones, índices y consultas reales.',
'Seis archivos sql/reports y prueba allSixSqlReportsExecuteAgainstRealDatabase.',
'InspectionController.analytics ejecuta tres pipelines MongoDB.',
'Flota ficticia y historial de diez alquileres objetivo con puntualidad/retrasos/daños y una cancelación; carga omite conflictos existentes.',
'Medición reproducible de HTTP local en docs/evidencias/supuestos-medicion.txt; validar nuevamente en la VM.',
'Autorización HTTP para historial, auditoría y reportes; prueba de acceso de cliente.',
'JdbcTemplate y MongoTemplate consultan únicamente bases del prototipo.',
'Rangos SQL hasta exclusivo de 1 a 366 días; entradas invertidas se rechazan.',
'ReportController e HistoryController restringen datos globales a personal; seguridad de usuarios solo ADMIN.',
'Filtros por titular en reservas/alquileres/cobros y Access en inspecciones/pagos.',
'inspection-status distingue PENDIENTE/INCONSISTENTE/DISPONIBLE y anulaciones; prueba borra y restaura un documento en test.',
'ranking.sql usa RANK() y filtra <=5; historial demo con cantidades iguales.',
'Trigger auditoria_reserva y eventos outbox; vista Historial para consultar cambios.',
'Reportes tabulares y agregaciones, sin plataforma externa de BI.',
]}
general = [
'Prototipo académico, datos ficticios y cobros simulados en README/manual.',
'Una sede; el catálogo no incluye traslados.',
'Pendiente externo: confirmar integrantes y cronograma con el docente; el código no acredita participación del equipo.',
'Flujo principal cubierto por pruebas de integración y lifecycle.spec.js.',
'Sin bancos, aseguradoras, contratos o validadores externos.',
]
technical = [
'Esquema 3FN de 13 entidades preservado byte por byte; outbox es infraestructura adicional.',
'Referencias de alquiler verificadas por Access; no se declara FK entre motores.',
'Pendiente externo: despliegue real en Ubuntu/VM. Compose y guía incluidos; no se afirma ejecución en Linux.',
'Pendiente externo: asignación y comprobación de RAM/vCPU/disco del anfitrión.',
'Funciones, procedimientos PL/pgSQL, triggers, restricciones y transacciones; pruebas contra PostgreSQL real.',
'Parcial: controles y script backup.sh incluidos. Pendientes ejecución/restauración de respaldo e historial Git real del equipo.',
]
assert sum(len(v) for v in evidence.values()) == 101
assert len(items) == 112, len(items)
lines = ['# Cumplimiento de Supuestos SIRAV', '',
'Fuente: [Supuestos_SIRAV.docx](referencias/Supuestos_SIRAV.docx), versión 2.0, noviembre de 2026. Los 101 supuestos funcionales se incorporan a esta implementación; las condiciones externas se declaran por separado. Esta matriz indica soporte en código y pruebas concretas, no 101 pruebas automatizadas independientes.', '',
'## Políticas de esta implementación', '',
'Una sede; 25 vehículos iniciales en 5 categorías. Reservas y mantenimientos usan [inicio,fin), con fin exclusivo. Se rechazan conflictos; para reprogramar una reserva se cancela y crea otra. Inicio no anterior a hoy en Bogotá, salvo carga histórica deliberada. Mantenimiento programado admite cambios de fecha/motivo. Las tarifas utilizadas son históricas e inmutables en categoría/valor/inicio. COP se redondea a dos decimales; retraso por fecha calendario de Bogotá al 50% diario. Contraseñas se cambian localmente con la clave actual. Las inspecciones tienen versiones y anulación lógica. MongoDB se sincroniza mediante outbox; una ausencia sin evento pendiente se informa como inconsistencia.', '',
'Las decisiones operativas implementan la solicitud del usuario; la aprobación académica de supuestos inferidos, equipo, infraestructura y cronograma corresponde al equipo/docente. No se generan evidencias ficticias de VM, video, backups o commits.', '',
'## Ubicación del soporte', '',
'Backend: `security/` (JWT, usuarios, perfil, bitácora), `catalog/` (flota y mantenimiento), `rental/` (operaciones y cobros), `inspection/` (documentos, evidencias, outbox) y `report/` (reportes/historial). Frontend: vistas con el mismo propósito. SQL: `database/postgres/02-integrity.sql`, `03-procedures.sql`, `06-supuestos.sql` y `backend/src/main/resources/sql/reports/`. Pruebas: `backend/src/test/java/co/edu/sirav/IntegrationTest.java`, `security/AccessTest.java` y `frontend/e2e/`.', '']
for prefix,title,values in [('SG','Generales',general), *[(p,t,evidence[p]) for p,t in [('US','Usuarios y perfiles'),('CV','Catálogo'),('RE','Reservas'),('AL','Alquileres e inspecciones'),('MA','Mantenimiento'),('CO','Cobros simulados'),('HR','Historial y reportes')]], ('ST','Técnicos',technical)]:
    lines += ['## '+title, '', '| ID | Supuesto del documento | Soporte y verificación |', '| --- | --- | --- |']
    for i,value in enumerate(values,1):
        ident=f'{prefix}-{i:02}'
        lines.append(f'| {ident} | {items[ident].replace("|","/")} | {value.replace("|","/")} |')
    lines.append('')
(root/'docs/SUPUESTOS-CUMPLIMIENTO.md').write_text('\n'.join(lines),encoding='utf-8')
print('Matriz generada: 101 supuestos funcionales, 5 generales y 6 técnicos.')
