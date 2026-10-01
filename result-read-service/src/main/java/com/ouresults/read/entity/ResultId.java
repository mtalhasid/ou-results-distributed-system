package com.ouresults.read.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Embeddable;
import lombok.EqualsAndHashCode;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.io.Serializable;

@Embeddable
@Getter
@NoArgsConstructor
@EqualsAndHashCode
public class ResultId implements Serializable {
    @Column(name = "exam_id")
    private String examId;

    @Column(name = "roll_no")
    private String rollNo;

    @Column(name = "semester")
    private short semester;
}
