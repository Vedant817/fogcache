package io.fogcache.control;

import org.springframework.boot.SpringApplication;

/** Test bootstrap that attaches the Testcontainers configuration. */
public class TestFogcacheControlServiceApplication {

  /** Runs the application with the Testcontainers configuration attached. */
  public static void main(String[] args) {
    SpringApplication.from(FogcacheControlServiceApplication::main)
        .with(TestcontainersConfiguration.class)
        .run(args);
  }
}
