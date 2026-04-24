# Backend Comparison Example

This example demonstrates how to run gRPC servers with different HTTP/2 backends and measure their performance characteristics.

## Overview

gRPCServer.jl supports two HTTP/2 backends:

1. **PureHTTP2Backend** (Default)
   - Pure Julia implementation
   - No external dependencies
   - Good for development and prototyping
   - Suitable for general-purpose gRPC servers

2. **Nghttp2Backend** (Optional)
   - C-based nghttp2 library via Nghttp2Wrapper.jl
   - Higher performance for high-throughput scenarios
   - Better for production deployments with strict performance requirements

## Files

- `server_config.jl` - Shared service definitions and configuration
- `pure_backend.jl` - Server using PureHTTP2Backend
- `nghttp2_backend.jl` - Server using Nghttp2Backend
- `benchmark.jl` - Benchmarking script to compare backend performance
- `run_both.jl` - Run both servers simultaneously for comparison

## Running the Examples

### Prerequisites

```bash
cd 06_backend_comparison

# For PureHTTP2 only (always available)
julia pure_backend.jl

# For both backends (requires Nghttp2Wrapper installed)
julia run_both.jl
```

### Benchmark

Run the benchmark script to compare performance:

```bash
julia benchmark.jl
```

This will:
- Start servers with both backends
- Send test requests
- Measure latency and throughput
- Compare memory usage
- Display results

## Performance Considerations

- **PureHTTP2**: ~1-5ms latency, suitable for <1000 concurrent connections
- **Nghttp2**: ~0.1-1ms latency, suitable for >1000 concurrent connections and high throughput

Choose based on your requirements:
- Development/Testing: Use PureHTTP2 (simpler setup)
- Production/HighLoad: Use Nghttp2 if you have strict latency requirements
