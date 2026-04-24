# ==============================================================================
# Backend Benchmarking and Comparison
# ==============================================================================
# This script runs both backends simultaneously and compares their performance
# on common metrics: latency, throughput, and resource usage.

using gRPCServer
using Logging
using Statistics
using Printf
using Sockets
using Base.Threads
using Dates

include("server_config.jl")

# ==============================================================================
# Simple gRPC Client for Testing
# ==============================================================================

struct SimpleGRPCClient
    host::String
    port::Int
    socket::Union{TCPSocket, Nothing}
end

function connect_client(host::String, port::Int)::SimpleGRPCClient
    try
        socket = connect(host, port)
        return SimpleGRPCClient(host, port, socket)
    catch e
        @warn "Failed to connect to $host:$port" exception=e
        return SimpleGRPCClient(host, port, nothing)
    end
end

function is_connected(client::SimpleGRPCClient)::Bool
    return client.socket !== nothing && isopen(client.socket)
end

function close_client(client::SimpleGRPCClient)
    if is_connected(client)
        close(client.socket)
    end
end

# ==============================================================================
# Benchmark Functions
# ==============================================================================

struct BenchmarkResult
    backend_name::String
    num_requests::Int
    successful_requests::Int
    failed_requests::Int
    min_latency_ms::Float64
    max_latency_ms::Float64
    mean_latency_ms::Float64
    median_latency_ms::Float64
    p95_latency_ms::Float64
    p99_latency_ms::Float64
    total_time_seconds::Float64
    requests_per_second::Float64
end

function benchmark_backend(backend_name::String, host::String, port::Int, 
                          num_requests::Int, concurrent::Int)::BenchmarkResult
    @info "Benchmarking $backend_name backend..." port=port
    
    # Give server time to start
    sleep(0.5)
    
    latencies = Float64[]
    successful = 0
    failed = 0
    
    # Simple connection test
    client = connect_client(host, port)
    if !is_connected(client)
        @warn "Could not connect to $backend_name backend on $host:$port"
        return BenchmarkResult(
            backend_name, num_requests, 0, num_requests, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0
        )
    end
    close_client(client)
    
    # Run benchmark
    start_time = time()
    
    # Simple sequential benchmark (can be enhanced with actual gRPC calls)
    for i in 1:num_requests
        request_start = time()
        try
            client = connect_client(host, port)
            if is_connected(client)
                close_client(client)
                latency_ms = (time() - request_start) * 1000
                push!(latencies, latency_ms)
                successful += 1
            else
                failed += 1
            end
        catch e
            failed += 1
        end
        
        # Show progress
        if mod(i, max(1, div(num_requests, 10))) == 0
            @info "  Progress: $i/$num_requests"
        end
    end
    
    total_time = time() - start_time
    
    # Calculate statistics
    if isempty(latencies)
        return BenchmarkResult(
            backend_name, num_requests, 0, num_requests, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, total_time, 0.0
        )
    end
    
    sort!(latencies)
    min_lat = minimum(latencies)
    max_lat = maximum(latencies)
    mean_lat = mean(latencies)
    median_lat = Statistics.median(latencies)
    p95_lat = quantile(latencies, 0.95)
    p99_lat = quantile(latencies, 0.99)
    rps = successful / total_time
    
    return BenchmarkResult(
        backend_name, num_requests, successful, failed,
        min_lat, max_lat, mean_lat, median_lat, p95_lat, p99_lat,
        total_time, rps
    )
end

function print_benchmark_result(result::BenchmarkResult)
    println()
    println("=" ^80)
    println("Benchmark Results: $(result.backend_name)")
    println("=" ^80)
    println(@sprintf "Total Requests:        %d", result.num_requests)
    println(@sprintf "Successful:            %d (%.1f%%)", result.successful_requests, 
            100.0 * result.successful_requests / result.num_requests)
    println(@sprintf "Failed:                %d", result.failed_requests)
    println()
    println("Latency Statistics (milliseconds):")
    println(@sprintf "  Min:                 %.2f ms", result.min_latency_ms)
    println(@sprintf "  Max:                 %.2f ms", result.max_latency_ms)
    println(@sprintf "  Mean:                %.2f ms", result.mean_latency_ms)
    println(@sprintf "  Median (p50):        %.2f ms", result.median_latency_ms)
    println(@sprintf "  p95:                 %.2f ms", result.p95_latency_ms)
    println(@sprintf "  p99:                 %.2f ms", result.p99_latency_ms)
    println()
    println(@sprintf "Throughput:            %.0f requests/sec", result.requests_per_second)
    println(@sprintf "Total Time:            %.2f seconds", result.total_time_seconds)
    println("=" ^80)
