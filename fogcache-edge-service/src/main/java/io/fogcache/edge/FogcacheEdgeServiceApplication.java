package io.fogcache.edge;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/** Entry point for the FogCache edge service. */
@SpringBootApplication
public class FogcacheEdgeServiceApplication {

  /** Runs the application. */
  public static void main(String[] args) {
    SpringApplication.run(FogcacheEdgeServiceApplication.class, args);
  }
}
