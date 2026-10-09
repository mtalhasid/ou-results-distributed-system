"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.IngestionService = void 0;
const uuid_1 = require("uuid");
const logger_1 = require("../config/logger");
const csvParser_1 = require("../utils/csvParser");
class IngestionService {
    constructor(rabbitMqClient, batchSize = 500) {
        this.rabbitMqClient = rabbitMqClient;
        this.batchSize = batchSize;
    }
    async ingestCsv(stream, examOverrides) {
        const parseResult = await csvParser_1.CsvParser.parseStream(stream);
        const examId = examOverrides?.examId || parseResult.detectedExamId;
        if (!examId) {
            throw new Error("No exam_id found in CSV and none provided in request");
        }
        const title = examOverrides?.title || `Examination ${examId}`;
        const resultDate = examOverrides?.resultDate || new Date().toISOString().split("T")[0];
        const exam = {
            examId,
            title,
            resultDate
        };
        let batchesPublished = 0;
        const uploadedAt = new Date().toISOString();
        for (const [collegeCode, rows] of parseResult.collegeGroups.entries()) {
            for (let i = 0; i < rows.length; i += this.batchSize) {
                const chunk = rows.slice(i, i + this.batchSize);
                const batchMessage = {
                    batchId: (0, uuid_1.v4)(),
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
        logger_1.logger.info({
            examId,
            totalRows: parseResult.totalRows,
            batchesPublished,
            collegesCount: parseResult.collegeGroups.size
        }, "Ingestion completed and batches queued successfully");
        return {
            examId,
            totalRows: parseResult.totalRows,
            batchesPublished,
            collegesCount: parseResult.collegeGroups.size
        };
    }
}
exports.IngestionService = IngestionService;
//# sourceMappingURL=IngestionService.js.map