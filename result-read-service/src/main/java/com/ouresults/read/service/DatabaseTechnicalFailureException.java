package com.ouresults.read.service;

public class DatabaseTechnicalFailureException extends RuntimeException {
    public DatabaseTechnicalFailureException(String message, Throwable cause) {
        super(message, cause);
    }

    public DatabaseTechnicalFailureException(String message) {
        super(message);
    }
}
