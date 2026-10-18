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
