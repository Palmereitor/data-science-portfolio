-- =====================================================
-- FLEETLOGIX - 12 QUERIES DE ANALISIS SQL
-- Objetivo: documentar consultas basicas, intermedias y complejas
-- para evaluar operacion, eficiencia, costos y servicio.
-- =====================================================

-- QUERY 1 - Conteo general por tabla
-- Negocio: valida que la poblacion supere 505k registros y que
-- todas las entidades principales tengan datos.
SELECT 'vehicles' AS table_name, COUNT(*) AS records FROM vehicles
UNION ALL SELECT 'drivers', COUNT(*) FROM drivers
UNION ALL SELECT 'routes', COUNT(*) FROM routes
UNION ALL SELECT 'trips', COUNT(*) FROM trips
UNION ALL SELECT 'deliveries', COUNT(*) FROM deliveries
UNION ALL SELECT 'maintenance', COUNT(*) FROM maintenance;

-- QUERY 2 - Conductores activos con licencia proxima a vencer
-- Negocio: prioriza renovaciones para evitar interrupciones operativas.
SELECT
    driver_id,
    employee_code,
    first_name || ' ' || last_name AS driver_name,
    license_expiry,
    license_expiry - CURRENT_DATE AS days_to_expiry
FROM drivers
WHERE status = 'active'
  AND license_expiry BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '60 days'
ORDER BY license_expiry;

-- QUERY 3 - Vehiculos por tipo y estado
-- Negocio: muestra disponibilidad real de flota.
SELECT
    vehicle_type,
    status,
    COUNT(*) AS vehicle_count,
    ROUND(AVG(capacity_kg), 2) AS avg_capacity_kg
FROM vehicles
GROUP BY vehicle_type, status
ORDER BY vehicle_type, status;

-- QUERY 4 - Entregas diarias y puntualidad
-- Negocio: KPI base de servicio al cliente.
SELECT
    DATE(d.scheduled_datetime) AS delivery_date,
    COUNT(*) AS total_deliveries,
    SUM(CASE WHEN d.delivered_datetime <= d.scheduled_datetime + INTERVAL '30 minutes' THEN 1 ELSE 0 END) AS on_time_deliveries,
    ROUND(
        SUM(CASE WHEN d.delivered_datetime <= d.scheduled_datetime + INTERVAL '30 minutes' THEN 1 ELSE 0 END)::NUMERIC
        / NULLIF(COUNT(*), 0),
        4
    ) AS on_time_rate
FROM deliveries d
WHERE d.delivery_status = 'delivered'
GROUP BY DATE(d.scheduled_datetime)
ORDER BY delivery_date;

-- QUERY 5 - Ranking de conductores por entregas realizadas
-- Negocio: identifica productividad individual.
SELECT
    dr.driver_id,
    dr.employee_code,
    dr.first_name || ' ' || dr.last_name AS driver_name,
    COUNT(d.delivery_id) AS delivered_packages,
    COUNT(DISTINCT t.trip_id) AS completed_trips
FROM drivers dr
JOIN trips t ON dr.driver_id = t.driver_id
JOIN deliveries d ON t.trip_id = d.trip_id
WHERE t.status = 'completed'
  AND d.delivery_status = 'delivered'
GROUP BY dr.driver_id, dr.employee_code, driver_name
ORDER BY delivered_packages DESC
LIMIT 20;

-- QUERY 6 - Puntualidad por conductor
-- Negocio: compara calidad de servicio, no solo volumen.
SELECT
    dr.driver_id,
    dr.employee_code,
    dr.first_name || ' ' || dr.last_name AS driver_name,
    COUNT(d.delivery_id) AS total_deliveries,
    ROUND(AVG(EXTRACT(EPOCH FROM (d.delivered_datetime - d.scheduled_datetime)) / 60), 2) AS avg_delay_minutes,
    ROUND(
        AVG(CASE WHEN d.delivered_datetime <= d.scheduled_datetime + INTERVAL '30 minutes' THEN 1 ELSE 0 END),
        4
    ) AS on_time_rate
