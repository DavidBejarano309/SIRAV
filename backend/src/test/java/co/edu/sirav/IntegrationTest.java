package co.edu.sirav;

import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;

import co.edu.sirav.inspection.OutboxPublisher;
import com.mongodb.MongoTimeoutException;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.*;
import java.util.concurrent.*;
import org.bson.Document;
import org.junit.jupiter.api.*;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.core.io.ByteArrayResource;
import org.springframework.data.mongodb.core.MongoTemplate;
import org.springframework.data.mongodb.core.query.*;
import org.springframework.http.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.util.LinkedMultiValueMap;

/**
 * Integración con motores reales; solo el transporte fallido se simula en la prueba de reintentos.
 */
@SpringBootTest(
    webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
    properties = {
      "sirav.outbox-initial-delay=86400000",
      "sirav.evidence-directory=${SIRAV_TEST_EVIDENCE_DIR:../.runtime/test-evidencias}"
    })
@EnabledIfEnvironmentVariable(named = "SIRAV_INTEGRATION", matches = "true")
@TestMethodOrder(MethodOrderer.OrderAnnotation.class)
class IntegrationTest {
  // Las reglas de fechas de la base usan la hora de Bogotá; el servidor de CI está en UTC.
  private static final ZoneId BOGOTA = ZoneId.of("America/Bogota");

  @Autowired TestRestTemplate http;
  @Autowired JdbcTemplate db;
  @Autowired MongoTemplate mongo;
  @Autowired OutboxPublisher publisher;
  @Autowired PlatformTransactionManager transactions;
  private String adminToken;

  @BeforeEach
  void flushOutbox() {
    for (int i = 0;
        i < 20
            && db.queryForObject(
                    "SELECT count(*) FROM evento_outbox WHERE publicado_en IS NULL", Long.class)
                > 0;
        i++) publisher.publish();
  }

  String token(String email) {
    if (email.equals("admin@sirav.local") && adminToken != null) return adminToken;
    var response =
        http.postForEntity(
            "/api/auth/login",
            Map.of("email", email, "password", System.getenv("DEMO_PASSWORD")),
            Map.class);
    assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
    String value = (String) Objects.requireNonNull(response.getBody()).get("token");
    if (email.equals("admin@sirav.local")) adminToken = value;
    return value;
  }

  HttpEntity<Object> entity(String token, Object body) {
    var headers = new HttpHeaders();
    headers.setBearerAuth(token);
    headers.setContentType(MediaType.APPLICATION_JSON);
    headers.set("Idempotency-Key", UUID.randomUUID().toString());
    return new HttpEntity<>(body, headers);
  }

  @Test
  void authEnforcesRolesAndRevokesSessions() {
    String token = token("cliente@sirav.local");
    assertThat(
            http.exchange("/api/clients", HttpMethod.GET, entity(token, null), String.class)
                .getStatusCode())
        .isEqualTo(HttpStatus.FORBIDDEN);
    assertThat(
            http.exchange("/api/vehicles", HttpMethod.GET, entity(token, null), String.class)
                .getStatusCode())
        .isEqualTo(HttpStatus.OK);
    assertThat(
            http.exchange("/api/auth/logout", HttpMethod.POST, entity(token, null), String.class)
                .getStatusCode())
        .isEqualTo(HttpStatus.NO_CONTENT);
    assertThat(
            http.exchange("/api/vehicles", HttpMethod.GET, entity(token, null), String.class)
                .getStatusCode())
        .isEqualTo(HttpStatus.UNAUTHORIZED);
  }

