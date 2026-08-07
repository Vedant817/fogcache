package io.fogcache.routing;

import org.springframework.boot.SpringApplication;

public class TestFogcacheRoutingServiceApplication {

	public static void main(String[] args) {
		SpringApplication.from(FogcacheRoutingServiceApplication::main).with(TestcontainersConfiguration.class).run(args);
	}

}
