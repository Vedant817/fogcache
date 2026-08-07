package io.fogcache.routing;

import org.springframework.boot.SpringApplication;

/** Test bootstrap that attaches the Testcontainers configuration. */
public class TestFogcacheRoutingServiceApplication {

  /** Runs the application with the Testcontainers configuration attached. */
  public static void main(String[] args) {
    SpringApplication.from(FogcacheRoutingServiceApplication::main)
        .with(TestcontainersConfiguration.class)
        .run(args);
  }
}
