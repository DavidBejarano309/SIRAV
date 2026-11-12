"""Genera diccionario y fuente Chen a partir de las tablas suministradas."""
import re
from pathlib import Path

root = Path(__file__).resolve().parents[1]
schema = (root / 'database/postgres/01-schema.sql').read_text(encoding='utf-8')
tables = re.findall(r'CREATE TABLE (\w+)\s*\((.*?)\n\);', schema, re.S)
lines = ['# Diccionario de datos', '',
         'El esquema conserva las 13 entidades de dominio del SQL original. Los identificadores simples se generan como identidades; Usuario_Rol conserva su clave compuesta. Los timestamps de eventos usan zona horaria.', '',
         '## Relaciones y normalización', '',
         '- Usuario–Cliente: 1 a 0..1 mediante FK única opcional.',
         '- Reserva–Alquiler: 1 a 0..1 mediante FK única obligatoria en Alquiler.',
         '- Usuario–Rol: N:M mediante Usuario_Rol con clave compuesta.',
         '- Categoría–Vehículo, Categoría–Tarifa, Cliente–Reserva, Vehículo–Reserva y Vehículo–Mantenimiento: 1:N.',
         '- Alquiler–Pago, Alquiler–Cargo_Adicional, Reserva–Auditoria_Reserva y Usuario–Auditoria_Reserva: 1:N.', '',
         'El esquema sigue el diseño revisado aportado por el usuario. En clientes con cuenta, nombre, apellido y correo se almacenan exclusivamente en Usuario; en clientes sin cuenta, se almacenan en Cliente. La restricción ck_CLIENTE_origen_identidad impide duplicarlos. La vista v_cliente_contacto resuelve ambos casos sin copiar valores. Los totales financieros y la disponibilidad se calculan mediante vistas y funciones.', '',
         'No se necesita especialización EER para este alcance: los perfiles de acceso son asignaciones N:M, no subtipos disjuntos. Las extensiones técnicas de seguridad e integración se documentan al final.', '']
dot = ['graph SIRAV {', '  graph [layout=neato, overlap=false, splines=true, bgcolor="white", outputorder=edgesfirst];', '  node [fontname="Arial", fontsize=11, style=filled, fillcolor="#edf2e8", color="#526d50"];', '  edge [fontname="Arial", fontsize=9, color="#84947c"];']
for table, body in tables:
    columns = []
    for line in body.splitlines():
        s = line.strip().rstrip(',')
        if not re.match(r'^[a-z_][a-z_0-9]*\s+(BIGINT|VARCHAR|BOOLEAN|TIMESTAMPTZ|DATE|SMALLINT|INTEGER|NUMERIC)\b',s):
            continue
        m = re.match(r'(\w+)\s+(.+)', s)
        if m:
            columns.append(m.groups())
    primary = set(','.join(re.findall(r'PRIMARY KEY\s*\(([^)]+)\)', body)).replace(' ', '').split(','))
    unique = set(','.join(re.findall(r'UNIQUE\s*\(([^)]+)\)', body)).replace(' ', '').split(','))
    foreign = dict(re.findall(r'FOREIGN KEY\s*\((\w+)\) REFERENCES (\w+)', body))
    lines += [f'## {table}', '', '| Campo | Tipo | Nulo | Claves y valores |', '| --- | --- | --- | --- |']
    if table != 'USUARIO_ROL':
        dot.append(f'  {table} [shape=box, label="{table}", fillcolor="#dce7d3"];')
    for col, spec in columns:
        datatype = re.split(r'\s+(?:NOT NULL|GENERATED|DEFAULT)', spec)[0]
        info = []
        if col in primary:
            info.append('PK')
        if col in unique:
            info.append('UNIQUE')
        if col in foreign:
            info.append('FK → ' + foreign[col])
        if 'IDENTITY' in spec:
            info.append('Identidad automática')
        if 'DEFAULT now()' in spec:
            info.append('Fecha actual por defecto')
        nullable = 'No' if 'NOT NULL' in spec or col in primary else 'Sí'
        lines.append(f'| {col} | {datatype} | {nullable} | {"; ".join(info) or "Dato de dominio"} |')
        # En Chen los identificadores de otras entidades se representan por relaciones.
        if col not in foreign and table != 'USUARIO_ROL':
            attr = f'{table}_{col}'
            label = f'<<U>{col}</U>>' if col in primary else f'"{col}"'
            dot.append(f'  {attr} [shape=ellipse, label={label}, fillcolor="#fafbf7"];')
            dot.append(f'  {table} -- {attr};')
    lines.append('')

