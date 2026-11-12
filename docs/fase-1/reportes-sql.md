# Documento SQL de reportes

Historia de Jira: **SIRAV-22**. Son los seis reportes de la propuesta (sección 6.6, Tabla 9). Cada consulta está en `backend/src/main/resources/sql/reports/<nombre>.sql` y la aplicación la ejecuta con `GET /api/reports/<nombre>?from=AAAA-MM-DD&to=AAAA-MM-DD`, desde la pantalla **Reportes** (perfiles ADMIN y OPERADOR).

**Parámetros.** `:from` es el primer día incluido y `:to` el primer día excluido: el periodo es `[from, to)`, igual que las reservas. Las fechas con hora se convierten a la zona America/Bogota antes de compararlas.

**Verificación.** La prueba `allSixSqlReportsExecuteAgainstRealDatabase` (`IntegrationTest`) ejecuta los seis reportes contra PostgreSQL real en cada corrida de la integración continua.

| Reporte | Archivo | Técnica SQL principal |
|---|---|---|
| R1. Ocupación de cada vehículo por mes | `occupancy.sql` | `generate_series`, `CROSS JOIN`, rangos `tstzrange` y `FILTER` |
| R2. Ingresos simulados por categoría y por mes | `revenue.sql` | CTE de agregación previa, `JOIN` y `GROUP BY` |
| R3. Los cinco vehículos más alquilados de cada categoría | `ranking.sql` | Función de ventana `rank() OVER (PARTITION BY …)` |
| R4. Clientes con más reservas y su tasa de cancelación | `clients.sql` | `FILTER`, `NULLIF`, `dense_rank()` y vista `v_cliente_contacto` |
| R5. Devoluciones tardías y cargos adicionales | `late.sql` | `JOIN` múltiple, `LEFT JOIN` y `HAVING` |
| R6. Vehículos disponibles en un rango de fechas | `availability.sql` | `fn_vehiculo_disponible`, `NOT EXISTS` y `daterange` |

## R1. Ocupación de cada vehículo por mes

**Qué responde:** Días alquilados frente a días del periodo, por vehículo y mes.

**Técnica:** `generate_series` crea un calendario de días; `CROSS JOIN` con la flota; `LEFT JOIN` con los alquileres cuyo rango `tstzrange` se cruza con cada día (`&&`); `count(DISTINCT …) FILTER` evita contar dos veces un día con dos alquileres.

**Columnas del resultado:** placa, mes, dias_alquilados, dias_periodo, ocupacion_porcentaje.

```sql
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
```

## R2. Ingresos simulados por categoría y por mes

**Qué responde:** Suma de los pagos APROBADOS del periodo, por categoría y mes.

**Técnica:** CTE que agrega los pagos **antes** del `JOIN` (si se uniera primero con los cargos, los montos se multiplicarían); `date_trunc` en hora de Bogotá; `GROUP BY` por categoría y mes.

**Columnas del resultado:** categoria, mes, alquileres, ingresos_simulados.

```sql
-- R2: pagos agregados antes del JOIN para no multiplicar importes por cargos.
WITH cobros AS (
 SELECT p.id_alquiler,date_trunc('month',p.fecha_pago AT TIME ZONE 'America/Bogota') mes,sum(p.monto) total
 FROM pago p WHERE p.estado='APROBADO' AND p.fecha_pago>=CAST(:from AS date)::timestamp AT TIME ZONE 'America/Bogota' AND p.fecha_pago<CAST(:to AS date)::timestamp AT TIME ZONE 'America/Bogota'
 GROUP BY p.id_alquiler,date_trunc('month',p.fecha_pago AT TIME ZONE 'America/Bogota')
)
SELECT c.nombre categoria,to_char(co.mes,'YYYY-MM') mes,count(*) alquileres,sum(co.total) ingresos_simulados
FROM cobros co JOIN alquiler a USING(id_alquiler) JOIN reserva r USING(id_reserva) JOIN vehiculo v USING(id_vehiculo) JOIN categoria_vehiculo c USING(id_categoria)
GROUP BY c.nombre,co.mes ORDER BY co.mes,c.nombre
```

## R3. Los cinco vehículos más alquilados de cada categoría

**Qué responde:** Entregas del periodo por vehículo y su puesto dentro de la categoría.

**Técnica:** Función de ventana `rank() OVER (PARTITION BY categoria ORDER BY alquileres DESC)`; los empates comparten puesto; `LEFT JOIN` para incluir vehículos sin alquileres.

**Columnas del resultado:** categoria, placa, alquileres, puesto.

