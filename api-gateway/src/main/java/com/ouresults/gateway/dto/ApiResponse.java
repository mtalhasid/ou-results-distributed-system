package com.ouresults.gateway.dto;

public record ApiResponse<T>(
        String status,
        int statusCode,
        String message,
        T data
) {
    public static <T> ApiResponse<T> error(int statusCode, String message) {
        return new ApiResponse<>("error", statusCode, message, null);
    }
}
