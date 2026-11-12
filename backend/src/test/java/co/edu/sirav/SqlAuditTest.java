package co.edu.sirav;

import static org.assertj.core.api.Assertions.*;

import java.math.BigDecimal;
import java.util.*;
import java.util.function.Consumer;
import java.util.stream.Stream;
import org.junit.jupiter.api.*;
import org.springframework.http.*;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;

// La condición de AuditSupport no se hereda: sin esto, "mvn verify" (por ejemplo al construir la imagen Docker) las ejecuta sin bases de auditoría.
@EnabledIfEnvironmentVariable(named = "SIRAV_AUDIT", matches = "true")
class SqlAuditTest extends AuditSupport {
  @Test
  void allProjectRoutinesTriggersViewsAndRestrictedPrivilegesExist() {
    var names = db.queryForList("SELECT proname FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND proname ~ '^(fn_|trg_|sp_)'", String.class);
    assertThat(names).containsExactlyInAnyOrder("fn_actor", "fn_vehiculo_disponible", "fn_calcular_costo", "fn_calcular_cargo_retraso", "trg_validar_reserva", "trg_validar_mantenimiento", "trg_auditar_reserva", "trg_actualizar_estado_vehiculo", "trg_proteger_tarifa_historica", "sp_crear_reserva", "sp_confirmar_reserva", "sp_cancelar_reserva", "sp_iniciar_alquiler", "sp_cerrar_alquiler", "sp_cargar_historial_demo");
    assertThat(db.queryForObject("SELECT count(*) FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND NOT t.tgisinternal AND t.tgenabled='O'", Long.class)).isEqualTo(5);
    assertThat(db.queryForObject("SELECT count(*) FROM information_schema.views WHERE table_schema='public'", Long.class)).isEqualTo(2);
    assertThat(db.queryForObject("SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE'", Long.class)).isEqualTo(14);
    for (String table : List.of("reserva", "alquiler", "pago", "auditoria_reserva"))
      for (String permission : List.of("INSERT", "UPDATE", "DELETE"))
        assertThat(db.queryForObject("SELECT has_table_privilege(current_user,?,?)", Boolean.class, table, permission)).as(table + " " + permission).isFalse();
    assertThat(db.queryForObject("SELECT has_schema_privilege(current_user,'public','CREATE')", Boolean.class)).isFalse();
    assertThat(db.queryForObject("SELECT bool_and(prosecdef) FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname LIKE 'sp_%'", Boolean.class)).isTrue();
  }

  @Test
  void actorSettingIsLocalToTheTransaction() {
    long actor = actor();
    transaction().executeWithoutResult(status -> {
      db.queryForObject("SELECT set_config('sirav.actor',?,true)", String.class, Long.toString(actor));
      assertThat(db.queryForObject("SELECT fn_actor()", Long.class)).isEqualTo(actor);
    });
    assertThat(db.queryForObject("SELECT fn_actor()", Long.class)).isNull();
  }

