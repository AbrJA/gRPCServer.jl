# Example: Initializing gRPCServer with different HTTP/2 backends

using gRPCServer

# By default, gRPCServer uses the PureHTTP2Backend
println("Creating server with default backend...")
default_server = GRPCServer("127.0.0.1", 50051)
println("Default server backend type: ", typeof(default_server.http2_backend))

# We can explicitly pass the backend if desired
println("\nCreating server with explicit PureHTTP2Backend...")
pure_backend = PureHTTP2Backend()
pure_server = GRPCServer("127.0.0.1", 50052; http2_backend=pure_backend)
println("PureHTTP2 server backend type: ", typeof(pure_server.http2_backend))

# To use the Nghttp2Wrapper backend, it must be loaded in the environment
println("\nSetting up Nghttp2Backend (Requires Nghttp2Wrapper to be loaded)...")
try
    # In a real environment with Nghttp2Wrapper installed, you would do:
    # using Nghttp2Wrapper
    
    ng_backend = Nghttp2Backend()
    ng_server = GRPCServer("127.0.0.1", 50053; http2_backend=ng_backend)
    println("Nghttp2 server backend type: ", typeof(ng_server.http2_backend))
catch e
    println("Could not initialize Nghttp2Backend. Is Nghttp2Wrapper loaded?")
    println("Error: ", e)
end

println("\nAll servers initialized successfully!")
