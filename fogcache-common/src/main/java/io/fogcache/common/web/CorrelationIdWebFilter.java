package io.fogcache.common.web;

import java.util.UUID;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.http.server.reactive.ServerHttpRequest;
import org.springframework.web.server.ServerWebExchange;
import org.springframework.web.server.WebFilter;
import org.springframework.web.server.WebFilterChain;
import reactor.core.publisher.Mono;

/**
 * WebFlux filter that resolves the correlation ID for the request, echoes it back on the response,
 * and publishes it into the Reactor context under {@link CorrelationIds#CONTEXT_KEY}.
 *
 * <p>An inbound {@code X-Correlation-Id} is honored when it is present, not blank, and at most
 * {@value #MAX_CORRELATION_ID_LENGTH} characters long; otherwise a fresh UUID is generated. This is
 * the first filter in the chain ({@link Ordered#HIGHEST_PRECEDENCE}) so downstream code can rely on
 * the context value.
 */
@Order(Ordered.HIGHEST_PRECEDENCE)
public final class CorrelationIdWebFilter implements WebFilter {

  static final int MAX_CORRELATION_ID_LENGTH = 64;

  @Override
  public Mono<Void> filter(ServerWebExchange exchange, WebFilterChain chain) {
    String correlationId = resolveCorrelationId(exchange.getRequest());
    exchange.getResponse().getHeaders().set(CorrelationIds.HEADER, correlationId);
    return chain
        .filter(exchange)
        .contextWrite(context -> context.put(CorrelationIds.CONTEXT_KEY, correlationId));
  }

  private static String resolveCorrelationId(ServerHttpRequest request) {
    String supplied = request.getHeaders().getFirst(CorrelationIds.HEADER);
    if (supplied != null && !supplied.isBlank() && supplied.length() <= MAX_CORRELATION_ID_LENGTH) {
      return supplied;
    }
    return UUID.randomUUID().toString();
  }
}
