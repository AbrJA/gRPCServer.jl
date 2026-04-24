# Feature Showcase Example for gRPCServer.jl

This directory contains a production-grade example that showcases all major features of gRPCServer.jl.

## Features Demonstrated

### 1. **Multiple RPC Patterns**
- Unary RPC (request-response)
- Server streaming (one request, multiple responses)
- Client streaming (multiple requests, one response)
- Bidirectional streaming (multiple requests and responses)

### 2. **Service Management**
- Multiple services in a single server
- Service discovery via reflection
- Health checking service
- Dynamic service registration

### 3. **Protocol & Messaging**
- Protocol buffer message serialization
- Message compression (gzip, deflate)
- Custom metadata/headers
- Request context and cancellation

### 4. **Interceptors & Middleware**
- Logging interceptors
- Metrics collection
- Error recovery
- Request/response modification

### 5. **Server Configuration**
- Connection limits
- Stream limits
- Message size limits
- Timeout configuration
- Keepalive settings

### 6. **HTTP/2 Backends**
- PureHTTP2Backend (pure Julia)
- Nghttp2Backend (C-based, high-performance)
- Seamless backend switching

### 7. **Security**
- TLS/SSL support
- mTLS (mutual TLS)
- Client certificate verification
- Custom CA configuration

### 8. **Operations**
- Health status management
- Server reflection API
- Request ID tracking
- Comprehensive logging
- Graceful shutdown

## Running the Example

```bash
# Start the server
julia server.jl

# In another terminal, test with grpcurl
grpcurl -plaintext localhost:50051 list
grpcurl -plaintext -d '{"message":"hello"}' localhost:50051 showcase.Echo/Echo

# Or use the included client
julia client.jl
```

## Environment Variables

Configure the server with environment variables:

```bash
# Backend selection
GRPC_BACKEND=pure        # or "nghttp2"

# Network configuration
GRPC_HOST=0.0.0.0
GRPC_PORT=50051

# Limits
GRPC_MAX_CONNECTIONS=10000
GRPC_MAX_STREAMS=200
GRPC_MAX_MESSAGE_SIZE=4194304

# Timeouts
GRPC_KEEPALIVE_INTERVAL=60.0
GRPC_IDLE_TIMEOUT=300.0

# Features
GRPC_HEALTH_CHECK=true
GRPC_REFLECTION=true
GRPC_COMPRESSION=true
GRPC_DEBUG=false

# TLS
GRPC_TLS_ENABLED=false
GRPC_TLS_CERT=/path/to/cert.pem
GRPC_TLS_KEY=/path/to/key.pem
```

## Files

- `server.jl` - Production server with all features
- `client.jl` - Test client demonstrating all RPC patterns
- `services.jl` - Service definitions and handlers
- `interceptors.jl` - Custom interceptor implementations
- `config.jl` - Configuration utilities

## Notes

- The Echo service is ideal for health checks and latency testing
- The Math service demonstrates unary RPC with multiple methods
- The Stream service shows streaming capabilities
- All services include comprehensive logging and metrics
