# Multi-stage build for every FogCache service.
#
#   docker build --build-arg MODULE=fogcache-routing-service -t fogcache-routing-service:local .
#
# The runtime image is a plain JRE; the app jar is the only payload.

ARG JAVA_BASE=eclipse-temurin:21

FROM ${JAVA_BASE}-jdk-alpine AS build
ARG MODULE
WORKDIR /workspace
COPY . .
RUN --mount=type=cache,target=/root/.m2 \
    ./mvnw -B -ntp -pl ${MODULE} -am package -DskipTests \
        -Dspotless.check.skip=true -Dcheckstyle.skip=true \
        -Dspotbugs.skip=true -Djacoco.skip=true

FROM ${JAVA_BASE}-jre-alpine AS runtime
ARG MODULE
RUN addgroup -S fogcache && adduser -S fogcache -G fogcache
WORKDIR /app
COPY --from=build /workspace/${MODULE}/target/${MODULE}-*.jar /app/app.jar
USER fogcache
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
