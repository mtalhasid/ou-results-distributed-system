package com.ouresults.persistence.controller;

import com.ouresults.persistence.dto.ApiResponse;
import com.ouresults.persistence.dto.PublishStatusResponse;
import com.ouresults.persistence.service.ExamPublishService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@Slf4j
@RestController
@RequestMapping("/admin/exams")
@RequiredArgsConstructor
public class ExamPublishStatusController {

    private final ExamPublishService publishService;

    @GetMapping("/{examId}/publish-status")
    public ResponseEntity<ApiResponse<PublishStatusResponse>> getPublishStatus(@PathVariable("examId") String examId) {
        log.info("Fetching publish status for examId={}", examId);
        PublishStatusResponse status = publishService.getPublishStatus(examId);
        if ("NOT_FOUND".equals(status.overallStatus())) {
            return ResponseEntity.status(404).body(
                    ApiResponse.error(404, "Exam not found: " + examId)
            );
        }
        return ResponseEntity.ok(
                ApiResponse.success(200, "Publish status retrieved successfully", status)
        );
    }
}
