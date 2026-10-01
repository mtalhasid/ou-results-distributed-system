package com.ouresults.read.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.time.LocalDate;

@Entity
@Table(name = "exams")
@Getter
@NoArgsConstructor
public class ExamEntity {
    @Id
    @Column(name = "exam_id")
    private String examId;

    private String title;

    @Column(name = "result_date")
    private LocalDate resultDate;

    @Column(name = "publish_status")
    private String publishStatus;
}
