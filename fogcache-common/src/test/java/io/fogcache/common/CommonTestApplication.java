package io.fogcache.common;

import static org.springframework.web.reactive.function.server.RequestPredicates.GET;
import static org.springframework.web.reactive.function.server.RouterFunctions.route;

import io.fogcache.common.web.CorrelationIds;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.Bean;
import org.springframework.web.reactive.function.server.RouterFunction;
import org.springframework.web.reactive.function.server.ServerResponse;
import reactor.core.publisher.Mono;

/**
 * Minimal reactive application used by fogcache-common tests to exercise the auto-configured web
 * filters end to end.
 */
@SpringBootApplication
public class CommonTestApplication {

  public static void main(String[] args) {
    SpringApplication.run(CommonTestApplication.class, args);
  }

  @Bean
  RouterFunction<ServerResponse> testRoutes() {
    return route(GET("/ping"), request -> ServerResponse.ok().bodyValue("pong"))
        .andRoute(
            GET("/echo-correlation-id"),
            request ->
                Mono.deferContextual(
                    context -> ServerResponse.ok().bodyValue(CorrelationIds.fromContext(context))));
  }
}
