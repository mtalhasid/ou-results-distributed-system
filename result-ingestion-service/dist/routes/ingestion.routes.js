"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.createIngestionRouter = createIngestionRouter;
const express_1 = require("express");
const upload_middleware_1 = require("../middlewares/upload.middleware");
function createIngestionRouter(ingestionController) {
    const router = (0, express_1.Router)();
    router.post("/admin/results/upload", upload_middleware_1.handleCsvUpload, (req, res) => ingestionController.uploadResults(req, res));
    router.post("/admin/exams/:examId/publish", (req, res) => ingestionController.publishExam(req, res));
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
//# sourceMappingURL=ingestion.routes.js.map