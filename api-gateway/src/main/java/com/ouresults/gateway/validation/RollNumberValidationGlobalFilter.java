package com.ouresults.gateway.validation;

import com.ouresults.gateway.web.GatewayProblemDetailHandler;
import jakarta.validation.Validator;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.cloud.gateway.filter.GatewayFilterChain;
import org.springframework.cloud.gateway.filter.GlobalFilter;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import org.springframework.web.server.ServerWebExchange;
import reactor.core.publisher.Mono;

@Slf4j
@Component
@Order(Ordered.HIGHEST_PRECEDENCE + 1)
@RequiredArgsConstructor
public class RollNumberValidationGlobalFilter implements GlobalFilter {
    private static final String RESULTS_PATH = "/api/results";

    private final Validator validator;
    private final GatewayProblemDetailHandler problemDetailHandler;

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, GatewayFilterChain chain) {
        String path = exchange.getRequest().getPath().pathWithinApplication().value();
        if (!path.equals(RESULTS_PATH) && !path.startsWith(RESULTS_PATH + "/")) {
            return chain.filter(exchange);
        }

        String rollNumber = path.startsWith(RESULTS_PATH + "/")
                ? path.substring(RESULTS_PATH.length() + 1)
                : "";
        if (validator.validate(new RollNumber(rollNumber)).isEmpty()) {
            return chain.filter(exchange);
        }

        String correlationId = exchange.getRequest().getHeaders().getFirst("X-Correlation-Id");
        log.info("Rejected roll-number request correlationId={}", correlationId);
        return problemDetailHandler.writeProblem(
                exchange,
                HttpStatus.BAD_REQUEST,
                "The requested roll number is invalid."
        );
    }
}
