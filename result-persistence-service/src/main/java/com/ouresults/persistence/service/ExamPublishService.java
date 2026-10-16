package com.ouresults.persistence.service;

import com.ouresults.persistence.dto.PublishStatusResponse;
import com.ouresults.persistence.dto.PublishedEvent;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.dao.EmptyResultDataAccessException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionTemplate;

import javax.sql.DataSource;
import java.time.Instant;
import java.util.UUID;
import java.util.concurrent.TimeUnit;

@Slf4j
@Service
public class ExamPublishService {

    private final JdbcTemplate shard1Jdbc;
    private final JdbcTemplate shard2Jdbc;
    private final TransactionTemplate shard1Tx;
    private final TransactionTemplate shard2Tx;
    private final KafkaTemplate<String, Object> kafkaTemplate;
    private final String failingPublishShard;
    private final boolean demoCrashAfterShardsPublished;
    private final boolean demoFailingKafkaPublish;

    public ExamPublishService(
            @Qualifier("shard1DataSource") DataSource shard1DataSource,
            @Qualifier("shard2DataSource") DataSource shard2DataSource,
            @Qualifier("shard1TransactionTemplate") TransactionTemplate shard1Tx,
            @Qualifier("shard2TransactionTemplate") TransactionTemplate shard2Tx,
            KafkaTemplate<String, Object> kafkaTemplate,
            @Value("${app.demo.failing-publish-shard:none}") String failingPublishShard,
            @Value("${app.demo.crash-after-shards-published:false}") boolean demoCrashAfterShardsPublished,
            @Value("${app.demo.failing-kafka-publish:false}") boolean demoFailingKafkaPublish
    ) {
        this.shard1Jdbc = new JdbcTemplate(shard1DataSource);
        this.shard2Jdbc = new JdbcTemplate(shard2DataSource);
        this.shard1Tx = shard1Tx;
        this.shard2Tx = shard2Tx;
        this.kafkaTemplate = kafkaTemplate;
        this.failingPublishShard = failingPublishShard;
        this.demoCrashAfterShardsPublished = demoCrashAfterShardsPublished;
        this.demoFailingKafkaPublish = demoFailingKafkaPublish;
    }

    public void executePublish(String examId) {
        String s1 = getExamStatus(shard1Jdbc, examId);
        String s2 = getExamStatus(shard2Jdbc, examId);

        if (s1 == null && s2 == null) {
            throw new IllegalStateException("Exam " + examId + " does not exist on any shard.");
        }

        // Idempotency: Already published on both shards
        if ("PUBLISHED".equalsIgnoreCase(s1) && "PUBLISHED".equalsIgnoreCase(s2)) {
            log.info("Exam {} is already PUBLISHED on both shards. Nothing to do.", examId);
            return;
        }

        // Crash recovery: Past the point of no return
        if (isPastPointOfNoReturn(s1, s2)) {
            log.info("Exam {} is past point of no return (shard1={}, shard2={}). Resuming completion without rollback.",
                    examId, s1, s2);
            completePublication(examId);
            return;
        }

        // Step 1: Set status to PUBLISHING on both shards
        shard1Jdbc.update("UPDATE exams SET publish_status = 'PUBLISHING' WHERE exam_id = ? AND publish_status IN ('DRAFT', 'FAILED', 'PUBLISHING')", examId);
        shard2Jdbc.update("UPDATE exams SET publish_status = 'PUBLISHING' WHERE exam_id = ? AND publish_status IN ('DRAFT', 'FAILED', 'PUBLISHING')", examId);
        log.info("Set publish_status to PUBLISHING for exam {} on both shards", examId);

        // Step 2 & 3: Flip rows on both shards
        try {
            if ("shard1".equalsIgnoreCase(failingPublishShard)) {
                throw new IllegalStateException("Simulated failure on shard1 for demo rollback verification");
            }
            int flipped1 = shard1Tx.execute(status ->
                    shard1Jdbc.update("UPDATE results SET published = true WHERE exam_id = ? AND published = false", examId)
            );
            log.info("Flipped {} rows to published=true on Shard 1 for exam {}", flipped1, examId);

            if ("shard2".equalsIgnoreCase(failingPublishShard)) {
                throw new IllegalStateException("Simulated failure on shard2 for demo rollback verification");
            }
            int flipped2 = shard2Tx.execute(status ->
                    shard2Jdbc.update("UPDATE results SET published = true WHERE exam_id = ? AND published = false", examId)
            );
            log.info("Flipped {} rows to published=true on Shard 2 for exam {}", flipped2, examId);

            // Point of no return reached: both shards have their rows flipped!
            shard1Jdbc.update("UPDATE exams SET publish_status = 'SHARDS_PUBLISHED' WHERE exam_id = ?", examId);
            shard2Jdbc.update("UPDATE exams SET publish_status = 'SHARDS_PUBLISHED' WHERE exam_id = ?", examId);
            log.info("POINT OF NO RETURN reached for exam {}: status updated to SHARDS_PUBLISHED on both shards", examId);

            if (demoCrashAfterShardsPublished) {
                log.warn("DEMO CRASH TRIGGERED: Halting JVM immediately past point of no return (SHARDS_PUBLISHED) before Kafka or RabbitMQ ACK.");
                Runtime.getRuntime().halt(137);
            }

        } catch (Exception ex) {
            log.error("Publication failed before point of no return for exam {}. Undoing flips and setting FAILED...", examId, ex);
            rollbackPublish(examId);
            throw new RuntimeException("Publication failed before point of no return: " + ex.getMessage(), ex);
        }

        // Step 4: Emit Kafka event and mark PUBLISHED
        completePublication(examId);
    }

