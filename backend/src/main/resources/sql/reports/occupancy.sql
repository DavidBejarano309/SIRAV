-- R1: días distintos; varios alquileres en un mismo día no duplican ocupación.
WITH calendario AS (
 SELECT d::date dia FROM generate_series(CAST(:from AS date),CAST(:to AS date)-1,interval '1 day') d
), actividad AS (
 SELECT v.placa,date_trunc('month',c.dia) mes,count(DISTINCT c.dia) dias_periodo,
 count(DISTINCT c.dia) FILTER(WHERE a.id_alquiler IS NOT NULL) dias_alquilados
 FROM vehiculo v CROSS JOIN calendario c
 LEFT JOIN reserva r ON r.id_vehiculo=v.id_vehiculo
 LEFT JOIN alquiler a ON a.id_reserva=r.id_reserva
 AND tstzrange(a.fecha_entrega,coalesce(a.fecha_devolucion,now()),'[)') &&
     tstzrange(c.dia::timestamp AT TIME ZONE 'America/Bogota',(c.dia+1)::timestamp AT TIME ZONE 'America/Bogota','[)')
 GROUP BY v.placa,date_trunc('month',c.dia)
)
SELECT placa,to_char(mes,'YYYY-MM') mes,dias_alquilados,dias_periodo,
 round(100.0*dias_alquilados/dias_periodo,2) ocupacion_porcentaje
FROM actividad ORDER BY mes,placa
