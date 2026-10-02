package com.ouresults.gateway.config;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.validation.annotation.Validated;

@Validated
@ConfigurationProperties(prefix = "gateway")
public record GatewayProperties(
        @NotBlank String readServiceUrl,
        @NotBlank String collegeMapLocation,
        @NotBlank String redisHost,
        @Min(1) @Max(65535) int redisPort,
        @Min(1) @Max(65535) int serverPort,
        @Valid @NotNull RateLimit rateLimit
) {
    public record RateLimit(
            @Min(1) int replenishRate,
            @Min(1) int burstCapacity
    ) {
    }
}
