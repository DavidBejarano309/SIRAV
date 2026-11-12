package co.edu.sirav.inspection;

import java.time.Instant;
import java.util.Date;
import org.bson.Document;
import org.slf4j.*;
import org.springframework.data.mongodb.core.MongoTemplate;
import org.springframework.data.mongodb.core.query.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

@Component
public class OutboxPublisher {
  private static final Logger log = LoggerFactory.getLogger(OutboxPublisher.class);
  private final JdbcTemplate db;
  private final MongoTemplate mongo;

  public OutboxPublisher(JdbcTemplate db, MongoTemplate mongo) {
    this.db = db;
    this.mongo = mongo;
  }

  @Scheduled(
      fixedDelayString = "${sirav.outbox-delay:2000}",
      initialDelayString = "${sirav.outbox-initial-delay:0}")
  @Transactional
  public void publish() {
    var rows =
        db.queryForList(
            "SELECT * FROM evento_outbox WHERE publicado_en IS NULL ORDER BY creado_en LIMIT 50 FOR"
                + " UPDATE SKIP LOCKED");
    for (var row : rows) {
      try {
        String id = row.get("id").toString();
        String collection = row.get("coleccion").toString();
        if (!collection.equals("inspecciones_vehiculo")
            && !collection.equals("bitacora_operaciones"))
          throw new IllegalArgumentException("Colección inválida");
        var document = Document.parse(row.get("documento").toString());
        document.put("fecha", Date.from(Instant.parse(document.getString("fecha"))));
        var update = new Update();
        document.forEach(update::setOnInsert);
        mongo.upsert(Query.query(Criteria.where("_id").is(id)), update, collection);
        db.update(
            "UPDATE evento_outbox SET publicado_en=now(),intentos=intentos+1 WHERE id=?",
            row.get("id"));
      } catch (Exception e) {
        db.update("UPDATE evento_outbox SET intentos=intentos+1 WHERE id=?", row.get("id"));
        log.warn("event=outbox_retry id={} type={}", row.get("id"), e.getClass().getSimpleName());
        break; // evita saturar el motor cuando no está disponible
      }
    }
  }
}
