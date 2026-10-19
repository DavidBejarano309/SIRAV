\# Requerimientos priorizados — SIRAV



Prioridad según MoSCoW: Must (indispensable), Should (importante), Could (si hay tiempo).



\## Requerimientos funcionales

| ID | Requerimiento | Prioridad |

|---|---|---|

| RF-01 | Autenticar usuarios y controlar el acceso por rol (administrador, operador, cliente) | Must |

| RF-02 | Gestionar clientes (crear, consultar, actualizar) | Must |

| RF-03 | Gestionar vehículos, categorías y tarifas | Must |

| RF-04 | Consultar disponibilidad de vehículos por rango de fechas | Must |

| RF-05 | Crear, confirmar y cancelar reservas, impidiendo cruces de fechas (RN-01) | Must |

| RF-06 | Iniciar un alquiler desde una reserva confirmada y registrar la entrega | Must |

| RF-07 | Cerrar un alquiler: devolución, cálculo de costo final y cargos por retraso | Must |

| RF-08 | Registrar pagos y cargos adicionales de un alquiler | Must |

| RF-09 | Registrar mantenimientos y bloquear el vehículo mientras dure | Should |

| RF-10 | Auditar automáticamente los cambios de estado de una reserva | Should |

| RF-11 | Registrar inspecciones del vehículo (entrega y devolución) en MongoDB | Must |

| RF-12 | Registrar la bitácora de operaciones en MongoDB | Should |

| RF-13 | Generar los reportes R1 a R6 desde PostgreSQL | Must |

| RF-14 | Mostrar un tablero con indicadores básicos | Could |



\## Requerimientos no funcionales

| ID | Requerimiento | Prioridad |

|---|---|---|

| RNF-01 | Integridad de datos con PK, FK, CHECK y UNIQUE | Must |

| RNF-02 | Consistencia ante concurrencia: dos usuarios no pueden reservar el mismo vehículo a la vez | Must |

| RNF-03 | Contraseñas almacenadas con hash, nunca en texto plano | Must |

| RNF-04 | Privilegios mínimos por rol en la base de datos | Should |

| RNF-05 | Despliegue completo en una VM Ubuntu Server | Must |

| RNF-06 | Interfaz usable en navegador de escritorio (Thymeleaf y Bootstrap) | Should |

| RNF-07 | Scripts SQL reproducibles y numerados en el repositorio | Must |

