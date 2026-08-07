package io.fogcache.content;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/** Entry point for the FogCache content service. */
@SpringBootApplication
public class FogcacheContentServiceApplication {

  /** Runs the application. */
  public static void main(String[] args) {
    SpringApplication.run(FogcacheContentServiceApplication.class, args);
  }
}
