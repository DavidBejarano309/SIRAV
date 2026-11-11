package co.edu.sirav.catalog;

import co.edu.sirav.common.ApiException;
import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.*;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api")
public class CatalogController {
  public record Vehicle(
      @Positive long idCategoria,
      @NotBlank @Size(max = 12) String placa,
      @NotBlank @Size(max = 70) String marca,
      @NotBlank @Size(max = 70) String modelo,
      @Min(1950) @Max(2100) int anio,
      @Size(max = 40) String color,
      @Min(0) int kilometrajeActual,
      @Pattern(regexp = "DISPONIBLE|INACTIVO") String estadoOperativo) {}

  public record Category(
      @NotBlank @Size(max = 70) String nombre, @Size(max = 4000) String descripcion) {}

  public record Rate(
      @Positive long idCategoria,
      @NotNull @DecimalMin("0.01") BigDecimal valorDiario,
      @NotNull LocalDate vigenteDesde,
      LocalDate vigenteHasta) {}

  public record Client(
      @NotBlank @Size(max = 100) String nombres,
      @NotBlank @Size(max = 100) String apellidos,
      @NotBlank @Size(max = 30) String documento,
      @Size(max = 25) String telefono,
      @Email @Size(max = 150) String email,
      @NotBlank @Size(max = 40) String licenciaConduccion) {}

  public record Maintenance(
      @Positive long idVehiculo,
      @NotNull LocalDate fechaInicio,
      @NotNull LocalDate fechaFin,
      @NotBlank @Size(max = 4000) String descripcion) {}

  private final JdbcTemplate db;
  private final NamedParameterJdbcTemplate named;

  public CatalogController(JdbcTemplate db, NamedParameterJdbcTemplate named) {
    this.db = db;
    this.named = named;
  }

  @GetMapping("/categories")
  public List<Map<String, Object>> categories() {
    return db.queryForList("SELECT * FROM categoria_vehiculo ORDER BY nombre");
  }

  @GetMapping("/vehicles")
  public List<Map<String, Object>> vehicles(
      @RequestParam(required = false) Long category,
      @RequestParam(required = false) LocalDate from,
      @RequestParam(required = false) LocalDate to,
      @RequestParam(defaultValue = "") String search,
      @RequestParam(defaultValue = "false") boolean available) {
    dates(from, to);
    var params = new HashMap<String, Object>();
    params.put("category", category);
    params.put("from", from);
    params.put("to", to);
    params.put("available", available);
    params.put("search", "%" + search + "%");
    return named.queryForList(
        """
SELECT v.*,c.nombre categoria,t.valor_diario,
  fn_vehiculo_disponible(v.id_vehiculo,coalesce(CAST(:from AS date),current_date),coalesce(CAST(:to AS date),current_date+1)) disponible
FROM vehiculo v JOIN categoria_vehiculo c USING(id_categoria)
LEFT JOIN LATERAL(SELECT valor_diario FROM tarifa WHERE id_categoria=v.id_categoria AND vigente_desde<=coalesce(CAST(:from AS date),current_date) AND (vigente_hasta IS NULL OR vigente_hasta>=coalesce(CAST(:to AS date),current_date+1)) ORDER BY vigente_desde DESC LIMIT 1) t ON true
WHERE (CAST(:category AS bigint) IS NULL OR v.id_categoria=:category)
  AND (v.marca||' '||v.modelo||' '||v.placa ILIKE :search)
  AND (:available=false OR (t.valor_diario IS NOT NULL AND fn_vehiculo_disponible(v.id_vehiculo,coalesce(CAST(:from AS date),current_date),coalesce(CAST(:to AS date),current_date+1))))
ORDER BY v.id_vehiculo
""",
        params);
  }

