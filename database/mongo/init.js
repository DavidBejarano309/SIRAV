const appDb=db.getSiblingDB('sirav_3fn');
appDb.createUser({user:'sirav_app',pwd:process.env.MONGO_PASSWORD,roles:[{role:'readWrite',db:'sirav'}]});
appDb.createCollection('inspecciones_vehiculo',{validator:{$jsonSchema:{bsonType:'object',required:['alquilerId','vehiculoId','tipo','danos','anulada'],properties:{tipo:{enum:['ENTREGA','DEVOLUCION']},danos:{bsonType:'array'},anulada:{bsonType:'bool'}}}}});
appDb.inspecciones_vehiculo.createIndex({alquilerId:1,tipo:1},{unique:true});
appDb.inspecciones_vehiculo.createIndex({vehiculoId:1,fecha:-1});
appDb.inspecciones_vehiculo.createIndex({'danos.severidad':1,fecha:-1});
appDb.createCollection('bitacora_operaciones');
appDb.bitacora_operaciones.createIndex({fecha:-1});
