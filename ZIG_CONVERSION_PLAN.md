# K7/Katakate: Python to Zig Conversion Plan - COMPREHENSIVE 30-POINT SPECIFICATION

**Project:** Katakate (K7) - Secure VM Sandbox Orchestration System
**Current Stack:** Python (FastAPI, Typer, Kubernetes client, Rich, Typer)
**Target Stack:** Zig (native compiled, zero-cost abstractions, manual memory management)
**Estimated Effort:** 6-12 months (1-2 full-time developers)
**Current Codebase:** ~3000+ lines Python across 9 source files
**Target:** High-performance, memory-safe, sub-10MB binary

---

## Overview

This document outlines a comprehensive **30-POINT DETAILED PLAN** to convert the entire K7 project from Python to Zig. This plan has been expanded from the original 20-point version to include granular implementation details for each component. Zig is a systems programming language that provides:
- **Performance:** Native compiled code with zero-cost abstractions, 10x faster startup, 5x lower memory usage
- **Safety:** Compile-time memory safety without garbage collection, zero null pointers
- **Control:** Manual memory management with allocators, predictable performance
- **Simplicity:** No hidden control flow, clear error handling via error unions, explicit everything

---

## Phase 1: Foundation & Infrastructure (Points 1-5)

### 1. Set Up Zig Development Environment & Build System

**Tasks:**
- Install Zig compiler (latest stable: 0.13.0 or newer)
- Create `build.zig` build script with targets:
  - `k7-cli` - Command-line interface binary
  - `k7-api` - HTTP API server binary
  - `libk7core` - Core business logic library
  - `libk7sdk` - C-compatible SDK for language bindings
- Set up directory structure:
  ```
  src/
    ├── cli/           # CLI application
    ├── api/           # HTTP API server
    ├── core/          # Core business logic
    ├── sdk/           # Client SDK
    ├── kubernetes/    # Kubernetes client library
    └── common/        # Shared utilities
  ```
- Configure build modes (Debug, ReleaseSafe, ReleaseFast, ReleaseSmall)
- Set up cross-compilation for amd64 Linux targets

**Dependencies:**
- Zig compiler toolchain
- Build configuration for static/dynamic linking

**Deliverables:**
- Working `build.zig` with all targets
- Documented build instructions
- CI/CD integration for Zig builds

---

### 2. Implement Core Data Structures & Models

**Tasks:**
- Convert Python models to Zig structs:
  - `SandboxConfig` - Sandbox configuration
  - `SandboxInfo` - Sandbox status information
  - `ExecResult` - Command execution results
  - `OperationResult` - Generic operation results
- Implement serialization/deserialization:
  - JSON parsing (use `std.json`)
  - YAML parsing (find or create Zig YAML library)
- Create memory-safe string handling utilities
- Implement resource limit types (CPU, memory, storage)
- Add validation functions for all data structures

**Key Considerations:**
- Use Zig's allocators for dynamic memory
- Implement `deinit()` methods for cleanup
- Use tagged unions for variant types
- Leverage compile-time type checking

**Deliverables:**
- `src/core/models.zig` with all data structures
- Unit tests for serialization/deserialization
- Documentation for each struct

---

### 3. Build Kubernetes Client Library in Zig

**Tasks:**
- Research existing Zig Kubernetes clients (or build from scratch)
- Implement Kubernetes API client:
  - HTTP client with TLS support (use `std.http.Client`)
  - Kubeconfig parsing (YAML)
  - Authentication (bearer tokens, client certificates)
  - In-cluster config support
- Implement Kubernetes resource clients:
  - `AppsV1Api` - Deployments
  - `CoreV1Api` - Pods, Secrets, Services
  - `NetworkingV1Api` - NetworkPolicies
  - `CustomObjectsApi` - Metrics API
- Implement Kubernetes watch/stream functionality:
  - WebSocket or chunked transfer support for `kubectl exec` equivalent
  - Event streaming for pod status changes
- Error handling with Kubernetes API error types

**Key APIs to Implement:**
```zig
// Example structure
const KubernetesClient = struct {
    allocator: std.mem.Allocator,
    config: KubeConfig,
    http_client: std.http.Client,

    pub fn init(allocator: std.mem.Allocator, config_path: ?[]const u8) !KubernetesClient
    pub fn deinit(self: *KubernetesClient) void

    // Deployment operations
    pub fn createDeployment(self: *KubernetesClient, namespace: []const u8, deployment: Deployment) !void
    pub fn deleteDeployment(self: *KubernetesClient, namespace: []const u8, name: []const u8) !void
    pub fn listDeployments(self: *KubernetesClient, namespace: ?[]const u8) ![]Deployment

    // Pod operations
    pub fn listPods(self: *KubernetesClient, namespace: []const u8, label_selector: []const u8) ![]Pod
    pub fn execCommand(self: *KubernetesClient, namespace: []const u8, pod: []const u8, command: []const []const u8) !ExecResult

    // NetworkPolicy operations
    pub fn createNetworkPolicy(self: *KubernetesClient, namespace: []const u8, policy: NetworkPolicy) !void

    // Secret operations
    pub fn createSecret(self: *KubernetesClient, namespace: []const u8, secret: Secret) !void
};
```

**Challenges:**
- Kubernetes API is complex and verbose
- Need streaming support for exec
- TLS certificate handling
- Watch API for real-time updates

**Deliverables:**
- `src/kubernetes/client.zig` - Main Kubernetes client
- `src/kubernetes/models.zig` - Kubernetes resource models
- `src/kubernetes/config.zig` - Kubeconfig parsing
- Integration tests with real/mock K8s cluster

---

### 4. Create HTTP Client for SDK & API Communication

**Tasks:**
- Implement HTTP/HTTPS client using `std.http.Client`
- Add TLS certificate validation
- Implement request/response handling:
  - JSON serialization/deserialization
  - Custom headers (X-API-Key, Authorization)
  - Query parameters
  - Request timeouts
- Connection pooling and reuse
- Error handling for network failures
- Retry logic with exponential backoff

**SDK Client Structure:**
```zig
const K7Client = struct {
    allocator: std.mem.Allocator,
    base_url: []const u8,
    api_key: []const u8,
    http_client: std.http.Client,
    verify_ssl: bool,

    pub fn init(allocator: std.mem.Allocator, endpoint: []const u8, api_key: []const u8) !K7Client
    pub fn deinit(self: *K7Client) void

    pub fn create(self: *K7Client, config: SandboxConfig) !SandboxProxy
    pub fn list(self: *K7Client, namespace: ?[]const u8) ![]SandboxInfo
    pub fn delete(self: *K7Client, name: []const u8, namespace: []const u8) !void
    pub fn exec(self: *K7Client, name: []const u8, command: []const u8, namespace: []const u8) !ExecResult
};
```

**Deliverables:**
- `src/sdk/client.zig` - Client SDK implementation
- `src/common/http.zig` - Shared HTTP utilities
- Unit tests for HTTP operations
- Example client usage code

---

### 5. Implement CLI Application (Replace Typer)

**Tasks:**
- Create argument parsing using Zig's standard library or `zig-clap`
- Implement CLI commands:
  - `k7 install` - Install K7 on nodes (Ansible execution)
  - `k7 create` - Create sandbox from YAML config
  - `k7 list` - List sandboxes
  - `k7 delete <name>` - Delete specific sandbox
  - `k7 delete-all` - Delete all sandboxes
  - `k7 shell <name>` - Interactive shell in sandbox
  - `k7 start-api` - Start API server
  - `k7 stop-api` - Stop API server
  - `k7 api-status` - Check API status
  - `k7 generate-api-key <name>` - Generate API key
  - `k7 list-api-keys` - List API keys
  - `k7 revoke-api-key <name>` - Revoke API key
  - `k7 get-api-endpoint` - Get API endpoint
- Implement rich terminal output:
  - Progress bars (replace Rich library)
  - Colored output
  - Tables
  - Spinners
- YAML config file parsing
- Error messages and help text
- Interactive prompts for confirmation

**CLI Argument Structure:**
```zig
const CliArgs = struct {
    command: Command,
    flags: Flags,

    const Command = union(enum) {
        create: CreateArgs,
        list: ListArgs,
        delete: DeleteArgs,
        install: InstallArgs,
        // ... more commands
    };
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();
    const args = try CliArgs.parse(allocator);
    defer args.deinit();

    try executeCommand(allocator, args);
}
```

**Deliverables:**
- `src/cli/main.zig` - CLI entry point
- `src/cli/commands/` - Individual command implementations
- `src/common/terminal.zig` - Terminal utilities (colors, progress)
- Man pages and help documentation

