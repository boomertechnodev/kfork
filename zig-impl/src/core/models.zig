const std = @import("std");
const Allocator = std.mem.Allocator;

/// Sandbox configuration model
pub const SandboxConfig = struct {
    name: []const u8,
    image: []const u8,
    namespace: []const u8 = "default",
    env_file: ?[]const u8 = null,
    egress_whitelist: ?[][]const u8 = null,
    limits: ?std.StringHashMap([]const u8) = null,
    before_script: []const u8 = "",
    pod_non_root: bool = false,
    container_non_root: bool = false,
    cap_drop: ?[][]const u8 = null,
    cap_add: ?[][]const u8 = null,

    /// Initialize a new SandboxConfig with an allocator
    pub fn init(allocator: Allocator) !SandboxConfig {
        return SandboxConfig{
            .name = "",
            .image = "",
            .namespace = "default",
            .env_file = null,
            .egress_whitelist = null,
            .limits = null,
            .before_script = "",
            .pod_non_root = false,
            .container_non_root = false,
            .cap_drop = null,
            .cap_add = null,
        };
    }

    /// Free all allocated memory
    pub fn deinit(self: *SandboxConfig, allocator: Allocator) void {
        if (self.egress_whitelist) |whitelist| {
            for (whitelist) |item| {
                allocator.free(item);
            }
            allocator.free(whitelist);
        }

        if (self.limits) |*limits_map| {
            var it = limits_map.iterator();
            while (it.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                allocator.free(entry.value_ptr.*);
            }
            limits_map.deinit();
        }

        if (self.cap_drop) |caps| {
            for (caps) |cap| {
                allocator.free(cap);
            }
            allocator.free(caps);
        }

        if (self.cap_add) |caps| {
            for (caps) |cap| {
                allocator.free(cap);
            }
            allocator.free(caps);
        }
    }

    /// Parse from JSON
    pub fn fromJson(allocator: Allocator, json_str: []const u8) !SandboxConfig {
        const parsed = try std.json.parseFromSlice(
            SandboxConfig,
            allocator,
            json_str,
            .{ .allocate = .alloc_always },
        );
        return parsed.value;
    }

    /// Convert to JSON
    pub fn toJson(self: *const SandboxConfig, allocator: Allocator) ![]const u8 {
        var string = std.ArrayList(u8).init(allocator);
        errdefer string.deinit();

        try std.json.stringify(self, .{}, string.writer());
        return string.toOwnedSlice();
    }

    /// Validate configuration
    pub fn validate(self: *const SandboxConfig) !void {
        if (self.name.len == 0) {
            return error.InvalidName;
        }
        if (self.image.len == 0) {
            return error.InvalidImage;
        }
        if (self.namespace.len == 0) {
            return error.InvalidNamespace;
        }
    }
};

/// Sandbox information model
pub const SandboxInfo = struct {
    name: []const u8,
    namespace: []const u8,
    status: []const u8,
    ready: []const u8,
    restarts: i32,
    age: []const u8,
    image: []const u8,
    error_message: []const u8 = "",

    /// Free allocated memory
    pub fn deinit(self: *SandboxInfo, allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.namespace);
        allocator.free(self.status);
        allocator.free(self.ready);
        allocator.free(self.age);
        allocator.free(self.image);
        if (self.error_message.len > 0) {
            allocator.free(self.error_message);
        }
    }

    /// Convert to JSON
    pub fn toJson(self: *const SandboxInfo, allocator: Allocator) ![]const u8 {
        var string = std.ArrayList(u8).init(allocator);
        errdefer string.deinit();

        try std.json.stringify(self, .{}, string.writer());
        return string.toOwnedSlice();
    }
};

/// Command execution result
pub const ExecResult = struct {
    exit_code: i32,
    stdout: []const u8,
    stderr: []const u8,
    duration_ms: i64,

    /// Free allocated memory
    pub fn deinit(self: *ExecResult, allocator: Allocator) void {
        allocator.free(self.stdout);
        allocator.free(self.stderr);
    }

    /// Convert to JSON
    pub fn toJson(self: *const ExecResult, allocator: Allocator) ![]const u8 {
        var string = std.ArrayList(u8).init(allocator);
        errdefer string.deinit();

        try std.json.stringify(self, .{}, string.writer());
        return string.toOwnedSlice();
    }
};

