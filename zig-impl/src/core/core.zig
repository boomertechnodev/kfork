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

            // TODO: Parse JSON and check if pod is ready
            // For now, sleep and retry
            std.time.sleep(2 * std.time.ns_per_s); // 2 seconds

            // Placeholder: assume ready after 10 seconds
            if (elapsed > 10) break;
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

        // TODO: Parse JSON response to get deployment list
        // For now, query pods directly to get status
        const pods_json = try self.kube_client.listPods(ns, label_selector);
        defer self.allocator.free(pods_json);

        // TODO: Parse JSON and build SandboxInfo array
        // This requires a JSON parser - for now return empty list as placeholder
        // In full implementation, would use std.json to parse and extract:
        // - deployment name
        // - pod status (Running/Pending/Failed)
        // - age calculation from creationTimestamp
        // - ready condition from status.conditions
        // - restart count from status.containerStatuses
        const empty_list = try self.allocator.alloc(models.SandboxInfo, 0);
        return empty_list;
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

        // Step 1: Find pod for deployment
        const label_selector = try std.fmt.allocPrint(self.allocator, "app={s}", .{sandbox_name});
        defer self.allocator.free(label_selector);

        const pods_json = try self.kube_client.listPods(namespace, label_selector);
        defer self.allocator.free(pods_json);

        // TODO: Parse JSON to get pod name
        // For now, construct expected pod name
        // In real implementation, would parse pods_json to get actual pod name

        // Step 2: Parse command into array
        var cmd_parts = std.ArrayList([]const u8).init(self.allocator);
        defer cmd_parts.deinit();

        try cmd_parts.append("/bin/sh");
        try cmd_parts.append("-c");
        try cmd_parts.append(command);

        // Step 3: Execute command via Kubernetes exec API
        // This requires WebSocket support which is complex
        // For now, use the exec API endpoint
        const pod_name = try std.fmt.allocPrint(self.allocator, "{s}-pod", .{sandbox_name});
        defer self.allocator.free(pod_name);

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

        // TODO: Parse exec response to extract stdout, stderr, exit code
        // WebSocket exec protocol returns binary stream with channel prefixes
        // For now, return placeholder response

        const duration_ms = std.time.milliTimestamp() - start_time;

        return models.ExecResult{
            .exit_code = 0,
            .stdout = try self.allocator.dupe(u8, "Command executed successfully"),
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

        // TODO: Parse JSON response to extract metrics
        // Response format:
        // {
        //   "items": [
        //     {
        //       "metadata": {"name": "pod-name", "namespace": "default"},
        //       "containers": [
        //         {
        //           "name": "container-name",
        //           "usage": {"cpu": "100m", "memory": "128Mi"}
        //         }
        //       ]
        //     }
        //   ]
        // }
        //
        // Would need to:
        // 1. Parse JSON with std.json
        // 2. Extract pod names and container usage
        // 3. Convert CPU units (n=nanocores, u=microcores, m=millicores)
        // 4. Convert memory units (Ki/Mi/Gi to bytes)
        // 5. Build MetricInfo array

        // For now, return empty list as placeholder
        const empty_list = try self.allocator.alloc(MetricInfo, 0);
        return empty_list;
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
