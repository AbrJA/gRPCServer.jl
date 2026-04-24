# ==============================================================================
# Advanced TLS/mTLS Example
# ==============================================================================
# This example demonstrates how to set up a secure gRPC server with:
# - TLS encryption (HTTPS for gRPC)
# - mTLS (mutual TLS with client certificate verification)
# - Custom CA configuration
# - Certificate pinning patterns
#
# Prerequisites:
#   - Server certificate and key (cert.pem, key.pem)
#   - Client certificate and key for mTLS (client_cert.pem, client_key.pem)
#   - CA certificate (ca.pem)
#
# Generate test certificates:
#   # Server cert
#   openssl req -x509 -newkey rsa:4096 -keyout key.pem -out cert.pem -days 365 -nodes
#
#   # Client cert for mTLS
#   openssl req -x509 -newkey rsa:4096 -keyout client_key.pem -out client_cert.pem -days 365 -nodes
#
#   # Self-signed CA
#   openssl req -x509 -newkey rsa:4096 -keyout ca_key.pem -out ca.pem -days 365 -nodes

using gRPCServer
using Logging

# Message types
struct SecureRequest
    message::String
end

struct SecureReply
    message::String
    secure_transport::Bool
end

# Service
struct SecureService end

# Handler
function secure_handler(ctx::ServerContext, request::SecureRequest)::SecureReply
    @info "Secure request received" message=request.message
    return SecureReply(
        "Secure: $(request.message)",
        true  # Indicates TLS is active
    )
end

# Service descriptor
function gRPCServer.service_descriptor(::SecureService)
    ServiceDescriptor(
        "secure.Service",
        Dict(
            "Call" => MethodDescriptor(
                "Call", MethodType.UNARY,
                SecureRequest, SecureReply,
                secure_handler
            )
        ),
        nothing
    )
end

# ==============================================================================
# Main Server with TLS
# ==============================================================================

function main()
    @info "Secure gRPC Server Example (TLS/mTLS)"
    @info "=" ^ 80
    
    # Configuration from environment
    enable_mtls = parse(Bool, get(ENV, "ENABLE_MTLS", "false"))
    cert_path = get(ENV, "TLS_CERT", "cert.pem")
    key_path = get(ENV, "TLS_KEY", "key.pem")
    ca_path = get(ENV, "TLS_CA", "ca.pem")
    
    # Verify certificate files exist
    for file in [cert_path, key_path]
        if !isfile(file)
            @error "Certificate file not found: $file"
            @info "Generate test certificates with:"
            @info "  openssl req -x509 -newkey rsa:4096 -keyout key.pem -out cert.pem -days 365 -nodes"
            return
        end
    end
    
    if enable_mtls && !isfile(ca_path)
        @error "CA certificate file not found: $ca_path (required for mTLS)"
        return
    end
    
    # Create TLS configuration
    tls_config = TLSConfig(
        cert_chain=cert_path,
        private_key=key_path,
        client_ca=enable_mtls ? ca_path : nothing,
        require_client_cert=enable_mtls,
        min_version=:TLSv1_2,
        alpn_protocols=["h2"]
    )
    
    @info "TLS Configuration:"
    @info "  Cert:          $cert_path"
    @info "  Key:           $key_path"
    @info "  mTLS:          $(enable_mtls ? "enabled" : "disabled")"
    if enable_mtls
        @info "  CA Cert:       $ca_path"
        @info "  Require Certs: yes"
    end
    @info ""
    
    # Create server with TLS
    server = GRPCServer(
        "0.0.0.0", 50051;
        tls=tls_config,
        enable_health_check=true,
        enable_reflection=true
    )
    
    register!(server, SecureService())
    
    @info "=" ^ 80
    @info "Secure server started on 0.0.0.0:50051 (TLS enabled)"
    @info ""
    @info "Test with grpcurl:"
    if enable_mtls
        @info "  grpcurl -cacert ca.pem -cert client_cert.pem -key client_key.pem \\"
        @info "    -d '{\"message\":\"hello\"}' localhost:50051 secure.Service/Call"
    else
        @info "  grpcurl -insecure \\"
        @info "    -d '{\"message\":\"hello\"}' localhost:50051 secure.Service/Call"
    end
    @info ""
    @info "Press Ctrl+C to stop"
    @info "=" ^ 80
    
    run(server)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
