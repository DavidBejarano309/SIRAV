package co.edu.sirav;

import static org.assertj.core.api.Assertions.*;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.*;
import java.util.concurrent.*;
import org.bson.Document;
import org.junit.jupiter.api.Test;
import org.springframework.data.mongodb.core.query.*;
import org.springframework.http.*;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;

// La condición de AuditSupport no se hereda: sin esto, "mvn verify" (por ejemplo al construir la imagen Docker) las ejecuta sin bases de auditoría.
@EnabledIfEnvironmentVariable(named = "SIRAV_AUDIT", matches = "true")
class ConcurrencyAuditTest extends AuditSupport {
  @Test
  void independentVehiclesAcceptAllEightConcurrentReservations() throws Exception {
    var fleet = new ArrayList<Fleet>();
    for (int i=0;i<8;i++) fleet.add(fleet());
    LocalDate from=today().plusDays(80);
    long actor=actor();
    assertThat(race(8,i -> sqlOutcome(() -> db.update("CALL sp_crear_reserva(?,?,?,?,?,?)",actor,fleet.get(i).client(),fleet.get(i).vehicle(),from,from.plusDays(1),UUID.randomUUID())))).containsOnly("OK");
  }

  @Test
  void confirmationAndCancellationAlwaysEndInAConsistentCancelledReservation() throws Exception {
    for (int round=0;round<4;round++) {
      long reservation=reserve(fleet(),today().plusDays(90),today().plusDays(91));
      long actor=actor();
      var outcomes=race(2,i -> sqlOutcome(() -> {
        if (i==0) db.update("CALL sp_confirmar_reserva(?,?)",actor,reservation);
        else db.update("CALL sp_cancelar_reserva(?,?,?)",actor,reservation,"AUDIT cancelacion concurrente");
      }));
      assertThat(outcomes.get(1)).isEqualTo("OK");
      assertThat(outcomes.get(0)).isIn("OK","P0001");
      assertThat(db.queryForObject("SELECT estado FROM reserva WHERE id_reserva=?",String.class,reservation)).isEqualTo("CANCELADA");
    }
  }

  @Test
  void twoAdministratorsCannotConcurrentlyDeactivateTheLastAdministrator() throws Exception {
    String firstToken=admin();
    long first=actor();
    String email="audit-admin-"+UUID.randomUUID()+"@example.com";
    var created=request(firstToken,HttpMethod.POST,"/users",Map.of("nombre","Audit","apellido","Admin","email",email,"password","AuditSegura2026!","roles",List.of("ADMIN")));
    assertThat(created.getStatusCode()).isEqualTo(HttpStatus.CREATED);
    long second=((Number)created.getBody().get("id")).longValue();
    String secondToken=login(email,"AuditSegura2026!");
    try {
      var outcomes=race(2,i -> request(i==0 ? firstToken : secondToken,HttpMethod.PUT,"/users/"+(i==0 ? first : second),Map.of("activo",false,"roles",List.of("ADMIN"))).getStatusCode().value());
      assertThat(outcomes).containsExactlyInAnyOrder(200,409);
      assertThat(db.queryForObject("SELECT count(*) FROM usuario u JOIN usuario_rol ur USING(id_usuario) JOIN rol r USING(id_rol) WHERE u.activo AND r.nombre='ADMIN'",Long.class)).isEqualTo(1);
    } finally {
      owner().update("UPDATE usuario SET activo=true WHERE id_usuario=?",first);
      owner().update("UPDATE usuario SET activo=false WHERE id_usuario=?",second);
    }
  }

  @Test
  void eightDifferentKeysCompetingForOneVehicleHaveExactlyOneWinner() throws Exception {
    for (int round = 0; round < 3; round++) {
      var f = fleet();
      LocalDate from = today().plusDays(30);
      long actor = actor();
      var results = race(8, i -> sqlOutcome(() -> db.update("CALL sp_crear_reserva(?,?,?,?,?,?)", actor, f.client(), f.vehicle(), from, from.plusDays(2), UUID.randomUUID())));
      assertThat(results.stream().filter("OK"::equals).count()).isEqualTo(1);
      assertThat(results).allMatch(value -> Set.of("OK", "P0001").contains(value));
      assertThat(db.queryForObject("SELECT count(*) FROM reserva WHERE id_vehiculo=?", Long.class, f.vehicle())).isEqualTo(1);
    }
  }

