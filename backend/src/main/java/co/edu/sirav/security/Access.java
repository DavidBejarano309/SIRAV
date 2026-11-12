package co.edu.sirav.security;

import co.edu.sirav.common.ApiException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.stereotype.Component;

@Component
public class Access {
  private final JdbcTemplate db;

  public Access(JdbcTemplate db) {
    this.db = db;
  }

  public long actor(JwtAuthenticationToken auth) {
    return Long.parseLong(auth.getName());
  }

  public boolean staff(JwtAuthenticationToken auth) {
    return auth.getAuthorities().stream()
        .anyMatch(
            a -> a.getAuthority().equals("ROLE_ADMIN") || a.getAuthority().equals("ROLE_OPERADOR"));
  }

  public long client(JwtAuthenticationToken auth) {
    var ids =
        db.queryForList(
            "SELECT id_cliente FROM cliente WHERE id_usuario=?", Long.class, actor(auth));
    if (ids.isEmpty()) throw ApiException.forbidden();
    return ids.getFirst();
  }

  public void reservation(JwtAuthenticationToken auth, long id) {
    var ids =
        db.queryForList(
            "SELECT c.id_usuario FROM reserva r JOIN cliente c USING(id_cliente) WHERE"
                + " r.id_reserva=?",
            Long.class,
            id);
    if (ids.isEmpty()) throw ApiException.missing();
    if (!staff(auth) && !Long.valueOf(actor(auth)).equals(ids.getFirst()))
      throw ApiException.forbidden();
  }

  public void rental(JwtAuthenticationToken auth, long id) {
    var ids =
        db.queryForList("SELECT id_reserva FROM alquiler WHERE id_alquiler=?", Long.class, id);
    if (ids.isEmpty()) throw ApiException.missing();
    reservation(auth, ids.getFirst());
  }
}
