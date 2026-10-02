package com.ouresults.read.service;

import com.ouresults.read.config.ShardContext;
import com.ouresults.read.config.ShardMap;
import com.ouresults.read.dto.ResultResponse;
import com.ouresults.read.repository.ResultRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.context.annotation.Profile;

import java.util.List;

@Service
@RequiredArgsConstructor
@Profile("naive")
public class ResultReadServiceImpl implements ResultReadService {
    private final ResultRepository resultRepository;
    private final ShardMap shardMap;
    private final ShardContext shardContext;

    @Override
    public List<ResultResponse> findByRollNo(String rollNo) {
        String shard = shardMap.shardFor(rollNo.substring(0, 4));
        String previousShard = shardContext.useShard(shard);
        try {
            return resultRepository.findPublishedByRollNo(rollNo).stream()
                    .map(ResultResponse::from)
                    .toList();
        } finally {
            shardContext.restore(previousShard);
        }
    }
}