---

## Phase 2: Core Business Logic (Points 6-10)

### 6. Port K7Core Business Logic

**Tasks:**
- Convert `src/k7/core/core.py` to `src/core/core.zig`
- Implement all core functions:
  - `createSandbox()` - Create sandbox with Kubernetes resources
  - `listSandboxes()` - List all sandboxes
  - `deleteSandbox()` - Delete sandbox and resources
  - `deleteAllSandboxes()` - Bulk delete
  - `execCommand()` - Execute commands in sandbox
  - `getSandboxMetrics()` - Get resource usage metrics
  - `installNode()` - Install K7 via Ansible
- Implement security features:
  - Container security context (capability dropping, non-root)
  - Network policy creation (egress/ingress rules)
  - Secret management
  - Resource limits enforcement
- Progress callback system for long-running operations
- Readiness probe checking
- Before-script execution handling

**Core Module Structure:**
```zig
const K7Core = struct {
    allocator: std.mem.Allocator,
    kube_client: KubernetesClient,
    config_loaded: bool,

    pub fn init(allocator: std.mem.Allocator, kubeconfig_path: ?[]const u8) !K7Core
    pub fn deinit(self: *K7Core) void

    pub fn createSandbox(
        self: *K7Core,
        config: SandboxConfig,
        progress_callback: ?*const fn(ProgressEvent) void
    ) !OperationResult

    pub fn listSandboxes(self: *K7Core, namespace: ?[]const u8) ![]SandboxInfo
    pub fn deleteSandbox(self: *K7Core, name: []const u8, namespace: []const u8) !OperationResult
    pub fn execCommand(self: *K7Core, sandbox_name: []const u8, command: []const u8, namespace: []const u8) !ExecResult
    pub fn getSandboxMetrics(self: *K7Core, namespace: ?[]const u8) ![]MetricInfo
    pub fn installNode(self: *K7Core, playbook: ?[]const u8, inventory: ?[]const u8, verbose: bool) !OperationResult
};
```

**Deliverables:**
- `src/core/core.zig` - Core business logic
- `src/core/security.zig` - Security context builders
- `src/core/network.zig` - Network policy utilities
- Integration tests with mocked Kubernetes API

---

### 7. Implement Subprocess Management (Ansible Execution)

**Tasks:**
- Replace Python's `subprocess.Popen` with Zig's `std.ChildProcess`
- Implement Ansible playbook execution:
  - Process spawning and monitoring
  - Real-time stdout/stderr streaming
  - Progress parsing from Ansible output
  - ANSI escape sequence handling
  - Process timeout handling
- Temporary file management for playbooks/inventory
- Environment variable passing
- Signal handling (SIGTERM, SIGKILL)

**Subprocess Module:**
```zig
const AnsibleRunner = struct {
    allocator: std.mem.Allocator,

    pub fn runPlaybook(
        self: *AnsibleRunner,
        playbook_content: []const u8,
        inventory_content: []const u8,
        verbose: bool,
        progress_callback: ?*const fn(ProgressEvent) void
    ) !OperationResult {
        // Create temp files
        const playbook_path = try createTempFile(self.allocator, playbook_content);
        defer deleteTempFile(playbook_path);

        const inventory_path = try createTempFile(self.allocator, inventory_content);
        defer deleteTempFile(inventory_path);

        // Build command
        var argv = std.ArrayList([]const u8).init(self.allocator);
        defer argv.deinit();

        try argv.append("ansible-playbook");
        try argv.append("-i");
        try argv.append(inventory_path);
        try argv.append(playbook_path);
        if (verbose) try argv.append("-v");

        // Execute with streaming output
        var child = std.ChildProcess.init(argv.items, self.allocator);
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;

        try child.spawn();

        // Read output and parse progress
        // ... (streaming and parsing logic)

        const result = try child.wait();
        return if (result.Exited == 0)
            OperationResult{ .success = true, .message = "Installation completed" }
        else
            OperationResult{ .success = false, .error = "Installation failed" };
    }
};
```

**Deliverables:**
- `src/core/ansible.zig` - Ansible execution module
- `src/common/process.zig` - Process utilities
- Tests for process execution and parsing

---

### 8. Create HTTP API Server (Replace FastAPI)

**Tasks:**
- Implement HTTP server using `std.http.Server` or `zap` library
- Create REST API endpoints:
  - `GET /` - Root endpoint (version info)
  - `GET /health` - Health check
  - `POST /api/v1/sandboxes` - Create sandbox
  - `GET /api/v1/sandboxes` - List sandboxes
  - `GET /api/v1/sandboxes/{name}` - Get sandbox details
  - `DELETE /api/v1/sandboxes/{name}` - Delete sandbox
  - `DELETE /api/v1/sandboxes` - Delete all sandboxes
  - `POST /api/v1/sandboxes/{name}/exec` - Execute command
  - `GET /api/v1/sandboxes/metrics` - Get metrics
  - `POST /api/v1/install` - Install on nodes
- Implement middleware:
  - API key authentication (X-API-Key, Authorization: Bearer)
  - CORS headers
  - Request logging
  - Error handling
- Request/response JSON handling
- Route parameter parsing
- Query parameter parsing
- Concurrent request handling (async I/O)

**API Server Structure:**
```zig
const K7ApiServer = struct {
    allocator: std.mem.Allocator,
    core: K7Core,
    address: std.net.Address,
    server: std.http.Server,
    api_keys: ApiKeyStore,

    pub fn init(allocator: std.mem.Allocator, port: u16) !K7ApiServer
    pub fn deinit(self: *K7ApiServer) void

    pub fn start(self: *K7ApiServer) !void {
        std.log.info("Starting API server on port {d}", .{self.address.getPort()});

        while (true) {
            // Accept connections
            var res = try self.server.accept(.{
                .allocator = self.allocator,
            });
            defer res.deinit();

            // Handle request
            try self.handleRequest(&res);
        }
    }

    fn handleRequest(self: *K7ApiServer, res: *std.http.Server.Response) !void {
        // Route matching
        const path = res.request.target;
        const method = res.request.method;

        // Authenticate (except health endpoints)
        if (!isPublicEndpoint(path)) {
            const api_key = try extractApiKey(&res.request);
            if (!try self.verifyApiKey(api_key)) {
                return sendError(res, 401, "Unauthorized", "Invalid API key");
            }
        }

        // Route to handlers
        if (method == .GET and std.mem.eql(u8, path, "/health")) {
            return handleHealth(res);
        } else if (method == .POST and std.mem.startsWith(u8, path, "/api/v1/sandboxes")) {
            return self.handleCreateSandbox(res);
        }
        // ... more routes
    }
};
```

**Deliverables:**
- `src/api/server.zig` - HTTP server implementation
- `src/api/routes/` - Route handlers
- `src/api/auth.zig` - Authentication middleware
- `src/api/responses.zig` - Response formatting
- API documentation (OpenAPI spec)

---

### 9. Implement API Key Management & Authentication

**Tasks:**
- Convert API key storage from Python to Zig
- Implement cryptographic functions:
  - Replace SHA256 with bcrypt or Argon2 for key hashing
  - Use `std.crypto` for secure hashing
  - Timing-attack resistant comparison
- API key CRUD operations:
  - Generate keys with cryptographically secure random
  - Store keys in JSON file with 0600 permissions
  - Load/save keys with file locking
  - Expiry checking
  - Last-used timestamp updates
- File I/O with proper error handling
- Thread-safe access to key store

**API Key Module:**
```zig
const ApiKeyStore = struct {
    allocator: std.mem.Allocator,
    file_path: []const u8,
    keys: std.StringHashMap(ApiKeyData),
    mutex: std.Thread.Mutex,

    const ApiKeyData = struct {
        name: []const u8,
        hash: []const u8,
        created: i64,
        expires: ?i64,
        last_used: ?i64,
    };

    pub fn init(allocator: std.mem.Allocator, file_path: []const u8) !ApiKeyStore
    pub fn deinit(self: *ApiKeyStore) void

    pub fn generateKey(self: *ApiKeyStore, name: []const u8, expires_days: u32) ![]const u8 {
        // Generate cryptographically secure random key
        var key_bytes: [32]u8 = undefined;
        std.crypto.random.bytes(&key_bytes);
        const key = try std.base64.url_safe.Encoder.encode(self.allocator, &key_bytes);

        // Hash with Argon2
        const hash = try hashApiKey(self.allocator, key);

        // Store
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.keys.put(hash, .{
            .name = try self.allocator.dupe(u8, name),
            .hash = hash,
            .created = std.time.timestamp(),
            .expires = if (expires_days > 0) std.time.timestamp() + (expires_days * 86400) else null,
            .last_used = null,
        });

        try self.save();
        return key;
    }

    pub fn verifyKey(self: *ApiKeyStore, key: []const u8) !bool {
        const hash = try hashApiKey(self.allocator, key);
        defer self.allocator.free(hash);

        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.keys.get(hash)) |data| {
            // Check expiry
            if (data.expires) |exp| {
                if (std.time.timestamp() > exp) return false;
            }

            // Update last used
            var mutable_data = data;
            mutable_data.last_used = std.time.timestamp();
            try self.keys.put(hash, mutable_data);
            try self.save();

            return true;
        }
        return false;
    }

    fn hashApiKey(allocator: std.mem.Allocator, key: []const u8) ![]const u8 {
        // Use Argon2 instead of SHA256
        // Implementation depends on available crypto library
    }
};
```

