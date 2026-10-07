package com.ouresults.read.config;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.boot.context.properties.bind.DefaultValue;
import org.springframework.validation.annotation.Validated;

@Slf4j
@Validated
@ConfigurationProperties(prefix = "app")
public record AppProperties(
        boolean exposeInstanceId,
        String instanceId,
        Demo demo
) {
    public AppProperties {
        if (demo != null && !"none".equals(demo.failingShard())) {
            log.warn("Demo database failure enabled for shard={} correlationId=startup", demo.failingShard());
        }
    }

    public record Demo(
            @DefaultValue("none")
            @NotBlank
            @Pattern(regexp = "none|shard1|shard2")
            String failingShard
    ) {}
}
