package com.ouresults.gateway.web;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.cloud.gateway.filter.GatewayFilterChain;
import org.springframework.cloud.gateway.filter.GlobalFilter;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.http.server.reactive.ServerHttpResponse;
import org.springframework.stereotype.Component;
import org.springframework.web.server.ServerWebExchange;
import reactor.core.publisher.Mono;

import java.util.UUID;

@Slf4j
@Component
@Order(Ordered.HIGHEST_PRECEDENCE)
@RequiredArgsConstructor
public class GatewayCorrelationIdGlobalFilter implements GlobalFilter {
    private static final String HEADER_NAME = "X-Correlation-Id";

    private final GatewayProblemDetailHandler problemDetailHandler;

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, GatewayFilterChain chain) {
        String incoming = exchange.getRequest().getHeaders().getFirst(HEADER_NAME);
        String correlationId = incoming == null || incoming.isBlank()
                ? UUID.randomUUID().toString()
                : incoming;

        ServerWebExchange correlatedExchange = exchange.mutate()
                .request(request -> request.headers(headers -> headers.set(HEADER_NAME, correlationId)))
                .build();
        ServerHttpResponse response = correlatedExchange.getResponse();
        response.beforeCommit(() -> {
            response.getHeaders().set(HEADER_NAME, correlationId);
            return Mono.empty();
        });
        ServerHttpResponse decoratedResponse = problemDetailHandler.decorateRateLimitResponse(
                correlatedExchange,
                response,
                correlationId
        );
        ServerWebExchange routedExchange = correlatedExchange.mutate()
                .response(decoratedResponse)
                .build();

        return Mono.deferContextual(context -> {
            log.debug(
                    "Gateway request method={} route=/api/results/{rollNo} correlationId={}",
                    routedExchange.getRequest().getMethod(),
                    correlationId
            );
            return chain.filter(routedExchange);
        }).contextWrite(context -> context.put(CorrelationContextConfiguration.CORRELATION_ID, correlationId));
    }
}
