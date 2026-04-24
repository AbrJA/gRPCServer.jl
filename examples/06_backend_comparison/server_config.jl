# Shared configuration and service definitions for backend comparison

using gRPCServer
include("../01_hello_world/generated/helloworld/helloworld.jl")
using .helloworld

# ==============================================================================
# Shared Test Service
# ==============================================================================

"""A simple echo service for testing different backends"""

# Service handlers
function echo_handler(ctx::ServerContext, request::HelloRequest)::HelloReply
    @debug "Echo request" name=request.name request_id=ctx.request_id
    return HelloReply("Echo: $(request.name)")
end

# Service descriptor
struct EchoService end

function gRPCServer.service_descriptor(::EchoService)
    ServiceDescriptor(
        "helloworld.Echo",
        Dict(
            "Echo" => MethodDescriptor(
                "Echo", MethodType.UNARY,
                HelloRequest, HelloReply,
                echo_handler
            )
        ),
        nothing
    )
end

# ==============================================================================
# Server Factory Function
# ==============================================================================

"""
    create_server(host::String, port::Int, backend_type::Symbol)

Create a gRPC server with the specified backend.

# Arguments
- `host`: Server bind address (e.g., "127.0.0.1" or "0.0.0.0")
- `port`: Server port
- `backend_type`: `:pure` for PureHTTP2, `:nghttp2` for Nghttp2

# Returns
A configured GRPCServer instance with EchoService registered.
"""
function create_server(host::String, port::Int, backend_type::Symbol=:pure)
    local backend

    if backend_type == :nghttp2
        try
            # Try to load Nghttp2Wrapper
            @eval using Nghttp2Wrapper
            backend = gRPCServer.Nghttp2Backend()
            @info "Created server with Nghttp2Backend"
        catch e
            @warn "Failed to load Nghttp2Wrapper, falling back to PureHTTP2" exception=e
            backend = gRPCServer.PureHTTP2Backend()
        end
    else
        backend = gRPCServer.PureHTTP2Backend()
        @info "Created server with PureHTTP2Backend"
    end

    server = GRPCServer(host, port;
        http2_backend=backend,
        enable_health_check=true,
        enable_reflection=true,
        log_requests=true,
        max_concurrent_streams=200,
        max_connections=1000,
        compression_enabled=true
    )

    register!(server, EchoService())

    return server
end

# ==============================================================================
# Configuration Constants
# ==============================================================================

const PURE_BACKEND_PORT = 50051
const NGHTTP2_BACKEND_PORT = 50052

# Test parameters for benchmarking
const BENCHMARK_CONFIG = (
    num_requests = 1000,
    concurrent_requests = 10,
    message_size = 100,
    timeout_seconds = 30.0,
)
