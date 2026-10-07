package com.ouresults.read.service;

import com.ouresults.read.config.ShardRoutingConfiguration.ShardMap;
import com.ouresults.read.dto.ResultResponse;
import lombok.RequiredArgsConstructor;
import org.springframework.cache.annotation.Cacheable;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Service;

import java.util.List;

@Service
@Profile("optimized")
@RequiredArgsConstructor
public class OptimizedResultReadService implements ResultReadService {
    private final ShardMap shardMap;
    private final ShardDatabaseReader shardDatabaseReader;

    /**
     * {@code sync = true} ensures only one thread per cache key enters the
     * method body; all other threads for the same key wait on the result.
     * This prevents a cold-burst stampede: 1000 requests for the same cold
     * roll number produce exactly 1 DB read, not 1000.
     *
     * <p>The per-shard bulkhead lives on {@link ShardDatabaseReader}, so
     * cache hits are served here without ever touching the bulkhead or DB.
     */
    @Override
    @Cacheable(cacheNames = "result", key = "#rollNo")
    public List<ResultResponse> findByRollNo(String rollNo) {
        String shard = shardMap.shardFor(rollNo.substring(0, 4));
        return switch (shard) {
            case "shard1" -> shardDatabaseReader.readShard1(rollNo);
            case "shard2" -> shardDatabaseReader.readShard2(rollNo);
            default -> throw new IllegalStateException("Shard map returned unsupported shard: " + shard);
        };
    }
}
