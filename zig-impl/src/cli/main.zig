const std = @import("std");
const models = @import("../core/models.zig");
const core = @import("../core/core.zig");

const K7_VERSION = "0.0.3";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    // Parse command-line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        try printUsage(stdout);
        return;
    }

    const command = args[1];

    if (std.mem.eql(u8, command, "--version") or std.mem.eql(u8, command, "-V")) {
        try stdout.print("{s}\n", .{K7_VERSION});
        return;
    } else if (std.mem.eql(u8, command, "--help") or std.mem.eql(u8, command, "-h")) {
        try printUsage(stdout);
        return;
    } else if (std.mem.eql(u8, command, "install")) {
        try cmdInstall(allocator, args[2..], stdout, stderr);
    } else if (std.mem.eql(u8, command, "create")) {
        try cmdCreate(allocator, args[2..], stdout, stderr);
    } else if (std.mem.eql(u8, command, "list")) {
        try cmdList(allocator, args[2..], stdout, stderr);
    } else if (std.mem.eql(u8, command, "delete")) {
        try cmdDelete(allocator, args[2..], stdout, stderr);
    } else if (std.mem.eql(u8, command, "delete-all")) {
        try cmdDeleteAll(allocator, args[2..], stdout, stderr);
    } else if (std.mem.eql(u8, command, "shell")) {
        try cmdShell(allocator, args[2..], stdout, stderr);
    } else if (std.mem.eql(u8, command, "logs")) {
        try cmdLogs(allocator, args[2..], stdout, stderr);
    } else if (std.mem.eql(u8, command, "top")) {
        try cmdTop(allocator, args[2..], stdout, stderr);
    } else if (std.mem.eql(u8, command, "generate-api-key")) {
        try cmdGenerateApiKey(allocator, args[2..], stdout, stderr);
    } else if (std.mem.eql(u8, command, "list-api-keys")) {
        try cmdListApiKeys(allocator, args[2..], stdout, stderr);
    } else if (std.mem.eql(u8, command, "revoke-api-key")) {
        try cmdRevokeApiKey(allocator, args[2..], stdout, stderr);
    } else if (std.mem.eql(u8, command, "start-api")) {
        try cmdStartApi(allocator, args[2..], stdout, stderr);
    } else if (std.mem.eql(u8, command, "stop-api")) {
        try cmdStopApi(allocator, args[2..], stdout, stderr);
    } else if (std.mem.eql(u8, command, "api-status")) {
        try cmdApiStatus(allocator, args[2..], stdout, stderr);
    } else if (std.mem.eql(u8, command, "get-api-endpoint")) {
        try cmdGetApiEndpoint(allocator, args[2..], stdout, stderr);
    } else {
        try stderr.print("Unknown command: {s}\n\n", .{command});
        try printUsage(stderr);
        std.process.exit(1);
    }
}

fn printUsage(writer: anytype) !void {
    try writer.writeAll(
        \\K7 - Secure VM Sandbox Orchestration (Zig Implementation)
        \\
        \\Usage: k7 [OPTIONS] COMMAND [ARGS]...
        \\
        \\Options:
        \\  -h, --help     Show this help message
        \\  -V, --version  Show version and exit
        \\
        \\Commands:
        \\  install                Install K7 on target hosts using Ansible
        \\  create                 Create a new sandbox from YAML config or CLI arguments
        \\  list                   List all running sandboxes
        \\  delete <name>          Delete a sandbox and all its associated resources
        \\  delete-all             Delete all sandboxes in a namespace
        \\  shell <name>           Shell into sandbox (bypasses network policy)
        \\  logs <name>            Show sandbox pod logs
        \\  top                    Dynamic top-like view of sandbox resource usage
        \\  generate-api-key <name>  Generate a new API key
        \\  list-api-keys          List all API keys
        \\  revoke-api-key <name>  Revoke an API key by name
        \\  start-api              Start the K7 API server
        \\  stop-api               Stop the K7 API server
        \\  api-status             Show API server status and connection info
        \\  get-api-endpoint       Print the current Cloudflared public URL for the API
        \\
        \\For more information, see: https://docs.katakate.org
        \\
    );
}

