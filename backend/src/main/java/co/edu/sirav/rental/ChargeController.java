package co.edu.sirav.rental;

import co.edu.sirav.security.Access;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/charges")
public class ChargeController {
  private final JdbcTemplate db;
  private final Access access;

  public ChargeController(JdbcTemplate db, Access access) {
    this.db = db;
    this.access = access;
  }

  @GetMapping
  public List<Map<String, Object>> charges(JwtAuthenticationToken auth) {
    return db.queryForList(
        "SELECT id_alquiler,id_reserva,cliente,placa,costo_base,cargos,round(costo_base+cargos,2)"
            + " total_simulado,pagado,estado_alquiler FROM v_reservas WHERE id_alquiler IS NOT NULL"
            + " AND (? OR id_usuario=?) ORDER BY id_alquiler DESC",
        access.staff(auth),
        access.actor(auth));
  }
}