**Security Improvements:**
- Replace SHA256 with Argon2id or bcrypt
- Implement rate limiting for auth attempts
- Add audit logging for key usage
- Secure memory wiping for sensitive data

**Deliverables:**
- `src/api/apikey.zig` - API key management
- `src/common/crypto.zig` - Cryptographic utilities
- Unit tests for key generation and verification
- Migration tool from old Python format

---

### 10. Add Error Handling & Logging

**Tasks:**
- Implement comprehensive error types using Zig error unions:
  ```zig
  const K7Error = error{
      // Kubernetes errors
      KubernetesConnectionFailed,
      KubernetesConfigNotFound,
      DeploymentAlreadyExists,
      DeploymentNotFound,
      PodNotRunning,

      // API errors
      InvalidApiKey,
      ApiKeyExpired,
      Unauthorized,
      BadRequest,

      // Network errors
      NetworkTimeout,
      ConnectionRefused,
      TlsVerificationFailed,

      // File I/O errors
      ConfigFileNotFound,
      InvalidYamlFormat,
      InvalidJsonFormat,

      // General
      OutOfMemory,
      InvalidInput,
  };
  ```
- Create logging system using `std.log`:
  - Configurable log levels (debug, info, warn, error)
  - Structured logging with context
  - Log rotation and file output
  - Performance logging for API requests
- Error context propagation
- Stack trace preservation for debugging
- User-friendly error messages for CLI

**Logging Structure:**
```zig
const Logger = struct {
    level: std.log.Level,
    output: std.fs.File,

    pub fn init(level: std.log.Level, output_path: ?[]const u8) !Logger

    pub fn debug(self: *Logger, comptime fmt: []const u8, args: anytype) void
    pub fn info(self: *Logger, comptime fmt: []const u8, args: anytype) void
    pub fn warn(self: *Logger, comptime fmt: []const u8, args: anytype) void
    pub fn err(self: *Logger, comptime fmt: []const u8, args: anytype) void

    pub fn logApiRequest(self: *Logger, method: []const u8, path: []const u8, status: u16, duration_ms: u64) void
};

// Usage:
const result = k7core.createSandbox(config, null) catch |e| {
    logger.err("Failed to create sandbox: {s}", .{@errorName(e)});
    return e;
};
```

**Deliverables:**
- `src/common/error.zig` - Error type definitions
- `src/common/logger.zig` - Logging implementation
- Error documentation
- Logging configuration files

---

## Phase 3: Async I/O & Performance (Points 11-15)

### 11. Implement Async I/O for API Server