relationships = [('USUARIO','CLIENTE','tiene perfil','0..1','0..1'),('USUARIO','ROL','tiene asignado','0..N','1..N'),('CATEGORIA_VEHICULO','VEHICULO','clasifica','1','0..N'),('CATEGORIA_VEHICULO','TARIFA','define','1','0..N'),('CLIENTE','RESERVA','solicita','1','0..N'),('VEHICULO','RESERVA','se reserva','1','0..N'),('TARIFA','RESERVA','se aplica','1','0..N'),('RESERVA','ALQUILER','origina','1','0..1'),('ALQUILER','PAGO','recibe','1','0..N'),('ALQUILER','CARGO_ADICIONAL','genera','1','0..N'),('VEHICULO','MANTENIMIENTO','requiere','1','0..N'),('RESERVA','AUDITORIA_RESERVA','registra','1','1..N'),('USUARIO','AUDITORIA_RESERVA','realiza','0..1','0..N')]
for i,(a,b,verb,ca,cb) in enumerate(relationships):
    dot += [f'  rel{i} [shape=diamond, label="{verb}", fillcolor="#fff3de"];', f'  {a} -- rel{i} [label="{ca}"];', f'  rel{i} -- {b} [label="{cb}"];']
dot += ['  asignado_en [shape=ellipse, label="asignado_en"];', '  rel1 -- asignado_en;', '}']
lines += ['## Extensiones implementadas', '',
          '| Tabla/campo | Tipo | Propósito |', '| --- | --- | --- |',
          '| Reserva.idempotencia | UUID NOT NULL UNIQUE | Reintentos de la misma solicitud |',
          '| Evento_Outbox.id | UUID PK | Identidad idempotente del evento |',
          '| Evento_Outbox.coleccion | VARCHAR(50) NOT NULL | Destino documental permitido |',
          '| Evento_Outbox.documento | JSONB NOT NULL | Documento durable hasta publicación |',
          '| Evento_Outbox.creado_en | TIMESTAMPTZ NOT NULL DEFAULT now() | Orden y trazabilidad |',
          '| Evento_Outbox.publicado_en | TIMESTAMPTZ opcional | Confirmación de escritura MongoDB |',
          '| Evento_Outbox.intentos | INTEGER NOT NULL DEFAULT 0 | Reintentos realizados |', '',
          '## Restricciones adicionales', '',
          'Fechas fin posteriores al inicio; tarifas positivas y vigencias sin cruces; kilómetros no negativos ni decrecientes al devolver; combustible entre 0 y 100; estados enumerados; pagos exclusivamente SIMULADO; reservas vigentes sin cruces; mantenimiento sin cruces con reservas. Ver `database/postgres/02-integrity.sql` para la definición ejecutable.', '',
          '## Modelo documental', '',
          '`inspecciones_vehiculo`: `_id` UUID del evento, `alquilerId`, `vehiculoId`, `categoriaId`, `tipo`, `fecha`, `actor`, `kilometraje`, `combustible`, `danos[]` (zona, severidad, descripción), `evidencias[]`, `observaciones`, `anulada`, `version` e historial de correcciones. Índice único por alquiler y tipo; índices de vehículo/fecha y severidad/fecha.', '',
          '`bitacora_operaciones`: `_id`, acción, actor, fecha y datos variables del evento. Índice de fecha descendente. La auditoría oficial de reservas se conserva en PostgreSQL, incluso si la proyección documental está pendiente.', '',
          'Las listas variables de daños y evidencias justifican el almacenamiento documental. Las relaciones monetarias y el control de disponibilidad permanecen en el motor relacional. No existen FK entre motores; la API verifica pertenencia e identidad del alquiler.', '']
(root/'docs/DICCIONARIO.md').write_text('\n'.join(lines),encoding='utf-8')
(root/'docs/modelo-chen.dot').write_text('\n'.join(dot),encoding='utf-8')
print(f'Diccionario de {len(tables)} entidades y fuente Chen generados.')
