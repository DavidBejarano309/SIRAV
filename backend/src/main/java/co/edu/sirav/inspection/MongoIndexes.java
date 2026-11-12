package co.edu.sirav.inspection;

import org.springframework.boot.CommandLineRunner;
import org.springframework.data.domain.Sort;
import org.springframework.data.mongodb.core.MongoTemplate;
import org.springframework.data.mongodb.core.index.Index;
import org.springframework.stereotype.Component;

@Component
public class MongoIndexes implements CommandLineRunner {
  private final MongoTemplate mongo;

  public MongoIndexes(MongoTemplate mongo) {
    this.mongo = mongo;
  }

  @Override
  public void run(String... args) {
    var indexes = mongo.indexOps("inspecciones_vehiculo");
    indexes.createIndex(
        new Index().on("alquilerId", Sort.Direction.ASC).on("tipo", Sort.Direction.ASC).unique());
    indexes.createIndex(
        new Index().on("vehiculoId", Sort.Direction.ASC).on("fecha", Sort.Direction.DESC));
    indexes.createIndex(
        new Index().on("danos.severidad", Sort.Direction.ASC).on("fecha", Sort.Direction.DESC));
    mongo
        .indexOps("bitacora_operaciones")
        .createIndex(new Index().on("fecha", Sort.Direction.DESC));
  }
}
