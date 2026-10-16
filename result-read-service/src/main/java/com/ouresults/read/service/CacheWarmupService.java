package com.ouresults.read.service;

import com.ouresults.read.dto.ResultResponse;
import com.ouresults.read.entity.ResultEntity;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

@Slf4j
@Service
@Profile("optimized")
@RequiredArgsConstructor
public class CacheWarmupService {

    private final ShardDatabaseReader shardDatabaseReader;
    private final CacheWarmupWriter cacheWarmupWriter;
    private static final int PAGE_SIZE = 200;
    private static final long PACE_DELAY_MS = 100L;

    public void warmupExam(String examId) {
        log.info("Starting gentle cache warm-up for examId={} from primary shards...", examId);
        long startTime = System.currentTimeMillis();
        int totalWarmupCount = 0;

        for (String shard : List.of("shard1", "shard2")) {
            int page = 0;
            while (true) {
                List<ResultEntity> rows = shardDatabaseReader.fetchExamPageFromPrimary(shard, examId, page, PAGE_SIZE);
                if (rows == null || rows.isEmpty()) {
                    break;
                }

                // Group all rows in this page by rollNo
                Map<String, List<ResultResponse>> grouped = rows.stream()
                        .map(ResultResponse::from)
                        .collect(Collectors.groupingBy(ResultResponse::rollNo));

                for (Map.Entry<String, List<ResultResponse>> entry : grouped.entrySet()) {
                    cacheWarmupWriter.putInCache(entry.getKey(), entry.getValue());
                    totalWarmupCount++;
                }

                log.info("Warmed cache page={} ({} students) on {} for exam {}", page, grouped.size(), shard, examId);

                if (rows.size() < PAGE_SIZE) {
                    break;
                }
                page++;

                // Pace the pages gently for free-tier database primaries
                try {
                    Thread.sleep(PACE_DELAY_MS);
                } catch (InterruptedException ignored) {
                    Thread.currentThread().interrupt();
                    break;
                }
            }
        }

        long duration = System.currentTimeMillis() - startTime;
        log.info("Cache warm-up completed for examId={}: {} roll numbers cached in {} ms",
                examId, totalWarmupCount, duration);
    }
}
