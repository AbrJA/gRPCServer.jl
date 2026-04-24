# Method dispatch and service registration for gRPCServer.jl

using ProtoBuf
import ProtoBuf as PB

"""
    MethodDescriptor

Describes a single RPC method.

# Fields
- `name::String`: Method name (e.g., "SayHello")
- `method_type::MethodType.T`: RPC pattern type
- `input_type::String`: Fully-qualified request message type name
- `output_type::String`: Fully-qualified response message type name
- `handler::Function`: Handler function reference

# Handler Signatures by MethodType
- `UNARY`: `(ctx::ServerContext, request::T) -> R`
- `SERVER_STREAMING`: `(ctx::ServerContext, request::T, stream::ServerStream{R}) -> Nothing`
- `CLIENT_STREAMING`: `(ctx::ServerContext, stream::ClientStream{T}) -> R`
- `BIDI_STREAMING`: `(ctx::ServerContext, stream::BidiStream{T,R}) -> Nothing`

# Example
```julia
method = MethodDescriptor(
    "SayHello",
    MethodType.UNARY,
    "helloworld.HelloRequest",
    "helloworld.HelloReply",
    say_hello
)
```
"""
struct MethodDescriptor
    name::String
    method_type::MethodType.T
    input_type::String
    output_type::String
    handler::Function
    input_julia_type::Union{Type, Nothing}
    output_julia_type::Union{Type, Nothing}

    # Constructor with string type names (backward compatible)
    function MethodDescriptor(
        name::String,
        method_type::MethodType.T,
        input_type::String,
        output_type::String,
        handler::Function
    )
        new(name, method_type, input_type, output_type, handler, nothing, nothing)
    end

    # Constructor with Julia types (preferred - enables auto-registration)
    function MethodDescriptor(
        name::String,
        method_type::MethodType.T,
        input_type::Type,
        output_type::Type,
        handler::Function
    )
        # Derive protobuf type name from Julia type
        input_name = _type_to_proto_name(input_type)
        output_name = _type_to_proto_name(output_type)
        new(name, method_type, input_name, output_name, handler, input_type, output_type)
    end
end

"""
    _type_to_proto_name(T::Type) -> String

Convert a Julia type to its protobuf fully-qualified name.
Uses the module hierarchy to construct the name.
"""
function _type_to_proto_name(T::Type)::String
    # Get the module path
    mod = parentmodule(T)
    type_name = string(nameof(T))

    # Build package name from module hierarchy
    parts = String[]
    while mod !== Main && mod !== Base && mod !== Core
        pushfirst!(parts, string(nameof(mod)))
        mod = parentmodule(mod)
    end

    if isempty(parts)
        return type_name
    else
        return join(parts, ".") * "." * type_name
    end
end

function Base.show(io::IO, method::MethodDescriptor)
    print(io, "MethodDescriptor($(method.name), $(method.method_type))")
end

"""
    ServiceDescriptor

Describes a gRPC service and its methods.

# Fields
- `name::String`: Fully-qualified service name (e.g., "helloworld.Greeter")
- `methods::Dict{String, MethodDescriptor}`: Methods keyed by name
- `file_descriptor::Union{Vector{UInt8}, Nothing}`: File descriptor for reflection (optional)

# Example
```julia
service = ServiceDescriptor(
    "helloworld.Greeter",
    Dict(
        "SayHello" => MethodDescriptor(
            "SayHello",
            MethodType.UNARY,
            "helloworld.HelloRequest",
            "helloworld.HelloReply",
            say_hello
        )
    ),
    nothing
)
```
"""
struct ServiceDescriptor
    name::String
    methods::Dict{String, MethodDescriptor}
    file_descriptor::Union{Vector{Vector{UInt8}}, Nothing}

    function ServiceDescriptor(
        name::String,
        methods::Dict{String, MethodDescriptor},
        file_descriptor::Union{Vector{Vector{UInt8}}, Nothing}=nothing
    )
        new(name, methods, file_descriptor)
    end
end

function Base.show(io::IO, service::ServiceDescriptor)
    print(io, "ServiceDescriptor($(service.name), $(length(service.methods)) methods)")
end

