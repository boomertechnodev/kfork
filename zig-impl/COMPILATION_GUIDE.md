# K7/Katakate Zig Implementation - Compilation and Testing Guide

**Date:** 2025-01-15
**Status:** Ready for compilation (Zig toolchain required)
**Target Zig Version:** 0.13.0 or later

---

## Prerequisites

### Install Zig Toolchain

```bash
# Download Zig 0.13.0 for Linux x86_64
cd /tmp
wget https://ziglang.org/download/0.13.0/zig-linux-x86_64-0.13.0.tar.xz
tar xf zig-linux-x86_64-0.13.0.tar.xz
sudo mv zig-linux-x86_64-0.13.0 /usr/local/zig
export PATH=$PATH:/usr/local/zig

# Verify installation
zig version
# Expected: 0.13.0
```

**Alternative (Latest Master Build):**
```bash
# If 0.13.0 is not available, use latest
wget https://ziglang.org/builds/zig-linux-x86_64-<VERSION>.tar.xz
# Follow same steps as above
```

---

## Build System Fixes Applied

### Fixed in This Session

**File:** `build.zig`
**Issue:** Redundant `linkLibrary()` calls
**Fix:** Removed unnecessary linking since modules use direct `@import()`

**Changes:**
1. Removed `k7_cli.linkLibrary(k7core);` (line 35)
2. Removed `k7_api.linkLibrary(k7core);` (line 48)
3. Removed `k7sdk.linkLibrary(k7core);` (line 61)

**Reason:** CLI, API, and SDK already import core modules directly via `@import("../core/core.zig")`. The `linkLibrary()` was redundant and could cause linker conflicts.

---

## Compilation Steps

### 1. Build All Targets

```bash
cd /home/user/kfork/zig-impl
zig build
```

**Expected Output:**
```
Build libk7core.a
Build k7
Build k7-api
Build libk7sdk.so
```

**Expected Artifacts:**
- `zig-out/lib/libk7core.a` - Core library (static)
- `zig-out/bin/k7` - CLI executable
- `zig-out/bin/k7-api` - API server executable
- `zig-out/lib/libk7sdk.so` - C-compatible SDK (shared library)

### 2. Build Specific Targets

```bash
# Build only CLI
zig build install -Dtarget=k7

# Build only API server
zig build install -Dtarget=k7-api

# Build only SDK
zig build install -Dtarget=k7sdk
```

### 3. Build with Optimization

```bash
# Debug build (default)
zig build

# Release with safety checks
zig build -Doptimize=ReleaseSafe

# Release optimized (production)
zig build -Doptimize=ReleaseFast

# Smallest binary size
zig build -Doptimize=ReleaseSmall
```

---

## Testing

### 1. Run Unit Tests

```bash
cd /home/user/kfork/zig-impl
zig build test
```

**Test Files:**
- `src/core/models.zig` - Contains 5 unit tests

**Expected Tests:**
1. ✅ `SandboxConfig: initialization`
2. ✅ `SandboxConfig: validation`
3. ✅ `SandboxConfig: JSON serialization`
4. ✅ `ExecResult: creation and JSON`
5. ✅ `OperationResult: success and error results`

**Expected Output:**
```
All 5 tests passed.
```

### 2. Test CLI

```bash
# Test CLI compiles and runs
zig build run-cli -- --help

# Expected output:
# K7/Katakate CLI v0.0.3
# Usage: k7 <command> [options]
# ...
```

**Test Commands:**
```bash
# Test version
zig build run-cli -- --version

# Test generate-api-key
zig build run-cli -- generate-api-key test-key

# Test list (requires Kubernetes)
export KUBECONFIG=/path/to/kubeconfig
zig build run-cli -- list

# Test create (requires Kubernetes)
zig build run-cli -- create --name test --image alpine:latest
```

### 3. Test API Server

```bash
# Start API server
export KUBECONFIG=/path/to/kubeconfig
export K7_API_KEY=your-api-key-here
zig build run-api

# In another terminal, test endpoints
curl http://localhost:8000/

# Expected:
# {"name":"K7/Katakate API","version":"0.0.3","status":"running"}

curl http://localhost:8000/health

# Expected:
# {"status":"healthy","checks":{"kubernetes":"ok","metrics_api":"ok"}}
```

---

## Expected Compilation Issues

### Potential Issues and Solutions

#### Issue 1: HTTP Client API Changes
**Symptoms:** Compilation errors in `src/kubernetes/client.zig` related to `std.http`

