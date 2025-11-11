const std = @import("std");
const models = @import("../core/models.zig");
const core = @import("../core/core.zig");

const K7_API_VERSION = "0.0.3";
const DEFAULT_PORT: u16 = 8000;
const DEFAULT_HOST = "0.0.0.0";

// ============================================================================
// API Key Store
// ============================================================================

pub const ApiKeyStore = struct {
    allocator: std.mem.Allocator,
    keys: std.StringHashMap([]const u8), // key_hash -> key_name

    pub fn init(allocator: std.mem.Allocator) ApiKeyStore {
        return ApiKeyStore{
            .allocator = allocator,
            .keys = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *ApiKeyStore) void {
        var it = self.keys.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.keys.deinit();
    }

    /// Add an API key (stores SHA256 hash)
    pub fn addKey(self: *ApiKeyStore, key: []const u8, name: []const u8) !void {
        const hash = try self.hashKey(key);
        const name_copy = try self.allocator.dupe(u8, name);
        try self.keys.put(hash, name_copy);
    }

    /// Verify API key (constant-time comparison)
    pub fn verifyKey(self: *ApiKeyStore, key: []const u8) !bool {
        const hash = try self.hashKey(key);
        defer self.allocator.free(hash);

        return self.keys.contains(hash);
    }

    fn hashKey(self: *ApiKeyStore, key: []const u8) ![]const u8 {
        var hasher = std.crypto.hash.sha2.Sha256.init(.{});
        hasher.update(key);
        var digest: [32]u8 = undefined;
        hasher.final(&digest);

        // Convert to hex string
        var hex = try self.allocator.alloc(u8, 64);
        _ = try std.fmt.bufPrint(hex, "{}", .{std.fmt.fmtSliceHexLower(&digest)});
        return hex;
    }
};

// ============================================================================
// HTTP Server
// ============================================================================

pub const ApiServer = struct {
    allocator: std.mem.Allocator,
    address: std.net.Address,
    api_key_store: ApiKeyStore,
    k7_core: core.K7Core,
    running: bool,

    pub fn init(
        allocator: std.mem.Allocator,
        host: []const u8,
        port: u16,
        kubeconfig_path: ?[]const u8,
    ) !ApiServer {
        const address = try std.net.Address.parseIp(host, port);
        var api_key_store = ApiKeyStore.init(allocator);

        // Load API keys from environment or config
        // For now, create a default key for testing
        const default_key = std.os.getenv("K7_API_KEY") orelse "dev-api-key-changeme";
        try api_key_store.addKey(default_key, "default");

        const k7_core = try core.K7Core.init(allocator, kubeconfig_path);

        return ApiServer{
            .allocator = allocator,
            .address = address,
            .api_key_store = api_key_store,
            .k7_core = k7_core,
            .running = false,
        };
    }

    pub fn deinit(self: *ApiServer) void {
        self.api_key_store.deinit();
        self.k7_core.deinit();
    }

    pub fn start(self: *ApiServer) !void {
        const stdout = std.io.getStdOut().writer();

        try stdout.print("K7 API Server v{s}\n", .{K7_API_VERSION});
        try stdout.print("Listening on http://{}\n", .{self.address});
        try stdout.print("Press Ctrl+C to stop\n\n");

        var server = std.http.Server.init(self.allocator, .{ .reuse_address = true });
        defer server.deinit();

        try server.listen(self.address);
        self.running = true;

        while (self.running) {
            // Accept connection
            var response = try server.accept(.{
                .allocator = self.allocator,
            });
            defer response.deinit();

            // Handle request
            while (response.reset() != .closing) {
                response.wait() catch |err| {
                    try stdout.print("Error waiting for request: {}\n", .{err});
                    continue;
                };

                try self.handleRequest(&response);
            }
        }
    }

    fn handleRequest(self: *ApiServer, response: *std.http.Server.Response) !void {
        const method = response.request.method;
        const target = response.request.target;

        // Log request
        const stdout = std.io.getStdOut().writer();
        try stdout.print("{s} {s}\n", .{ @tagName(method), target });

        // Authenticate (except for health and root endpoints)
        if (!std.mem.eql(u8, target, "/") and !std.mem.eql(u8, target, "/health")) {
            const authorized = try self.authenticate(response.request.headers);
            if (!authorized) {
                try self.sendJsonError(response, .unauthorized, "Invalid or missing API key");
                return;
            }
        }

        // Route request
        if (std.mem.eql(u8, target, "/")) {
            try self.handleRoot(response);
        } else if (std.mem.eql(u8, target, "/health")) {
            try self.handleHealth(response);
        } else if (std.mem.startsWith(u8, target, "/api/v1/sandboxes")) {
            try self.handleSandboxesRoute(response, method, target);
        } else if (std.mem.eql(u8, target, "/api/v1/install")) {
            try self.handleInstall(response);
        } else {
            try self.sendJsonError(response, .not_found, "Endpoint not found");
        }
    }

    fn authenticate(self: *ApiServer, headers: std.http.Headers) !bool {
        var it = headers.iterator();
        while (it.next()) |header| {
            if (std.ascii.eqlIgnoreCase(header.name, "authorization")) {
                // Format: "Bearer <api-key>"
                if (std.mem.startsWith(u8, header.value, "Bearer ")) {
                    const api_key = header.value[7..];
                    return try self.api_key_store.verifyKey(api_key);
                }
            }
            if (std.ascii.eqlIgnoreCase(header.name, "x-api-key")) {
                return try self.api_key_store.verifyKey(header.value);
            }
        }
        return false;
    }

    // ========================================================================
    // Route Handlers
    // ========================================================================

    fn handleRoot(self: *ApiServer, response: *std.http.Server.Response) !void {
        _ = self;
        const body = try std.fmt.allocPrint(
            response.allocator,
            "{{\"name\":\"K7/Katakate API\",\"version\":\"{s}\",\"status\":\"running\"}}",
            .{K7_API_VERSION},
        );
        defer response.allocator.free(body);

        try response.headers.append("content-type", "application/json");
        response.status = .ok;
        try response.do();
        try response.writeAll(body);
        try response.finish();
    }

    fn handleHealth(self: *ApiServer, response: *std.http.Server.Response) !void {
        _ = self;
        const body = "{\"status\":\"healthy\"}";

        try response.headers.append("content-type", "application/json");
        response.status = .ok;
        try response.do();
        try response.writeAll(body);
        try response.finish();
    }

    fn handleSandboxesRoute(
        self: *ApiServer,
        response: *std.http.Server.Response,
        method: std.http.Method,
        target: []const u8,
    ) !void {
        if (std.mem.eql(u8, target, "/api/v1/sandboxes")) {
            // /api/v1/sandboxes - list or create
            if (method == .GET) {
                try self.handleListSandboxes(response);
            } else if (method == .POST) {
                try self.handleCreateSandbox(response);
            } else if (method == .DELETE) {
                try self.handleDeleteAllSandboxes(response);
            } else {
                try self.sendJsonError(response, .method_not_allowed, "Method not allowed");
            }
        } else if (std.mem.eql(u8, target, "/api/v1/sandboxes/metrics")) {
            // /api/v1/sandboxes/metrics
            try self.handleGetMetrics(response);
        } else {
            // /api/v1/sandboxes/{name} or /api/v1/sandboxes/{name}/exec
            const sandbox_prefix = "/api/v1/sandboxes/";
            if (std.mem.startsWith(u8, target, sandbox_prefix)) {
                const rest = target[sandbox_prefix.len..];

                if (std.mem.indexOf(u8, rest, "/exec")) |exec_idx| {
                    const name = rest[0..exec_idx];
                    if (method == .POST) {
                        try self.handleExecCommand(response, name);
                    } else {
                        try self.sendJsonError(response, .method_not_allowed, "Method not allowed");
                    }
                } else {
                    // Just sandbox name
                    if (method == .GET) {
                        try self.handleGetSandbox(response, rest);
                    } else if (method == .DELETE) {
                        try self.handleDeleteSandbox(response, rest);
                    } else {
                        try self.sendJsonError(response, .method_not_allowed, "Method not allowed");
                    }
                }
            } else {
                try self.sendJsonError(response, .not_found, "Endpoint not found");
            }
        }
    }

    fn handleCreateSandbox(self: *ApiServer, response: *std.http.Server.Response) !void {
        // Read request body
        var body_buffer: [1024 * 1024]u8 = undefined; // 1MB max
        const body = try response.reader().readAll(&body_buffer);

        // Parse JSON into SandboxConfig
        const config = models.SandboxConfig.fromJson(self.allocator, body[0..body.len]) catch |err| {
            const err_msg = try std.fmt.allocPrint(
                self.allocator,
                "Invalid request body: {s}",
                .{@errorName(err)},
            );
            defer self.allocator.free(err_msg);
            try self.sendJsonError(response, .bad_request, err_msg);
            return;
        };

        // Create sandbox
        const result = self.k7_core.createSandbox(config, null) catch |err| {
            const err_msg = try std.fmt.allocPrint(
                self.allocator,
                "Failed to create sandbox: {s}",
                .{@errorName(err)},
            );
            defer self.allocator.free(err_msg);
            try self.sendJsonError(response, .internal_server_error, err_msg);
            return;
        };
        defer result.deinit(self.allocator);

        // Send response
        const json = try result.toJson(self.allocator);
        defer self.allocator.free(json);

        try response.headers.append("content-type", "application/json");
        response.status = .created;
        try response.do();
        try response.writeAll(json);
        try response.finish();
    }

    fn handleListSandboxes(self: *ApiServer, response: *std.http.Server.Response) !void {
        // Parse namespace from query params
        const target = response.request.target;
        const namespace_param = try parseQueryParam(self.allocator, target, "namespace");
        defer if (namespace_param) |ns| self.allocator.free(ns);

        const namespace: ?[]const u8 = namespace_param;

        const sandboxes = self.k7_core.listSandboxes(namespace) catch |err| {
            const err_msg = try std.fmt.allocPrint(
                self.allocator,
                "Failed to list sandboxes: {s}",
                .{@errorName(err)},
            );
            defer self.allocator.free(err_msg);
            try self.sendJsonError(response, .internal_server_error, err_msg);
            return;
        };
        defer self.allocator.free(sandboxes);

        // Serialize to JSON
        var json_array = std.ArrayList(u8).init(self.allocator);
        defer json_array.deinit();

        try json_array.append('[');
        for (sandboxes, 0..) |sandbox, i| {
            if (i > 0) try json_array.append(',');
            const sandbox_json = try sandbox.toJson(self.allocator);
            defer self.allocator.free(sandbox_json);
            try json_array.appendSlice(sandbox_json);
        }
        try json_array.append(']');

        const json = try json_array.toOwnedSlice();
        defer self.allocator.free(json);

        try response.headers.append("content-type", "application/json");
        response.status = .ok;
        try response.do();
        try response.writeAll(json);
        try response.finish();
    }

    fn handleGetSandbox(self: *ApiServer, response: *std.http.Server.Response, name: []const u8) !void {
        _ = self;
        _ = name;
        // TODO: Implement get single sandbox
        try self.sendJsonError(response, .not_implemented, "Get sandbox not yet implemented");
    }

    fn handleDeleteSandbox(self: *ApiServer, response: *std.http.Server.Response, name: []const u8) !void {
        // Parse namespace from query params (default: "default")
        const target = response.request.target;
        const namespace_param = try parseQueryParam(self.allocator, target, "namespace");
        defer if (namespace_param) |ns| self.allocator.free(ns);

        const namespace = namespace_param orelse "default";

        const result = self.k7_core.deleteSandbox(name, namespace) catch |err| {
            const err_msg = try std.fmt.allocPrint(
                self.allocator,
                "Failed to delete sandbox: {s}",
                .{@errorName(err)},
            );
            defer self.allocator.free(err_msg);
            try self.sendJsonError(response, .internal_server_error, err_msg);
            return;
        };
        defer result.deinit(self.allocator);

        const json = try result.toJson(self.allocator);
        defer self.allocator.free(json);

        try response.headers.append("content-type", "application/json");
        response.status = .ok;
        try response.do();
        try response.writeAll(json);
        try response.finish();
    }

    fn handleDeleteAllSandboxes(self: *ApiServer, response: *std.http.Server.Response) !void {
        // Parse namespace from query params (default: "default")
        const target = response.request.target;
        const namespace_param = try parseQueryParam(self.allocator, target, "namespace");
        defer if (namespace_param) |ns| self.allocator.free(ns);

        const namespace = namespace_param orelse "default";

        const result = self.k7_core.deleteAllSandboxes(namespace) catch |err| {
            const err_msg = try std.fmt.allocPrint(
                self.allocator,
                "Failed to delete sandboxes: {s}",
                .{@errorName(err)},
            );
            defer self.allocator.free(err_msg);
            try self.sendJsonError(response, .internal_server_error, err_msg);
            return;
        };
        defer result.deinit(self.allocator);

        const json = try result.toJson(self.allocator);
        defer self.allocator.free(json);

        try response.headers.append("content-type", "application/json");
        response.status = .ok;
        try response.do();
        try response.writeAll(json);
        try response.finish();
    }

    fn handleExecCommand(self: *ApiServer, response: *std.http.Server.Response, sandbox_name: []const u8) !void {
        // Parse namespace from query params (default: "default")
        const target = response.request.target;
        const namespace_param = try parseQueryParam(self.allocator, target, "namespace");
        defer if (namespace_param) |ns| self.allocator.free(ns);

        const namespace = namespace_param orelse "default";

        // Read request body
        var body_buffer: [1024 * 1024]u8 = undefined;
        const body = try response.reader().readAll(&body_buffer);

        // Parse JSON to get command
        // Expected format: {"command": "ls -la"}
        const command = blk: {
            var arena = std.heap.ArenaAllocator.init(self.allocator);
            defer arena.deinit();
            const arena_allocator = arena.allocator();

            const parsed = std.json.parseFromSlice(
                std.json.Value,
                arena_allocator,
                body,
                .{},
            ) catch {
                try self.sendJsonError(response, .bad_request, "Invalid JSON in request body");
                return;
            };

            const root = parsed.value;
            if (root != .object) {
                try self.sendJsonError(response, .bad_request, "Request body must be JSON object");
                return;
            }

            const cmd_value = root.object.get("command") orelse {
                try self.sendJsonError(response, .bad_request, "Missing 'command' field in request body");
                return;
            };

            if (cmd_value != .string) {
                try self.sendJsonError(response, .bad_request, "'command' must be a string");
                return;
            }

            break :blk try self.allocator.dupe(u8, cmd_value.string);
        };
        defer self.allocator.free(command);

        const result = self.k7_core.execCommand(sandbox_name, command, namespace) catch |err| {
            const err_msg = try std.fmt.allocPrint(
                self.allocator,
                "Failed to execute command: {s}",
                .{@errorName(err)},
            );
            defer self.allocator.free(err_msg);
            try self.sendJsonError(response, .internal_server_error, err_msg);
            return;
        };
        defer result.deinit(self.allocator);

        _ = body;

        const json = try result.toJson(self.allocator);
        defer self.allocator.free(json);

        try response.headers.append("content-type", "application/json");
        response.status = .ok;
        try response.do();
        try response.writeAll(json);
        try response.finish();
    }

    fn handleGetMetrics(self: *ApiServer, response: *std.http.Server.Response) !void {
        // Parse namespace from query params
        const target = response.request.target;
        const namespace_param = try parseQueryParam(self.allocator, target, "namespace");
        defer if (namespace_param) |ns| self.allocator.free(ns);

        const namespace: ?[]const u8 = namespace_param;

        const metrics = self.k7_core.getSandboxMetrics(namespace) catch |err| {
            const err_msg = try std.fmt.allocPrint(
                self.allocator,
                "Failed to get metrics: {s}",
                .{@errorName(err)},
            );
            defer self.allocator.free(err_msg);
            try self.sendJsonError(response, .internal_server_error, err_msg);
            return;
        };
        defer self.allocator.free(metrics);

        // Serialize metrics to JSON
        var json_array = std.ArrayList(u8).init(self.allocator);
        defer json_array.deinit();

        try json_array.append('[');
        for (metrics, 0..) |metric, i| {
            if (i > 0) try json_array.append(',');

            // Manually build JSON object for each metric
            // {"name":"pod-name","namespace":"default","cpu_usage":"100m","memory_usage":"256Mi"}
            const metric_json = try std.fmt.allocPrint(
                self.allocator,
                "{{\"name\":\"{s}\",\"namespace\":\"{s}\",\"cpu_usage\":\"{s}\",\"memory_usage\":\"{s}\"}}",
                .{ metric.name, metric.namespace, metric.cpu_usage, metric.memory_usage },
            );
            defer self.allocator.free(metric_json);

            try json_array.appendSlice(metric_json);
        }
        try json_array.append(']');

        const json = try json_array.toOwnedSlice();
        defer self.allocator.free(json);

        try response.headers.append("content-type", "application/json");
        response.status = .ok;
        try response.do();
        try response.writeAll(json);
        try response.finish();
    }

    fn handleInstall(self: *ApiServer, response: *std.http.Server.Response) !void {
        _ = self;
        // TODO: Implement installation endpoint
        try self.sendJsonError(response, .not_implemented, "Install endpoint not yet implemented");
    }

    // ========================================================================
    // Helper Methods
    // ========================================================================

    /// Parse a query parameter from URL target
    /// Example: parseQueryParam("/api/v1/sandboxes?namespace=prod", "namespace") -> "prod"
    fn parseQueryParam(allocator: std.mem.Allocator, target: []const u8, param_name: []const u8) !?[]const u8 {
        // Find query string start
        const query_start = std.mem.indexOf(u8, target, "?") orelse return null;
        if (query_start + 1 >= target.len) return null;

        const query_string = target[query_start + 1 ..];

        // Split by & to get individual params
        var iter = std.mem.splitScalar(u8, query_string, '&');
        while (iter.next()) |param| {
            // Split by = to get key and value
            const eq_pos = std.mem.indexOf(u8, param, "=") orelse continue;
            if (eq_pos == 0 or eq_pos + 1 >= param.len) continue;

            const key = param[0..eq_pos];
            const value = param[eq_pos + 1 ..];

            if (std.mem.eql(u8, key, param_name)) {
                // URL decode value (basic implementation)
                return try urlDecode(allocator, value);
            }
        }

        return null;
    }

    /// Basic URL decode (handles %20, %2F, etc.)
    fn urlDecode(allocator: std.mem.Allocator, encoded: []const u8) ![]const u8 {
        var decoded = std.ArrayList(u8).init(allocator);
        defer decoded.deinit();

        var i: usize = 0;
        while (i < encoded.len) {
            if (encoded[i] == '%' and i + 2 < encoded.len) {
                // Decode %XX hex sequence
                const hex_str = encoded[i + 1 .. i + 3];
                const byte = std.fmt.parseInt(u8, hex_str, 16) catch {
                    // Invalid hex, keep as-is
                    try decoded.append(encoded[i]);
                    i += 1;
                    continue;
                };
                try decoded.append(byte);
                i += 3;
            } else if (encoded[i] == '+') {
                // + is space in query strings
                try decoded.append(' ');
                i += 1;
            } else {
                try decoded.append(encoded[i]);
                i += 1;
            }
        }

        return try decoded.toOwnedSlice();
    }

    fn sendJsonError(
        self: *ApiServer,
        response: *std.http.Server.Response,
        status: std.http.Status,
        message: []const u8,
    ) !void {
        _ = self;
        const body = try std.fmt.allocPrint(
            response.allocator,
            "{{\"error\":\"{s}\"}}",
            .{message},
        );
        defer response.allocator.free(body);

        try response.headers.append("content-type", "application/json");
        response.status = status;
        try response.do();
        try response.writeAll(body);
        try response.finish();
    }
};

// ============================================================================
// Main Entry Point
// ============================================================================

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse command line arguments
    const kubeconfig_path = std.os.getenv("KUBECONFIG");
    const port_str = std.os.getenv("K7_PORT") orelse "8000";
    const port = try std.fmt.parseInt(u16, port_str, 10);

    var server = try ApiServer.init(allocator, DEFAULT_HOST, port, kubeconfig_path);
    defer server.deinit();

    try server.start();
}
