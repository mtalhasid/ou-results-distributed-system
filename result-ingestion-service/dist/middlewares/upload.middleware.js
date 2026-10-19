"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.handleCsvUpload = void 0;
const multer_1 = __importDefault(require("multer"));
const upload = (0, multer_1.default)({
    storage: multer_1.default.memoryStorage(),
    limits: { fileSize: 50 * 1024 * 1024 } // 50MB
}).single("file");
const handleCsvUpload = (req, res, next) => {
    upload(req, res, (err) => {
        if (err instanceof multer_1.default.MulterError) {
            const message = err.code === "LIMIT_FILE_SIZE"
                ? "File size exceeds the limit of 50MB"
                : err.message;
            return res.status(400).json({ status: "error", statusCode: 400, message, data: null });
        }
        else if (err) {
            return res.status(400).json({ status: "error", statusCode: 400, message: err.message, data: null });
        }
        next();
    });
};
exports.handleCsvUpload = handleCsvUpload;
//# sourceMappingURL=upload.middleware.js.map