"""
    service_descriptor(service) -> ServiceDescriptor

Get the service descriptor for a service implementation.

This function should be overloaded for custom service types.

# Example
```julia
struct GreeterService end

function gRPCServer.service_descriptor(::GreeterService)
    ServiceDescriptor(
        "helloworld.Greeter",
        Dict(
            "SayHello" => MethodDescriptor(
                "SayHello", MethodType.UNARY,
                "helloworld.HelloRequest", "helloworld.HelloReply",
                say_hello
            )
        ),
        nothing
    )
end
```
"""
function service_descriptor(service)::ServiceDescriptor
    throw(MethodSignatureError(
        "service_descriptor",
        "service_descriptor(service::T) -> ServiceDescriptor",
        "No implementation for $(typeof(service))"
    ))
end

"""
    ServiceRegistry

Registry of services and methods for request routing.

# Fields
- `services::Dict{String, ServiceDescriptor}`: Services by name
- `method_lookup::Dict{String, Tuple{ServiceDescriptor, MethodDescriptor}}`: Method lookup by path
"""
mutable struct ServiceRegistry
    services::Dict{String, ServiceDescriptor}
    method_lookup::Dict{String, Tuple{ServiceDescriptor, MethodDescriptor}}

    ServiceRegistry() = new(
        Dict{String, ServiceDescriptor}(),
        Dict{String, Tuple{ServiceDescriptor, MethodDescriptor}}()
    )
end

"""
    register!(registry::ServiceRegistry, descriptor::ServiceDescriptor)

Register a service in the registry.
Also auto-registers protobuf types if Julia types were provided in MethodDescriptor.
"""
function register!(registry::ServiceRegistry, descriptor::ServiceDescriptor)
    if haskey(registry.services, descriptor.name)
        throw(ServiceAlreadyRegisteredError(descriptor.name))
    end

    registry.services[descriptor.name] = descriptor

    # Build method lookup and auto-register types
    type_registry = get_type_registry()
    for (method_name, method) in descriptor.methods
        path = "/$(descriptor.name)/$(method_name)"
        registry.method_lookup[path] = (descriptor, method)

        # Auto-register Julia types if provided
        if method.input_julia_type !== nothing
            type_registry[method.input_type] = method.input_julia_type
        end
        if method.output_julia_type !== nothing
            type_registry[method.output_type] = method.output_julia_type
        end
    end
end

"""
    lookup_method(registry::ServiceRegistry, path::String) -> Union{Tuple{ServiceDescriptor, MethodDescriptor}, Nothing}

Look up a method by its path (e.g., "/helloworld.Greeter/SayHello").
"""
function lookup_method(registry::ServiceRegistry, path::String)::Union{Tuple{ServiceDescriptor, MethodDescriptor}, Nothing}
    return get(registry.method_lookup, path, nothing)
end

"""
    get_service(registry::ServiceRegistry, name::String) -> Union{ServiceDescriptor, Nothing}

Get a service by name.
"""
function get_service(registry::ServiceRegistry, name::String)::Union{ServiceDescriptor, Nothing}
    return get(registry.services, name, nothing)
end

"""
    list_services(registry::ServiceRegistry) -> Vector{String}

List all registered service names.
"""
function list_services(registry::ServiceRegistry)::Vector{String}
    return collect(keys(registry.services))
end

function Base.show(io::IO, registry::ServiceRegistry)
    print(io, "ServiceRegistry($(length(registry.services)) services, $(length(registry.method_lookup)) methods)")
end

"""
    RequestDispatcher

Dispatches incoming requests to the appropriate handler.

# Fields
- `registry::ServiceRegistry`: Service registry
- `interceptor_chain::InterceptorChain`: Global interceptors
- `service_interceptors::Dict{String, InterceptorChain}`: Per-service interceptors
- `debug_mode::Bool`: Include exception details in errors
"""
mutable struct RequestDispatcher
    registry::ServiceRegistry
    interceptor_chain::InterceptorChain
    service_interceptors::Dict{String, InterceptorChain}
    debug_mode::Bool

    RequestDispatcher(; debug_mode::Bool=false) = new(
        ServiceRegistry(),
        InterceptorChain(),
        Dict{String, InterceptorChain}(),
        debug_mode
    )
end

"""
    register_service!(dispatcher::RequestDispatcher, descriptor::ServiceDescriptor)

Register a service with the dispatcher.
"""
function register_service!(dispatcher::RequestDispatcher, descriptor::ServiceDescriptor)
    register!(dispatcher.registry, descriptor)
