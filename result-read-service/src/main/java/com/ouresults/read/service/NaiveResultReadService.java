package com.ouresults.read.service;

import com.ouresults.read.config.ShardRoutingConfiguration.ShardContext;
import com.ouresults.read.config.ShardRoutingConfiguration.ShardMap;
import com.ouresults.read.dto.ResultResponse;
import com.ouresults.read.repository.ResultRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Service;

import java.util.List;

@Service
@Profile("naive")
@RequiredArgsConstructor
public class NaiveResultReadService implements ResultReadService {
    private final ResultRepository resultRepository;
    private final ShardMap shardMap;
    private final ShardContext shardContext;

    @Override
    public List<ResultResponse> findByRollNo(String rollNo) {
        String shard = shardMap.shardFor(rollNo.substring(0, 4));
        String previous = shardContext.useShard(shard);
        try {
            return resultRepository.findPublishedByRollNo(rollNo).stream()
                    .map(ResultResponse::from)
                    .toList();
        } finally {
            shardContext.restore(previous);
        }
    }
}
