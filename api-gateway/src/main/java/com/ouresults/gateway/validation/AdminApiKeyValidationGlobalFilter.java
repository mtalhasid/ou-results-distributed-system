package com.ouresults.gateway.validation;

import com.ouresults.gateway.web.GatewayProblemDetailHandler;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
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
@Order(Ordered.HIGHEST_PRECEDENCE + 2)
@RequiredArgsConstructor
public class AdminApiKeyValidationGlobalFilter implements GlobalFilter {

    private static final String ADMIN_PATH = "/admin";
    private static final String API_KEY_HEADER = "X-Admin-Api-Key";

    private final GatewayProblemDetailHandler problemDetailHandler;

    @Value("${gateway.admin-api-key:ou-admin-secret-key-2026}")
    private String adminApiKey;

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, GatewayFilterChain chain) {
        String path = exchange.getRequest().getPath().pathWithinApplication().value();
        if (!path.equals(ADMIN_PATH) && !path.startsWith(ADMIN_PATH + "/")) {
            return chain.filter(exchange);
        }

        String providedKey = exchange.getRequest().getHeaders().getFirst(API_KEY_HEADER);
        if (providedKey != null && providedKey.equals(adminApiKey)) {
            return chain.filter(exchange);
        }

        String correlationId = exchange.getRequest().getHeaders().getFirst("X-Correlation-Id");
        log.warn("Unauthorized admin request rejected correlationId={} path={}", correlationId, path);
        return problemDetailHandler.writeProblem(
                exchange,
                HttpStatus.UNAUTHORIZED,
                "Unauthorized: Invalid or missing X-Admin-Api-Key header."
        );
    }
}
