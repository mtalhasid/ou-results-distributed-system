package com.ouresults.read.service;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.ouresults.read.config.ShardContext;
import com.ouresults.read.config.ShardMap;
import com.ouresults.read.dto.ResultResponse;
import com.ouresults.read.repository.ResultRepository;
import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Profile;
import org.springframework.dao.DataAccessException;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.data.redis.core.script.DefaultRedisScript;
import org.springframework.stereotype.Service;

import java.time.Duration;
import java.util.List;
import java.util.UUID;

@Slf4j
@Service
@Profile("optimized")
public class OptimizedResultReadService implements ResultReadService {
    private static final Duration POSITIVE_TTL = Duration.ofMinutes(10);
    private static final Duration NEGATIVE_TTL = Duration.ofSeconds(30);
    private static final Duration LOCK_TTL = Duration.ofSeconds(15);
    private static final int LOCK_RECHECK_ATTEMPTS = 5;
    private static final long LOCK_RECHECK_DELAY_MILLIS = 50;
    private static final TypeReference<List<ResultResponse>> RESULT_LIST_TYPE = new TypeReference<>() {};
    private static final DefaultRedisScript<Long> RELEASE_LOCK_SCRIPT = new DefaultRedisScript<>(
            "if redis.call('get', KEYS[1]) == ARGV[1] then "
                    + "return redis.call('del', KEYS[1]) else return 0 end",
            Long.class
    );

    private final ResultRepository resultRepository;
    private final ShardMap shardMap;
    private final ShardContext shardContext;
    private final RedisTemplate<String, String> redisTemplate;
    private final ObjectMapper objectMapper;
    private final Counter cacheHits;
    private final Counter cacheMisses;
    private final Counter negativeCacheHits;
    private final Counter lockWaits;

    public OptimizedResultReadService(
            ResultRepository resultRepository,
            ShardMap shardMap,
            ShardContext shardContext,
            @Qualifier("resultRedisTemplate") RedisTemplate<String, String> redisTemplate,
            ObjectMapper objectMapper,
            MeterRegistry meterRegistry
    ) {
        this.resultRepository = resultRepository;
        this.shardMap = shardMap;
        this.shardContext = shardContext;
        this.redisTemplate = redisTemplate;
        this.objectMapper = objectMapper;
        this.cacheHits = meterRegistry.counter("result.cache.hit");
        this.cacheMisses = meterRegistry.counter("result.cache.miss");
        this.negativeCacheHits = meterRegistry.counter("result.cache.negative.hit");
        this.lockWaits = meterRegistry.counter("result.cache.lock.wait");
    }

    @Override
    public List<ResultResponse> findByRollNo(String rollNo) {
        String cacheKey = "result:{" + rollNo + "}";
        CacheLookup initialLookup = readCache(cacheKey);
        if (!initialLookup.available()) {
            return readFromDatabase(rollNo);
        }
        if (initialLookup.value() != null) {
            return recordCacheHit(initialLookup.value());
        }
        cacheMisses.increment();

        String lockKey = "lock:" + cacheKey;
        String lockToken = UUID.randomUUID().toString();
        boolean lockAcquired;
        try {
            lockAcquired = Boolean.TRUE.equals(
                    redisTemplate.opsForValue().setIfAbsent(lockKey, lockToken, LOCK_TTL)
            );
        } catch (DataAccessException exception) {
            log.warn("Redis unavailable while acquiring result cache lock; reading from the database.");
            return readFromDatabase(rollNo);
        }

        if (lockAcquired) {
            try {
                CacheLookup lookupAfterLock = readCache(cacheKey);
                if (!lookupAfterLock.available()) {
                    return readFromDatabase(rollNo);
                }
                if (lookupAfterLock.value() != null) {
                    return recordCacheHit(lookupAfterLock.value());
                }

                List<ResultResponse> results = readFromDatabase(rollNo);
                writeCache(cacheKey, results);
                return results;
            } finally {
                releaseLock(lockKey, lockToken);
            }
        }

        lockWaits.increment();
        for (int attempt = 0; attempt < LOCK_RECHECK_ATTEMPTS; attempt++) {
            try {
                Thread.sleep(LOCK_RECHECK_DELAY_MILLIS);
            } catch (InterruptedException exception) {
                Thread.currentThread().interrupt();
                log.warn("Interrupted while waiting for a result cache fill; reading from the database.");
                return readFromDatabase(rollNo);
            }

            CacheLookup lookupWhileWaiting = readCache(cacheKey);
            if (!lookupWhileWaiting.available()) {
                return readFromDatabase(rollNo);
            }
            if (lookupWhileWaiting.value() != null) {
                return recordCacheHit(lookupWhileWaiting.value());
            }
        }

        List<ResultResponse> results = readFromDatabase(rollNo);
        writeCache(cacheKey, results);
        return results;
    }

    private CacheLookup readCache(String cacheKey) {
        try {
            String cachedJson = redisTemplate.opsForValue().get(cacheKey);
            if (cachedJson == null) {
                return new CacheLookup(true, null);
            }
            List<ResultResponse> results = objectMapper.readValue(cachedJson, RESULT_LIST_TYPE);
            if (results == null) {
                log.warn("Invalid null value in result cache; treating it as a cache miss.");
                return new CacheLookup(true, null);
            }
            return new CacheLookup(true, results);
        } catch (DataAccessException exception) {
            log.warn("Redis unavailable while reading result cache; reading from the database.");
            return new CacheLookup(false, null);
        } catch (JsonProcessingException exception) {
            log.warn("Invalid JSON in result cache; treating it as a cache miss.", exception);
            try {
                redisTemplate.delete(cacheKey);
            } catch (DataAccessException cacheException) {
                log.warn("Redis unavailable while removing an invalid result cache entry.");
            }
            return new CacheLookup(true, null);
        }
    }

    private List<ResultResponse> recordCacheHit(List<ResultResponse> results) {
        cacheHits.increment();
        if (results.isEmpty()) {
            negativeCacheHits.increment();
        }
        return results;
    }

    private void writeCache(String cacheKey, List<ResultResponse> results) {
        try {
            String cachedJson = objectMapper.writeValueAsString(results);
            Duration ttl = results.isEmpty() ? NEGATIVE_TTL : POSITIVE_TTL;
            redisTemplate.opsForValue().set(cacheKey, cachedJson, ttl);
        } catch (DataAccessException exception) {
            log.warn("Redis unavailable while writing result cache; returning database results.");
        } catch (JsonProcessingException exception) {
            log.error("Could not serialize result list for cache; returning database results.", exception);
        }
    }

    private void releaseLock(String lockKey, String lockToken) {
        try {
            redisTemplate.execute(RELEASE_LOCK_SCRIPT, List.of(lockKey), lockToken);
        } catch (DataAccessException exception) {
            log.warn("Redis unavailable while releasing result cache lock; its expiry will release it.");
        }
    }

    private List<ResultResponse> readFromDatabase(String rollNo) {
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

    private record CacheLookup(boolean available, List<ResultResponse> value) {}
}
