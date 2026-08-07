package io.fogcache.analytics;

import org.springframework.boot.SpringApplication;

public class TestFogcacheAnalyticsServiceApplication {

	public static void main(String[] args) {
		SpringApplication.from(FogcacheAnalyticsServiceApplication::main).with(TestcontainersConfiguration.class).run(args);
	}

}