  @Test
  @Order(1)
  void lifecyclePersistsInspectionAndSimulatedPayment() throws InterruptedException {
    String token = token("admin@sirav.local");
    long client =
        db.queryForObject("SELECT id_cliente FROM cliente WHERE documento='DEMO-001'", Long.class);
    long vehicle =
        db.queryForObject("SELECT id_vehiculo FROM vehiculo WHERE placa='SIR102'", Long.class);
    var headers = new HttpHeaders();
    headers.setBearerAuth(token);
    headers.setContentType(MediaType.APPLICATION_JSON);
    headers.set("Idempotency-Key", UUID.randomUUID().toString());
    var input =
        Map.of(
            "idCliente",
            client,
            "idVehiculo",
            vehicle,
            "fechaInicio",
            LocalDate.now(BOGOTA).toString(),
            "fechaFin",
            LocalDate.now(BOGOTA).plusDays(1).toString());
    var created =
        http.exchange(
            "/api/reservations", HttpMethod.POST, new HttpEntity<>(input, headers), Map.class);
    assertThat(created.getStatusCode())
        .withFailMessage("%s", created.getBody())
        .isEqualTo(HttpStatus.CREATED);
    long id = ((Number) Objects.requireNonNull(created.getBody()).get("id_reserva")).longValue();
    var retry =
        http.exchange(
            "/api/reservations", HttpMethod.POST, new HttpEntity<>(input, headers), Map.class);
    assertThat(retry.getBody().get("id_reserva")).isEqualTo(created.getBody().get("id_reserva"));
    assertThat(
            http.exchange(
                    "/api/reservations/" + id + "/confirm",
                    HttpMethod.POST,
                    entity(token, null),
                    String.class)
                .getStatusCode())
        .isEqualTo(HttpStatus.NO_CONTENT);
    var handover =
        Map.of(
            "kilometraje",
            100000,
            "combustible",
            90,
            "inspeccion",
            Map.of(
                "danos",
                List.of(
                    Map.of(
                        "zona", "Puerta", "severidad", "ALTA", "descripcion", "Rayón de prueba")),
                "evidencias",
                List.of(upload(token, id, true)),
                "observaciones",
                "Prueba integrada"));
    var start =
        http.exchange(
            "/api/reservations/" + id + "/start",
            HttpMethod.POST,
            entity(token, handover),
            Map.class);
    assertThat(start.getStatusCode())
        .withFailMessage("%s", start.getBody())
        .isEqualTo(HttpStatus.OK);
    long rental = ((Number) start.getBody().get("id_alquiler")).longValue();
    var invalid =
        Map.of(
            "kilometraje",
            0,
            "combustible",
            80,
            "inspeccion",
            Map.of("danos", List.of(), "evidencias", List.of()));
    assertThat(
            http.exchange(
                    "/api/rentals/" + rental + "/close",
                    HttpMethod.POST,
                    entity(token, invalid),
                    Map.class)
                .getStatusCode())
        .isEqualTo(HttpStatus.CONFLICT);
    assertThat(
            db.queryForObject(
                "SELECT estado FROM alquiler WHERE id_alquiler=?", String.class, rental))
        .isEqualTo("ACTIVA");
    assertThat(
            db.queryForObject("SELECT count(*) FROM pago WHERE id_alquiler=?", Long.class, rental))
        .isZero();
    var close =
        http.exchange(
            "/api/rentals/" + rental + "/close",
            HttpMethod.POST,
            entity(token, handover),
            Map.class);
    assertThat(close.getStatusCode())
        .withFailMessage("%s", close.getBody())
        .isEqualTo(HttpStatus.OK);
    assertThat(close.getBody().get("estado")).isEqualTo("CERRADA");
    assertThat(((Number) close.getBody().get("pagado")).doubleValue()).isGreaterThan(0);
    assertThat(
            http.exchange(
                    "/api/rentals/" + rental + "/close",
                    HttpMethod.POST,
                    entity(token, handover),
                    Map.class)
                .getStatusCode())
        .isEqualTo(HttpStatus.CONFLICT);
    assertThat(
            db.queryForObject("SELECT count(*) FROM pago WHERE id_alquiler=?", Long.class, rental))
        .isEqualTo(1L);
    flushOutbox();
    for (int i = 0; i < 50; i++) {
      var inspections =
          http.exchange(
              "/api/rentals/" + rental + "/inspections",
              HttpMethod.GET,
              entity(token, null),
              List.class);
      if (inspections.getBody() != null && inspections.getBody().size() == 2) return;
      Thread.sleep(200);
    }
    fail("Las dos inspecciones no se sincronizaron en 10 segundos");
  }

  @Test
  void concurrentReservationsHaveExactlyOneWinner() throws Exception {
    long client =
        db.queryForObject("SELECT id_cliente FROM cliente WHERE documento='DEMO-001'", Long.class);
    long actor =
        db.queryForObject(
            "SELECT id_usuario FROM usuario WHERE email='admin@sirav.local'", Long.class);
    long vehicle =
        db.queryForObject("SELECT id_vehiculo FROM vehiculo WHERE placa='SIR101'", Long.class);
    var keys = List.of(UUID.randomUUID(), UUID.randomUUID());
    var barrier = new CyclicBarrier(2);
    try (var pool = Executors.newFixedThreadPool(2)) {
      var tasks = new ArrayList<Future<Boolean>>();
      for (var key : keys)
        tasks.add(
            pool.submit(
                () -> {
                  barrier.await(5, TimeUnit.SECONDS);
                  try {
                    db.update(
                        "CALL sp_crear_reserva(?,?,?,?,?,?)",
                        actor,
                        client,
                        vehicle,
                        LocalDate.now(BOGOTA).plusDays(90),
                        LocalDate.now(BOGOTA).plusDays(93),
                        key);
                    return true;
                  } catch (org.springframework.dao.DataAccessException e) {
                    return false;
                  }
                }));
      int successes = 0;
      for (var result : tasks) if (result.get(10, TimeUnit.SECONDS)) successes++;
      assertThat(successes).isEqualTo(1);
    } finally {
      for (var key : keys)
        for (long id :
            db.queryForList("SELECT id_reserva FROM reserva WHERE idempotencia=?", Long.class, key))
          db.update(
              "CALL sp_cancelar_reserva(?,?,?)", actor, id, "Limpieza de prueba de concurrencia");
    }
  }

