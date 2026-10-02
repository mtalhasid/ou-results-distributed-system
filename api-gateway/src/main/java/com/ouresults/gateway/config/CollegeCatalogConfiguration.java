package com.ouresults.gateway.config;

import lombok.RequiredArgsConstructor;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.io.ResourceLoader;
import org.yaml.snakeyaml.LoaderOptions;
import org.yaml.snakeyaml.Yaml;
import org.yaml.snakeyaml.constructor.SafeConstructor;

import java.io.IOException;
import java.util.HashMap;
import java.util.Map;

@Configuration(proxyBeanMethods = false)
@RequiredArgsConstructor
public class CollegeCatalogConfiguration {
    private final ResourceLoader resourceLoader;
    private final GatewayProperties gatewayProperties;

    @Bean
    public CollegeCatalog collegeCatalog() throws IOException {
        var resource = resourceLoader.getResource(gatewayProperties.collegeMapLocation());
        try (var input = resource.getInputStream()) {
            Object document = new Yaml(new SafeConstructor(new LoaderOptions())).load(input);
            if (!(document instanceof Map<?, ?> root)
                    || !(root.get("colleges") instanceof Map<?, ?> entries)) {
                throw new IllegalStateException("Gateway shard map must contain a colleges mapping.");
            }

            Map<String, String> colleges = new HashMap<>();
            for (Map.Entry<?, ?> entry : entries.entrySet()) {
                if (entry.getKey() instanceof String code
                        && entry.getValue() instanceof String shard) {
                    colleges.put(code, shard);
                } else {
                    throw new IllegalStateException("Gateway shard map contains an invalid college entry.");
                }
            }
            return new CollegeCatalog(colleges);
        }
    }
}