  record InvalidSql(String name, String state, Consumer<Fleet> execute) {}
  @TestFactory
  Stream<DynamicTest> databaseConstraintsRejectInvalidRows() {
    return Stream.of(
        new InvalidSql("correo normalizado", "23514", f -> db.update("INSERT INTO usuario(nombre,apellido,email,password_hash) VALUES('AUD','SQL',?,'unused')", UUID.randomUUID()+"@EXAMPLE.COM")),
        new InvalidSql("correo duplicado", "23505", f -> db.update("INSERT INTO usuario(nombre,apellido,email,password_hash) VALUES('AUD','SQL','admin@sirav.local','unused')")),
        new InvalidSql("cliente sin identidad", "23514", f -> db.update("INSERT INTO cliente(documento) VALUES(?)", "AUD-"+UUID.randomUUID().toString().substring(0,16))),
        new InvalidSql("identidad duplicada de cuenta", "23514", f -> db.update("INSERT INTO cliente(id_usuario,nombres,apellidos,documento) VALUES(?,'Duplicado','SQL',?)", actor(), "AUD-"+UUID.randomUUID().toString().substring(0,16))),
        new InvalidSql("anio invalido", "23514", f -> db.update("UPDATE vehiculo SET anio=1949 WHERE id_vehiculo=?", f.vehicle())),
        new InvalidSql("kilometraje negativo", "23514", f -> db.update("UPDATE vehiculo SET kilometraje_actual=-1 WHERE id_vehiculo=?", f.vehicle())),
        new InvalidSql("estado de vehiculo invalido", "23514", f -> db.update("UPDATE vehiculo SET estado_operativo='INVALIDO' WHERE id_vehiculo=?", f.vehicle())),
        new InvalidSql("tarifa no positiva", "23514", f -> db.update("UPDATE tarifa SET valor_diario=0 WHERE id_tarifa=?", f.rate())),
        new InvalidSql("tarifas solapadas", "23P01", f -> db.update("INSERT INTO tarifa(id_categoria,valor_diario,vigente_desde) VALUES(?,50000,'2021-01-01')", f.category())),
        new InvalidSql("reserva sin dias", "23514", f -> owner().update("INSERT INTO reserva(id_cliente,id_vehiculo,id_tarifa,fecha_inicio,fecha_fin,estado) VALUES(?,?,?,current_date+1,current_date+1,'SOLICITADA')", f.client(), f.vehicle(), f.rate())),
        new InvalidSql("cliente inexistente", "23503", f -> owner().update("INSERT INTO reserva(id_cliente,id_vehiculo,id_tarifa,fecha_inicio,fecha_fin,estado) VALUES(-1,?,?,current_date+1,current_date+2,'SOLICITADA')", f.vehicle(), f.rate())),
        new InvalidSql("mantenimiento sin dias", "23514", f -> db.update("INSERT INTO mantenimiento(id_vehiculo,fecha_inicio,fecha_fin,descripcion,estado) VALUES(?,current_date+1,current_date+1,'AUDIT','PROGRAMADO')", f.vehicle())),
        new InvalidSql("pago negativo", "23514", f -> owner().update("INSERT INTO pago(id_alquiler,monto,tipo,estado) VALUES(-1,-1,'SIMULADO','APROBADO')")),
        new InvalidSql("pago no simulado", "23514", f -> owner().update("INSERT INTO pago(id_alquiler,monto,tipo,estado) VALUES(-1,1,'REAL','APROBADO')")),
        new InvalidSql("cargo negativo", "23514", f -> owner().update("INSERT INTO cargo_adicional(id_alquiler,concepto,monto) VALUES(-1,'AUDIT',-1)")),
        new InvalidSql("rol duplicado", "23505", f -> db.update("INSERT INTO usuario_rol(id_usuario,id_rol) SELECT id_usuario,id_rol FROM usuario_rol WHERE id_usuario=? LIMIT 1", actor()))
    ).map(c -> DynamicTest.dynamicTest(c.name(), () -> {
      var f = fleet();
      assertThat(sqlOutcome(() -> c.execute().accept(f))).isEqualTo(c.state());
    }));
  }

  @Test
  void cancellationRequiresANonNullMeaningfulReasonEvenWhenCallingSqlDirectly() {
    var f = fleet();
    long reservation = reserve(f, today().plusDays(10), today().plusDays(12));
    assertThat(sqlOutcome(() -> db.update("CALL sp_cancelar_reserva(?,?,?)", actor(), reservation, null))).isEqualTo("P0001");
    assertThat(sqlOutcome(() -> db.update("CALL sp_cancelar_reserva(?,?,?)", actor(), reservation, "  x  "))).isEqualTo("P0001");
    assertThat(db.queryForObject("SELECT estado FROM reserva WHERE id_reserva=?", String.class, reservation)).isEqualTo("SOLICITADA");
    db.update("CALL sp_cancelar_reserva(?,?,?)", actor(), reservation, "AUDIT cancelacion valida");
    assertThat(db.queryForObject("SELECT observacion FROM auditoria_reserva WHERE id_reserva=? AND estado_nuevo='CANCELADA'", String.class, reservation)).isEqualTo("AUDIT cancelacion valida");
  }

  @Test
  void reservationDatesAndIdentityAreImmutableAndIdempotencyCannotBeReusedForOtherData() {
    var f = fleet();
    UUID key = UUID.randomUUID();
    var from = today().plusDays(15);
    reserve(f, from, from.plusDays(2), key);
    long id = db.queryForObject("SELECT id_reserva FROM reserva WHERE idempotencia=?", Long.class, key);
    assertThat(sqlOutcome(() -> reserve(f, from, from.plusDays(3), key))).isEqualTo("P0001");
    assertThat(sqlOutcome(() -> owner().update("UPDATE reserva SET fecha_fin=fecha_fin+1 WHERE id_reserva=?", id))).isEqualTo("P0001");
    assertThat(sqlOutcome(() -> owner().update("UPDATE reserva SET estado='CERRADA' WHERE id_reserva=?", id))).isEqualTo("P0001");
    db.update("CALL sp_cancelar_reserva(?,?,?)", actor(), id, "AUDIT idempotencia");
    reserve(f, from, from.plusDays(2), key);
    assertThat(db.queryForObject("SELECT estado FROM reserva WHERE id_reserva=?", String.class, id)).isEqualTo("CANCELADA");
    assertThat(db.queryForObject("SELECT count(*) FROM reserva WHERE id_vehiculo=?", Long.class, f.vehicle())).isEqualTo(1);
  }