  @Test
  void allSixSqlReportsExecuteAgainstRealDatabase() {
    String token = token("admin@sirav.local");
    for (String type :
        List.of("occupancy", "revenue", "ranking", "clients", "late", "availability")) {
      var response =
          http.exchange(
              "/api/reports/"
                  + type
                  + "?from="
                  + LocalDate.now(BOGOTA).withDayOfMonth(1)
                  + "&to="
                  + LocalDate.now(BOGOTA).plusDays(5),
              HttpMethod.GET,
              entity(token, null),
              String.class);
      assertThat(response.getStatusCode())
          .withFailMessage("%s: %s", type, response.getBody())
          .isEqualTo(HttpStatus.OK);
    }
  }

  @Test
  void applicationRoleCannotWriteReservationsDirectly() {
    assertThatThrownBy(() -> db.update("UPDATE reserva SET estado='CERRADA' WHERE false"))
        .isInstanceOf(org.springframework.dao.DataAccessException.class);
  }

  @Test
  void registeredClientUsesUserIdentityWithoutDuplicatingIt() {
    String key = UUID.randomUUID().toString();
    var input =
        Map.of(
            "nombre",
            "Ana",
            "apellido",
            "Prueba",
            "email",
            key + "@example.com",
            "password",
            "PruebaSegura2026!",
            "documento",
            key.substring(0, 20),
            "licencia",
            "LIC-PRUEBA");
    var response = http.postForEntity("/api/auth/register", input, Map.class);
    assertThat(response.getStatusCode())
        .withFailMessage("%s", response.getBody())
        .isEqualTo(HttpStatus.CREATED);
    long id = ((Number) response.getBody().get("id")).longValue();
    var client = db.queryForMap("SELECT * FROM cliente WHERE id_usuario=?", id);
    assertThat(client.get("nombres")).isNull();
    assertThat(client.get("apellidos")).isNull();
    assertThat(client.get("email")).isNull();
    db.update("UPDATE usuario SET nombre='Ana actualizada' WHERE id_usuario=?", id);
    assertThat(
            db.queryForObject(
                "SELECT nombres FROM v_cliente_contacto WHERE id_usuario=?", String.class, id))
        .isEqualTo("Ana actualizada");
    assertThatThrownBy(
            () -> db.update("UPDATE cliente SET nombres='Duplicado' WHERE id_usuario=?", id))
        .isInstanceOf(org.springframework.dao.DataAccessException.class);
  }

  @Test
  void clientWithoutAccountKeepsItsOwnIdentity() {
    String token = token("admin@sirav.local");
    String document = "INV-" + UUID.randomUUID().toString().substring(0, 12);
    var input =
        Map.of(
            "nombres",
            "Invitado",
            "apellidos",
            "Prueba",
            "documento",
            document,
            "email",
            "invitado@example.com",
            "licenciaConduccion",
            "LIC-INV");
    var created = http.exchange("/api/clients", HttpMethod.POST, entity(token, input), Map.class);
    assertThat(created.getStatusCode())
        .withFailMessage("%s", created.getBody())
        .isEqualTo(HttpStatus.OK);
    long id = ((Number) created.getBody().get("id_cliente")).longValue();
    var contact = db.queryForMap("SELECT * FROM v_cliente_contacto WHERE id_cliente=?", id);
    assertThat(contact.get("id_usuario")).isNull();
    assertThat(contact.get("nombres")).isEqualTo("Invitado");
    assertThat(contact.get("email")).isEqualTo("invitado@example.com");
    var found =
        http.exchange(
            "/api/clients?search=" + document, HttpMethod.GET, entity(token, null), List.class);
    assertThat(found.getStatusCode()).isEqualTo(HttpStatus.OK);
    assertThat(found.getBody()).hasSize(1);
  }

