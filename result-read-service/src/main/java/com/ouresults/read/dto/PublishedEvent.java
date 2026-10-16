package com.ouresults.read.dto;

import java.time.Instant;

public record PublishedEvent(
        String eventId,
        String eventType,
        String examId,
        Instant occurredAt
) {}
