package io.fogcache.common.autoconfigure;

import io.fogcache.common.observability.OpenTelemetryAppenderInitializer;
import io.opentelemetry.api.OpenTelemetry;
import org.springframework.boot.autoconfigure.AutoConfiguration;
import org.springframework.boot.autoconfigure.condition.ConditionalOnBean;
import org.springframework.boot.autoconfigure.condition.ConditionalOnClass;
import org.springframework.boot.autoconfigure.condition.ConditionalOnMissingBean;
import org.springframework.context.annotation.Bean;

/**
 * Auto-configuration that registers the Logback OpenTelemetry appender with the application's
 * {@link OpenTelemetry} instance, whenever one is available.
 *
 * <p>Runs after Spring Boot's {@code OpenTelemetrySdkAutoConfiguration} (referenced by name to
 * avoid a hard dependency on {@code spring-boot-opentelemetry}) so the bean presence check below
 * sees the final decision. Unlike {@link FogcacheCommonAutoConfiguration} this is not limited to
 * reactive applications: the appender is equally relevant to servlet services.
 */
@AutoConfiguration(
    afterName =
        "org.springframework.boot.opentelemetry.autoconfigure.OpenTelemetrySdkAutoConfiguration")
@ConditionalOnClass(OpenTelemetry.class)
@ConditionalOnBean(OpenTelemetry.class)
public class FogcacheObservabilityAutoConfiguration {

  @Bean
  @ConditionalOnMissingBean
  public OpenTelemetryAppenderInitializer openTelemetryAppenderInitializer(
      OpenTelemetry openTelemetry) {
    return new OpenTelemetryAppenderInitializer(openTelemetry);
  }
}
