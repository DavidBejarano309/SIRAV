package co.edu.sirav.report;

import co.edu.sirav.catalog.CatalogController;
import co.edu.sirav.common.ApiException;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/reports")
@PreAuthorize("hasAnyRole('ADMIN','OPERADOR')")
public class ReportController {
  private static final Set<String> REPORTS =
      Set.of("occupancy", "revenue", "ranking", "clients", "late", "availability");
  private final NamedParameterJdbcTemplate db;

  public ReportController(NamedParameterJdbcTemplate db) {
    this.db = db;
  }

  @GetMapping("/{type}")
  public List<Map<String, Object>> report(
      @PathVariable String type, @RequestParam LocalDate from, @RequestParam LocalDate to)
      throws IOException {
    CatalogController.dates(from, to);
    if (!REPORTS.contains(type)) throw ApiException.missing();
    String sql =
        new ClassPathResource("sql/reports/" + type + ".sql")
            .getContentAsString(StandardCharsets.UTF_8);
    return db.queryForList(sql, Map.of("from", from, "to", to));
  }
}
