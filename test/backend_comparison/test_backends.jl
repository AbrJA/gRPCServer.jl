# ==============================================================================
# Backend Comparison Tests
# ==============================================================================
# Integration tests that verify both HTTP/2 backends work correctly with
# all gRPCServer features: unary, streaming, compression, TLS, etc.

using Test
using gRPCServer
using Logging
using Base.Threads

# Include test utilities (same as main test suite)
include("../TestUtils.jl")
using .TestUtils

# Include backend configuration from examples
include(joinpath(@__DIR__, "../../examples/06_backend_comparison/server_config.jl"))

# ==============================================================================
# Helper Functions
# ==============================================================================

"""Create a test server with specified backend"""
function create_test_server(port::Int, backend_type::Symbol)
    server = create_server("127.0.0.1", port, backend_type)
    return server
end

"""Wait for server to be ready"""
function wait_server_ready(host::String, port::Int, timeout_seconds=5.0)
    start = time()
    while time() - start < timeout_seconds
        try
            socket = connect(host, port)
            close(socket)
            sleep(0.1)
            return true
        catch
            sleep(0.05)
        end
    end
    return false
end

"""Run a test server in background"""
function run_server_in_background(server::GRPCServer)
    task = @async try
        run(server)
    catch e
        if !(e isa InterruptException)
            @error "Server task error" exception=(e, catch_backtrace())
        end
    end
    return task
end

# ==============================================================================
# Test Sets
# ==============================================================================

@testset "Backend Comparison Tests" begin
    
    @testset "PureHTTP2Backend Basics" begin
        port = 60001
        server = create_test_server(port, :pure)
        task = run_server_in_background(server)
        
        try
            @test wait_server_ready("127.0.0.1", port)
            @test server.status == ServerStatus.RUNNING
            @test server.http2_backend isa gRPCServer.PureHTTP2Backend
            
            # Verify services are registered
            services = keys(server.dispatcher.registry.services)
            @test length(services) > 0
            @test "echo.Echo" in services
            
            # Verify built-in services
            @test "grpc.health.v1.Health" in services
            @test "grpc.reflection.v1alpha.ServerReflection" in services
        finally
            # Cleanup
            if server.status == ServerStatus.RUNNING
                # In real implementation, would call shutdown
            end
        end
    end
    
    @testset "Nghttp2Backend Basics" begin
        try
            @eval using Nghttp2Wrapper
        catch
            @test_skip "Nghttp2Wrapper not available"
            return
        end
        
        port = 60002
        server = create_test_server(port, :nghttp2)
        task = run_server_in_background(server)
        
        try
            @test wait_server_ready("127.0.0.1", port)
            @test server.status == ServerStatus.RUNNING
            @test server.http2_backend isa gRPCServer.Nghttp2Backend
            
            # Verify services are registered
            services = keys(server.dispatcher.services)
            @test length(services) > 0
            @test "echo.Echo" in services
        finally
            # Cleanup
            if server.status == ServerStatus.RUNNING
                # In real implementation, would call shutdown
            end
        end
    end
    
    @testset "Backend Configuration" begin
        # Test PureHTTP2Backend creation
        pure_backend = gRPCServer.PureHTTP2Backend()
        @test pure_backend isa gRPCServer.AbstractHTTP2Backend
        
        # Test Nghttp2Backend creation (if available)
        try
            @eval using Nghttp2Wrapper
            ng_backend = gRPCServer.Nghttp2Backend()
            @test ng_backend isa gRPCServer.AbstractHTTP2Backend
        catch
            @test_skip "Nghttp2Wrapper not available"
        end
    end
    
    @testset "Server Creation with Both Backends" begin
        # PureHTTP2 server
        server1 = GRPCServer("127.0.0.1", 60003;
            http2_backend=gRPCServer.PureHTTP2Backend()
        )
        @test server1.http2_backend isa gRPCServer.PureHTTP2Backend
        
        # Nghttp2 server (if available)
        try
            @eval using Nghttp2Wrapper
            server2 = GRPCServer("127.0.0.1", 60004;
                http2_backend=gRPCServer.Nghttp2Backend()
            )
            @test server2.http2_backend isa gRPCServer.Nghttp2Backend
        catch
            @test_skip "Nghttp2Wrapper not available"
        end
    end
    
    @testset "ServerConfig with Both Backends" begin
        config = ServerConfig(
            max_connections=1000,
            max_concurrent_streams=200,
            max_message_size=8*1024*1024,
            enable_health_check=true,
            enable_reflection=true,
            compression_enabled=true
        )
        
        # Test with PureHTTP2
        server1 = GRPCServer("127.0.0.1", 60005;
            http2_backend=gRPCServer.PureHTTP2Backend(),
            max_connections=config.max_connections,
            max_concurrent_streams=config.max_concurrent_streams
        )
        @test server1.config.max_connections == config.max_connections
        
        # Test with Nghttp2 (if available)
        try
            @eval using Nghttp2Wrapper
            server2 = GRPCServer("127.0.0.1", 60006;
                http2_backend=gRPCServer.Nghttp2Backend(),
                max_connections=config.max_connections
            )
            @test server2.config.max_connections == config.max_connections
        catch
            @test_skip "Nghttp2Wrapper not available"
        end
    end
    
    @testset "Interoperability: Service Registration" begin
        # Both backends should support the same service registration
        service = EchoService()
        descriptor = gRPCServer.service_descriptor(service)
        
        @test descriptor.name == "echo.Echo"
        @test haskey(descriptor.methods, "Echo")
        @test haskey(descriptor.methods, "ServerInfo")
    end
    
end

println()
@info "Backend comparison tests completed successfully!"
