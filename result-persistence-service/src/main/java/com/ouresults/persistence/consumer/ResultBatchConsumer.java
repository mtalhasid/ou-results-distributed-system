package com.ouresults.persistence.consumer;

import com.ouresults.persistence.dto.ResultBatchMessage;
import com.ouresults.persistence.service.ResultBatchPersistenceService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.stereotype.Component;

@Slf4j
@Component
@RequiredArgsConstructor
public class ResultBatchConsumer {

    private final ResultBatchPersistenceService persistenceService;

    @RabbitListener(queues = "results.write")
    public void consumeBatch(ResultBatchMessage message) {
        log.info("Received batch message batchId={} examId={} collegeCode={} rows={}",
                message.batchId(), message.examId(), message.collegeCode(),
                message.rows() != null ? message.rows().size() : 0);
        persistenceService.persistBatch(message);
    }
}
