# Guion del video demostrativo — SIRAV

Historia de Jira: **SIRAV-37**. Duración máxima: **15 minutos**, con la participación de los dos integrantes. Sigue la demostración prevista en la sección 9 de la propuesta.

**Antes de grabar:**

- [ ] VM encendida, `docker compose ps` con los cuatro servicios arriba y la reserva de prueba del script ya cerrada.
- [ ] Navegador del anfitrión en `http://localhost:8088`, en una ventana privada.
- [ ] Una terminal SSH en la VM y otra con `psql` abierta (`docker compose exec postgres psql -U sirav_owner -d sirav_3fn`).
- [ ] Elegir un vehículo libre hoy y mañana; anotar su placa.
- [ ] Resolución de pantalla 1920×1080 y fuente de la terminal en 16 pt o más.

| Tiempo | Quién | Pantalla | Qué se muestra y se dice |
|---|---|---|---|
| 0:00 – 1:00 | David | Diapositiva o README | Presentación: problema (dobles asignaciones e inspecciones sin estructura), objetivo y equipo |
| 1:00 – 2:30 | Jose David | `docs/diagramas/` | Modelo E-R (Chen), EER con las dos especializaciones y relacional en Crow's Foot. Mencionar la corrección a 3FN de la identidad del cliente |
| 2:30 – 3:30 | Jose David | Arquitectura | React → API REST → procedimientos `sp_` en PostgreSQL; outbox → MongoDB; todo en Docker dentro de la VM |
| 3:30 – 5:00 | David | Navegador, perfil **cliente** | Catálogo con fechas; un vehículo disponible; crear la reserva (por dentro, `sp_crear_reserva`); ver el costo base |
| 5:00 – 6:00 | David | Navegador + `psql` | Intentar otra reserva del mismo vehículo con fechas superpuestas: la aplicación muestra *"El vehículo no está disponible en esas fechas"*. En `psql`, mostrar `ex_reserva_vehiculo_periodo` (`\d reserva`) y el código `SR001 e_reserva_solapada` |
| 6:00 – 6:45 | Jose David | Terminal | Concurrencia: explicar la prueba `concurrentReservationsHaveExactlyOneWinner` (dos hilos, un ganador) y mostrar el resultado en GitHub Actions |
| 6:45 – 9:00 | Jose David | Navegador, perfil **operador** | Confirmar la reserva; registrar la entrega con kilometraje, combustible e inspección; registrar la devolución con un daño de severidad ALTA; ver el pago SIMULADO y el historial (`auditoria_reserva`) |
| 9:00 – 10:30 | David | Navegador + `mongosh` | Inspecciones en MongoDB: documento con `danos[]`, corrección con versión e historial; consulta de daños ALTA (`$elemMatch`) y las tres agregaciones |
| 10:30 – 11:30 | Jose David | Navegador, pantalla **Reportes** | Un reporte SQL (R3, ranking con `rank() OVER`) y R6 (disponibilidad) |
| 11:30 – 12:30 | David | `psql` | Seguridad: `SET ROLE sirav_app; DELETE FROM reserva;` → *permission denied*; `SET ROLE sirav_reportes; SELECT password_hash FROM usuario;` → *permission denied* |
| 12:30 – 14:00 | Jose David | Terminal SSH en la VM | `lsb_release -a`, `docker compose ps`, `bash scripts/verificar-despliegue.sh` y `bash scripts/backup.sh` |
| 14:00 – 15:00 | David | GitHub y Jira | Repositorio con ramas y PR, integración continua en verde, tablero de Jira y cierre con lecciones aprendidas |

**Frases clave:**

- "La regla de no solapar reservas la garantiza la base de datos, no la pantalla: aunque dos personas reserven al mismo tiempo, solo una lo logra."
- "PostgreSQL es la fuente de verdad. MongoDB guarda las inspecciones, que tienen una estructura variable, y el outbox evita perderlas."
- "Todo corre en cuatro contenedores en Ubuntu Server, y la instalación está verificada automáticamente en cada cambio."

**Después de grabar:** subir el video, poner el enlace en el README y en SIRAV-37, y guardar las capturas de la sección 11 de la guía de instalación.
