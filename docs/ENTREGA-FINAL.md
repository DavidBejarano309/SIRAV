# Entrega final del proyecto SIRAV

Sistema Integral de Reservas y Alquiler de Vehículos. Proyecto final de Bases de Datos 2, Universidad El Bosque.

Integrantes: David Felipe Bejarano Montes y Jose David Rodriguez. Docente: Ing., Esp., M.Ed. Christian Felipe Duarte. Fecha: 11 de noviembre de 2026.

Repositorio: https://github.com/DavidBejarano309/SIRAV (aplicación en el PR #17 y documentación en el PR #18). Seguimiento en Jira, proyecto SIRAV.

Cada documento viene en PDF para leerlo directamente. Los originales editables (Markdown, DOCX y fuentes de los diagramas) están en el repositorio y en `08_Repositorio/`.

## Entregables de la propuesta (sección 8)

| Fase | Entregable | Archivo | Jira | Estado |
|---|---|---|---|---|
| Fase 1 | Documento de propuesta (v1.2) | `01_Fase1_Propuesta_y_Gestion/SIRAV_Propuesta_v1.2.docx` y `.pdf` | SIRAV-1 | Completo |
| Fase 1 | Documento de supuestos | `01_Fase1_Propuesta_y_Gestion/Supuestos.pdf`, `Supuestos_SIRAV_v2.0.docx` (101 supuestos) y `Supuestos_cumplimiento.pdf` | SIRAV-9 | Completo |
| Fase 1 | Requerimientos priorizados con trazabilidad | `01_Fase1_Propuesta_y_Gestion/Requerimientos.pdf` | SIRAV-9 | Completo |
| Fase 1 | Matriz de riesgos | `01_Fase1_Propuesta_y_Gestion/Matriz_de_riesgos.pdf` | SIRAV-9 | Completo |
| Fase 1 | Gantt, RACI y metodología | `01_Fase1_Propuesta_y_Gestion/Gestion_Gantt_RACI.pdf` y `SIRAV_Gantt.png` | SIRAV-10 | Completo |
| Fase 1 | Modelo E-R (Chen) y E-R extendido (EER) | `02_Modelado/SIRAV_ER_Chen.png` y `SIRAV_ER_Extendido.png` | SIRAV-11 | Completo |
| Fase 1 | E-R lógico y modelo relacional en Crow's Foot | `02_Modelado/SIRAV_Logico_CrowsFoot.png` y `SIRAV_Relacional_CrowsFoot.png` | SIRAV-12 | Completo (generados del catálogo de PostgreSQL) |
| Fase 1 | Diccionario de datos y verificación de 3FN | `02_Modelado/Diccionario_de_datos.pdf` | SIRAV-13 | Completo |
| Fase 1 | Documento SQL de reportes | `02_Modelado/Reportes_SQL_R1-R6.pdf` | SIRAV-22 | Completo |
| Fase 2 | Análisis de selección de SO y de RDBMS | `03_Fase2_Infraestructura/Seleccion_SO_y_RDBMS.pdf` | SIRAV-14 | Completo |
| Fase 2 | VM implementada | Tres VM Ubuntu Server 24.04 en VirtualBox: `03_Fase2_Infraestructura/Guia_de_instalacion.pdf`, `VM_bases_de_datos.pdf` y `VM_web.pdf` | SIRAV-15 | Completo |
| Fase 2 | Instalación, puertos, arranque y respaldos | `03_Fase2_Infraestructura/Guia_de_instalacion.pdf` y `Politica_de_respaldos.pdf` | SIRAV-35 | Completo. Pendiente: ejecutar el primer respaldo real en las VM |
| Fase 2 | RDBMS implementado y scripts de creación, inserción y varios | `04_PostgreSQL/` | SIRAV-16 a 21, 24, 32 | Completo |
| Fase 2 | Modelo documental e implementación en MongoDB | `05_MongoDB/` | SIRAV-23, 25, 26 | Completo |
| Fase 2 | Conexiones de la aplicación a ambas bases | `08_Repositorio/SIRAV_codigo_fuente.zip` (`backend/`) | SIRAV-27 a 31 | Completo |
| Fase 2 | Pruebas de concurrencia y de punta a punta | `06_Pruebas_y_Evidencias/` (plan, auditoría en las VM y evidencias) | SIRAV-18, 33, 34 | Completo |
| Fase 2 | Repositorio Git | GitHub y `08_Repositorio/` | SIRAV-8 | Completo |
| Fase 2 | Video demostrativo (máx. 15 min) | `07_Cierre/Guion_del_video.pdf` (diálogos de David y Jose David) | SIRAV-37 | Pendiente: grabar |
| Cierre | Informe ejecutivo (máx. 5 páginas) | `07_Cierre/SIRAV_Informe_Ejecutivo.pdf` (4 páginas) y `.docx` | SIRAV-36 | Completo |

## Resultados verificables

- **Despliegue:** tres VM de 2 GB (PostgreSQL 17.6, MongoDB 8.0.5 y web con Nginx, React y la API Java 21), auditadas el 10 y 11 de noviembre de 2026.
- **Pruebas:**
  - Auditoría en las VM: **81 aprobadas** (72 de Java, 5 de interfaz y 4 de navegador) y 64 solicitudes concurrentes.
  - GitHub Actions: las 72 de Java y la prueba de las ocho excepciones SR001 a SR008 corren en cada cambio.
- **Reglas en la base:**
  - Restricción de exclusión GiST y bloqueo `FOR UPDATE`: dos reservas simultáneas del mismo vehículo producen un solo ganador.
  - Ocho excepciones con nombre (`e_reserva_solapada`, `e_transicion_invalida`, …).
  - Usuario de la aplicación sin escritura directa sobre reservas ni pagos.

## Carpetas

| Carpeta | Contenido |
|---|---|
| `01_Fase1_Propuesta_y_Gestion/` | Propuesta, supuestos (resumen, documento v2.0 y cumplimiento), requerimientos, riesgos, gestión y backlog de Jira |
| `02_Modelado/` | Diagramas Chen, EER, Crow's Foot lógico y relacional, y estados; diccionario; reportes; `fuentes/` con los `.dot` y `.mmd` |
| `03_Fase2_Infraestructura/` | Selección de SO y RDBMS, guía de instalación, documentos de las VM, política de respaldos, diagramas de arquitectura y scripts de despliegue (`virtualbox/`) |
| `04_PostgreSQL/` | `01-schema.sql` a `07-concurrency-validation.sql`, `init.sh`, `actualizar-excepciones-con-nombre.sql`, `pruebas-excepciones.sql` y los seis reportes (`reportes/`) |
| `05_MongoDB/` | Modelo documental (PDF y diagrama) e `init.js` |
| `06_Pruebas_y_Evidencias/` | Plan y resultados de pruebas, auditoría en las VM, capturas y salidas de las pruebas |
| `07_Cierre/` | Informe ejecutivo y guion del video |
| `08_Repositorio/` | Código fuente completo en esta versión (`git archive`) |

## Pendientes del equipo antes de entregar

1. Publicar la API nueva y actualizar la base de las VM, en ese orden (guía de instalación, parte A).
2. Ejecutar en las VM el primer respaldo real y su ensayo de restauración (`backup-vms.ps1` y `test-backup-vms.ps1`).
3. Grabar el video con el guion (SIRAV-37).
4. Completar el estado del riesgo R4 (reparto del trabajo) en la matriz de riesgos.
5. Revisar y fusionar el PR #18 y luego el #17 a `develop`.