  @Test
  void invalidHandoverAndReturnRollBackAllTheirChanges() {
    var f = fleet();
    long id = reserve(f, today(), today().plusDays(1));
    long actor = actor();
    assertThat(sqlOutcome(() -> db.update("CALL sp_iniciar_alquiler(?,?,?,?,?::jsonb)", actor, id, 1000, new BigDecimal("80"), INSPECTION))).isEqualTo("P0001");
    db.update("CALL sp_confirmar_reserva(?,?)", actor, id);
    for (String inspection : List.of("{}", "{\"danos\":null}", "{\"danos\":{}}"))
      assertThat(sqlOutcome(() -> db.update("CALL sp_iniciar_alquiler(?,?,?,?,?::jsonb)", actor, id, 1000, new BigDecimal("80"), inspection))).isEqualTo("P0001");
    assertThat(sqlOutcome(() -> db.update("CALL sp_iniciar_alquiler(?,?,?,?,?::jsonb)", actor, id, 999, new BigDecimal("80"), INSPECTION))).isEqualTo("P0001");
    assertThat(sqlOutcome(() -> db.update("CALL sp_iniciar_alquiler(?,?,?,?,?::jsonb)", actor, id, 1000, new BigDecimal("101"), INSPECTION))).isEqualTo("23514");
    assertThat(db.queryForObject("SELECT count(*) FROM alquiler WHERE id_reserva=?", Long.class, id)).isZero();
    db.update("CALL sp_iniciar_alquiler(?,?,?,?,?::jsonb)", actor, id, 1000, new BigDecimal("80"), INSPECTION);
    long rental = db.queryForObject("SELECT id_alquiler FROM alquiler WHERE id_reserva=?", Long.class, id);
    assertThat(sqlOutcome(() -> db.update("CALL sp_cerrar_alquiler(?,?,?,?,?::jsonb)", actor, rental, 999, new BigDecimal("70"), INSPECTION))).isEqualTo("P0001");
    assertThat(sqlOutcome(() -> db.update("CALL sp_cerrar_alquiler(?,?,?,?,?::jsonb)", actor, rental, 1010, new BigDecimal("101"), INSPECTION))).isEqualTo("23514");
    assertThat(db.queryForObject("SELECT count(*) FROM pago WHERE id_alquiler=?", Long.class, rental)).isZero();
    assertThat(db.queryForObject("SELECT estado FROM alquiler WHERE id_alquiler=?", String.class, rental)).isEqualTo("ACTIVA");
    close(rental);
    assertThat(db.queryForList("SELECT estado_nuevo FROM auditoria_reserva WHERE id_reserva=? ORDER BY id_auditoria", String.class, id)).containsExactly("SOLICITADA", "CONFIRMADA", "ACTIVA", "CERRADA");
    assertThat(db.queryForObject("SELECT bool_and(id_usuario=?) FROM auditoria_reserva WHERE id_reserva=?", Boolean.class, actor, id)).isTrue();
    assertThat(db.queryForObject("SELECT estado_operativo FROM vehiculo WHERE id_vehiculo=?", String.class, f.vehicle())).isEqualTo("DISPONIBLE");
  }

