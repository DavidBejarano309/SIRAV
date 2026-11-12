"""Genera el informe ejecutivo de cuatro páginas con ReportLab."""
from pathlib import Path
from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.pagesizes import A4
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, PageBreak, Table, TableStyle

root = Path(__file__).resolve().parents[1]
output = root / 'output/pdf/Informe-ejecutivo-SIRAV.pdf'
output.parent.mkdir(parents=True, exist_ok=True)
font_dir = Path('C:/Windows/Fonts')
if (font_dir / 'arial.ttf').exists():
    pdfmetrics.registerFont(TTFont('Report', str(font_dir / 'arial.ttf')))
    pdfmetrics.registerFont(TTFont('ReportBold', str(font_dir / 'arialbd.ttf')))
else:
    from reportlab.pdfbase.pdfmetrics import registerFontFamily
    # Helvetica soporta el texto español del informe en Linux.
    pdfmetrics.registerFontFamily('Report', normal='Helvetica', bold='Helvetica-Bold')

family = 'Report' if (font_dir / 'arial.ttf').exists() else 'Helvetica'
bold = 'ReportBold' if family == 'Report' else 'Helvetica-Bold'
pdfmetrics.registerFontFamily(family, normal=family, bold=bold, italic=family, boldItalic=bold)
styles = getSampleStyleSheet()
styles.add(ParagraphStyle(name='ReportTitle', fontName=bold, fontSize=26, leading=31, textColor=colors.HexColor('#193f36'), spaceAfter=18))
styles.add(ParagraphStyle(name='Section', fontName=bold, fontSize=14, leading=19, spaceBefore=17, spaceAfter=9, textColor=colors.HexColor('#244c3d')))
styles.add(ParagraphStyle(name='Copy', fontName=family, fontSize=10.5, leading=16, spaceAfter=10, textColor=colors.HexColor('#37483d')))
styles.add(ParagraphStyle(name='SmallCopy', fontName=family, fontSize=9, leading=13, spaceAfter=8, textColor=colors.HexColor('#697768')))
story = []
def p(text): story.append(Paragraph(text, styles['Copy']))
def h(text): story.append(Paragraph(text, styles['Section']))
def table(rows):
    body = [[Paragraph(str(v), styles['SmallCopy']) for v in row] for row in rows]
    t = Table(body, colWidths=[155, 340], hAlign='LEFT')
    t.setStyle(TableStyle([('BACKGROUND',(0,0),(-1,0),colors.HexColor('#edf2e7')),('VALIGN',(0,0),(-1,-1),'TOP'),('LINEBELOW',(0,0),(-1,-1),.4,colors.HexColor('#e1e7d9')),('LEFTPADDING',(0,0),(-1,-1),10),('RIGHTPADDING',(0,0),(-1,-1),10),('TOPPADDING',(0,0),(-1,-1),9),('BOTTOMPADDING',(0,0),(-1,-1),6)]))
    story.append(t)

story.append(Paragraph('SIRAV Informe ejecutivo', styles['ReportTitle']))
story.append(Paragraph('Sistema Integral de Reservas y Alquiler de Vehículos<br/>Bases de Datos 2 · Universidad El Bosque<br/>Implementación y alcance verificado · 21 de octubre de 2026', styles['SmallCopy']))
h('Problema')
p('Una empresa pequeña de alquiler necesita coordinar vehículos, clientes y fechas sin asignar el mismo vehículo a dos operaciones superpuestas. Los registros manuales separan la entrega, las condiciones del automóvil, la devolución y los cobros, lo que dificulta detectar conflictos y reconstruir lo ocurrido.')
h('Solución implementada')
p('SIRAV integra el ciclo de reserva, confirmación, entrega y devolución en una aplicación web. La base relacional controla las reglas críticas; las inspecciones conservan listas variables de daños y evidencias en MongoDB. Administrador, operador y cliente acceden a capacidades distintas mediante autenticación JWT y autorización en el servidor.')
table([['Componente','Responsabilidad'],['React','Catálogo, formularios operativos, historial, inspecciones y reportes.'],['Spring Boot y Java','API REST, validación, JWT, permisos, transacciones y coordinación entre bases.'],['PostgreSQL y PL/pgSQL','Trece entidades del dominio, procedimientos, funciones, triggers, excepciones e integridad.'],['MongoDB','Documentos de inspección y bitácora; CRUD, búsqueda compleja y agregaciones.']])
h('Alcance del prototipo')
p('Se implementan tarifas por vigencia, mantenimiento, cotización, reservas sin cruces, cancelaciones, inspecciones, cargos por retraso y pagos simulados. El documento definitivo excluye Oracle: se utiliza PL/pgSQL como mecanismo equivalente a PL/SQL. No se incorporan pagos reales ni almacenamiento de fotografías; las evidencias se registran por referencia.')

