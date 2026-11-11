// =====================================================================
// SIRAV - MongoDB | 01_colecciones.js  (SIRAV-25)
// Crea las colecciones con validación $jsonSchema, los índices y los
// usuarios de la base. Se puede ejecutar varias veces: recrea todo.
//
// Uso (como administrador, desde db/mongo):
//   mongosh "mongodb://admin:<clave>@localhost:27017/admin" 01_colecciones.js
// Contraseñas de los usuarios de la base por variable de entorno
// (los valores por defecto son solo para pruebas locales):
//   SIRAV_MONGO_APP_PWD, SIRAV_MONGO_REPORTES_PWD
// Autores: David Bejarano, Jose David Rodriguez
// =====================================================================

load('00_comun.js');

const sirav = db.getSiblingDB(SIRAV_DB_NOMBRE);

// Recrear desde cero
sirav.inspecciones_vehiculo.drop();
sirav.bitacora_operaciones.drop();

// ---------------------------------------------------------------------
// inspecciones_vehiculo
// Patrones: Embedding (daños, evidencias y datos del vehículo dentro de la
// inspección), Polymorphic (ENTREGA y DEVOLUCION en la misma colección,
// con forma distinta) y Computed (resumen precalculado en la devolución).
// ---------------------------------------------------------------------
const esquemaDano = {
  bsonType: 'object',
  required: ['zona', 'severidad', 'descripcion', 'nuevo'],
  additionalProperties: false,
  properties: {
    zona:           { enum: ZONAS, description: 'Zona del vehículo' },
    severidad:      { enum: SEVERIDADES },
    descripcion:    { bsonType: 'string', minLength: 3, maxLength: 300 },
    nuevo:          { bsonType: 'bool', description: 'true si no estaba en la inspección de entrega' },
    costo_estimado: { bsonType: ['int', 'long', 'double', 'decimal'], minimum: 0 }
  }
};

const camposComunes = {
  _id:                  { bsonType: 'objectId' },
  tipo:                 { enum: TIPOS_INSPECCION },
  id_alquiler:          { bsonType: ['int', 'long'], minimum: 1, description: 'Referencia lógica a alquiler.id_alquiler de PostgreSQL' },
  vehiculo: {
    bsonType: 'object',
    required: ['id_vehiculo', 'placa', 'categoria'],
    additionalProperties: false,
    properties: {
      id_vehiculo: { bsonType: ['int', 'long'], minimum: 1 },
      placa:       { bsonType: 'string', pattern: '^[A-Z]{3}[0-9]{3}$' },
      categoria:   { bsonType: 'string' }
    }
  },
  fecha:                { bsonType: 'date' },
  km:                   { bsonType: ['int', 'long'], minimum: 0 },
  combustible:          { bsonType: ['int', 'long', 'double', 'decimal'], minimum: 0, maximum: 100, description: 'Porcentaje del tanque' },
  danos:                { bsonType: 'array', maxItems: 30, items: esquemaDano },
  evidencias:           { bsonType: 'array', maxItems: 20, items: { bsonType: 'string', pattern: '^[A-Za-z0-9_.-]+\\.(jpg|jpeg|png)$' } },
  observaciones:        { bsonType: 'string', maxLength: 1000 },
  id_usuario_inspector: { bsonType: ['int', 'long'], minimum: 1 },
  estado:               { enum: ['VIGENTE', 'ANULADA'] },
  anulacion: {
    bsonType: 'object',
    required: ['motivo', 'fecha', 'id_usuario'],
    properties: {
      motivo:     { bsonType: 'string', minLength: 3 },
      fecha:      { bsonType: 'date' },
      id_usuario: { bsonType: ['int', 'long'] }
    }
  },
  version_esquema:      { bsonType: 'int', enum: [1] }
};

const camposRequeridos = ['tipo', 'id_alquiler', 'vehiculo', 'fecha', 'km', 'combustible',
                          'danos', 'evidencias', 'id_usuario_inspector', 'estado', 'version_esquema'];

const esquemaResumen = {
  bsonType: 'object',
  required: ['total_danos', 'danos_nuevos', 'severidad_maxima', 'km_recorridos', 'combustible_consumido', 'monto_danos_estimado'],
  additionalProperties: false,
  properties: {
    total_danos:           { bsonType: 'int', minimum: 0 },
    danos_nuevos:          { bsonType: 'int', minimum: 0 },
    severidad_maxima:      { enum: SEVERIDADES.concat([null]) },
    km_recorridos:         { bsonType: ['int', 'long'], minimum: 0 },
    combustible_consumido: { bsonType: ['int', 'long', 'double', 'decimal'] },
    monto_danos_estimado:  { bsonType: ['int', 'long', 'double', 'decimal'], minimum: 0 }
  }
};

sirav.createCollection('inspecciones_vehiculo', {
  validator: {
    $jsonSchema: {
      bsonType: 'object',
      title: 'Inspección de entrega o devolución de un vehículo',
      // Polymorphic: una forma por tipo
      oneOf: [
        {
          required: camposRequeridos,
          additionalProperties: false,
          properties: Object.assign({}, camposComunes, { tipo: { enum: ['ENTREGA'] } })
        },
        {
          required: camposRequeridos.concat(['resumen']),
          additionalProperties: false,
          properties: Object.assign({}, camposComunes, { tipo: { enum: ['DEVOLUCION'] }, resumen: esquemaResumen })
        }
      ]
    }
  },
  validationLevel: 'strict',
  validationAction: 'error'
});