// Placeholder implementations for commands
// Each of these would be implemented fully with proper K7Core integration

fn cmdInstall(allocator: std.mem.Allocator, args: [][]const u8, stdout: anytype, stderr: anytype) !void {
    _ = allocator;
    _ = args;
    _ = stderr;
    try stdout.writeAll("TODO: Implement install command (Ansible playbook execution)\n");
}

fn cmdCreate(allocator: std.mem.Allocator, args: [][]const u8, stdout: anytype, stderr: anytype) !void {
    // Parse arguments: --config <file> or inline args
    var config_file: ?[]const u8 = null;
    var name: ?[]const u8 = null;
    var image: ?[]const u8 = null;
    var namespace: []const u8 = "default";

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--config") or std.mem.eql(u8, arg, "-c")) {
            if (i + 1 >= args.len) {
                try stderr.writeAll("Error: --config requires a file path\n");
                return error.MissingArgument;
            }
            config_file = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "--name") or std.mem.eql(u8, arg, "-n")) {
            if (i + 1 >= args.len) {
                try stderr.writeAll("Error: --name requires a value\n");
                return error.MissingArgument;
            }
            name = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "--image") or std.mem.eql(u8, arg, "-i")) {
            if (i + 1 >= args.len) {
                try stderr.writeAll("Error: --image requires a value\n");
                return error.MissingArgument;
            }
            image = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "--namespace") or std.mem.eql(u8, arg, "-ns")) {
            if (i + 1 >= args.len) {
                try stderr.writeAll("Error: --namespace requires a value\n");
                return error.MissingArgument;
            }
            namespace = args[i + 1];
            i += 1;
        }
    }

    var config: models.SandboxConfig = undefined;

    if (config_file) |file_path| {
        // Load from YAML/JSON file
        const file_content = std.fs.cwd().readFileAlloc(allocator, file_path, 10 * 1024 * 1024) catch |err| {
            try stderr.print("Error reading config file: {s}\n", .{@errorName(err)});
            return error.FileReadFailed;
        };
        defer allocator.free(file_content);

        // TODO: Parse YAML (requires external library)
        // For now, try JSON
        config = models.SandboxConfig.fromJson(allocator, file_content) catch |err| {
            try stderr.print("Error parsing config: {s}\n", .{@errorName(err)});
            return error.ConfigParseFailed;
        };
    } else {
        // Create from CLI arguments
        if (name == null or image == null) {
            try stderr.writeAll("Error: --name and --image are required\n");
            return error.MissingArgument;
        }

        config = models.SandboxConfig{
            .name = name.?,
            .image = image.?,
            .namespace = namespace,
            .env_file = null,
            .egress_whitelist = null,
            .limits = null,
            .before_script = "",
            .pod_non_root = true,
            .container_non_root = true,
            .cap_drop = null,
            .cap_add = null,
        };
    }

    // Initialize K7Core
    const kubeconfig = std.os.getenv("KUBECONFIG");
    var k7_core = core.K7Core.init(allocator, kubeconfig) catch |err| {
        try stderr.print("Error initializing K7Core: {s}\n", .{@errorName(err)});
        return error.InitFailed;
    };
    defer k7_core.deinit();

    // Progress callback
    const ProgressCallback = struct {
        fn callback(event: core.ProgressEvent) void {
            const out = std.io.getStdOut().writer();
            out.print("[{s}] {s}", .{ event.stage, event.status }) catch {};
            if (event.message) |msg| {
                out.print(": {s}", .{msg}) catch {};
            }
            out.writeAll("\n") catch {};
        }
    };

    try stdout.print("Creating sandbox '{s}'...\n", .{config.name});

    // Create sandbox
    const result = k7_core.createSandbox(config, ProgressCallback.callback) catch |err| {
        try stderr.print("Error creating sandbox: {s}\n", .{@errorName(err)});
        return error.CreateFailed;
    };
    defer result.deinit(allocator);

    if (result.success) {
        try stdout.print("✓ Sandbox created successfully: {s}\n", .{result.message});
    } else {
        try stderr.print("✗ Failed to create sandbox: {s}\n", .{result.err});
        return error.CreateFailed;
    }
}

