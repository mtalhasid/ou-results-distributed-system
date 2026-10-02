# Coding standards

- Use Java 21 and the Spring Boot version already configured for the module. Prefer framework features and established libraries over hand-written infrastructure.
- Use constructor injection only, with Lombok `@RequiredArgsConstructor` and `final` dependencies. Do not use `@Autowired`.
- Use Lombok to remove boilerplate (`@Slf4j`, `@Getter`, and `@Builder` where useful). Do not write getters, setters, `equals`, `hashCode`, or `toString` by hand. Do not use `@Data` on JPA entities.
- Use Java records for DTOs, request and response models, and immutable configuration.
- Bind settings with `@ConfigurationProperties` records annotated with `@Validated`; avoid scattered `@Value` fields. Environment-specific values use `${VAR:default}`.
- Use Jakarta Bean Validation (`@Pattern` and custom constraints) for input validation rather than hand-written validation logic.
- Return errors as RFC 7807 `ProblemDetail` through one central handler.
- Use parameterized SLF4J messages. Include the correlation ID on every application log line; never log secrets or full email addresses.
- Prefer Actuator and built-in Micrometer metrics; add custom counters only when no built-in metric fits.
- Keep classes small and single-purpose. Remove dead code and avoid comments that merely restate the code.
- Whenever a script, port, parameter, or run procedure changes, update `docs/commands.md` in the same change.
