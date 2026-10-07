package com.ouresults.gateway.web;

import com.ouresults.gateway.dto.ApiResponse;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class ReadServiceFallbackController {
    private static final String RETRY_AFTER_SECONDS = "5";

    @GetMapping("/fallback/read")
    public ResponseEntity<ApiResponse<Void>> readUnavailable() {
        return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
                .header(HttpHeaders.RETRY_AFTER, RETRY_AFTER_SECONDS)
                .body(ApiResponse.error(503, "temporarily unavailable, try again shortly"));
    }
}