fn cmdList(allocator: std.mem.Allocator, args: [][]const u8, stdout: anytype, stderr: anytype) !void {
    // Parse namespace from args
    var namespace: ?[]const u8 = null;
    if (args.len > 0 and std.mem.eql(u8, args[0], "--namespace")) {
        if (args.len < 2) {
            try stderr.writeAll("Error: --namespace requires a value\n");
            return error.MissingArgument;
        }
        namespace = args[1];
    }

    // Initialize K7Core
    const kubeconfig = std.os.getenv("KUBECONFIG");
    var k7_core = core.K7Core.init(allocator, kubeconfig) catch |err| {
        try stderr.print("Error initializing K7Core: {s}\n", .{@errorName(err)});
        return error.InitFailed;
    };
    defer k7_core.deinit();

    // List sandboxes
    const sandboxes = k7_core.listSandboxes(namespace) catch |err| {
        try stderr.print("Error listing sandboxes: {s}\n", .{@errorName(err)});
        return error.ListFailed;
    };
    defer allocator.free(sandboxes);

    if (sandboxes.len == 0) {
        try stdout.writeAll("No sandboxes found.\n");
        return;
    }

    // Print table header
    try stdout.writeAll("NAME                    NAMESPACE    STATUS      AGE\n");
    try stdout.writeAll("----                    ---------    ------      ---\n");

    // Print each sandbox
    for (sandboxes) |sandbox| {
        try stdout.print("{s:<23} {s:<12} {s:<11} {s}\n", .{
            sandbox.name,
            sandbox.namespace,
            sandbox.status,
            sandbox.age,
        });
    }
}

fn cmdDelete(allocator: std.mem.Allocator, args: [][]const u8, stdout: anytype, stderr: anytype) !void {
    if (args.len < 1) {
        try stderr.writeAll("Error: sandbox name is required\n");
        return error.MissingArgument;
    }

    const name = args[0];
    var namespace: []const u8 = "default";

    // Check for --namespace flag
    if (args.len > 2 and std.mem.eql(u8, args[1], "--namespace")) {
        namespace = args[2];
    }

    // Initialize K7Core
    const kubeconfig = std.os.getenv("KUBECONFIG");
    var k7_core = core.K7Core.init(allocator, kubeconfig) catch |err| {
        try stderr.print("Error initializing K7Core: {s}\n", .{@errorName(err)});
        return error.InitFailed;
    };
    defer k7_core.deinit();

    try stdout.print("Deleting sandbox '{s}' in namespace '{s}'...\n", .{ name, namespace });

    // Delete sandbox
    const result = k7_core.deleteSandbox(name, namespace) catch |err| {
        try stderr.print("Error deleting sandbox: {s}\n", .{@errorName(err)});
        return error.DeleteFailed;
    };
    defer result.deinit(allocator);

    if (result.success) {
        try stdout.print("✓ Sandbox deleted successfully\n", .{});
    } else {
        try stderr.print("✗ Failed to delete sandbox: {s}\n", .{result.err});
        return error.DeleteFailed;
    }
}

fn cmdDeleteAll(allocator: std.mem.Allocator, args: [][]const u8, stdout: anytype, stderr: anytype) !void {
    var namespace: []const u8 = "default";

    // Check for --namespace flag
    if (args.len > 1 and std.mem.eql(u8, args[0], "--namespace")) {
        namespace = args[1];
    }

    // Initialize K7Core
    const kubeconfig = std.os.getenv("KUBECONFIG");
    var k7_core = core.K7Core.init(allocator, kubeconfig) catch |err| {
        try stderr.print("Error initializing K7Core: {s}\n", .{@errorName(err)});
        return error.InitFailed;
    };
    defer k7_core.deinit();

    try stdout.print("Deleting all sandboxes in namespace '{s}'...\n", .{namespace});

    // Delete all sandboxes
    const result = k7_core.deleteAllSandboxes(namespace) catch |err| {
        try stderr.print("Error deleting sandboxes: {s}\n", .{@errorName(err)});
        return error.DeleteFailed;
    };
    defer result.deinit(allocator);

    if (result.success) {
        try stdout.print("✓ All sandboxes deleted successfully\n", .{});
    } else {
        try stderr.print("✗ Failed to delete sandboxes: {s}\n", .{result.err});
        return error.DeleteFailed;
    }
}

