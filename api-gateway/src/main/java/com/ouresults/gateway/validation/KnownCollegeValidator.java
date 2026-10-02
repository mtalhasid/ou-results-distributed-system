package com.ouresults.gateway.validation;

import com.ouresults.gateway.config.CollegeCatalog;
import jakarta.validation.ConstraintValidator;
import jakarta.validation.ConstraintValidatorContext;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

@Component
@RequiredArgsConstructor
public class KnownCollegeValidator implements ConstraintValidator<KnownCollege, String> {
    private final CollegeCatalog collegeCatalog;

    @Override
    public boolean isValid(String value, ConstraintValidatorContext context) {
        return value != null
                && value.length() >= 4
                && collegeCatalog.colleges().containsKey(value.substring(0, 4));
    }
}
