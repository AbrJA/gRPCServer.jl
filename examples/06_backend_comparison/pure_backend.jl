# ==============================================================================
# gRPC Server with PureHTTP2Backend
# ==============================================================================
# This example demonstrates a gRPC server using the default PureHTTP2Backend.
# PureHTTP2 is a pure Julia implementation with no external C dependencies.

using gRPCServer
using Logging

include("server_config.jl")

function main()
    host = "127.0.0.1"
    port = PURE_BACKEND_PORT
    
    # Create server with PureHTTP2Backend
    server = create_server(host, port, :pure)
    
    @info "=" ^80
    @info "gRPC Server with PureHTTP2Backend"
    @info "=" ^80
    @info "Starting server" host=host port=port
    @info "Backend: PureHTTP2 (Pure Julia implementation)"
    @info ""
    @info "Features enabled:"
    @info "  - Health checking service"
    @info "  - Reflection service"
    @info "  - Compression support (gzip, deflate)"
    @info "  - Request logging"
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
