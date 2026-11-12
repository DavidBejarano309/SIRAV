package co.edu.sirav.report;

import co.edu.sirav.catalog.CatalogController;
import java.time.*;
import java.util.*;
import org.bson.Document;
import org.springframework.data.domain.Sort;
import org.springframework.data.mongodb.core.MongoTemplate;
import org.springframework.data.mongodb.core.query.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/audit")
public class HistoryController {
  private final JdbcTemplate db;
  private final MongoTemplate mongo;

  public HistoryController(JdbcTemplate db, MongoTemplate mongo) {
    this.db = db;
    this.mongo = mongo;
  }

  @GetMapping("/reservations")
  @PreAuthorize("hasAnyRole('ADMIN','OPERADOR')")
  public List<Map<String, Object>> reservations(
      @RequestParam LocalDate from, @RequestParam LocalDate to) {
    CatalogController.dates(from, to);
    return db.queryForList(
        "SELECT a.*,u.email actor FROM auditoria_reserva a LEFT JOIN usuario u USING(id_usuario)"
            + " WHERE a.fecha_evento>=?::date::timestamp AT TIME ZONE 'America/Bogota' AND"
            + " a.fecha_evento<?::date::timestamp AT TIME ZONE 'America/Bogota' ORDER BY"
            + " a.fecha_evento DESC LIMIT 200",
        from,
        to);
  }

  @GetMapping("/events")
  @PreAuthorize("hasRole('ADMIN')")
  public List<Document> events(
      @RequestParam LocalDate from,
      @RequestParam LocalDate to,
      @RequestParam(defaultValue = "") String action) {
    CatalogController.dates(from, to);
    var criteria =
        Criteria.where("fecha")
            .gte(Date.from(from.atStartOfDay(ZoneId.of("America/Bogota")).toInstant()))
            .lt(Date.from(to.atStartOfDay(ZoneId.of("America/Bogota")).toInstant()));
    if (!action.isBlank()) criteria.and("accion").is(action);
    return mongo.find(
        Query.query(criteria).with(Sort.by(Sort.Direction.DESC, "fecha")).limit(200),
        Document.class,
        "bitacora_operaciones");
  }
}
