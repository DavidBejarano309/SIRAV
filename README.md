# SIRAV — Sistema Integral de Reservas y Alquiler de Vehículos

Proyecto Final de **Bases de Datos 2** — Universidad El Bosque, Ingeniería de Sistemas.

Aplicación web académica para una empresa pequeña de alquiler de vehículos. Controla disponibilidad, reservas, entregas, devoluciones e inspecciones, e impide por diseño que un mismo vehículo quede asignado a períodos que se superponen (regla implementada en la base de datos).

## Tecnologías
| Capa | Tecnología |
|---|---|
| Aplicación | Java, Spring Boot, Spring Security, Thymeleaf, Bootstrap |
| Base relacional | PostgreSQL (PL/pgSQL) |
| Base documental | MongoDB |
| Plataforma | Ubuntu Server en máquina virtual |

## Estructura del repositorio
| Carpeta | Contenido |
|---|---|
| `app/` | Aplicación Spring Boot |
| `db/postgres/` | Scripts SQL numerados (creación, inserción, funciones, procedimientos, triggers, reportes, seguridad) |
| `db/mongo/` | Modelo documental, scripts de colecciones, consultas y agregaciones |
| `infra/` | Guía de instalación de la VM, servicios, puertos y respaldos |
| `docs/fase-1/` | Propuesta, supuestos, modelos E-R y relacional, diccionario de datos, reportes SQL |
| `docs/fase-2/` | Análisis de SO y RDBMS, evidencias de implementación |
| `docs/gestion/` | Backlog Scrum, Gantt, RACI, riesgos |

## Gestión
- Metodología híbrida: modelado secuencial (Fase 1) y Scrum ligero (Fase 2), con sprints semanales.
- Tablero y backlog en Jira (espacio SIRAV).
- Flujo de trabajo y convenciones: ver [CONTRIBUTING.md](CONTRIBUTING.md).

## Equipo
- David Felipe Bejarano Montes
- [Integrante 2]

## Cómo ejecutar
_Pendiente: se completará cuando la aplicación y la VM estén implementadas (ver `infra/`)._