fn cmdShell(allocator: std.mem.Allocator, args: [][]const u8, stdout: anytype, stderr: anytype) !void {
    if (args.len < 1) {
        try stderr.writeAll("Error: sandbox name is required\n");
        return error.MissingArgument;
    }

    const name = args[0];
    var namespace: []const u8 = "default";

    if (args.len > 2 and std.mem.eql(u8, args[1], "--namespace")) {
        namespace = args[2];
    }

    // Initialize K7Core
    const kubeconfig = std.os.getenv("KUBECONFIG");
    var k7_core = core.K7Core.init(allocator, kubeconfig) catch |err| {
        try stderr.print("Error initializing K7Core: {s}\n", .{@errorName(err)});
        return error.InitFailed;
    };
    defer k7_core.deinit();

    try stdout.print("Opening shell in sandbox '{s}'...\n", .{name});

    // Execute /bin/sh
    const result = k7_core.execCommand(name, "/bin/sh", namespace) catch |err| {
        try stderr.print("Error opening shell: {s}\n", .{@errorName(err)});
        return error.ShellFailed;
    };
    defer result.deinit(allocator);

    // Print stdout and stderr
    if (result.stdout.len > 0) {
        try stdout.print("{s}", .{result.stdout});
    }
    if (result.stderr.len > 0) {
        try stderr.print("{s}", .{result.stderr});
    }

    if (result.exit_code != 0) {
        try stderr.print("Shell exited with code: {d}\n", .{result.exit_code});
    }
}

fn cmdLogs(allocator: std.mem.Allocator, args: [][]const u8, stdout: anytype, stderr: anytype) !void {
    if (args.len < 1) {
        try stderr.writeAll("Error: sandbox name is required\n");
        return error.MissingArgument;
    }

    const name = args[0];
    var namespace: []const u8 = "default";

    if (args.len > 2 and std.mem.eql(u8, args[1], "--namespace")) {
        namespace = args[2];
    }

    // Initialize K7Core
    const kubeconfig = std.os.getenv("KUBECONFIG");
    var k7_core = core.K7Core.init(allocator, kubeconfig) catch |err| {
        try stderr.print("Error initializing K7Core: {s}\n", .{@errorName(err)});
        return error.InitFailed;
    };
    defer k7_core.deinit();

    // Get logs via exec command
    const result = k7_core.execCommand(name, "cat /proc/1/fd/1", namespace) catch |err| {
        try stderr.print("Error getting logs: {s}\n", .{@errorName(err)});
        return error.LogsFailed;
    };
    defer result.deinit(allocator);

    // Print logs
    if (result.stdout.len > 0) {
        try stdout.print("{s}", .{result.stdout});
    }
}

