package io.fogcache.edge;

import org.springframework.boot.SpringApplication;

public class TestFogcacheEdgeServiceApplication {

	public static void main(String[] args) {
		SpringApplication.from(FogcacheEdgeServiceApplication::main).with(TestcontainersConfiguration.class).run(args);
	}

}