  @GetMapping("/vehicles/{id}/quote")
  public Map<String, Object> quote(
      @PathVariable long id, @RequestParam LocalDate from, @RequestParam LocalDate to) {
    dates(from, to);
    var rows =
        db.queryForList(
            "SELECT t.id_tarifa,t.valor_diario,?::date-?::date"
                + " dias,(?::date-?::date)*t.valor_diario"
                + " total,fn_vehiculo_disponible(v.id_vehiculo,?,?) disponible FROM vehiculo v JOIN"
                + " tarifa t USING(id_categoria) WHERE v.id_vehiculo=? AND t.vigente_desde<=? AND"
                + " (t.vigente_hasta IS NULL OR t.vigente_hasta>=?)",
            to,
            from,
            to,
            from,
            from,
            to,
            id,
            from,
            to);
    if (rows.isEmpty())
      throw new ApiException(HttpStatus.CONFLICT, "No hay tarifa que cubra esas fechas");
    return rows.getFirst();
  }

  public static void dates(LocalDate from, LocalDate to) {
    if ((from == null) != (to == null)
        || (from != null && (!to.isAfter(from) || to.isAfter(from.plusDays(366)))))
      throw new ApiException(
          HttpStatus.BAD_REQUEST, "Indique ambas fechas; el período debe ser de 1 a 366 días");
  }

  @PostMapping("/vehicles")
  @PreAuthorize("hasRole('ADMIN')")
  public Map<String, Object> createVehicle(@Valid @RequestBody Vehicle v) {
    return db.queryForMap(
        "INSERT INTO"
            + " vehiculo(id_categoria,placa,marca,modelo,anio,color,kilometraje_actual,estado_operativo)"
            + " VALUES(?,?,?,?,?,?,?,?) RETURNING *",
        v.idCategoria(),
        v.placa().toUpperCase(Locale.ROOT),
        v.marca(),
        v.modelo(),
        v.anio(),
        v.color(),
        v.kilometrajeActual(),
        Objects.requireNonNullElse(v.estadoOperativo(), "DISPONIBLE"));
  }

  @PutMapping("/vehicles/{id}")
  @PreAuthorize("hasRole('ADMIN')")
  @Transactional
  public Map<String, Object> updateVehicle(@PathVariable long id, @Valid @RequestBody Vehicle v) {
    var current = db.queryForList("SELECT * FROM vehiculo WHERE id_vehiculo=? FOR UPDATE", id);
    if (current.isEmpty()) throw ApiException.missing();
    if (Boolean.TRUE.equals(
        db.queryForObject(
            "SELECT EXISTS(SELECT 1 FROM reserva WHERE id_vehiculo=? AND estado IN"
                + " ('SOLICITADA','CONFIRMADA','ACTIVA'))",
            Boolean.class,
            id)))
      throw new ApiException(
          HttpStatus.CONFLICT, "No se puede editar un vehículo con reservas vigentes");
    if (v.kilometrajeActual() < ((Number) current.getFirst().get("kilometraje_actual")).intValue())
      throw new ApiException(HttpStatus.CONFLICT, "El kilometraje no puede disminuir");
    return db.queryForMap(
        "UPDATE vehiculo SET"
            + " id_categoria=?,placa=?,marca=?,modelo=?,anio=?,color=?,kilometraje_actual=?,estado_operativo=?"
            + " WHERE id_vehiculo=? RETURNING *",
        v.idCategoria(),
        v.placa().toUpperCase(Locale.ROOT),
        v.marca(),
        v.modelo(),
        v.anio(),
        v.color(),
        v.kilometrajeActual(),
        Objects.requireNonNullElse(v.estadoOperativo(), "DISPONIBLE"),
        id);
  }

  @PostMapping("/categories")
  @PreAuthorize("hasRole('ADMIN')")
  public Map<String, Object> createCategory(@Valid @RequestBody Category c) {
    return db.queryForMap(
        "INSERT INTO categoria_vehiculo(nombre,descripcion) VALUES(?,?) RETURNING *",
        c.nombre(),
        c.descripcion());
  }

  @GetMapping("/rates")
  @PreAuthorize("hasAnyRole('ADMIN','OPERADOR')")
  public List<Map<String, Object>> rates() {
    return db.queryForList(
        "SELECT t.*,c.nombre categoria FROM tarifa t JOIN categoria_vehiculo c USING(id_categoria)"
            + " ORDER BY id_tarifa DESC");
  }

