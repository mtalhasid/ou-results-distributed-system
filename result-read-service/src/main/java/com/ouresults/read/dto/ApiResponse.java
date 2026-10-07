package com.ouresults.read.dto;

public record ApiResponse<T>(
        String status,
        int statusCode,
        String message,
        T data
) {
    public static <T> ApiResponse<T> success(int statusCode, String message, T data) {
        return new ApiResponse<>("success", statusCode, message, data);
    }

    public static <T> ApiResponse<T> error(int statusCode, String message) {
        return new ApiResponse<>("error", statusCode, message, null);
    }
}
