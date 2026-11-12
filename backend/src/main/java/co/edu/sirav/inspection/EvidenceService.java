package co.edu.sirav.inspection;

import co.edu.sirav.common.ApiException;
import java.io.*;
import java.nio.file.*;
import java.util.*;
import javax.imageio.ImageIO;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

/** Las imágenes viven en archivos; PostgreSQL y MongoDB guardan solo referencias. */
@Service
public class EvidenceService {
  private final Path root;

  public EvidenceService(
      @Value("${sirav.evidence-directory:.runtime/evidencias}") String directory) {
    root = Path.of(directory).toAbsolutePath().normalize();
  }

  public String save(long reservation, MultipartFile file) {
    if (file.isEmpty() || file.getSize() > 5 * 1024 * 1024)
      throw new ApiException(HttpStatus.BAD_REQUEST, "Adjunte una imagen PNG o JPEG de hasta 5 MB");
    try {
      byte[] bytes = file.getBytes();
      String extension;
      if (bytes.length > 8
          && bytes[0] == (byte) 137
          && bytes[1] == 80
          && bytes[2] == 78
          && bytes[3] == 71) extension = "png";
      else if (bytes.length > 3
          && bytes[0] == (byte) 255
          && bytes[1] == (byte) 216
          && bytes[2] == (byte) 255) extension = "jpg";
      else throw new ApiException(HttpStatus.BAD_REQUEST, "El archivo debe ser PNG o JPEG");
      var image = ImageIO.read(new ByteArrayInputStream(bytes));
      if (image == null || (long) image.getWidth() * image.getHeight() > 20_000_000)
        throw new ApiException(
            HttpStatus.BAD_REQUEST, "La imagen no es válida o es demasiado grande");
      String name = UUID.randomUUID() + "." + extension;
      Path directory = root.resolve(Long.toString(reservation));
      Files.createDirectories(directory);
      Files.write(directory.resolve(name), bytes, StandardOpenOption.CREATE_NEW);
      return "/api/reservations/" + reservation + "/evidence/" + name;
    } catch (IOException e) {
      throw new ApiException(HttpStatus.SERVICE_UNAVAILABLE, "No fue posible guardar la evidencia");
    }
  }

  public Path file(long reservation, String name) {
    if (!name.matches("[a-f0-9-]{36}\\.(png|jpg)")) throw ApiException.missing();
    Path file = root.resolve(Long.toString(reservation)).resolve(name).normalize();
    if (!file.startsWith(root) || !Files.isRegularFile(file)) throw ApiException.missing();
    return file;
  }

  public void validate(long reservation, List<String> references) {
    String prefix = "/api/reservations/" + reservation + "/evidence/";
    for (String ref : references) {
      if (!ref.startsWith(prefix))
        throw new ApiException(
            HttpStatus.BAD_REQUEST, "Adjunte las evidencias a esta reserva desde el formulario");
      try {
        file(reservation, ref.substring(prefix.length()));
      } catch (ApiException e) {
        throw new ApiException(
            HttpStatus.BAD_REQUEST, "Una evidencia no está disponible; vuelva a adjuntarla");
      }
    }
  }
}
