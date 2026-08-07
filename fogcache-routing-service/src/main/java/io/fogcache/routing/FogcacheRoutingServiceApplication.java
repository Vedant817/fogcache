package io.fogcache.routing;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/** Entry point for the FogCache routing service. */
@SpringBootApplication
public class FogcacheRoutingServiceApplication {

  /** Runs the application. */
  public static void main(String[] args) {
    SpringApplication.run(FogcacheRoutingServiceApplication.class, args);
  }
}
