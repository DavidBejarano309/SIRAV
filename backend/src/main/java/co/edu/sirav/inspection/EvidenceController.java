package co.edu.sirav.inspection;

import co.edu.sirav.security.Access;
import java.util.*;
import org.springframework.core.io.*;
import org.springframework.http.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

@RestController
@RequestMapping("/api")
public class EvidenceController {
  private final EvidenceService evidence;
  private final Access access;
  private final JdbcTemplate db;

  public EvidenceController(EvidenceService evidence, Access access, JdbcTemplate db) {
    this.evidence = evidence;
    this.access = access;
    this.db = db;
  }

  @PostMapping(
      value = "/reservations/{id}/evidence",
      consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
  @ResponseStatus(org.springframework.http.HttpStatus.CREATED)
  @PreAuthorize("hasAnyRole('ADMIN','OPERADOR')")
  public Map<String, String> upload(
      JwtAuthenticationToken auth, @PathVariable long id, @RequestParam MultipartFile file) {
    access.reservation(auth, id);
    return Map.of("referencia", evidence.save(id, file));
  }

  @PostMapping(value = "/rentals/{id}/evidence", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
  @ResponseStatus(org.springframework.http.HttpStatus.CREATED)
  @PreAuthorize("hasAnyRole('ADMIN','OPERADOR')")
  public Map<String, String> uploadForRental(
      JwtAuthenticationToken auth, @PathVariable long id, @RequestParam MultipartFile file) {
    access.rental(auth, id);
    long reservation =
        Objects.requireNonNull(
            db.queryForObject(
                "SELECT id_reserva FROM alquiler WHERE id_alquiler=?", Long.class, id));
    return Map.of("referencia", evidence.save(reservation, file));
  }

  @GetMapping("/reservations/{id}/evidence/{name}")
  public ResponseEntity<Resource> download(
      JwtAuthenticationToken auth, @PathVariable long id, @PathVariable String name) {
    access.reservation(auth, id);
    var path = evidence.file(id, name);
    return ResponseEntity.ok()
        .contentType(name.endsWith(".png") ? MediaType.IMAGE_PNG : MediaType.IMAGE_JPEG)
        .header(HttpHeaders.CONTENT_DISPOSITION, "inline; filename=\"" + name + "\"")
        .header("X-Content-Type-Options", "nosniff")
        .body(new FileSystemResource(path));
  }
}