end

"""
    add_interceptor!(dispatcher::RequestDispatcher, interceptor::Interceptor)

Add a global interceptor.
"""
function add_interceptor!(dispatcher::RequestDispatcher, interceptor::Interceptor)
    add!(dispatcher.interceptor_chain, interceptor)
end

"""
    add_interceptor!(dispatcher::RequestDispatcher, service_name::String, interceptor::Interceptor)

Add a service-specific interceptor.
"""
function add_interceptor!(dispatcher::RequestDispatcher, service_name::String, interceptor::Interceptor)
    if !haskey(dispatcher.service_interceptors, service_name)
        dispatcher.service_interceptors[service_name] = InterceptorChain()
    end
    add!(dispatcher.service_interceptors[service_name], interceptor)
end

"""
    dispatch_unary(
        dispatcher::RequestDispatcher,
        ctx::ServerContext,
        request_data::Vector{UInt8}
    ) -> Tuple{StatusCode.T, String, Vector{UInt8}}

Dispatch a unary RPC request.
Returns (status_code, status_message, response_data).
"""
function dispatch_unary(
    dispatcher::RequestDispatcher,
    ctx::ServerContext,
    request_data::Vector{UInt8}
)::Tuple{StatusCode.T, String, Vector{UInt8}}
    path = ctx.method

    # Look up method
    result = lookup_method(dispatcher.registry, path)
    if result === nothing
        return (StatusCode.UNIMPLEMENTED, "Method not found: $path", UInt8[])
    end

    service, method = result

    if method.method_type != MethodType.UNARY
        return (StatusCode.UNIMPLEMENTED, "Method is not unary: $(method.name)", UInt8[])
    end

    try
        # Deserialize request
        request = deserialize_message(request_data, method.input_type)

        # Build interceptor chain
        info = MethodInfo(service.name, method.name, method.method_type)
        handler = build_handler_chain(dispatcher, service.name, method.handler, info)

        # Execute handler
        response = handler(ctx, request)

        # Serialize response
        response_data = serialize_message(response)

        return (StatusCode.OK, "", response_data)

    catch e
        return handle_exception(e, dispatcher.debug_mode)
    end
end

"""
    build_handler_chain(dispatcher, service_name, handler, info) -> Function

Build the complete handler chain with interceptors.
"""
function build_handler_chain(
    dispatcher::RequestDispatcher,
    service_name::String,
    handler::Function,
    info::MethodInfo
)::Function
    # Start with the actual handler
    wrapped = handler

    # Apply service-specific interceptors first (innermost)
    if haskey(dispatcher.service_interceptors, service_name)
        wrapped = wrap(dispatcher.service_interceptors[service_name], wrapped, info)
    end

    # Apply global interceptors (outermost)
    wrapped = wrap(dispatcher.interceptor_chain, wrapped, info)

    return wrapped
end

"""
    handle_exception(e::Exception, debug_mode::Bool) -> Tuple{StatusCode.T, String, Vector{UInt8}}

Convert an exception to a gRPC status response.
"""
function handle_exception(e::Exception, debug_mode::Bool)::Tuple{StatusCode.T, String, Vector{UInt8}}
    if e isa GRPCError
        return (e.code, e.message, UInt8[])
    end

    # Map known exceptions to status codes
    code = exception_to_status_code(e)

    message = if debug_mode
        io = IOBuffer()
        showerror(io, e)
        String(take!(io))
    else
        if code == StatusCode.INTERNAL
            "Internal server error"
        else
            string(e)
        end
    end

    return (code, message, UInt8[])
end

"""
    handle_exception_with_logging(e::Exception, ctx::ServerContext, debug_mode::Bool) -> Tuple{StatusCode.T, String, Vector{UInt8}}

Convert an exception to a gRPC status response with structured logging.
Includes request_id in all error logs for traceability.
"""
function handle_exception_with_logging(e::Exception, ctx::ServerContext, debug_mode::Bool)::Tuple{StatusCode.T, String, Vector{UInt8}}
    if e isa GRPCError
        @warn "gRPC error" request_id=ctx.request_id method=ctx.method code=e.code message=e.message
        return (e.code, e.message, UInt8[])
    end

    # Map known exceptions to status codes
    code = exception_to_status_code(e)

    message = if debug_mode
        io = IOBuffer()
        showerror(io, e)
        String(take!(io))
    else
        if code == StatusCode.INTERNAL
            "Internal server error"
        else
            string(e)
        end
    end

    # Log with structured context
    if code == StatusCode.INTERNAL
        @error "Internal server error" request_id=ctx.request_id method=ctx.method exception=(e, catch_backtrace())
    else
        @warn "Request error" request_id=ctx.request_id method=ctx.method code=code message=message
    end

    return (code, message, UInt8[])
