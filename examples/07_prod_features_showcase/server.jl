# ==============================================================================
# Feature Showcase Server
# ==============================================================================
# This server demonstrates all key features of gRPCServer.jl:
# - Multiple services with different RPC patterns
# - Custom interceptors for logging, metrics, and rate limiting
# - Health checking and reflection services
# - Comprehensive configuration management
# - Backend selection (PureHTTP2 vs Nghttp2)
# - Graceful shutdown with metrics reporting

using gRPCServer
using Logging

include("config.jl")
include("services.jl")
include("interceptors.jl")

# ==============================================================================
# Main Server Implementation
# ==============================================================================

function main()
    # Configure logging
    global_logger(ConsoleLogger(stderr, Logging.Info))
    
    @info "=" ^ 80
    @info "gRPCServer Feature Showcase"
    @info "=" ^ 80
    
    # Load configuration
    config = load_showcase_config()
    print_showcase_config(config)
    @info ""
    
    # Select HTTP/2 backend
    local backend
    if config.backend == :nghttp2
        try
            @eval using Nghttp2Wrapper
            backend = gRPCServer.Nghttp2Backend()
            @info "Backend: Nghttp2Backend (high-performance C-based)"
        catch e
            @warn "Nghttp2Wrapper not available, falling back to PureHTTP2Backend" exception=e
            backend = gRPCServer.PureHTTP2Backend()
        end
    else
        backend = gRPCServer.PureHTTP2Backend()
        @info "Backend: PureHTTP2Backend (pure Julia implementation)"
    end
    @info ""
    
    # Create server
    @info "Creating gRPC server..."
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
    
    # Setup interceptors
    @info "Setting up interceptors..."
    local metrics_interceptor = nothing
    
    if config.enable_metrics
        metrics_interceptor = MetricsInterceptor()
        add_interceptor!(server, metrics_interceptor)
        @info "  ✓ Metrics interceptor"
    end
    
    if config.enable_rate_limiting
        add_interceptor!(server, RateLimitingInterceptor(config.max_requests_per_second))
        @info "  ✓ Rate limiting interceptor"
    end
    
    add_interceptor!(server, HeaderPropagationInterceptor())
    @info "  ✓ Header propagation interceptor"
    
    if config.enable_logging
        add_interceptor!(server, LoggingInterceptor())
        @info "  ✓ Logging interceptor"
    end
    
    # Register services
    @info "Registering services..."
    register!(server, EchoService())
    @info "  ✓ Echo service (unary RPC)"
    
    register!(server, MathService())
    @info "  ✓ Math service (multiple unary methods)"
    
    register!(server, StreamService())
    @info "  ✓ Stream service (server streaming)"
    
    register!(server, ChatService())
    @info "  ✓ Chat service (bidirectional streaming)"
    
    # Display registered services
    @info ""
    @info "Registered services:"
    for service_name in keys(server.dispatcher.registry.services)
        @info "  • $service_name"
    end
    
    # Set initial health status
    set_health!(server, HealthStatus.SERVING)
    
    # Display connection info
    @info ""
    @info "=" ^ 80
    @info "Server ready at $(config.host):$(config.port)"
    @info "=" ^ 80
    @info ""
    @info "Test the server:"
    @info ""
    @info "1. List services:"
    @info "   grpcurl -plaintext localhost:$(config.port) list"
    @info ""
    @info "2. Call Echo service:"
    @info "   grpcurl -plaintext -d '{\"message\":\"Hello\",\"delay_ms\":0}' \\"
    @info "     localhost:$(config.port) showcase.Echo/Echo"
    @info ""
    @info "3. Call Math service:"
    @info "   grpcurl -plaintext -d '{\"operand_a\":10,\"operand_b\":5}' \\"
    @info "     localhost:$(config.port) showcase.Math/Add"
    @info ""
    @info "4. Server streaming:"
    @info "   grpcurl -plaintext -d '{\"count\":5,\"delay_ms\":100}' \\"
    @info "     localhost:$(config.port) showcase.Stream/CountStream"
    @info ""
    @info "Press Ctrl+C to stop the server"
    @info "=" ^ 80
    @info ""
    
    # Start server
    try
        run(server)
    catch e
        if e isa InterruptException
            @info ""
            @info "Shutdown signal received"
            @info "Waiting up to $(config.drain_timeout)s for in-flight requests to complete..."
            
            # Print final metrics
            if metrics_interceptor !== nothing
                @info ""
                print_metrics(metrics_interceptor)
            end
        else
            @error "Server error" exception=(e, catch_backtrace())
            rethrow()
        end
    finally
        @info ""
        @info "Server stopped"
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
