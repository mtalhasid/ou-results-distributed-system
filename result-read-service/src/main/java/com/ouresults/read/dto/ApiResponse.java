package com.ouresults.read.dto;

import lombok.Builder;

@Builder
public record ApiResponse<T>(
        String status,
        int statusCode,
        String message,
        T data
) {
    public static <T> ApiResponse<T> success(int statusCode, String message, T data) {
        return ApiResponse.<T>builder()
                .status("success")
                .statusCode(statusCode)
                .message(message)
                .data(data)
                .build();
    }

    public static <T> ApiResponse<T> error(int statusCode, String message) {
        return ApiResponse.<T>builder()
                .status("error")
                .statusCode(statusCode)
                .message(message)
                .data(null)
                .build();
    }
}
