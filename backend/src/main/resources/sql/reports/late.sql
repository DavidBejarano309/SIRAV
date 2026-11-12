-- R5: retrasos y cargos, HAVING sobre agregación sin unir pagos.
SELECT v.placa,c.nombres||' '||c.apellidos cliente,a.id_alquiler,r.fecha_fin fecha_prevista,
 (a.fecha_devolucion AT TIME ZONE 'America/Bogota')::date fecha_real,
 greatest(0,(a.fecha_devolucion AT TIME ZONE 'America/Bogota')::date-r.fecha_fin) dias_retraso,
 coalesce(sum(ca.monto),0) cargos
FROM alquiler a JOIN reserva r USING(id_reserva) JOIN v_cliente_contacto c USING(id_cliente) JOIN vehiculo v USING(id_vehiculo)
LEFT JOIN cargo_adicional ca ON ca.id_alquiler=a.id_alquiler
WHERE a.estado='CERRADA' AND (a.fecha_devolucion AT TIME ZONE 'America/Bogota')::date>=:from AND (a.fecha_devolucion AT TIME ZONE 'America/Bogota')::date<:to
GROUP BY v.placa,c.nombres,c.apellidos,a.id_alquiler,r.fecha_fin
HAVING (a.fecha_devolucion AT TIME ZONE 'America/Bogota')::date>r.fecha_fin OR coalesce(sum(ca.monto),0)>0
ORDER BY dias_retraso DESC
