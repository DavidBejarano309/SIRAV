package co.edu.sirav.inspection;

import co.edu.sirav.common.ApiException;
import co.edu.sirav.rental.RentalService;
import co.edu.sirav.security.Access;
import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import java.time.*;
import java.util.*;
import org.bson.Document;
import org.springframework.data.domain.Sort;
import org.springframework.data.mongodb.core.MongoTemplate;
import org.springframework.data.mongodb.core.query.*;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api")
public class InspectionController {
  private static final String COLLECTION = "inspecciones_vehiculo";

  public record Correction(
      @Min(0) long version, @Valid @NotNull RentalService.Inspection inspeccion) {}

  private final MongoTemplate mongo;
  private final Access access;
  private final JdbcTemplate db;

  public InspectionController(MongoTemplate mongo, Access access, JdbcTemplate db) {
    this.mongo = mongo;
    this.access = access;
    this.db = db;
  }

  @GetMapping("/rentals/{id}/inspections")
  public List<Document> forRental(JwtAuthenticationToken auth, @PathVariable long id) {
    access.rental(auth, id);
    return mongo.find(
        Query.query(Criteria.where("alquilerId").is(id)).with(Sort.by("fecha")),
        Document.class,
        COLLECTION);
  }

  @GetMapping("/inspections")
  @PreAuthorize("hasAnyRole('ADMIN','OPERADOR')")
  public List<Document> search(
      @RequestParam(required = false) Long vehicle,
      @RequestParam(required = false) LocalDate from,
      @RequestParam(required = false) LocalDate to,
      @RequestParam(defaultValue = "false") boolean severe) {
    var criteria = new Criteria();
    var filters = new ArrayList<Criteria>();
    filters.add(Criteria.where("anulada").is(false));
    if (vehicle != null) filters.add(Criteria.where("vehiculoId").is(vehicle));
    if (from != null)
      filters.add(
          Criteria.where("fecha")
              .gte(Date.from(from.atStartOfDay(ZoneId.of("America/Bogota")).toInstant())));
    if (to != null)
      filters.add(
          Criteria.where("fecha")
              .lt(Date.from(to.plusDays(1).atStartOfDay(ZoneId.of("America/Bogota")).toInstant())));
    if (severe)
      filters.add(Criteria.where("danos").elemMatch(Criteria.where("severidad").is("ALTA")));
    criteria.andOperator(filters);
    return mongo.find(
        Query.query(criteria).with(Sort.by(Sort.Direction.DESC, "fecha")).limit(100),
        Document.class,
        COLLECTION);
  }

  @PutMapping("/inspections/{id}")
  @PreAuthorize("hasAnyRole('ADMIN','OPERADOR')")
  public Document correct(
      JwtAuthenticationToken auth, @PathVariable String id, @Valid @RequestBody Correction input) {
    var original = mongo.findById(id, Document.class, COLLECTION);
    if (original == null) throw ApiException.missing();
    access.rental(auth, ((Number) original.get("alquilerId")).longValue());
    var data = input.inspeccion();
    var update =
        new Update()
            .set(
                "danos",
                data.danos().stream()
                    .map(
                        d ->
                            new Document("zona", d.zona())
                                .append("severidad", d.severidad())
                                .append("descripcion", d.descripcion()))
                    .toList())
            .set("evidencias", data.evidencias())
            .set("observaciones", data.observaciones())
            .set("corregidaPor", access.actor(auth))
            .set("corregidaEn", new Date())
            .inc("version", 1)
            .push(
                "historial",
                new Document("danos", original.get("danos"))
                    .append("evidencias", original.get("evidencias"))
                    .append("observaciones", original.get("observaciones"))
                    .append("actor", access.actor(auth))
                    .append("fecha", new Date()));
    var result =
        mongo.updateFirst(
            Query.query(
                Criteria.where("_id")
                    .is(id)
                    .and("version")
                    .is(input.version())
                    .and("anulada")
                    .is(false)),
            update,
            COLLECTION);
    if (result.getModifiedCount() == 0)
      throw new ApiException(
          HttpStatus.CONFLICT, "La inspección cambió o fue anulada; recargue antes de corregir");
    return mongo.findById(id, Document.class, COLLECTION);
  }

  @DeleteMapping("/inspections/{id}")
  @PreAuthorize("hasRole('ADMIN')")
  @ResponseStatus(HttpStatus.NO_CONTENT)
  public void annul(
      JwtAuthenticationToken auth,
      @PathVariable String id,
      @Valid @RequestBody RentalService.Cancellation input) {
    var result =
        mongo.updateFirst(
            Query.query(Criteria.where("_id").is(id).and("anulada").is(false)),
            new Update()
                .set("anulada", true)
                .set("motivoAnulacion", input.motivo())
                .set("anuladaPor", access.actor(auth))
                .set("anuladaEn", new Date())
                .inc("version", 1),
            COLLECTION);
    if (result.getModifiedCount() == 0) throw ApiException.missing();
  }

  @GetMapping("/inspections/analytics")
  @PreAuthorize("hasAnyRole('ADMIN','OPERADOR')")
  public Map<String, Object> analytics() {
    var collection = mongo.getCollection(COLLECTION);
    var valid = new Document("$match", new Document("anulada", false));
    var category =
        collection
            .aggregate(
                List.of(
                    valid,
                    new Document(
                        "$group",
                        new Document("_id", "$categoriaId")
                            .append("inspecciones", new Document("$sum", 1))
                            .append("kilometrajePromedio", new Document("$avg", "$kilometraje"))
                            .append("combustiblePromedio", new Document("$avg", "$combustible"))),
                    new Document("$sort", new Document("_id", 1))))
            .into(new ArrayList<>());
    var zones =
        collection
            .aggregate(
                List.of(
                    valid,
                    new Document("$unwind", "$danos"),
                    new Document(
                        "$group",
                        new Document(
                                "_id",
                                new Document(
                                        "mes",
                                        new Document(
                                            "$dateToString",
                                            new Document("format", "%Y-%m")
                                                .append("date", "$fecha")
                                                .append("timezone", "America/Bogota")))
                                    .append("zona", "$danos.zona"))
                            .append("incidencias", new Document("$sum", 1))),
                    new Document("$sort", new Document("incidencias", -1))))
            .into(new ArrayList<>());
    var vehicles =
        collection
            .aggregate(
                List.of(
                    valid,
                    new Document("$unwind", "$danos"),
                    new Document(
                        "$group",
                        new Document("_id", "$vehiculoId")
                            .append("incidencias", new Document("$sum", 1))),
                    new Document("$sort", new Document("incidencias", -1))))
            .into(new ArrayList<>());
    return Map.of(
        "porCategoria",
        category,
        "zonasPorMes",
        zones,
        "incidenciasPorVehiculo",
        vehicles,
        "pendientesSincronizacion",
        db.queryForObject(
            "SELECT count(*) FROM evento_outbox WHERE publicado_en IS NULL", Long.class));
  }
}
