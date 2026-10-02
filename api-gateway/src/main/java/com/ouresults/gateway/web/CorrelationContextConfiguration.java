package com.ouresults.gateway.web;

import jakarta.annotation.PostConstruct;
import io.micrometer.context.ContextRegistry;
import org.slf4j.MDC;
import org.springframework.context.annotation.Configuration;
import reactor.core.publisher.Hooks;

@Configuration(proxyBeanMethods = false)
public class CorrelationContextConfiguration {
    public static final String CORRELATION_ID = "correlationId";

    @PostConstruct
    public void enableCorrelationContextPropagation() {
        ContextRegistry.getInstance().removeThreadLocalAccessor(CORRELATION_ID);
        ContextRegistry.getInstance().registerThreadLocalAccessor(
                CORRELATION_ID,
                () -> MDC.get(CORRELATION_ID),
                value -> {
                    if (value == null) {
                        MDC.remove(CORRELATION_ID);
                    } else {
                        MDC.put(CORRELATION_ID, value);
                    }
                },
                () -> MDC.remove(CORRELATION_ID)
        );
        Hooks.enableAutomaticContextPropagation();
    }
}
