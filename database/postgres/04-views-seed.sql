CREATE VIEW v_reservas AS
SELECT r.*, c.nombres||' '||c.apellidos cliente, c.id_usuario,
 v.placa,v.marca,v.modelo,v.id_categoria,cv.nombre categoria,t.valor_diario,
 fn_calcular_costo(r.id_reserva) costo_base,a.id_alquiler,a.estado estado_alquiler,
 a.fecha_entrega,a.fecha_devolucion,a.km_salida,a.km_entrada,
 coalesce(cargos.total,0) cargos,coalesce(pagos.total,0) pagado,v.kilometraje_actual
FROM reserva r JOIN v_cliente_contacto c USING(id_cliente) JOIN vehiculo v USING(id_vehiculo)
JOIN categoria_vehiculo cv USING(id_categoria) JOIN tarifa t ON t.id_tarifa=r.id_tarifa
LEFT JOIN alquiler a USING(id_reserva)
LEFT JOIN LATERAL(SELECT sum(monto) total FROM cargo_adicional WHERE id_alquiler=a.id_alquiler) cargos ON true
LEFT JOIN LATERAL(SELECT sum(monto) total FROM pago WHERE id_alquiler=a.id_alquiler AND estado='APROBADO') pagos ON true;

INSERT INTO rol(nombre) VALUES ('ADMIN'),('OPERADOR'),('CLIENTE');
INSERT INTO categoria_vehiculo(nombre,descripcion) VALUES
 ('Compacto','Ágil para recorrer la ciudad'),('SUV','Espacio y comodidad para cada destino'),('Sedán','Confort para viajes de negocios');
INSERT INTO vehiculo(id_categoria,placa,marca,modelo,anio,color,kilometraje_actual,estado_operativo) VALUES
 (1,'SIR101','Renault','Kwid',2024,'Blanco',12500,'DISPONIBLE'),
 (1,'SIR102','Kia','Picanto',2025,'Gris',8200,'DISPONIBLE'),
 (2,'SIR201','Mazda','CX-30',2025,'Rojo',15000,'DISPONIBLE'),
 (2,'SIR202','Renault','Duster',2024,'Verde',21000,'DISPONIBLE'),
 (3,'SIR301','Toyota','Corolla',2025,'Plata',6500,'DISPONIBLE'),
 (3,'SIR302','Nissan','Versa',2024,'Azul',18300,'DISPONIBLE');
INSERT INTO tarifa(id_categoria,valor_diario,vigente_desde) VALUES(1,120000,'2020-01-01'),(2,240000,'2020-01-01'),(3,180000,'2020-01-01');
