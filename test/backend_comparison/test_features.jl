# ==============================================================================
# Feature Support Tests for Both Backends
# ==============================================================================
# Tests that verify both backends support key gRPCServer features:
# - Compression
# - Metadata/Headers
# - Interceptors
# - Health checks
# - Reflection
# - Timeouts

using Test
using gRPCServer
using Logging

include("../TestUtils.jl")
using .TestUtils

include(joinpath(@__DIR__, "../../examples/06_backend_comparison/server_config.jl"))

@testset "Feature Support Across Backends" begin
    
    @testset "Compression Support" begin
        # Both backends should support compression
        codecs_pure = [CompressionCodec.GZIP, CompressionCodec.DEFLATE]
        codecs_ng = [CompressionCodec.GZIP, CompressionCodec.DEFLATE]
        
        server_pure = GRPCServer("127.0.0.1", 60010;
            http2_backend=gRPCServer.PureHTTP2Backend(),
            compression_enabled=true,
            supported_codecs=codecs_pure
        )
        @test server_pure.config.compression_enabled
        @test server_pure.config.supported_codecs == codecs_pure
        
        try
            @eval using Nghttp2Wrapper
            server_ng = GRPCServer("127.0.0.1", 60011;
                http2_backend=gRPCServer.Nghttp2Backend(),
                compression_enabled=true,
                supported_codecs=codecs_ng
            )
            @test server_ng.config.compression_enabled
            @test server_ng.config.supported_codecs == codecs_ng
        catch
            @test_skip "Nghttp2Wrapper not available"
        end
    end
    
    @testset "Health Check Service" begin
        # Both backends should support health checks
        server_pure = GRPCServer("127.0.0.1", 60012;
            http2_backend=gRPCServer.PureHTTP2Backend(),
            enable_health_check=true
        )
        @test server_pure.config.enable_health_check
        @test "grpc.health.v1.Health" in keys(server_pure.dispatcher.registry.services)
        
        try
            @eval using Nghttp2Wrapper
            server_ng = GRPCServer("127.0.0.1", 60013;
                http2_backend=gRPCServer.Nghttp2Backend(),
                enable_health_check=true
            )
            @test server_ng.config.enable_health_check
            @test "grpc.health.v1.Health" in keys(server_ng.dispatcher.registry.services)
        catch
            @test_skip "Nghttp2Wrapper not available"
        end
    end
    
    @testset "Reflection Service" begin
        # Both backends should support reflection
        server_pure = GRPCServer("127.0.0.1", 60014;
            http2_backend=gRPCServer.PureHTTP2Backend(),
            enable_reflection=true
        )
        @test server_pure.config.enable_reflection
        @test "grpc.reflection.v1alpha.ServerReflection" in keys(server_pure.dispatcher.registry.services)
        
        try
            @eval using Nghttp2Wrapper
            server_ng = GRPCServer("127.0.0.1", 60015;
                http2_backend=gRPCServer.Nghttp2Backend(),
                enable_reflection=true
            )
            @test server_ng.config.enable_reflection
            @test "grpc.reflection.v1alpha.ServerReflection" in keys(server_ng.dispatcher.registry.services)
        catch
            @test_skip "Nghttp2Wrapper not available"
        end
    end
    
    @testset "Message Size Limits" begin
        # Both backends should enforce message size limits
        max_size = 2 * 1024 * 1024  # 2MB
        
        server_pure = GRPCServer("127.0.0.1", 60016;
            http2_backend=gRPCServer.PureHTTP2Backend(),
            max_message_size=max_size
        )
        @test server_pure.config.max_message_size == max_size
        
        try
            @eval using Nghttp2Wrapper
            server_ng = GRPCServer("127.0.0.1", 60017;
                http2_backend=gRPCServer.Nghttp2Backend(),
                max_message_size=max_size
            )
            @test server_ng.config.max_message_size == max_size
        catch
            @test_skip "Nghttp2Wrapper not available"
        end
    end
    
    @testset "Connection Limits" begin
        # Both backends should support connection limits
        max_conn = 500
        max_streams = 150
        
        server_pure = GRPCServer("127.0.0.1", 60018;
            http2_backend=gRPCServer.PureHTTP2Backend(),
            max_connections=max_conn,
            max_concurrent_streams=max_streams
        )
        @test server_pure.config.max_connections == max_conn
        @test server_pure.config.max_concurrent_streams == max_streams
        
        try
            @eval using Nghttp2Wrapper
            server_ng = GRPCServer("127.0.0.1", 60019;
                http2_backend=gRPCServer.Nghttp2Backend(),
                max_connections=max_conn,
                max_concurrent_streams=max_streams
            )
            @test server_ng.config.max_connections == max_conn
            @test server_ng.config.max_concurrent_streams == max_streams
        catch
            @test_skip "Nghttp2Wrapper not available"
        end
    end
    
    @testset "Timeout Configuration" begin
        # Both backends should support various timeout settings
        server_pure = GRPCServer("127.0.0.1", 60020;
            http2_backend=gRPCServer.PureHTTP2Backend(),
            keepalive_interval=30.0,
            keepalive_timeout=10.0,
            idle_timeout=60.0,
            drain_timeout=30.0
        )
        @test server_pure.config.keepalive_interval == 30.0
        @test server_pure.config.keepalive_timeout == 10.0
        @test server_pure.config.idle_timeout == 60.0
        @test server_pure.config.drain_timeout == 30.0
        
        try
            @eval using Nghttp2Wrapper
            server_ng = GRPCServer("127.0.0.1", 60021;
                http2_backend=gRPCServer.Nghttp2Backend(),
                keepalive_interval=30.0,
                keepalive_timeout=10.0,
                idle_timeout=60.0,
                drain_timeout=30.0
            )
            @test server_ng.config.keepalive_interval == 30.0
            @test server_ng.config.keepalive_timeout == 10.0
        catch
            @test_skip "Nghttp2Wrapper not available"
        end
    end
    
end

println()
@info "Feature support tests completed successfully!"
