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
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Map;

@Configuration
public class ShardRoutingConfiguration {

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

    public record ShardMap(Map<String, String> colleges) {
        public String shardFor(String collegeCode) {
            String shard = colleges.get(collegeCode);
            if (shard == null) {
                throw new UnknownCollegeException(collegeCode);
            }
            return shard;
        }
    }

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

    @Bean("shard1PrimaryDataSource")
    @Profile("optimized")
    HikariDataSource shard1PrimaryForOptimized(@Value("${SHARD_1_PRIMARY:${SHARD_1_PRIMARY_REPLICA}}") String url) {
        return createDataSource(url);
    }

    @Bean("shard2PrimaryDataSource")
    @Profile("optimized")
    HikariDataSource shard2PrimaryForOptimized(@Value("${SHARD_2_PRIMARY:${SHARD_2_PRIMARY_REPLICA}}") String url) {
        return createDataSource(url);
    }

    @Bean
    @Primary
    DataSource dataSource(
            @Qualifier("shard1DataSource") DataSource shard1,
            @Qualifier("shard2DataSource") DataSource shard2,
            @org.springframework.beans.factory.annotation.Autowired(required = false) @Qualifier("shard1PrimaryDataSource") DataSource shard1Primary,
            @org.springframework.beans.factory.annotation.Autowired(required = false) @Qualifier("shard2PrimaryDataSource") DataSource shard2Primary,
            ShardContext shardContext
    ) {
        var routing = new AbstractRoutingDataSource() {
            @Override
            protected Object determineCurrentLookupKey() {
                return shardContext.currentShard();
            }
        };
        Map<Object, Object> targets = new java.util.HashMap<>();
        targets.put("shard1", shard1);
        targets.put("shard2", shard2);
        targets.put("shard1Primary", shard1Primary != null ? shard1Primary : shard1);
        targets.put("shard2Primary", shard2Primary != null ? shard2Primary : shard2);
        routing.setTargetDataSources(targets);
        routing.setLenientFallback(false);
        routing.afterPropertiesSet();
        return routing;
    }

    private static HikariDataSource createDataSource(String rawUrl) {
        URI uri = URI.create(rawUrl.startsWith("jdbc:") ? rawUrl.substring(5) : rawUrl);
        int port = uri.getPort() > 0 ? uri.getPort() : 5432;
        String query = uri.getRawQuery() != null ? "?" + uri.getRawQuery() : "";
        String jdbcUrl = "jdbc:postgresql://" + uri.getHost() + ":" + port + uri.getRawPath() + query;

        var ds = new HikariDataSource();
        ds.setJdbcUrl(jdbcUrl);
        ds.setDriverClassName("org.postgresql.Driver");

        if (uri.getRawUserInfo() != null) {
            String[] creds = uri.getRawUserInfo().split(":", 2);
            if (creds.length == 2) {
                ds.setUsername(URLDecoder.decode(creds[0], StandardCharsets.UTF_8));
                ds.setPassword(URLDecoder.decode(creds[1], StandardCharsets.UTF_8));
            }
        }
        return ds;
    }
}
