package io.fogcache.routing;

import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Condition;
import org.springframework.context.annotation.ConditionContext;
import org.springframework.context.annotation.Conditional;
import org.springframework.core.type.AnnotatedTypeMetadata;
import org.testcontainers.DockerClientFactory;
import org.testcontainers.grafana.LgtmStackContainer;
import org.testcontainers.utility.DockerImageName;

/**
 * Starts the Grafana OTLP/LGTM stack (metrics, traces, logs) for the context tests. The container
 * is only started when a working Docker daemon is available, so `mvn verify` stays green on
 * machines without Docker and the LGTM smoke test simply degrades to a plain context load.
 */
@TestConfiguration(proxyBeanMethods = false)
class TestcontainersConfiguration {

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
