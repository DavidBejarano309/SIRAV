package co.edu.sirav.security;

import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;

import co.edu.sirav.common.ApiException;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;

class AccessTest {
  final JdbcTemplate db = mock(JdbcTemplate.class);
  final Access access = new Access(db);

  JwtAuthenticationToken auth(String role) {
    return new JwtAuthenticationToken(
        Jwt.withTokenValue("test").header("alg", "HS256").subject("7").build(),
        List.of(new SimpleGrantedAuthority("ROLE_" + role)));
  }

  @Test
  void customerCannotReadAnotherCustomersReservation() {
    when(db.queryForList(anyString(), eq(Long.class), eq(99L))).thenReturn(List.of(8L));
    assertThatThrownBy(() -> access.reservation(auth("CLIENTE"), 99))
        .isInstanceOf(ApiException.class)
        .hasMessageContaining("permiso");
  }

  @Test
  void operatorCanAccessCustomerReservation() {
    when(db.queryForList(anyString(), eq(Long.class), eq(99L))).thenReturn(List.of(8L));
    assertThatCode(() -> access.reservation(auth("OPERADOR"), 99)).doesNotThrowAnyException();
  }

  @Test
  void missingReservationDoesNotGrantAccess() {
    when(db.queryForList(anyString(), eq(Long.class), eq(99L))).thenReturn(List.of());
    assertThatThrownBy(() -> access.reservation(auth("ADMIN"), 99))
        .isInstanceOf(ApiException.class)
        .hasMessageContaining("no encontrado");
  }
}