end

"""
    _type_registry

Lazily initialized type registry mapping protobuf type names to Julia types.
"""
const _type_registry = Ref{Dict{String, Type}}()

"""
    get_type_registry() -> Dict{String, Type}

Get the type registry, initializing it on first access.
"""
function get_type_registry()::Dict{String, Type}
    if !isassigned(_type_registry)
        # Initialize with known types - these are defined in the proto files
        # which are included after dispatch.jl
        _type_registry[] = Dict{String, Type}(
            "grpc.health.v1.HealthCheckRequest" => HealthCheckRequest,
            "grpc.health.v1.HealthCheckResponse" => HealthCheckResponse,
            "grpc.reflection.v1alpha.ServerReflectionRequest" => ServerReflectionRequest,
            "grpc.reflection.v1alpha.ServerReflectionResponse" => ServerReflectionResponse,
        )
    end
    return _type_registry[]
end

"""
    deserialize_message(data::Vector{UInt8}, type_name::String) -> Any

Deserialize a Protocol Buffer message from raw bytes.

Note: The gRPC Length-Prefixed Message header (5 bytes) should already be stripped
by the time this function is called. This function receives raw protobuf bytes.
"""
function deserialize_message(data::Vector{UInt8}, type_name::String)
    # Look up the Julia type from the registry
    julia_type = get(get_type_registry(), type_name, nothing)

    if julia_type === nothing
        # Unknown type - return raw bytes as fallback
        @warn "Unknown protobuf type, returning raw bytes" type_name
        return data
    end

    # Use ProtoBuf.jl to decode the message
    try
        io = IOBuffer(data)
        decoder = ProtoBuf.ProtoDecoder(io)
        return ProtoBuf.decode(decoder, julia_type)
    catch e
        if _supports_generic_proto_fallback(julia_type)
            try
                return _generic_deserialize_message(data, julia_type)
            catch fallback_error
                throw(GRPCError(StatusCode.INVALID_ARGUMENT, "Failed to deserialize $type_name: $(sprint(showerror, fallback_error))"))
            end
        end
        throw(GRPCError(StatusCode.INVALID_ARGUMENT, "Failed to deserialize $type_name: $(sprint(showerror, e))"))
    end
end

"""
    serialize_message(message) -> Vector{UInt8}

Serialize a Protocol Buffer message to raw bytes.

Note: This returns raw protobuf bytes WITHOUT the gRPC Length-Prefixed header.
The gRPC framing is added later by the transport layer (server.jl encode_grpc_message).
"""
function serialize_message(message)::Vector{UInt8}
    # Serialize message using ProtoBuf
    if message isa Vector{UInt8}
        return message
    end

    # Use ProtoBuf.jl to encode the message
    try
        msg_io = IOBuffer()
        encoder = ProtoBuf.ProtoEncoder(msg_io)
        ProtoBuf.encode(encoder, message)
        return take!(msg_io)
    catch e
        if _supports_generic_proto_fallback(typeof(message))
            try
                return _generic_serialize_message(message)
            catch fallback_error
                @error "Failed to serialize message" exception=(fallback_error, catch_backtrace())
                return UInt8[]
            end
        end
        @error "Failed to serialize message" exception=(e, catch_backtrace())
        return UInt8[]
    end
end

function _supports_generic_proto_fallback(T::Type)::Bool
    return !isempty(fieldnames(T))
end

function _field_numbers_for_type(T::Type)
    try
        fn = PB.field_numbers(T)
        if !isempty(fn)
            return fn
        end
    catch
    end
    # Fallback: assign sequential field numbers based on struct field order
    names = fieldnames(T)
    values = Tuple(1:length(names))
    return NamedTuple{names}(values)
end

