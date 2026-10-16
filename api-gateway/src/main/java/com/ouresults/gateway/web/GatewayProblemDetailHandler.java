package com.ouresults.gateway.web;

import com.ouresults.gateway.dto.ApiResponse;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpStatus;
import org.springframework.http.HttpStatusCode;
import org.springframework.http.MediaType;
import org.springframework.http.codec.HttpMessageWriter;
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
public class GatewayProblemDetailHandler {
    private final ServerCodecConfigurer codecConfigurer;
    private final ServerResponse.Context responseContext;

    public GatewayProblemDetailHandler(ServerCodecConfigurer codecConfigurer) {
        this.codecConfigurer = codecConfigurer;
        this.responseContext = new GatewayResponseContext(codecConfigurer.getWriters());
    }

    public Mono<Void> writeProblem(
            ServerWebExchange exchange,
            HttpStatusCode status,
            String detail
    ) {
        ApiResponse<Void> body = ApiResponse.error(status.value(), detail);
        return ServerResponse.status(status)
                .contentType(MediaType.APPLICATION_JSON)
                .bodyValue(body)
                .flatMap(response -> response.writeTo(exchange, responseContext));
    }

    public ServerHttpResponse decorateRateLimitResponse(
            ServerWebExchange exchange,
            ServerHttpResponse response,
            String correlationId
    ) {
        return new RateLimitResponseDecorator(
                response,
                exchange,
                correlationId,
                this
        );
    }

    private static class GatewayResponseContext implements ServerResponse.Context {
        private final List<HttpMessageWriter<?>> writers;

        GatewayResponseContext(List<HttpMessageWriter<?>> writers) {
            this.writers = writers;
        }

        @Override
        public List<HttpMessageWriter<?>> messageWriters() {
            return writers;
        }

        @Override
        public List<ViewResolver> viewResolvers() {
            return List.of();
        }
    }

    private static class RateLimitResponseDecorator extends ServerHttpResponseDecorator {
        private final ServerWebExchange exchange;
        private final String correlationId;
        private final GatewayProblemDetailHandler problemHandler;

        RateLimitResponseDecorator(
                ServerHttpResponse delegate,
                ServerWebExchange exchange,
                String correlationId,
                GatewayProblemDetailHandler problemHandler
        ) {
            super(delegate);
            this.exchange = exchange;
            this.correlationId = correlationId;
            this.problemHandler = problemHandler;
        }

        @Override
        public Mono<Void> setComplete() {
            if (getStatusCode() == HttpStatus.TOO_MANY_REQUESTS && !isCommitted()) {
                log.warn("Request rate limit exceeded correlationId={}", correlationId);
                return problemHandler.writeProblem(
                        exchange,
                        HttpStatus.TOO_MANY_REQUESTS,
                        "Request rate limit exceeded."
                );
            }
            return super.setComplete();
        }
    }
}
