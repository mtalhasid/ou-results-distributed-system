package com.ouresults.read.entity;

import com.fasterxml.jackson.databind.JsonNode;
import jakarta.persistence.Column;
import jakarta.persistence.EmbeddedId;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import lombok.Getter;
import lombok.NoArgsConstructor;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

import java.math.BigDecimal;

@Entity
@Table(name = "results")
@Getter
@NoArgsConstructor
public class ResultEntity {
    @EmbeddedId
    private ResultId id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "exam_id", insertable = false, updatable = false)
    private ExamEntity exam;

    @Column(name = "college_code")
    private String collegeCode;

    @Column(name = "batch_year")
    private short batchYear;

    @Column(name = "dept_code")
    private String deptCode;

    private String name;

    @Column(name = "father_name")
    private String fatherName;

    private String gender;
    private String course;
    private String medium;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(columnDefinition = "jsonb")
    private JsonNode subjects;

    @Column(name = "result_status")
    private String resultStatus;

    private BigDecimal sgpa;
    private BigDecimal cgpa;
    private boolean published;
}
