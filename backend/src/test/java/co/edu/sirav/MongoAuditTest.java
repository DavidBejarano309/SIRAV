package co.edu.sirav;

import static org.assertj.core.api.Assertions.*;

import co.edu.sirav.inspection.OutboxPublisher;
import com.mongodb.MongoWriteException;
import com.mongodb.client.MongoClients;
import java.util.*;
import java.util.stream.Stream;
import org.bson.Document;
import org.junit.jupiter.api.*;
import org.springframework.data.mongodb.core.MongoTemplate;
import org.springframework.data.mongodb.core.query.*;
import org.springframework.http.*;

class MongoAuditTest extends AuditSupport {
  @TestFactory
  Stream<DynamicTest> documentValidatorRejectsMissingFieldsAndWrongTypes() {
    long rental = start(fleet());
    flush();
    Document original = mongo.findOne(Query.query(Criteria.where("alquilerId").is(rental)),Document.class,"inspecciones_vehiculo");
    return Stream.of("alquilerId","vehiculoId","tipo","danos","anulada","tipo-invalido","danos-no-array","anulada-no-bool")
        .map(field -> DynamicTest.dynamicTest(field,() -> {
          var invalid = new Document(original);
          invalid.put("_id",UUID.randomUUID().toString());
          invalid.put("tipo","DEVOLUCION");
          switch(field) {
            case "tipo-invalido" -> invalid.put("tipo","OTRO");
            case "danos-no-array" -> invalid.put("danos","texto");
            case "anulada-no-bool" -> invalid.put("anulada","false");
            default -> invalid.remove(field);
          }
          assertThatThrownBy(() -> mongo.getCollection("inspecciones_vehiculo").insertOne(invalid))
              .isInstanceOfSatisfying(MongoWriteException.class,e -> assertThat(e.getError().getCode()).isEqualTo(121));
        }));
  }

  @Test
  void uniqueRentalAndInspectionTypeIndexRejectsDuplicates() {
    long rental = start(fleet());
    flush();
    var original = mongo.findOne(Query.query(Criteria.where("alquilerId").is(rental)),Document.class,"inspecciones_vehiculo");
    var duplicate = new Document(original);
    duplicate.put("_id",UUID.randomUUID().toString());
    assertThatThrownBy(() -> mongo.getCollection("inspecciones_vehiculo").insertOne(duplicate))
        .isInstanceOfSatisfying(MongoWriteException.class,e -> assertThat(e.getError().getCode()).isEqualTo(11000));
    assertThat(mongo.count(Query.query(Criteria.where("alquilerId").is(rental)),"inspecciones_vehiculo")).isEqualTo(1);
  }

  @Test
  void realConnectionFailureKeepsTheOutboxEventUntilItCanBeDelivered() {
    String id = db.queryForObject("INSERT INTO evento_outbox(coleccion,documento) VALUES('bitacora_operaciones',jsonb_build_object('accion','AUDIT_REAL_DISCONNECT','fecha',now())) RETURNING id::text",String.class);
    try (var client=MongoClients.create("mongodb://127.0.0.1:1/sirav_audit_unreachable?serverSelectionTimeoutMS=200&connectTimeoutMS=200&socketTimeoutMS=200")) {
      var unavailable = new MongoTemplate(client,"sirav_audit_unreachable");
      transaction().executeWithoutResult(status -> new OutboxPublisher(db,unavailable).publish());
    }
    assertThat(db.queryForObject("SELECT publicado_en IS NULL AND intentos=1 FROM evento_outbox WHERE id=?::uuid",Boolean.class,id)).isTrue();
    assertThat(mongo.findById(id,Document.class,"bitacora_operaciones")).isNull();
    flush();
    assertThat(mongo.findById(id,Document.class,"bitacora_operaciones")).isNotNull();
    assertThat(db.queryForObject("SELECT publicado_en IS NOT NULL AND intentos=2 FROM evento_outbox WHERE id=?::uuid",Boolean.class,id)).isTrue();
  }

  @Test
  void complexSearchAggregationsAndLogicalDeletionAgreeWithStoredDocuments() {
    var f = fleet();
    long rental = start(f);
    close(rental);
    flush();
    var original = mongo.findOne(Query.query(Criteria.where("alquilerId").is(rental).and("tipo").is("ENTREGA")),Document.class,"inspecciones_vehiculo");
    String token=admin();
    String zone="AUD-"+f.plate();
    var correction=Map.of("version",0,"inspeccion",Map.of("danos",List.of(Map.of("zona",zone,"severidad","ALTA","descripcion","Prueba documental")),"evidencias",List.of(),"observaciones","AUDIT"));
    assertThat(request(token,HttpMethod.PUT,"/inspections/"+original.get("_id"),correction).getStatusCode()).isEqualTo(HttpStatus.OK);
    var found=http.exchange("/api/inspections?severe=true&vehicle="+f.vehicle()+"&from="+today()+"&to="+today(),HttpMethod.GET,entity(token,null),List.class);
    assertThat(found.getStatusCode()).isEqualTo(HttpStatus.OK);
    assertThat(found.getBody()).hasSize(1);
    var analytics=request(token,HttpMethod.GET,"/inspections/analytics",null);
    assertThat(analytics.getStatusCode()).isEqualTo(HttpStatus.OK);
    var category=((List<Map>)analytics.getBody().get("porCategoria")).stream().filter(row -> ((Number)row.get("_id")).longValue()==f.category()).findFirst().orElseThrow();
    assertThat(((Number)category.get("inspecciones")).longValue()).isEqualTo(2);
    var zones=(List<Map>)analytics.getBody().get("zonasPorMes");
    assertThat(zones).anyMatch(row -> zone.equals(((Map)row.get("_id")).get("zona")) && ((Number)row.get("incidencias")).intValue()==1);
    var vehicles=(List<Map>)analytics.getBody().get("incidenciasPorVehiculo");
    assertThat(vehicles).anyMatch(row -> ((Number)row.get("_id")).longValue()==f.vehicle() && ((Number)row.get("incidencias")).intValue()==1);
    assertThat(request(token,HttpMethod.DELETE,"/inspections/"+original.get("_id"),Map.of("motivo","Anulacion controlada de auditoria")).getStatusCode()).isEqualTo(HttpStatus.NO_CONTENT);
    assertThat(mongo.findById(original.get("_id"),Document.class,"inspecciones_vehiculo").getBoolean("anulada")).isTrue();
    var after=http.exchange("/api/inspections?severe=true&vehicle="+f.vehicle(),HttpMethod.GET,entity(token,null),List.class);
    assertThat(after.getBody()).isEmpty();
    var status=request(token,HttpMethod.GET,"/rentals/"+rental+"/inspection-status",null);
    assertThat(status.getBody().get("estado")).isEqualTo("DISPONIBLE");
    assertThat((List)status.getBody().get("anuladas")).contains("ENTREGA");
  }
}