function _field_number_lookup(T::Type)::Dict{Int, Symbol}
    field_nums = _field_numbers_for_type(T)
    lookup = Dict{Int, Symbol}()
    for name in keys(field_nums)
        lookup[Int(getfield(field_nums, name))] = name
    end
    return lookup
end

function _wire_type_for_field_type(T::Type)::UInt8
    if T <: AbstractString || T <: Vector{UInt8}
        return 0x02
    elseif T <: Bool || T <: Integer
        return 0x00
    elseif T <: Float64
        return 0x01
    elseif T <: Float32
        return 0x05
    end
    throw(ArgumentError("Unsupported protobuf field type: $T"))
end

function _encode_varint(value::UInt64)::Vector{UInt8}
    buf = UInt8[]
    current = value
    while current >= 0x80
        push!(buf, UInt8((current & 0x7f) | 0x80))
        current >>= 7
    end
    push!(buf, UInt8(current))
    return buf
end

function _encode_signed_varint(value::Integer)::Vector{UInt8}
    signed = Int64(value)
    return _encode_varint(reinterpret(UInt64, signed))
end

function _read_varint(data::Vector{UInt8}, index::Int)
    value = UInt64(0)
    shift = 0
    current = index
    while current <= length(data)
        byte = data[current]
        value |= UInt64(byte & 0x7f) << shift
        current += 1
        if (byte & 0x80) == 0
            return value, current
        end
        shift += 7
        if shift > 63
            throw(ArgumentError("Malformed protobuf varint"))
        end
    end
    throw(ArgumentError("Unexpected EOF while reading protobuf varint"))
end

function _skip_field(data::Vector{UInt8}, index::Int, wire_type::UInt8)
    if wire_type == 0x00
        _, next_index = _read_varint(data, index)
        return next_index
    elseif wire_type == 0x01
        next_index = index + 8
    elseif wire_type == 0x02
        len, cursor = _read_varint(data, index)
        next_index = cursor + Int(len)
    elseif wire_type == 0x05
        next_index = index + 4
    else
        throw(ArgumentError("Unsupported protobuf wire type: $wire_type"))
    end

    if next_index - 1 > length(data)
        throw(ArgumentError("Unexpected EOF while skipping protobuf field"))
    end
    return next_index
end

function _default_field_value(T::Type)
    if T <: AbstractString
        return ""
    elseif T <: Vector{UInt8}
        return UInt8[]
    elseif T <: Bool
        return false
    elseif T <: Float64 || T <: Float32
        return zero(T)
    elseif T <: Integer
        return zero(T)
    end
    throw(ArgumentError("Unsupported protobuf field type: $T"))
end

function _decode_field_value(data::Vector{UInt8}, index::Int, field_type::Type, wire_type::UInt8)
    if field_type <: AbstractString
        wire_type == 0x02 || throw(ArgumentError("Expected length-delimited string field"))
        len, cursor = _read_varint(data, index)
        end_index = cursor + Int(len) - 1
        end_index <= length(data) || throw(ArgumentError("Unexpected EOF while reading string field"))
        return String(data[cursor:end_index]), end_index + 1
    elseif field_type <: Vector{UInt8}
        wire_type == 0x02 || throw(ArgumentError("Expected length-delimited bytes field"))
        len, cursor = _read_varint(data, index)
        end_index = cursor + Int(len) - 1
        end_index <= length(data) || throw(ArgumentError("Unexpected EOF while reading bytes field"))
        return copy(data[cursor:end_index]), end_index + 1
    elseif field_type <: Bool
        wire_type == 0x00 || throw(ArgumentError("Expected varint bool field"))
        value, next_index = _read_varint(data, index)
        return value != 0, next_index
    elseif field_type <: Int32
        wire_type == 0x00 || throw(ArgumentError("Expected varint int32 field"))
        value, next_index = _read_varint(data, index)
        return reinterpret(Int32, UInt32(value)), next_index
    elseif field_type <: Int64
        wire_type == 0x00 || throw(ArgumentError("Expected varint int64 field"))
        value, next_index = _read_varint(data, index)
        return reinterpret(Int64, value), next_index
    elseif field_type <: Int
        wire_type == 0x00 || throw(ArgumentError("Expected varint int field"))
        value, next_index = _read_varint(data, index)
        return Int(reinterpret(Int64, value)), next_index
    elseif field_type <: UInt32
        wire_type == 0x00 || throw(ArgumentError("Expected varint uint32 field"))
        value, next_index = _read_varint(data, index)
        return UInt32(value), next_index
    elseif field_type <: UInt64
        wire_type == 0x00 || throw(ArgumentError("Expected varint uint64 field"))
        value, next_index = _read_varint(data, index)
        return value, next_index
    elseif field_type <: Float64
        wire_type == 0x01 || throw(ArgumentError("Expected fixed64 field"))
        index + 7 <= length(data) || throw(ArgumentError("Unexpected EOF while reading float64 field"))
        raw = reinterpret(UInt64, only(reinterpret(Float64, data[index:index+7])))
        return reinterpret(Float64, raw), index + 8
    elseif field_type <: Float32
        wire_type == 0x05 || throw(ArgumentError("Expected fixed32 field"))
        index + 3 <= length(data) || throw(ArgumentError("Unexpected EOF while reading float32 field"))
        raw = reinterpret(UInt32, only(reinterpret(Float32, data[index:index+3])))
        return reinterpret(Float32, raw), index + 4
    end

    throw(ArgumentError("Unsupported protobuf field type: $field_type"))
