# Service Discovery (Eureka)

Spring Boot Eureka server on `http://localhost:8761`. The API gateway resolves `lb://result-read-service` through Eureka and round-robins across all registered read instances.

Read instances register automatically when started by the stack launcher. The gateway de-registers an instance when its heartbeat stops.

Start from the repository root ([docs/getting-started.md](../docs/getting-started.md)):

```powershell
.\scripts\start-stack.ps1 -Profile optimized
```

Dashboard: `http://localhost:8761`
