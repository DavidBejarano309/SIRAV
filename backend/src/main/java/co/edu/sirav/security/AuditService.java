package co.edu.sirav.security;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

/** Guarda metadatos de seguridad; nunca contraseñas ni tokens. */
@Service
public class AuditService {
  private final JdbcTemplate db;

  public AuditService(JdbcTemplate db) {
    this.db = db;
  }

  public void record(String action, Long actor, Long target, String result) {
    db.update(
        "INSERT INTO evento_outbox(coleccion,documento)"
            + " VALUES('bitacora_operaciones',jsonb_build_object('accion',?::text,'actor',?::bigint,'usuarioId',?::bigint,'resultado',?::text,'fecha',now()))",
        action,
        actor,
        target,
        result);
  }
}
