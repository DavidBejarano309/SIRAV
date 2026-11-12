package co.edu.sirav.rental;

import co.edu.sirav.inspection.EvidenceService;
import co.edu.sirav.security.Access;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class RentalService {
  public record Reservation(
      Long idCliente,
      @Positive long idVehiculo,
      @NotNull LocalDate fechaInicio,
      @NotNull LocalDate fechaFin) {}

  public record Damage(
      @NotBlank @Size(max = 60) String zona,
      @Pattern(regexp = "BAJA|MEDIA|ALTA") @NotNull String severidad,
      @NotBlank @Size(max = 500) String descripcion) {}

  public record Inspection(
      @NotNull @Size(max = 50) List<@NotNull @Valid Damage> danos,
      @NotNull @Size(max = 10) List<@NotBlank @Size(max = 500) String> evidencias,
      @Size(max = 2000) String observaciones) {}

  public record Handover(
      @Min(0) int kilometraje,
      @NotNull @DecimalMin("0") @DecimalMax("100") BigDecimal combustible,
      @Valid @NotNull Inspection inspeccion) {}

  public record Cancellation(@NotBlank @Size(min = 5, max = 1000) String motivo) {}

  private final JdbcTemplate db;
  private final Access access;
  private final ObjectMapper json;
  private final EvidenceService evidence;

  public RentalService(
      JdbcTemplate db, Access access, ObjectMapper json, EvidenceService evidence) {
    this.db = db;
    this.access = access;
    this.json = json;
    this.evidence = evidence;
  }

  @Transactional
  public Map<String, Object> create(JwtAuthenticationToken auth, Reservation r, UUID key) {
    long client = access.staff(auth) && r.idCliente() != null ? r.idCliente() : access.client(auth);
    if (!Boolean.TRUE.equals(
        db.queryForObject(
            "SELECT EXISTS(SELECT 1 FROM cliente WHERE id_cliente=? AND licencia_conduccion IS NOT"
                + " NULL AND trim(licencia_conduccion)<>'')",
            Boolean.class,
            client))) throw new IllegalArgumentException("El cliente requiere licencia");
    db.update(
        "CALL sp_crear_reserva(?,?,?,?,?,?)",
        access.actor(auth),
        client,
        r.idVehiculo(),
        r.fechaInicio(),
        r.fechaFin(),
        key);
    return db.queryForMap("SELECT * FROM v_reservas WHERE idempotencia=?", key);
  }

  @Transactional
  public void confirm(JwtAuthenticationToken auth, long id) {
    access.reservation(auth, id);
    db.update("CALL sp_confirmar_reserva(?,?)", access.actor(auth), id);
  }

  @Transactional
  public void cancel(JwtAuthenticationToken auth, long id, String reason) {
    access.reservation(auth, id);
    db.update("CALL sp_cancelar_reserva(?,?,?)", access.actor(auth), id, reason);
  }

  @Transactional
  public Map<String, Object> start(JwtAuthenticationToken auth, long id, Handover h) {
    access.reservation(auth, id);
    evidence.validate(id, h.inspeccion().evidencias());
    db.update(
        "CALL sp_iniciar_alquiler(?,?,?,?,?::jsonb)",
        access.actor(auth),
        id,
        h.kilometraje(),
        h.combustible(),
        encode(h.inspeccion()));
    return db.queryForMap("SELECT * FROM v_reservas WHERE id_reserva=?", id);
  }

  @Transactional
  public Map<String, Object> close(JwtAuthenticationToken auth, long id, Handover h) {
    access.rental(auth, id);
    long reservation =
        Objects.requireNonNull(
            db.queryForObject(
                "SELECT id_reserva FROM alquiler WHERE id_alquiler=?", Long.class, id));
    evidence.validate(reservation, h.inspeccion().evidencias());
    db.update(
        "CALL sp_cerrar_alquiler(?,?,?,?,?::jsonb)",
        access.actor(auth),
        id,
        h.kilometraje(),
        h.combustible(),
        encode(h.inspeccion()));
    return db.queryForMap("SELECT * FROM v_reservas WHERE id_alquiler=?", id);
  }

  private String encode(Object value) {
    try {
      return json.writeValueAsString(value);
    } catch (JsonProcessingException e) {
      throw new IllegalArgumentException("Inspección inválida", e);
    }
  }
}