/// Generic operation result
pub const OperationResult = struct {
    success: bool,
    message: []const u8 = "",
    err: []const u8 = "",
    data: ?std.json.Value = null,

    /// Free allocated memory
    pub fn deinit(self: *OperationResult, allocator: Allocator) void {
        if (self.message.len > 0) {
            allocator.free(self.message);
        }
        if (self.err.len > 0) {
            allocator.free(self.err);
        }
        if (self.data) |data| {
            data.deinit();
        }
    }

    /// Convert to JSON
    pub fn toJson(self: *const OperationResult, allocator: Allocator) ![]const u8 {
        var string = std.ArrayList(u8).init(allocator);
        errdefer string.deinit();

        try std.json.stringify(self, .{}, string.writer());
        return string.toOwnedSlice();
    }

    /// Create success result
    pub fn success_result(allocator: Allocator, message: []const u8) !OperationResult {
        const msg_copy = try allocator.dupe(u8, message);
        return OperationResult{
            .success = true,
            .message = msg_copy,
            .err = "",
            .data = null,
        };
    }

    /// Create error result
    pub fn error_result(allocator: Allocator, error_msg: []const u8) !OperationResult {
        const err_copy = try allocator.dupe(u8, error_msg);
        return OperationResult{
            .success = false,
            .message = "",
            .err = err_copy,
            .data = null,
        };
    }
};

// =============================================================================
// Unit Tests
// =============================================================================

test "SandboxConfig: initialization" {
    const allocator = std.testing.allocator;

    var config = try SandboxConfig.init(allocator);
    defer config.deinit(allocator);

    try std.testing.expectEqualStrings("", config.name);
    try std.testing.expectEqualStrings("", config.image);
    try std.testing.expectEqualStrings("default", config.namespace);
    try std.testing.expectEqual(@as(?[]const u8, null), config.env_file);
    try std.testing.expectEqual(false, config.pod_non_root);
    try std.testing.expectEqual(false, config.container_non_root);
}

test "SandboxConfig: validation" {
    const allocator = std.testing.allocator;

    var config = SandboxConfig{
        .name = "test-sandbox",
        .image = "alpine:latest",
        .namespace = "default",
        .env_file = null,
        .egress_whitelist = null,
        .limits = null,
        .before_script = "",
        .pod_non_root = false,
        .container_non_root = false,
        .cap_drop = null,
        .cap_add = null,
    };

    try config.validate();

    // Test invalid config
    var invalid_config = config;
    invalid_config.name = "";
    try std.testing.expectError(error.InvalidName, invalid_config.validate());
}

test "SandboxConfig: JSON serialization" {
    const allocator = std.testing.allocator;

    const json_str =
        \\{
        \\  "name": "test",
        \\  "image": "alpine:latest",
        \\  "namespace": "default",
        \\  "env_file": null,
        \\  "egress_whitelist": null,
        \\  "limits": null,
        \\  "before_script": "",
        \\  "pod_non_root": false,
        \\  "container_non_root": false,
        \\  "cap_drop": null,
        \\  "cap_add": null
        \\}
    ;

    const config = try SandboxConfig.fromJson(allocator, json_str);
    defer {
        var mutable_config = config;
        mutable_config.deinit(allocator);
    }

    try std.testing.expectEqualStrings("test", config.name);
    try std.testing.expectEqualStrings("alpine:latest", config.image);
}

test "ExecResult: creation and JSON" {
    const allocator = std.testing.allocator;

    const stdout_copy = try allocator.dupe(u8, "Hello World");
    const stderr_copy = try allocator.dupe(u8, "");

    var result = ExecResult{
        .exit_code = 0,
        .stdout = stdout_copy,
        .stderr = stderr_copy,
        .duration_ms = 123,
    };
    defer result.deinit(allocator);

    const json = try result.toJson(allocator);
    defer allocator.free(json);

    try std.testing.expect(json.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, json, "Hello World") != null);
}

test "OperationResult: success and error results" {
    const allocator = std.testing.allocator;

    var success = try OperationResult.success_result(allocator, "Operation succeeded");
    defer success.deinit(allocator);

    try std.testing.expectEqual(true, success.success);
    try std.testing.expectEqualStrings("Operation succeeded", success.message);

    var failure = try OperationResult.error_result(allocator, "Operation failed");
    defer failure.deinit(allocator);

    try std.testing.expectEqual(false, failure.success);
    try std.testing.expectEqualStrings("Operation failed", failure.err);
}
