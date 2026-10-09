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
    upload.single("file"),
    (req, res) => ingestionController.uploadResults(req, res)
  );

  router.get("/health", (req, res) => {
    res.status(200).json({ status: "UP", service: "result-ingestion-service" });
  });

  return router;
}
