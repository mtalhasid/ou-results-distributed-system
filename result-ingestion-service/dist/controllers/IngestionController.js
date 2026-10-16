"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.IngestionController = void 0;
const stream_1 = require("stream");
const logger_1 = require("../config/logger");
class IngestionController {
    constructor(ingestionService) {
        this.ingestionService = ingestionService;
    }
    async uploadResults(req, res) {
        try {
            if (!req.file) {
                res.status(400).json({
                    status: "error",
                    statusCode: 400,
                    message: "No CSV file provided in the request (expected form field 'file')"
                });
                return;
            }
            const { examId, title, resultDate } = req.body;
            const fileStream = stream_1.Readable.from(req.file.buffer);
            const result = await this.ingestionService.ingestCsv(fileStream, {
                examId: examId ? String(examId).trim() : undefined,
                title: title ? String(title).trim() : undefined,
                resultDate: resultDate ? String(resultDate).trim() : undefined
            });
            res.status(200).json({
                status: "success",
                statusCode: 200,
                message: "Results uploaded and queued successfully",
                data: result
            });
        }
        catch (err) {
            const errorMessage = err instanceof Error ? err.message : "Unknown error during ingestion";
            logger_1.logger.error({ err }, "Error processing CSV upload");
            res.status(400).json({
                status: "error",
                statusCode: 400,
                message: errorMessage
            });
        }
    }
    async publishExam(req, res) {
        try {
            const examId = req.params.examId ? String(req.params.examId).trim() : "";
            if (!examId) {
                res.status(400).json({
                    status: "error",
                    statusCode: 400,
                    message: "Exam ID must be provided in URL path"
                });
                return;
            }
            await this.ingestionService.publishExam(examId);
            res.status(200).json({
                status: "success",
                statusCode: 200,
                message: `Publication procedure initiated for examination ${examId}`,
                data: {
                    examId,
                    status: "PUBLISHING"
                }
            });
        }
        catch (err) {
            const errorMessage = err instanceof Error ? err.message : "Error initiating publication";
            logger_1.logger.error({ err }, "Error publishing exam");
            res.status(500).json({
                status: "error",
                statusCode: 500,
                message: errorMessage
            });
        }
    }
}
exports.IngestionController = IngestionController;
//# sourceMappingURL=IngestionController.js.map