package com.ouresults.read.config;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.boot.context.properties.bind.DefaultValue;
import org.springframework.validation.annotation.Validated;

@Validated
@Slf4j
@ConfigurationProperties(prefix = "app.demo")
public record DemoProperties(
        @DefaultValue("none")
        @NotBlank
        @Pattern(regexp = "none|shard1|shard2")
        String failingShard
) {
    public DemoProperties {
        if (!"none".equals(failingShard)) {
            log.warn("Demo database failure enabled for shard={} correlationId=startup", failingShard);
        }
    }
}
