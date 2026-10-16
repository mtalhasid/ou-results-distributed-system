package com.ouresults.read.controller;

import com.ouresults.read.config.ShardRoutingConfiguration.ShardContext;
import com.ouresults.read.config.ShardRoutingConfiguration.ShardMap;
import com.ouresults.read.dto.ApiResponse;
import com.ouresults.read.dto.ResultResponse;
import com.ouresults.read.repository.ResultRepository;
import com.ouresults.read.service.ShardDatabaseReader;
import jakarta.validation.constraints.Pattern;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@Validated
@RestController
@RequestMapping("/internal/results")
@RequiredArgsConstructor
public class InternalResultController {

    private final ShardMap shardMap;
    private final ObjectProvider<ShardDatabaseReader> shardDatabaseReaderProvider;
    private final ShardContext shardContext;
    private final ResultRepository resultRepository;

    @GetMapping("/{rollNo}")
    public ApiResponse<List<ResultResponse>> getInternalResults(
            @PathVariable
            @Pattern(regexp = "^\\d{12}$", message = "rollNo must be exactly 12 digits")
            String rollNo,
            @RequestParam(name = "consistency", defaultValue = "strong")
            String consistency
    ) {
        String shard = shardMap.shardFor(rollNo.substring(0, 4));
        ShardDatabaseReader reader = shardDatabaseReaderProvider.getIfAvailable();
        List<ResultResponse> results;
        if (reader != null) {
            results = reader.readFromPrimary(shard, rollNo);
        } else {
            String previous = shardContext.useShard(shard + "Primary");
            try {
                results = resultRepository.findPublishedByRollNo(rollNo).stream()
                        .map(ResultResponse::from)
                        .toList();
            } finally {
                shardContext.restore(previous);
            }
        }
        return ApiResponse.<List<ResultResponse>>builder()
                .status("success")
                .statusCode(200)
                .message("Results retrieved successfully from primary shard (strong consistency).")
                .data(results)
                .build();
    }
}
