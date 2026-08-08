package io.fogcache.common.observability;

import io.opentelemetry.api.OpenTelemetry;
import io.opentelemetry.instrumentation.logback.appender.v1_0.OpenTelemetryAppender;
import org.springframework.beans.factory.InitializingBean;

/**
 * Hands the application's {@link OpenTelemetry} instance to the Logback appender so log records
 * emitted through {@code logback-spring.xml}'s {@code OTEL} appender reach the OTel log pipeline.
 *
 * <p>Spring Boot configures the log export pipeline ({@code SdkLoggerProvider} and its OTLP
 * exporter) but deliberately does not install the Logback appender itself; the OpenTelemetry
 * instance must be registered programmatically at startup, which this class does.
 */
public class OpenTelemetryAppenderInitializer implements InitializingBean {

  private final OpenTelemetry openTelemetry;

  public OpenTelemetryAppenderInitializer(OpenTelemetry openTelemetry) {
    this.openTelemetry = openTelemetry;
  }

  @Override
  public void afterPropertiesSet() {
    OpenTelemetryAppender.install(this.openTelemetry);
  }
}
