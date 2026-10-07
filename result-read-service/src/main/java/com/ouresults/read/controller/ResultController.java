package com.ouresults.read.controller;

import com.ouresults.read.dto.ApiResponse;
import com.ouresults.read.dto.ResultResponse;
import com.ouresults.read.service.ResultReadService;
import jakarta.validation.constraints.Pattern;
import lombok.RequiredArgsConstructor;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@Validated
@RestController
@RequestMapping("/api/results")
@RequiredArgsConstructor
public class ResultController {
    private final ResultReadService resultReadService;

    @GetMapping("/{rollNo}")
    public ApiResponse<List<ResultResponse>> getResults(
            @PathVariable
            @Pattern(regexp = "^\\d{12}$", message = "rollNo must be exactly 12 digits")
            String rollNo
    ) {
        List<ResultResponse> results = resultReadService.findByRollNo(rollNo);
        return ApiResponse.success(200, "Results retrieved successfully.", results);
    }
}
