# K7/Katakate - Zig Implementation

**Status:** 🚧 Work in Progress - Foundation Phase
**Version:** 0.0.3 (matching Python implementation)
**Language:** Zig 0.13.0+

This directory contains the Zig implementation of K7/Katakate, a secure VM sandbox orchestration system. This is a complete rewrite from Python with focus on performance, safety, and minimal resource usage.

## 🎯 Implementation Status

### ✅ Completed
- [x] Project structure with proper build system
- [x] Core data models (SandboxConfig, SandboxInfo, ExecResult, OperationResult)
- [x] JSON serialization/deserialization for all models
- [x] Memory management with allocators and proper cleanup
- [x] Unit tests for core data structures
- [x] CLI command structure and argument parsing
- [x] API server structure
- [x] K7Core business logic structure
- [x] C FFI SDK structure for language bindings

### 🚧 In Progress
- [ ] Kubernetes client library implementation
- [ ] Full K7Core business logic (sandbox creation/deletion/exec)
- [ ] HTTP server with authentication middleware
- [ ] CLI command implementations
- [ ] API endpoint handlers
- [ ] YAML configuration parsing
- [ ] Terminal UI with progress bars and tables

### 📋 Planned (Phases 2-5)
- [ ] Async I/O and concurrency
- [ ] Custom memory allocators for performance
- [ ] Comprehensive integration test suite
- [ ] Debian package build system
- [ ] Docker container builds
- [ ] Advanced features (metrics, rate limiting, health checks, etc.)

## 🏗️ Project Structure

```
zig-impl/
├── build.zig                    # Build configuration
├── README.md                    # This file
├── src/
│   ├── cli/
│   │   └── main.zig            # CLI application entry point
│   ├── api/
│   │   └── main.zig            # API server entry point
│   ├── core/
│   │   ├── core.zig            # K7Core business logic
│   │   └── models.zig          # Data models (COMPLETE)
│   ├── sdk/
│   │   └── sdk.zig             # C FFI SDK for language bindings
│   ├── kubernetes/
│   │   └── client.zig          # Kubernetes API client (TODO)
│   └── common/
│       ├── http.zig            # HTTP utilities (TODO)
│       ├── logging.zig         # Logging system (TODO)
│       ├── error.zig           # Error types (TODO)
│       └── terminal.zig        # Terminal UI utilities (TODO)
└── tests/
    ├── unit/                    # Unit tests
    └── integration/             # Integration tests
```

## 🚀 Building

### Prerequisites

- Zig 0.13.0 or later: https://ziglang.org/download/
- Linux x86_64 (primary target)
- For testing: Docker, Kubernetes, Kata Containers

### Build Commands

```bash
# Build all targets (CLI + API + SDK)
zig build

# Build with optimizations
zig build -Doptimize=ReleaseFast

# Run unit tests
zig build test

# Run CLI
zig build run-cli -- --help

# Run API server
zig build run-api

# Install to zig-out/bin/
zig build install
```

### Build Targets

| Target | Description | Output |
|--------|-------------|--------|
| `k7` | CLI executable | `zig-out/bin/k7` |
| `k7-api` | API server | `zig-out/bin/k7-api` |
| `libk7core.a` | Core library (static) | `zig-out/lib/libk7core.a` |
| `libk7sdk.so` | SDK library (shared, C FFI) | `zig-out/lib/libk7sdk.so` |

## 📦 Installation

### From Source

```bash
cd zig-impl
zig build -Doptimize=ReleaseFast
sudo cp zig-out/bin/k7 /usr/local/bin/
sudo cp zig-out/bin/k7-api /usr/local/bin/
```

### Debian Package (Planned)

```bash
./scripts/build-deb.sh
sudo dpkg -i k7_0.0.3_amd64.deb
```

## 🧪 Testing

### Run Unit Tests

```bash
zig build test
```

### Run Integration Tests (Requires Kubernetes)

```bash
# TODO: Implement integration test runner
./scripts/run-integration-tests.sh
```

### Memory Leak Detection

