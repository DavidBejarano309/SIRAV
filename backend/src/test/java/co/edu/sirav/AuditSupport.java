package co.edu.sirav;

import static org.assertj.core.api.Assertions.*;

import co.edu.sirav.inspection.OutboxPublisher;
import java.math.BigDecimal;
import java.sql.SQLException;
import java.time.LocalDate;
import java.util.*;
import java.util.concurrent.*;
import java.util.function.IntFunction;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.dao.DataAccessException;
import org.springframework.data.mongodb.core.MongoTemplate;
import org.springframework.http.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = {
    "sirav.outbox-initial-delay=86400000",
    "sirav.evidence-directory=${SIRAV_TEST_EVIDENCE_DIR:../.runtime/test-evidencias}"
})
@EnabledIfEnvironmentVariable(named = "SIRAV_AUDIT", matches = "true")
abstract class AuditSupport {
  @Autowired JdbcTemplate db;
  @Autowired MongoTemplate mongo;
  @Autowired TestRestTemplate http;
  @Autowired OutboxPublisher publisher;
  @Autowired PlatformTransactionManager transactions;
  static final String INSPECTION = "{\"danos\":[],\"evidencias\":[],\"observaciones\":\"AUDIT\"}";
  private static String cachedAdmin;

  @BeforeEach
  void isolatedDatabaseAndPendingEvents() {
    assertThat(db.queryForObject("SELECT current_database()", String.class))
        .matches("sirav_audit_[0-9]{14}");
    assertThat(mongo.getDb().getName()).matches("sirav_audit_[0-9]{14}");
    flush();
  }

  JdbcTemplate owner() {
    assertThat(System.getenv("DB_URL")).matches("jdbc:postgresql://[^/]+/sirav_audit_[0-9]{14}");
    return new JdbcTemplate(new DriverManagerDataSource(System.getenv("DB_URL"),
        "sirav_owner", System.getenv("SIRAV_AUDIT_OWNER_PASSWORD")));
  }

  TransactionTemplate transaction() { return new TransactionTemplate(transactions); }
  LocalDate today() {
    return db.queryForObject("SELECT (now() AT TIME ZONE 'America/Bogota')::date", LocalDate.class);
  }
  long actor() {
    return db.queryForObject("SELECT id_usuario FROM usuario WHERE email='admin@sirav.local'", Long.class);
  }

  record Fleet(long category, long rate, long vehicle, long client, String plate) {}
  Fleet fleet() {
    String key = UUID.randomUUID().toString().replace("-", "");
    long category = db.queryForObject("INSERT INTO categoria_vehiculo(nombre) VALUES(?) RETURNING id_categoria", Long.class, "AUD-" + key);
    long rate = db.queryForObject("INSERT INTO tarifa(id_categoria,valor_diario,vigente_desde) VALUES(?,120000,'2020-01-01') RETURNING id_tarifa", Long.class, category);
    String plate = "A" + key.substring(0, 11).toUpperCase(Locale.ROOT);
    long vehicle = db.queryForObject("INSERT INTO vehiculo(id_categoria,placa,marca,modelo,anio,kilometraje_actual,estado_operativo) VALUES(?,?,'AUDITORIA','SQL',2025,1000,'DISPONIBLE') RETURNING id_vehiculo", Long.class, category, plate);
    long client = db.queryForObject("INSERT INTO cliente(nombres,apellidos,documento,licencia_conduccion) VALUES('Auditoria','SQL',?,'AUD-LIC') RETURNING id_cliente", Long.class, "AUD-" + key.substring(0, 20));
    return new Fleet(category, rate, vehicle, client, plate);
  }

  long reserve(Fleet f, LocalDate from, LocalDate to) {
    UUID key = UUID.randomUUID();
    reserve(f, from, to, key);
    return db.queryForObject("SELECT id_reserva FROM reserva WHERE idempotencia=?", Long.class, key);
  }
  void reserve(Fleet f, LocalDate from, LocalDate to, UUID key) {
    db.update("CALL sp_crear_reserva(?,?,?,?,?,?)", actor(), f.client(), f.vehicle(), from, to, key);
  }
  long start(Fleet f) {
    long reservation = reserve(f, today(), today().plusDays(1));
    db.update("CALL sp_confirmar_reserva(?,?)", actor(), reservation);
    db.update("CALL sp_iniciar_alquiler(?,?,?,?,?::jsonb)", actor(), reservation, 1000, new BigDecimal("80"), INSPECTION);
    return db.queryForObject("SELECT id_alquiler FROM alquiler WHERE id_reserva=?", Long.class, reservation);
  }
  void close(long rental) {
    db.update("CALL sp_cerrar_alquiler(?,?,?,?,?::jsonb)", actor(), rental, 1010, new BigDecimal("70"), INSPECTION);
  }
  void flush() {
    for (int i = 0; i < 50 && db.queryForObject("SELECT count(*) FROM evento_outbox WHERE publicado_en IS NULL", Long.class) > 0; i++) publisher.publish();
    assertThat(db.queryForObject("SELECT count(*) FROM evento_outbox WHERE publicado_en IS NULL", Long.class)).isZero();
  }

  String login(String email, String password) {
    var response = http.postForEntity("/api/auth/login", Map.of("email", email, "password", password), Map.class);
    assertThat(response.getStatusCode()).withFailMessage("Login %s: %s", email, response.getBody()).isEqualTo(HttpStatus.OK);
    return response.getBody().get("token").toString();
  }
  String admin() {
    if (cachedAdmin == null || http.exchange("/api/auth/me", HttpMethod.GET, entity(cachedAdmin, null), String.class).getStatusCode() != HttpStatus.OK)
      cachedAdmin = login("admin@sirav.local", System.getenv("DEMO_PASSWORD"));
    return cachedAdmin;
  }
  HttpEntity<Object> entity(String token, Object value) {
    var headers = new HttpHeaders();
    headers.setBearerAuth(token);
    headers.setContentType(MediaType.APPLICATION_JSON);
    headers.set("Idempotency-Key", UUID.randomUUID().toString());
    return new HttpEntity<>(value, headers);
  }
  ResponseEntity<Map> request(String token, HttpMethod method, String path, Object value) {
    return http.exchange("/api" + path, method, entity(token, value), Map.class);
  }

  <T> List<T> race(int clients, IntFunction<T> task) throws Exception {
    var barrier = new CyclicBarrier(clients);
    try (var pool = Executors.newFixedThreadPool(clients)) {
      var futures = new ArrayList<Future<T>>();
      for (int i = 0; i < clients; i++) {
        int index = i;
        futures.add(pool.submit(() -> { barrier.await(20, TimeUnit.SECONDS); return task.apply(index); }));
      }
      var results = new ArrayList<T>();
      for (var future : futures) results.add(future.get(60, TimeUnit.SECONDS));
      return results;
    }
  }
  String sqlOutcome(Runnable task) {
    try { task.run(); return "OK"; }
    catch (DataAccessException failure) {
      // Los errores de negocio usan SQLSTATE propios (SR001 a SR008, excepciones e_ con nombre);
      // estas pruebas los agrupan como P0001 y pruebas-excepciones.sql verifica cada código exacto.
      if (failure.getMostSpecificCause() instanceof SQLException sql)
        return sql.getSQLState() != null && sql.getSQLState().startsWith("SR") ? "P0001" : sql.getSQLState();
      throw failure;
    }
  }
}
