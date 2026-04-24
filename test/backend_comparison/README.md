# Backend Comparison Tests

This directory contains tests for comparing and validating both HTTP/2 backends
(PureHTTP2Backend and Nghttp2Backend) in gRPCServer.jl.

## Test Files

### test_backends.jl
Basic backend functionality tests:
- Server creation with both backends
- Service registration
- Built-in service availability (Health, Reflection)
- Backend type verification

### test_features.jl
Feature parity tests ensuring both backends support:
- Compression (GZIP, DEFLATE)
- Health check service
- Reflection service
- Message size limits
- Connection limits
- Timeout configuration

## Running the Tests

From the project root:

```bash
julia test/backend_comparison/test_backends.jl
julia test/backend_comparison/test_features.jl
```

Or run all tests including backend comparison:

```bash
julia test/runtests.jl
```

## Test Configuration

Tests use high port numbers (60000+) to avoid conflicts:
- PureHTTP2Backend tests: 60001, 60003, 60005, etc.
- Nghttp2Backend tests: 60002, 60004, 60006, etc.

## Notes

- Tests that require Nghttp2Wrapper will be skipped if the package is not installed
- Each test creates fresh server instances to avoid state pollution
- Tests are designed to be independent and can run in any order