  @Test
  @Order(2)
  void mongodbCrudVersioningComplexSearchAndAggregations() throws InterruptedException {
    String token = token("admin@sirav.local");
    List<Map<String, Object>> inspections = List.of();
    for (int i = 0; i < 50; i++) {
      var response =
          http.exchange(
              "/api/inspections?severe=true", HttpMethod.GET, entity(token, null), List.class);
      assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
      inspections = response.getBody();
      if (inspections != null && !inspections.isEmpty()) break;
      Thread.sleep(200);
    }
    assertThat(inspections).isNotEmpty();
    var original = inspections.getFirst();
    String id = original.get("_id").toString();
    var correction =
        Map.of(
            "version",
            original.get("version"),
            "inspeccion",
            Map.of(
                "danos",
                List.of(
                    Map.of(
                        "zona", "Puerta", "severidad", "ALTA", "descripcion", "Daño confirmado")),
                "evidencias",
                List.of(),
                "observaciones",
                "Corregida en prueba"));
    assertThat(
            http.exchange(
                    "/api/inspections/" + id, HttpMethod.PUT, entity(token, correction), Map.class)
                .getStatusCode())
        .isEqualTo(HttpStatus.OK);
    assertThat(
            http.exchange(
                    "/api/inspections/" + id, HttpMethod.PUT, entity(token, correction), Map.class)
                .getStatusCode())
        .isEqualTo(HttpStatus.CONFLICT);
    var analytics =
        http.exchange("/api/inspections/analytics", HttpMethod.GET, entity(token, null), Map.class);
    assertThat(analytics.getStatusCode()).isEqualTo(HttpStatus.OK);
    assertThat(analytics.getBody())
        .containsKeys("porCategoria", "zonasPorMes", "incidenciasPorVehiculo");
    assertThat(
            http.exchange(
                    "/api/inspections/" + id,
                    HttpMethod.DELETE,
                    entity(token, Map.of("motivo", "Anulación de prueba")),
                    String.class)
                .getStatusCode())
        .isEqualTo(HttpStatus.NO_CONTENT);
  }

