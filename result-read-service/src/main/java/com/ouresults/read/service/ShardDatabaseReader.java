package com.ouresults.read.service;

import com.ouresults.read.config.DemoProperties;
import com.ouresults.read.config.ShardContext;
import com.ouresults.read.dto.ResultResponse;
import com.ouresults.read.repository.ResultRepository;
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
    private final DemoProperties demoProperties;

    @CircuitBreaker(name = "shard1Database", fallbackMethod = "shard1Fallback")
    public List<ResultResponse> readShard1(String rollNo) {
        return readFromShard("shard1", rollNo);
    }

    @CircuitBreaker(name = "shard2Database", fallbackMethod = "shard2Fallback")
    public List<ResultResponse> readShard2(String rollNo) {
        return readFromShard("shard2", rollNo);
    }

    private List<ResultResponse> readFromShard(String shard, String rollNo) {
        if (demoProperties.failingShard().equals(shard)) {
            throw new DatabaseTechnicalFailureException("Demo database connection failure for " + shard + ".");
        }

        String previousShard = shardContext.useShard(shard);
        try {
            return resultRepository.findPublishedByRollNo(rollNo).stream()
                    .map(ResultResponse::from)
                    .toList();
        } catch (DataAccessException exception) {
            if (isTechnicalFailure(exception)) {
                throw new DatabaseTechnicalFailureException(
                        "Technical database failure for " + shard + ".",
                        exception
                );
            }
            throw exception;
        } finally {
            shardContext.restore(previousShard);
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
                || failure instanceof DatabaseTechnicalFailureException) {
            throw new ShardUnavailableException(shard, failure);
        }
        if (failure instanceof RuntimeException runtimeException) {
            throw runtimeException;
        }
        throw new IllegalStateException("Unexpected checked failure during database read.", failure);
    }

    private boolean isTechnicalFailure(DataAccessException exception) {
        if (exception instanceof DataAccessResourceFailureException
                || exception instanceof QueryTimeoutException) {
            return true;
        }
        for (Throwable cause = exception; cause != null; cause = cause.getCause()) {
            if (cause instanceof SQLTimeoutException
                    || cause instanceof SQLTransientConnectionException
                    || cause instanceof SQLException sqlException
                    && sqlException.getSQLState() != null
                    && sqlException.getSQLState().startsWith("08")) {
                return true;
            }
        }
        return false;
    }
}
