package com.ouresults.read.service;

import com.ouresults.read.dto.ResultResponse;
import org.springframework.cache.annotation.CachePut;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;

import java.util.List;

@Component
@Profile("optimized")
public class CacheWarmupWriter {

    @CachePut(cacheNames = "result", key = "#rollNo")
    public List<ResultResponse> putInCache(String rollNo, List<ResultResponse> results) {
        return results;
    }
}
