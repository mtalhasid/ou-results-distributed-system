package com.ouresults.read.consumer;

import com.ouresults.read.dto.PublishedEvent;
import com.ouresults.read.service.CacheWarmupService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Profile;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Component;

@Slf4j
@Component
@Profile("optimized")
@RequiredArgsConstructor
public class PublishEventConsumer {

    private final CacheWarmupService cacheWarmupService;

    @KafkaListener(topics = "results.published", groupId = "read-service-cache-warmup")
    public void onExamPublished(PublishedEvent event) {
        log.info("Received results.published event for examId={}", event.examId());
        try {
            cacheWarmupService.warmupExam(event.examId());
        } catch (Exception e) {
            log.error("Failed to warm up cache for examId={}", event.examId(), e);
        }
    }
}
