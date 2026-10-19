import { Router } from "express";
import { IngestionController } from "../controllers/IngestionController";
import { handleCsvUpload } from "../middlewares/upload.middleware";

export function createIngestionRouter(
  ingestionController: IngestionController,
): Router {
  const router = Router();

  router.post("/admin/results/upload", handleCsvUpload, (req, res) =>
    ingestionController.uploadResults(req, res),
  );

  router.post("/admin/exams/:examId/publish", (req, res) =>
    ingestionController.publishExam(req, res),
  );

  router.get("/admin/metrics/memory", (_req, res) => {
    const mem = process.memoryUsage();
    res.status(200).json({
      status: "success",
      statusCode: 200,
      data: {
        rssMB: parseFloat((mem.rss / (1024 * 1024)).toFixed(2)),
        heapUsedMB: parseFloat((mem.heapUsed / (1024 * 1024)).toFixed(2)),
        heapTotalMB: parseFloat((mem.heapTotal / (1024 * 1024)).toFixed(2)),
      },
    });
  });

  router.get("/health", (req, res) => {
    res.status(200).json({ status: "UP", service: "result-ingestion-service" });
  });

  return router;
}