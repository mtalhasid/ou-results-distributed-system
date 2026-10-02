package com.ouresults.gateway.validation;

import jakarta.validation.constraints.Pattern;

public record RollNumber(
        @Pattern(regexp = "^\\d{12}$", message = "roll number must contain exactly 12 digits")
        @KnownCollege
        String value
) {
}