  String upload(String token, long reservation, boolean valid) {
    byte[] bytes =
        valid
            ? Base64.getDecoder()
                .decode(
                    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=")
            : "texto".getBytes();
    var file =
        new ByteArrayResource(bytes) {
          @Override
          public String getFilename() {
            return "prueba.png";
          }
        };
    var body = new LinkedMultiValueMap<String, Object>();
    body.add("file", file);
    var headers = new HttpHeaders();
    headers.setBearerAuth(token);
    headers.setContentType(MediaType.MULTIPART_FORM_DATA);
    var response =
        http.exchange(
            "/api/reservations/" + reservation + "/evidence",
            HttpMethod.POST,
            new HttpEntity<>(body, headers),
            Map.class);
    assertThat(response.getStatusCode())
        .withFailMessage("%s", response.getBody())
        .isEqualTo(valid ? HttpStatus.CREATED : HttpStatus.BAD_REQUEST);
    if (!valid) return "";
    String reference = response.getBody().get("referencia").toString();
    assertThat(
            http.exchange(reference, HttpMethod.GET, entity(token, null), byte[].class).getBody())
        .isEqualTo(bytes);
    return reference;
  }

  @Test
  void usersSupportMultipleRolesProfileChangesAndRevocation() {
    String admin = token("admin@sirav.local");
    String key = UUID.randomUUID().toString().substring(0, 12);
    String email = key + "@example.com";
    var created =
        http.exchange(
            "/api/users",
            HttpMethod.POST,
            entity(
                admin,
                Map.of(
                    "nombre",
                    "Usuario",
                    "apellido",
                    "Prueba",
                    "email",
                    email,
                    "password",
                    "PruebaSegura2026!",
                    "roles",
                    List.of("OPERADOR", "CLIENTE"),
                    "documento",
                    key,
                    "licencia",
                    "LIC-TEST")),
            Map.class);
    assertThat(created.getStatusCode())
        .withFailMessage("%s", created.getBody())
        .isEqualTo(HttpStatus.CREATED);
    long id = ((Number) created.getBody().get("id")).longValue();
    var login =
        http.postForEntity(
            "/api/auth/login", Map.of("email", email, "password", "PruebaSegura2026!"), Map.class);
    String session = login.getBody().get("token").toString();
    assertThat(((Map) login.getBody().get("user")).get("roles"))
        .isEqualTo(List.of("CLIENTE", "OPERADOR"));
    assertThat(
            http.exchange("/api/users", HttpMethod.GET, entity(session, null), String.class)
                .getStatusCode())
        .isEqualTo(HttpStatus.FORBIDDEN);
    assertThat(
            http.exchange(
                    "/api/auth/me",
                    HttpMethod.PUT,
                    entity(
                        session,
                        Map.of(
                            "nombre",
                            "Nuevo",
                            "apellido",
                            "Nombre",
                            "telefono",
                            "3000000000",
                            "licencia",
                            "LIC-NUEVA")),
                    Map.class)
                .getStatusCode())
        .isEqualTo(HttpStatus.OK);
    assertThat(
            db.queryForObject(
                "SELECT nombres FROM v_cliente_contacto WHERE id_usuario=?", String.class, id))
        .isEqualTo("Nuevo");
    assertThat(
            db.queryForMap("SELECT nombres,apellidos,email FROM cliente WHERE id_usuario=?", id)
                .values())
        .containsOnlyNulls();
    assertThat(
            http.exchange(
                    "/api/auth/password",
                    HttpMethod.POST,
                    entity(
                        session,
                        Map.of("actual", "PruebaSegura2026!", "nueva", "NuevaSegura2026!")),
                    String.class)
                .getStatusCode())
        .isEqualTo(HttpStatus.NO_CONTENT);
    assertThat(
            http.exchange("/api/auth/me", HttpMethod.GET, entity(session, null), String.class)
                .getStatusCode())
        .isEqualTo(HttpStatus.UNAUTHORIZED);
    login =
        http.postForEntity(
            "/api/auth/login", Map.of("email", email, "password", "NuevaSegura2026!"), Map.class);
    assertThat(login.getStatusCode()).isEqualTo(HttpStatus.OK);
    session = login.getBody().get("token").toString();
    long client =
        db.queryForObject("SELECT id_cliente FROM cliente WHERE id_usuario=?", Long.class, id);
    long vehicle =
        db.queryForObject("SELECT id_vehiculo FROM vehiculo WHERE placa='SIR505'", Long.class);
    LocalDate reservationFrom = LocalDate.now(BOGOTA).plusDays(200);
    while (!db.queryForObject(
        "SELECT fn_vehiculo_disponible(?,?,?)",
        Boolean.class,
        vehicle,
        reservationFrom,
        reservationFrom.plusDays(1))) reservationFrom = reservationFrom.plusDays(2);
    var reservation =
        http.exchange(
            "/api/reservations",
            HttpMethod.POST,
            entity(
                session,
                Map.of(
                    "idVehiculo",
                    vehicle,
                    "fechaInicio",
                    reservationFrom.toString(),
                    "fechaFin",
                    reservationFrom.plusDays(1).toString())),
            Map.class);
    assertThat(reservation.getStatusCode())
        .withFailMessage("%s", reservation.getBody())
        .isEqualTo(HttpStatus.CREATED);
    assertThat(
            http.exchange(
                    "/api/users/" + id,
                    HttpMethod.PUT,
                    entity(admin, Map.of("activo", false, "roles", List.of("CLIENTE", "OPERADOR"))),
                    Map.class)
                .getStatusCode())
        .isEqualTo(HttpStatus.OK);
    assertThat(
            http.exchange("/api/auth/me", HttpMethod.GET, entity(session, null), String.class)
                .getStatusCode())
        .isEqualTo(HttpStatus.UNAUTHORIZED);
    assertThat(
            db.queryForObject(
                "SELECT count(*) FROM reserva WHERE id_cliente=?", Long.class, client))
        .isEqualTo(1);
    flushOutbox();
    assertThat(mongo.count(Query.query(Criteria.where("usuarioId").is(id)), "bitacora_operaciones"))
        .isGreaterThan(2);
    assertThat(
            http.exchange(
                    "/api/audit/events?from="
                        + LocalDate.now(BOGOTA).minusDays(1)
                        + "&to="
                        + LocalDate.now(BOGOTA).plusDays(1),
                    HttpMethod.GET,
                    entity(admin, null),
                    List.class)
                .getBody())
        .isNotEmpty();
  }

  @Test
  void clientsCannotAssignPrivilegesOrReadOtherPeoplesData() {
    String key = UUID.randomUUID().toString().substring(0, 12);
    String email = key + "@example.com";
    var input =
        Map.of(
            "nombre",
            "Cliente",
            "apellido",
            "Aislado",
            "email",
            email,
            "password",
            "PruebaSegura2026!",
            "documento",
            key,
            "licencia",
            "LIC",
            "roles",
            List.of("ADMIN"));
    assertThat(http.postForEntity("/api/auth/register", input, Map.class).getStatusCode())
        .isEqualTo(HttpStatus.CREATED);
    assertThat(http.postForEntity("/api/auth/register", input, Map.class).getStatusCode())
        .isEqualTo(HttpStatus.CONFLICT);
    var login =
        http.postForEntity(
            "/api/auth/login", Map.of("email", email, "password", "PruebaSegura2026!"), Map.class);
    assertThat(((Map) login.getBody().get("user")).get("roles")).isEqualTo(List.of("CLIENTE"));
    String session = login.getBody().get("token").toString();
    long reservation = db.queryForObject("SELECT min(id_reserva) FROM reserva", Long.class);
    long rental = db.queryForObject("SELECT min(id_alquiler) FROM alquiler", Long.class);
    for (String path :
        List.of(
            "/users",
            "/maintenance",
            "/reports/revenue?from=2020-01-01&to=2030-01-01",
            "/reservations/" + reservation + "/history",
            "/rentals/" + rental + "/inspections",
            "/rentals/" + rental + "/payments"))
      assertThat(
              http.exchange("/api" + path, HttpMethod.GET, entity(session, null), String.class)
                  .getStatusCode())
          .withFailMessage(path)
          .isEqualTo(HttpStatus.FORBIDDEN);
    for (String path : List.of("/reservations", "/rentals", "/charges"))
      assertThat(
              http.exchange("/api" + path, HttpMethod.GET, entity(session, null), List.class)
                  .getBody())
          .isEmpty();
    long adminId =
        db.queryForObject(
            "SELECT id_usuario FROM usuario WHERE email='admin@sirav.local'", Long.class);
    assertThat(
            http.exchange(
                    "/api/users/" + adminId,
                    HttpMethod.PUT,
                    entity(
                        token("admin@sirav.local"),
                        Map.of("activo", false, "roles", List.of("ADMIN"))),
                    Map.class)
                .getStatusCode())
        .isEqualTo(HttpStatus.CONFLICT);
  }

  @Test
  void maintenanceEditsPreserveHistoryAndAvailability() {
    String admin = token("admin@sirav.local");
    long vehicle =
        db.queryForObject("SELECT id_vehiculo FROM vehiculo WHERE placa='SIR504'", Long.class);
    LocalDate from = LocalDate.now(BOGOTA).plusDays(150);
    LocalDate to = from.plusDays(3);
    var input =
        Map.of(
            "idVehiculo",
            vehicle,
            "fechaInicio",
            from.toString(),
            "fechaFin",
            to.toString(),
            "descripcion",
            "Revisión de prueba");
    var created =
        http.exchange("/api/maintenance", HttpMethod.POST, entity(admin, input), Map.class);
    assertThat(created.getStatusCode()).isEqualTo(HttpStatus.OK);
    long id = ((Number) created.getBody().get("id_mantenimiento")).longValue();
    assertThat(
            http.exchange("/api/maintenance", HttpMethod.POST, entity(admin, input), Map.class)
                .getStatusCode())
        .isEqualTo(HttpStatus.CONFLICT);
    assertThat(
            db.queryForObject(
                "SELECT fn_vehiculo_disponible(?,?,?)", Boolean.class, vehicle, from, to))
        .isFalse();
    var changed =
        Map.of(
            "idVehiculo",
            vehicle,
            "fechaInicio",
            to.toString(),
            "fechaFin",
            to.plusDays(2).toString(),
            "descripcion",
            "Reprogramado para prueba");
    assertThat(
            http.exchange(
                    "/api/maintenance/" + id, HttpMethod.PUT, entity(admin, changed), Map.class)
                .getStatusCode())
        .isEqualTo(HttpStatus.OK);
    assertThat(
            db.queryForObject(
                "SELECT fn_vehiculo_disponible(?,?,?)", Boolean.class, vehicle, from, to))
        .isTrue();
    assertThat(
            http.exchange(
                    "/api/maintenance/" + id,
                    HttpMethod.PATCH,
                    entity(admin, Map.of("estado", "COMPLETADO")),
                    Map.class)
                .getStatusCode())
        .isEqualTo(HttpStatus.OK);
    assertThat(
            db.queryForObject(
                "SELECT estado FROM mantenimiento WHERE id_mantenimiento=?", String.class, id))
        .isEqualTo("COMPLETADO");
  }

  @Test
  void historicalTariffsAndBogotaRoundingAreStable() {
    long reservation =
        db.queryForObject("SELECT min(id_reserva) FROM reserva WHERE estado='CERRADA'", Long.class);
    var row =
        db.queryForMap(
            "SELECT r.id_tarifa,r.fecha_fin,t.valor_diario,fn_calcular_costo(id_reserva) base FROM"
                + " reserva r JOIN tarifa t USING(id_tarifa) WHERE id_reserva=?",
            reservation);
    assertThatThrownBy(
            () ->
                db.update(
                    "UPDATE tarifa SET valor_diario=valor_diario+1 WHERE id_tarifa=?",
                    row.get("id_tarifa")))
        .isInstanceOf(org.springframework.dao.DataAccessException.class);
    assertThat(db.queryForObject("SELECT fn_calcular_costo(?)", BigDecimal.class, reservation))
        .isEqualByComparingTo(row.get("base").toString());
    LocalDate end = ((java.sql.Date) row.get("fecha_fin")).toLocalDate();
    assertThat(
            db.queryForObject(
                "SELECT fn_calcular_cargo_retraso(?,?::timestamptz)",
                BigDecimal.class,
                reservation,
                end + "T23:59:59-05:00"))
        .isZero();
    assertThat(
            db.queryForObject(
                "SELECT fn_calcular_cargo_retraso(?,?::timestamptz)",
                BigDecimal.class,
                reservation,
                end.plusDays(1) + "T00:00:00-05:00"))
        .isEqualByComparingTo(
            ((BigDecimal) row.get("valor_diario")).multiply(new BigDecimal("0.5")).setScale(2));
    assertThat(db.queryForObject("SELECT count(*) FROM vehiculo", Long.class))
        .isGreaterThanOrEqualTo(25);
    assertThat(db.queryForObject("SELECT count(*) FROM categoria_vehiculo", Long.class))
        .isGreaterThanOrEqualTo(5);
  }

  @Test
  void missingMongoDocumentIsReportedAndFailedPublishIsRetried() {
    String admin = token("admin@sirav.local");
    var document =
        mongo.findOne(
            Query.query(Criteria.where("anulada").is(false)),
            Document.class,
            "inspecciones_vehiculo");
    assertThat(document).isNotNull();
    long rental = ((Number) document.get("alquilerId")).longValue();
    try {
      mongo.remove(
          Query.query(Criteria.where("_id").is(document.get("_id"))), "inspecciones_vehiculo");
      var status =
          http.exchange(
              "/api/rentals/" + rental + "/inspection-status",
              HttpMethod.GET,
              entity(admin, null),
              Map.class);
      assertThat(status.getStatusCode()).isEqualTo(HttpStatus.OK);
      assertThat(status.getBody().get("estado")).isEqualTo("INCONSISTENTE");
    } finally {
      mongo.insert(document, "inspecciones_vehiculo");
    }
    flushOutbox();
    String id =
        db.queryForObject(
            "INSERT INTO evento_outbox(coleccion,documento)"
                + " VALUES('bitacora_operaciones',jsonb_build_object('accion','PRUEBA_REINTENTO','fecha',now()))"
                + " RETURNING id::text",
            String.class);
    var disconnected = mock(MongoTemplate.class);
    when(disconnected.upsert(any(Query.class), any(Update.class), anyString()))
        .thenThrow(new MongoTimeoutException("Fallo de transporte simulado"));
    new TransactionTemplate(transactions)
        .executeWithoutResult(s -> new OutboxPublisher(db, disconnected).publish());
    assertThat(
            db.queryForObject(
                "SELECT publicado_en IS NULL AND intentos>0 FROM evento_outbox WHERE id=?::uuid",
                Boolean.class,
                id))
        .isTrue();
    flushOutbox();
    assertThat(mongo.findById(id, Document.class, "bitacora_operaciones")).isNotNull();
    assertThat(
            db.queryForObject(
                "SELECT publicado_en IS NOT NULL FROM evento_outbox WHERE id=?::uuid",
                Boolean.class,
                id))
        .isTrue();
  }

  @Test
  void adjacentDatesMaintenanceConflictsAndHalfCentRounding() {
    long actor =
        db.queryForObject(
            "SELECT id_usuario FROM usuario WHERE email='admin@sirav.local'", Long.class);
    long client =
        db.queryForObject("SELECT id_cliente FROM cliente WHERE documento='DEMO-001'", Long.class);
    String key = UUID.randomUUID().toString().substring(0, 10);
    long category =
        db.queryForObject(
            "INSERT INTO categoria_vehiculo(nombre) VALUES(?) RETURNING id_categoria",
            Long.class,
            "Prueba-" + key);
    db.update(
        "INSERT INTO tarifa(id_categoria,valor_diario,vigente_desde) VALUES(?,0.01,'2020-01-01')",
        category);
    long vehicle =
        db.queryForObject(
            "INSERT INTO"
                + " vehiculo(id_categoria,placa,marca,modelo,anio,kilometraje_actual,estado_operativo)"
                + " VALUES(?,?,'Prueba','Temporal',2025,0,'DISPONIBLE') RETURNING id_vehiculo",
            Long.class,
            category,
            "T" + key.toUpperCase());
    var keys = List.of(UUID.randomUUID(), UUID.randomUUID());
    LocalDate from = LocalDate.now(BOGOTA).plusDays(250);
    try {
      db.update(
          "CALL sp_crear_reserva(?,?,?,?,?,?)",
          actor,
          client,
          vehicle,
          from,
          from.plusDays(2),
          keys.get(0));
      db.update(
          "CALL sp_crear_reserva(?,?,?,?,?,?)",
          actor,
          client,
          vehicle,
          from.plusDays(2),
          from.plusDays(4),
          keys.get(1));
      assertThatThrownBy(
              () ->
                  db.update(
                      "CALL sp_crear_reserva(?,?,?,?,?,?)",
                      actor,
                      client,
                      vehicle,
                      from.plusDays(1),
                      from.plusDays(3),
                      UUID.randomUUID()))
          .isInstanceOf(org.springframework.dao.DataAccessException.class);
      assertThatThrownBy(
              () ->
                  db.update(
                      "CALL sp_crear_reserva(?,?,?,?,?,?)",
                      actor,
                      client,
                      vehicle,
                      LocalDate.now(BOGOTA).minusDays(2),
                      LocalDate.now(BOGOTA).minusDays(1),
                      UUID.randomUUID()))
          .isInstanceOf(org.springframework.dao.DataAccessException.class);
      assertThatThrownBy(
              () ->
                  db.update(
                      "INSERT INTO"
                          + " mantenimiento(id_vehiculo,fecha_inicio,fecha_fin,descripcion,estado)"
                          + " VALUES(?,?,?,'Conflicto de prueba','PROGRAMADO')",
                      vehicle,
                      from,
                      from.plusDays(1)))
          .isInstanceOf(org.springframework.dao.DataAccessException.class);
      assertThat(
              db.queryForObject(
                  "SELECT count(*) FROM reserva WHERE id_vehiculo=?", Long.class, vehicle))
          .isEqualTo(2);
      assertThat(
              db.queryForObject(
                  "SELECT count(*) FROM mantenimiento WHERE id_vehiculo=?", Long.class, vehicle))
          .isZero();
      long reservation =
          db.queryForObject(
              "SELECT id_reserva FROM reserva WHERE idempotencia=?", Long.class, keys.get(0));
      assertThat(
              db.queryForObject(
                  "SELECT fn_calcular_cargo_retraso(?,?::timestamptz)",
                  BigDecimal.class,
                  reservation,
                  from.plusDays(3) + "T00:00:00-05:00"))
          .isEqualByComparingTo("0.01");
      upload(token("admin@sirav.local"), reservation, false);
    } finally {
      for (UUID id : keys)
        for (long reservation :
            db.queryForList("SELECT id_reserva FROM reserva WHERE idempotencia=?", Long.class, id))
          db.update(
              "CALL sp_cancelar_reserva(?,?,?)", actor, reservation, "Fin de prueba de intervalos");
      db.update("UPDATE vehiculo SET estado_operativo='INACTIVO' WHERE id_vehiculo=?", vehicle);
    }
  }

  @Test
  void rentalRemainsConsistentWhenMongoTransportFails() {
    long actor =
        db.queryForObject(
            "SELECT id_usuario FROM usuario WHERE email='admin@sirav.local'", Long.class);
    long client =
        db.queryForObject("SELECT id_cliente FROM cliente WHERE documento='DEMO-001'", Long.class);
    long vehicle =
        db.queryForObject("SELECT id_vehiculo FROM vehiculo WHERE placa='SIR503'", Long.class);
    UUID key = UUID.randomUUID();
    db.update(
        "CALL sp_crear_reserva(?,?,?,?,?,?)",
        actor,
        client,
        vehicle,
        LocalDate.now(BOGOTA),
        LocalDate.now(BOGOTA).plusDays(1),
        key);
    long reservation =
        db.queryForObject("SELECT id_reserva FROM reserva WHERE idempotencia=?", Long.class, key);
    db.update("CALL sp_confirmar_reserva(?,?)", actor, reservation);
    flushOutbox();
    String inspection =
        "{\"danos\":[],\"evidencias\":[],\"observaciones\":\"Fallo parcial controlado\"}";
    int km =
        db.queryForObject(
            "SELECT kilometraje_actual FROM vehiculo WHERE id_vehiculo=?", Integer.class, vehicle);
    db.update("CALL sp_iniciar_alquiler(?,?,?,?,?::jsonb)", actor, reservation, km, 80, inspection);
    long rental =
        db.queryForObject(
            "SELECT id_alquiler FROM alquiler WHERE id_reserva=?", Long.class, reservation);
    try {
      var disconnected = mock(MongoTemplate.class);
      when(disconnected.upsert(any(Query.class), any(Update.class), anyString()))
          .thenThrow(new MongoTimeoutException("MongoDB no disponible en esta prueba"));
      new TransactionTemplate(transactions)
          .executeWithoutResult(s -> new OutboxPublisher(db, disconnected).publish());
      assertThat(
              db.queryForObject(
                  "SELECT estado FROM alquiler WHERE id_alquiler=?", String.class, rental))
          .isEqualTo("ACTIVA");
      assertThat(
              db.queryForObject(
                  "SELECT count(*) FROM evento_outbox WHERE coleccion='inspecciones_vehiculo' AND"
                      + " documento->>'alquilerId'=? AND publicado_en IS NULL",
                  Long.class,
                  Long.toString(rental)))
          .isEqualTo(1);
      assertThat(
              mongo.count(
                  Query.query(Criteria.where("alquilerId").is(rental)), "inspecciones_vehiculo"))
          .isZero();
      flushOutbox();
      assertThat(
              mongo.count(
                  Query.query(Criteria.where("alquilerId").is(rental)), "inspecciones_vehiculo"))
          .isEqualTo(1);
    } finally {
      db.update("CALL sp_cerrar_alquiler(?,?,?,?,?::jsonb)", actor, rental, km, 70, inspection);
      flushOutbox();
    }
  }
}