**Cause:** Zig 0.13 may have changed HTTP client APIs

**Solution:**
```zig
// If std.http.Client signature changed, update:
var client = std.http.Client{ .allocator = self.allocator };
```

#### Issue 2: JSON Parsing API Changes
**Symptoms:** Errors related to `std.json.parseFromSlice`

**Cause:** JSON API might have changed between Zig versions

**Solution:**
```zig
// Check latest Zig documentation for parseFromSlice signature
// Current usage:
const parsed = std.json.parseFromSlice(
    std.json.Value,
    arena_allocator,
    json_string,
    .{},
);
```

#### Issue 3: Build System Changes
**Symptoms:** Errors in `build.zig` related to `b.path()`

**Cause:** Build API changes in Zig 0.13

**Solution:**
```zig
// If b.path() doesn't exist, try:
.root_source_file = .{ .path = "src/cli/main.zig" },
// OR
.root_source_file = b.pathFromRoot("src/cli/main.zig"),
```

#### Issue 4: Process.Child API Changes
**Symptoms:** Errors in `installNode()` function in `core.zig`

**Cause:** std.process.Child API changes

**Solution:**
```zig
// Check current Child.init() signature
var child = std.process.Child.init(argv, self.allocator);
// May need to change to:
var child = try std.process.Child.init(.{
    .allocator = self.allocator,
    .argv = argv,
});
```

---

## Code Review Checklist

Before first compilation, verify:

- [ ] All `@import()` statements use correct relative paths
- [ ] All `pub fn` signatures match between declaration and definition
- [ ] All `defer` statements pair with allocations
- [ ] All `errdefer` statements handle partial initialization
- [ ] All arena allocators are properly deinitialized
- [ ] No unused variables (all `_ = var;` are intentional)
- [ ] All HTTP methods use correct Zig 0.13 APIs
- [ ] All JSON parsing uses correct API signatures
- [ ] All file I/O uses correct Zig 0.13 patterns

---

## Integration Test Plan

### Test Environment Setup

```bash
# 1. Install Kubernetes (minikube or kind)
minikube start --driver=docker

# OR
kind create cluster

# 2. Install Kata Containers runtime
# Follow: https://github.com/kata-containers/kata-containers/blob/main/docs/install/README.md

# 3. Verify Kata is available
kubectl get runtimeclass

# Expected output should include:
# kata
```

### Integration Tests

#### Test 1: Sandbox Creation
```bash
# Create sandbox
k7 create --name test-sandbox --image alpine:latest

# Expected: Success message
# Verify:
kubectl get pods -l managed-by=k7
# Should show: test-sandbox-xxx Running
```

#### Test 2: Sandbox Listing
```bash
# List sandboxes
k7 list

# Expected output (table format):
# NAME            NAMESPACE  STATUS   AGE
# test-sandbox    default    Running  1m
```

#### Test 3: Command Execution
```bash
# Execute command
k7 shell test-sandbox -- ls -la

# Expected: Directory listing from container
```

#### Test 4: Metrics
```bash
# Get metrics
k7 top

# Expected output (table format):
# NAME            NAMESPACE  CPU    MEMORY
# test-sandbox    default    10m    128Mi
```

#### Test 5: Deletion
```bash
# Delete sandbox
k7 delete test-sandbox

# Expected: Success message
# Verify:
kubectl get pods -l managed-by=k7
# Should show: No resources found
```

#### Test 6: API Server
```bash
# Start API server
export K7_API_KEY=$(k7 generate-api-key admin | grep "API Key:" | awk '{print $3}')
k7-api &

# Test endpoints
curl -H "X-API-Key: $K7_API_KEY" http://localhost:8000/api/v1/sandboxes

# Expected: JSON array of sandboxes

# Create via API
curl -X POST \
  -H "X-API-Key: $K7_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"name":"api-test","image":"alpine:latest"}' \
  http://localhost:8000/api/v1/sandboxes

# Expected: 201 Created with JSON response
```

#### Test 7: Installation Feature
```bash
# Test Ansible integration (requires ansible-playbook)
curl -X POST \
  -H "X-API-Key: $K7_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"verbose":true}' \
  http://localhost:8000/api/v1/install

# Expected: Success with Ansible output
```

---

## Performance Benchmarking

### Benchmark Suite

