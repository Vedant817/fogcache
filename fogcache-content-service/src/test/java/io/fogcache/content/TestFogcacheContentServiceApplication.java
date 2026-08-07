package io.fogcache.content;

import org.springframework.boot.SpringApplication;

public class TestFogcacheContentServiceApplication {

	public static void main(String[] args) {
		SpringApplication.from(FogcacheContentServiceApplication::main).with(TestcontainersConfiguration.class).run(args);
	}

}
