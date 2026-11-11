-- R3: top cinco con empates usando función de ventana por categoría.
WITH conteo AS (
 SELECT c.nombre categoria,v.placa,count(a.id_alquiler) alquileres
 FROM vehiculo v JOIN categoria_vehiculo c USING(id_categoria)
 LEFT JOIN reserva r USING(id_vehiculo)
 LEFT JOIN alquiler a ON a.id_reserva=r.id_reserva AND (a.fecha_entrega AT TIME ZONE 'America/Bogota')::date>=:from AND (a.fecha_entrega AT TIME ZONE 'America/Bogota')::date<:to
 GROUP BY c.nombre,v.placa
), posiciones AS (SELECT *,rank() OVER(PARTITION BY categoria ORDER BY alquileres DESC) puesto FROM conteo)
SELECT * FROM posiciones WHERE puesto<=5 ORDER BY categoria,puesto,placa
