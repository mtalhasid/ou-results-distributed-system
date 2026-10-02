package com.ouresults.gateway.web;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpStatus;
import org.springframework.http.HttpStatusCode;
import org.springframework.http.MediaType;
import org.springframework.http.ProblemDetail;
import org.springframework.http.codec.ServerCodecConfigurer;
import org.springframework.http.server.reactive.ServerHttpResponse;
import org.springframework.http.server.reactive.ServerHttpResponseDecorator;
import org.springframework.stereotype.Component;
import org.springframework.web.reactive.function.server.ServerResponse;
import org.springframework.web.reactive.result.view.ViewResolver;
import org.springframework.web.server.ServerWebExchange;
import reactor.core.publisher.Mono;

import java.util.List;

@Slf4j
@Component
@RequiredArgsConstructor
public class GatewayProblemDetailHandler {
    private final ServerCodecConfigurer codecConfigurer;

    public Mono<Void> writeProblem(
            ServerWebExchange exchange,
            HttpStatusCode status,
            String detail
    ) {
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(status, detail);
        problem.setInstance(exchange.getRequest().getURI());
        return ServerResponse.status(status)
                .contentType(MediaType.APPLICATION_PROBLEM_JSON)
                .bodyValue(problem)
                .flatMap(response -> response.writeTo(exchange, new ServerResponse.Context() {
                    @Override
                    public List<org.springframework.http.codec.HttpMessageWriter<?>> messageWriters() {
                        return codecConfigurer.getWriters();
                    }

                    @Override
                    public List<ViewResolver> viewResolvers() {
                        return List.of();
                    }
                }));
    }

    public ServerHttpResponse decorateRateLimitResponse(
            ServerWebExchange exchange,
            ServerHttpResponse response,
            String correlationId
    ) {
        return new ServerHttpResponseDecorator(response) {
            @Override
            public Mono<Void> setComplete() {
                if (getStatusCode() == HttpStatus.TOO_MANY_REQUESTS && !isCommitted()) {
                    log.warn("Request rate limit exceeded correlationId={}", correlationId);
                    return writeProblem(
                            exchange,
                            HttpStatus.TOO_MANY_REQUESTS,
                            "Request rate limit exceeded."
                    );
                }
                return super.setComplete();
            }
        };
    }
}
