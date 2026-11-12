# Modelo de datos revisado

La definición ejecutable es database/postgres/01-schema.sql, copia del archivo revisado aportado por el usuario. El diccionario se genera desde ese esquema. Los diagramas PNG y el informe de octubre representan la versión anterior y no se incluyen en el ZIP simplificado.

```mermaid
erDiagram
 USUARIO o|--o| CLIENTE : identifica
 USUARIO ||--o{ USUARIO_ROL : recibe
 ROL ||--o{ USUARIO_ROL : asigna
 CLIENTE ||--o{ RESERVA : solicita
 CATEGORIA_VEHICULO ||--o{ VEHICULO : clasifica
 CATEGORIA_VEHICULO ||--o{ TARIFA : define
 VEHICULO ||--o{ RESERVA : recibe
 TARIFA ||--o{ RESERVA : aplica
 RESERVA ||--o| ALQUILER : origina
 ALQUILER ||--o{ PAGO : recibe
 ALQUILER ||--o{ CARGO_ADICIONAL : genera
 VEHICULO ||--o{ MANTENIMIENTO : requiere
 RESERVA ||--|{ AUDITORIA_RESERVA : registra
 USUARIO o|--o{ AUDITORIA_RESERVA : ejecuta
```

Si CLIENTE.id_usuario no es NULL, CLIENTE.nombres/apellidos/email deben ser NULL. Si id_usuario es NULL, se requieren nombres y apellidos en CLIENTE. v_cliente_contacto no es una entidad adicional: es una vista que reúne la identidad desde la fuente correspondiente.

```mermaid
stateDiagram-v2
 [*] --> SOLICITADA
 SOLICITADA --> CONFIRMADA
 SOLICITADA --> CANCELADA
 CONFIRMADA --> ACTIVA
 CONFIRMADA --> CANCELADA
 ACTIVA --> CERRADA
```

La tabla técnica evento_outbox coordina la publicación de documentos en MongoDB; no se cuenta como entidad del dominio de alquiler.
