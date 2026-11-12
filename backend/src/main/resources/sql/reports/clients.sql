-- R4: agregación condicional, tasa de cancelación y clasificación de clientes.
WITH actividad AS (
 SELECT c.id_cliente,c.nombres||' '||c.apellidos cliente,count(r.id_reserva) reservas,count(r.id_reserva) FILTER(WHERE r.estado='CANCELADA') canceladas,
 coalesce(sum(fn_calcular_costo(r.id_reserva)) FILTER(WHERE r.estado='CERRADA'),0) valor_base_cerrado
 FROM v_cliente_contacto c LEFT JOIN reserva r ON r.id_cliente=c.id_cliente AND (r.fecha_solicitud AT TIME ZONE 'America/Bogota')::date>=:from AND (r.fecha_solicitud AT TIME ZONE 'America/Bogota')::date<:to
 GROUP BY c.id_cliente,c.nombres,c.apellidos
)
SELECT *,round(100.0*canceladas/nullif(reservas,0),2) tasa_cancelacion,dense_rank() OVER(ORDER BY reservas DESC) posicion FROM actividad ORDER BY reservas DESC,cliente