  @Test
  void historicRatesAndBogotaHalfCentBoundariesRemainStable() {
    var f = fleet();
    db.update("UPDATE tarifa SET valor_diario=0.01 WHERE id_tarifa=?", f.rate());
    var from = today().plusDays(20);
    long reservation = reserve(f, from, from.plusDays(2));
    assertThat(db.queryForObject("SELECT fn_calcular_costo(?)", BigDecimal.class, reservation)).isEqualByComparingTo("0.02");
    assertThat(db.queryForObject("SELECT fn_calcular_cargo_retraso(?,?::timestamptz)", BigDecimal.class, reservation, from.plusDays(3)+"T04:59:59Z")).isZero();
    assertThat(db.queryForObject("SELECT fn_calcular_cargo_retraso(?,?::timestamptz)", BigDecimal.class, reservation, from.plusDays(3)+"T05:00:00Z")).isEqualByComparingTo("0.01");
    assertThat(sqlOutcome(() -> db.update("UPDATE tarifa SET valor_diario=2 WHERE id_tarifa=?", f.rate()))).isEqualTo("P0001");
    assertThat(sqlOutcome(() -> db.update("UPDATE tarifa SET vigente_desde='2021-01-01' WHERE id_tarifa=?", f.rate()))).isEqualTo("P0001");
    assertThat(sqlOutcome(() -> db.update("UPDATE tarifa SET vigente_hasta=? WHERE id_tarifa=?", from.plusDays(1), f.rate()))).isEqualTo("P0001");
    db.update("UPDATE tarifa SET vigente_hasta=? WHERE id_tarifa=?", from.plusDays(2), f.rate());
  }

  @Test
  void allSixReportsReturnCorrectValuesForAnIsolatedRental() {
    var f = fleet();
    long rental = start(f);
    owner().update("INSERT INTO cargo_adicional(id_alquiler,concepto,monto) VALUES(?,'AUDIT A',10000),(?,'AUDIT B',5000)", rental, rental);
    close(rental);
    String token = admin();
    String dates = "?from="+today()+"&to="+today().plusDays(1);
    var results = new HashMap<String, List<Map>>();
    for (String type : List.of("occupancy","revenue","ranking","clients","late","availability")) {
      var response = http.exchange("/api/reports/"+type+dates, HttpMethod.GET, entity(token,null), List.class);
      assertThat(response.getStatusCode()).as(type).isEqualTo(HttpStatus.OK);
      results.put(type, response.getBody());
    }
    var revenue = results.get("revenue").stream().filter(row -> row.get("categoria").equals(db.queryForObject("SELECT nombre FROM categoria_vehiculo WHERE id_categoria=?", String.class, f.category()))).findFirst().orElseThrow();
    assertThat(new BigDecimal(revenue.get("ingresos_simulados").toString())).isEqualByComparingTo("135000");
    assertThat(((Number) revenue.get("alquileres")).intValue()).isEqualTo(1);
    var occupancy = results.get("occupancy").stream().filter(row -> f.plate().equals(row.get("placa"))).findFirst().orElseThrow();
    assertThat(((Number) occupancy.get("dias_alquilados")).intValue()).isEqualTo(1);
    assertThat(new BigDecimal(occupancy.get("ocupacion_porcentaje").toString())).isEqualByComparingTo("100");
    var rank = results.get("ranking").stream().filter(row -> f.plate().equals(row.get("placa"))).findFirst().orElseThrow();
    assertThat(((Number) rank.get("puesto")).intValue()).isEqualTo(1);
    var client = results.get("clients").stream().filter(row -> ((Number) row.get("id_cliente")).longValue()==f.client()).findFirst().orElseThrow();
    assertThat(((Number) client.get("reservas")).intValue()).isEqualTo(1);
    var charged = results.get("late").stream().filter(row -> f.plate().equals(row.get("placa"))).findFirst().orElseThrow();
    assertThat(((Number) charged.get("dias_retraso")).intValue()).isZero();
    assertThat(new BigDecimal(charged.get("cargos").toString())).isEqualByComparingTo("15000");
    assertThat(results.get("availability")).anyMatch(row -> f.plate().equals(row.get("placa")));
    var view = db.queryForMap("SELECT costo_base,cargos,pagado FROM v_reservas WHERE id_alquiler=?", rental);
    assertThat((BigDecimal) view.get("costo_base")).isEqualByComparingTo("120000");
    assertThat((BigDecimal) view.get("cargos")).isEqualByComparingTo("15000");
    assertThat((BigDecimal) view.get("pagado")).isEqualByComparingTo("135000");
  }

  @Test
  void demoHistoryProcedureIsIdempotent() {
    var before = db.queryForMap("SELECT (SELECT count(*) FROM reserva) reservas,(SELECT count(*) FROM alquiler) alquileres,(SELECT count(*) FROM pago) pagos");
    db.update("CALL sp_cargar_historial_demo()");
    db.update("CALL sp_cargar_historial_demo()");
    assertThat(db.queryForMap("SELECT (SELECT count(*) FROM reserva) reservas,(SELECT count(*) FROM alquiler) alquileres,(SELECT count(*) FROM pago) pagos")).isEqualTo(before);
  }
}