end

function _encode_field_value(value, field_type::Type)::Vector{UInt8}
    if field_type <: AbstractString
        bytes = Vector{UInt8}(String(value))
        return vcat(_encode_varint(UInt64(length(bytes))), bytes)
    elseif field_type <: Vector{UInt8}
        bytes = Vector{UInt8}(value)
        return vcat(_encode_varint(UInt64(length(bytes))), bytes)
    elseif field_type <: Bool
        return _encode_varint(value ? UInt64(1) : UInt64(0))
    elseif field_type <: Int32 || field_type <: Int64 || field_type <: Int
        return _encode_signed_varint(value)
    elseif field_type <: UInt32 || field_type <: UInt64
        return _encode_varint(UInt64(value))
    elseif field_type <: Float64
        return collect(reinterpret(UInt8, [Float64(value)]))
    elseif field_type <: Float32
        return collect(reinterpret(UInt8, [Float32(value)]))
    end

    throw(ArgumentError("Unsupported protobuf field type: $field_type"))
end

function _generic_deserialize_message(data::Vector{UInt8}, T::Type)
    values = Dict{Symbol, Any}()
    number_lookup = _field_number_lookup(T)
    index = 1

    while index <= length(data)
        tag, next_index = _read_varint(data, index)
        field_number = Int(tag >> 3)
        wire_type = UInt8(tag & 0x07)
        field_name = get(number_lookup, field_number, nothing)

        if field_name === nothing
            index = _skip_field(data, next_index, wire_type)
            continue
        end

        field_type = fieldtype(T, field_name)
        field_value, index = _decode_field_value(data, next_index, field_type, wire_type)
        values[field_name] = field_value
    end

    ordered_values = Any[]
    for field_name in fieldnames(T)
        field_type = fieldtype(T, field_name)
        push!(ordered_values, get(values, field_name, _default_field_value(field_type)))
    end

    return T(ordered_values...)
end

function _generic_serialize_message(message)::Vector{UInt8}
    T = typeof(message)
    field_nums = _field_numbers_for_type(T)
    encoded = UInt8[]

    for field_name in fieldnames(T)
        field_type = fieldtype(T, field_name)
        field_number = Int(getfield(field_nums, field_name))
        wire_type = _wire_type_for_field_type(field_type)
        tag = UInt64((field_number << 3) | wire_type)
        append!(encoded, _encode_varint(tag))
        append!(encoded, _encode_field_value(getfield(message, field_name), field_type))
    end

    return encoded
end

"""
    parse_grpc_path(path::String) -> Tuple{String, String}

Parse a gRPC path into (service_name, method_name).
"""
function parse_grpc_path(path::String)::Tuple{String, String}
    # Path format: /<service>/<method>
    if !startswith(path, "/")
        throw(GRPCError(StatusCode.INVALID_ARGUMENT, "Invalid path format: $path"))
    end

    parts = split(path[2:end], "/")
    if length(parts) != 2
        throw(GRPCError(StatusCode.INVALID_ARGUMENT, "Invalid path format: $path"))
    end

    return (String(parts[1]), String(parts[2]))
