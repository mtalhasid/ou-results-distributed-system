package com.ouresults.read.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.ouresults.read.config.ShardContext;
import com.ouresults.read.config.ShardMap;
import com.ouresults.read.repository.ResultRepository;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.data.redis.RedisConnectionFailureException;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.data.redis.core.ValueOperations;

import java.time.Duration;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class OptimizedResultReadServiceTest {
    private static final String ROLL_NO = "160423733001";
    private static final String CACHE_KEY = "result:{" + ROLL_NO + "}";
    private static final String LOCK_KEY = "lock:" + CACHE_KEY;

    private final ResultRepository resultRepository = mock(ResultRepository.class);
    private final ShardMap shardMap = mock(ShardMap.class);
    private final ShardContext shardContext = mock(ShardContext.class);
    private final RedisTemplate<String, String> redisTemplate = mock(RedisTemplate.class);
    private final ValueOperations<String, String> valueOperations = mock(ValueOperations.class);
    private final SimpleMeterRegistry meterRegistry = new SimpleMeterRegistry();
    private OptimizedResultReadService service;

    @BeforeEach
    void setUp() {
        when(redisTemplate.opsForValue()).thenReturn(valueOperations);
        when(shardMap.shardFor("1604")).thenReturn("shard1");
        when(resultRepository.findPublishedByRollNo(ROLL_NO)).thenReturn(List.of());
        service = new OptimizedResultReadService(
                resultRepository,
                shardMap,
                shardContext,
                redisTemplate,
                new ObjectMapper().findAndRegisterModules(),
                meterRegistry
        );
    }

    @Test
    void cachesEmptyResultsAndCountsSubsequentNegativeHits() {
        when(valueOperations.get(CACHE_KEY)).thenReturn(null, null, "[]");
        when(valueOperations.setIfAbsent(eq(LOCK_KEY), any(String.class), eq(Duration.ofSeconds(15))))
                .thenReturn(true);

        assertTrue(service.findByRollNo(ROLL_NO).isEmpty());
        assertTrue(service.findByRollNo(ROLL_NO).isEmpty());

        verify(valueOperations).set(CACHE_KEY, "[]", Duration.ofSeconds(30));
        verify(resultRepository).findPublishedByRollNo(ROLL_NO);
        assertEquals(1.0, meterRegistry.get("result.cache.miss").counter().count());
        assertEquals(1.0, meterRegistry.get("result.cache.hit").counter().count());
        assertEquals(1.0, meterRegistry.get("result.cache.negative.hit").counter().count());
    }

    @Test
    void readsFromDatabaseWhenRedisIsUnavailable() {
        when(valueOperations.get(CACHE_KEY))
                .thenThrow(new RedisConnectionFailureException("Redis unavailable"));

        assertTrue(service.findByRollNo(ROLL_NO).isEmpty());

        verify(resultRepository).findPublishedByRollNo(ROLL_NO);
        verify(valueOperations, never()).setIfAbsent(any(String.class), any(String.class), any(Duration.class));
    }

    @Test
    void waitsForContendedFillAndUsesTheCacheWhenItAppears() {
        when(valueOperations.get(CACHE_KEY)).thenReturn(null, "[]");
        when(valueOperations.setIfAbsent(eq(LOCK_KEY), any(String.class), eq(Duration.ofSeconds(15))))
                .thenReturn(false);

        assertTrue(service.findByRollNo(ROLL_NO).isEmpty());

        verify(resultRepository, never()).findPublishedByRollNo(ROLL_NO);
        assertEquals(1.0, meterRegistry.get("result.cache.lock.wait").counter().count());
        assertEquals(1.0, meterRegistry.get("result.cache.negative.hit").counter().count());
    }
}