  @PostMapping("/rates")
  @PreAuthorize("hasRole('ADMIN')")
  public Map<String, Object> rate(@Valid @RequestBody Rate r) {
    return db.queryForMap(
        "INSERT INTO tarifa(id_categoria,valor_diario,vigente_desde,vigente_hasta) VALUES(?,?,?,?)"
            + " RETURNING *",
        r.idCategoria(),
        r.valorDiario(),
        r.vigenteDesde(),
        r.vigenteHasta());
  }

  @PutMapping("/rates/{id}/end")
  @PreAuthorize("hasRole('ADMIN')")
  public Map<String, Object> endRate(
      @PathVariable long id, @RequestBody Map<String, String> input) {
    LocalDate date = LocalDate.parse(input.get("vigenteHasta"));
    if (Boolean.TRUE.equals(
        db.queryForObject(
            "SELECT EXISTS(SELECT 1 FROM reserva WHERE id_tarifa=? AND fecha_fin>?)",
            Boolean.class,
            id,
            date)))
      throw new ApiException(
          HttpStatus.CONFLICT, "La nueva vigencia debe cubrir las reservas existentes");
    var rows =
        db.queryForList(
            "UPDATE tarifa SET vigente_hasta=? WHERE id_tarifa=? RETURNING *", date, id);
    if (rows.isEmpty()) throw ApiException.missing();
    return rows.getFirst();
  }

  @GetMapping("/clients")
  @PreAuthorize("hasAnyRole('ADMIN','OPERADOR')")
  public List<Map<String, Object>> clients(@RequestParam(defaultValue = "") String search) {
    return db.queryForList(
        "SELECT * FROM v_cliente_contacto WHERE nombres||' '||apellidos||' '||documento ILIKE ?"
            + " ORDER BY id_cliente DESC LIMIT 100",
        "%" + search + "%");
  }

  @PostMapping("/clients")
  @PreAuthorize("hasAnyRole('ADMIN','OPERADOR')")
  public Map<String, Object> createClient(@Valid @RequestBody Client c) {
    return db.queryForMap(
        "INSERT INTO cliente(nombres,apellidos,documento,telefono,email,licencia_conduccion)"
            + " VALUES(?,?,?,?,?,?) RETURNING *",
        c.nombres(),
        c.apellidos(),
        c.documento(),
        c.telefono(),
        c.email(),
        c.licenciaConduccion());
  }

  @GetMapping("/maintenance")
  @PreAuthorize("hasAnyRole('ADMIN','OPERADOR')")
  public List<Map<String, Object>> maintenance() {
    return db.queryForList(
        "SELECT m.*,v.placa FROM mantenimiento m JOIN vehiculo v USING(id_vehiculo) ORDER BY"
            + " fecha_inicio DESC LIMIT 100");
  }

  @PostMapping("/maintenance")
  @PreAuthorize("hasAnyRole('ADMIN','OPERADOR')")
  public Map<String, Object> maintenance(@Valid @RequestBody Maintenance m) {
    return db.queryForMap(
        "INSERT INTO mantenimiento(id_vehiculo,fecha_inicio,fecha_fin,descripcion,estado)"
            + " VALUES(?,?,?,?,'PROGRAMADO') RETURNING *",
        m.idVehiculo(),
        m.fechaInicio(),
        m.fechaFin(),
        m.descripcion());
  }

  @PatchMapping("/maintenance/{id}")
  @PreAuthorize("hasAnyRole('ADMIN','OPERADOR')")
  public Map<String, Object> maintenanceState(
      @PathVariable long id, @RequestBody Map<String, String> input) {
    String state = input.get("estado");
    if (!Set.of("COMPLETADO", "CANCELADO").contains(state)) throw new IllegalArgumentException();
    var rows =
        db.queryForList(
            "UPDATE mantenimiento SET estado=? WHERE id_mantenimiento=? AND estado='PROGRAMADO'"
                + " RETURNING *",
            state,
            id);
    if (rows.isEmpty())
      throw new ApiException(HttpStatus.CONFLICT, "El mantenimiento ya fue finalizado o no existe");
    return rows.getFirst();
  }
}
