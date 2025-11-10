const std = @import("std");
const models = @import("../core/models.zig");

// C-compatible SDK for language bindings
// This allows Python, Go, Node.js, etc. to use K7 via FFI

/// Opaque client handle for C FFI
pub const K7Client = opaque {};

/// Initialize K7 client
export fn k7_client_init(endpoint: [*:0]const u8, api_key: [*:0]const u8) ?*K7Client {
    _ = endpoint;
    _ = api_key;

    // TODO: Implement client initialization
    // 1. Allocate client structure
    // 2. Store endpoint and api_key
    // 3. Initialize HTTP client
    // 4. Return opaque pointer

    return null;
}

/// Destroy K7 client
export fn k7_client_deinit(client: *K7Client) void {
    _ = client;

    // TODO: Implement client cleanup
    // 1. Free all allocated memory
    // 2. Close HTTP connections
    // 3. Deallocate client structure
}

/// Create sandbox
export fn k7_create_sandbox(client: *K7Client, config_json: [*:0]const u8) ?[*:0]const u8 {
    _ = client;
    _ = config_json;

    // TODO: Implement sandbox creation
    // 1. Parse config JSON
    // 2. Send POST request to /api/v1/sandboxes
    // 3. Return JSON response (must be freed by caller with k7_free_string)

    return null;
}

/// List sandboxes
export fn k7_list_sandboxes(client: *K7Client, namespace: ?[*:0]const u8) ?[*:0]const u8 {
    _ = client;
    _ = namespace;

    // TODO: Implement sandbox listing
    // 1. Send GET request to /api/v1/sandboxes
    // 2. Return JSON array response

    return null;
}

/// Delete sandbox
export fn k7_delete_sandbox(client: *K7Client, name: [*:0]const u8, namespace: [*:0]const u8) bool {
    _ = client;
    _ = name;
    _ = namespace;

    // TODO: Implement sandbox deletion
    // 1. Send DELETE request to /api/v1/sandboxes/{name}
    // 2. Return true on success, false on failure

    return false;
}

/// Execute command in sandbox
export fn k7_exec_command(
    client: *K7Client,
    name: [*:0]const u8,
    command: [*:0]const u8,
    namespace: [*:0]const u8,
) ?[*:0]const u8 {
    _ = client;
    _ = name;
    _ = command;
    _ = namespace;

    // TODO: Implement command execution
    // 1. Send POST request to /api/v1/sandboxes/{name}/exec
    // 2. Return JSON ExecResult

    return null;
}

/// Free string allocated by SDK
export fn k7_free_string(str: [*:0]const u8) void {
    _ = str;

    // TODO: Implement string deallocation
    // Use C allocator to free memory
}

// Example Python usage with ctypes:
//
// import ctypes
// import json
//
// libk7 = ctypes.CDLL("libk7sdk.so")
//
// libk7.k7_client_init.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
// libk7.k7_client_init.restype = ctypes.c_void_p
//
// libk7.k7_create_sandbox.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
// libk7.k7_create_sandbox.restype = ctypes.c_char_p
//
// libk7.k7_free_string.argtypes = [ctypes.c_char_p]
// libk7.k7_free_string.restype = None
//
// client = libk7.k7_client_init(b"https://api.example.com", b"my-key")
//
// config = json.dumps({"name": "test", "image": "alpine:latest"})
// result_json = libk7.k7_create_sandbox(client, config.encode())
// result = json.loads(result_json.decode())
// libk7.k7_free_string(result_json)
//
// libk7.k7_client_deinit(client)
