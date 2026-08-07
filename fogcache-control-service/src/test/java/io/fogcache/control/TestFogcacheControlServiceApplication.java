package io.fogcache.control;

import org.springframework.boot.SpringApplication;

public class TestFogcacheControlServiceApplication {

	public static void main(String[] args) {
		SpringApplication.from(FogcacheControlServiceApplication::main).with(TestcontainersConfiguration.class).run(args);
	}

}