fn cmdTop(allocator: std.mem.Allocator, args: [][]const u8, stdout: anytype, stderr: anytype) !void {
    var namespace: ?[]const u8 = null;

    if (args.len > 1 and std.mem.eql(u8, args[0], "--namespace")) {
        namespace = args[1];
    }

    // Initialize K7Core
    const kubeconfig = std.os.getenv("KUBECONFIG");
    var k7_core = core.K7Core.init(allocator, kubeconfig) catch |err| {
        try stderr.print("Error initializing K7Core: {s}\n", .{@errorName(err)});
        return error.InitFailed;
    };
    defer k7_core.deinit();

    // Get metrics
    const metrics = k7_core.getSandboxMetrics(namespace) catch |err| {
        try stderr.print("Error getting metrics: {s}\n", .{@errorName(err)});
        return error.TopFailed;
    };
    defer allocator.free(metrics);

    if (metrics.len == 0) {
        try stdout.writeAll("No sandboxes found.\n");
        return;
    }

    // Print table header
    try stdout.writeAll("NAME                    NAMESPACE    CPU         MEMORY\n");
    try stdout.writeAll("----                    ---------    ---         ------\n");

    // Print each metric
    for (metrics) |metric| {
        try stdout.print("{s:<23} {s:<12} {s:<11} {s}\n", .{
            metric.name,
            metric.namespace,
            metric.cpu_usage,
            metric.memory_usage,
        });
    }
}

fn cmdGenerateApiKey(allocator: std.mem.Allocator, args: [][]const u8, stdout: anytype, stderr: anytype) !void {
    if (args.len < 1) {
        try stderr.writeAll("Error: key name is required\n");
        return error.MissingArgument;
    }

    const key_name = args[0];

    // Generate random API key (32 bytes = 64 hex chars)
    var random_bytes: [32]u8 = undefined;
    std.crypto.random.bytes(&random_bytes);

    // Convert to hex string
    var api_key_buf: [64]u8 = undefined;
    const api_key = std.fmt.bufPrint(&api_key_buf, "{}", .{std.fmt.fmtSliceHexLower(&random_bytes)}) catch unreachable;

    // Compute SHA256 hash for storage
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(api_key);
    var digest: [32]u8 = undefined;
    hasher.final(&digest);

    var hash_buf: [64]u8 = undefined;
    const hash_hex = std.fmt.bufPrint(&hash_buf, "{}", .{std.fmt.fmtSliceHexLower(&digest)}) catch unreachable;

    try stdout.print("Generated API key for '{s}':\n\n", .{key_name});
    try stdout.print("API Key: {s}\n", .{api_key});
    try stdout.print("SHA256:  {s}\n\n", .{hash_hex});
    try stdout.writeAll("⚠️  Save this API key securely - it cannot be recovered!\n");
    try stdout.writeAll("💾 Store the SHA256 hash in your API key database.\n");

    // TODO: Optionally save to config file
    _ = allocator;
}

fn cmdListApiKeys(allocator: std.mem.Allocator, args: [][]const u8, stdout: anytype, stderr: anytype) !void {
    _ = allocator;
    _ = args;
    _ = stderr;
    try stdout.writeAll("TODO: Implement list-api-keys command (read from JSON file)\n");
}

fn cmdRevokeApiKey(allocator: std.mem.Allocator, args: [][]const u8, stdout: anytype, stderr: anytype) !void {
    _ = allocator;
    _ = args;
    _ = stderr;
    try stdout.writeAll("TODO: Implement revoke-api-key command\n");
}

fn cmdStartApi(allocator: std.mem.Allocator, args: [][]const u8, stdout: anytype, stderr: anytype) !void {
    _ = allocator;
    _ = args;
    _ = stderr;
    try stdout.writeAll("TODO: Implement start-api command (docker-compose wrapper)\n");
}

fn cmdStopApi(allocator: std.mem.Allocator, args: [][]const u8, stdout: anytype, stderr: anytype) !void {
    _ = allocator;
    _ = args;
    _ = stderr;
    try stdout.writeAll("TODO: Implement stop-api command (docker-compose down)\n");
}

fn cmdApiStatus(allocator: std.mem.Allocator, args: [][]const u8, stdout: anytype, stderr: anytype) !void {
    _ = allocator;
    _ = args;
    _ = stderr;
    try stdout.writeAll("TODO: Implement api-status command (check docker containers)\n");
}

fn cmdGetApiEndpoint(allocator: std.mem.Allocator, args: [][]const u8, stdout: anytype, stderr: anytype) !void {
    _ = allocator;
    _ = args;
    _ = stderr;
    try stdout.writeAll("TODO: Implement get-api-endpoint command (parse cloudflared logs)\n");
}
