package com.ouresults.persistence.consumer;

import com.ouresults.persistence.dto.PublishCommand;
import com.ouresults.persistence.service.ExamPublishService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.stereotype.Component;

@Slf4j
@Component
@RequiredArgsConstructor
public class PublishCommandConsumer {

    private final ExamPublishService publishService;

    @RabbitListener(queues = "results.publish")
    public void consumePublishCommand(PublishCommand command) {
        log.info("Received publish command for examId={} requestedAt={}", command.examId(), command.requestedAt());
        publishService.executePublish(command.examId());
        log.info("Successfully finished processing publish command for examId={}", command.examId());
    }
}
