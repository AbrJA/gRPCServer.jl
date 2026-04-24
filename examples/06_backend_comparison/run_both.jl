# ==============================================================================
# Run Both Backends Simultaneously for Comparison
# ==============================================================================
# This script starts servers with both PureHTTP2Backend and Nghttp2Backend
# side by side, allowing you to test and compare them in parallel.

using gRPCServer
using Logging
using Base.Threads

include("server_config.jl")

function main()
    println()
    println("=" ^80)
    println("gRPCServer Backend Comparison - Running Both Backends")
    println("=" ^80)
    println()
    
    # Create both servers
    @info "Creating servers..."
    pure_server = create_server("127.0.0.1", PURE_BACKEND_PORT, :pure)
    
    nghttp2_available = true
    nghttp2_server = nothing
    try
        @eval using Nghttp2Wrapper
        nghttp2_server = create_server("127.0.0.1", NGHTTP2_BACKEND_PORT, :nghttp2)
    catch e
        @warn "Nghttp2Backend not available" exception=e
        nghttp2_available = false
    end
    
    println()
    println("=" ^80)
    println("Server Configuration")
    println("=" ^80)
    println("PureHTTP2Backend:  127.0.0.1:$(PURE_BACKEND_PORT)")
    if nghttp2_available
        println("Nghttp2Backend:    127.0.0.1:$(NGHTTP2_BACKEND_PORT)")
    else
        println("Nghttp2Backend:    NOT AVAILABLE (install Nghttp2Wrapper to enable)")
    end
    println()
    println("Testing with grpcurl:")
    println()
    println("PureHTTP2 Backend:")
    println("  grpcurl -plaintext localhost:$(PURE_BACKEND_PORT) list")
    println("  grpcurl -plaintext -d '{\"name\":\"test\"}' \\")
    println("    localhost:$(PURE_BACKEND_PORT) helloworld.Echo/Echo")
    println()
    if nghttp2_available
        println("Nghttp2 Backend:")
        println("  grpcurl -plaintext localhost:$(NGHTTP2_BACKEND_PORT) list")
        println("  grpcurl -plaintext -d '{\"name\":\"test\"}' \\")
        println("    localhost:$(NGHTTP2_BACKEND_PORT) helloworld.Echo/Echo")
        println()
    end
    println("=" ^80)
    println("Press Ctrl+C to stop all servers")
    println("=" ^80)
    println()
    
    # Start servers in separate tasks
    @info "Starting servers..."
    pure_task = @async run(pure_server)
    
    nghttp2_task = nothing
    if nghttp2_available
        nghttp2_task = @async run(nghttp2_server)
    end
    
    # Keep running until interrupted
    try
        while true
            sleep(1)
        end
    catch e
        if e isa InterruptException
            @info "Shutting down servers..."
        else
            @error "Unexpected error" exception=(e, catch_backtrace())
        end
    end
end

main()