FROM drivers dr
JOIN trips t ON dr.driver_id = t.driver_id
JOIN deliveries d ON t.trip_id = d.trip_id
WHERE d.delivery_status = 'delivered'
GROUP BY dr.driver_id, dr.employee_code, driver_name
HAVING COUNT(d.delivery_id) >= 50
ORDER BY on_time_rate DESC, total_deliveries DESC;

-- QUERY 7 - Eficiencia de combustible por ruta
-- Negocio: detecta rutas con mayor consumo relativo.
SELECT
    r.route_code,
    r.origin_city,
    r.destination_city,
    ROUND(AVG(r.distance_km / NULLIF(t.fuel_consumed_liters, 0)), 2) AS avg_km_per_liter,
    ROUND(AVG(t.fuel_consumed_liters), 2) AS avg_fuel_liters,
    COUNT(t.trip_id) AS trips
FROM routes r
JOIN trips t ON r.route_id = t.route_id
WHERE t.status = 'completed'
GROUP BY r.route_code, r.origin_city, r.destination_city
ORDER BY avg_km_per_liter ASC;

-- QUERY 8 - Distribucion horaria de entregas
-- Negocio: ayuda a dimensionar turnos y ventanas de despacho.
SELECT
    EXTRACT(HOUR FROM scheduled_datetime) AS scheduled_hour,
    COUNT(*) AS deliveries,
    ROUND(AVG(package_weight_kg), 2) AS avg_package_weight
FROM deliveries
GROUP BY scheduled_hour
ORDER BY scheduled_hour;

-- QUERY 9 - Costo de mantenimiento por vehiculo
-- Negocio: senala unidades costosas o candidatas a renovacion.
SELECT
    v.vehicle_id,
    v.license_plate,
    v.vehicle_type,
    COUNT(m.maintenance_id) AS maintenance_events,
    ROUND(COALESCE(SUM(m.cost), 0), 2) AS total_maintenance_cost,
    COUNT(t.trip_id) AS trips,
    ROUND(COALESCE(SUM(m.cost), 0) / NULLIF(COUNT(DISTINCT t.trip_id), 0), 2) AS maintenance_cost_per_trip
FROM vehicles v
LEFT JOIN maintenance m ON v.vehicle_id = m.vehicle_id
LEFT JOIN trips t ON v.vehicle_id = t.vehicle_id
GROUP BY v.vehicle_id, v.license_plate, v.vehicle_type
ORDER BY total_maintenance_cost DESC;

-- QUERY 10 - Rentabilidad estimada por ruta
-- Negocio: combina ingresos estimados, combustible y peajes.
SELECT
    r.route_code,
    r.origin_city,
    r.destination_city,
    COUNT(d.delivery_id) AS deliveries,
    ROUND(SUM(20000 + d.package_weight_kg * 500), 2) AS estimated_revenue,
    ROUND(SUM((t.fuel_consumed_liters * 5000 + r.toll_cost) / NULLIF(delivery_counts.delivery_count, 0)), 2) AS estimated_cost,
    ROUND(
        SUM(20000 + d.package_weight_kg * 500)
        - SUM((t.fuel_consumed_liters * 5000 + r.toll_cost) / NULLIF(delivery_counts.delivery_count, 0)),
        2
    ) AS estimated_margin
FROM routes r
JOIN trips t ON r.route_id = t.route_id
JOIN deliveries d ON t.trip_id = d.trip_id
JOIN (
    SELECT trip_id, COUNT(*) AS delivery_count
    FROM deliveries
    GROUP BY trip_id
) delivery_counts ON t.trip_id = delivery_counts.trip_id
WHERE d.delivery_status = 'delivered'
GROUP BY r.route_code, r.origin_city, r.destination_city
ORDER BY estimated_margin DESC;

