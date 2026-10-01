package com.ouresults.read.dto;

import com.fasterxml.jackson.databind.JsonNode;
import com.ouresults.read.entity.ResultEntity;

import java.math.BigDecimal;
import java.time.LocalDate;

public record ResultResponse(
        String examId,
        String title,
        LocalDate resultDate,
        String rollNo,
        short semester,
        String collegeCode,
        short batchYear,
        String deptCode,
        String name,
        String fatherName,
        String gender,
        String course,
        String medium,
        JsonNode subjects,
        String resultStatus,
        BigDecimal sgpa,
        BigDecimal cgpa
) {
    public static ResultResponse from(ResultEntity result) {
        return new ResultResponse(
                result.getId().getExamId(),
                result.getExam().getTitle(),
                result.getExam().getResultDate(),
                result.getId().getRollNo(),
                result.getId().getSemester(),
                result.getCollegeCode(),
                result.getBatchYear(),
                result.getDeptCode(),
                result.getName(),
                result.getFatherName(),
                result.getGender(),
                result.getCourse(),
                result.getMedium(),
                result.getSubjects(),
                result.getResultStatus(),
                result.getSgpa(),
                result.getCgpa()
        );
    }
}
