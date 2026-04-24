# ==============================================================================
# gRPC Server with Nghttp2Backend
# ==============================================================================
# This example demonstrates a gRPC server using the Nghttp2Backend.
# Nghttp2 is a C-based implementation optimized for high performance.
#
# Prerequisites: Nghttp2Wrapper.jl must be installed in the environment

using gRPCServer
using Logging

include("server_config.jl")

function main()
    host = "127.0.0.1"
    port = NGHTTP2_BACKEND_PORT
    
    # Verify Nghttp2Wrapper is available
    try
        @eval using Nghttp2Wrapper
    catch e
        @error "Nghttp2Wrapper is not installed" exception=e
        @info "To use Nghttp2Backend, install Nghttp2Wrapper:"
        @info "  using Pkg"
        @info "  Pkg.add(\"Nghttp2Wrapper\")"
        return
    end
    
    # Create server with Nghttp2Backend
    server = create_server(host, port, :nghttp2)
    
    @info "=" ^80
    @info "gRPC Server with Nghttp2Backend"
    @info "=" ^80
    @info "Starting server" host=host port=port
    @info "Backend: Nghttp2 (C-based, high-performance)"
    @info ""
    @info "Features enabled:"
    @info "  - Health checking service"
    @info "  - Reflection service"
    @info "  - Compression support (gzip, deflate)"
    @info "  - Request logging"
    @info ""
    @info "Performance characteristics:"
    @info "  - Lower latency than PureHTTP2"
    @info "  - Better for high-throughput scenarios"
    @info "  - Optimized for >1000 concurrent connections"
    @info ""
    @info "Test with grpcurl:"
    @info "  grpcurl -plaintext localhost:$port list"
    @info "  grpcurl -plaintext -d '{\"name\":\"hello\"}' localhost:$port helloworld.Echo/Echo"
    @info ""
    @info "Press Ctrl+C to stop the server"
    @info "=" ^80
    
    try
        run(server)
    catch e
        if e isa InterruptException
            @info "Server stopped by user"
        else
            @error "Server error" exception=(e, catch_backtrace())
        end
    end
end

main()
