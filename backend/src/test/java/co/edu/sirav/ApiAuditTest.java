package co.edu.sirav;

import static org.assertj.core.api.Assertions.*;

import java.util.*;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.http.*;

@EnabledIfEnvironmentVariable(named = "SIRAV_AUDIT", matches = "true")
class ApiAuditTest extends AuditSupport {
  Map<String,Object> userInput(Object roles) {
    return Map.of("nombre","Auditoria","apellido","API","email",UUID.randomUUID()+"@example.com","password","AuditSegura2026!","roles",roles);
  }

  @Test
  void userCreationRejectsNullRoles() {
    var response = request(admin(), HttpMethod.POST, "/users", userInput(Collections.singletonList(null)));
    assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
  }

  @Test
  void permissionsRejectNullRolesWithoutErasingExistingPermissions() {
    String token = admin();
    var created = request(token,HttpMethod.POST,"/users",userInput(List.of("OPERADOR")));
    assertThat(created.getStatusCode()).isEqualTo(HttpStatus.CREATED);
    long id = ((Number) created.getBody().get("id")).longValue();
    var response = request(token,HttpMethod.PUT,"/users/"+id,Map.of("activo",true,"roles",Collections.singletonList(null)));
    assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
    assertThat(db.queryForObject("SELECT count(*) FROM usuario_rol WHERE id_usuario=?",Long.class,id)).isEqualTo(1);
  }

  @Test
  void nullDamageElementsCannotCreateAnInvalidInspection() {
    var f = fleet();
    long reservation = reserve(f,today(),today().plusDays(1));
    db.update("CALL sp_confirmar_reserva(?,?)",actor(),reservation);
    var input = Map.of("kilometraje",1000,"combustible",80,"inspeccion",Map.of("danos",Collections.singletonList(null),"evidencias",List.of()));
    assertThat(request(admin(),HttpMethod.POST,"/reservations/"+reservation+"/start",input).getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
    assertThat(db.queryForObject("SELECT count(*) FROM alquiler WHERE id_reserva=?",Long.class,reservation)).isZero();
  }

  @Test
  void missingRateEndDateIsABadRequestRatherThanAServerError() {
    var f = fleet();
    assertThat(request(admin(),HttpMethod.PUT,"/rates/"+f.rate()+"/end",Map.of()).getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
    assertThat(db.queryForObject("SELECT vigente_hasta FROM tarifa WHERE id_tarifa=?",java.sql.Date.class,f.rate())).isNull();
    assertThat(request(admin(),HttpMethod.PUT,"/rates/"+f.rate()+"/end",Map.of("vigenteHasta",today().plusDays(1).toString())).getStatusCode()).isEqualTo(HttpStatus.OK);
  }

  @Test
  void missingMaintenanceStateIsABadRequestRatherThanAServerError() {
    var f = fleet();
    long id = db.queryForObject("INSERT INTO mantenimiento(id_vehiculo,fecha_inicio,fecha_fin,descripcion,estado) VALUES(?,?,?,'AUDIT API','PROGRAMADO') RETURNING id_mantenimiento",Long.class,f.vehicle(),today().plusDays(30),today().plusDays(31));
    assertThat(request(admin(),HttpMethod.PATCH,"/maintenance/"+id,Map.of()).getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
    assertThat(db.queryForObject("SELECT estado FROM mantenimiento WHERE id_mantenimiento=?",String.class,id)).isEqualTo("PROGRAMADO");
    assertThat(request(admin(),HttpMethod.PATCH,"/maintenance/"+id,Map.of("estado","COMPLETADO")).getStatusCode()).isEqualTo(HttpStatus.OK);
  }

  @Test
  void unauthenticatedUsersAndClientsCannotAccessAdministrativeEndpoints() {
    for (String path : List.of("/api/vehicles","/api/users","/api/inspections/analytics","/api/maintenance"))
      assertThat(http.getForEntity(path,String.class).getStatusCode()).as(path).isEqualTo(HttpStatus.UNAUTHORIZED);
    String customer = login("cliente@sirav.local",System.getenv("DEMO_PASSWORD"));
    for (String path : List.of("/users","/maintenance","/rates","/inspections","/inspections/analytics"))
      assertThat(http.exchange("/api"+path,HttpMethod.GET,entity(customer,null),String.class).getStatusCode()).as(path).isEqualTo(HttpStatus.FORBIDDEN);
  }

  @Test
  void unicodePasswordsOver72BytesAreRejectedBeforeBcryptTruncation() {
    var body = new HashMap<>(userInput(List.of("OPERADOR")));
    body.put("password","é".repeat(37));
    assertThat(request(admin(),HttpMethod.POST,"/users",body).getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
    assertThat(db.queryForObject("SELECT count(*) FROM usuario WHERE email=?",Long.class,body.get("email"))).isZero();
  }

  @Test
  void loginLimitRejectsTheSixteenthAttemptForTheSameAccountAndAddress() {
    String email = "audit-limit-"+UUID.randomUUID()+"@example.com";
    for (int i=0;i<15;i++) assertThat(http.postForEntity("/api/auth/login",Map.of("email",email,"password","Incorrecta2026!"),Map.class).getStatusCode()).isEqualTo(HttpStatus.UNAUTHORIZED);
    assertThat(http.postForEntity("/api/auth/login",Map.of("email",email,"password","Incorrecta2026!"),Map.class).getStatusCode()).isEqualTo(HttpStatus.TOO_MANY_REQUESTS);
  }
}
