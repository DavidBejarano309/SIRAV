package co.edu.sirav.common;

import java.sql.SQLException;
import java.util.stream.Collectors;
import org.slf4j.*;
import org.springframework.dao.*;
import org.springframework.http.*;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.*;

@RestControllerAdvice
public class ApiErrors {
  private static final Logger log = LoggerFactory.getLogger(ApiErrors.class);

  @ExceptionHandler(ApiException.class)
  ProblemDetail api(ApiException e) {
    return ProblemDetail.forStatusAndDetail(e.status(), e.getMessage());
  }

  @ExceptionHandler(AccessDeniedException.class)
  ProblemDetail denied() {
    return ProblemDetail.forStatusAndDetail(
        HttpStatus.FORBIDDEN, "No tiene permiso para esta operación");
  }

  @ExceptionHandler(MethodArgumentNotValidException.class)
  ProblemDetail validation(MethodArgumentNotValidException e) {
    return ProblemDetail.forStatusAndDetail(
        HttpStatus.BAD_REQUEST,
        e.getBindingResult().getFieldErrors().stream()
            .map(x -> x.getField() + ": " + x.getDefaultMessage())
            .distinct()
            .collect(Collectors.joining("; ")));
  }

  @ExceptionHandler({
    IllegalArgumentException.class,
    org.springframework.http.converter.HttpMessageNotReadableException.class,
    org.springframework.web.method.annotation.MethodArgumentTypeMismatchException.class
  })
  ProblemDetail invalid(Exception e) {
    return ProblemDetail.forStatusAndDetail(
        HttpStatus.BAD_REQUEST, "Revise el formato y los valores enviados");
  }

  @ExceptionHandler(DataAccessException.class)
  ProblemDetail database(DataAccessException e) {
    Throwable cause = e.getMostSpecificCause();
    if (cause instanceof SQLException sql) {
      String state = sql.getSQLState();
      if ("P0001".equals(state))
        return ProblemDetail.forStatusAndDetail(
            HttpStatus.CONFLICT, sql.getMessage().split("\n")[0].replace("ERROR: ", ""));
      if (state != null && state.startsWith("23"))
        return ProblemDetail.forStatusAndDetail(
            HttpStatus.CONFLICT,
            "Los datos están duplicados, son incompatibles o tienen relaciones pendientes");
    }
    log.error("event=database_error type={}", e.getClass().getSimpleName());
    return ProblemDetail.forStatusAndDetail(
        HttpStatus.SERVICE_UNAVAILABLE, "No fue posible acceder a los datos. Intente de nuevo");
  }

  @ExceptionHandler(com.mongodb.MongoException.class)
  ProblemDetail mongo(com.mongodb.MongoException e) {
    log.warn("event=mongo_error type={}", e.getClass().getSimpleName());
    return ProblemDetail.forStatusAndDetail(
        HttpStatus.SERVICE_UNAVAILABLE, "Las inspecciones no están disponibles. Intente de nuevo");
  }
}
