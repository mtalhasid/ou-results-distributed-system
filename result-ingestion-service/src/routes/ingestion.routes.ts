import { Router } from "express";
import multer from "multer";
import { IngestionController } from "../controllers/IngestionController";

export function createIngestionRouter(ingestionController: IngestionController): Router {
  const router = Router();

  const upload = multer({
    storage: multer.memoryStorage(),
    limits: {
      fileSize: 50 * 1024 * 1024 // 50MB limit
    }
  });

  router.post(
    "/admin/results/upload",
    (req, res, next) => {
      upload.single("file")(req, res, (err) => {
        if (err instanceof multer.MulterError) {
          if (err.code === "LIMIT_FILE_SIZE") {
            return res.status(400).json({
              status: "error",
              statusCode: 400,
              message: "File size exceeds the limit of 50MB",
              data: null
            });
          }
          return res.status(400).json({
            status: "error",
            statusCode: 400,
            message: err.message,
            data: null
          });
        } else if (err) {
          return res.status(400).json({
            status: "error",
            statusCode: 400,
            message: err.message,
            data: null
          });
        }
        next();
      });
    },
    (req, res) => ingestionController.uploadResults(req, res)
  );

  router.get("/admin/metrics/memory", (req, res) => {
    const mem = process.memoryUsage();
    res.status(200).json({
      status: "success",
      statusCode: 200,
      data: {
        rssMB: parseFloat((mem.rss / (1024 * 1024)).toFixed(2)),
        heapUsedMB: parseFloat((mem.heapUsed / (1024 * 1024)).toFixed(2)),
        heapTotalMB: parseFloat((mem.heapTotal / (1024 * 1024)).toFixed(2))
      }
    });
  });

  router.get("/health", (req, res) => {
    res.status(200).json({ status: "UP", service: "result-ingestion-service" });
  });

  return router;
}
