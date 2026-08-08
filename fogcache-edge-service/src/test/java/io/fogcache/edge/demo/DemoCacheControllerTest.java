package io.fogcache.edge.demo;

import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.context.annotation.Bean;
import org.springframework.http.MediaType;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.ReactiveJwtDecoder;
import org.springframework.test.context.ContextConfiguration;
import org.springframework.test.web.reactive.server.WebTestClient;
import reactor.core.publisher.Mono;

/** Exercises the demo cache miss/hit semantics against the seed fixture checksums. */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@ContextConfiguration(classes = DemoCacheControllerTest.SecurityTestConfig.class)
class DemoCacheControllerTest {

  private static final String HELLO_SHA256 =
      "29d46da10f066712751a480ae70187382b39a4034d4d3986ab2921803b2c6f9f";

  @LocalServerPort private int port;

  private WebTestClient client;

  @BeforeEach
  void setUp() {
    client = WebTestClient.bindToServer().baseUrl("http://localhost:" + port).build();
  }

  @Test
  void anonymousRequestsAreRejected() {
    client.get().uri("/demo/cache/object-hello").exchange().expectStatus().isUnauthorized();
  }

  @Test
  void firstRequestIsMissSecondIsHit() {
    WebTestClient.ResponseSpec miss = fetch("object-hello");
    miss.expectStatus()
        .isOk()
        .expectHeader()
        .valueEquals("X-FogCache-Status", "miss")
        .expectHeader()
        .valueEquals("X-FogCache-Sha256", HELLO_SHA256)
        .expectBody()
        .equals("hello from fogcache seed fixture\n".getBytes(StandardCharsets.UTF_8));

    WebTestClient.ResponseSpec hit = fetch("object-hello");
    hit.expectStatus()
        .isOk()
        .expectHeader()
        .valueEquals("X-FogCache-Status", "hit")
        .expectHeader()
        .valueEquals("X-FogCache-Sha256", HELLO_SHA256)
        .expectBody()
        .equals("hello from fogcache seed fixture\n".getBytes(StandardCharsets.UTF_8));
  }

  @Test
  void binaryObjectChecksumMatchesSeedManifest() {
    fetch("object-image")
        .expectStatus()
        .isOk()
        .expectHeader()
        .valueEquals("X-FogCache-Status", "miss")
        .expectHeader()
        .valueEquals(
            "X-FogCache-Sha256",
            "95aee26e885f50bdff72c290077d9d3729a1fefdcaec02da7aaf6aec5036add9");
    fetch("object-image")
        .expectStatus()
        .isOk()
        .expectHeader()
        .valueEquals("X-FogCache-Status", "hit");
  }

  @Test
  void unknownObjectIsNotFound() {
    fetch("object-does-not-exist").expectStatus().isNotFound();
  }

  @Test
  void contentTypesAreServedAsDeclared() {
    fetch("object-config")
        .expectStatus()
        .isOk()
        .expectHeader()
        .contentTypeCompatibleWith(MediaType.APPLICATION_JSON);
  }

  private WebTestClient.ResponseSpec fetch(String uid) {
    return client
        .get()
        .uri("/demo/cache/{uid}", uid)
        .header("Authorization", "Bearer test-token")
        .exchange();
  }

  @TestConfiguration
  static class SecurityTestConfig {

    @Bean
    ReactiveJwtDecoder jwtDecoder() {
      return token ->
          Mono.just(
              Jwt.withTokenValue(token)
                  .header("alg", "none")
                  .subject("viewer")
                  .audience(List.of("fogcache"))
                  .claim("realm_access", Map.of("roles", List.of("viewer")))
                  .issuedAt(Instant.now())
                  .expiresAt(Instant.now().plusSeconds(300))
                  .build());
    }
  }
}
