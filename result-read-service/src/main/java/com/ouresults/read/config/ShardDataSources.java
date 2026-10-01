package com.ouresults.read.config;

import com.zaxxer.hikari.HikariDataSource;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Primary;
import org.springframework.jdbc.datasource.lookup.AbstractRoutingDataSource;

import javax.sql.DataSource;
import java.net.URI;
import java.net.URISyntaxException;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.util.Map;

@Configuration
public class ShardDataSources {
    @Bean("shard1DataSource")
    HikariDataSource shard1DataSource(@Value("${SHARD_1_PRIMARY}") String url) {
        return createDataSource(url);
    }

    @Bean("shard2DataSource")
    HikariDataSource shard2DataSource(@Value("${SHARD_2_PRIMARY}") String url) {
        return createDataSource(url);
    }

    @Bean
    @Primary
    DataSource dataSource(
            @Qualifier("shard1DataSource") DataSource shard1,
            @Qualifier("shard2DataSource") DataSource shard2,
            ShardContext shardContext
    ) {
        var routingDataSource = new AbstractRoutingDataSource() {
            @Override
            protected Object determineCurrentLookupKey() {
                return shardContext.currentShard();
            }
        };
        routingDataSource.setTargetDataSources(Map.of("shard1", shard1, "shard2", shard2));
        routingDataSource.setLenientFallback(false);
        routingDataSource.afterPropertiesSet();
        return routingDataSource;
    }

    private HikariDataSource createDataSource(String url) {
        URI uri;
        try {
            uri = new URI(url.startsWith("jdbc:") ? url.substring("jdbc:".length()) : url);
        } catch (URISyntaxException exception) {
            throw new IllegalArgumentException("Shard database URL is not a valid PostgreSQL URL", exception);
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

        var dataSource = new HikariDataSource();
        dataSource.setJdbcUrl(jdbcUrl.toString());
        dataSource.setDriverClassName("org.postgresql.Driver");
        if (uri.getRawUserInfo() != null) {
            String[] credentials = uri.getRawUserInfo().split(":", 2);
            if (credentials.length != 2) {
                throw new IllegalArgumentException("Shard database URL must include username and password");
            }
            dataSource.setUsername(URLDecoder.decode(credentials[0], StandardCharsets.UTF_8));
            dataSource.setPassword(URLDecoder.decode(credentials[1], StandardCharsets.UTF_8));
        }
        return dataSource;
    }
}
