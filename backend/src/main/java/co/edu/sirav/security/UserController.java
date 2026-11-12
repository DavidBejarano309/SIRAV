package co.edu.sirav.security;

import co.edu.sirav.common.ApiException;
import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import java.util.*;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/users")
@PreAuthorize("hasRole('ADMIN')")
public class UserController {
  public record NewUser(
      @NotBlank @Size(max = 100) String nombre,
      @NotBlank @Size(max = 100) String apellido,
      @NotBlank @Email @Size(max = 150) String email,
      @NotBlank @Size(min = 10, max = 72) String password,
      @NotEmpty Set<@NotNull @Pattern(regexp = "ADMIN|OPERADOR|CLIENTE") String> roles,
      @Size(max = 30) String documento,
      @Size(max = 40) String licencia) {}

  public record Permissions(
      boolean activo, @NotEmpty Set<@NotNull @Pattern(regexp = "ADMIN|OPERADOR|CLIENTE") String> roles) {}

  private final JdbcTemplate db;
  private final PasswordEncoder passwords;
  private final AuditService audit;
  private final Access access;

  public UserController(
      JdbcTemplate db, PasswordEncoder passwords, AuditService audit, Access access) {
    this.db = db;
    this.passwords = passwords;
    this.audit = audit;
    this.access = access;
  }

  @GetMapping
  public List<Map<String, Object>> users() {
    return db.queryForList(
        "SELECT u.id_usuario,u.nombre,u.apellido,u.email,u.activo,string_agg(r.nombre,',' ORDER BY"
            + " r.nombre) roles FROM usuario u JOIN usuario_rol ur USING(id_usuario) JOIN rol r"
            + " USING(id_rol) GROUP BY u.id_usuario ORDER BY u.id_usuario");
  }

  @PostMapping
  @ResponseStatus(HttpStatus.CREATED)
  @Transactional
  public Map<String, Object> create(
      JwtAuthenticationToken auth, @Valid @RequestBody NewUser input) {
    AuthService.validatePassword(input.password());
    if (input.roles().contains("CLIENTE")
        && (input.documento() == null
            || input.documento().isBlank()
            || input.licencia() == null
            || input.licencia().isBlank()))
      throw new ApiException(
          HttpStatus.BAD_REQUEST, "El rol cliente requiere documento y licencia");
    long id =
        Objects.requireNonNull(
            db.queryForObject(
                "INSERT INTO usuario(nombre,apellido,email,password_hash) VALUES(?,?,?,?) RETURNING"
                    + " id_usuario",
                Long.class,
                input.nombre().trim(),
                input.apellido().trim(),
                input.email().trim().toLowerCase(Locale.ROOT),
                passwords.encode(input.password())));
    for (String role : input.roles())
      db.update(
          "INSERT INTO usuario_rol(id_usuario,id_rol) SELECT ?,id_rol FROM rol WHERE nombre=?",
          id,
          role);
    if (input.roles().contains("CLIENTE"))
      db.update(
          "INSERT INTO cliente(id_usuario,documento,licencia_conduccion) VALUES(?,?,?)",
          id,
          input.documento(),
          input.licencia());
    audit.record("USUARIO_CREADO", access.actor(auth), id, "OK");
    return Map.of("id", id, "message", "Usuario creado");
  }

  @PutMapping("/{id}")
  @Transactional
  public Map<String, Object> permissions(
      JwtAuthenticationToken auth, @PathVariable long id, @Valid @RequestBody Permissions input) {
    db.execute("SELECT pg_advisory_xact_lock(8945021)");
    if (db.queryForList("SELECT id_usuario FROM usuario WHERE id_usuario=? FOR UPDATE", id)
        .isEmpty()) throw ApiException.missing();
    if (!input.activo() || !input.roles().contains("ADMIN")) {
      long remaining =
          Objects.requireNonNull(
              db.queryForObject(
                  "SELECT count(*) FROM usuario u JOIN usuario_rol ur USING(id_usuario) JOIN rol r"
                      + " USING(id_rol) WHERE u.activo AND r.nombre='ADMIN' AND u.id_usuario<>?",
                  Long.class,
                  id));
      if (remaining == 0)
        throw new ApiException(HttpStatus.CONFLICT, "Debe conservar un administrador activo");
    }
    if (input.roles().contains("CLIENTE")
        && !Boolean.TRUE.equals(
            db.queryForObject(
                "SELECT EXISTS(SELECT 1 FROM cliente WHERE id_usuario=?)", Boolean.class, id)))
      throw new ApiException(
          HttpStatus.CONFLICT,
          "La cuenta necesita un perfil de cliente; créela con documento y licencia");
    db.update(
        "UPDATE usuario SET activo=?,token_version=token_version+1 WHERE id_usuario=?",
        input.activo(),
        id);
    db.update("DELETE FROM usuario_rol WHERE id_usuario=?", id);
    for (String role : input.roles())
      db.update(
          "INSERT INTO usuario_rol(id_usuario,id_rol) SELECT ?,id_rol FROM rol WHERE nombre=?",
          id,
          role);
    audit.record("PERMISOS_ACTUALIZADOS", access.actor(auth), id, "OK");
    return Map.of("message", "Permisos guardados; las sesiones anteriores fueron revocadas");
  }
}
