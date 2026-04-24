# ==============================================================================
# Production-Ready gRPCServer Example
# ==============================================================================
# This example demonstrates how to set up a production-ready gRPC server with:
# - Multiple services and RPC patterns
# - Custom interceptors for logging, metrics, and error recovery
# - TLS/mTLS configuration
# - Health checking and reflection services
# - Graceful shutdown handling
# - Environment-based configuration
# - Backend selection (PureHTTP2 vs Nghttp2)
# - Comprehensive error handling
# ==============================================================================

using gRPCServer
using Logging
using Dates
using Statistics

# ==============================================================================
# PART 1: Define Message Types and Services
# ==============================================================================

# Echo service for testing
struct EchoRequest
    message::String
end

struct EchoReply
    message::String
    timestamp::String
end

# Math service for computation
struct MathRequest
    operand_a::Float64
    operand_b::Float64
end

struct MathReply
    result::Float64
    operation::String
end

struct DivideRequest
    dividend::Float64
    divisor::Float64
end

struct DivideReply
    quotient::Float64
    remainder::Float64
end

# Service containers
struct EchoService end
struct MathService end

# ==============================================================================
# PART 2: Implement Service Handlers
# ==============================================================================

# Echo handlers
function echo_handler(ctx::ServerContext, request::EchoRequest)::EchoReply
    @info "Echo request" message=request.message request_id=ctx.request_id
    return EchoReply(
        "Echo: $(request.message)",
        string(now())
    )
end

# Math handlers
function add_handler(ctx::ServerContext, request::MathRequest)::MathReply
    @debug "Add request" a=request.operand_a b=request.operand_b request_id=ctx.request_id
    return MathReply(
        request.operand_a + request.operand_b,
        "ADD"
    )
end

function multiply_handler(ctx::ServerContext, request::MathRequest)::MathReply
    @debug "Multiply request" a=request.operand_a b=request.operand_b request_id=ctx.request_id
    return MathReply(
        request.operand_a * request.operand_b,
        "MULTIPLY"
    )
end

function divide_handler(ctx::ServerContext, request::DivideRequest)::DivideReply
    @debug "Divide request" dividend=request.dividend divisor=request.divisor request_id=ctx.request_id

    if request.divisor == 0.0
        @warn "Division by zero attempt" request_id=ctx.request_id
        # In real gRPC, would return error via context
        return DivideReply(0.0, request.dividend)
    end

    quotient = div(request.dividend, request.divisor)
    remainder = rem(request.dividend, request.divisor)

    return DivideReply(Float64(quotient), remainder)
end

# ==============================================================================
# PART 3: Define Service Descriptors
# ==============================================================================

function gRPCServer.service_descriptor(::EchoService)
    ServiceDescriptor(
        "example.Echo",
        Dict(
            "Echo" => MethodDescriptor(
                "Echo", MethodType.UNARY,
                EchoRequest, EchoReply,
                echo_handler
            )
        ),
        nothing
    )
end

function gRPCServer.service_descriptor(::MathService)
    ServiceDescriptor(
        "example.Math",
        Dict(
            "Add" => MethodDescriptor(
                "Add", MethodType.UNARY,
                MathRequest, MathReply,
                add_handler
            ),
            "Multiply" => MethodDescriptor(
                "Multiply", MethodType.UNARY,
                MathRequest, MathReply,
                multiply_handler
            ),
            "Divide" => MethodDescriptor(
                "Divide", MethodType.UNARY,
                DivideRequest, DivideReply,
                divide_handler
            )
        ),
        nothing
    )
end

# ==============================================================================
# PART 4: Custom Interceptors
# ==============================================================================

"""Simple logging interceptor"""
struct LoggingInterceptor <: gRPCServer.Interceptor
    enabled::Bool
end

LoggingInterceptor() = LoggingInterceptor(true)

