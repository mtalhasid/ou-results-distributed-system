package com.ouresults.read.controller;

import com.ouresults.read.config.ShardMap;
import com.ouresults.read.dto.ResultResponse;
import com.ouresults.read.service.ResultReadService;
import com.ouresults.read.service.ShardUnavailableException;
import jakarta.validation.constraints.Pattern;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ProblemDetail;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/api/results")
@RequiredArgsConstructor
public class ResultController {
    private final ResultReadService resultReadService;

    @GetMapping("/{rollNo}")
    public List<ResultResponse> getResults(
            @PathVariable
            @Pattern(regexp = "^\\d{12}$", message = "rollNo must be exactly 12 digits")
            String rollNo
    ) {
        return resultReadService.findByRollNo(rollNo);
    }

    @ExceptionHandler(ShardMap.UnknownCollegeException.class)
    @ResponseStatus(HttpStatus.BAD_REQUEST)
    public ErrorResponse unknownCollege(ShardMap.UnknownCollegeException exception) {
        return new ErrorResponse(exception.getMessage());
    }

    @ExceptionHandler(ShardUnavailableException.class)
    public ResponseEntity<ProblemDetail> shardUnavailable(ShardUnavailableException exception) {
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(
                HttpStatus.SERVICE_UNAVAILABLE,
                "temporarily unavailable, try again shortly"
        );
        return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
                .header(HttpHeaders.RETRY_AFTER, "5")
                .contentType(MediaType.APPLICATION_PROBLEM_JSON)
                .body(problem);
    }

    public record ErrorResponse(String message) {}
}
