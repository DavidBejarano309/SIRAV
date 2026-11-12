FROM maven:3.9.11-eclipse-temurin-21 AS build
WORKDIR /app
COPY pom.xml .
RUN mvn -B dependency:go-offline
COPY src src
RUN mvn -B verify
FROM eclipse-temurin:21-jre-alpine
RUN addgroup -S sirav && adduser -S sirav -G sirav && mkdir -p /app/evidencias && chown -R sirav:sirav /app
USER sirav
WORKDIR /app
COPY --from=build /app/target/sirav-api-1.0.0.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java","-jar","app.jar"]