story.append(PageBreak())
story.append(Paragraph('Diseño y decisiones técnicas', styles['ReportTitle']))
h('Modelo relacional y reglas')
p('El esquema conserva las 13 entidades suministradas: Usuario, Rol, Usuario_Rol, Cliente, Categoria_Vehiculo, Vehiculo, Tarifa, Reserva, Alquiler, Pago, Cargo_Adicional, Mantenimiento y Auditoria_Reserva. Incluye relaciones 1:1, 1:N y N:M y separación de dependencias hasta 3FN. Los totales y la disponibilidad se calculan, en lugar de duplicarse en Reserva.')
p('Los intervalos se representan como [inicio, fin). Una restricción de exclusión por vehículo impide reservas solapadas en estado SOLICITADA, CONFIRMADA o ACTIVA. Los procedimientos bloquean el vehículo antes de validar cruces con mantenimientos. La fecha fin debe ser posterior al inicio y la tarifa debe cubrir todo el período.')
h('Lógica de negocio y atomicidad')
p('Cinco procedimientos gestionan crear, confirmar, cancelar, iniciar y cerrar. Tres funciones calculan disponibilidad, costo base y retraso. Los triggers validan transiciones, mantenimiento, auditoría y estado operativo. La aplicación llama a estos objetos con parámetros y confirma la transacción completa mediante Spring; un error revierte los cambios. El repositorio incluye un ejemplo ejecutable de COMMIT y ROLLBACK.')
p('Cada día calendario de retraso genera un cargo del 50% de la tarifa diaria. Al cerrar, el sistema genera un pago SIMULADO con el costo base y los cargos. El kilometraje no puede disminuir y el combustible debe estar entre 0 y 100. La entrega y la devolución requieren una inspección, aunque no tenga daños.')
h('Consistencia documental')
p('Una tabla técnica outbox guarda el documento de inspección en la misma transacción del alquiler. Un publicador lo envía a MongoDB y reintenta si el motor no está disponible. El UUID del evento permite una escritura idempotente; un reintento no duplica ni sobrescribe una inspección corregida. La interfaz informa cuando una inspección está pendiente de sincronización.')
h('Seguridad')
p('Las contraseñas usan BCrypt. Los JWT expiran y se revocan al cerrar sesión o cambiar permisos. Cada petición comprueba la cuenta activa y la versión del token. El cliente solo consulta sus propias operaciones. El rol SQL de la API no escribe directamente reservas, alquileres, pagos ni auditoría; ejecuta procedimientos controlados. Los secretos se configuran fuera de Git.')

story.append(PageBreak())
story.append(Paragraph('Resultados y validación', styles['ReportTitle']))
p('La verificación funcional se realizó en Windows con PostgreSQL 18 local, MongoDB 8.0.5 y JDK 23 compilando para Java 21. La configuración de despliegue utiliza PostgreSQL 17 y Java 21 en contenedores; el despliegue Docker y la VM Linux requieren una ejecución adicional en el entorno de entrega.')
h('Pruebas automatizadas')
table([['Comprobación','Evidencia de implementación'],['Backend','Pruebas de autorización, exportación segura, ciclo completo, concurrencia, permisos SQL, reportes y CRUD MongoDB. Los resultados de cada ejecución se conservan en Surefire y se resumen en docs/PRUEBAS.md.'],['Atomicidad','Una devolución con kilometraje inválido es rechazada y no crea pago; la devolución válida cierra el alquiler y genera las dos inspecciones del ciclo.'],['Concurrencia','Dos solicitudes simultáneas para el mismo vehículo y período producen exactamente una reserva aceptada.'],['MongoDB','Consulta de severidad alta, corrección versionada, rechazo de versión obsoleta, anulación lógica y tres agregaciones.'],['Frontend','Pruebas de autenticación y registro, compilación de producción y pruebas de navegación en navegador de escritorio y móvil.']])
h('Consultas complejas')
p('Los seis reportes cubren ocupación mensual con calendario y días distintos; ingresos por categoría y mes; ranking de los vehículos por categoría con funciones de ventana; actividad y tasa de cancelación de clientes; devoluciones tardías con HAVING; y disponibilidad con anti joins. Las agregaciones documentales calculan promedios por categoría, zonas de daño por mes e incidencias por vehículo.')
h('Límites de los resultados')
p('Los datos son de demostración y los pagos no representan transacciones financieras. Las pruebas no equivalen a una auditoría de seguridad ni a una certificación de rendimiento. No se afirma el objetivo de dos segundos en una VM sin medirlo allí. La actualización de inspecciones es eventualmente consistente y la interfaz puede mostrar una sincronización pendiente durante unos segundos.')

