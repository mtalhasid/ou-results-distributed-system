import { Request, Response } from "express";
import { Readable } from "stream";
import { IngestionService } from "../services/IngestionService";
import { logger } from "../config/logger";

export class IngestionController {
  private readonly ingestionService: IngestionService;

  constructor(ingestionService: IngestionService) {
    this.ingestionService = ingestionService;
  }

  public async uploadResults(req: Request, res: Response): Promise<void> {
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
      const fileStream = Readable.from(req.file.buffer);

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
    } catch (err: unknown) {
      const errorMessage = err instanceof Error ? err.message : "Unknown error during ingestion";
      logger.error({ err }, "Error processing CSV upload");
      res.status(400).json({
        status: "error",
        statusCode: 400,
        message: errorMessage
      });
    }
  }

  public async publishExam(req: Request, res: Response): Promise<void> {
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
    } catch (err: unknown) {
      const errorMessage = err instanceof Error ? err.message : "Error initiating publication";
      logger.error({ err }, "Error publishing exam");
      res.status(500).json({
        status: "error",
        statusCode: 500,
        message: errorMessage
      });
    }
  }
}
