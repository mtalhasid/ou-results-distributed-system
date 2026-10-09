# Coding Standards & Architecture Guidelines

These standards apply to all services across the repository.

---

## 1. Java & Spring Boot Guidelines (All Java Services)

* **Use Framework Annotations & Established Libraries:** Always prefer native Spring and established libraries over hand-written infrastructure. Never re-invent wheels (e.g., use `@RabbitListener`, `@Transactional`, `@Validated`, `@Repository`, `@Cacheable`, Spring Data JPA). Do not write hundreds of lines of custom synchronization or locking when standard framework annotations exist.
* **Records for DTOs:** All request payloads, response envelopes, DTOs, and immutable configuration properties must be Java `record`s.
* **Dependency Injection:** Use constructor injection only via Lombok `@RequiredArgsConstructor` with `final` fields. Never use `@Autowired`.
* **Lombok for Boilerplate:** Use `@Slf4j`, `@Getter`, and `@Builder` where appropriate. Never write manual getters, setters, or constructors. Do not use `@Data` on JPA entities.
* **Unified API Response Envelope:** Every HTTP response must use `ApiResponse<T>` with `status`, `statusCode`, `message`, and `data`. Provide `@Builder` and standard factory helpers.
* **Centralized Exception Handling:** All exceptions must be routed through a central `@RestControllerAdvice` in the `exception` package returning consistent `ApiResponse` structures.
* **Validation:** Use Jakarta Bean Validation (`@Pattern`, `@NotNull`, `@Size`) directly on controllers with `@Validated`.
* **Logging & Observability:** Include `correlationId` on all logs using MDC and parameterized SLF4J messages. Never log passwords, tokens, or database secrets.

---

## 2. Node.js, Express & TypeScript Guidelines (Ingestion & Account Services)

* **Clear Modular Directory Structure:** Every service must enforce a strict separation of concerns into dedicated directories:
  * `controllers/` - HTTP request handling, response formatting, status codes.
  * `services/` - Core business logic, batching, orchestration.
  * `routes/` - Express router definitions and middleware bindings.
  * `types/` - TypeScript interfaces, type definitions, and DTO types.
  * `utils/` - Shared helper utilities, parsers, and formatters.
  * `config/` - Environment variables, schema maps, and connection clients.
* **Class-Based Architecture:** Do not write loose standalone functions for core handlers. Controllers, services, and publishers must be organized into clean classes (e.g., `IngestionController`, `IngestionService`, `RabbitMqPublisher`) with methods defined inside the class.
* **Single Responsibility Principle:** Each file must do exactly one job. A controller file handles only HTTP interaction; a service file handles only business operations; a route file only maps endpoints.
* **Type Safety & Runtime Validation:** Use TypeScript strict mode and Zod schemas for runtime validation of incoming files and request bodies.
* **Logging:** Use `pino` with JSON formatting, extracting and propagating `X-Correlation-Id` across all logs and message headers.

---

## 3. General Repository Rules

* **No Custom Infrastructure When Libraries Exist:** Do not hand-build infrastructure that a standard framework feature or well-known library already provides. In Spring services, use native messaging listeners, JSON message converters, declarative retry configurations, and dead-letter routing. In Node services, use established libraries (such as amqp-connection-manager, multer, csv-parse, zod, pino) for connection pooling, streaming, validation, and logging instead of writing manual plumbing. If no standard feature exists for something, justify it and keep any custom code minimal.
* **Documentation Alongside Code:** Whenever a script, port, parameter, or run procedure changes, update `docs/getting-started.md` and the root README run section in the same change.
* **Clean Code:** Keep classes small, focused, and single-purpose. Do not commit dead code or boilerplate comments that merely restate what the code does.
