# Matriz de riesgos — SIRAV

Riesgos identificados en la propuesta (Tabla 11), con su probabilidad, impacto y mitigación. La última columna registra cómo quedó cada riesgo al cierre del proyecto; R7 se identificó durante la ejecución.

| ID | Riesgo | Probabilidad | Impacto | Mitigación | Estado al cierre |
|---|---|---|---|---|---|
| R1 | Curva de aprendizaje de restricciones de exclusión y PL/pgSQL. | Media | Alto | Prototipo en la semana 1; alternativa con trigger y bloqueo de filas (`SELECT FOR UPDATE`). | **Mitigado.** Se usan las dos defensas a la vez: exclusión GiST y `FOR UPDATE`. La prueba de concurrencia confirma un solo ganador. |
| R2 | Recursos insuficientes del equipo para la VM. | Media | Alto | Perfil mínimo de 4 GB; probar la VM en la semana 1. | **Abierto.** El despliegue con Docker Compose está listo y documentado; falta instalarlo en la VM (SIRAV-15). |
| R3 | Retraso al integrar Spring Boot con dos bases de datos. | Media | Alto | Probar ambas conexiones en la semana 2, antes de construir la interfaz. | **Ocurrió y se resolvió.** El usuario de MongoDB tenía permisos sobre otra base y el backend no arrancaba; se corrigió en `database/mongo/init.js`. El patrón outbox evita perder inspecciones si MongoDB no responde. |
| R4 | Reparto desigual de trabajo o integrante no disponible (equipo de dos). | Media | Alto | Revisión semanal, puntos de historia por persona en Jira y respaldo cruzado de roles. | *A completar por el equipo con el registro de Jira y GitHub.* |
| R5 | Crecimiento del alcance con funciones nuevas. | Alta | Medio | Alcance congelado; lo adicional pasa a ampliaciones futuras. | **Controlado.** Se retiraron funciones accesorias: tablero de indicadores, administración avanzada de usuarios y exportación CSV (`docs/CAMBIOS-3FN.md`). |
| R6 | Pérdida de código o de la máquina virtual. | Baja | Alto | Repositorio en GitHub, scripts de despliegue, instantánea de la VM y copias de las bases. | **Mitigado.** Repositorio con integración continua y `scripts/backup.sh` (`pg_dump` y `mongodump`). Falta la instantánea de la VM. |
| R7 | Dos versiones del esquema en paralelo (scripts sueltos y aplicación). | Media | Alto | Elegir una sola fuente de verdad y alinear la documentación. | **Ocurrió y se resolvió.** Se adoptó el esquema de la aplicación (PR #17), se cerraron los PR del esquema anterior y se actualizaron supuestos, requerimientos, diagramas y diccionario. |

## Escala

- **Probabilidad:** Baja (poco probable en el plazo de 4 semanas), Media (puede ocurrir), Alta (es probable que ocurra).
- **Impacto:** Medio (retrasa una entrega parcial), Alto (compromete la entrega final o un requisito obligatorio).