```sql
-- R3: top cinco con empates usando función de ventana por categoría.
WITH conteo AS (
 SELECT c.nombre categoria,v.placa,count(a.id_alquiler) alquileres
 FROM vehiculo v JOIN categoria_vehiculo c USING(id_categoria)
 LEFT JOIN reserva r USING(id_vehiculo)
 LEFT JOIN alquiler a ON a.id_reserva=r.id_reserva AND (a.fecha_entrega AT TIME ZONE 'America/Bogota')::date>=:from AND (a.fecha_entrega AT TIME ZONE 'America/Bogota')::date<:to
 GROUP BY c.nombre,v.placa
), posiciones AS (SELECT *,rank() OVER(PARTITION BY categoria ORDER BY alquileres DESC) puesto FROM conteo)
SELECT * FROM posiciones WHERE puesto<=5 ORDER BY categoria,puesto,placa
```

## R4. Clientes con más reservas y su tasa de cancelación

**Qué responde:** Reservas, cancelaciones y valor base cerrado por cliente.

**Técnica:** Agregación condicional con `FILTER (WHERE estado = …)`, `NULLIF` para no dividir entre cero, `dense_rank()` para la posición y la vista `v_cliente_contacto` para el nombre de clientes con o sin cuenta.

**Columnas del resultado:** id_cliente, cliente, reservas, canceladas, valor_base_cerrado, tasa_cancelacion, posicion.

```sql
-- R4: agregación condicional, tasa de cancelación y clasificación de clientes.
WITH actividad AS (
 SELECT c.id_cliente,c.nombres||' '||c.apellidos cliente,count(r.id_reserva) reservas,count(r.id_reserva) FILTER(WHERE r.estado='CANCELADA') canceladas,
 coalesce(sum(fn_calcular_costo(r.id_reserva)) FILTER(WHERE r.estado='CERRADA'),0) valor_base_cerrado
 FROM v_cliente_contacto c LEFT JOIN reserva r ON r.id_cliente=c.id_cliente AND (r.fecha_solicitud AT TIME ZONE 'America/Bogota')::date>=:from AND (r.fecha_solicitud AT TIME ZONE 'America/Bogota')::date<:to
 GROUP BY c.id_cliente,c.nombres,c.apellidos
)
SELECT *,round(100.0*canceladas/nullif(reservas,0),2) tasa_cancelacion,dense_rank() OVER(ORDER BY reservas DESC) posicion FROM actividad ORDER BY reservas DESC,cliente
```

## R5. Devoluciones tardías y cargos adicionales

**Qué responde:** Alquileres cerrados en el periodo con retraso o con cargos.

**Técnica:** `JOIN` de alquiler, reserva, cliente y vehículo; `LEFT JOIN` con los cargos; `HAVING` sobre la suma de cargos o los días de retraso calculados con `greatest(0, devolución − fecha_fin)`.

**Columnas del resultado:** placa, cliente, id_alquiler, fecha_prevista, fecha_real, dias_retraso, cargos.

```sql
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
```

## R6. Vehículos disponibles en un rango de fechas

**Qué responde:** Vehículos libres en `[desde, hasta)` con la tarifa vigente y el costo base del periodo.

**Técnica:** `fn_vehiculo_disponible` (reservas vigentes sin cruce) y anti-join correlacionado `NOT EXISTS` con los mantenimientos programados; operador de rangos `&&` sobre `daterange(…, '[)')`.

**Columnas del resultado:** placa, marca, modelo, categoria, valor_diario, dias, costo_base.

```sql
-- R6: anti joins correlacionados y función de disponibilidad.
SELECT v.placa,v.marca,v.modelo,c.nombre categoria,t.valor_diario,CAST(:to AS date)-CAST(:from AS date) dias,
 (CAST(:to AS date)-CAST(:from AS date))*t.valor_diario costo_base
FROM vehiculo v JOIN categoria_vehiculo c USING(id_categoria) JOIN tarifa t USING(id_categoria)
WHERE v.estado_operativo<>'INACTIVO' AND t.vigente_desde<=:from AND (t.vigente_hasta IS NULL OR t.vigente_hasta>=:to)
 AND fn_vehiculo_disponible(v.id_vehiculo,CAST(:from AS date),CAST(:to AS date))
 AND NOT EXISTS(SELECT 1 FROM mantenimiento m WHERE m.id_vehiculo=v.id_vehiculo AND m.estado='PROGRAMADO' AND daterange(m.fecha_inicio,m.fecha_fin,'[)') && daterange(CAST(:from AS date),CAST(:to AS date),'[)'))
ORDER BY t.valor_diario,v.placa
```
