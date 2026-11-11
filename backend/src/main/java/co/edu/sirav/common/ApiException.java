package co.edu.sirav.common;

import org.springframework.http.HttpStatus;

public class ApiException extends RuntimeException {
  private final HttpStatus status;

  public ApiException(HttpStatus status, String message) {
    super(message);
    this.status = status;
  }

  public HttpStatus status() {
    return status;
  }

  public static ApiException missing() {
    return new ApiException(HttpStatus.NOT_FOUND, "Registro no encontrado");
  }

  public static ApiException forbidden() {
    return new ApiException(HttpStatus.FORBIDDEN, "No tiene permiso para esta operación");
  }
}
