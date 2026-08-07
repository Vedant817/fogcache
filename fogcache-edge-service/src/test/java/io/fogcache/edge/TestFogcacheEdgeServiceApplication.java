package io.fogcache.edge;

import org.springframework.boot.SpringApplication;

/** Test bootstrap that attaches the Testcontainers configuration. */
public class TestFogcacheEdgeServiceApplication {

  /** Runs the application with the Testcontainers configuration attached. */
  public static void main(String[] args) {
    SpringApplication.from(FogcacheEdgeServiceApplication::main)
        .with(TestcontainersConfiguration.class)
        .run(args);
  }
}
