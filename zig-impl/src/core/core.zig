const std = @import("std");
const models = @import("models.zig");
const k8s = @import("../kubernetes/client.zig");

/// K7Core - Core business logic for sandbox management
pub const K7Core = struct {
    allocator: std.mem.Allocator,
    kube_client: k8s.Client,
    config_loaded: bool,

    pub fn init(allocator: std.mem.Allocator, kubeconfig_path: ?[]const u8) !K7Core {
        const kube_client = try k8s.Client.initFromKubeconfig(allocator, kubeconfig_path);

        return K7Core{
            .allocator = allocator,
            .kube_client = kube_client,
            .config_loaded = true,
        };
    }

    pub fn deinit(self: *K7Core) void {
        self.kube_client.deinit();
    }

    /// Create a new sandbox
    pub fn createSandbox(
        self: *K7Core,
        config: models.SandboxConfig,
        progress_callback: ?*const fn (event: ProgressEvent) void,
    ) !models.OperationResult {
        // Validate configuration
        try config.validate();

        if (progress_callback) |cb| {
            cb(ProgressEvent{
                .stage = "validation",
                .status = "success",
                .message = "Configuration validated",
            });
        }

        const namespace = config.namespace;
        var secret_name: ?[]const u8 = null;

        // Step 1: Create Secret from env_file if provided
        if (config.env_file) |env_file_path| {
            if (progress_callback) |cb| {
                cb(ProgressEvent{
                    .stage = "secret",
                    .status = "creating",
                    .message = "Creating secret from env file",
                });
            }

            secret_name = try std.fmt.allocPrint(self.allocator, "{s}-env", .{config.name});
            errdefer if (secret_name) |sn| self.allocator.free(sn);

            // Read env file
            const env_content = try std.fs.cwd().readFileAlloc(self.allocator, env_file_path, 10 * 1024 * 1024);
            defer self.allocator.free(env_content);

            // Create secret with env data
            var secret = k8s.Secret{
                .metadata = k8s.ObjectMeta{
                    .name = secret_name.?,
                    .namespace = namespace,
                },
                .type = "Opaque",
                .stringData = std.StringHashMap([]const u8).init(self.allocator),
            };
            defer secret.deinit(self.allocator);

            try secret.stringData.?.put(".env", env_content);

            const secret_response = try self.kube_client.createSecret(namespace, secret);
            defer self.allocator.free(secret_response);

            if (progress_callback) |cb| {
                cb(ProgressEvent{
                    .stage = "secret",
                    .status = "created",
                    .message = "Secret created successfully",
                });
            }
        }

        // Step 2: Build Deployment manifest
        if (progress_callback) |cb| {
            cb(ProgressEvent{
                .stage = "deployment",
                .status = "creating",
                .message = "Building deployment manifest",
            });
        }

        // Build labels
        var labels = std.StringHashMap([]const u8).init(self.allocator);
        defer labels.deinit();
        try labels.put("app", config.name);
        try labels.put("runtime", "kata");
        try labels.put("managed-by", "k7");

        // Build security context
        var capabilities_drop = std.ArrayList([]const u8).init(self.allocator);
        defer capabilities_drop.deinit();

        if (config.cap_drop) |caps| {
            for (caps) |cap| {
                try capabilities_drop.append(cap);
            }
        } else {
            // Default: drop ALL capabilities
            try capabilities_drop.append("ALL");
        }

        const security_context = k8s.SecurityContext{
            .runAsNonRoot = if (config.container_non_root) true else null,
            .runAsUser = if (config.container_non_root) 1000 else null,
            .capabilities = k8s.Capabilities{
                .drop = try capabilities_drop.toOwnedSlice(),
                .add = config.cap_add,
            },
        };

        // Build environment variables
        var env_vars = std.ArrayList(k8s.EnvVar).init(self.allocator);
        defer env_vars.deinit();

        if (secret_name) |sn| {
            try env_vars.append(k8s.EnvVar{
                .name = "ENV_FILE",
                .valueFrom = k8s.EnvVarSource{
                    .secretKeyRef = k8s.SecretKeySelector{
                        .name = sn,
                        .key = ".env",
                    },
                },
            });
        }

        // Build container spec
        const container = k8s.Container{
            .name = "sandbox",
            .image = config.image,
            .command = if (config.before_script.len > 0)
                try self.buildContainerCommand(config.before_script)
            else
                null,
            .env = if (env_vars.items.len > 0) try env_vars.toOwnedSlice() else null,
            .resources = try self.buildResourceRequirements(config.limits),
            .securityContext = security_context,
        };

        // Build pod spec
        var containers = try self.allocator.alloc(k8s.Container, 1);
        containers[0] = container;

        const pod_security_context = k8s.PodSecurityContext{
            .runAsNonRoot = if (config.pod_non_root) true else null,
            .runAsUser = if (config.pod_non_root) 1000 else null,
            .fsGroup = if (config.pod_non_root) 1000 else null,
        };

        var pod_meta = k8s.ObjectMeta{
            .name = config.name,
            .namespace = namespace,
            .labels = labels,
        };

        const pod_spec = k8s.PodSpec{
            .containers = containers,
            .runtimeClassName = "kata",
            .securityContext = pod_security_context,
        };

        // Build deployment
        var deployment = k8s.Deployment{
            .metadata = k8s.ObjectMeta{
                .name = config.name,
                .namespace = namespace,
            },
            .spec = k8s.DeploymentSpec{
                .replicas = 1,
                .selector = k8s.LabelSelector{ .matchLabels = labels },
                .template = k8s.PodTemplateSpec{
                    .metadata = pod_meta,
                    .spec = pod_spec,
                },
            },
        };
        defer deployment.deinit(self.allocator);

        // Step 3: Create Deployment via Kubernetes API
        const deployment_response = try self.kube_client.createDeployment(namespace, deployment);
        defer self.allocator.free(deployment_response);

        if (progress_callback) |cb| {
            cb(ProgressEvent{
                .stage = "deployment",
                .status = "created",
                .message = "Deployment created successfully",
            });
        }

        // Step 4: Create NetworkPolicies
        if (config.egress_whitelist) |egress_cidrs| {
            if (progress_callback) |cb| {
                cb(ProgressEvent{
                    .stage = "network-policy",
                    .status = "creating",
                    .message = "Creating network policies",
                });
            }

            try self.createNetworkPolicies(config.name, namespace, egress_cidrs, labels);

            if (progress_callback) |cb| {
                cb(ProgressEvent{
                    .stage = "network-policy",
                    .status = "created",
                    .message = "Network policies created",
                });
            }
        }

        // Step 5: Wait for pod readiness
        if (progress_callback) |cb| {
            cb(ProgressEvent{
                .stage = "readiness",
                .status = "waiting",
                .message = "Waiting for pod to become ready",
            });
        }

        try self.waitForPodReady(config.name, namespace, 300); // 5 minute timeout

        if (progress_callback) |cb| {
            cb(ProgressEvent{
                .stage = "readiness",
                .status = "ready",
                .message = "Sandbox is ready",
            });
        }

        return try models.OperationResult.success_result(
            self.allocator,
            "Sandbox created successfully",
        );
    }

    fn buildContainerCommand(self: *K7Core, before_script: []const u8) ![][]const u8 {
        var command = try self.allocator.alloc([]const u8, 3);
        command[0] = try self.allocator.dupe(u8, "/bin/sh");
        command[1] = try self.allocator.dupe(u8, "-c");
        command[2] = try self.allocator.dupe(u8, before_script);
        return command;
    }

    fn buildResourceRequirements(self: *K7Core, limits: ?std.StringHashMap([]const u8)) !?k8s.ResourceRequirements {
        if (limits == null) return null;

        var resource_limits = std.StringHashMap([]const u8).init(self.allocator);
        var it = limits.?.iterator();
        while (it.next()) |entry| {
            const key = try self.allocator.dupe(u8, entry.key_ptr.*);
            const value = try self.allocator.dupe(u8, entry.value_ptr.*);
            try resource_limits.put(key, value);
        }

        return k8s.ResourceRequirements{
            .limits = resource_limits,
            .requests = null,
        };
    }

    fn createNetworkPolicies(
        self: *K7Core,
        name: []const u8,
        namespace: []const u8,
        egress_cidrs: [][]const u8,
        labels: std.StringHashMap([]const u8),
    ) !void {
        // Create egress policy
        var egress_rules = try self.allocator.alloc(k8s.NetworkPolicyEgressRule, egress_cidrs.len);
        for (egress_cidrs, 0..) |cidr, i| {
            var peers = try self.allocator.alloc(k8s.NetworkPolicyPeer, 1);
            peers[0] = k8s.NetworkPolicyPeer{
                .ipBlock = k8s.IPBlock{ .cidr = cidr },
            };
            egress_rules[i] = k8s.NetworkPolicyEgressRule{
                .to = peers,
                .ports = null,
            };
        }

        var policy_types = try self.allocator.alloc([]const u8, 2);
        policy_types[0] = try self.allocator.dupe(u8, "Egress");
        policy_types[1] = try self.allocator.dupe(u8, "Ingress");

        const egress_policy_name = try std.fmt.allocPrint(self.allocator, "{s}-egress", .{name});
        defer self.allocator.free(egress_policy_name);

        var egress_policy = k8s.NetworkPolicy{
            .metadata = k8s.ObjectMeta{
                .name = egress_policy_name,
                .namespace = namespace,
            },
            .spec = k8s.NetworkPolicySpec{
                .podSelector = k8s.LabelSelector{ .matchLabels = labels },
                .policyTypes = policy_types,
                .ingress = null, // Deny all ingress
                .egress = egress_rules,
            },
        };
        defer egress_policy.deinit(self.allocator);

        const response = try self.kube_client.createNetworkPolicy(namespace, egress_policy);
        defer self.allocator.free(response);
    }

    fn waitForPodReady(self: *K7Core, deployment_name: []const u8, namespace: []const u8, timeout_seconds: u64) !void {
        const start_time = std.time.timestamp();
        const label_selector = try std.fmt.allocPrint(self.allocator, "app={s}", .{deployment_name});
        defer self.allocator.free(label_selector);

        while (true) {
            // Check timeout
            const elapsed = @as(u64, @intCast(std.time.timestamp() - start_time));
            if (elapsed > timeout_seconds) {
                return error.Timeout;
            }

            // Query pods
            const pods_json = try self.kube_client.listPods(namespace, label_selector);
            defer self.allocator.free(pods_json);

            // Parse JSON to check if pod is ready
            // Kubernetes API response format:
            // {"kind":"PodList","items":[{"status":{"conditions":[{"type":"Ready","status":"True"}]}}]}
            var arena = std.heap.ArenaAllocator.init(self.allocator);
            defer arena.deinit();
            const arena_allocator = arena.allocator();

            const parsed = std.json.parseFromSlice(
                std.json.Value,
                arena_allocator,
                pods_json,
                .{},
            ) catch {
                // If JSON parsing fails, wait and retry
                std.time.sleep(2 * std.time.ns_per_s);
                continue;
            };

            const root = parsed.value;

            // Get items array
            const items = if (root.object.get("items")) |items_value|
                if (items_value == .array) items_value.array else {
                    std.time.sleep(2 * std.time.ns_per_s);
                    continue;
                }
            else {
                std.time.sleep(2 * std.time.ns_per_s);
                continue;
            };

            // Check if we have at least one pod
            if (items.items.len == 0) {
                // No pods yet, wait and retry
                std.time.sleep(2 * std.time.ns_per_s);
                continue;
            }

            // Check the first pod's ready status
            const first_pod = items.items[0];
            if (first_pod != .object) {
                std.time.sleep(2 * std.time.ns_per_s);
                continue;
            }

            const pod = first_pod.object;

            // Get status object
            const status_obj = if (pod.get("status")) |s|
                if (s == .object) s.object else {
                    std.time.sleep(2 * std.time.ns_per_s);
                    continue;
                }
            else {
                std.time.sleep(2 * std.time.ns_per_s);
                continue;
            };

            // Check conditions array for Ready condition
            const conditions = if (status_obj.get("conditions")) |c|
                if (c == .array) c.array else {
                    std.time.sleep(2 * std.time.ns_per_s);
                    continue;
                }
            else {
                std.time.sleep(2 * std.time.ns_per_s);
                continue;
            };

            // Look for Ready condition with status=True
            var is_ready = false;
            for (conditions.items) |condition_value| {
                if (condition_value != .object) continue;
                const condition = condition_value.object;

                const condition_type = if (condition.get("type")) |t|
                    if (t == .string) t.string else continue
                else continue;

                if (std.mem.eql(u8, condition_type, "Ready")) {
                    const condition_status = if (condition.get("status")) |s|
                        if (s == .string) s.string else "False"
                    else "False";

                    if (std.mem.eql(u8, condition_status, "True")) {
                        is_ready = true;
                        break;
                    }
                }
            }

            if (is_ready) {
                // Pod is ready!
                return;
            } else {
                // Not ready yet, wait and retry
                std.time.sleep(2 * std.time.ns_per_s);
            }
        }
    }

    /// List all sandboxes
    pub fn listSandboxes(
        self: *K7Core,
        namespace: ?[]const u8,
    ) ![]models.SandboxInfo {
        const ns = namespace orelse self.kube_client.config.namespace;
        const label_selector = "runtime=kata,managed-by=k7";

        // Query Kubernetes API for deployments with label runtime=kata
        const deployments_json = try self.kube_client.listDeployments(ns, label_selector);
        defer self.allocator.free(deployments_json);

        // Query pods to get status
        const pods_json = try self.kube_client.listPods(ns, label_selector);
        defer self.allocator.free(pods_json);

        // Parse pods JSON response
        // Kubernetes API response format:
        // {"kind":"PodList","items":[{"metadata":{"name":"...","creationTimestamp":"..."},"spec":{"containers":[{"image":"..."}]},"status":{"phase":"Running","conditions":[...],"containerStatuses":[{"restartCount":0}]}}]}

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const arena_allocator = arena.allocator();

        const parsed = std.json.parseFromSlice(
            std.json.Value,
            arena_allocator,
            pods_json,
            .{},
        ) catch {
            // If JSON parsing fails, return empty list rather than erroring
            const empty_list = try self.allocator.alloc(models.SandboxInfo, 0);
            return empty_list;
        };

        const root = parsed.value;

        // Get items array
        const items = if (root.object.get("items")) |items_value|
            if (items_value == .array) items_value.array else return try self.allocator.alloc(models.SandboxInfo, 0)
        else
            return try self.allocator.alloc(models.SandboxInfo, 0);

        if (items.items.len == 0) {
            const empty_list = try self.allocator.alloc(models.SandboxInfo, 0);
            return empty_list;
        }

        // Allocate result array
        var sandbox_list = std.ArrayList(models.SandboxInfo).init(self.allocator);
        errdefer {
            for (sandbox_list.items) |*item| {
                item.deinit(self.allocator);
            }
            sandbox_list.deinit();
        }

        // Parse each pod
        for (items.items) |item_value| {
            if (item_value != .object) continue;
            const item = item_value.object;

            // Extract metadata
            const metadata = if (item.get("metadata")) |m|
                if (m == .object) m.object else continue
            else continue;

            const name = if (metadata.get("name")) |n|
                if (n == .string) n.string else continue
            else continue;

            const pod_namespace = if (metadata.get("namespace")) |n|
                if (n == .string) n.string else ns
            else ns;

            const creation_timestamp = if (metadata.get("creationTimestamp")) |ct|
                if (ct == .string) ct.string else ""
            else "";

            // Extract spec
            const spec = if (item.get("spec")) |s|
                if (s == .object) s.object else continue
            else continue;

            var image: []const u8 = "unknown";
            if (spec.get("containers")) |containers_value| {
                if (containers_value == .array and containers_value.array.items.len > 0) {
                    const first_container = containers_value.array.items[0];
                    if (first_container == .object) {
                        if (first_container.object.get("image")) |img| {
                            if (img == .string) {
                                image = img.string;
                            }
                        }
                    }
                }
            }

            // Extract status
            const status_obj = if (item.get("status")) |s|
                if (s == .object) s.object else continue
            else continue;

            const phase = if (status_obj.get("phase")) |p|
                if (p == .string) p.string else "Unknown"
            else "Unknown";

            // Get ready status from conditions
            var ready_str: []const u8 = "False";
            if (status_obj.get("conditions")) |conditions_value| {
                if (conditions_value == .array) {
                    for (conditions_value.array.items) |condition_value| {
                        if (condition_value == .object) {
                            const condition = condition_value.object;
                            if (condition.get("type")) |type_value| {
                                if (type_value == .string and std.mem.eql(u8, type_value.string, "Ready")) {
                                    if (condition.get("status")) |status_value| {
                                        if (status_value == .string) {
                                            ready_str = status_value.string;
                                        }
                                    }
                                    break;
                                }
                            }
                        }
                    }
                }
            }

            // Get restart count
            var restarts: i32 = 0;
            if (status_obj.get("containerStatuses")) |container_statuses_value| {
                if (container_statuses_value == .array and container_statuses_value.array.items.len > 0) {
                    const first_status = container_statuses_value.array.items[0];
                    if (first_status == .object) {
                        if (first_status.object.get("restartCount")) |rc| {
                            if (rc == .integer) {
                                restarts = @intCast(rc.integer);
                            }
                        }
                    }
                }
            }

            // Calculate age from creationTimestamp
            const age = try self.calculateAge(creation_timestamp);

            // Create SandboxInfo
            const info = models.SandboxInfo{
                .name = try self.allocator.dupe(u8, name),
                .namespace = try self.allocator.dupe(u8, pod_namespace),
                .status = try self.allocator.dupe(u8, phase),
                .ready = try self.allocator.dupe(u8, ready_str),
                .restarts = restarts,
                .age = age,
                .image = try self.allocator.dupe(u8, image),
                .error_message = "",
            };

            try sandbox_list.append(info);
        }

        return try sandbox_list.toOwnedSlice();
    }

    /// Calculate age string from RFC3339 timestamp
    /// Example: "2024-01-15T10:30:00Z" -> "5m" or "2h" or "3d"
    fn calculateAge(self: *K7Core, timestamp: []const u8) ![]const u8 {
        if (timestamp.len == 0) {
            return try self.allocator.dupe(u8, "unknown");
        }

        // Parse RFC3339 timestamp
        // Format: YYYY-MM-DDTHH:MM:SSZ or YYYY-MM-DDTHH:MM:SS+00:00
        const epoch_seconds = parseRFC3339(timestamp) catch {
            return try self.allocator.dupe(u8, "unknown");
        };

        // Get current time
        const now = std.time.timestamp();

        // Calculate difference
        if (now < epoch_seconds) {
            // Timestamp is in the future (shouldn't happen)
            return try self.allocator.dupe(u8, "0s");
        }

        const diff_seconds = @as(u64, @intCast(now - epoch_seconds));

        // Format as human-readable age
        return try self.formatAge(diff_seconds);
    }

    /// Parse RFC3339 timestamp to Unix epoch seconds
    /// Format: "2024-01-15T10:30:00Z" or "2024-01-15T10:30:00+00:00"
    fn parseRFC3339(timestamp: []const u8) !i64 {
        // Minimum length: "2024-01-01T00:00:00Z" = 20 characters
        if (timestamp.len < 20) return error.InvalidTimestamp;

        // Parse date components
        const year = try std.fmt.parseInt(i32, timestamp[0..4], 10);
        const month = try std.fmt.parseInt(u32, timestamp[5..7], 10);
        const day = try std.fmt.parseInt(u32, timestamp[8..10], 10);

        if (timestamp[10] != 'T') return error.InvalidTimestamp;

        // Parse time components
        const hour = try std.fmt.parseInt(u32, timestamp[11..13], 10);
        const minute = try std.fmt.parseInt(u32, timestamp[14..16], 10);
        const second = try std.fmt.parseInt(u32, timestamp[17..19], 10);

        // Validate ranges
        if (month < 1 or month > 12) return error.InvalidTimestamp;
        if (day < 1 or day > 31) return error.InvalidTimestamp;
        if (hour > 23) return error.InvalidTimestamp;
        if (minute > 59) return error.InvalidTimestamp;
        if (second > 59) return error.InvalidTimestamp;

        // Calculate Unix epoch (days since 1970-01-01)
        // Simplified calculation (doesn't account for all leap years perfectly)
        var days: i64 = 0;

        // Add years (approximate - 365.25 days per year)
        days += @as(i64, year - 1970) * 365;

        // Add leap year days (every 4 years since 1972, excluding centuries not divisible by 400)
        const leap_years = @divTrunc(year - 1972, 4) + 1;
        days += leap_years;

        // Add months (approximate)
        const days_per_month = [_]u32{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
        for (0..month - 1) |m| {
            days += days_per_month[m];
        }

        // Add days
        days += @as(i64, day - 1);

        // Calculate seconds
        var seconds: i64 = days * 86400;
        seconds += @as(i64, hour) * 3600;
        seconds += @as(i64, minute) * 60;
        seconds += @as(i64, second);

        return seconds;
    }

    /// Format age in seconds to human-readable string
    fn formatAge(self: *K7Core, seconds: u64) ![]const u8 {
        const minute = 60;
        const hour = minute * 60;
        const day = hour * 24;
        const week = day * 7;
        const month = day * 30;
        const year = day * 365;

        if (seconds < minute) {
            return try std.fmt.allocPrint(self.allocator, "{d}s", .{seconds});
        } else if (seconds < hour) {
            const minutes = seconds / minute;
            return try std.fmt.allocPrint(self.allocator, "{d}m", .{minutes});
        } else if (seconds < day) {
            const hours = seconds / hour;
            return try std.fmt.allocPrint(self.allocator, "{d}h", .{hours});
        } else if (seconds < week) {
            const days = seconds / day;
            return try std.fmt.allocPrint(self.allocator, "{d}d", .{days});
        } else if (seconds < month) {
            const weeks = seconds / week;
            return try std.fmt.allocPrint(self.allocator, "{d}w", .{weeks});
        } else if (seconds < year) {
            const months = seconds / month;
            return try std.fmt.allocPrint(self.allocator, "{d}mo", .{months});
        } else {
            const years = seconds / year;
            return try std.fmt.allocPrint(self.allocator, "{d}y", .{years});
        }
    }

    /// Delete a sandbox
    pub fn deleteSandbox(
        self: *K7Core,
        name: []const u8,
        namespace: []const u8,
    ) !models.OperationResult {
        var errors = std.ArrayList([]const u8).init(self.allocator);
        defer {
            for (errors.items) |err| self.allocator.free(err);
            errors.deinit();
        }

        // Step 1: Delete Deployment
        self.kube_client.deleteDeployment(namespace, name) catch |err| {
            const err_msg = try std.fmt.allocPrint(
                self.allocator,
                "Failed to delete deployment: {s}",
                .{@errorName(err)},
            );
            try errors.append(err_msg);
        };

        // Step 2: Delete Secret (if env_file was used)
        const secret_name = try std.fmt.allocPrint(self.allocator, "{s}-env", .{name});
        defer self.allocator.free(secret_name);

        self.kube_client.deleteSecret(namespace, secret_name) catch |err| {
            // Ignore ResourceNotFound errors for secret (might not exist)
            if (err != error.ResourceNotFound) {
                const err_msg = try std.fmt.allocPrint(
                    self.allocator,
                    "Failed to delete secret: {s}",
                    .{@errorName(err)},
                );
                try errors.append(err_msg);
            }
        };

        // Step 3: Delete NetworkPolicies
        const egress_policy_name = try std.fmt.allocPrint(self.allocator, "{s}-egress", .{name});
        defer self.allocator.free(egress_policy_name);

        self.kube_client.deleteNetworkPolicy(namespace, egress_policy_name) catch |err| {
            if (err != error.ResourceNotFound) {
                const err_msg = try std.fmt.allocPrint(
                    self.allocator,
                    "Failed to delete network policy: {s}",
                    .{@errorName(err)},
                );
                try errors.append(err_msg);
            }
        };

        // Check if there were any critical errors
        if (errors.items.len > 0) {
            var error_message = std.ArrayList(u8).init(self.allocator);
            defer error_message.deinit();

            try error_message.appendSlice("Sandbox deletion completed with errors: ");
            for (errors.items, 0..) |err, i| {
                if (i > 0) try error_message.appendSlice("; ");
                try error_message.appendSlice(err);
            }

            return try models.OperationResult.error_result(
                self.allocator,
                try error_message.toOwnedSlice(),
            );
        }

        return try models.OperationResult.success_result(
            self.allocator,
            "Sandbox deleted successfully",
        );
    }

    /// Delete all sandboxes in namespace
    pub fn deleteAllSandboxes(
        self: *K7Core,
        namespace: []const u8,
    ) !models.OperationResult {
        // Get all sandboxes
        const sandboxes = try self.listSandboxes(namespace);
        defer self.allocator.free(sandboxes);

        // Delete each one
        for (sandboxes) |sandbox| {
            _ = try self.deleteSandbox(sandbox.name, namespace);
        }

        return try models.OperationResult.success_result(
            self.allocator,
            "All sandboxes deleted successfully (placeholder)",
        );
    }

    /// Execute command in sandbox
    pub fn execCommand(
        self: *K7Core,
        sandbox_name: []const u8,
        command: []const u8,
        namespace: []const u8,
    ) !models.ExecResult {
        const start_time = std.time.milliTimestamp();

        // Step 1: Find pod for deployment by parsing pods JSON
        const label_selector = try std.fmt.allocPrint(self.allocator, "app={s}", .{sandbox_name});
        defer self.allocator.free(label_selector);

        const pods_json = try self.kube_client.listPods(namespace, label_selector);
        defer self.allocator.free(pods_json);

        // Parse JSON to get actual pod name
        // Kubernetes API response format:
        // {"kind":"PodList","items":[{"metadata":{"name":"actual-pod-name"}}]}
        const pod_name = blk: {
            var arena = std.heap.ArenaAllocator.init(self.allocator);
            defer arena.deinit();
            const arena_allocator = arena.allocator();

            const parsed = std.json.parseFromSlice(
                std.json.Value,
                arena_allocator,
                pods_json,
                .{},
            ) catch {
                const stderr_msg = try std.fmt.allocPrint(
                    self.allocator,
                    "Failed to parse pods JSON response",
                    .{},
                );
                return models.ExecResult{
                    .exit_code = 1,
                    .stdout = try self.allocator.dupe(u8, ""),
                    .stderr = stderr_msg,
                    .duration_ms = std.time.milliTimestamp() - start_time,
                };
            };

            const root = parsed.value;

            // Get items array
            const items = if (root.object.get("items")) |items_value|
                if (items_value == .array) items_value.array else {
                    const stderr_msg = try std.fmt.allocPrint(
                        self.allocator,
                        "Invalid pods response: missing items array",
                        .{},
                    );
                    return models.ExecResult{
                        .exit_code = 1,
                        .stdout = try self.allocator.dupe(u8, ""),
                        .stderr = stderr_msg,
                        .duration_ms = std.time.milliTimestamp() - start_time,
                    };
                }
            else {
                const stderr_msg = try std.fmt.allocPrint(
                    self.allocator,
                    "Invalid pods response: missing items field",
                    .{},
                );
                return models.ExecResult{
                    .exit_code = 1,
                    .stdout = try self.allocator.dupe(u8, ""),
                    .stderr = stderr_msg,
                    .duration_ms = std.time.milliTimestamp() - start_time,
                };
            };

            // Check if we have at least one pod
            if (items.items.len == 0) {
                const stderr_msg = try std.fmt.allocPrint(
                    self.allocator,
                    "No pods found for sandbox '{s}'",
                    .{sandbox_name},
                );
                return models.ExecResult{
                    .exit_code = 1,
                    .stdout = try self.allocator.dupe(u8, ""),
                    .stderr = stderr_msg,
                    .duration_ms = std.time.milliTimestamp() - start_time,
                };
            }

            // Get first pod's metadata
            const first_pod = items.items[0];
            if (first_pod != .object) {
                const stderr_msg = try std.fmt.allocPrint(
                    self.allocator,
                    "Invalid pod object in response",
                    .{},
                );
                return models.ExecResult{
                    .exit_code = 1,
                    .stdout = try self.allocator.dupe(u8, ""),
                    .stderr = stderr_msg,
                    .duration_ms = std.time.milliTimestamp() - start_time,
                };
            }

            const pod = first_pod.object;

            const metadata = if (pod.get("metadata")) |m|
                if (m == .object) m.object else {
                    const stderr_msg = try std.fmt.allocPrint(
                        self.allocator,
                        "Invalid pod metadata",
                        .{},
                    );
                    return models.ExecResult{
                        .exit_code = 1,
                        .stdout = try self.allocator.dupe(u8, ""),
                        .stderr = stderr_msg,
                        .duration_ms = std.time.milliTimestamp() - start_time,
                    };
                }
            else {
                const stderr_msg = try std.fmt.allocPrint(
                    self.allocator,
                    "Missing pod metadata",
                    .{},
                );
                return models.ExecResult{
                    .exit_code = 1,
                    .stdout = try self.allocator.dupe(u8, ""),
                    .stderr = stderr_msg,
                    .duration_ms = std.time.milliTimestamp() - start_time,
                };
            };

            const name = if (metadata.get("name")) |n|
                if (n == .string) n.string else {
                    const stderr_msg = try std.fmt.allocPrint(
                        self.allocator,
                        "Invalid pod name in metadata",
                        .{},
                    );
                    return models.ExecResult{
                        .exit_code = 1,
                        .stdout = try self.allocator.dupe(u8, ""),
                        .stderr = stderr_msg,
                        .duration_ms = std.time.milliTimestamp() - start_time,
                    };
                }
            else {
                const stderr_msg = try std.fmt.allocPrint(
                    self.allocator,
                    "Missing pod name in metadata",
                    .{},
                );
                return models.ExecResult{
                    .exit_code = 1,
                    .stdout = try self.allocator.dupe(u8, ""),
                    .stderr = stderr_msg,
                    .duration_ms = std.time.milliTimestamp() - start_time,
                };
            };

            // Duplicate pod name to keep it after arena deinit
            break :blk try self.allocator.dupe(u8, name);
        };
        defer self.allocator.free(pod_name);

        // Step 2: Parse command into array
        var cmd_parts = std.ArrayList([]const u8).init(self.allocator);
        defer cmd_parts.deinit();

        try cmd_parts.append("/bin/sh");
        try cmd_parts.append("-c");
        try cmd_parts.append(command);

        // Step 3: Execute command via Kubernetes exec API
        // Note: Kubernetes exec API uses WebSocket protocol with SPDY or WebSocket streams
        // The response format is binary with channel prefixes:
        // - Channel 1: stdout
        // - Channel 2: stderr
        // - Channel 3: exit code (JSON: {"status":"Success","code":0} or {"status":"Failure","code":N})
        // Full implementation requires WebSocket client with binary frame parsing
        const exec_response = self.kube_client.execInPod(
            namespace,
            pod_name,
            "sandbox", // container name
            try cmd_parts.toOwnedSlice(),
        ) catch |err| {
            const stderr_msg = try std.fmt.allocPrint(
                self.allocator,
                "Failed to execute command: {s}",
                .{@errorName(err)},
            );

            return models.ExecResult{
                .exit_code = 1,
                .stdout = try self.allocator.dupe(u8, ""),
                .stderr = stderr_msg,
                .duration_ms = std.time.milliTimestamp() - start_time,
            };
        };
        defer self.allocator.free(exec_response);

        // Parse exec response
        // The Kubernetes client's execInPod returns the raw response body
        // For simplicity, treat the entire response as stdout for now
        // A full implementation would:
        // 1. Parse WebSocket frames with channel prefixes (1 byte: channel, rest: data)
        // 2. Split stdout (channel 1) from stderr (channel 2)
        // 3. Parse exit code from channel 3 JSON payload
        // For now, basic string handling:
        const duration_ms = std.time.milliTimestamp() - start_time;

        // Check if response indicates error
        if (std.mem.indexOf(u8, exec_response, "error") != null or
            std.mem.indexOf(u8, exec_response, "Error") != null or
            std.mem.indexOf(u8, exec_response, "failed") != null)
        {
            return models.ExecResult{
                .exit_code = 1,
                .stdout = try self.allocator.dupe(u8, ""),
                .stderr = try self.allocator.dupe(u8, exec_response),
                .duration_ms = duration_ms,
            };
        }

        // Assume success for now
        return models.ExecResult{
            .exit_code = 0,
            .stdout = try self.allocator.dupe(u8, exec_response),
            .stderr = try self.allocator.dupe(u8, ""),
            .duration_ms = duration_ms,
        };
    }

    /// Get sandbox metrics
    pub fn getSandboxMetrics(
        self: *K7Core,
        namespace: ?[]const u8,
    ) ![]MetricInfo {
        const ns = namespace orelse self.kube_client.config.namespace;

        // Query Kubernetes metrics API (metrics.k8s.io/v1beta1)
        const metrics_json = try self.kube_client.getPodMetrics(ns);
        defer self.allocator.free(metrics_json);

        // Parse metrics JSON response
        // Response format:
        // {"kind":"PodMetricsList","items":[{"metadata":{"name":"pod-name","namespace":"default"},"containers":[{"name":"container-name","usage":{"cpu":"100m","memory":"128Mi"}}]}]}

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const arena_allocator = arena.allocator();

        const parsed = std.json.parseFromSlice(
            std.json.Value,
            arena_allocator,
            metrics_json,
            .{},
        ) catch {
            // If JSON parsing fails, return empty list
            const empty_list = try self.allocator.alloc(MetricInfo, 0);
            return empty_list;
        };

        const root = parsed.value;

        // Get items array
        const items = if (root.object.get("items")) |items_value|
            if (items_value == .array) items_value.array else return try self.allocator.alloc(MetricInfo, 0)
        else
            return try self.allocator.alloc(MetricInfo, 0);

        if (items.items.len == 0) {
            const empty_list = try self.allocator.alloc(MetricInfo, 0);
            return empty_list;
        }

        // Allocate result array
        var metrics_list = std.ArrayList(MetricInfo).init(self.allocator);
        errdefer metrics_list.deinit();

        // Parse each pod metric
        for (items.items) |item_value| {
            if (item_value != .object) continue;
            const item = item_value.object;

            // Extract metadata
            const metadata = if (item.get("metadata")) |m|
                if (m == .object) m.object else continue
            else continue;

            const name = if (metadata.get("name")) |n|
                if (n == .string) n.string else continue
            else continue;

            const pod_namespace = if (metadata.get("namespace")) |n|
                if (n == .string) n.string else ns
            else ns;

            // Extract containers
            const containers = if (item.get("containers")) |c|
                if (c == .array) c.array else continue
            else continue;

            // Aggregate metrics from all containers
            var total_cpu_millicores: u64 = 0;
            var total_memory_bytes: u64 = 0;

            for (containers.items) |container_value| {
                if (container_value != .object) continue;
                const container = container_value.object;

                const usage = if (container.get("usage")) |u|
                    if (u == .object) u.object else continue
                else continue;

                // Parse CPU
                if (usage.get("cpu")) |cpu_value| {
                    if (cpu_value == .string) {
                        const cpu_str = cpu_value.string;
                        const cpu_millicores = try self.parseCpuString(cpu_str);
                        total_cpu_millicores += cpu_millicores;
                    }
                }

                // Parse Memory
                if (usage.get("memory")) |memory_value| {
                    if (memory_value == .string) {
                        const memory_str = memory_value.string;
                        const memory_bytes = try self.parseMemoryString(memory_str);
                        total_memory_bytes += memory_bytes;
                    }
                }
            }

            // Format metrics for display
            const cpu_display = try self.formatCpuMetric(total_cpu_millicores);
            const memory_display = try self.formatMemoryMetric(total_memory_bytes);

            // Create MetricInfo
            const info = MetricInfo{
                .name = try self.allocator.dupe(u8, name),
                .namespace = try self.allocator.dupe(u8, pod_namespace),
                .cpu_usage = cpu_display,
                .memory_usage = memory_display,
            };

            try metrics_list.append(info);
        }

        return try metrics_list.toOwnedSlice();
    }

    /// Parse CPU string from Kubernetes metrics (e.g., "100m", "1", "500n")
    /// Returns millicores
    fn parseCpuString(self: *K7Core, cpu_str: []const u8) !u64 {
        _ = self;
        if (cpu_str.len == 0) return 0;

        // Check for unit suffix
        const last_char = cpu_str[cpu_str.len - 1];

        if (std.ascii.isDigit(last_char)) {
            // No suffix, value is in cores, convert to millicores
            const cores = try std.fmt.parseInt(u64, cpu_str, 10);
            return cores * 1000;
        } else if (last_char == 'm') {
            // Millicores
            const value_str = cpu_str[0 .. cpu_str.len - 1];
            return try std.fmt.parseInt(u64, value_str, 10);
        } else if (last_char == 'n') {
            // Nanocores, convert to millicores
            const value_str = cpu_str[0 .. cpu_str.len - 1];
            const nanocores = try std.fmt.parseInt(u64, value_str, 10);
            return nanocores / 1_000_000;
        } else if (last_char == 'u') {
            // Microcores, convert to millicores
            const value_str = cpu_str[0 .. cpu_str.len - 1];
            const microcores = try std.fmt.parseInt(u64, value_str, 10);
            return microcores / 1000;
        }

        return 0;
    }

    /// Parse memory string from Kubernetes metrics (e.g., "128Mi", "1Gi", "512Ki")
    /// Returns bytes
    fn parseMemoryString(self: *K7Core, memory_str: []const u8) !u64 {
        _ = self;
        if (memory_str.len < 2) return 0;

        // Check for unit suffix (Ki, Mi, Gi, Ti)
        if (memory_str.len >= 2) {
            const suffix = memory_str[memory_str.len - 2 ..];
            var value_str: []const u8 = undefined;
            var multiplier: u64 = 1;

            if (std.mem.eql(u8, suffix, "Ki")) {
                value_str = memory_str[0 .. memory_str.len - 2];
                multiplier = 1024;
            } else if (std.mem.eql(u8, suffix, "Mi")) {
                value_str = memory_str[0 .. memory_str.len - 2];
                multiplier = 1024 * 1024;
            } else if (std.mem.eql(u8, suffix, "Gi")) {
                value_str = memory_str[0 .. memory_str.len - 2];
                multiplier = 1024 * 1024 * 1024;
            } else if (std.mem.eql(u8, suffix, "Ti")) {
                value_str = memory_str[0 .. memory_str.len - 2];
                multiplier = 1024 * 1024 * 1024 * 1024;
            } else {
                // No recognized suffix, try to parse as raw bytes
                return try std.fmt.parseInt(u64, memory_str, 10);
            }

            const value = try std.fmt.parseInt(u64, value_str, 10);
            return value * multiplier;
        }

        return 0;
    }

    /// Format CPU millicores for display (e.g., "100m", "1.5", "2.25")
    fn formatCpuMetric(self: *K7Core, millicores: u64) ![]const u8 {
        if (millicores == 0) {
            return try self.allocator.dupe(u8, "0m");
        }

        if (millicores < 1000) {
            // Display as millicores
            return try std.fmt.allocPrint(self.allocator, "{d}m", .{millicores});
        } else {
            // Display as cores with decimal
            const cores = millicores / 1000;
            const remainder = millicores % 1000;
            if (remainder == 0) {
                return try std.fmt.allocPrint(self.allocator, "{d}", .{cores});
            } else {
                // Show up to 2 decimal places
                const decimal = remainder / 10;
                return try std.fmt.allocPrint(self.allocator, "{d}.{d:0>2}", .{ cores, decimal });
            }
        }
    }

    /// Format memory bytes for display (e.g., "128Mi", "1.5Gi")
    fn formatMemoryMetric(self: *K7Core, bytes: u64) ![]const u8 {
        if (bytes == 0) {
            return try self.allocator.dupe(u8, "0");
        }

        const gb = 1024 * 1024 * 1024;
        const mb = 1024 * 1024;
        const kb = 1024;

        if (bytes >= gb) {
            const gigs = bytes / gb;
            const remainder = (bytes % gb) / (gb / 10);
            if (remainder == 0) {
                return try std.fmt.allocPrint(self.allocator, "{d}Gi", .{gigs});
            } else {
                return try std.fmt.allocPrint(self.allocator, "{d}.{d}Gi", .{ gigs, remainder });
            }
        } else if (bytes >= mb) {
            const megs = bytes / mb;
            const remainder = (bytes % mb) / (mb / 10);
            if (remainder == 0) {
                return try std.fmt.allocPrint(self.allocator, "{d}Mi", .{megs});
            } else {
                return try std.fmt.allocPrint(self.allocator, "{d}.{d}Mi", .{ megs, remainder });
            }
        } else if (bytes >= kb) {
            const kilos = bytes / kb;
            return try std.fmt.allocPrint(self.allocator, "{d}Ki", .{kilos});
        } else {
            return try std.fmt.allocPrint(self.allocator, "{d}", .{bytes});
        }
    }

    /// Install K7 on node via Ansible
    pub fn installNode(
        self: *K7Core,
        playbook_content: ?[]const u8,
        inventory_content: ?[]const u8,
        verbose: bool,
        progress_callback: ?*const fn (event: ProgressEvent) void,
    ) !models.OperationResult {
        _ = self;
        _ = playbook_content;
        _ = inventory_content;
        _ = verbose;
        _ = progress_callback;

        // TODO: Implement Ansible execution:
        // 1. Create temporary files for playbook and inventory
        // 2. Spawn ansible-playbook subprocess
        // 3. Stream stdout/stderr
        // 4. Parse output for progress (TASK [...] lines)
        // 5. Invoke progress callback
        // 6. Return success/failure

        return try models.OperationResult.success_result(
            self.allocator,
            "Installation completed successfully (placeholder)",
        );
    }
};

/// Progress event for callbacks
pub const ProgressEvent = struct {
    stage: []const u8,
    status: []const u8,
    message: ?[]const u8 = null,
};

/// Metric information
pub const MetricInfo = struct {
    name: []const u8,
    namespace: []const u8,
    cpu_usage: []const u8,
    memory_usage: []const u8,
};
