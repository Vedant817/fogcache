package io.fogcache.content;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIf;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.testcontainers.DockerClientFactory;

@Import(TestcontainersConfiguration.class)
@SpringBootTest
@EnabledIf("dockerAvailable")
class FogcacheContentServiceApplicationTests {

  static boolean dockerAvailable() {
    return DockerClientFactory.instance().isDockerAvailable();
  }

  @Test
  void contextLoads() {}
}
