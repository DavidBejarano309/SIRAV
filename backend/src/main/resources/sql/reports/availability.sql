-- R6: anti joins correlacionados y función de disponibilidad.
SELECT v.placa,v.marca,v.modelo,c.nombre categoria,t.valor_diario,CAST(:to AS date)-CAST(:from AS date) dias,
 (CAST(:to AS date)-CAST(:from AS date))*t.valor_diario costo_base
FROM vehiculo v JOIN categoria_vehiculo c USING(id_categoria) JOIN tarifa t USING(id_categoria)
WHERE v.estado_operativo<>'INACTIVO' AND t.vigente_desde<=:from AND (t.vigente_hasta IS NULL OR t.vigente_hasta>=:to)
 AND fn_vehiculo_disponible(v.id_vehiculo,CAST(:from AS date),CAST(:to AS date))
 AND NOT EXISTS(SELECT 1 FROM mantenimiento m WHERE m.id_vehiculo=v.id_vehiculo AND m.estado='PROGRAMADO' AND daterange(m.fecha_inicio,m.fecha_fin,'[)') && daterange(CAST(:from AS date),CAST(:to AS date),'[)'))
ORDER BY t.valor_diario,v.placa