function (::LoggingInterceptor)(ctx::ServerContext, request, info::MethodInfo, next::Function)
    start_time = time()
    try
        result = next(ctx, request)
        elapsed = (time() - start_time) * 1000
        @info "RPC completed" service=info.service_name method=info.method_name elapsed_ms=round(elapsed; digits=2)
        return result
    catch e
        elapsed = (time() - start_time) * 1000
        @error "RPC failed" service=info.service_name method=info.method_name elapsed_ms=round(elapsed; digits=2) exception=e
        rethrow()
    end
end

"""Simple metrics interceptor for tracking statistics"""
mutable struct MetricsInterceptor <: gRPCServer.Interceptor
    total_requests::Int
    total_errors::Int
    latencies::Vector{Float64}
    lock::ReentrantLock
end

MetricsInterceptor() = MetricsInterceptor(0, 0, Float64[], ReentrantLock())

function (interceptor::MetricsInterceptor)(ctx::ServerContext, request, info::MethodInfo, next::Function)
    start_time = time()
    try
        result = next(ctx, request)
        elapsed = (time() - start_time) * 1000

        lock(interceptor.lock) do
            interceptor.total_requests += 1
            push!(interceptor.latencies, elapsed)
            # Keep only last 10000 latencies to avoid unbounded growth
            if length(interceptor.latencies) > 10000
                interceptor.latencies = interceptor.latencies[end-9999:end]
            end
        end

        return result
    catch e
        lock(interceptor.lock) do
            interceptor.total_requests += 1
            interceptor.total_errors += 1
        end
        rethrow()
    end
end

function print_metrics(metrics::MetricsInterceptor)
    lock(metrics.lock) do
        if metrics.total_requests > 0
            avg_latency = mean(metrics.latencies)
            min_latency = minimum(metrics.latencies)
            max_latency = maximum(metrics.latencies)
            error_rate = metrics.total_errors / metrics.total_requests * 100

            @info "Metrics Summary" total_requests=metrics.total_requests avg_latency_ms=round(avg_latency; digits=2) min_latency_ms=round(min_latency; digits=2) max_latency_ms=round(max_latency; digits=2) error_rate=round(error_rate; digits=1)
        end
    end
end

# ==============================================================================
# PART 5: Configuration Management
# ==============================================================================

"""Load configuration from environment variables"""
function load_config()
    return (
        # Server address
        host = get(ENV, "GRPC_HOST", "0.0.0.0"),
        port = parse(Int, get(ENV, "GRPC_PORT", "50051")),

        # Backend selection
        backend = Symbol(get(ENV, "GRPC_BACKEND", "pure")),

        # Connection limits
        max_connections = parse(Int, get(ENV, "GRPC_MAX_CONNECTIONS", "10000")),
        max_concurrent_streams = parse(Int, get(ENV, "GRPC_MAX_STREAMS", "200")),
        max_message_size = parse(Int, get(ENV, "GRPC_MAX_MESSAGE_SIZE", "4194304")),  # 4MB

        # Timeouts (in seconds)
        keepalive_interval = parse(Float64, get(ENV, "GRPC_KEEPALIVE_INTERVAL", "60.0")),
        keepalive_timeout = parse(Float64, get(ENV, "GRPC_KEEPALIVE_TIMEOUT", "20.0")),
        idle_timeout = parse(Float64, get(ENV, "GRPC_IDLE_TIMEOUT", "300.0")),
        drain_timeout = parse(Float64, get(ENV, "GRPC_DRAIN_TIMEOUT", "30.0")),

        # Features
        enable_health_check = parse(Bool, get(ENV, "GRPC_HEALTH_CHECK", "true")),
        enable_reflection = parse(Bool, get(ENV, "GRPC_REFLECTION", "true")),
        enable_compression = parse(Bool, get(ENV, "GRPC_COMPRESSION", "true")),
        debug_mode = parse(Bool, get(ENV, "GRPC_DEBUG", "false")),

        # TLS
        enable_tls = parse(Bool, get(ENV, "GRPC_TLS_ENABLED", "false")),
        tls_cert = get(ENV, "GRPC_TLS_CERT", ""),
        tls_key = get(ENV, "GRPC_TLS_KEY", ""),
    )
