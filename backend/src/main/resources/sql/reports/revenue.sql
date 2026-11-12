-- R2: pagos agregados antes del JOIN para no multiplicar importes por cargos.
WITH cobros AS (
 SELECT p.id_alquiler,date_trunc('month',p.fecha_pago AT TIME ZONE 'America/Bogota') mes,sum(p.monto) total
 FROM pago p WHERE p.estado='APROBADO' AND p.fecha_pago>=CAST(:from AS date)::timestamp AT TIME ZONE 'America/Bogota' AND p.fecha_pago<CAST(:to AS date)::timestamp AT TIME ZONE 'America/Bogota'
 GROUP BY p.id_alquiler,date_trunc('month',p.fecha_pago AT TIME ZONE 'America/Bogota')
)
SELECT c.nombre categoria,to_char(co.mes,'YYYY-MM') mes,count(*) alquileres,sum(co.total) ingresos_simulados
FROM cobros co JOIN alquiler a USING(id_alquiler) JOIN reserva r USING(id_reserva) JOIN tarifa t USING(id_tarifa) JOIN categoria_vehiculo c ON c.id_categoria=t.id_categoria
GROUP BY c.nombre,co.mes ORDER BY co.mes,c.nombre
