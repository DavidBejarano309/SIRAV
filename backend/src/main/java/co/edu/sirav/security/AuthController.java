package co.edu.sirav.security;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/auth")
public class AuthController {
  private final AuthService auth;
  private final Access access;

  public AuthController(AuthService auth, Access access) {
    this.auth = auth;
    this.access = access;
  }

  @PostMapping("/login")
  @io.swagger.v3.oas.annotations.security.SecurityRequirements
  public Map<String, Object> login(
      @Valid @RequestBody AuthService.Login input, HttpServletRequest request) {
    return auth.login(input, request.getRemoteAddr());
  }

  @PostMapping("/register")
  @io.swagger.v3.oas.annotations.security.SecurityRequirements
  @ResponseStatus(HttpStatus.CREATED)
  public Map<String, Object> register(@Valid @RequestBody AuthService.Register input) {
    return auth.register(input);
  }

  @GetMapping("/me")
  public Map<String, Object> me(JwtAuthenticationToken principal) {
    return auth.me(access.actor(principal));
  }

  @PostMapping("/logout")
  @ResponseStatus(HttpStatus.NO_CONTENT)
  public void logout(JwtAuthenticationToken principal) {
    auth.logout(access.actor(principal));
  }

  @PutMapping("/me")
  public Map<String, Object> profile(
      JwtAuthenticationToken principal, @Valid @RequestBody AuthService.Profile input) {
    return auth.profile(access.actor(principal), input);
  }

  @PostMapping("/password")
  @ResponseStatus(HttpStatus.NO_CONTENT)
  public void password(
      JwtAuthenticationToken principal, @Valid @RequestBody AuthService.PasswordChange input) {
    auth.password(access.actor(principal), input);
  }
}