  @Test
  void eightSimultaneousRetriesCreateOnlyOneReservationAndOneAuditEvent() throws Exception {
    var f = fleet();
    UUID key = UUID.randomUUID();
    LocalDate from = today().plusDays(40);
    long actor = actor();
    var results = race(8, i -> sqlOutcome(() -> db.update("CALL sp_crear_reserva(?,?,?,?,?,?)", actor, f.client(), f.vehicle(), from, from.plusDays(1), key)));
    assertThat(results).containsOnly("OK");
    long reservation = db.queryForObject("SELECT id_reserva FROM reserva WHERE idempotencia=?", Long.class, key);
    assertThat(db.queryForObject("SELECT count(*) FROM reserva WHERE id_vehiculo=?", Long.class, f.vehicle())).isEqualTo(1);
    assertThat(db.queryForObject("SELECT count(*) FROM auditoria_reserva WHERE id_reserva=?", Long.class, reservation)).isEqualTo(1);
  }

  @Test
  void reservationAndMaintenanceCannotBothWinTheSameDates() throws Exception {
    for (int round = 0; round < 6; round++) {
      var f = fleet();
      LocalDate from = today().plusDays(50);
      long actor = actor();
      var results = race(2, i -> sqlOutcome(() -> {
        if (i == 0) db.update("CALL sp_crear_reserva(?,?,?,?,?,?)", actor, f.client(), f.vehicle(), from, from.plusDays(2), UUID.randomUUID());
        else db.update("INSERT INTO mantenimiento(id_vehiculo,fecha_inicio,fecha_fin,descripcion,estado) VALUES(?,?,?,'AUDIT RACE','PROGRAMADO')", f.vehicle(), from, from.plusDays(2));
      }));
      assertThat(results.stream().filter("OK"::equals).count()).isEqualTo(1);
      assertThat(results).allMatch(value -> Set.of("OK", "P0001").contains(value));
      assertThat(db.queryForObject("SELECT (SELECT count(*) FROM reserva WHERE id_vehiculo=?)+(SELECT count(*) FROM mantenimiento WHERE id_vehiculo=?)", Long.class, f.vehicle(), f.vehicle())).isEqualTo(1);
    }
  }

  @Test
  void eightOverlappingMaintenanceRequestsProduceOnlyOneBooking() throws Exception {
    var f = fleet();
    LocalDate from = today().plusDays(60);
    var results = race(8, i -> sqlOutcome(() -> db.update("INSERT INTO mantenimiento(id_vehiculo,fecha_inicio,fecha_fin,descripcion,estado) VALUES(?,?,?,'AUDIT RACE','PROGRAMADO')", f.vehicle(), from, from.plusDays(2))));
    assertThat(results.stream().filter("OK"::equals).count()).isEqualTo(1);
    assertThat(results).allMatch(value -> Set.of("OK", "23P01").contains(value));
  }

  @Test
  void concurrentHandoverAndReturnDoNotDuplicateRentalsPaymentsOrInspections() throws Exception {
    var f = fleet();
    long reservation = reserve(f, today(), today().plusDays(1));
    long actor = actor();
    db.update("CALL sp_confirmar_reserva(?,?)", actor, reservation);
    var starts = race(8, i -> sqlOutcome(() -> db.update("CALL sp_iniciar_alquiler(?,?,?,?,?::jsonb)", actor, reservation, 1000, new BigDecimal("80"), INSPECTION)));
    assertThat(starts.stream().filter("OK"::equals).count()).isEqualTo(1);
    assertThat(starts).allMatch(value -> Set.of("OK", "P0001").contains(value));
    long rental = db.queryForObject("SELECT id_alquiler FROM alquiler WHERE id_reserva=?", Long.class, reservation);
    var closes = race(8, i -> sqlOutcome(() -> db.update("CALL sp_cerrar_alquiler(?,?,?,?,?::jsonb)", actor, rental, 1010, new BigDecimal("70"), INSPECTION)));
    assertThat(closes.stream().filter("OK"::equals).count()).isEqualTo(1);
    assertThat(closes).allMatch(value -> Set.of("OK", "P0001").contains(value));
    assertThat(db.queryForObject("SELECT count(*) FROM alquiler WHERE id_reserva=?", Long.class, reservation)).isEqualTo(1);
    assertThat(db.queryForObject("SELECT count(*) FROM pago WHERE id_alquiler=?", Long.class, rental)).isEqualTo(1);
    assertThat(db.queryForObject("SELECT kilometraje_actual FROM vehiculo WHERE id_vehiculo=?", Integer.class, f.vehicle())).isEqualTo(1010);
    flush();
    assertThat(mongo.count(Query.query(Criteria.where("alquilerId").is(rental)), "inspecciones_vehiculo")).isEqualTo(2);
  }

