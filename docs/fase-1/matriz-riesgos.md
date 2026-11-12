# Matriz de riesgos — SIRAV

Riesgos identificados en la propuesta (Tabla 11), con su probabilidad, impacto y mitigación. La última columna registra cómo quedó cada riesgo al cierre del proyecto; R7 se identificó durante la ejecución.

| ID | Riesgo | Probabilidad | Impacto | Mitigación | Estado al cierre |
|---|---|---|---|---|---|
| R1 | Curva de aprendizaje de restricciones de exclusión y PL/pgSQL. | Media | Alto | Prototipo en la semana 1; alternativa con trigger y bloqueo de filas (`SELECT FOR UPDATE`). | **Mitigado.** Se usan las dos defensas a la vez: exclusión GiST y `FOR UPDATE`. La prueba de concurrencia confirma un solo ganador. |
| R2 | Recursos insuficientes del equipo para la VM. | Media | Alto | Perfil mínimo de 4 GB; probar la VM en la semana 1. | **Mitigado.** Se dividió el sistema en tres VM de 2 GB cada una (PostgreSQL, MongoDB y web) en lugar de una sola de 4 a 6 GB. Uso observado: entre 375 y 567 MB por VM. El modo de virtualización NEM hace lento el arranque (cerca de 11 min la API). |
| R3 | Retraso al integrar Spring Boot con dos bases de datos. | Media | Alto | Probar ambas conexiones en la semana 2, antes de construir la interfaz. | **Ocurrió y se resolvió.** El usuario de MongoDB tenía permisos sobre otra base y el backend no arrancaba; se corrigió en `database/mongo/init.js`. El patrón outbox evita perder inspecciones si MongoDB no responde. |
| R4 | Reparto desigual de trabajo o integrante no disponible (equipo de dos). | Media | Alto | Revisión semanal, puntos de historia por persona en Jira y respaldo cruzado de roles. | *A completar por el equipo con el registro de Jira y GitHub.* |
| R5 | Crecimiento del alcance con funciones nuevas. | Alta | Medio | Alcance congelado; lo adicional pasa a ampliaciones futuras. | **Ocurrió de forma controlada.** El documento de supuestos v2.0 (101 supuestos) amplió el alcance: administración básica de cuentas, perfil, historial, cargos y fotos de evidencia. Cada supuesto quedó trazado en `docs/SUPUESTOS-CUMPLIMIENTO.md` y probado por la auditoría. No se agregaron funciones fuera de los supuestos (sin tablero de indicadores ni exportación CSV). |
| R6 | Pérdida de código o de la máquina virtual. | Baja | Alto | Repositorio en GitHub, scripts de despliegue, instantánea de la VM y copias de las bases. | **Mitigado en parte.** Repositorio con integración continua; política de respaldos con SHA-256 y scripts para las tres VM (`backup-vms.ps1`, `test-backup-vms.ps1`). Falta ejecutar el primer respaldo real y el ensayo de restauración en las VM. El procedimiento está verificado en el despliegue Docker. |
| R7 | Dos versiones del esquema en paralelo (scripts sueltos y aplicación). | Media | Alto | Elegir una sola fuente de verdad y alinear la documentación. | **Ocurrió y se resolvió.** Se adoptó el esquema de la aplicación (PR #17), se cerraron los PR del esquema anterior y se actualizaron supuestos, requerimientos, diagramas y diccionario. La versión del equipo del 11 de noviembre se integró sobre esa misma base. |

## Escala

- **Probabilidad:** Baja (poco probable en el plazo de 4 semanas), Media (puede ocurrir), Alta (es probable que ocurra).
- **Impacto:** Medio (retrasa una entrega parcial), Alto (compromete la entrega final o un requisito obligatorio).
