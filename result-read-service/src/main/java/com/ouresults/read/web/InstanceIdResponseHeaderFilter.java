package com.ouresults.read.web;

import com.ouresults.read.config.ReadServiceProperties;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import lombok.RequiredArgsConstructor;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;

@Component
@RequiredArgsConstructor
@ConditionalOnProperty(prefix = "app", name = "expose-instance-id", havingValue = "true")
public class InstanceIdResponseHeaderFilter extends OncePerRequestFilter {
    private static final String HEADER_NAME = "X-Instance-Id";

    private final ReadServiceProperties properties;

    @Override
    protected void doFilterInternal(
            HttpServletRequest request,
            HttpServletResponse response,
            FilterChain filterChain
    ) throws ServletException, IOException {
        response.setHeader(HEADER_NAME, properties.instanceId());
        filterChain.doFilter(request, response);
    }
}