end

"""
    dispatch_server_streaming(
        dispatcher::RequestDispatcher,
        ctx::ServerContext,
        request_data::Vector{UInt8},
        send_callback::Function,
        close_callback::Function
    ) -> Tuple{StatusCode.T, String}

Dispatch a server streaming RPC request.
Returns (status_code, status_message) after streaming completes.
"""
function dispatch_server_streaming(
    dispatcher::RequestDispatcher,
    ctx::ServerContext,
    request_data::Vector{UInt8},
    send_callback::Function,
    close_callback::Function
)::Tuple{StatusCode.T, String}
    path = ctx.method

    # Look up method
    result = lookup_method(dispatcher.registry, path)
    if result === nothing
        return (StatusCode.UNIMPLEMENTED, "Method not found: $path")
    end

    service, method = result

    if method.method_type != MethodType.SERVER_STREAMING
        return (StatusCode.UNIMPLEMENTED, "Method is not server streaming: $(method.name)")
    end

    try
        # Deserialize request
        request = deserialize_message(request_data, method.input_type)

        # Create server stream
        stream = ServerStream{Any}(send_callback, close_callback)

        # Build interceptor chain for streaming
        info = MethodInfo(service.name, method.name, method.method_type)

        # For streaming, we wrap the handler differently
        # The handler signature is (ctx, request, stream) -> Nothing
        handler = method.handler

        # Apply interceptors (they receive the request, not the stream)
        wrapped_handler = build_streaming_handler_chain(dispatcher, service.name, handler, info, stream)

        # Execute handler
        wrapped_handler(ctx, request)

        return (StatusCode.OK, "")

    catch e
        code, message, _ = handle_exception(e, dispatcher.debug_mode)
        return (code, message)
    end
end

"""
    dispatch_client_streaming(
        dispatcher::RequestDispatcher,
        ctx::ServerContext,
        receive_callback::Function,
        is_cancelled_callback::Function
    ) -> Tuple{StatusCode.T, String, Vector{UInt8}}

Dispatch a client streaming RPC request.
Returns (status_code, status_message, response_data).
"""
function dispatch_client_streaming(
    dispatcher::RequestDispatcher,
    ctx::ServerContext,
    receive_callback::Function,
    is_cancelled_callback::Function
)::Tuple{StatusCode.T, String, Vector{UInt8}}
    path = ctx.method

    # Look up method
    result = lookup_method(dispatcher.registry, path)
    if result === nothing
        return (StatusCode.UNIMPLEMENTED, "Method not found: $path", UInt8[])
    end

    service, method = result

    if method.method_type != MethodType.CLIENT_STREAMING
        return (StatusCode.UNIMPLEMENTED, "Method is not client streaming: $(method.name)", UInt8[])
    end

    try
        # Create client stream with the correct input type
        # Use the Julia type if available, otherwise fall back to Any
        input_type = method.input_julia_type !== nothing ? method.input_julia_type : Any
        stream = ClientStream{input_type}(receive_callback, is_cancelled_callback)

        # Build interceptor chain
        info = MethodInfo(service.name, method.name, method.method_type)

        # For client streaming, handler signature is (ctx, stream) -> response
        handler = method.handler
        wrapped_handler = build_client_streaming_handler_chain(dispatcher, service.name, handler, info)

        # Execute handler - it returns the response
        response = wrapped_handler(ctx, stream)

        # Serialize response
        response_data = serialize_message(response)

        return (StatusCode.OK, "", response_data)

    catch e
        @error "Error in client streaming handler" exception=(e, catch_backtrace())
        return handle_exception(e, dispatcher.debug_mode)
    end
end

