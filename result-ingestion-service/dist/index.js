"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.app = void 0;
const express_1 = __importDefault(require("express"));
const pino_http_1 = __importDefault(require("pino-http"));
const dotenv_1 = __importDefault(require("dotenv"));
const logger_1 = require("./config/logger");
const rabbitmq_1 = require("./config/rabbitmq");
const IngestionService_1 = require("./services/IngestionService");
const IngestionController_1 = require("./controllers/IngestionController");
const ingestion_routes_1 = require("./routes/ingestion.routes");
dotenv_1.default.config();
const port = process.env.PORT ? parseInt(process.env.PORT, 10) : 3000;
const app = (0, express_1.default)();
exports.app = app;
app.use((0, pino_http_1.default)({ logger: logger_1.logger }));
app.use(express_1.default.json());
app.use(express_1.default.urlencoded({ extended: true }));
const rabbitMqClient = new rabbitmq_1.RabbitMqClient();
const ingestionService = new IngestionService_1.IngestionService(rabbitMqClient);
const ingestionController = new IngestionController_1.IngestionController(ingestionService);
app.use((0, ingestion_routes_1.createIngestionRouter)(ingestionController));
const server = app.listen(port, () => {
    logger_1.logger.info(`Result Ingestion Service listening on port ${port}`);
});
const gracefulShutdown = async (signal) => {
    logger_1.logger.info(`Received ${signal}. Shutting down gracefully...`);
    server.close(async () => {
        try {
            await rabbitMqClient.close();
            logger_1.logger.info("RabbitMQ connections closed. Server stopped.");
            process.exit(0);
        }
        catch (err) {
            logger_1.logger.error({ err }, "Error during shutdown");
            process.exit(1);
        }
    });
};
process.on("SIGTERM", () => gracefulShutdown("SIGTERM"));
process.on("SIGINT", () => gracefulShutdown("SIGINT"));
//# sourceMappingURL=index.js.map