// Solo una inspección VIGENTE de cada tipo por alquiler (las anuladas no cuentan)
sirav.inspecciones_vehiculo.createIndex(
  { id_alquiler: 1, tipo: 1 },
  { name: 'ux_inspeccion_alquiler_tipo', unique: true, partialFilterExpression: { estado: 'VIGENTE' } }
);
// Historial por vehículo e incidencias por vehículo (SIRAV-26)
sirav.inspecciones_vehiculo.createIndex({ 'vehiculo.id_vehiculo': 1, fecha: -1 }, { name: 'ix_inspeccion_vehiculo_fecha' });
// Consulta compleja: daños de severidad alta en un rango de fechas ($elemMatch)
sirav.inspecciones_vehiculo.createIndex({ 'danos.severidad': 1, fecha: -1 }, { name: 'ix_inspeccion_severidad_fecha' });
// Promedios de km y combustible por categoría
sirav.inspecciones_vehiculo.createIndex({ tipo: 1, 'vehiculo.categoria': 1 }, { name: 'ix_inspeccion_tipo_categoria' });

// ---------------------------------------------------------------------
// bitacora_operaciones
// Patrones: Bucket (un documento por día con hasta BITACORA_MAX_EVENTOS
// eventos) y Polymorphic (cada tipo de evento trae un detalle distinto).
// ---------------------------------------------------------------------
sirav.createCollection('bitacora_operaciones', {
  validator: {
    $jsonSchema: {
      bsonType: 'object',
      title: 'Bucket diario de eventos de la aplicación',
      required: ['fecha', 'count', 'eventos', 'primer_ts', 'ultimo_ts'],
      additionalProperties: false,
      properties: {
        _id:       { bsonType: 'objectId' },
        fecha:     { bsonType: 'date', description: 'Medianoche de Bogotá del día del bucket' },
        count:     { bsonType: 'int', minimum: 1, maximum: BITACORA_MAX_EVENTOS },
        primer_ts: { bsonType: 'date' },
        ultimo_ts: { bsonType: 'date' },
        eventos: {
          bsonType: 'array',
          minItems: 1,
          maxItems: BITACORA_MAX_EVENTOS,
          items: {
            bsonType: 'object',
            required: ['tipo', 'ts', 'detalle'],
            additionalProperties: false,
            properties: {
              tipo:       { enum: TIPOS_EVENTO },
              ts:         { bsonType: 'date' },
              id_usuario: { bsonType: ['int', 'long', 'null'] },
              detalle:    { bsonType: 'object' }
            }
          }
        }
      }
    }
  },
  validationLevel: 'strict',
  validationAction: 'error'
});

sirav.bitacora_operaciones.createIndex({ fecha: 1, count: 1 }, { name: 'ix_bitacora_fecha_count' });
sirav.bitacora_operaciones.createIndex({ 'eventos.tipo': 1, fecha: -1 }, { name: 'ix_bitacora_tipo_fecha' });

// ---------------------------------------------------------------------
// Usuarios de la base (mínimo privilegio, como en PostgreSQL)
//   sirav_app_mongo:      leer, insertar y actualizar; sin borrar ni
//                         eliminar colecciones (anular = actualizar)
//   sirav_reportes_mongo: solo lectura
// ---------------------------------------------------------------------
const vv_pwd_app = (typeof process !== 'undefined' && process.env.SIRAV_MONGO_APP_PWD) || 'Sirav_Mongo_App_2026*';
const vv_pwd_rep = (typeof process !== 'undefined' && process.env.SIRAV_MONGO_REPORTES_PWD) || 'Sirav_Mongo_Reportes_2026*';

if (sirav.getUser('sirav_app_mongo'))      sirav.dropUser('sirav_app_mongo');
if (sirav.getUser('sirav_reportes_mongo')) sirav.dropUser('sirav_reportes_mongo');
if (sirav.getRole('sirav_app_rol'))        sirav.dropRole('sirav_app_rol');

sirav.createRole({
  role: 'sirav_app_rol',
  privileges: [
    { resource: { db: SIRAV_DB_NOMBRE, collection: 'inspecciones_vehiculo' }, actions: ['find', 'insert', 'update'] },
    { resource: { db: SIRAV_DB_NOMBRE, collection: 'bitacora_operaciones' },  actions: ['find', 'insert', 'update'] }
  ],
  roles: []
});

sirav.createUser({ user: 'sirav_app_mongo', pwd: vv_pwd_app, roles: [{ role: 'sirav_app_rol', db: SIRAV_DB_NOMBRE }] });
sirav.createUser({ user: 'sirav_reportes_mongo', pwd: vv_pwd_rep, roles: [{ role: 'read', db: SIRAV_DB_NOMBRE }] });

print('Colecciones: ' + sirav.getCollectionNames().sort().join(', '));
print('Índices de inspecciones_vehiculo: ' + sirav.inspecciones_vehiculo.getIndexes().map(i => i.name).join(', '));
print('Índices de bitacora_operaciones: ' + sirav.bitacora_operaciones.getIndexes().map(i => i.name).join(', '));
print('Usuarios: ' + sirav.getUsers().users.map(u => u.user).sort().join(', '));