"""
    dispatch_bidi_streaming(
        dispatcher::RequestDispatcher,
        ctx::ServerContext,
        receive_callback::Function,
        send_callback::Function,
        close_callback::Function,
        is_cancelled_callback::Function
    ) -> Tuple{StatusCode.T, String}

Dispatch a bidirectional streaming RPC request.
Returns (status_code, status_message) after streaming completes.
"""
function dispatch_bidi_streaming(
    dispatcher::RequestDispatcher,
    ctx::ServerContext,
    receive_callback::Function,
    send_callback::Function,
    close_callback::Function,
    is_cancelled_callback::Function
)::Tuple{StatusCode.T, String}
    path = ctx.method

    # Look up method
    result = lookup_method(dispatcher.registry, path)
    if result === nothing
        return (StatusCode.UNIMPLEMENTED, "Method not found: $path")
    end

    service, method = result

    if method.method_type != MethodType.BIDI_STREAMING
        return (StatusCode.UNIMPLEMENTED, "Method is not bidirectional streaming: $(method.name)")
    end

    try
        # Create bidi stream with the correct input/output types
        # Use the Julia types if available, otherwise fall back to Any
        input_type = method.input_julia_type !== nothing ? method.input_julia_type : Any
        output_type = method.output_julia_type !== nothing ? method.output_julia_type : Any
        stream = BidiStream{input_type, output_type}(receive_callback, send_callback, close_callback, is_cancelled_callback)

        # Build interceptor chain
        info = MethodInfo(service.name, method.name, method.method_type)

        # For bidi streaming, handler signature is (ctx, stream) -> Nothing
        handler = method.handler
        wrapped_handler = build_bidi_streaming_handler_chain(dispatcher, service.name, handler, info)

        # Execute handler
        wrapped_handler(ctx, stream)

        return (StatusCode.OK, "")

    catch e
        code, message, _ = handle_exception(e, dispatcher.debug_mode)
        return (code, message)
    end
end

"""
    build_streaming_handler_chain(dispatcher, service_name, handler, info, stream) -> Function

Build handler chain for server streaming with interceptors.
Returns a function `(ctx, request) -> Nothing`.
"""
function build_streaming_handler_chain(
    dispatcher::RequestDispatcher,
    service_name::String,
    handler::Function,
    info::MethodInfo,
    stream::ServerStream
)::Function
    # The actual handler takes (ctx, request, stream)
    # We create a wrapper that captures the stream
    final_handler = (ctx, request) -> begin
        handler(ctx, request, stream)
        return nothing
    end

    # Apply service-specific interceptors first (innermost)
    wrapped = final_handler
    if haskey(dispatcher.service_interceptors, service_name)
        wrapped = wrap(dispatcher.service_interceptors[service_name], wrapped, info)
    end

    # Apply global interceptors (outermost)
    wrapped = wrap(dispatcher.interceptor_chain, wrapped, info)

    return wrapped
end

"""
    build_client_streaming_handler_chain(dispatcher, service_name, handler, info) -> Function

Build handler chain for client streaming with interceptors.
Returns a function `(ctx, stream) -> response`.
"""
function build_client_streaming_handler_chain(
    dispatcher::RequestDispatcher,
    service_name::String,
    handler::Function,
    info::MethodInfo
)::Function
    # For client streaming, the handler already takes (ctx, stream) -> response
    # We adapt it for the interceptor chain which expects (ctx, request) -> response
    # The "request" in this case is the stream

    wrapped = handler

    # Apply service-specific interceptors first (innermost)
    if haskey(dispatcher.service_interceptors, service_name)
        wrapped = wrap_streaming(dispatcher.service_interceptors[service_name], wrapped, info)
    end

    # Apply global interceptors (outermost)
    wrapped = wrap_streaming(dispatcher.interceptor_chain, wrapped, info)

    return wrapped
end

"""
    build_bidi_streaming_handler_chain(dispatcher, service_name, handler, info) -> Function

Build handler chain for bidirectional streaming with interceptors.
Returns a function `(ctx, stream) -> Nothing`.
"""
function build_bidi_streaming_handler_chain(
    dispatcher::RequestDispatcher,
    service_name::String,
    handler::Function,
    info::MethodInfo
)::Function
    # For bidi streaming, the handler takes (ctx, stream) -> Nothing
    # Similar to client streaming adaptation

    wrapped = handler

    # Apply service-specific interceptors first (innermost)
    if haskey(dispatcher.service_interceptors, service_name)
        wrapped = wrap_streaming(dispatcher.service_interceptors[service_name], wrapped, info)
    end

    # Apply global interceptors (outermost)
    wrapped = wrap_streaming(dispatcher.interceptor_chain, wrapped, info)

    return wrapped
end

function Base.show(io::IO, dispatcher::RequestDispatcher)
    print(io, "RequestDispatcher($(dispatcher.registry), $(length(dispatcher.interceptor_chain)) interceptors)")
end