  @Test
  void concurrentMongoCorrectionsHaveOneWinnerAndPreserveOriginalHistory() throws Exception {
    long rental = start(fleet());
    flush();
    Document original = mongo.findOne(Query.query(Criteria.where("alquilerId").is(rental)), Document.class, "inspecciones_vehiculo");
    String token = admin();
    var input = Map.of("version", 0, "inspeccion", Map.of("danos", List.of(), "evidencias", List.of(), "observaciones", "AUDIT CONCURRENT CORRECTION"));
    var results = race(8, i -> request(token, HttpMethod.PUT, "/inspections/" + original.get("_id"), input).getStatusCode().value());
    assertThat(results.stream().filter(value -> value == 200).count()).isEqualTo(1);
    assertThat(results).allMatch(value -> value == 200 || value == 409);
    Document updated = mongo.findById(original.get("_id"), Document.class, "inspecciones_vehiculo");
    assertThat(((Number) updated.get("version")).longValue()).isEqualTo(1);
    assertThat(updated.getList("historial", Document.class)).hasSize(1);
  }

  @Test
  void simultaneousOutboxPublishersDoNotLoseOrDuplicateEvents() throws Exception {
    var ids = new ArrayList<String>();
    for (int i = 0; i < 64; i++) ids.add(db.queryForObject("INSERT INTO evento_outbox(coleccion,documento) VALUES('bitacora_operaciones',jsonb_build_object('accion','AUDIT_PARALLEL','fecha',now())) RETURNING id::text", String.class));
    race(3, i -> { publisher.publish(); return true; });
    flush();
    assertThat(mongo.count(Query.query(Criteria.where("_id").in(ids)), "bitacora_operaciones")).isEqualTo(64);
    publisher.publish();
    assertThat(mongo.count(Query.query(Criteria.where("_id").in(ids)), "bitacora_operaciones")).isEqualTo(64);
  }

  @Test
  void tariffValidityCannotBeShortenedWhileAReservationIsBeingCommitted() throws Exception {
    var f = fleet();
    long actor = actor();
    LocalDate from = today().plusDays(70);
    var inserted = new CountDownLatch(1);
    var commit = new CountDownLatch(1);
    String application = "audit-rate-" + f.rate();
    try (var pool = Executors.newFixedThreadPool(2)) {
      var reservation = pool.submit(() -> transaction().execute(status -> {
        db.update("CALL sp_crear_reserva(?,?,?,?,?,?)", actor, f.client(), f.vehicle(), from, from.plusDays(3), UUID.randomUUID());
        inserted.countDown();
        try { assertThat(commit.await(20, TimeUnit.SECONDS)).isTrue(); }
        catch (InterruptedException e) { Thread.currentThread().interrupt(); throw new RuntimeException(e); }
        return true;
      }));
      assertThat(inserted.await(20, TimeUnit.SECONDS)).isTrue();
      var ending = pool.submit(() -> sqlOutcome(() -> transaction().executeWithoutResult(status -> {
        db.queryForObject("SELECT set_config('application_name',?,true)", String.class, application);
        db.update("UPDATE tarifa SET vigente_hasta=? WHERE id_tarifa=?", from.plusDays(1), f.rate());
      })));
      try {
        long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(5);
        while (!ending.isDone() && System.nanoTime() < deadline) {
          if (db.queryForObject("SELECT count(*) FROM pg_stat_activity WHERE application_name=? AND wait_event_type='Lock'", Long.class, application) > 0) break;
          Thread.sleep(20);
        }
      } finally { commit.countDown(); }
      assertThat(reservation.get(30, TimeUnit.SECONDS)).isTrue();
      assertThat(ending.get(30, TimeUnit.SECONDS)).isEqualTo("P0001");
    } finally { commit.countDown(); }
    assertThat(db.queryForObject("SELECT count(*) FROM reserva r JOIN tarifa t USING(id_tarifa) WHERE r.id_vehiculo=? AND t.vigente_hasta<r.fecha_fin", Long.class, f.vehicle())).isZero();
  }
}
