package co.edu.sirav.security;

import co.edu.sirav.common.ApiException;
import jakarta.validation.constraints.*;
import java.time.Instant;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;
import org.slf4j.*;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.oauth2.jose.jws.MacAlgorithm;
import org.springframework.security.oauth2.jwt.*;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class AuthService {
  public record Login(@Email @NotBlank String email, @NotBlank @Size(max = 100) String password) {}

  public record Register(
      @NotBlank @Size(max = 100) String nombre,
      @NotBlank @Size(max = 100) String apellido,
      @Email @NotBlank @Size(max = 150) String email,
      @Size(min = 10, max = 72) @NotBlank String password,
      @NotBlank @Size(max = 30) String documento,
      @NotBlank @Size(max = 40) String licencia,
      @Size(max = 25) String telefono) {}

  private record Attempt(long minute, int count) {}

  private static final Logger log = LoggerFactory.getLogger(AuthService.class);
  private final JdbcTemplate db;
  private final PasswordEncoder passwords;
  private final JwtEncoder encoder;
  private final Map<String, Attempt> attempts = new ConcurrentHashMap<>();
  private final long minutes;

  public AuthService(
      JdbcTemplate db,
      PasswordEncoder passwords,
      JwtEncoder encoder,
      @Value("${sirav.token-minutes}") long minutes) {
    this.db = db;
    this.passwords = passwords;
    this.encoder = encoder;
    this.minutes = minutes;
  }

  public Map<String, Object> login(Login input, String address) {
    long minute = Instant.now().getEpochSecond() / 60;
    attempts.entrySet().removeIf(e -> e.getValue().minute() < minute - 1);
    Attempt attempt =
        attempts.compute(
            address,
            (k, v) -> new Attempt(minute, v == null || v.minute() != minute ? 1 : v.count() + 1));
    if (attempt.count() > 15)
      throw new ApiException(HttpStatus.TOO_MANY_REQUESTS, "Demasiados intentos. Espere un minuto");
    var users =
        db.queryForList(
            "SELECT * FROM usuario WHERE email=?", input.email().trim().toLowerCase(Locale.ROOT));
    if (users.isEmpty()
        || !Boolean.TRUE.equals(users.getFirst().get("activo"))
        || !passwords.matches(input.password(), (String) users.getFirst().get("password_hash"))) {
      log.info("event=login outcome=rejected");
      throw new ApiException(HttpStatus.UNAUTHORIZED, "Correo o contraseña incorrectos");
    }
    var user = users.getFirst();
    long id = ((Number) user.get("id_usuario")).longValue();
    var roles = roles(id);
    var now = Instant.now();
    var claims =
        JwtClaimsSet.builder()
            .issuer("sirav")
            .subject(Long.toString(id))
            .issuedAt(now)
            .expiresAt(now.plusSeconds(minutes * 60))
            .claim("roles", roles)
            .claim("ver", user.get("token_version"))
            .build();
    String token =
        encoder
            .encode(JwtEncoderParameters.from(JwsHeader.with(MacAlgorithm.HS256).build(), claims))
            .getTokenValue();
    log.info("event=login actor={} outcome=success", id);
    return Map.of("token", token, "expiresIn", minutes * 60, "user", me(id));
  }

  @Transactional
  public Map<String, Object> register(Register input) {
    if (input.password().getBytes(java.nio.charset.StandardCharsets.UTF_8).length > 72)
      throw new IllegalArgumentException("La contraseña supera 72 bytes");
    long id =
        Objects.requireNonNull(
            db.queryForObject(
                "INSERT INTO usuario(nombre,apellido,email,password_hash,activo)"
                    + " VALUES(?,?,?,?,true) RETURNING id_usuario",
                Long.class,
                input.nombre().trim(),
                input.apellido().trim(),
                input.email().trim().toLowerCase(Locale.ROOT),
                passwords.encode(input.password())));
    db.update(
        "INSERT INTO usuario_rol(id_usuario,id_rol) SELECT ?,id_rol FROM rol WHERE"
            + " nombre='CLIENTE'",
        id);
    db.update(
        "INSERT INTO cliente(id_usuario,documento,telefono,licencia_conduccion) VALUES(?,?,?,?)",
        id,
        input.documento().trim(),
        input.telefono(),
        input.licencia());
    return Map.of("id", id, "message", "Cuenta creada. Ya puede iniciar sesión");
  }

  public List<String> roles(long id) {
    return db.queryForList(
        "SELECT r.nombre FROM rol r JOIN usuario_rol ur USING(id_rol) WHERE ur.id_usuario=? ORDER"
            + " BY r.nombre",
        String.class,
        id);
  }

  public Map<String, Object> me(long id) {
    var user =
        db.queryForMap(
            "SELECT"
                + " u.id_usuario,u.nombre,u.apellido,u.email,u.activo,c.id_cliente,c.documento,c.telefono,c.licencia_conduccion"
                + " FROM usuario u LEFT JOIN cliente c USING(id_usuario) WHERE u.id_usuario=?",
            id);
    user.put("roles", roles(id));
    return user;
  }

  public void logout(long id) {
    db.update("UPDATE usuario SET token_version=token_version+1 WHERE id_usuario=?", id);
  }
}
