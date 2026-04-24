# ==============================================================================
# Custom Interceptor Implementations
# ==============================================================================

using gRPCServer
using Logging
using Statistics

"""
    LoggingInterceptor

Logs incoming RPC calls with timing and result information.
"""
struct LoggingInterceptor <: gRPCServer.Interceptor
    enabled::Bool
end

LoggingInterceptor() = LoggingInterceptor(true)

function (interceptor::LoggingInterceptor)(ctx::ServerContext, request, info::MethodInfo, next::Function)
    if !interceptor.enabled
        return next(ctx, request)
    end

    start_time = time()
    @info "RPC start" service=info.service_name method=info.method_name request_id=ctx.request_id

    try
        result = next(ctx, request)
        elapsed = (time() - start_time) * 1000
        @info "RPC success" service=info.service_name method=info.method_name elapsed_ms=round(elapsed; digits=2) request_id=ctx.request_id
        return result
    catch e
        elapsed = (time() - start_time) * 1000
        @error "RPC error" service=info.service_name method=info.method_name elapsed_ms=round(elapsed; digits=2) exception=e request_id=ctx.request_id
        rethrow()
    end
end

"""
    MetricsInterceptor

Collects performance metrics about RPC calls.
"""
mutable struct MetricsInterceptor <: gRPCServer.Interceptor
    total_requests::Int
    total_errors::Int
    latencies::Vector{Float64}
    by_method::Dict{String, Dict{String, Any}}
    lock::ReentrantLock
end

function MetricsInterceptor()
    MetricsInterceptor(0, 0, Float64[], Dict{String, Dict{String, Any}}(), ReentrantLock())
end

function (interceptor::MetricsInterceptor)(ctx::ServerContext, request, info::MethodInfo, next::Function)
    start_time = time()

    try
        result = next(ctx, request)
        elapsed = (time() - start_time) * 1000

        lock(interceptor.lock) do
            interceptor.total_requests += 1
            push!(interceptor.latencies, elapsed)

            # Track by method
            method_key = "$(info.service_name)/$(info.method_name)"
            if !haskey(interceptor.by_method, method_key)
                interceptor.by_method[method_key] = Dict(
                    "count" => 0,
                    "errors" => 0,
                    "latencies" => Float64[]
                )
            end
            interceptor.by_method[method_key]["count"] += 1
            push!(interceptor.by_method[method_key]["latencies"], elapsed)

            # Limit stored latencies
            if length(interceptor.latencies) > 10000
                interceptor.latencies = interceptor.latencies[end-9999:end]
            end
        end

        return result
    catch e
        elapsed = (time() - start_time) * 1000

        lock(interceptor.lock) do
            interceptor.total_requests += 1
            interceptor.total_errors += 1

            # Track error by method
            method_key = "$(info.service_name)/$(info.method_name)"
            if !haskey(interceptor.by_method, method_key)
                interceptor.by_method[method_key] = Dict(
                    "count" => 0,
                    "errors" => 0,
                    "latencies" => Float64[]
                )
            end
            interceptor.by_method[method_key]["count"] += 1
            interceptor.by_method[method_key]["errors"] += 1
            push!(interceptor.by_method[method_key]["latencies"], elapsed)
        end

        rethrow()
    end
end

function print_metrics(metrics::MetricsInterceptor)
    lock(metrics.lock) do
        @info "Metrics Summary"
        @info "  Total Requests: $(metrics.total_requests)"
        @info "  Total Errors:   $(metrics.total_errors)"

        if !isempty(metrics.latencies)
            @info "  Latency Statistics (ms):"
            @info "    Min:       $(round(minimum(metrics.latencies); digits=2))"
            @info "    Max:       $(round(maximum(metrics.latencies); digits=2))"
            @info "    Mean:      $(round(mean(metrics.latencies); digits=2))"
            @info "    p95:       $(round(quantile(metrics.latencies, 0.95); digits=2))"
            @info "    p99:       $(round(quantile(metrics.latencies, 0.99); digits=2))"
        end

        @info "  Per-Method Statistics:"
        for (method, stats) in metrics.by_method
            error_rate = stats["count"] > 0 ? stats["errors"] / stats["count"] * 100 : 0
            if !isempty(stats["latencies"])
                mean_lat = mean(stats["latencies"])
                @info "    $method"
                @info "      Requests: $(stats["count"]), Errors: $(stats["errors"]) ($(round(error_rate; digits=1))%)"
                @info "      Avg Latency: $(round(mean_lat; digits=2)) ms"
            end
        end
    end
end

"""
    RateLimitingInterceptor

Simple rate limiting based on requests per second.
"""
mutable struct RateLimitingInterceptor <: gRPCServer.Interceptor
    max_requests_per_second::Int
    requests_in_window::Int
    window_start::Float64
    lock::ReentrantLock
end

function RateLimitingInterceptor(max_rps::Int=1000)
    RateLimitingInterceptor(max_rps, 0, time(), ReentrantLock())
end

function (interceptor::RateLimitingInterceptor)(ctx::ServerContext, request, info::MethodInfo, next::Function)
    lock(interceptor.lock) do
        now = time()
        window_elapsed = now - interceptor.window_start

        # Reset window if > 1 second
        if window_elapsed > 1.0
            interceptor.requests_in_window = 0
            interceptor.window_start = now
        end

        # Check rate limit
        if interceptor.requests_in_window >= interceptor.max_requests_per_second
            @warn "Rate limit exceeded" current_rps=interceptor.requests_in_window request_id=ctx.request_id
            throw(GRPCError(StatusCode.RESOURCE_EXHAUSTED, "Rate limit exceeded"))
        end

        interceptor.requests_in_window += 1
    end

    return next(ctx, request)
end

"""
    HeaderPropagationInterceptor

Demonstrates how to extract and work with metadata/headers.
"""
struct HeaderPropagationInterceptor <: gRPCServer.Interceptor end

function (::HeaderPropagationInterceptor)(ctx::ServerContext, request, info::MethodInfo, next::Function)
    # Extract custom headers if present
    request_id = get_metadata(ctx, "x-request-id")
    user_agent = get_metadata(ctx, "user-agent")
    authorization = get_metadata(ctx, "authorization")

    if request_id !== nothing
        @debug "Custom request ID from client" request_id=request_id
    end
    if user_agent !== nothing
        @debug "User agent" user_agent=user_agent
    end
    if authorization !== nothing
        @debug "Authorization header present"
    end

    result = next(ctx, request)

    # Could set response headers here if needed
    # set_header!(ctx, "x-response-time", string(time()))

    return result
end
