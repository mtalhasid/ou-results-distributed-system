import express from "express";
import pinoHttp from "pino-http";
import dotenv from "dotenv";
import { logger } from "./config/logger";
import { RabbitMqClient } from "./config/rabbitmq";
import { IngestionService } from "./services/IngestionService";
import { IngestionController } from "./controllers/IngestionController";
import { createIngestionRouter } from "./routes/ingestion.routes";

dotenv.config();

const port = process.env.PORT ? parseInt(process.env.PORT, 10) : 3000;
const app = express();

app.use(pinoHttp({ logger }));
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

const rabbitMqClient = new RabbitMqClient();
const ingestionService = new IngestionService(rabbitMqClient);
const ingestionController = new IngestionController(ingestionService);

app.use(createIngestionRouter(ingestionController));

const server = app.listen(port, () => {
  logger.info(`Result Ingestion Service listening on port ${port}`);
});

const gracefulShutdown = async (signal: string) => {
  logger.info(`Received ${signal}. Shutting down gracefully...`);
  server.close(async () => {
    try {
      await rabbitMqClient.close();
      logger.info("RabbitMQ connections closed. Server stopped.");
      process.exit(0);
    } catch (err) {
      logger.error({ err }, "Error during shutdown");
      process.exit(1);
    }
  });
};

process.on("SIGTERM", () => gracefulShutdown("SIGTERM"));
process.on("SIGINT", () => gracefulShutdown("SIGINT"));

export { app };
