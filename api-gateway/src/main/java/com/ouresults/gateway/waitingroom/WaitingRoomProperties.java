package com.ouresults.gateway.waitingroom;

import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotNull;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.validation.annotation.Validated;

import java.time.Duration;

@Validated
@ConfigurationProperties(prefix = "waiting-room")
public record WaitingRoomProperties(
        boolean enabled,
        @Min(1) int maxActive,
        @NotNull Duration activeTtl,
        @NotNull Duration queueTtl,
        @Min(1) int maxQueueLength,
        @NotNull Duration retryAfter
) {
    public WaitingRoomProperties {
        // apply defaults when constructed via @ConfigurationProperties binding
    }
}