    private boolean isPastPointOfNoReturn(String s1, String s2) {
        return "SHARDS_PUBLISHED".equalsIgnoreCase(s1)
                || "SHARDS_PUBLISHED".equalsIgnoreCase(s2)
                || ("PUBLISHED".equalsIgnoreCase(s1) && !"DRAFT".equalsIgnoreCase(s2))
                || ("PUBLISHED".equalsIgnoreCase(s2) && !"DRAFT".equalsIgnoreCase(s1));
    }

    private void completePublication(String examId) {
        try {
            emitKafkaEvent(examId);
            shard1Jdbc.update("UPDATE exams SET publish_status = 'PUBLISHED' WHERE exam_id = ?", examId);
            shard2Jdbc.update("UPDATE exams SET publish_status = 'PUBLISHED' WHERE exam_id = ?", examId);
            log.info("Exam {} successfully marked PUBLISHED on both shards", examId);
        } catch (Exception ex) {
            log.error("Failed to emit Kafka event or mark PUBLISHED for exam {} (past point of no return). Never rolling back; will retry on redelivery.", examId, ex);
            throw new RuntimeException("Kafka event emission / final status update failed: " + ex.getMessage(), ex);
        }
    }

    private void rollbackPublish(String examId) {
        try {
            shard1Jdbc.update("UPDATE results SET published = false WHERE exam_id = ?", examId);
            shard2Jdbc.update("UPDATE results SET published = false WHERE exam_id = ?", examId);
            shard1Jdbc.update("UPDATE exams SET publish_status = 'FAILED' WHERE exam_id = ?", examId);
            shard2Jdbc.update("UPDATE exams SET publish_status = 'FAILED' WHERE exam_id = ?", examId);
            log.warn("Rolled back publication for exam {}: results set to published=false, exam status set to FAILED on both shards", examId);
        } catch (Exception ex) {
            log.error("Error during rollback for exam {}", examId, ex);
        }
    }

    private void emitKafkaEvent(String examId) throws Exception {
        if (demoFailingKafkaPublish) {
            log.warn("DEMO KAFKA FAILURE TRIGGERED: Simulating Kafka broker outage past point of no return for exam {}", examId);
            throw new IllegalStateException("DEMO: Simulated Kafka cluster outage past point of no return");
        }
        PublishedEvent event = new PublishedEvent(
                "evt-" + UUID.randomUUID(),
                "results.published",
                examId,
                Instant.now()
        );
        log.info("Sending results.published event to Kafka for exam {}", examId);
        // Synchronously wait up to 10s for Kafka broker acknowledgement
        kafkaTemplate.send("results.published", examId, event).get(10, TimeUnit.SECONDS);
        log.info("Kafka event results.published acknowledged by broker for exam {}", examId);
    }

    public PublishStatusResponse getPublishStatus(String examId) {
        PublishStatusResponse.ShardStatus s1 = queryShardStatus(shard1Jdbc, examId);
        PublishStatusResponse.ShardStatus s2 = queryShardStatus(shard2Jdbc, examId);

        String overall = determineOverallStatus(s1.status(), s2.status());

        return new PublishStatusResponse(examId, overall, s1, s2);
    }

    private String determineOverallStatus(String s1, String s2) {
        if ("NOT_FOUND".equals(s1) && "NOT_FOUND".equals(s2)) {
            return "NOT_FOUND";
        }
        if ("PUBLISHED".equals(s1) && "PUBLISHED".equals(s2)) {
            return "PUBLISHED";
        }
        if ("SHARDS_PUBLISHED".equals(s1) && "SHARDS_PUBLISHED".equals(s2)) {
            return "SHARDS_PUBLISHED";
        }
        // If either shard reached SHARDS_PUBLISHED or PUBLISHED, point of no return was reached
        if ("SHARDS_PUBLISHED".equals(s1) || "SHARDS_PUBLISHED".equals(s2)
                || "PUBLISHED".equals(s1) || "PUBLISHED".equals(s2)) {
            return "SHARDS_PUBLISHED";
        }
        if ("PUBLISHING".equals(s1) || "PUBLISHING".equals(s2)) {
            return "PUBLISHING";
        }
        if ("FAILED".equals(s1) || "FAILED".equals(s2)) {
            return "FAILED";
        }
        if ("DRAFT".equals(s1) && "DRAFT".equals(s2)) {
            return "DRAFT";
        }
        return "INCONSISTENT";
    }

    private PublishStatusResponse.ShardStatus queryShardStatus(JdbcTemplate jdbc, String examId) {
        String status = getExamStatus(jdbc, examId);
        if (status == null) {
            return new PublishStatusResponse.ShardStatus("NOT_FOUND", 0, 0);
        }
        Long pubCount = jdbc.queryForObject(
                "SELECT COUNT(*) FROM results WHERE exam_id = ? AND published = true", Long.class, examId);
        Long unpubCount = jdbc.queryForObject(
                "SELECT COUNT(*) FROM results WHERE exam_id = ? AND published = false", Long.class, examId);

        return new PublishStatusResponse.ShardStatus(
                status,
                pubCount != null ? pubCount : 0,
                unpubCount != null ? unpubCount : 0
        );
    }

    private String getExamStatus(JdbcTemplate jdbc, String examId) {
        try {
            return jdbc.queryForObject(
                    "SELECT publish_status FROM exams WHERE exam_id = ?",
                    String.class,
                    examId
            );
        } catch (EmptyResultDataAccessException ex) {
            return null;
        }
    }
}
