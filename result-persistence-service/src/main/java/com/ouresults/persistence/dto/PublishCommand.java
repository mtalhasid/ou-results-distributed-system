package com.ouresults.persistence.dto;

import java.time.Instant;

public record PublishCommand(
        String examId,
        Instant requestedAt
) {}
