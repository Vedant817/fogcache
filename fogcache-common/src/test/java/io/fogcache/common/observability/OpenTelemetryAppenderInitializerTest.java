package io.fogcache.common.observability;

import static org.assertj.core.api.Assertions.assertThatCode;

import io.opentelemetry.api.OpenTelemetry;
import org.junit.jupiter.api.Test;

class OpenTelemetryAppenderInitializerTest {

  @Test
  void installsOpenTelemetryIntoAppender() {
    OpenTelemetryAppenderInitializer initializer =
        new OpenTelemetryAppenderInitializer(OpenTelemetry.noop());

    assertThatCode(initializer::afterPropertiesSet).doesNotThrowAnyException();
  }
}
