package com.ouresults.read.exception;

public class UnknownCollegeException extends RuntimeException {
    public UnknownCollegeException(String collegeCode) {
        super("Unknown college code: " + collegeCode);
    }
}
