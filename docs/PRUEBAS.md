# Pruebas de la versión 3FN

Las pruebas integrales usan PostgreSQL y MongoDB reales en la base aislada sirav_3fn_test. La aplicación normal utiliza sirav_3fn; la versión anterior utilizaba sirav y no se modifica.

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

Los resultados de la ejecución actual se guardan en docs/evidencias/3fn-resultados.txt. Los resúmenes Surefire son regenerables desde backend/target/surefire-reports. Las capturas 3fn-*.png proceden de la versión simplificada; las anteriores no se incluyen en el ZIP nuevo.

Docker Compose y la VM Linux necesitan verificarse en un entorno con Docker. Esta entrega no afirma haber creado una VM ni grabado el video.