-- QUERY 11 - Uso de capacidad de vehiculos
-- Negocio: mide si los viajes salen subutilizados o sobrecargados.
SELECT
    v.vehicle_type,
    COUNT(t.trip_id) AS trips,
    ROUND(AVG(t.total_weight_kg / NULLIF(v.capacity_kg, 0)), 4) AS avg_capacity_utilization,
    ROUND(MIN(t.total_weight_kg / NULLIF(v.capacity_kg, 0)), 4) AS min_capacity_utilization,
    ROUND(MAX(t.total_weight_kg / NULLIF(v.capacity_kg, 0)), 4) AS max_capacity_utilization
FROM vehicles v
JOIN trips t ON v.vehicle_id = t.vehicle_id
WHERE t.status = 'completed'
GROUP BY v.vehicle_type
ORDER BY avg_capacity_utilization DESC;

-- QUERY 12 - Vista mensual ejecutiva
-- Negocio: resume volumen, puntualidad, ingresos y costo por mes.
SELECT
    DATE_TRUNC('month', d.scheduled_datetime)::DATE AS month,
    COUNT(d.delivery_id) AS deliveries,
    COUNT(DISTINCT t.trip_id) AS trips,
    ROUND(AVG(EXTRACT(EPOCH FROM (t.arrival_datetime - t.departure_datetime)) / 3600), 2) AS avg_trip_hours,
    ROUND(AVG(CASE WHEN d.delivered_datetime <= d.scheduled_datetime + INTERVAL '30 minutes' THEN 1 ELSE 0 END), 4) AS on_time_rate,
    ROUND(SUM(20000 + d.package_weight_kg * 500), 2) AS estimated_revenue
FROM deliveries d
JOIN trips t ON d.trip_id = t.trip_id
WHERE d.delivery_status = 'delivered'
GROUP BY month
ORDER BY month;

-- =====================================================
-- QUERIES COMPLEMENTARIAS 13-30
-- Se agregan para cubrir la referencia del enunciado a 30 consultas.
-- Las primeras 12 son las documentadas en detalle en el manual.
-- =====================================================

-- QUERY 13 - Ultimo mantenimiento por vehiculo activo
SELECT
    v.vehicle_id,
    v.license_plate,
    v.vehicle_type,
    MAX(m.maintenance_date) AS last_maintenance_date
FROM vehicles v
LEFT JOIN maintenance m ON v.vehicle_id = m.vehicle_id
WHERE v.status = 'active'
GROUP BY v.vehicle_id, v.license_plate, v.vehicle_type
ORDER BY last_maintenance_date NULLS FIRST;

-- QUERY 14 - Entregas fallidas o pendientes por ciudad destino
SELECT
    r.destination_city,
    d.delivery_status,
    COUNT(*) AS deliveries
FROM deliveries d
JOIN trips t ON d.trip_id = t.trip_id
JOIN routes r ON t.route_id = r.route_id
WHERE d.delivery_status <> 'delivered'
GROUP BY r.destination_city, d.delivery_status
ORDER BY deliveries DESC;

-- QUERY 15 - Peso promedio transportado por tipo de vehiculo
SELECT
    v.vehicle_type,
    COUNT(t.trip_id) AS trips,
    ROUND(AVG(t.total_weight_kg), 2) AS avg_weight_kg
FROM vehicles v
JOIN trips t ON v.vehicle_id = t.vehicle_id
GROUP BY v.vehicle_type
ORDER BY avg_weight_kg DESC;

-- QUERY 16 - Rutas con mayor volumen de paquetes
SELECT
    r.route_code,
    r.origin_city,
    r.destination_city,
    COUNT(d.delivery_id) AS packages
FROM routes r
JOIN trips t ON r.route_id = t.route_id
JOIN deliveries d ON t.trip_id = d.trip_id
GROUP BY r.route_code, r.origin_city, r.destination_city
ORDER BY packages DESC
LIMIT 10;

