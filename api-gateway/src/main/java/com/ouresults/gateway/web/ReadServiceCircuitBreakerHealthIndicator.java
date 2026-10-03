package com.ouresults.gateway.web;

import io.github.resilience4j.circuitbreaker.CircuitBreaker;
import io.github.resilience4j.circuitbreaker.CircuitBreakerRegistry;
import lombok.RequiredArgsConstructor;
import org.springframework.boot.health.contributor.Health;
import org.springframework.boot.health.contributor.HealthIndicator;
import org.springframework.stereotype.Component;

@Component
@RequiredArgsConstructor
public class ReadServiceCircuitBreakerHealthIndicator implements HealthIndicator {
    private final CircuitBreakerRegistry circuitBreakerRegistry;

    @Override
    public Health health() {
        CircuitBreaker circuitBreaker = circuitBreakerRegistry.circuitBreaker("readService");
        Health.Builder health = circuitBreaker.getState() == CircuitBreaker.State.OPEN
                ? Health.down()
                : Health.up();
        return health
                .withDetail("name", circuitBreaker.getName())
                .withDetail("state", circuitBreaker.getState().name())
                .withDetail("failureRate", circuitBreaker.getMetrics().getFailureRate())
                .withDetail("notPermittedCalls", circuitBreaker.getMetrics().getNumberOfNotPermittedCalls())
                .build();
    }
}
