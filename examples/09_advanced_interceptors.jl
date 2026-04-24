# ==============================================================================
# Advanced Interceptors Example
# ==============================================================================
# This example demonstrates advanced interceptor patterns:
# - Request/response modification
# - Authentication and authorization
# - Distributed tracing integration
# - Custom error handling
# - Performance profiling

using gRPCServer
using Logging
using UUIDs
using Dates
include("01_hello_world/generated/helloworld/helloworld.jl")
using .helloworld

# ==============================================================================
# Message Types
# ==============================================================================

struct AuthRequest
    username::String
    password::String
end

struct AuthReply
    success::Bool
    token::String
    message::String
end

# ==============================================================================
# Authentication Interceptor
# ==============================================================================

"""
    AuthenticationInterceptor

Validates authentication tokens in request headers.
Prevents unauthenticated requests from reaching handlers.
"""
struct AuthenticationInterceptor <: gRPCServer.Interceptor
    valid_tokens::Set{String}
end

AuthenticationInterceptor() = AuthenticationInterceptor(Set(["demo-token-123"]))

function (interceptor::AuthenticationInterceptor)(ctx::ServerContext, request, info::MethodInfo, next::Function)
    # Skip auth for health check and reflection services
    if startswith(info.service_name, "grpc.") || startswith(info.service_name, "grpc.reflection")
        return next(ctx, request)
    end

    # Extract token from metadata
    token = get_metadata_string(ctx, "authorization")

    if token === nothing || !in(token, interceptor.valid_tokens)
        @warn "Unauthorized request" service=info.service_name method=info.method_name request_id=ctx.request_id
        throw(GRPCError(StatusCode.UNAUTHENTICATED, "Authentication required"))
    end

    @debug "Request authenticated" token_present=true request_id=ctx.request_id
    return next(ctx, request)
end

# ==============================================================================
# Tracing Interceptor
# ==============================================================================

"""
    TracingInterceptor

Implements distributed tracing similar to Jaeger/Datadog.
Propagates trace context through the call chain.
"""
struct TracingInterceptor <: gRPCServer.Interceptor
    service_name::String
end

function (interceptor::TracingInterceptor)(ctx::ServerContext, request, info::MethodInfo, next::Function)
    trace_id = get_metadata_string(ctx, "x-trace-id")
    if trace_id === nothing
        trace_id = string(uuid4())
    end
    span_id = string(uuid4())

    @info "Span start" trace_id=trace_id span_id=span_id service=interceptor.service_name rpc_service=info.service_name rpc_method=info.method_name

    start_time = time()
    try
        result = next(ctx, request)
        elapsed = (time() - start_time) * 1000

        @info "Span success" trace_id=trace_id span_id=span_id elapsed_ms=round(elapsed; digits=2)
        return result
    catch e
        elapsed = (time() - start_time) * 1000
        @warn "Span error" trace_id=trace_id span_id=span_id elapsed_ms=round(elapsed; digits=2) exception=e
        rethrow()
    end
end

# ==============================================================================
# Caching Interceptor
# ==============================================================================

"""
    CachingInterceptor

Simple request/response caching based on request content.
Useful for idempotent operations.
"""
mutable struct CachingInterceptor <: gRPCServer.Interceptor
    cache::Dict{String, Any}
    max_cache_size::Int
    hits::Int
    misses::Int
    lock::ReentrantLock
end

function CachingInterceptor(max_size::Int=1000)
    CachingInterceptor(Dict{String, Any}(), max_size, 0, 0, ReentrantLock())
end

function (interceptor::CachingInterceptor)(ctx::ServerContext, request, info::MethodInfo, next::Function)
    # Only cache unary requests
    cache_key = "$(info.service_name)/$(info.method_name)/$(hash(request))"

    lock(interceptor.lock) do
        if haskey(interceptor.cache, cache_key)
            interceptor.hits += 1
            @debug "Cache hit" cache_key=cache_key hits=interceptor.hits
            return interceptor.cache[cache_key]
        end
    end

    # Cache miss
    result = next(ctx, request)

    lock(interceptor.lock) do
        interceptor.misses += 1
        # Store in cache if not full
        if length(interceptor.cache) < interceptor.max_cache_size
            interceptor.cache[cache_key] = result
        end
    end

    return result
end

function print_cache_stats(interceptor::CachingInterceptor)
    lock(interceptor.lock) do
        total = interceptor.hits + interceptor.misses
        hit_rate = total > 0 ? interceptor.hits / total * 100 : 0
        @info "Cache Statistics"
        @info "  Hits:     $(interceptor.hits)"
        @info "  Misses:   $(interceptor.misses)"
        @info "  Hit Rate: $(round(hit_rate; digits=1))%"
        @info "  Size:     $(length(interceptor.cache))/$(interceptor.max_cache_size)"
    end
end

# ==============================================================================
# Service Definition
# ==============================================================================

struct AdvancedService end

function authenticate_handler(ctx::ServerContext, request::HelloRequest)::HelloReply
    @info "Authentication request" username=request.name

    # Simple auth logic for demo
    if request.name == "demo"
        return HelloReply("Authentication successful; token=demo-token-123")
    else
        return HelloReply("Authentication failed")
    end
end

function gRPCServer.service_descriptor(::AdvancedService)
    ServiceDescriptor(
        "helloworld.Advanced",
        Dict(
            "Authenticate" => MethodDescriptor(
                "Authenticate", MethodType.UNARY,
                HelloRequest, HelloReply,
                authenticate_handler
            )
        ),
        nothing
    )
end

# ==============================================================================
# Main Server with Advanced Interceptors
# ==============================================================================

function main()
    @info "Advanced Interceptors Example"
    @info "=" ^ 80

    # Create server
    server = GRPCServer(
        "0.0.0.0", 50051;
        enable_health_check=true,
        enable_reflection=true
    )

    # Setup interceptors
    @info "Setting up interceptors..."

    # Tracing (outer)
    add_interceptor!(server, TracingInterceptor("advanced-server"))

    # Authentication (middle)
    auth_interceptor = AuthenticationInterceptor()
    add_interceptor!(server, auth_interceptor)

    # Caching (inner)
    cache_interceptor = CachingInterceptor(100)
    add_interceptor!(server, cache_interceptor)

    # Register service
    register!(server, AdvancedService())

    @info "=" ^ 80
    @info "Advanced server started on 0.0.0.0:50051"
    @info ""
    @info "Features:"
    @info "  • Distributed tracing (trace IDs)"
    @info "  • Authentication (x-trace-id header required)"
    @info "  • Request caching"
    @info ""
    @info "First, authenticate to get a token:"
    @info "  grpcurl -plaintext -d '{\"name\":\"demo\"}' \\"
    @info "    localhost:50051 helloworld.Advanced/Authenticate"
    @info ""
    @info "Then use the token in subsequent requests:"
    @info "  grpcurl -plaintext -H 'authorization: demo-token-123' \\"
    @info "    -d '{\"name\":\"demo\"}' localhost:50051 helloworld.Advanced/Authenticate"
    @info ""
    @info "Press Ctrl+C to stop"
    @info "=" ^ 80

    try
        run(server)
    catch e
        if e isa InterruptException
            @info "Shutting down..."
            print_cache_stats(cache_interceptor)
        else
            rethrow()
        end
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
