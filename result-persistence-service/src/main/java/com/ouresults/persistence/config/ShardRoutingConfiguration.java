package com.ouresults.persistence.config;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.dataformat.yaml.YAMLFactory;
import com.zaxxer.hikari.HikariDataSource;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

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
    ShardMap shardMap(@Value("${shard-map-path:contracts/shard-map.yml}") String path) {
        try (var input = Files.newInputStream(Path.of(path))) {
            var yaml = new ObjectMapper(new YAMLFactory())
                    .readValue(input, ShardMapDocument.class);
            return new ShardMap(Map.copyOf(yaml.colleges()));
        } catch (IOException ex) {
            throw new IllegalStateException("Could not load shard map from " + path, ex);
        }
    }

    private record ShardMapDocument(Map<String, String> colleges) {}

    @Bean("shard1DataSource")
    HikariDataSource shard1Primary(@Value("${SHARD_1_PRIMARY}") String url) {
        return createDataSource(url);
    }

    @Bean("shard2DataSource")
    HikariDataSource shard2Primary(@Value("${SHARD_2_PRIMARY}") String url) {
        return createDataSource(url);
    }

    @Bean("shard1TransactionManager")
    PlatformTransactionManager shard1TransactionManager(@Qualifier("shard1DataSource") DataSource dataSource) {
        return new DataSourceTransactionManager(dataSource);
    }

    @Bean("shard2TransactionManager")
    PlatformTransactionManager shard2TransactionManager(@Qualifier("shard2DataSource") DataSource dataSource) {
        return new DataSourceTransactionManager(dataSource);
    }

    @Bean("shard1TransactionTemplate")
    TransactionTemplate shard1TransactionTemplate(@Qualifier("shard1TransactionManager") PlatformTransactionManager tm) {
        return new TransactionTemplate(tm);
    }

    @Bean("shard2TransactionTemplate")
    TransactionTemplate shard2TransactionTemplate(@Qualifier("shard2TransactionManager") PlatformTransactionManager tm) {
        return new TransactionTemplate(tm);
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
