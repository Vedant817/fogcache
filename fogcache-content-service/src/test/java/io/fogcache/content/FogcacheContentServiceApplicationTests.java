package io.fogcache.content;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;

@Import(TestcontainersConfiguration.class)
@SpringBootTest
class FogcacheContentServiceApplicationTests {

	@Test
	void contextLoads() {
	}

}
