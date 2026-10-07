package com.ouresults.read.config;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.dataformat.yaml.YAMLFactory;
import com.ouresults.read.exception.UnknownCollegeException;
import com.zaxxer.hikari.HikariDataSource;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Primary;
import org.springframework.context.annotation.Profile;
import org.springframework.jdbc.datasource.lookup.AbstractRoutingDataSource;
import org.springframework.stereotype.Component;

import javax.sql.DataSource;
import java.io.IOException;
import java.net.URI;
import java.net.URISyntaxException;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Map;

/**
 * Shard routing: holds the shard map, the per-thread shard selector, and the
 * two profile-specific HikariDataSource beans wired into an AbstractRoutingDataSource.
 */
@Configuration
public class ShardRoutingConfiguration {

    // ── Shard map ────────────────────────────────────────────────────────────

    @Bean
    ShardMap shardMap(@Value("${shard-map-path:/app/config/shard-map.yml}") String path) {
        try (var input = Files.newInputStream(Path.of(path))) {
            var yaml = new ObjectMapper(new YAMLFactory())
                    .readValue(input, ShardMapDocument.class);
            return new ShardMap(Map.copyOf(yaml.colleges()));
        } catch (IOException ex) {
            throw new IllegalStateException("Could not load shard map from " + path, ex);
        }
    }

    private record ShardMapDocument(Map<String, String> colleges) {}

    /**
     * Immutable map of college-code → shard name.
     * Kept as a standalone bean so services can inject it directly.
     */
    public record ShardMap(Map<String, String> colleges) {
        public String shardFor(String collegeCode) {
            String shard = colleges.get(collegeCode);
            if (shard == null) {
                throw new UnknownCollegeException(collegeCode);
            }
            return shard;
        }
    }

    // ── Per-thread shard context ─────────────────────────────────────────────

    @Component
    public static class ShardContext {
        private final ThreadLocal<String> current = new ThreadLocal<>();

        public String currentShard() {
            return current.get();
        }

        public String useShard(String shard) {
            String previous = current.get();
            current.set(shard);
            return previous;
        }

        public void restore(String previous) {
            if (previous == null) {
                current.remove();
            } else {
                current.set(previous);
            }
        }
    }

    // ── Data sources ─────────────────────────────────────────────────────────

    @Bean("shard1DataSource")
    @Profile("naive")
    HikariDataSource shard1Primary(@Value("${SHARD_1_PRIMARY}") String url) {
        return createDataSource(url);
    }

    @Bean("shard2DataSource")
    @Profile("naive")
    HikariDataSource shard2Primary(@Value("${SHARD_2_PRIMARY}") String url) {
        return createDataSource(url);
    }

    @Bean("shard1DataSource")
    @Profile("optimized")
    HikariDataSource shard1Replica(@Value("${SHARD_1_PRIMARY_REPLICA}") String url) {
        return createDataSource(url);
    }

    @Bean("shard2DataSource")
    @Profile("optimized")
    HikariDataSource shard2Replica(@Value("${SHARD_2_PRIMARY_REPLICA}") String url) {
        return createDataSource(url);
    }

    @Bean
    @Primary
    DataSource dataSource(
            @Qualifier("shard1DataSource") DataSource shard1,
            @Qualifier("shard2DataSource") DataSource shard2,
            ShardContext shardContext
    ) {
        var routing = new AbstractRoutingDataSource() {
            @Override
            protected Object determineCurrentLookupKey() {
                return shardContext.currentShard();
            }
        };
        routing.setTargetDataSources(Map.of("shard1", shard1, "shard2", shard2));
        routing.setLenientFallback(false);
        routing.afterPropertiesSet();
        return routing;
    }

    // ── URL parsing ───────────────────────────────────────────────────────────

    private static HikariDataSource createDataSource(String url) {
        URI uri;
        try {
            uri = new URI(url.startsWith("jdbc:") ? url.substring("jdbc:".length()) : url);
        } catch (URISyntaxException ex) {
            throw new IllegalArgumentException("Shard database URL is not a valid PostgreSQL URL", ex);
        }
        if (!"postgresql".equals(uri.getScheme()) || uri.getHost() == null) {
            throw new IllegalArgumentException("Shard database URL must use the PostgreSQL URI format");
        }

        StringBuilder jdbcUrl = new StringBuilder("jdbc:postgresql://").append(uri.getHost());
        if (uri.getPort() >= 0) {
            jdbcUrl.append(':').append(uri.getPort());
        }
        jdbcUrl.append(uri.getRawPath());
        if (uri.getRawQuery() != null) {
            jdbcUrl.append('?').append(uri.getRawQuery());
        }

        var ds = new HikariDataSource();
        ds.setJdbcUrl(jdbcUrl.toString());
        ds.setDriverClassName("org.postgresql.Driver");
        if (uri.getRawUserInfo() != null) {
            String[] creds = uri.getRawUserInfo().split(":", 2);
            if (creds.length != 2) {
                throw new IllegalArgumentException("Shard database URL must include username and password");
            }
            ds.setUsername(URLDecoder.decode(creds[0], StandardCharsets.UTF_8));
            ds.setPassword(URLDecoder.decode(creds[1], StandardCharsets.UTF_8));
        }
        return ds;
    }
}
