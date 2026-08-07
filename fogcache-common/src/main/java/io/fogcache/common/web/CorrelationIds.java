package io.fogcache.common.web;

import reactor.util.context.ContextView;

/**
 * Names and context plumbing for the correlation ID that travels with every request through the
 * FogCache data path (see technical-design.md "Tracing" and security/threat-model.md T-09).
 *
 * <p>Handlers read the value from the Reactor context via {@link #fromContext(ContextView)};
 * because the value is carried in the Reactor context rather than a thread-local, it survives
 * thread hops in the reactive pipeline.
 */
public final class CorrelationIds {

  /** Header name used on both request and response. */
  public static final String HEADER = "X-Correlation-Id";

  /** Reactor context key under which the correlation ID is published. */
  public static final String CONTEXT_KEY = "io.fogcache.correlationId";

  /** Placeholder returned when no correlation ID is present in the context. */
  public static final String UNKNOWN = "unknown";

  private CorrelationIds() {}

  /**
   * Reads the correlation ID from the given Reactor context view, falling back to {@link #UNKNOWN}
   * when absent.
   */
  public static String fromContext(ContextView context) {
    return context.getOrDefault(CONTEXT_KEY, UNKNOWN);
  }
}
