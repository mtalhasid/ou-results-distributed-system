import { Readable } from "stream";
import { v4 as uuidv4 } from "uuid";
import { RabbitMqClient } from "../config/rabbitmq";
import { logger } from "../config/logger";
import { CsvParser } from "../utils/csvParser";
import { ExamMetadata, IngestionResult, ResultBatchMessage } from "../types/ingestion.types";

export class IngestionService {
  private readonly rabbitMqClient: RabbitMqClient;
  private readonly batchSize: number;

  constructor(rabbitMqClient: RabbitMqClient, batchSize = 500) {
    this.rabbitMqClient = rabbitMqClient;
    this.batchSize = batchSize;
  }

  public async ingestCsv(
    stream: Readable,
    examOverrides?: { examId?: string; title?: string; resultDate?: string }
  ): Promise<IngestionResult> {
    const parseResult = await CsvParser.parseStream(stream);

    const examId = examOverrides?.examId || parseResult.detectedExamId;
    if (!examId) {
      throw new Error("No exam_id found in CSV and none provided in request");
    }

    const title = examOverrides?.title || `Examination ${examId}`;
    const resultDate = examOverrides?.resultDate || new Date().toISOString().split("T")[0];

    const exam: ExamMetadata = {
      examId,
      title,
      resultDate
    };

    let batchesPublished = 0;
    const uploadedAt = new Date().toISOString();

    for (const [collegeCode, rows] of parseResult.collegeGroups.entries()) {
      for (let i = 0; i < rows.length; i += this.batchSize) {
        const chunk = rows.slice(i, i + this.batchSize);
        const batchMessage: ResultBatchMessage = {
          batchId: uuidv4(),
          examId,
          collegeCode,
          uploadedAt,
          exam,
          rows: chunk
        };

        await this.rabbitMqClient.publishBatch("results.write", batchMessage);
        batchesPublished++;
      }
    }

    logger.info(
      {
        examId,
        totalRows: parseResult.totalRows,
        batchesPublished,
        collegesCount: parseResult.collegeGroups.size
      },
      "Ingestion completed and batches queued successfully"
    );

    return {
      examId,
      totalRows: parseResult.totalRows,
      batchesPublished,
      collegesCount: parseResult.collegeGroups.size
    };
  }
}
