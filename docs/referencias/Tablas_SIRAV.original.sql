

CREATE TABLE USUARIO (
  id_usuario BIGINT NOT NULL,
  nombre VARCHAR(100) NOT NULL,
  apellido VARCHAR(100) NOT NULL,
  email VARCHAR(150) NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  activo BOOLEAN NOT NULL,
  creado_en TIMESTAMP NOT NULL,
  CONSTRAINT pk_USUARIO PRIMARY KEY (id_usuario),
  CONSTRAINT uq_USUARIO_email UNIQUE (email)
);

CREATE TABLE ROL (
  id_rol BIGINT NOT NULL,
  nombre VARCHAR(30) NOT NULL,
  CONSTRAINT pk_ROL PRIMARY KEY (id_rol),
  CONSTRAINT uq_ROL_nombre UNIQUE (nombre)
);

CREATE TABLE USUARIO_ROL (
  id_usuario BIGINT NOT NULL,
  id_rol BIGINT NOT NULL,
  asignado_en TIMESTAMP NOT NULL,
  CONSTRAINT pk_USUARIO_ROL PRIMARY KEY (id_usuario, id_rol),
  CONSTRAINT fk_USUARIO_ROL_id_usuario FOREIGN KEY (id_usuario) REFERENCES USUARIO (id_usuario),
  CONSTRAINT fk_USUARIO_ROL_id_rol FOREIGN KEY (id_rol) REFERENCES ROL (id_rol)
);

CREATE TABLE CLIENTE (
  id_cliente BIGINT NOT NULL,
  id_usuario BIGINT,
  nombres VARCHAR(100) NOT NULL,
  apellidos VARCHAR(100) NOT NULL,
  documento VARCHAR(30) NOT NULL,
  telefono VARCHAR(25),
  email VARCHAR(150),
  licencia_conduccion VARCHAR(40),
  CONSTRAINT pk_CLIENTE PRIMARY KEY (id_cliente),
  CONSTRAINT uq_CLIENTE_id_usuario UNIQUE (id_usuario),
  CONSTRAINT uq_CLIENTE_documento UNIQUE (documento),
  CONSTRAINT fk_CLIENTE_id_usuario FOREIGN KEY (id_usuario) REFERENCES USUARIO (id_usuario)
);

CREATE TABLE CATEGORIA_VEHICULO (
  id_categoria BIGINT NOT NULL,
  nombre VARCHAR(70) NOT NULL,
  descripcion VARCHAR(4000),
  CONSTRAINT pk_CATEGORIA_VEHICULO PRIMARY KEY (id_categoria),
  CONSTRAINT uq_CATEGORIA_VEHICULO_nombre UNIQUE (nombre)
);

CREATE TABLE VEHICULO (
  id_vehiculo BIGINT NOT NULL,
  id_categoria BIGINT NOT NULL,
  placa VARCHAR(12) NOT NULL,
  marca VARCHAR(70) NOT NULL,
  modelo VARCHAR(70) NOT NULL,
  anio SMALLINT NOT NULL,
  color VARCHAR(40),
  kilometraje_actual INTEGER NOT NULL,
  estado_operativo VARCHAR(20) NOT NULL,
  CONSTRAINT pk_VEHICULO PRIMARY KEY (id_vehiculo),
  CONSTRAINT uq_VEHICULO_placa UNIQUE (placa),
  CONSTRAINT fk_VEHICULO_id_categoria FOREIGN KEY (id_categoria) REFERENCES CATEGORIA_VEHICULO (id_categoria)
);

CREATE TABLE TARIFA (
  id_tarifa BIGINT NOT NULL,
  id_categoria BIGINT NOT NULL,
  valor_diario NUMERIC(12,2) NOT NULL,
  vigente_desde DATE NOT NULL,
  vigente_hasta DATE,
  CONSTRAINT pk_TARIFA PRIMARY KEY (id_tarifa),
  CONSTRAINT fk_TARIFA_id_categoria FOREIGN KEY (id_categoria) REFERENCES CATEGORIA_VEHICULO (id_categoria)
);

