# ==============================================================================
# Configuration Management for Feature Showcase
# ==============================================================================

using Logging

"""Load configuration from environment variables"""
function load_showcase_config()
    return (
        # Server address
        host = get(ENV, "GRPC_HOST", "0.0.0.0"),
        port = parse(Int, get(ENV, "GRPC_PORT", "50051")),
        
        # Backend selection
        backend = Symbol(get(ENV, "GRPC_BACKEND", "pure")),
        
        # Connection limits
        max_connections = parse(Int, get(ENV, "GRPC_MAX_CONNECTIONS", "10000")),
        max_concurrent_streams = parse(Int, get(ENV, "GRPC_MAX_STREAMS", "200")),
        max_message_size = parse(Int, get(ENV, "GRPC_MAX_MESSAGE_SIZE", "4194304")),
        
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
        
        # Interceptors
        enable_logging = parse(Bool, get(ENV, "GRPC_INTERCEPTOR_LOGGING", "true")),
        enable_metrics = parse(Bool, get(ENV, "GRPC_INTERCEPTOR_METRICS", "true")),
        enable_rate_limiting = parse(Bool, get(ENV, "GRPC_INTERCEPTOR_RATE_LIMIT", "false")),
        max_requests_per_second = parse(Int, get(ENV, "GRPC_MAX_RPS", "1000")),
    )
end

"""Print configuration to logs"""
function print_showcase_config(config)
    @info "Feature Showcase Configuration"
    @info "  Address:              $(config.host):$(config.port)"
    @info "  Backend:              $(config.backend)"
    @info "  Max Connections:      $(config.max_connections)"
    @info "  Max Streams/Conn:     $(config.max_concurrent_streams)"
    @info "  Max Message Size:     $(config.max_message_size / 1024 / 1024) MB"
    @info "  Keepalive Interval:   $(config.keepalive_interval)s"
    @info "  Idle Timeout:         $(config.idle_timeout)s"
    @info "  Drain Timeout:        $(config.drain_timeout)s"
    @info "  Health Check:         $(config.enable_health_check ? "enabled" : "disabled")"
    @info "  Reflection:           $(config.enable_reflection ? "enabled" : "disabled")"
    @info "  Compression:          $(config.enable_compression ? "enabled" : "disabled")"
    @info "  Debug Mode:           $(config.debug_mode ? "enabled" : "disabled")"
    @info "  Logging Interceptor:  $(config.enable_logging ? "enabled" : "disabled")"
    @info "  Metrics Interceptor:  $(config.enable_metrics ? "enabled" : "disabled")"
    @info "  Rate Limiting:        $(config.enable_rate_limiting ? "enabled" : "disabled")"
    if config.enable_rate_limiting
        @info "    Max RPS:            $(config.max_requests_per_second)"
    end
end