**Tasks:**
- Choose async runtime:
  - Option 1: Use `std.event.Loop` (Zig's async/await)
  - Option 2: Use io_uring on Linux for maximum performance
  - Option 3: Thread pool with blocking I/O
- Convert API server to handle concurrent requests
- Implement connection pooling for Kubernetes API
- Non-blocking HTTP request handling
- Async file I/O for API keys and logs
- Graceful shutdown handling

**Async Patterns:**
```zig
// Option 1: Zig async/await (if supported)
pub fn handleRequest(self: *K7ApiServer, res: *std.http.Server.Response) !void {
    const body = try res.reader().readAllAlloc(self.allocator, 1024 * 1024);
    defer self.allocator.free(body);

    // Parse request
    const config = try std.json.parseFromSlice(SandboxConfig, self.allocator, body, .{});
    defer config.deinit();

    // Create sandbox asynchronously
    const result = try async self.core.createSandbox(config.value, null);

    // Send response
    try sendJson(res, result);
}

// Option 2: Thread pool
const ThreadPool = struct {
    allocator: std.mem.Allocator,
    threads: []std.Thread,
    queue: RequestQueue,

    pub fn init(allocator: std.mem.Allocator, num_threads: usize) !ThreadPool
    pub fn submit(self: *ThreadPool, request: Request) !void
    pub fn shutdown(self: *ThreadPool) void
};
```

**Performance Targets:**
- Handle 1000+ concurrent connections
- Sub-millisecond response times for health checks
- Less than 100ms response for sandbox creation API calls
- Efficient memory usage with connection pooling

**Deliverables:**
- Async HTTP server implementation
- Connection pool for Kubernetes API
- Performance benchmarks
- Load testing results

---

### 12. Optimize Memory Management with Custom Allocators

**Tasks:**
- Implement custom allocators for different use cases:
  - Arena allocator for request-scoped memory
  - Pool allocator for fixed-size objects
  - General-purpose allocator for long-lived data
- Memory profiling and leak detection
- Zero-copy operations where possible
- String interning for repeated values
- Memory usage monitoring and limits

**Allocator Strategy:**
```zig
// Request handler with arena allocator
fn handleCreateSandbox(self: *K7ApiServer, res: *std.http.Server.Response) !void {
    // Use arena for request-scoped allocations
    var arena = std.heap.ArenaAllocator.init(self.allocator);
    defer arena.deinit(); // Frees all at once

    const allocator = arena.allocator();

    const body = try res.reader().readAllAlloc(allocator, 1024 * 1024);
    // No need to free - arena handles it

    const config = try std.json.parseFromSlice(SandboxConfig, allocator, body, .{});
    // No need to deinit - arena handles it

    // Core operations use main allocator for long-lived data
    const result = try self.core.createSandbox(config.value, null);

    try sendJson(res, result);
}

// Pool allocator for sandbox objects
const SandboxPool = struct {
    pool: std.heap.MemoryPool(SandboxInfo),

    pub fn init(allocator: std.mem.Allocator) !SandboxPool {
        return .{
            .pool = std.heap.MemoryPool(SandboxInfo).init(allocator),
        };
    }

    pub fn create(self: *SandboxPool) !*SandboxInfo {
        return self.pool.create();
    }

    pub fn destroy(self: *SandboxPool, item: *SandboxInfo) void {
        self.pool.destroy(item);
    }
};
```

**Memory Optimization Goals:**
- Reduce allocations by 50% compared to Python
- Zero memory leaks (verified with Valgrind/AddressSanitizer)
- Predictable memory usage
- Memory footprint < 50MB for API server at rest

**Deliverables:**
- Custom allocator implementations
- Memory profiling tools integration
- Memory usage documentation
- Allocation patterns guide

---

### 13. Create Testing Framework & Test Suite

**Tasks:**
- Set up Zig testing infrastructure:
  - Unit tests for all modules (`test` blocks)
  - Integration tests with real/mock Kubernetes
  - End-to-end tests for CLI and API
- Mock implementations:
  - Mock Kubernetes API server
  - Mock HTTP responses
  - Stub file system operations
- Test utilities:
  - Assertion helpers
  - Test fixtures
  - Temporary directory management
- Code coverage measurement
- Continuous testing in CI/CD

**Testing Structure:**
```zig
// Unit test example
test "SandboxConfig validation" {
    const allocator = std.testing.allocator;

    const config = SandboxConfig{
        .name = "test-sandbox",
        .image = "alpine:latest",
        .namespace = "default",
        .limits = .{
            .cpu = "1",
            .memory = "1Gi",
        },
    };

    try std.testing.expect(config.validate());
}

// Integration test example
test "K7Core creates sandbox" {
    const allocator = std.testing.allocator;

    // Setup mock Kubernetes client
    var mock_kube = try MockKubernetesClient.init(allocator);
    defer mock_kube.deinit();

    var core = K7Core{
        .allocator = allocator,
        .kube_client = mock_kube.client(),
        .config_loaded = true,
    };

    const config = SandboxConfig{ /* ... */ };
    const result = try core.createSandbox(config, null);

    try std.testing.expect(result.success);
    try std.testing.expectEqualStrings("Sandbox test-sandbox created successfully", result.message.?);
}

// Benchmark example
test "API server throughput" {
    const allocator = std.testing.allocator;

    var server = try K7ApiServer.init(allocator, 8080);
    defer server.deinit();

    const start = std.time.nanoTimestamp();

    // Simulate 1000 requests
    for (0..1000) |_| {
        // Send request
        // Measure response
    }

    const duration = std.time.nanoTimestamp() - start;
    const rps = 1000.0 / (@as(f64, @floatFromInt(duration)) / 1e9);

    std.debug.print("Requests per second: {d:.2}\n", .{rps});
}
```

**Test Coverage Goals:**
- 80%+ code coverage
- All public APIs tested
- Edge cases and error paths covered
- Performance regression tests

**Deliverables:**
- Comprehensive test suite
- Mock implementations
- Test documentation
- CI/CD test integration

---

### 14. Implement YAML Configuration Parser

**Tasks:**
- Find or implement YAML parser for Zig:
  - Option 1: Use existing library (if available)
  - Option 2: Write minimal YAML parser for K7 config format
  - Option 3: Switch to TOML (Zig-friendly alternative)
- Support K7 YAML config format:
  ```yaml
  name: my-sandbox
  image: alpine:latest
  namespace: default
  egress_whitelist:
    - "1.1.1.1/32"
    - "8.8.8.8/32"
  limits:
    cpu: "1"
    memory: "1Gi"
    ephemeral-storage: "2Gi"
  before_script: |
    apk add --no-cache git curl
  env_file: /path/to/.env
  ```
- Parse Kubernetes kubeconfig YAML
- Parse Ansible playbook YAML (read-only)
- Validation and error reporting

**YAML Parser Integration:**
```zig
const YamlParser = struct {
    allocator: std.mem.Allocator,

    pub fn parseFile(allocator: std.mem.Allocator, path: []const u8, comptime T: type) !T {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const content = try file.readToEndAlloc(allocator, 10 * 1024 * 1024);
        defer allocator.free(content);

        return parseString(allocator, content, T);
    }

    pub fn parseString(allocator: std.mem.Allocator, yaml: []const u8, comptime T: type) !T {
        // YAML parsing logic
        // Map to struct T
    }
};

// Usage:
const config = try YamlParser.parseFile(allocator, "k7.yaml", SandboxConfig);
defer config.deinit(allocator);
```

**Alternative: Use TOML instead:**
```toml
[sandbox]
name = "my-sandbox"
image = "alpine:latest"
namespace = "default"

[[sandbox.egress_whitelist]]
cidr = "1.1.1.1/32"

[[sandbox.egress_whitelist]]
cidr = "8.8.8.8/32"

[sandbox.limits]
cpu = "1"
memory = "1Gi"
ephemeral-storage = "2Gi"

[sandbox.before_script]
script = """
apk add --no-cache git curl
"""
```

**Deliverables:**
- YAML/TOML parser integration
- Config validation
- Parsing error messages
- Config format documentation

---

### 15. Add Prometheus Metrics & Monitoring

**Tasks:**
- Implement Prometheus metrics exporter
- Expose `/metrics` endpoint
- Track metrics:
  - API request rate (by endpoint, method, status)
  - API request duration (histogram)
  - Active sandboxes count (by namespace)
  - Sandbox creation/deletion rate
  - Kubernetes API call duration
  - Memory usage
  - Goroutine/thread count
  - API key usage (by key name)
  - Error rate (by error type)
- OpenMetrics format support
- Custom metrics for business logic

**Metrics Implementation:**
```zig
const Metrics = struct {
    allocator: std.mem.Allocator,
    mutex: std.Thread.Mutex,

    // Counters
    api_requests_total: std.StringHashMap(u64),
    sandboxes_created_total: u64,
    sandboxes_deleted_total: u64,
    errors_total: std.StringHashMap(u64),

    // Gauges
    active_sandboxes: u64,
    memory_usage_bytes: u64,

    // Histograms
    request_duration_seconds: Histogram,

    pub fn init(allocator: std.mem.Allocator) !Metrics
    pub fn deinit(self: *Metrics) void

    pub fn incrementCounter(self: *Metrics, name: []const u8, labels: []const Label) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        // Increment counter
    }

    pub fn setGauge(self: *Metrics, name: []const u8, value: f64) void
    pub fn observeHistogram(self: *Metrics, name: []const u8, value: f64) void

    pub fn export(self: *Metrics, writer: anytype) !void {
        // Export Prometheus format
        // # HELP api_requests_total Total API requests
        // # TYPE api_requests_total counter
        // api_requests_total{method="GET",endpoint="/health",status="200"} 1234
    }
};

// Middleware for API server
fn metricsMiddleware(metrics: *Metrics, handler: anytype) !void {
    const start = std.time.nanoTimestamp();

    // Call handler
    handler() catch |e| {
        metrics.incrementCounter("errors_total", &.{.{ .name = "type", .value = @errorName(e) }});
        return e;
    };

    const duration = @as(f64, @floatFromInt(std.time.nanoTimestamp() - start)) / 1e9;
    metrics.observeHistogram("request_duration_seconds", duration);
    metrics.incrementCounter("api_requests_total", &.{
        .{ .name = "method", .value = "POST" },
        .{ .name = "endpoint", .value = "/api/v1/sandboxes" },
        .{ .name = "status", .value = "201" },
    });
}
```

**Integration:**
- Export metrics at `/metrics`
- Grafana dashboard templates
- Alert rules for critical metrics
- Documentation for operators

**Deliverables:**
- Prometheus exporter
- Grafana dashboards
- Alert configurations
- Monitoring runbook

---

## Phase 4: Packaging & Deployment (Points 16-20)

### 16. Create Debian Package Build System

**Tasks:**
- Convert Python-based `.deb` build to Zig
- Update `build.sh` to:
  - Build Zig binaries (CLI, API)
  - Create Debian package structure
  - Install binaries to `/usr/local/bin/`
  - Install systemd service files
  - Install man pages
  - Set up post-install scripts
- Package metadata (control file, changelog, copyright)
- Create `k7-api.service` systemd unit
- Create uninstall scripts
- Support multiple architectures (amd64, arm64)

**Debian Package Structure:**
```
k7_<version>_amd64/
├── DEBIAN/
│   ├── control
│   ├── postinst
│   ├── prerm
│   └── postrm
├── usr/
│   └── local/
│       └── bin/
│           ├── k7           # CLI binary
│           └── k7-api       # API server binary
├── lib/
│   └── systemd/
│       └── system/
│           └── k7-api.service
├── etc/
│   └── k7/
│       └── config.yaml
└── usr/
    └── share/
        ├── man/
        │   └── man1/
        │       └── k7.1.gz
        └── doc/
            └── k7/
                ├── README.md
                └── examples/
```

**Build Script:**
```bash
#!/bin/bash
# build-deb.sh

VERSION="0.1.0"
ARCH="amd64"

# Build Zig binaries
zig build -Doptimize=ReleaseFast

# Create package directory
mkdir -p "k7_${VERSION}_${ARCH}/DEBIAN"
mkdir -p "k7_${VERSION}_${ARCH}/usr/local/bin"
mkdir -p "k7_${VERSION}_${ARCH}/lib/systemd/system"

# Copy binaries
cp zig-out/bin/k7 "k7_${VERSION}_${ARCH}/usr/local/bin/"
cp zig-out/bin/k7-api "k7_${VERSION}_${ARCH}/usr/local/bin/"

# Copy systemd service
cp pkg/k7-api.service "k7_${VERSION}_${ARCH}/lib/systemd/system/"

# Create control file
cat > "k7_${VERSION}_${ARCH}/DEBIAN/control" <<EOF
Package: k7
Version: ${VERSION}
Architecture: ${ARCH}
Maintainer: Katakate <hi@katakate.org>
Description: Secure VM sandbox orchestration
Depends: kubernetes, containerd
EOF

# Build package
dpkg-deb --build "k7_${VERSION}_${ARCH}"
```

**Deliverables:**
- Automated `.deb` build system
- Package for amd64 and arm64
- Installation/uninstallation scripts
- PPA repository setup

---

### 17. Implement Docker Container Build

**Tasks:**
- Create multi-stage Dockerfile for API server:
  ```dockerfile
  # Build stage
  FROM alpine:latest AS builder

  RUN apk add --no-cache zig

  WORKDIR /app
  COPY . .
  RUN zig build -Doptimize=ReleaseSmall

  # Runtime stage
  FROM alpine:latest

  RUN apk add --no-cache ca-certificates

  COPY --from=builder /app/zig-out/bin/k7-api /usr/local/bin/

  EXPOSE 8000
  ENTRYPOINT ["/usr/local/bin/k7-api"]
  ```
- Optimize image size (multi-stage builds, Alpine base)
- Update docker-compose.yml
- Health checks in Docker
- Volume mounts for config and data
- Environment variable configuration

**Docker Compose:**
```yaml
version: '3.8'

services:
  k7-api:
    build:
      context: .
      dockerfile: Dockerfile.api
    image: katakate/k7-api:latest
    ports:
      - "8000:8000"
    volumes:
      - /etc/k7:/etc/k7:ro
      - /etc/rancher/k3s/k3s.yaml:/etc/rancher/k3s/k3s.yaml:ro
    environment:
      - K7_API_KEYS_FILE=/etc/k7/api_keys.json
      - K7_LOG_LEVEL=info
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "wget", "--spider", "http://localhost:8000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
```

**Deliverables:**
- Optimized Dockerfile
- Docker Compose configuration
- Container registry publishing
- Container security scanning

---

### 18. Update CI/CD Pipeline for Zig

**Tasks:**
- Update GitHub Actions workflows:
  ```yaml
  name: Build and Test

  on: [push, pull_request]

  jobs:
    build:
      runs-on: ubuntu-latest
      steps:
        - uses: actions/checkout@v3

        - name: Setup Zig
          uses: goto-bus-stop/setup-zig@v2
          with:
            version: 0.13.0

        - name: Build
          run: zig build

        - name: Run tests
          run: zig build test

        - name: Build Debian package
          run: ./scripts/build-deb.sh

        - name: Upload artifacts
          uses: actions/upload-artifact@v3
          with:
            name: k7-deb
            path: dist/*.deb

    docker:
      runs-on: ubuntu-latest
      steps:
        - uses: actions/checkout@v3

        - name: Build Docker image
          run: docker build -t katakate/k7-api:latest .

        - name: Push to registry
          if: github.ref == 'refs/heads/main'
          run: |
            echo "${{ secrets.DOCKER_PASSWORD }}" | docker login -u "${{ secrets.DOCKER_USERNAME }}" --password-stdin
            docker push katakate/k7-api:latest
  ```
- Cross-compilation for multiple architectures
- Security scanning (static analysis, dependency check)
- Performance benchmarking
- Release automation (tags → packages)
- Documentation generation

**Deliverables:**
- Updated CI/CD workflows
- Automated testing
- Automated releases
- Security scanning integration

---

### 19. Write C FFI for Language Bindings

**Tasks:**
- Create C-compatible API for libk7sdk:
  ```zig
  // Export C-compatible functions
  export fn k7_client_init(endpoint: [*c]const u8, api_key: [*c]const u8) ?*K7Client {
      const allocator = std.heap.c_allocator;
      const client = allocator.create(K7Client) catch return null;
      client.* = K7Client.init(
          allocator,
          std.mem.span(endpoint),
          std.mem.span(api_key)
      ) catch return null;
      return client;
  }

  export fn k7_client_deinit(client: *K7Client) void {
      client.deinit();
      std.heap.c_allocator.destroy(client);
  }

  export fn k7_create_sandbox(client: *K7Client, config_json: [*c]const u8) ?*SandboxProxy {
      // Parse JSON, call Zig function, return pointer
  }

  export fn k7_list_sandboxes(client: *K7Client, namespace: [*c]const u8) ?*SandboxList {
      // Implementation
  }

  export fn k7_exec_command(sandbox: *SandboxProxy, command: [*c]const u8) ?*ExecResult {
      // Implementation
  }
  ```
- Generate C header file:
  ```c
  // k7.h
  #ifndef K7_H
  #define K7_H

  #ifdef __cplusplus
  extern "C" {
  #endif

  typedef struct K7Client K7Client;
  typedef struct SandboxProxy SandboxProxy;
  typedef struct ExecResult ExecResult;

  K7Client* k7_client_init(const char* endpoint, const char* api_key);
  void k7_client_deinit(K7Client* client);
  SandboxProxy* k7_create_sandbox(K7Client* client, const char* config_json);
  void k7_exec_command(SandboxProxy* sandbox, const char* command, ExecResult* result);

  #ifdef __cplusplus
  }
  #endif

  #endif // K7_H
  ```
- Build shared library (.so, .dylib, .dll)
- Create language bindings:
  - Python (ctypes/cffi)
  - Go (cgo)
  - Node.js (N-API)
  - Ruby (FFI)
- Test bindings with example code

**Python Binding Example:**
```python
import ctypes
import json

# Load library
libk7 = ctypes.CDLL("libk7sdk.so")

# Define function signatures
libk7.k7_client_init.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
libk7.k7_client_init.restype = ctypes.c_void_p

libk7.k7_create_sandbox.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
libk7.k7_create_sandbox.restype = ctypes.c_void_p

# Use API
client = libk7.k7_client_init(b"https://api.example.com", b"my-key")

config = json.dumps({
    "name": "my-sandbox",
    "image": "alpine:latest"
})

sandbox = libk7.k7_create_sandbox(client, config.encode())
```

**Deliverables:**
- C-compatible library (libk7sdk)
- C header file
- Language bindings (Python, Go, Node.js)
- Binding documentation
- Example code for each language

---

### 20. Documentation & Migration Guide

**Tasks:**
- Update all documentation for Zig implementation:
  - Installation guide
  - CLI usage
  - API reference
  - SDK documentation
  - Configuration reference
- Create migration guide from Python to Zig:
  - Breaking changes
  - Config format changes (if any)
  - API compatibility
  - Performance improvements
- Write architecture documentation:
  - System design
  - Module organization
  - Memory management patterns
  - Error handling patterns
- Create developer guide:
  - Building from source
  - Contributing guidelines
  - Code style guide
  - Testing guidelines
- Add code comments and doc comments:
  ```zig
  /// Creates a new sandbox with the given configuration.
  ///
  /// The sandbox will be created as a Kubernetes deployment with the specified
  /// image, resource limits, and security settings.
  ///
  /// # Parameters
  /// - `config`: Sandbox configuration
  /// - `progress_callback`: Optional callback for progress updates
  ///
  /// # Returns
  /// - `OperationResult` with success/failure status
  ///
  /// # Errors
  /// - `KubernetesConnectionFailed` if cannot connect to cluster
  /// - `DeploymentAlreadyExists` if sandbox with same name exists
  /// - `InvalidInput` if config validation fails
  pub fn createSandbox(
      self: *K7Core,
      config: SandboxConfig,
      progress_callback: ?*const fn(ProgressEvent) void
  ) !OperationResult {
      // Implementation
  }
  ```
- Performance comparison benchmarks:
  - Startup time: Python vs Zig
  - Memory usage: Python vs Zig
  - Request throughput: Python vs Zig
  - Binary size: Python vs Zig

**Documentation Structure:**
```
docs/
├── README.md                    # Overview
├── installation/
│   ├── from-source.md          # Building from Zig source
│   ├── debian-package.md       # Installing .deb
│   └── docker.md               # Running in Docker
├── guides/
│   ├── getting-started.md      # Quick start
│   ├── cli.md                  # CLI reference
│   ├── api.md                  # API reference
│   └── sdk.md                  # SDK usage
├── architecture/
│   ├── overview.md             # System design
│   ├── security.md             # Security architecture
│   └── performance.md          # Performance characteristics
├── migration/
│   ├── python-to-zig.md        # Migration guide
│   └── breaking-changes.md     # Breaking changes
└── development/
    ├── building.md             # Build instructions
    ├── testing.md              # Testing guide
    ├── contributing.md         # Contribution guide
    └── style-guide.md          # Zig code style
```

**Migration Guide Content:**
```markdown
# Migrating from Python K7 to Zig K7

## Overview
K7 has been rewritten in Zig for improved performance, security, and resource usage.

## Breaking Changes

### CLI
- No changes - CLI interface remains compatible

### API
- API endpoints unchanged
- Response format unchanged
- Authentication unchanged (API keys still work)

### SDK
- New native Zig SDK available
- Python bindings provided via C FFI
- Old Python SDK deprecated but supported via compatibility layer

### Configuration
- YAML format unchanged
- Added optional TOML format support

## Performance Improvements
- 10x faster startup time (50ms vs 500ms)
- 5x lower memory usage (10MB vs 50MB)
- 2x higher API throughput (5000 rps vs 2500 rps)
- 100x smaller binary (5MB vs 500MB with dependencies)

## Installation

### From Debian Package
```bash
sudo add-apt-repository ppa:katakate.org/k7
sudo apt update
sudo apt install k7
```

### From Source
```bash
git clone https://github.com/Katakate/k7
cd k7
zig build -Doptimize=ReleaseFast
sudo cp zig-out/bin/k7 /usr/local/bin/
```

## Testing the Migration
Run both versions side by side and compare results.
```

**Deliverables:**
- Complete documentation rewrite
- Migration guide
- Performance benchmarks
- API compatibility matrix
- Developer onboarding guide

---

## Phase 5: Advanced Features & Optimization (Points 21-30)

### 21. Implement Prometheus Metrics Exporter

**Tasks:**
- Create Prometheus metrics exporter module in Zig that exposes `/metrics` endpoint with OpenMetrics format support for integration with Prometheus monitoring systems. Implement counter metrics for API request rates (by endpoint, method, and HTTP status code), histogram metrics for request duration with configurable buckets, gauge metrics for active sandboxes count per namespace and current memory usage, and custom business logic metrics for sandbox creation/deletion rates and API key usage statistics. Use mutex-protected data structures for thread-safe metric updates and implement efficient string interning for label values to minimize memory allocations.
- Design comprehensive monitoring strategy including Grafana dashboard templates with pre-built visualizations for API performance, sandbox lifecycle, resource utilization, and error rates. Create Prometheus alert rules for critical conditions such as high error rates, memory pressure, slow response times, and failed sandbox creations. Implement metric cardinality controls to prevent explosion of unique label combinations that could overwhelm Prometheus. Add support for custom metric labels from configuration and runtime context to enable flexible querying and aggregation.

**Key Metrics:**
```zig
const Metrics = struct {
    // Counters
    api_requests_total: CounterVec,        // Labels: method, endpoint, status
    sandboxes_created_total: Counter,
    sandboxes_deleted_total: Counter,
    errors_total: CounterVec,              // Labels: error_type

    // Gauges
    active_sandboxes: GaugeVec,            // Labels: namespace
    memory_usage_bytes: Gauge,
    api_keys_active: Gauge,

    // Histograms
    request_duration_seconds: HistogramVec, // Labels: endpoint
    sandbox_creation_duration_seconds: Histogram,
    kubernetes_api_duration_seconds: HistogramVec, // Labels: operation
};
```

**Deliverables:**
- Prometheus metrics exporter (`src/common/metrics.zig`)
- Grafana dashboard JSON templates
- Prometheus alert rule YAML files
- Metrics documentation with cardinality analysis
- Performance impact benchmarks

---

### 22. Build Rate Limiting & DDoS Protection

**Tasks:**
- Implement token bucket rate limiting algorithm in Zig with configurable limits per API key, per IP address, and global request rate caps to prevent API abuse and resource exhaustion attacks. Design sliding window counters using efficient ring buffer data structures to track request rates over configurable time windows (e.g., 100 requests per minute per API key). Implement distributed rate limiting state using shared memory or external Redis backend for multi-instance API deployments to ensure consistent limits across all API server instances. Add backpressure mechanisms that return 429 Too Many Requests responses with Retry-After headers when limits are exceeded, and implement exponential backoff suggestions for clients.
- Create DDoS protection layer with adaptive rate limiting that automatically tightens limits during attack scenarios based on error rates and response time degradation. Implement connection throttling to limit concurrent connections per IP and per API key. Add request size limits for JSON payloads to prevent memory exhaustion attacks. Implement IP allowlisting and blocklisting with CIDR support for manual override of rate limits. Create admin API endpoints for real-time rate limit adjustment without service restart. Integrate with Prometheus metrics to track rate limit hits and blocked requests for attack pattern analysis.

**Rate Limit Structure:**
```zig
const RateLimiter = struct {
    allocator: std.mem.Allocator,

    // Per-API-key limits
    api_key_limits: std.StringHashMap(TokenBucket),

    // Per-IP limits
    ip_limits: std.StringHashMap(TokenBucket),

    // Global limit
    global_limit: TokenBucket,

    // Configuration
    config: RateLimitConfig,

    pub fn checkLimit(self: *RateLimiter, api_key: []const u8, ip: []const u8) !bool
    pub fn recordRequest(self: *RateLimiter, api_key: []const u8, ip: []const u8) !void
    pub fn getRemainingQuota(self: *RateLimiter, api_key: []const u8) !u64
};
```

**Deliverables:**
- Rate limiting middleware (`src/api/ratelimit.zig`)
- DDoS protection module
- Configuration system for rate limits
- Admin API for limit management
- Attack simulation test suite

---

### 23. Create Health Check & Readiness Probes

**Tasks:**
- Implement comprehensive health check system in Zig with separate `/health/live` liveness probe endpoint (returns 200 if process is alive) and `/health/ready` readiness probe endpoint (returns 200 only if all dependencies are healthy including Kubernetes API connectivity, API key file accessibility, and internal service state). Design dependency health check framework that periodically polls Kubernetes API server, verifies kubeconfig validity, tests API key file read permissions, and validates internal state consistency. Implement circuit breaker pattern for health checks to avoid cascading failures when dependencies are temporarily unavailable. Add configurable health check intervals, timeout values, and failure threshold counts before marking service unhealthy.
- Create structured health check responses with JSON payload containing detailed status for each dependency component, version information, uptime statistics, and resource utilization metrics to aid in debugging and operational visibility. Implement graceful shutdown sequence that marks service as not-ready immediately upon receiving SIGTERM, drains existing connections with configurable timeout, and only exits after all in-flight requests complete or timeout expires. Add startup health checks that verify all critical dependencies before marking service ready to prevent routing traffic to partially initialized instances. Integrate health check status with Prometheus metrics for alerting on prolonged unhealthy states.

**Health Check Response:**
```zig
const HealthStatus = struct {
    status: enum { healthy, degraded, unhealthy },
    version: []const u8,
    uptime_seconds: u64,
    checks: []ComponentHealth,

    const ComponentHealth = struct {
        name: []const u8,
        status: enum { pass, warn, fail },
        message: ?[]const u8,
        duration_ms: u64,
    };
};
```

**Deliverables:**
- Health check endpoints (`src/api/health.zig`)
- Dependency health check framework
- Graceful shutdown handler
- Kubernetes liveness/readiness probe configs
- Health check integration tests

---

### 24. Implement Request Tracing & Correlation IDs

**Tasks:**
- Build distributed tracing system in Zig using OpenTelemetry standards to track request flow across API server, K7Core logic, and Kubernetes API calls with hierarchical span relationships. Implement automatic trace context propagation through all function calls using thread-local storage or async context to maintain trace IDs without manual parameter passing. Generate unique correlation IDs (UUID v4) for each incoming API request and inject them into all log statements, error responses, and outgoing Kubernetes API requests for end-to-end request tracking. Add trace sampling logic with configurable sampling rates to balance observability needs with performance overhead and storage costs.
- Create trace export mechanism that sends span data to OpenTelemetry collector or Jaeger backend via gRPC or HTTP protocol with batching and retry logic for reliability. Implement custom span attributes for K7-specific context including sandbox name, namespace, operation type, API key name (not value), and resource limits. Add trace visualization support by ensuring span timing and parent-child relationships are correctly represented for flame graph rendering. Integrate tracing with logging system to include trace IDs in structured log fields for correlation between logs and traces. Create sampling decision logic based on request characteristics like error status, slow response times, or specific API endpoints to always capture problematic requests.

**Tracing Architecture:**
```zig
const Tracer = struct {
    allocator: std.mem.Allocator,
    exporter: TraceExporter,
    sampler: TraceSampler,

    pub fn startSpan(self: *Tracer, name: []const u8, parent: ?*Span) !*Span
    pub fn endSpan(self: *Tracer, span: *Span) !void
    pub fn injectContext(self: *Tracer, span: *Span, headers: *HttpHeaders) !void
    pub fn extractContext(self: *Tracer, headers: *HttpHeaders) !?TraceContext
};

const Span = struct {
    trace_id: [16]u8,      // 128-bit trace ID
    span_id: [8]u8,        // 64-bit span ID
    parent_span_id: ?[8]u8,
    name: []const u8,
    start_time: i64,
    end_time: ?i64,
    attributes: std.StringHashMap([]const u8),
    events: std.ArrayList(SpanEvent),
};
```

**Deliverables:**
- OpenTelemetry tracing module (`src/common/tracing.zig`)
- Trace context propagation middleware
- Jaeger/OTLP exporter implementation
- Sampling strategy configuration
- Trace visualization examples

---

### 25. Add Configuration Management System

**Tasks:**
- Design comprehensive configuration management system in Zig that supports multiple configuration sources with clear precedence order: command-line flags (highest priority), environment variables (middle priority), and configuration files in YAML or TOML format (lowest priority). Implement configuration schema validation at startup to catch misconfiguration early with helpful error messages indicating specific validation failures and expected value formats. Create type-safe configuration struct with compile-time guarantees that all required fields are provided and optional fields have sensible defaults. Support configuration hot-reload via file watching or SIGHUP signal handler to update non-critical settings without service restart, with atomic configuration swap to prevent partial updates.
- Implement configuration sections for API server (bind address, port, TLS certificates, CORS settings), authentication (API key file path, hash algorithm, expiry policy), Kubernetes client (kubeconfig path, API server URL, timeout values, retry policy), rate limiting (limits per key/IP/global, time windows), logging (level, format, output destination), and metrics (enabled exporters, scrape interval, cardinality limits). Add configuration validation business rules such as ensuring port numbers are in valid range, file paths exist and are readable, and numeric values are within sensible bounds. Create configuration dump command that prints active configuration to stdout for debugging, masking sensitive values like API keys and passwords. Implement configuration versioning with migration support for backward compatibility when config schema evolves.

**Configuration Structure:**
```zig
const Config = struct {
    server: ServerConfig,
    auth: AuthConfig,
    kubernetes: KubernetesConfig,
    rate_limiting: RateLimitConfig,
    logging: LogConfig,
    metrics: MetricsConfig,

    const ServerConfig = struct {
        bind_address: []const u8 = "0.0.0.0",
        port: u16 = 8000,
        tls_enabled: bool = false,
        tls_cert_path: ?[]const u8 = null,
        tls_key_path: ?[]const u8 = null,
        cors_origins: [][]const u8 = &.{},
    };

    pub fn load(allocator: std.mem.Allocator) !Config
    pub fn validate(self: *const Config) !void
    pub fn reload(self: *Config) !void
};
```

**Deliverables:**
- Configuration management system (`src/common/config.zig`)
- Schema validation framework
- Hot-reload mechanism
- Configuration migration utilities
- Example config files (YAML/TOML)

---

### 26. Implement Audit Logging & Security Events

**Tasks:**
- Create comprehensive audit logging system in Zig that records all security-relevant events including API authentication attempts (both successful and failed with reason), API key lifecycle events (generation, revocation, expiration), sandbox creation/deletion operations with requesting user context, privilege escalation attempts via capability additions, network policy modifications, and admin command executions. Design audit log format using structured JSON with consistent schema including timestamp (ISO 8601), event type classification, actor identification (API key name, IP address), resource affected (sandbox name, namespace), operation attempted, success/failure outcome, and additional context-specific metadata.
- Implement tamper-evident audit log storage using append-only file mode with file integrity verification via cryptographic hash chains where each log entry includes hash of previous entry to detect tampering or deletion. Create audit log rotation policy with configurable file size or time-based rotation, compression of old logs, and retention policy enforcement. Add audit log querying API with filtering by time range, event type, actor, resource, and outcome for security investigations and compliance reporting. Implement real-time audit event streaming to external SIEM systems via syslog protocol or message queue for centralized security monitoring. Create audit log anonymization tool for sharing logs externally by redacting sensitive fields while preserving investigation utility.

**Audit Event Structure:**
```zig
const AuditEvent = struct {
    id: [16]u8,                    // UUID
    timestamp: i64,                // Unix timestamp (nanoseconds)
    event_type: EventType,
    severity: Severity,
    actor: Actor,
    resource: Resource,
    operation: []const u8,
    outcome: enum { success, failure, error },
    error_message: ?[]const u8,
    metadata: std.json.Value,
    previous_hash: [32]u8,         // SHA-256 of previous audit entry

    const EventType = enum {
        authentication,
        authorization,
        sandbox_creation,
        sandbox_deletion,
        sandbox_exec,
        api_key_generated,
        api_key_revoked,
        config_changed,
        security_violation,
    };
};
```

**Deliverables:**
- Audit logging system (`src/common/audit.zig`)
- Hash chain verification tool
- Audit log query API
- SIEM integration module
- Audit log analysis scripts

---

### 27. Create Backup & Disaster Recovery System

**Tasks:**
- Implement automated backup system in Zig for critical K7 state including API key database, audit logs, configuration files, and operational metadata with configurable backup schedule (hourly, daily, weekly). Design backup format using tar.gz archives with manifest file describing backup contents, creation timestamp, K7 version, and integrity checksums for each component. Create incremental backup mechanism that only captures changes since last full backup to minimize storage requirements and backup duration. Implement backup encryption using AES-256-GCM with key derivation from admin-provided passphrase or external key management service integration to protect sensitive data at rest.
- Build restore procedure that validates backup integrity via checksum verification before restoration, supports point-in-time recovery to specific backup timestamp, and handles version compatibility by migrating old backup formats to current schema. Create backup storage abstraction supporting local filesystem, S3-compatible object storage, and network file systems with unified API. Implement backup retention policy with configurable keep rules (e.g., daily for 7 days, weekly for 4 weeks, monthly for 12 months) and automatic cleanup of expired backups. Add disaster recovery testing framework that performs periodic restore drills to separate test environment to verify backup viability. Create backup monitoring integration with Prometheus metrics tracking backup success/failure, backup size trends, and time since last successful backup for alerting on backup system failures.

**Backup Management:**
```zig
const BackupManager = struct {
    allocator: std.mem.Allocator,
    storage: BackupStorage,
    encryption_key: [32]u8,

    pub fn createBackup(self: *BackupManager, backup_type: BackupType) !BackupInfo
    pub fn listBackups(self: *BackupManager) ![]BackupInfo
    pub fn restoreBackup(self: *BackupManager, backup_id: []const u8, options: RestoreOptions) !void
    pub fn verifyBackup(self: *BackupManager, backup_id: []const u8) !bool
    pub fn pruneBackups(self: *BackupManager, retention_policy: RetentionPolicy) !void
};

const BackupInfo = struct {
    id: []const u8,
    timestamp: i64,
    backup_type: enum { full, incremental },
    size_bytes: u64,
    components: [][]const u8,
    checksum: [32]u8,
};
```

**Deliverables:**
- Backup management system (`src/common/backup.zig`)
- Restore procedure implementation
- Encryption/decryption module
- Backup storage adapters (local, S3)
- Disaster recovery runbook

---

### 28. Implement Multi-Tenancy & Namespace Isolation

**Tasks:**
- Design multi-tenancy architecture in Zig that enforces strict namespace isolation where each API key is scoped to specific Kubernetes namespaces with role-based access control determining permitted operations per namespace. Implement namespace-aware API endpoints that validate requesting API key has permission to access target namespace before executing operations, preventing unauthorized cross-tenant access. Create tenant resource quota system that tracks and enforces limits on number of sandboxes per tenant, total CPU/memory allocation across tenant's sandboxes, and API request rate limits per tenant to prevent resource monopolization. Add tenant-specific configuration profiles allowing customization of default sandbox settings, network policies, and security contexts per tenant while maintaining system-wide security baselines.
- Build tenant lifecycle management API with endpoints for creating tenants (namespace + API keys + quotas), updating tenant quotas and permissions, suspending tenants to temporarily block all operations, and deleting tenants with automatic cleanup of all associated resources. Implement tenant usage tracking and billing metrics including sandbox runtime hours, API request counts, and resource consumption statistics per tenant for chargeback reporting. Create tenant isolation verification tests that attempt unauthorized cross-tenant access patterns to validate security boundaries. Add tenant onboarding workflow automation that provisions namespace, generates initial API key, sets default quotas, and sends welcome email with credentials. Implement tenant audit trail that records all operations performed by tenant for compliance and troubleshooting.

**Multi-Tenancy Structure:**
```zig
const TenantManager = struct {
    allocator: std.mem.Allocator,
    kube_client: *KubernetesClient,

    pub fn createTenant(self: *TenantManager, config: TenantConfig) !Tenant
    pub fn getTenant(self: *TenantManager, tenant_id: []const u8) !Tenant
    pub fn updateQuotas(self: *TenantManager, tenant_id: []const u8, quotas: ResourceQuotas) !void
    pub fn suspendTenant(self: *TenantManager, tenant_id: []const u8) !void
    pub fn deleteTenant(self: *TenantManager, tenant_id: []const u8) !void
    pub fn getTenantUsage(self: *TenantManager, tenant_id: []const u8) !UsageStats
};

const Tenant = struct {
    id: []const u8,
    name: []const u8,
    namespaces: [][]const u8,
    quotas: ResourceQuotas,
    api_keys: [][]const u8,
    status: enum { active, suspended, deleted },
    created_at: i64,
};
```

**Deliverables:**
- Multi-tenancy module (`src/core/tenancy.zig`)
- Namespace isolation enforcement
- Tenant quota system
- Tenant lifecycle API
- Cross-tenant access tests

---

### 29. Add Observability with Structured Logging

**Tasks:**
- Implement comprehensive structured logging system in Zig using JSON log format for machine-parseable output with consistent field schema across all log entries including timestamp (ISO 8601 with nanosecond precision), log level (debug/info/warn/error), logger name (component identifier), message (human-readable description), trace ID (for request correlation), and context fields (sandbox name, namespace, operation, API key, etc.). Design log levels with semantic meaning: DEBUG for detailed execution flow useful during development, INFO for important state changes and business events, WARN for degraded conditions that don't prevent operation, and ERROR for failures requiring intervention. Create contextual logging API that allows attaching metadata to logger instance which is automatically included in all subsequent log entries from that context, reducing boilerplate.
- Implement log output destinations supporting stdout/stderr for container environments, file output with rotation for traditional deployments, and network sinks like syslog or logstash for centralized aggregation. Add log filtering at runtime based on logger name patterns and minimum level to control verbosity without code changes. Create log sampling to reduce high-frequency log statement volume (e.g., successful health checks) while preserving anomalies. Implement log redaction for sensitive fields like API keys and environment variables to prevent credential leakage in logs. Build log querying CLI tool that parses JSON logs with filtering by time range, log level, component, trace ID, or custom field values for operational debugging. Integrate logging with error tracking systems like Sentry to automatically capture error logs with full context for investigation.

**Structured Logging:**
```zig
const Logger = struct {
    name: []const u8,
    level: LogLevel,
    output: LogOutput,
    context: std.StringHashMap(std.json.Value),

    pub fn debug(self: *Logger, comptime fmt: []const u8, args: anytype) void
    pub fn info(self: *Logger, comptime fmt: []const u8, args: anytype) void
    pub fn warn(self: *Logger, comptime fmt: []const u8, args: anytype) void
    pub fn err(self: *Logger, comptime fmt: []const u8, args: anytype) void

    pub fn withField(self: *Logger, key: []const u8, value: anytype) *Logger
    pub fn withFields(self: *Logger, fields: anytype) *Logger
};

// Example usage:
logger.withField("sandbox", "demo")
    .withField("namespace", "default")
    .info("Created sandbox successfully", .{});

// Output:
// {"timestamp":"2025-01-15T10:30:45.123456789Z","level":"info","logger":"k7.core","message":"Created sandbox successfully","sandbox":"demo","namespace":"default","trace_id":"a1b2c3d4"}
```

**Deliverables:**
- Structured logging system (`src/common/logging.zig`)
- Log rotation and retention
- Log redaction module
- Log query CLI tool
- Logging best practices guide

---

### 30. Implement Comprehensive Integration Test Suite

**Tasks:**
- Create end-to-end integration test suite in Zig that validates complete workflows from API request through Kubernetes operations to sandbox lifecycle with real or mock Kubernetes cluster. Build test harness that automatically sets up test environment including kind (Kubernetes in Docker) cluster with Kata runtime installed, test namespaces, test API keys, and network policies. Implement test scenarios covering happy paths (successful sandbox creation, execution, deletion), error paths (invalid config, missing dependencies, quota exceeded), edge cases (concurrent operations, resource exhaustion, network failures), and security scenarios (unauthorized access attempts, privilege escalation, network policy violation).
- Design test data factories in Zig that generate valid and invalid test inputs including SandboxConfig variants, kubeconfig files with different auth methods, API key configurations, and network policy specifications. Create test fixtures for mock Kubernetes API responses using recorded real API traffic or handcrafted responses for deterministic testing. Implement test cleanup that ensures all created resources (namespaces, deployments, secrets, network policies) are deleted after tests complete even on failure to prevent test pollution. Add performance regression tests that measure API response times, memory usage, and throughput to detect performance degradation in code changes. Build test reporting that generates detailed test results with execution time, resource usage, and coverage metrics in machine-readable format (JUnit XML, JSON) for CI integration. Create chaos testing scenarios using Toxiproxy or similar to inject network latency, packet loss, and service failures to validate resilience.

**Integration Test Structure:**
```zig
const IntegrationTest = struct {
    allocator: std.mem.Allocator,
    kube_client: *KubernetesClient,
    api_client: *K7ApiClient,
    test_namespace: []const u8,

    pub fn setUp(self: *IntegrationTest) !void {
        // Create test namespace, API keys, etc.
    }

    pub fn tearDown(self: *IntegrationTest) !void {
        // Clean up all test resources
    }

    pub fn testSandboxLifecycle(self: *IntegrationTest) !void {
        // Create -> Exec -> Delete workflow
    }

    pub fn testNetworkPolicyEnforcement(self: *IntegrationTest) !void {
        // Verify egress whitelisting works
    }

    pub fn testConcurrentOperations(self: *IntegrationTest) !void {
        // Multiple parallel sandbox operations
    }
};
```

**Deliverables:**
- Integration test suite (`tests/integration/`)
- Test environment setup automation
- Mock Kubernetes API server
- Chaos testing scenarios
- CI/CD integration configuration

---

## Summary & Timeline

### Estimated Effort

| Phase | Points | Estimated Time | Complexity |
|-------|--------|----------------|------------|
| Phase 1: Foundation & Infrastructure | 1-5 | 2-3 months | High |
| Phase 2: Core Business Logic | 6-10 | 2-3 months | High |
| Phase 3: Async I/O & Performance | 11-15 | 1-2 months | Medium |
| Phase 4: Packaging & Deployment | 16-20 | 1-2 months | Medium |
| Phase 5: Advanced Features & Optimization | 21-30 | 2-3 months | Medium-High |
| **Total** | **30 points** | **8-14 months** | **High** |

### Risk Assessment

**High Risks:**
1. **Kubernetes client complexity** - K8s API is extensive and complex
2. **Streaming support** - kubectl exec requires WebSocket/streaming
3. **YAML parsing** - Limited Zig YAML libraries available
4. **Async I/O maturity** - Zig's async is still evolving

**Mitigation:**
- Start with mock K8s API for testing
- Consider wrapping kubectl binary for exec initially
- Alternative: Use TOML instead of YAML
- Use thread pool initially, migrate to async later

### Success Criteria

1. **Functionality:** 100% feature parity with Python version
2. **Performance:**
   - 10x faster startup
   - 5x lower memory usage
   - 2x higher throughput
3. **Binary Size:** < 10MB (vs ~500MB Python + deps)
4. **Memory Safety:** Zero memory leaks (verified with Valgrind)
5. **Tests:** 80%+ code coverage
6. **Documentation:** Complete API and developer docs

### Why Zig?

**Advantages:**
- **Performance:** Native compiled code, zero GC pauses
- **Safety:** Compile-time safety without runtime overhead
- **Size:** Tiny binaries (5-10MB vs 500MB+ Python)
- **Memory:** Predictable memory usage, no GC
- **Cross-compilation:** Easy builds for multiple platforms
- **Simplicity:** No hidden control flow, clear error handling
- **C interop:** Easy FFI for language bindings

**Challenges:**
- **Ecosystem:** Fewer libraries than Python
- **Learning curve:** Different paradigm from Python
- **Tooling:** Less mature than Python ecosystem
- **Async:** Still evolving (but usable)

---

## Appendix: Zig vs Python Comparison

### Binary Size
- Python K7: ~500MB (interpreter + dependencies)
- Zig K7: ~5-10MB (static binary)

### Startup Time
- Python: ~500ms (import libraries, JIT warmup)
- Zig: ~10ms (native code, no warmup)

### Memory Usage
- Python API server: ~50MB at rest, ~200MB under load
- Zig API server: ~10MB at rest, ~30MB under load

### Request Latency
- Python: p50 ~5ms, p99 ~50ms (with GC pauses)
- Zig: p50 ~1ms, p99 ~5ms (no GC)

### Development Velocity
- Python: Faster initial development (high-level, batteries included)
- Zig: Slower initial development, faster long-term (compile-time safety)

### Deployment
- Python: Complex (virtualenv, dependencies, wheels)
- Zig: Simple (single binary, no dependencies)

---

**End of Zig Conversion Plan**
