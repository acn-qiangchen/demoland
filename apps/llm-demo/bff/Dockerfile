# ---- Build stage ----
FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /build

# Cache dependencies first
COPY pom.xml .
RUN mvn -q -B dependency:go-offline

# Build the fat jar
COPY src ./src
RUN mvn -q -B clean package -DskipTests

# ---- Runtime stage ----
FROM eclipse-temurin:17-jre AS runtime
WORKDIR /app

# Run as a non-root user (per CONTRIBUTING.md)
RUN groupadd --system app && useradd --system --gid app --home /app app
USER app

COPY --from=build /build/target/llm-demo-bff-*.jar /app/app.jar

EXPOSE 8081
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
