package com.ouresults.read.config;

import com.fasterxml.jackson.databind.JavaType;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.ouresults.read.dto.ResultResponse;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.cache.Cache;
import org.springframework.cache.annotation.CachingConfigurer;
import org.springframework.cache.annotation.EnableCaching;
import org.springframework.cache.interceptor.CacheErrorHandler;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;
import org.springframework.data.redis.cache.RedisCacheConfiguration;
import org.springframework.data.redis.cache.RedisCacheManager;
import org.springframework.data.redis.connection.RedisConnectionFactory;
import org.springframework.data.redis.serializer.Jackson2JsonRedisSerializer;
import org.springframework.data.redis.serializer.RedisSerializationContext.SerializationPair;
import org.springframework.data.redis.serializer.StringRedisSerializer;

import java.time.Duration;
import java.util.List;
import java.util.Map;

/**
 * Cache configuration for the optimized profile only.
 *
 * <p>Key format in Redis: {@code result::<rollNo>}
 * (Spring default prefix = cacheName + "::", so "result" + "160423733001" → "result::160423733001").
 *
 * <p>TTL: 10 minutes for all entries.
 *
 * <p>Statistics: Spring Boot auto-binds {@code cache.gets} (result=hit/miss) via
 * {@code RedisCacheMeterBinderProviderConfiguration} when the cache is pre-declared
 * with {@code withInitialCacheConfigurations}.
 *
 * <p>Redis-down: {@link CachingConfigurer#errorHandler()} logs one WARN and lets
 * the call fall through to the database.
 *
 * <p>Stampede protection: {@code @Cacheable(sync = true)} on the service method
 * serialises concurrent loaders for the same key so only one thread reads the DB.
 */
@Slf4j
@Configuration
@Profile("optimized")
@EnableCaching
@RequiredArgsConstructor
public class ResultCacheConfiguration implements CachingConfigurer {

    private static final Duration TTL = Duration.ofMinutes(10);

    private final ObjectMapper objectMapper;

    @Bean
    RedisCacheManager cacheManager(RedisConnectionFactory connectionFactory) {
        JavaType listType = objectMapper.getTypeFactory()
                .constructCollectionType(List.class, ResultResponse.class);

        RedisCacheConfiguration cacheConfig = RedisCacheConfiguration.defaultCacheConfig()
                .entryTtl(TTL)
                .serializeKeysWith(SerializationPair.fromSerializer(new StringRedisSerializer()))
                .serializeValuesWith(SerializationPair.fromSerializer(
                        new Jackson2JsonRedisSerializer<>(objectMapper, listType)));

        return RedisCacheManager.builder(connectionFactory)
                .cacheDefaults(cacheConfig)
                // Pre-declare so Spring Boot's CacheMetricsRegistrar binds cache.gets at startup.
                .withInitialCacheConfigurations(Map.of("result", cacheConfig))
                .enableStatistics()
                .build();
    }

    /** Log one WARN on any Redis error and fall through to the database. */
    @Override
    public CacheErrorHandler errorHandler() {
        return new CacheErrorHandler() {
            @Override
            public void handleCacheGetError(RuntimeException ex, Cache cache, Object key) {
                log.warn("Cache GET error cache={} key={}: {} — falling through to database.",
                        cache.getName(), key, ex.getMessage());
            }

            @Override
            public void handleCachePutError(RuntimeException ex, Cache cache, Object key, Object value) {
                log.warn("Cache PUT error cache={} key={}: {} — result served but not cached.",
                        cache.getName(), key, ex.getMessage());
            }

            @Override
            public void handleCacheEvictError(RuntimeException ex, Cache cache, Object key) {
                log.warn("Cache EVICT error cache={} key={}: {}",
                        cache.getName(), key, ex.getMessage());
            }

            @Override
            public void handleCacheClearError(RuntimeException ex, Cache cache) {
                log.warn("Cache CLEAR error cache={}: {}", cache.getName(), ex.getMessage());
            }
        };
    }
}
