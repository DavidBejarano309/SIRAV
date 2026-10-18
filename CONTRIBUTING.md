# Guía de trabajo

## Ramas
- `main`: versión estable y entregable. Solo recibe merges desde `develop` al cerrar un sprint.
- `develop`: integración.
- `feature/SIRAV-<n>-descripcion-corta`: una rama por historia de Jira (por ejemplo `feature/SIRAV-18-exclusion-rn01`).

## Pull requests
- Todo cambio entra a `develop` por pull request.
- Lo revisa el otro integrante antes de hacer merge (Definición de terminado).

## Commits
Mensajes descriptivos con prefijo y la clave de Jira:

```
<tipo>(<ámbito>): <resumen> [SIRAV-<n>]
```

Tipos: `feat`, `fix`, `docs`, `db`, `infra`, `test`, `chore`.
Ejemplo: `db(postgres): agrega restricción de exclusión para reservas [SIRAV-18]`

## Convenciones de base de datos
Prefijos: `sp_` procedimientos, `fn_` funciones, `trg_` triggers, `e_` excepciones, `ix_` índices, `cur_` cursores, `pck_` paquetes, `r_` registros, `param_` parámetros.
Variables: `vv_` (varchar), `vd_` (date), `vn_` (number), `vb_` (boolean), `vc_` (char).
Nombres de tablas y columnas en minúscula, sin tildes.

## Definición de terminado
Código o script en `develop`, probado en la VM, revisado por el otro integrante y con evidencia guardada en `docs/`.
