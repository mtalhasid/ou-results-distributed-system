package com.ouresults.persistence.dto;

import java.time.LocalDate;

public record ExamDto(
        String examId,
        String title,
        LocalDate resultDate
) {}
