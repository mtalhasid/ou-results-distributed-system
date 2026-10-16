package com.ouresults.persistence.dto;

public record PublishStatusResponse(
        String examId,
        String overallStatus,
        ShardStatus shard1,
        ShardStatus shard2
) {
    public record ShardStatus(
            String status,
            long publishedCount,
            long unpublishedCount
    ) {}
}
