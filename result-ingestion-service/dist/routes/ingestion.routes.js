"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.createIngestionRouter = createIngestionRouter;
const express_1 = require("express");
const multer_1 = __importDefault(require("multer"));
function createIngestionRouter(ingestionController) {
    const router = (0, express_1.Router)();
    const upload = (0, multer_1.default)({
        storage: multer_1.default.memoryStorage(),
        limits: {
            fileSize: 50 * 1024 * 1024 // 50MB limit
        }
    });
    router.post("/admin/results/upload", upload.single("file"), (req, res) => ingestionController.uploadResults(req, res));
    router.get("/health", (req, res) => {
        res.status(200).json({ status: "UP", service: "result-ingestion-service" });
    });
    return router;
}
//# sourceMappingURL=ingestion.routes.js.map