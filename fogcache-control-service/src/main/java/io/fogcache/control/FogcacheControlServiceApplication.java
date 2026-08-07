package io.fogcache.control;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/** Entry point for the FogCache control service. */
@SpringBootApplication
public class FogcacheControlServiceApplication {

  /** Runs the application. */
  public static void main(String[] args) {
    SpringApplication.run(FogcacheControlServiceApplication.class, args);
  }
}
