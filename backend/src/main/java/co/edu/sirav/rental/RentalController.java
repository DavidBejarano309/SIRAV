package co.edu.sirav.rental;

import co.edu.sirav.security.Access;
import jakarta.validation.Valid;
import java.util.*;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api")
public class RentalController {
  private final RentalService rentals;
  private final Access access;
  private final JdbcTemplate db;

  public RentalController(RentalService rentals, Access access, JdbcTemplate db) {
    this.rentals = rentals;
    this.access = access;
    this.db = db;
  }

  @GetMapping("/reservations")
  public List<Map<String, Object>> list(JwtAuthenticationToken auth) {
    return db.queryForList(
        "SELECT * FROM v_reservas WHERE (? OR id_usuario=?) ORDER BY fecha_solicitud DESC",
        access.staff(auth),
        access.actor(auth));
  }

  @PostMapping("/reservations")
  @ResponseStatus(HttpStatus.CREATED)
  public Map<String, Object> create(
      JwtAuthenticationToken auth,
      @Valid @RequestBody RentalService.Reservation input,
      @RequestHeader("Idempotency-Key") UUID key) {
    return rentals.create(auth, input, key);
  }

  @GetMapping("/reservations/{id}")
  public Map<String, Object> detail(JwtAuthenticationToken auth, @PathVariable long id) {
    access.reservation(auth, id);
    return db.queryForMap("SELECT * FROM v_reservas WHERE id_reserva=?", id);
  }

  @PostMapping("/reservations/{id}/confirm")
  @PreAuthorize("hasAnyRole('ADMIN','OPERADOR')")
  @ResponseStatus(HttpStatus.NO_CONTENT)
  public void confirm(JwtAuthenticationToken auth, @PathVariable long id) {
    rentals.confirm(auth, id);
  }

  @PostMapping("/reservations/{id}/cancel")
  @ResponseStatus(HttpStatus.NO_CONTENT)
  public void cancel(
      JwtAuthenticationToken auth,
      @PathVariable long id,
      @Valid @RequestBody RentalService.Cancellation input) {
    rentals.cancel(auth, id, input.motivo());
  }

  @PostMapping("/reservations/{id}/start")
  @PreAuthorize("hasAnyRole('ADMIN','OPERADOR')")
  public Map<String, Object> start(
      JwtAuthenticationToken auth,
      @PathVariable long id,
      @Valid @RequestBody RentalService.Handover input) {
    return rentals.start(auth, id, input);
  }

  @PostMapping("/rentals/{id}/close")
  @PreAuthorize("hasAnyRole('ADMIN','OPERADOR')")
  public Map<String, Object> close(
      JwtAuthenticationToken auth,
      @PathVariable long id,
      @Valid @RequestBody RentalService.Handover input) {
    return rentals.close(auth, id, input);
  }

  @GetMapping("/reservations/{id}/history")
  public List<Map<String, Object>> history(JwtAuthenticationToken auth, @PathVariable long id) {
    access.reservation(auth, id);
    return db.queryForList(
        "SELECT a.*,u.nombre actor FROM auditoria_reserva a LEFT JOIN usuario u USING(id_usuario)"
            + " WHERE id_reserva=? ORDER BY fecha_evento,id_auditoria",
        id);
  }

  @GetMapping("/rentals/{id}/payments")
  public Map<String, Object> payments(JwtAuthenticationToken auth, @PathVariable long id) {
    access.rental(auth, id);
    return Map.of(
        "pagos",
        db.queryForList("SELECT * FROM pago WHERE id_alquiler=? ORDER BY fecha_pago", id),
        "cargos",
        db.queryForList(
            "SELECT * FROM cargo_adicional WHERE id_alquiler=? ORDER BY fecha_registro", id));
  }
}
