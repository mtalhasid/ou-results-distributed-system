package com.ouresults.read.service;

import com.ouresults.read.config.AppProperties;
import com.ouresults.read.config.ShardRoutingConfiguration.ShardContext;
import com.ouresults.read.dto.ResultResponse;
import com.ouresults.read.exception.DatabaseTechnicalFailureException;
import com.ouresults.read.exception.ShardUnavailableException;
import com.ouresults.read.repository.ResultRepository;
import io.github.resilience4j.bulkhead.BulkheadFullException;
import io.github.resilience4j.bulkhead.annotation.Bulkhead;
import io.github.resilience4j.circuitbreaker.CallNotPermittedException;
import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import lombok.RequiredArgsConstructor;
import org.springframework.context.annotation.Profile;
import org.springframework.dao.DataAccessException;
import org.springframework.dao.DataAccessResourceFailureException;
import org.springframework.dao.QueryTimeoutException;
import org.springframework.stereotype.Component;

import java.sql.SQLException;
import java.sql.SQLTimeoutException;
import java.sql.SQLTransientConnectionException;
import java.util.List;

@Component
@Profile("optimized")
@RequiredArgsConstructor
public class ShardDatabaseReader {
    private final ResultRepository resultRepository;
    private final ShardContext shardContext;
    private final AppProperties appProperties;

    @Bulkhead(name = "shard1Database")
    @CircuitBreaker(name = "shard1Database", fallbackMethod = "shard1Fallback")
    public List<ResultResponse> readShard1(String rollNo) {
        return readFromShard("shard1", rollNo);
    }

    @Bulkhead(name = "shard2Database")
    @CircuitBreaker(name = "shard2Database", fallbackMethod = "shard2Fallback")
    public List<ResultResponse> readShard2(String rollNo) {
        return readFromShard("shard2", rollNo);
    }

    private List<ResultResponse> readFromShard(String shard, String rollNo) {
        if (appProperties.demo().failingShard().equals(shard)) {
            throw new DatabaseTechnicalFailureException("Demo database connection failure for " + shard + ".");
        }
        String previous = shardContext.useShard(shard);
        try {
            return resultRepository.findPublishedByRollNo(rollNo).stream()
                    .map(ResultResponse::from)
                    .toList();
        } catch (DataAccessException ex) {
            if (isTechnicalFailure(ex)) {
                throw new DatabaseTechnicalFailureException("Technical database failure for " + shard + ".", ex);
            }
            throw ex;
        } finally {
            shardContext.restore(previous);
        }
    }

    public List<ResultResponse> readFromPrimary(String shard, String rollNo) {
        String previous = shardContext.useShard(shard + "Primary");
        try {
            return resultRepository.findPublishedByRollNo(rollNo).stream()
                    .map(ResultResponse::from)
                    .toList();
        } finally {
            shardContext.restore(previous);
        }
    }

    public List<com.ouresults.read.entity.ResultEntity> fetchExamPageFromPrimary(
            String shard, String examId, int page, int pageSize) {
        String previous = shardContext.useShard(shard + "Primary");
        try {
            return resultRepository.findPublishedByExamId(
                    examId, org.springframework.data.domain.PageRequest.of(page, pageSize));
        } finally {
            shardContext.restore(previous);
        }
    }

    private List<ResultResponse> shard1Fallback(String rollNo, Throwable failure) {
        return handleFallback("shard1", failure);
    }

    private List<ResultResponse> shard2Fallback(String rollNo, Throwable failure) {
        return handleFallback("shard2", failure);
    }

    private List<ResultResponse> handleFallback(String shard, Throwable failure) {
        if (failure instanceof CallNotPermittedException
                || failure instanceof DatabaseTechnicalFailureException
                || failure instanceof BulkheadFullException) {
            throw new ShardUnavailableException(shard, failure);
        }
        if (failure instanceof RuntimeException re) {
            throw re;
        }
        throw new IllegalStateException("Unexpected checked failure during database read.", failure);
    }

    private boolean isTechnicalFailure(DataAccessException ex) {
        if (ex instanceof DataAccessResourceFailureException || ex instanceof QueryTimeoutException) {
            return true;
        }
        for (Throwable cause = ex; cause != null; cause = cause.getCause()) {
            if (cause instanceof SQLTimeoutException
                    || cause instanceof SQLTransientConnectionException
                    || cause instanceof SQLException sql
                    && sql.getSQLState() != null
                    && sql.getSQLState().startsWith("08")) {
                return true;
            }
        }
        return false;
    }
}
