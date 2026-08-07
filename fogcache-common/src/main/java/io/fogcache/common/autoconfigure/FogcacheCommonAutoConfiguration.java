package io.fogcache.common.autoconfigure;

import io.fogcache.common.web.CorrelationIdWebFilter;
import org.springframework.boot.autoconfigure.AutoConfiguration;
import org.springframework.boot.autoconfigure.condition.ConditionalOnMissingBean;
import org.springframework.boot.autoconfigure.condition.ConditionalOnWebApplication;
import org.springframework.boot.autoconfigure.condition.ConditionalOnWebApplication.Type;
import org.springframework.context.annotation.Bean;

/**
 * Auto-configuration for shared FogCache web concerns. Services only need the {@code
 * fogcache-common} dependency; no component scanning is required.
 */
@AutoConfiguration
@ConditionalOnWebApplication(type = Type.REACTIVE)
public class FogcacheCommonAutoConfiguration {

  @Bean
  @ConditionalOnMissingBean
  public CorrelationIdWebFilter correlationIdWebFilter() {
    return new CorrelationIdWebFilter();
  }
}
