package co.edu.sirav.security;

import java.util.Objects;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.CommandLineRunner;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

@Component
public class DemoSeed implements CommandLineRunner {
  private final JdbcTemplate db;
  private final PasswordEncoder encoder;
  private final boolean enabled;
  private final String password;

  public DemoSeed(
      JdbcTemplate db,
      PasswordEncoder encoder,
      @Value("${sirav.seed-demo}") boolean enabled,
      @Value("${sirav.demo-password}") String password) {
    this.db = db;
    this.encoder = encoder;
    this.enabled = enabled;
    this.password = password;
  }

  @Override
  @Transactional
  public void run(String... args) {
    if (!enabled) return;
    if (password.length() < 10 || password.length() > 72)
      throw new IllegalArgumentException("DEMO_PASSWORD requiere entre 10 y 72 caracteres");
    for (String role : new String[] {"ADMIN", "OPERADOR", "CLIENTE"}) {
      String email = role.toLowerCase() + "@sirav.local";
      if (Boolean.TRUE.equals(
          db.queryForObject(
              "SELECT EXISTS(SELECT 1 FROM usuario WHERE email=?)", Boolean.class, email)))
        continue;
      String nombre = role.substring(0, 1) + role.substring(1).toLowerCase();
      long id =
          Objects.requireNonNull(
              db.queryForObject(
                  "INSERT INTO usuario(nombre,apellido,email,password_hash,activo) VALUES(?,"
                      + " 'Demo',?,?,true) RETURNING id_usuario",
                  Long.class,
                  nombre,
                  email,
                  encoder.encode(password)));
      db.update(
          "INSERT INTO usuario_rol(id_usuario,id_rol) SELECT ?,id_rol FROM rol WHERE nombre=?",
          id,
          role);
      if (role.equals("CLIENTE"))
        db.update(
            "INSERT INTO cliente(id_usuario,documento,licencia_conduccion)"
                + " VALUES(?,'DEMO-001','DEMO-LIC-001')",
            id);
    }
  }
}