-- QUERY 17 - Conductores con mayor retraso promedio
SELECT
    dr.driver_id,
    dr.employee_code,
    dr.first_name || ' ' || dr.last_name AS driver_name,
    ROUND(AVG(EXTRACT(EPOCH FROM (d.delivered_datetime - d.scheduled_datetime)) / 60), 2) AS avg_delay_minutes
FROM drivers dr
JOIN trips t ON dr.driver_id = t.driver_id
JOIN deliveries d ON t.trip_id = d.trip_id
WHERE d.delivery_status = 'delivered'
GROUP BY dr.driver_id, dr.employee_code, driver_name
ORDER BY avg_delay_minutes DESC
LIMIT 15;

-- QUERY 18 - Tendencia semanal de entregas
SELECT
    DATE_TRUNC('week', scheduled_datetime)::DATE AS week_start,
    COUNT(*) AS deliveries
FROM deliveries
GROUP BY week_start
ORDER BY week_start;

-- QUERY 19 - Viajes por franja horaria de salida
SELECT
    CASE
        WHEN EXTRACT(HOUR FROM departure_datetime) BETWEEN 6 AND 11 THEN 'Mañana'
        WHEN EXTRACT(HOUR FROM departure_datetime) BETWEEN 12 AND 17 THEN 'Tarde'
        WHEN EXTRACT(HOUR FROM departure_datetime) BETWEEN 18 AND 23 THEN 'Noche'
        ELSE 'Madrugada'
    END AS time_band,
    COUNT(*) AS trips
FROM trips
GROUP BY time_band
ORDER BY trips DESC;

-- QUERY 20 - Costo promedio de mantenimiento por tipo
SELECT
    maintenance_type,
    COUNT(*) AS events,
    ROUND(AVG(cost), 2) AS avg_cost,
    ROUND(SUM(cost), 2) AS total_cost
FROM maintenance
GROUP BY maintenance_type
ORDER BY total_cost DESC;

-- QUERY 21 - Clientes con mas entregas
SELECT
    customer_name,
    COUNT(*) AS deliveries,
    ROUND(SUM(package_weight_kg), 2) AS total_weight_kg
FROM deliveries
GROUP BY customer_name
ORDER BY deliveries DESC, total_weight_kg DESC
LIMIT 20;

-- QUERY 22 - Vehiculos subutilizados
SELECT
    v.vehicle_id,
    v.license_plate,
    v.vehicle_type,
    COUNT(t.trip_id) AS trips,
    ROUND(AVG(t.total_weight_kg / NULLIF(v.capacity_kg, 0)), 4) AS avg_utilization
FROM vehicles v
JOIN trips t ON v.vehicle_id = t.vehicle_id
GROUP BY v.vehicle_id, v.license_plate, v.vehicle_type
HAVING AVG(t.total_weight_kg / NULLIF(v.capacity_kg, 0)) < 0.50
ORDER BY avg_utilization ASC;

-- QUERY 23 - Dia de la semana con mas entregas
SELECT
    EXTRACT(DOW FROM scheduled_datetime) AS day_of_week,
    COUNT(*) AS deliveries
FROM deliveries
GROUP BY day_of_week
ORDER BY deliveries DESC;

-- QUERY 24 - Comparacion de duracion real vs estimada por ruta
SELECT
    r.route_code,
    ROUND(AVG(EXTRACT(EPOCH FROM (t.arrival_datetime - t.departure_datetime)) / 3600), 2) AS avg_real_hours,
    ROUND(AVG(r.estimated_duration_hours), 2) AS avg_estimated_hours,
    ROUND(AVG(EXTRACT(EPOCH FROM (t.arrival_datetime - t.departure_datetime)) / 3600 - r.estimated_duration_hours), 2) AS avg_variance_hours
FROM routes r
JOIN trips t ON r.route_id = t.route_id
WHERE t.status = 'completed'
GROUP BY r.route_code
ORDER BY avg_variance_hours DESC;

