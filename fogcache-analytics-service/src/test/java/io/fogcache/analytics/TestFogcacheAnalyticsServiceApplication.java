package io.fogcache.analytics;

import org.springframework.boot.SpringApplication;

/** Test bootstrap that attaches the Testcontainers configuration. */
public class TestFogcacheAnalyticsServiceApplication {

  /** Runs the application with the Testcontainers configuration attached. */
  public static void main(String[] args) {
    SpringApplication.from(FogcacheAnalyticsServiceApplication::main)
        .with(TestcontainersConfiguration.class)
        .run(args);
  }
}
