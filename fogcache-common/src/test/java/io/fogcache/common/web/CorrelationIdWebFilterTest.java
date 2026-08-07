package io.fogcache.common.web;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.ApplicationContext;
import org.springframework.test.web.reactive.server.WebTestClient;
import org.springframework.test.web.reactive.server.WebTestClient.ResponseSpec;

@SpringBootTest
class CorrelationIdWebFilterTest {

  @Autowired private ApplicationContext applicationContext;

  private WebTestClient webTestClient;

  @BeforeEach
  void setUp() {
    webTestClient = WebTestClient.bindToApplicationContext(applicationContext).build();
  }

  @Test
  void echoesClientSuppliedCorrelationId() {
    webTestClient
        .get()
        .uri("/ping")
        .header(CorrelationIds.HEADER, "client-supplied-id")
        .exchange()
        .expectStatus()
        .isOk()
        .expectHeader()
        .valueEquals(CorrelationIds.HEADER, "client-supplied-id");
  }

  @Test
  void generatesCorrelationIdWhenAbsent() {
    webTestClient
        .get()
        .uri("/ping")
        .exchange()
        .expectStatus()
        .isOk()
        .expectHeader()
        .valueMatches(CorrelationIds.HEADER, ".+");
  }

  @Test
  void generatesUniqueCorrelationIdPerRequest() {
    String first = correlationIdFrom(webTestClient.get().uri("/ping").exchange());
    String second = correlationIdFrom(webTestClient.get().uri("/ping").exchange());

    assertThat(first).isNotEqualTo(second);
  }

  @Test
  void exposesCorrelationIdToHandlersViaReactorContext() {
    webTestClient
        .get()
        .uri("/echo-correlation-id")
        .header(CorrelationIds.HEADER, "context-bound-id")
        .exchange()
        .expectStatus()
        .isOk()
        .expectBody(String.class)
        .isEqualTo("context-bound-id");
  }

  private static String correlationIdFrom(ResponseSpec exchange) {
    exchange.expectStatus().isOk();
    return exchange.returnResult(String.class).getResponseHeaders().getFirst(CorrelationIds.HEADER);
  }
}