CREATE TABLE RESERVA (
  id_reserva BIGINT NOT NULL,
  id_cliente BIGINT NOT NULL,
  id_vehiculo BIGINT NOT NULL,
  id_tarifa BIGINT NOT NULL,
  fecha_inicio DATE NOT NULL,
  fecha_fin DATE NOT NULL,
  fecha_solicitud TIMESTAMP NOT NULL,
  estado VARCHAR(15) NOT NULL,
  CONSTRAINT pk_RESERVA PRIMARY KEY (id_reserva),
  CONSTRAINT fk_RESERVA_id_cliente FOREIGN KEY (id_cliente) REFERENCES CLIENTE (id_cliente),
  CONSTRAINT fk_RESERVA_id_vehiculo FOREIGN KEY (id_vehiculo) REFERENCES VEHICULO (id_vehiculo),
  CONSTRAINT fk_RESERVA_id_tarifa FOREIGN KEY (id_tarifa) REFERENCES TARIFA (id_tarifa)
);

CREATE TABLE ALQUILER (
  id_alquiler BIGINT NOT NULL,
  id_reserva BIGINT NOT NULL,
  fecha_entrega TIMESTAMP NOT NULL,
  fecha_devolucion TIMESTAMP,
  km_salida INTEGER NOT NULL,
  km_entrada INTEGER,
  combustible_salida NUMERIC(5,2) NOT NULL,
  combustible_entrada NUMERIC(5,2),
  estado VARCHAR(15) NOT NULL,
  CONSTRAINT pk_ALQUILER PRIMARY KEY (id_alquiler),
  CONSTRAINT uq_ALQUILER_id_reserva UNIQUE (id_reserva),
  CONSTRAINT fk_ALQUILER_id_reserva FOREIGN KEY (id_reserva) REFERENCES RESERVA (id_reserva)
);

CREATE TABLE PAGO (
  id_pago BIGINT NOT NULL,
  id_alquiler BIGINT NOT NULL,
  fecha_pago TIMESTAMP NOT NULL,
  monto NUMERIC(12,2) NOT NULL,
  tipo VARCHAR(30) NOT NULL,
  estado VARCHAR(15) NOT NULL,
  CONSTRAINT pk_PAGO PRIMARY KEY (id_pago),
  CONSTRAINT fk_PAGO_id_alquiler FOREIGN KEY (id_alquiler) REFERENCES ALQUILER (id_alquiler)
);

CREATE TABLE CARGO_ADICIONAL (
  id_cargo BIGINT NOT NULL,
  id_alquiler BIGINT NOT NULL,
  concepto VARCHAR(60) NOT NULL,
  descripcion VARCHAR(4000),
  monto NUMERIC(12,2) NOT NULL,
  fecha_registro TIMESTAMP NOT NULL,
  CONSTRAINT pk_CARGO_ADICIONAL PRIMARY KEY (id_cargo),
  CONSTRAINT fk_CARGO_ADICIONAL_id_alquiler FOREIGN KEY (id_alquiler) REFERENCES ALQUILER (id_alquiler)
);

CREATE TABLE MANTENIMIENTO (
  id_mantenimiento BIGINT NOT NULL,
  id_vehiculo BIGINT NOT NULL,
  fecha_inicio DATE NOT NULL,
  fecha_fin DATE NOT NULL,
  descripcion VARCHAR(4000) NOT NULL,
  estado VARCHAR(15) NOT NULL,
  CONSTRAINT pk_MANTENIMIENTO PRIMARY KEY (id_mantenimiento),
  CONSTRAINT fk_MANTENIMIENTO_id_vehiculo FOREIGN KEY (id_vehiculo) REFERENCES VEHICULO (id_vehiculo)
);

CREATE TABLE AUDITORIA_RESERVA (
  id_auditoria BIGINT NOT NULL,
  id_reserva BIGINT NOT NULL,
  id_usuario BIGINT,
  estado_anterior VARCHAR(15),
  estado_nuevo VARCHAR(15) NOT NULL,
  fecha_evento TIMESTAMP NOT NULL,
  observacion VARCHAR(4000),
  CONSTRAINT pk_AUDITORIA_RESERVA PRIMARY KEY (id_auditoria),
  CONSTRAINT fk_AUDITORIA_RESERVA_id_reserva FOREIGN KEY (id_reserva) REFERENCES RESERVA (id_reserva),
  CONSTRAINT fk_AUDITORIA_RESERVA_id_usuario FOREIGN KEY (id_usuario) REFERENCES USUARIO (id_usuario)
);