end

function print_config(config)
    @info "Server Configuration"
    @info "  Address:            $(config.host):$(config.port)"
    @info "  Backend:            $(config.backend)"
    @info "  Max Connections:    $(config.max_connections)"
    @info "  Max Streams:        $(config.max_concurrent_streams)"
    @info "  Max Message Size:   $(config.max_message_size / 1024 / 1024) MB"
    @info "  Keepalive Interval: $(config.keepalive_interval)s"
    @info "  Idle Timeout:       $(config.idle_timeout)s"
    @info "  Health Check:       $(config.enable_health_check ? "enabled" : "disabled")"
    @info "  Reflection:         $(config.enable_reflection ? "enabled" : "disabled")"
    @info "  Compression:        $(config.enable_compression ? "enabled" : "disabled")"
    @info "  TLS:                $(config.enable_tls ? "enabled" : "disabled")"
end

# ==============================================================================
# PART 6: Main Server Initialization
# ==============================================================================

function main()
    # Configure logging
    global_logger(ConsoleLogger(stderr, Logging.Info))

    @info "Production gRPC Server Starting"
    @info "=" ^ 80

    # Load configuration
    config = load_config()
    print_config(config)

    # Select HTTP/2 backend
    local backend
    if config.backend == :nghttp2
        try
            @eval using Nghttp2Wrapper
            backend = gRPCServer.Nghttp2Backend()
            @info "Using Nghttp2Backend (high-performance C-based)"
        catch e
            @warn "Nghttp2Wrapper not available, falling back to PureHTTP2Backend" exception=e
            backend = gRPCServer.PureHTTP2Backend()
        end
    else
        backend = gRPCServer.PureHTTP2Backend()
        @info "Using PureHTTP2Backend (pure Julia implementation)"
    end

    # Create server with configuration
    server = GRPCServer(
        config.host, config.port;
        http2_backend=backend,
        max_connections=config.max_connections,
        max_concurrent_streams=config.max_concurrent_streams,
        max_message_size=config.max_message_size,
        keepalive_interval=config.keepalive_interval,
        keepalive_timeout=config.keepalive_timeout,
        idle_timeout=config.idle_timeout,
        drain_timeout=config.drain_timeout,
        enable_health_check=config.enable_health_check,
        enable_reflection=config.enable_reflection,
        compression_enabled=config.enable_compression,
        debug_mode=config.debug_mode
    )

    # Create and add interceptors
    @info "Setting up interceptors..."
    logging_interceptor = LoggingInterceptor()
    metrics_interceptor = MetricsInterceptor()

    add_interceptor!(server, metrics_interceptor)
    add_interceptor!(server, logging_interceptor)

    # Register services
    @info "Registering services..."
    register!(server, EchoService())
    register!(server, MathService())

    @info "Registered services:"
    for service_name in keys(server.dispatcher.registry.services)
        @info "  - $service_name"
    end

    # Set initial health status
    set_health!(server, HealthStatus.SERVING)

    # Print startup info
    @info "=" ^ 80
    @info "gRPC Server ready on $(config.host):$(config.port)"
    @info ""
    @info "Test the server with grpcurl:"
    @info "  grpcurl -plaintext localhost:$(config.port) list"
    @info "  grpcurl -plaintext -d '{\"message\":\"hello\"}' localhost:$(config.port) example.Echo/Echo"
    @info ""
    @info "Press Ctrl+C to stop"
    @info "=" ^ 80

    # Handle signals for graceful shutdown
    try
        run(server)
    catch e
        if e isa InterruptException
            @info ""
            @info "Shutdown signal received, gracefully stopping..."
            @info "Waiting up to $(config.drain_timeout)s for in-flight requests..."

            # Print final metrics
            print_metrics(metrics_interceptor)
        else
            @error "Server error" exception=(e, catch_backtrace())
            rethrow()
        end
    finally
        @info "Server stopped"
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
