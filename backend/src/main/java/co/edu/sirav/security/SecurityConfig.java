package co.edu.sirav.security;

import com.nimbusds.jose.jwk.source.ImmutableSecret;
import java.nio.charset.StandardCharsets;
import java.util.List;
import javax.crypto.spec.SecretKeySpec;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.config.annotation.method.configuration.EnableMethodSecurity;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.oauth2.core.*;
import org.springframework.security.oauth2.jose.jws.MacAlgorithm;
import org.springframework.security.oauth2.jwt.*;
import org.springframework.security.oauth2.server.resource.authentication.*;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.web.cors.*;

@Configuration
@EnableMethodSecurity
public class SecurityConfig {
  @Bean
  PasswordEncoder passwordEncoder() {
    return new BCryptPasswordEncoder(12);
  }

  @Bean
  JwtEncoder jwtEncoder(@Value("${sirav.jwt-secret}") String secret) {
    checkSecret(secret);
    return new NimbusJwtEncoder(new ImmutableSecret<>(secret.getBytes(StandardCharsets.UTF_8)));
  }

  @Bean
  JwtDecoder jwtDecoder(@Value("${sirav.jwt-secret}") String secret, JdbcTemplate db) {
    checkSecret(secret);
    var decoder =
        NimbusJwtDecoder.withSecretKey(
                new SecretKeySpec(secret.getBytes(StandardCharsets.UTF_8), "HmacSHA256"))
            .macAlgorithm(MacAlgorithm.HS256)
            .build();
    OAuth2TokenValidator<Jwt> account =
        jwt -> {
          try {
            var count =
                db.queryForObject(
                    "SELECT count(*) FROM usuario WHERE id_usuario=? AND activo=true AND"
                        + " token_version=?",
                    Long.class,
                    Long.parseLong(jwt.getSubject()),
                    jwt.getClaim("ver"));
            if (count != null && count == 1) return OAuth2TokenValidatorResult.success();
          } catch (NumberFormatException ignored) {
            /* invalid subject */
          }
          return OAuth2TokenValidatorResult.failure(
              new OAuth2Error("invalid_token", "Cuenta inactiva o sesión revocada", null));
        };
    decoder.setJwtValidator(
        new DelegatingOAuth2TokenValidator<>(
            JwtValidators.createDefaultWithIssuer("sirav"), account));
    return decoder;
  }

  private void checkSecret(String secret) {
    if (secret.getBytes(StandardCharsets.UTF_8).length < 32)
      throw new IllegalArgumentException("JWT_SECRET debe contener al menos 32 bytes");
  }

  @Bean
  SecurityFilterChain filterChain(HttpSecurity http, @Value("${sirav.cors-origin}") String origin)
      throws Exception {
    var roles = new JwtGrantedAuthoritiesConverter();
    roles.setAuthoritiesClaimName("roles");
    roles.setAuthorityPrefix("ROLE_");
    var converter = new JwtAuthenticationConverter();
    converter.setJwtGrantedAuthoritiesConverter(roles);
    var cors = new CorsConfiguration();
    cors.setAllowedOrigins(java.util.Arrays.stream(origin.split(",")).map(String::trim).toList());
    cors.setAllowedMethods(List.of("GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"));
    cors.setAllowedHeaders(List.of("Authorization", "Content-Type", "Idempotency-Key"));
    var source = new UrlBasedCorsConfigurationSource();
    source.registerCorsConfiguration("/**", cors);
    return http.cors(c -> c.configurationSource(source))
        .csrf(c -> c.disable())
        .sessionManagement(c -> c.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
        .authorizeHttpRequests(
            a ->
                a.requestMatchers(
                        "/api/auth/login",
                        "/api/auth/register",
                        "/actuator/health",
                        "/v3/api-docs/**",
                        "/swagger-ui/**",
                        "/swagger-ui.html")
                    .permitAll()
                    .anyRequest()
                    .authenticated())
        .oauth2ResourceServer(o -> o.jwt(j -> j.jwtAuthenticationConverter(converter)))
        .headers(h -> h.frameOptions(f -> f.deny()))
        .build();
  }
}
