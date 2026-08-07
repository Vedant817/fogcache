package io.fogcache.analytics;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/** Entry point for the FogCache analytics service. */
@SpringBootApplication
public class FogcacheAnalyticsServiceApplication {

  /** Runs the application. */
  public static void main(String[] args) {
    SpringApplication.run(FogcacheAnalyticsServiceApplication.class, args);
  }
}
