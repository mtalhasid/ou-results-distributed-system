package com.ouresults.read.web;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.UUID;
import java.util.regex.Pattern;

@Component
public class CorrelationIdFilter extends OncePerRequestFilter {
    private static final Logger LOGGER = LoggerFactory.getLogger(CorrelationIdFilter.class);
    private static final Pattern SAFE_ID = Pattern.compile("[A-Za-z0-9._-]{1,64}");

    @Override
    protected void doFilterInternal(
            HttpServletRequest request,
            HttpServletResponse response,
            FilterChain filterChain
    ) throws ServletException, IOException {
        String incomingId = request.getHeader("X-Correlation-Id");
        String correlationId = incomingId != null && SAFE_ID.matcher(incomingId).matches()
                ? incomingId
                : UUID.randomUUID().toString();
        MDC.put("correlationId", correlationId);
        response.setHeader("X-Correlation-Id", correlationId);
        long startedAt = System.nanoTime();
        try {
            filterChain.doFilter(request, response);
        } finally {
            String path = request.getRequestURI().startsWith("/api/results/")
                    ? "/api/results/{rollNo}"
                    : request.getRequestURI();
            LOGGER.info("request completed method={} path={} status={} duration_ms={}",
                    request.getMethod(), path, response.getStatus(),
                    (System.nanoTime() - startedAt) / 1_000_000);
            MDC.remove("correlationId");
        }
    }
}
