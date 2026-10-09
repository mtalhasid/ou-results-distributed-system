package com.ouresults.persistence.config;

import java.util.Map;

public record ShardMap(Map<String, String> colleges) {
    public String shardFor(String collegeCode) {
        String shard = colleges.get(collegeCode);
        if (shard == null) {
            throw new IllegalArgumentException("Unknown college code: " + collegeCode);
        }
        return shard;
    }
}
