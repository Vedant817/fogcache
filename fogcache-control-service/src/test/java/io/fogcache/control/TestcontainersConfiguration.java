package io.fogcache.control;

import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Condition;
import org.springframework.context.annotation.ConditionContext;
import org.springframework.context.annotation.Conditional;
import org.springframework.core.type.AnnotatedTypeMetadata;
import org.testcontainers.DockerClientFactory;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.grafana.LgtmStackContainer;
import org.testcontainers.utility.DockerImageName;

/**
 * Starts the Postgres and Grafana OTLP/LGTM stack (metrics, traces, logs) for the context tests.
 * The containers are only started when a working Docker daemon is available, so `mvn verify` stays
 * green on machines without Docker and the smoke test simply skips.
 */
@TestConfiguration(proxyBeanMethods = false)
class TestcontainersConfiguration {

  @Bean
  @ServiceConnection
  @Conditional(DockerAvailableCondition.class)
  PostgreSQLContainer<?> postgresContainer() {
    return new PostgreSQLContainer<>(DockerImageName.parse("postgres:17"));
  }

  @Bean
  @ServiceConnection
  @Conditional(DockerAvailableCondition.class)
  LgtmStackContainer grafanaLgtmContainer() {
    return new LgtmStackContainer(DockerImageName.parse("grafana/otel-lgtm:latest"));
  }

  static final class DockerAvailableCondition implements Condition {

    @Override
    public boolean matches(ConditionContext context, AnnotatedTypeMetadata metadata) {
      return DockerClientFactory.instance().isDockerAvailable();
    }
  }
}