end

function compare_results(pure_result::BenchmarkResult, nghttp2_result::BenchmarkResult)
    println()
    println("=" ^80)
    println("Comparison: PureHTTP2 vs Nghttp2")
    println("=" ^80)
    
    # Calculate improvements
    latency_improvement = (pure_result.mean_latency_ms - nghttp2_result.mean_latency_ms) / 
                         pure_result.mean_latency_ms * 100
    throughput_improvement = (nghttp2_result.requests_per_second - pure_result.requests_per_second) / 
                            pure_result.requests_per_second * 100
    
    println()
    println("Latency Improvement (Nghttp2 vs PureHTTP2):")
    println(@sprintf "  Mean Latency:        %.1f%% %s", 
            abs(latency_improvement), 
            latency_improvement > 0 ? "faster ✓" : "slower ✗")
    println(@sprintf "  p95 Latency:         PureHTTP2: %.2f ms, Nghttp2: %.2f ms",
            pure_result.p95_latency_ms, nghttp2_result.p95_latency_ms)
    println(@sprintf "  p99 Latency:         PureHTTP2: %.2f ms, Nghttp2: %.2f ms",
            pure_result.p99_latency_ms, nghttp2_result.p99_latency_ms)
    
    println()
    println("Throughput Improvement (Nghttp2 vs PureHTTP2):")
    println(@sprintf "  Requests/sec:        %.1f%% %s", 
            abs(throughput_improvement),
            throughput_improvement > 0 ? "faster ✓" : "slower ✗")
    println(@sprintf "  PureHTTP2:           %.0f req/s", pure_result.requests_per_second)
    println(@sprintf "  Nghttp2:             %.0f req/s", nghttp2_result.requests_per_second)
    
    println()
    println("Recommendations:")
    if latency_improvement > 5
        println("  • Nghttp2 has significantly better latency")
        println("  • Consider Nghttp2 for latency-sensitive applications")
    elseif latency_improvement < -5
        println("  • PureHTTP2 has comparable or better latency")
    else
        println("  • Both backends have similar latency profiles")
    end
    
    println()
    println("=" ^80)
end

# ==============================================================================
# Main Benchmark Runner
# ==============================================================================

function main()
    @info "gRPCServer Backend Benchmarking Tool"
    @info "=" ^80
    
    # Configuration
    num_requests = get(ENV, "BENCHMARK_REQUESTS", "100") |> x -> parse(Int, x)
    concurrent = get(ENV, "BENCHMARK_CONCURRENT", "10") |> x -> parse(Int, x)
    
    @info "Configuration" num_requests=num_requests concurrent=concurrent
    @info ""
    
    # Start Pure Backend Server in background
    @info "Starting PureHTTP2Backend server on port $(PURE_BACKEND_PORT)..."
    pure_server = create_server("127.0.0.1", PURE_BACKEND_PORT, :pure)
    pure_task = @async run(pure_server)
    
    # Try to start Nghttp2 Backend Server
    @info "Starting Nghttp2Backend server on port $(NGHTTP2_BACKEND_PORT)..."
    nghttp2_server = nothing
    nghttp2_task = nothing
    
    try
        @eval using Nghttp2Wrapper
        nghttp2_server = create_server("127.0.0.1", NGHTTP2_BACKEND_PORT, :nghttp2)
        nghttp2_task = @async run(nghttp2_server)
    catch e
        @warn "Nghttp2Wrapper not available, benchmarking PureHTTP2 only" exception=e
    end
    
    @info "Waiting for servers to start..."
    sleep(2.0)
    
    # Run benchmarks
    @info "=" ^80
    @info "Running benchmarks..."
    @info "=" ^80
    
    pure_result = benchmark_backend(
        "PureHTTP2", "127.0.0.1", PURE_BACKEND_PORT, num_requests, concurrent
    )
    
    nghttp2_result = if nghttp2_server !== nothing
        benchmark_backend(
            "Nghttp2", "127.0.0.1", NGHTTP2_BACKEND_PORT, num_requests, concurrent
        )
    else
        nothing
    end
    
    # Print results
    print_benchmark_result(pure_result)
    
    if nghttp2_result !== nothing
        print_benchmark_result(nghttp2_result)
        compare_results(pure_result, nghttp2_result)
    end
    
    # Cleanup
    @info "Shutting down servers..."
    if pure_server !== nothing && pure_server.status == ServerStatus.RUNNING
        # In a real scenario, we'd call shutdown
        # For now, interrupt the task
    end
    
    @info "Benchmark complete!"
end

# Run only if executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
