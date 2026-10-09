package com.ouresults.persistence.dto;

import com.fasterxml.jackson.databind.JsonNode;
import java.math.BigDecimal;

public record ResultRowDto(
        String rollNo,
        short semester,
        String collegeCode,
        short batchYear,
        String deptCode,
        String name,
        String fatherName,
        String gender,
        String course,
        String medium,
        JsonNode subjects,
        String resultStatus,
        BigDecimal sgpa,
        BigDecimal cgpa
) {}
