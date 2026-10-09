import amqp, { AmqpConnectionManager, ChannelWrapper } from "amqp-connection-manager";
import { logger } from "./logger";
import { ResultBatchMessage } from "../types/ingestion.types";

export class RabbitMqClient {
  private connection: AmqpConnectionManager;
  private channelWrapper: ChannelWrapper;
  private readonly exchangeName: string;

  constructor(url?: string, exchangeName?: string) {
    const amqpUrl = url || process.env.RABBITMQ_URL || "amqp://guest:guest@localhost:5672";
    this.exchangeName = exchangeName || process.env.RABBITMQ_EXCHANGE || "results.direct";

    this.connection = amqp.connect([amqpUrl]);
    this.connection.on("connect", () => {
      logger.info("RabbitMQ connection established");
    });
    this.connection.on("disconnect", (params) => {
      logger.warn({ err: params.err }, "RabbitMQ connection lost, attempting reconnect");
    });

    this.channelWrapper = this.connection.createChannel({
      json: true,
      setup: async () => {
        // Topology is pre-declared in definitions.json; neither app declares queues
      }
    });
  }

  public async publishBatch(routingKey: string, message: ResultBatchMessage): Promise<void> {
    await this.channelWrapper.publish(this.exchangeName, routingKey, message, {
      contentType: "application/json",
      persistent: true
    });
  }

  public async close(): Promise<void> {
    await this.channelWrapper.close();
    await this.connection.close();
  }
}
