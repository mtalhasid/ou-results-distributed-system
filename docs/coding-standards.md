# Coding standards

- Use Java 21 and the Spring Boot version already configured for the module. Prefer framework features and established libraries over hand-written infrastructure.
- Use constructor injection only, with Lombok `@RequiredArgsConstructor` and `final` dependencies. Do not use `@Autowired`.
- Use Lombok to remove boilerplate (`@Slf4j`, `@Getter`, and `@Builder` where useful). Do not write getters, setters, `equals`, `hashCode`, or `toString` by hand. Do not use `@Data` on JPA entities.
- Use Java records for DTOs, request and response models, and immutable configuration.
- Bind settings with `@ConfigurationProperties` records annotated with `@Validated`; avoid scattered `@Value` fields. Environment-specific values use `${VAR:default}`.
- Use Jakarta Bean Validation (`@Pattern` and custom constraints) for input validation rather than hand-written validation logic. Annotate controllers with `@Validated` and put validation constraints directly on path variables and request parameters.
- **Every response, success and error, uses one envelope record `ApiResponse<T>`** with fields `status` (`"success"` or `"error"`), `statusCode` (the HTTP status code as an integer), `message` (a short human-readable string), and `data` (`null` on errors, the payload on success). Each service defines its own copy of the record; no code is shared between services. The `ProblemDetail` type is not used in responses.
- **All custom exceptions and the single `@RestControllerAdvice` live in an `exception` package.** No `@ExceptionHandler` methods in controllers. One handler maps each exception to an `ApiResponse` with the correct status: unknown college → 400, validation → 400, shard unavailable → 503 with `Retry-After`, unexpected → 500 with a generic message (details in the log only).
- Return errors as `ApiResponse` through the one central `@RestControllerAdvice` handler.
- Use parameterized SLF4J messages. Include the correlation ID on every application log line; never log secrets or full email addresses.
- Prefer Actuator and built-in Micrometer metrics; add custom counters only when no built-in metric fits.
- Keep classes small and single-purpose. Remove dead code and avoid comments that merely restate the code.
- Whenever a script, port, parameter, or run procedure changes, update `docs/commands.md` in the same change.