-- QUERY 25 - Rutas con mayor costo de peajes acumulado
SELECT
    r.route_code,
    r.origin_city,
    r.destination_city,
    COUNT(t.trip_id) AS trips,
    SUM(r.toll_cost) AS total_toll_cost
FROM routes r
JOIN trips t ON r.route_id = t.route_id
GROUP BY r.route_code, r.origin_city, r.destination_city
ORDER BY total_toll_cost DESC;

-- QUERY 26 - Window function: ranking mensual de rutas por entregas
WITH monthly_route_deliveries AS (
    SELECT
        DATE_TRUNC('month', d.scheduled_datetime)::DATE AS month,
        r.route_code,
        COUNT(*) AS deliveries
    FROM deliveries d
    JOIN trips t ON d.trip_id = t.trip_id
    JOIN routes r ON t.route_id = r.route_id
    GROUP BY month, r.route_code
)
SELECT
    month,
    route_code,
    deliveries,
    RANK() OVER (PARTITION BY month ORDER BY deliveries DESC) AS route_rank
FROM monthly_route_deliveries
ORDER BY month, route_rank;

-- QUERY 27 - Window function: cambio mensual de entregas
WITH monthly_deliveries AS (
    SELECT DATE_TRUNC('month', scheduled_datetime)::DATE AS month, COUNT(*) AS deliveries
    FROM deliveries
    GROUP BY month
)
SELECT
    month,
    deliveries,
    LAG(deliveries) OVER (ORDER BY month) AS previous_month_deliveries,
    deliveries - LAG(deliveries) OVER (ORDER BY month) AS delivery_delta
FROM monthly_deliveries
ORDER BY month;

-- QUERY 28 - CTE: conductores sobre el promedio de puntualidad
WITH driver_rates AS (
    SELECT
        dr.driver_id,
        dr.employee_code,
        ROUND(AVG(CASE WHEN d.delivered_datetime <= d.scheduled_datetime + INTERVAL '30 minutes' THEN 1 ELSE 0 END), 4) AS on_time_rate
    FROM drivers dr
    JOIN trips t ON dr.driver_id = t.driver_id
    JOIN deliveries d ON t.trip_id = d.trip_id
    WHERE d.delivery_status = 'delivered'
    GROUP BY dr.driver_id, dr.employee_code
),
global_rate AS (
    SELECT AVG(on_time_rate) AS avg_rate FROM driver_rates
)
SELECT dr.*
FROM driver_rates dr
CROSS JOIN global_rate gr
WHERE dr.on_time_rate > gr.avg_rate
ORDER BY dr.on_time_rate DESC;

-- QUERY 29 - Subconsulta correlacionada: vehiculos con mantenimiento caro
SELECT
    v.vehicle_id,
    v.license_plate,
    v.vehicle_type
FROM vehicles v
WHERE (
    SELECT COALESCE(SUM(m.cost), 0)
    FROM maintenance m
    WHERE m.vehicle_id = v.vehicle_id
) > (
    SELECT AVG(vehicle_cost)
    FROM (
        SELECT vehicle_id, SUM(cost) AS vehicle_cost
        FROM maintenance
        GROUP BY vehicle_id
    ) costs
);

-- QUERY 30 - Resumen ejecutivo por ciudad destino
SELECT
    r.destination_city,
    COUNT(d.delivery_id) AS deliveries,
    COUNT(DISTINCT t.trip_id) AS trips,
    ROUND(AVG(d.package_weight_kg), 2) AS avg_package_weight,
    ROUND(AVG(CASE WHEN d.delivered_datetime <= d.scheduled_datetime + INTERVAL '30 minutes' THEN 1 ELSE 0 END), 4) AS on_time_rate,
    ROUND(SUM(20000 + d.package_weight_kg * 500), 2) AS estimated_revenue
FROM routes r
JOIN trips t ON r.route_id = t.route_id
JOIN deliveries d ON t.trip_id = d.trip_id
GROUP BY r.destination_city
ORDER BY estimated_revenue DESC;
