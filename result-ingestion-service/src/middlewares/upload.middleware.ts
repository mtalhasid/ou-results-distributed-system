import multer from "multer";
import { Request, Response, NextFunction } from "express";

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 50 * 1024 * 1024 } // 50MB
}).single("file");

export const handleCsvUpload = (req: Request, res: Response, next: NextFunction) => {
  upload(req, res, (err) => {
    if (err instanceof multer.MulterError) {
      const message = err.code === "LIMIT_FILE_SIZE" 
        ? "File size exceeds the limit of 50MB" 
        : err.message;
      return res.status(400).json({ status: "error", statusCode: 400, message, data: null });
    } else if (err) {
      return res.status(400).json({ status: "error", statusCode: 400, message: err.message, data: null });
    }
    next();
  });
};