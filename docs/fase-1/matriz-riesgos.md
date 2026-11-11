# Matriz de riesgos — SIRAV

Riesgos identificados en la propuesta (Tabla 11), con su probabilidad, impacto y mitigación.

| ID | Riesgo | Probabilidad | Impacto | Mitigación |
|---|---|---|---|---|
| R1 | Curva de aprendizaje de restricciones de exclusión y PL/pgSQL. | Media | Alto | Prototipo en la semana 1; alternativa con trigger y bloqueo de filas (`SELECT FOR UPDATE`). |
| R2 | Recursos insuficientes del equipo para la VM. | Media | Alto | Perfil mínimo de 4 GB; probar la VM en la semana 1. |
| R3 | Retraso al integrar Spring Boot con dos bases de datos. | Media | Alto | Probar ambas conexiones en la semana 2, antes de construir la interfaz. |
| R4 | Reparto desigual de trabajo o integrante no disponible (equipo de dos). | Media | Alto | Revisión semanal, puntos de historia por persona en Jira y respaldo cruzado de roles. |
| R5 | Crecimiento del alcance con funciones nuevas. | Alta | Medio | Alcance congelado; lo adicional pasa a ampliaciones futuras. |
| R6 | Pérdida de código o de la máquina virtual. | Baja | Alto | Repositorio en GitHub, scripts de despliegue, instantánea de la VM y copias de las bases. |

## Escala

- **Probabilidad:** Baja (poco probable en el plazo de 4 semanas), Media (puede ocurrir), Alta (es probable que ocurra).
- **Impacto:** Medio (retrasa una entrega parcial), Alto (compromete la entrega final o un requisito obligatorio).