story.append(PageBreak())
story.append(Paragraph('Gestión y cierre de entrega', styles['ReportTitle']))
h('Organización propuesta')
p('Se entrega un plan híbrido de cuatro semanas, una EDT con estimación de 124 horas, hitos, matriz RACI para tres integrantes, ocho riesgos con probabilidad e impacto, historias con aceptación y una plantilla de trazabilidad. La organización responde al documento definitivo, que exige tres estudiantes; los nombres y responsabilidades reales deben validarse por el equipo.')
h('Despliegue y evidencia académica')
p('El repositorio incluye Docker Compose, Dockerfiles, creación de usuarios con privilegios limitados, configuración por entorno, respaldo y guía de instalación en Ubuntu Server dentro de una máquina virtual. El guion distribuye una demostración de 13 minutos y 30 segundos entre los integrantes.')
p('Siguen requiriendo ejecución personal del equipo: crear y documentar la VM Linux, validar su acceso desde el anfitrión, conservar evidencias de respaldo y restauración, generar el historial colaborativo en Git y grabar el video. Los modelos deben revisarse en la herramienta aceptada por el docente. No se presentan planes ni guías como pruebas de actividades que no se han realizado.')
h('Lecciones y evolución')
p('La prevención de cruces pertenece a la base y debe comprobarse con concurrencia real. La combinación de dos motores necesita un mecanismo explícito de recuperación; no basta con escribir secuencialmente en ambos. Las consultas financieras deben agregar cada relación antes de unirla, para evitar totales duplicados. Una siguiente iteración puede incorporar recuperación de contraseña, almacenamiento de evidencias, medición de rendimiento en la VM y monitoreo de eventos pendientes.')
h('Conclusión')
p('La implementación conecta la aplicación web con los dos motores y concentra las reglas transaccionales en PL/pgSQL. El código, los scripts, los modelos y los manuales permiten reproducir el prototipo y preparar la sustentación. La entrega académica debe completarse con las evidencias reales de infraestructura y participación del equipo.')
h('Referencias principales')
for text in ['Elmasri, R., y Navathe, S. B. (2016). Fundamentals of Database Systems. 7.ª ed. Pearson.','Silberschatz, A., Korth, H. F., y Sudarshan, S. (2019). Database System Concepts. 7.ª ed. McGraw-Hill.','Bradshaw, S., Brazil, E., y Chodorow, K. (2019). MongoDB: The Definitive Guide. 3.ª ed. O’Reilly.','Gray, J. (1981). The transaction concept: virtues and limitations. VLDB, 144-154.']:
    story.append(Paragraph(text, styles['SmallCopy']))

def footer(canvas, doc):
    canvas.setFont(family, 8)
    canvas.setFillColor(colors.HexColor('#88927d'))
    canvas.drawString(49, 27, 'SIRAV  |  Bases de Datos 2  |  Informe ejecutivo')
    canvas.drawRightString(A4[0]-49, 27, str(doc.page))

doc = SimpleDocTemplate(str(output), pagesize=A4, rightMargin=50, leftMargin=50, topMargin=45, bottomMargin=45, title='SIRAV Informe ejecutivo', author='Proyecto SIRAV')
doc.build(story, onFirstPage=footer, onLaterPages=footer)
(root/'docs/INFORME-EJECUTIVO.pdf').write_bytes(output.read_bytes())
print(output)
