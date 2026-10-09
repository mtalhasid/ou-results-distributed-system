package com.ouresults.persistence.dto;

import java.time.Instant;
import java.util.List;

public record ResultBatchMessage(
        String batchId,
        String examId,
        String collegeCode,
        Instant uploadedAt,
        ExamDto exam,
        List<ResultRowDto> rows
) {}
