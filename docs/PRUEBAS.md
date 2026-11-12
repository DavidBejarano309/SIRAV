# Pruebas de la versión 3FN con supuestos

La auditoría actual en VirtualBox aprobó **72 pruebas Java, 5 frontend y 4 flujos de navegador**, además de **64 solicitudes HTTP en grupos de ocho**. Se corrigieron siete casos defectuosos de SQL y validación de entradas. Consulta el [informe funcional y de concurrencia](AUDITORIA-FUNCIONAL-VM.md) para ver escenarios, evidencias y límites de carga.

La auditoría usa PostgreSQL y MongoDB reales en bases nuevas `sirav_audit_FECHA`. La ejecución local anterior utiliza `sirav_3fn_test`. La aplicación normal utiliza `sirav_3fn`.

## Ejecución local

```powershell
./scripts/start-local.ps1 -DatabasesOnly
./scripts/test-local.ps1 -Maven RUTA-A-MVN
./scripts/start-local.ps1
cd frontend
npm run test:e2e
```

El script de pruebas configura credenciales locales de demostración, inicializa la base de test si está vacía y ejecuta Maven, Vitest y el build React. Nunca se sustituyen las restricciones PostgreSQL por H2.

## Casos

- Roles y revocación JWT.
- Clientes registrados sin nombre/correo duplicados en CLIENTE.
- Actualización de identidad en USUARIO reflejada en v_cliente_contacto.
- Rechazo por la restricción de identidad al intentar copiar un nombre al perfil enlazado.
- Clientes de mostrador con identidad propia y lectura correcta por la API.
- Reserva idempotente y competencia concurrente por vehículo.
- Entrega, cierre, pago simulado e inspecciones MongoDB.
- Rechazo de devolución inválida sin generar pago parcial.
- CRUD documental, control de versión, daños altos y agregaciones.
- Ejecución de los seis reportes SQL.
- Navegación de administrador, permisos visibles del cliente y ciclo completo en React.

La ejecución anterior aprobó 18 pruebas Java (15 integrales y 3 unitarias), 3 pruebas Vitest y 4 escenarios Playwright. La auditoría nueva amplía esa batería con contratos SQL, validaciones, concurrencia y una conexión fallida real a un destino de prueba MongoDB. Se conservan los datos de auditoría para comprobar los resultados.

Se agregan casos de roles múltiples, perfil 3FN, cambio de contraseña, desactivación sin borrar reservas, último administrador, registro duplicado, aislamiento de clientes, imágenes reales y rechazo de archivos inválidos, edición/solapamiento de mantenimiento, intervalos adyacentes, tarifas históricas, redondeo de medio centavo y cambio de día en Bogotá, ausencia documental y recuperación del outbox tras un fallo al registrar una inspección.

Los resultados están en docs/evidencias/supuestos-resultados.txt y supuestos-medicion.txt. Surefire y JaCoCo se regeneran en backend/target. Las capturas supuestos-*.png pertenecen a esta versión y ocultan filas con correos ajenos a los dominios de demostración. La medición de siete endpoints HTTP (seis reportes y las agregaciones) dio 9–17 ms en el entorno local tras una petición de calentamiento. No representa una prueba de carga ni una medición en VM.

Para repetir los tiempos en Windows: configura DEMO_PASSWORD y ejecuta scripts/measure-local.ps1. Las consultas se midieron con flota de 25 vehículos/5 categorías y datos ficticios de historial. Los resultados pueden variar según equipo, volumen y red.

La aplicación y las dos bases ya se verificaron en las tres VM de VirtualBox. La evidencia de video y de participación del equipo corresponde a su entrega académica.
