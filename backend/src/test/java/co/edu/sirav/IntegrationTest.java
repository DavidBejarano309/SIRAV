package co.edu.sirav;

import static org.assertj.core.api.Assertions.*;

import java.time.LocalDate;
import java.time.ZoneId;
import java.util.*;
import java.util.concurrent.*;
import org.junit.jupiter.api.*;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.http.*;
import org.springframework.jdbc.core.JdbcTemplate;

/** Pruebas contra PostgreSQL y MongoDB reales; nunca se sustituyen por H2 o mocks. */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@EnabledIfEnvironmentVariable(named = "SIRAV_INTEGRATION", matches = "true")
@TestMethodOrder(MethodOrderer.OrderAnnotation.class)
class IntegrationTest {
  // Las reglas de fechas de la base usan la hora de Bogotá; el servidor de CI está en UTC.
  private static final ZoneId BOGOTA = ZoneId.of("America/Bogota");

  @Autowired TestRestTemplate http;
  @Autowired JdbcTemplate db;

  String token(String email) {
    var response =
        http.postForEntity(
            "/api/auth/login",
            Map.of("email", email, "password", System.getenv("DEMO_PASSWORD")),
            Map.class);
    assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
    return (String) Objects.requireNonNull(response.getBody()).get("token");
  }

  HttpEntity<Object> entity(String token, Object body) {
    var headers = new HttpHeaders();
    headers.setBearerAuth(token);
    headers.setContentType(MediaType.APPLICATION_JSON);
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
                List.of("evidencia/prueba.jpg"),
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
}
