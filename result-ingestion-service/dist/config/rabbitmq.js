"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.RabbitMqClient = void 0;
const amqp_connection_manager_1 = __importDefault(require("amqp-connection-manager"));
const logger_1 = require("./logger");
class RabbitMqClient {
    constructor(url, exchangeName) {
        const amqpUrl = url || process.env.RABBITMQ_URL || "amqp://guest:guest@localhost:5672";
        this.exchangeName = exchangeName || process.env.RABBITMQ_EXCHANGE || "results.direct";
        this.connection = amqp_connection_manager_1.default.connect([amqpUrl]);
        this.connection.on("connect", () => {
            logger_1.logger.info("RabbitMQ connection established");
        });
        this.connection.on("disconnect", (params) => {
            logger_1.logger.warn({ err: params.err }, "RabbitMQ connection lost, attempting reconnect");
        });
        this.channelWrapper = this.connection.createChannel({
            json: true,
            setup: async () => {
                // Topology is pre-declared in definitions.json; neither app declares queues
            }
        });
    }
    async publishBatch(routingKey, message) {
        await this.channelWrapper.publish(this.exchangeName, routingKey, message, {
            contentType: "application/json",
            persistent: true
        });
    }
    async close() {
        await this.channelWrapper.close();
        await this.connection.close();
    }
}
exports.RabbitMqClient = RabbitMqClient;
//# sourceMappingURL=rabbitmq.js.map