```bash
# 1. Startup time
time k7 --version
# Target: < 10ms

# 2. Binary size
ls -lh zig-out/bin/k7
# Target: < 10MB

# 3. Memory usage (at rest)
k7-api &
sleep 2
ps aux | grep k7-api | grep -v grep | awk '{print $6/1024 "MB"}'
# Target: < 10MB

# 4. Request latency (p50)
# Using Apache Bench:
export K7_API_KEY=your-key
ab -n 1000 -c 10 -H "X-API-Key: $K7_API_KEY" http://localhost:8000/health
# Target p50: < 1ms

# 5. Throughput
wrk -t4 -c100 -d30s -H "X-API-Key: $K7_API_KEY" http://localhost:8000/health
# Target: > 5000 req/sec
```

### Expected Performance

| Metric | Python (Current) | Zig (Target) | Actual | Status |
|--------|------------------|--------------|--------|--------|
| Startup Time | 500ms | 10ms | TBD | ⏱️ |
| Binary Size | 500MB | 5-10MB | TBD | ⏱️ |
| Memory (rest) | 50MB | 10MB | TBD | ⏱️ |
| Memory (load) | 200MB | 30MB | TBD | ⏱️ |
| Latency (p50) | 5ms | 1ms | TBD | ⏱️ |
| Latency (p99) | 50ms | 5ms | TBD | ⏱️ |
| Throughput | 2500 rps | 5000 rps | TBD | ⏱️ |

---

## Troubleshooting

### Compilation Errors

**Error: `zig: command not found`**
```bash
# Solution: Add Zig to PATH
export PATH=$PATH:/usr/local/zig
```

**Error: `error: unable to find module 'std'`**
```bash
# Solution: Zig installation is incomplete, reinstall
rm -rf /usr/local/zig
# Re-download and extract
```

**Error: `error: no member named 'xxx' in 'std.http'`**
```bash
# Solution: API changed in Zig version, check documentation
zig version
# Update code to match current std.http API
```

### Runtime Errors

**Error: `Failed to connect to Kubernetes API`**
```bash
# Solution: Check KUBECONFIG
echo $KUBECONFIG
kubectl cluster-info
```

**Error: `Unauthorized: Invalid or missing API key`**
```bash
# Solution: Generate and use API key
export K7_API_KEY=$(k7 generate-api-key admin | grep "API Key:" | awk '{print $3}')
```

**Error: `RuntimeClass 'kata' not found`**
```bash
# Solution: Install Kata Containers runtime class
kubectl apply -f https://raw.githubusercontent.com/kata-containers/kata-containers/main/tools/packaging/kata-deploy/runtimeclasses/kata-runtimeclass.yaml
```

---

## Success Criteria

All criteria must pass before declaring production-ready:

- [ ] ✅ Compilation: Zero errors, zero warnings
- [ ] ✅ Unit Tests: 100% pass rate (5/5 tests)
- [ ] ✅ CLI: All 8 commands functional
- [ ] ✅ API: All 10 endpoints return correct responses
- [ ] ✅ Integration: Create → List → Exec → Delete flow works
- [ ] ✅ Performance: Meets all target metrics
- [ ] ✅ Memory: No leaks detected (valgrind clean)
- [ ] ✅ Security: All sandboxes properly isolated
- [ ] ✅ Network: Egress policies enforced
- [ ] ✅ Monitoring: Health checks accurate

---

## Next Steps After Compilation Success

1. **Package Distribution**
   ```bash
   # Create Debian package
   ./scripts/build-deb.sh

   # Create RPM package
   ./scripts/build-rpm.sh

   # Create Docker image
   docker build -t k7-api:v0.0.3 .
   ```

2. **Production Deployment**
   ```bash
   # Deploy to Kubernetes
   kubectl apply -f k8s/deployment.yaml

   # Verify deployment
   kubectl get pods -n k7-system
   ```

3. **Migration from Python**
   ```bash
   # Run side-by-side comparison
   ./scripts/compare-python-zig.sh

   # Gradual traffic shift
   ./scripts/migrate-traffic.sh 10%  # 10% to Zig
   ./scripts/migrate-traffic.sh 50%  # 50% to Zig
   ./scripts/migrate-traffic.sh 100% # Full migration
   ```

4. **Monitoring Setup**
   ```bash
   # Configure Prometheus scraping
   # Configure Grafana dashboards
   # Set up alerting rules
   ```

---

**Document Status:** Ready for execution
**Last Updated:** 2025-01-15
**Next Action:** Install Zig toolchain and run `zig build test`
