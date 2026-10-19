# Contributing to OU Results Distributed System

Thank you for your interest in contributing to the **OU Results Distributed Processing System**! We welcome bug fixes, performance optimizations, architectural enhancements, and documentation improvements.

---

## 1. Getting Started & Local Environment

Before making changes, ensure your local environment is configured:

* **Prerequisites:** JDK 21+, Node.js 20+, Docker Desktop, and PowerShell.
* **Environment Setup & Stack Launcher:** Follow the complete local setup, Docker configuration, and service orchestration guide in [docs/getting-started.md](docs/getting-started.md).
* **Architecture & Scenarios:** Familiarize yourself with the system architecture in [docs/system-design.md](docs/system-design.md) and the end-to-end scenarios in [docs/workflow.md](docs/workflow.md).

---

## 2. Contribution Workflow

1. **Fork & Branch:**
   * Fork the repository and create a descriptive branch off `main`:
     ```bash
     git checkout -b feature/your-feature-name
     ```

2. **Build Verification:**
   * Ensure all Java services and the TypeScript ingestion service compile cleanly:
     ```powershell
     .\scripts\build.ps1
     ```

3. **Running Tests:**
   * Execute the relevant test harnesses under `tests/` to verify your changes:
     * Read path & rate limiting: `.\tests\read\run-spike-test.ps1`
     * Write ingestion & resilience: `.\tests\write\upload-smoke.ps1`
     * Saga coordination: `.\tests\publish\publish-happy-path.ps1`
   * For k6 arrival-rate benchmarks, see Section 9 of [docs/getting-started.md](docs/getting-started.md).

4. **Code Guidelines:**
   * **Java Services:** Follow standard Spring Boot 3 idioms. Maintain the CQRS separation (JPA on read models; raw `JdbcTemplate` batching on write models).
   * **TypeScript Service:** Use strict types and stream-based parsing for I/O paths without in-memory buffering.
   * **Documentation:** Keep `docs/` and architecture references up to date if you modify service contracts or workflows.

5. **Submitting a Pull Request:**
   * Push your branch to your fork and submit a PR to `main`.
   * Include a clear summary of your changes, the motivation, and test verification output.

---

## 3. Reporting Issues

* Use GitHub Issues to report bugs or request features.
* Include steps to reproduce, service logs (gateway, read service, or persistence worker), and environment details.
