package com.ouresults.persistence.service;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.ouresults.persistence.config.ShardMap;
import com.ouresults.persistence.dto.ExamDto;
import com.ouresults.persistence.dto.ResultBatchMessage;
import com.ouresults.persistence.dto.ResultRowDto;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionTemplate;

import javax.sql.DataSource;
import java.sql.PreparedStatement;
import java.sql.SQLException;
import java.sql.Timestamp;
import java.util.List;

@Slf4j
@Service
public class ResultBatchPersistenceService {

    private static final String UPSERT_EXAM_SQL = """
            INSERT INTO exams (exam_id, title, result_date, publish_status)
            VALUES (?, ?, ?, 'DRAFT')
            ON CONFLICT (exam_id) DO NOTHING
            """;

    private static final String UPSERT_RESULTS_SQL = """
            INSERT INTO results (
                exam_id, roll_no, semester, college_code, batch_year, dept_code,
                name, father_name, gender, course, medium, subjects,
                result_status, sgpa, cgpa, published, uploaded_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?::jsonb, ?, ?, ?, false, ?)
            ON CONFLICT (exam_id, roll_no, semester)
            DO UPDATE SET
                college_code = EXCLUDED.college_code,
                batch_year = EXCLUDED.batch_year,
                dept_code = EXCLUDED.dept_code,
                name = EXCLUDED.name,
                father_name = EXCLUDED.father_name,
                gender = EXCLUDED.gender,
                course = EXCLUDED.course,
                medium = EXCLUDED.medium,
                subjects = EXCLUDED.subjects,
                result_status = EXCLUDED.result_status,
                sgpa = EXCLUDED.sgpa,
                cgpa = EXCLUDED.cgpa,
                uploaded_at = EXCLUDED.uploaded_at
            WHERE EXCLUDED.uploaded_at > results.uploaded_at
            """;

    private final ShardMap shardMap;
    private final JdbcTemplate shard1JdbcTemplate;
    private final JdbcTemplate shard2JdbcTemplate;
    private final TransactionTemplate shard1TransactionTemplate;
    private final TransactionTemplate shard2TransactionTemplate;
    private final ObjectMapper objectMapper;

    public ResultBatchPersistenceService(
            ShardMap shardMap,
            @Qualifier("shard1DataSource") DataSource shard1DataSource,
            @Qualifier("shard2DataSource") DataSource shard2DataSource,
            @Qualifier("shard1TransactionTemplate") TransactionTemplate shard1TransactionTemplate,
            @Qualifier("shard2TransactionTemplate") TransactionTemplate shard2TransactionTemplate,
            ObjectMapper objectMapper
    ) {
        this.shardMap = shardMap;
        this.shard1JdbcTemplate = new JdbcTemplate(shard1DataSource);
        this.shard2JdbcTemplate = new JdbcTemplate(shard2DataSource);
        this.shard1TransactionTemplate = shard1TransactionTemplate;
        this.shard2TransactionTemplate = shard2TransactionTemplate;
        this.objectMapper = objectMapper;
    }

    public void persistBatch(ResultBatchMessage message) {
        if (message.rows() == null || message.rows().isEmpty()) {
            log.info("Batch {} is empty, skipping persistence.", message.batchId());
            return;
        }

        if (message.exam() != null) {
            ensureExamExistsOnBothShards(message.exam());
        }

        String shard = shardMap.shardFor(message.collegeCode());
        JdbcTemplate targetJdbc = "shard1".equalsIgnoreCase(shard) ? shard1JdbcTemplate : shard2JdbcTemplate;
        TransactionTemplate targetTx = "shard1".equalsIgnoreCase(shard) ? shard1TransactionTemplate : shard2TransactionTemplate;

        List<ResultRowDto> rows = message.rows();
        Timestamp uploadedAtTs = Timestamp.from(message.uploadedAt());

        targetTx.executeWithoutResult(status -> {
            targetJdbc.batchUpdate(UPSERT_RESULTS_SQL, rows, rows.size(), (PreparedStatement ps, ResultRowDto row) -> {
                if ("FORCE_TRANSACTION_FAILURE".equals(row.name())) {
                    throw new IllegalStateException("Simulated mid-batch failure for atomicity verification");
                }
                try {
                    ps.setString(1, message.examId());
                    ps.setString(2, row.rollNo());
                    ps.setShort(3, row.semester());
                    ps.setString(4, row.collegeCode());
                    ps.setShort(5, row.batchYear());
                    ps.setString(6, row.deptCode());
                    ps.setString(7, row.name());
                    ps.setString(8, row.fatherName());
                    ps.setString(9, row.gender());
                    ps.setString(10, row.course());
                    ps.setString(11, row.medium());
                    ps.setString(12, objectMapper.writeValueAsString(row.subjects()));
                    ps.setString(13, row.resultStatus());
                    ps.setBigDecimal(14, row.sgpa());
                    ps.setBigDecimal(15, row.cgpa());
                    ps.setTimestamp(16, uploadedAtTs);
                } catch (JsonProcessingException e) {
                    throw new SQLException("Error serializing subjects jsonb", e);
                }
            });
        });

        log.info("Persisted batch batchId={} examId={} collegeCode={} shard={} count={}",
                message.batchId(), message.examId(), message.collegeCode(), shard, rows.size());
    }

    private void ensureExamExistsOnBothShards(ExamDto exam) {
        shard1JdbcTemplate.update(UPSERT_EXAM_SQL, exam.examId(), exam.title(), exam.resultDate());
        shard2JdbcTemplate.update(UPSERT_EXAM_SQL, exam.examId(), exam.title(), exam.resultDate());
    }
}