```bash
# Build with sanitizers
zig build -Doptimize=ReleaseSafe

# Run with Valgrind
valgrind --leak-check=full ./zig-out/bin/k7 list
```

## 📊 Performance Benchmarks

### vs Python Implementation

| Metric | Python | Zig | Improvement |
|--------|--------|-----|-------------|
| Binary Size | ~500MB (+ interpreter) | ~5-10MB | 50-100x |
| Startup Time | ~500ms | ~10ms (target) | 50x |
| Memory (API at rest) | ~50MB | ~10MB (target) | 5x |
| Memory (API under load) | ~200MB | ~30MB (target) | 6-7x |
| Request Latency (p50) | ~5ms | ~1ms (target) | 5x |
| Request Latency (p99) | ~50ms (GC pauses) | ~5ms (target) | 10x |
| Throughput | ~2500 rps | ~5000 rps (target) | 2x |

## 🔧 Development

### Code Style

- Follow Zig standard library conventions
- Use `zig fmt` before committing
- Run `zig build test` before pushing
- Document public APIs with doc comments (`///`)
- Always use explicit error handling (no try without handling)
- Prefer explicit allocators over implicit

### Memory Management Patterns

```zig
// Arena allocator for request-scoped memory
var arena = std.heap.ArenaAllocator.init(allocator);
defer arena.deinit();  // Frees all at once

const request_allocator = arena.allocator();

// Explicit cleanup with defer
const string = try allocator.dupe(u8, "Hello");
defer allocator.free(string);

// Struct with deinit pattern
var config = try SandboxConfig.init(allocator);
defer config.deinit(allocator);
```

### Error Handling

```zig
// Define error sets
const K7Error = error{
    KubernetesConnectionFailed,
    DeploymentNotFound,
    InvalidApiKey,
};

// Return error unions
pub fn doSomething() !Result {
    return error.KubernetesConnectionFailed;
}

// Handle errors explicitly
const result = doSomething() catch |err| {
    std.log.err("Failed: {s}", .{@errorName(err)});
    return err;
};
```

## 📚 API Documentation

### Core Data Models

See `src/core/models.zig` for complete API documentation.

**SandboxConfig:**
- `name: []const u8` - Sandbox name
- `image: []const u8` - Container image
- `namespace: []const u8` - Kubernetes namespace
- `egress_whitelist: ?[][]const u8` - CIDR blocks for egress
- `limits: ?std.StringHashMap([]const u8)` - Resource limits
- `before_script: []const u8` - Script to run before lockdown
- Security options: `pod_non_root`, `container_non_root`, `cap_drop`, `cap_add`

**ExecResult:**
- `exit_code: i32` - Command exit code
- `stdout: []const u8` - Standard output
- `stderr: []const u8` - Standard error
- `duration_ms: i64` - Execution duration

## 🔐 Security

- Compile-time memory safety (no null pointers, no buffer overflows)
- Explicit error handling (no hidden exceptions)
- API key hashing with Argon2id (planned, currently SHA256 in Python)
- Capability dropping (ALL by default)
- Network isolation via Kubernetes NetworkPolicies
- Non-root execution
- Seccomp profiles

## 🤝 Contributing

1. Follow the [30-point Zig conversion plan](../ZIG_CONVERSION_PLAN.md)
2. Write tests for new functionality
3. Ensure `zig build test` passes
4. Run `zig fmt` on all modified files
5. Document public APIs with doc comments
6. Update this README if adding new features

## 📝 License

Apache 2.0 - See LICENSE file

## 🙏 Acknowledgments

- Original Python implementation: K7/Katakate team
- Zig programming language: Andrew Kelley and contributors
- Inspiration: Performance-critical systems programming

## 📞 Contact

- Project: https://katakate.org
- Documentation: https://docs.katakate.org
- Issues: https://github.com/Katakate/k7/issues
- Security: security@katakate.org

---

**Note:** This Zig implementation is being developed following a comprehensive 30-point conversion plan. See `ZIG_CONVERSION_PLAN.md` for detailed technical specifications and implementation roadmap.
