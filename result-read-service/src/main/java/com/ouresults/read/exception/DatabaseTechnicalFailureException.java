package com.ouresults.read.exception;

public class DatabaseTechnicalFailureException extends RuntimeException {
    public DatabaseTechnicalFailureException(String message) {
        super(message);
    }

    public DatabaseTechnicalFailureException(String message, Throwable cause) {
        super(message, cause);
    }
}
