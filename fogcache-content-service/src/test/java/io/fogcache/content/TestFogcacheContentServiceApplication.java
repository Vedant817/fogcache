package io.fogcache.content;

import org.springframework.boot.SpringApplication;

/** Test bootstrap that attaches the Testcontainers configuration. */
public class TestFogcacheContentServiceApplication {

  /** Runs the application with the Testcontainers configuration attached. */
  public static void main(String[] args) {
    SpringApplication.from(FogcacheContentServiceApplication::main)
        .with(TestcontainersConfiguration.class)
        .run(args);
  }
}
