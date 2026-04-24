# ==============================================================================
# Service Definitions for Feature Showcase
# ==============================================================================

using gRPCServer
using Dates

# ==============================================================================
# Message Types
# ==============================================================================

# Echo Service Messages
struct EchoRequest
    message::String
    delay_ms::Int
end

struct EchoReply
    message::String
    server_time::String
    request_id::String
end

# Math Service Messages
struct MathUnaryRequest
    operand_a::Float64
    operand_b::Float64
end

struct MathUnaryReply
    result::Float64
    operation::String
end

# Streaming Service Messages
struct StreamRequest
    count::Int
    delay_ms::Int
end

struct StreamReply
    sequence::Int
    timestamp::String
    data::String
end

# Bidirectional Chat
struct ChatMessage
    user::String
    text::String
    timestamp::String
end

# ==============================================================================
# Service Containers
# ==============================================================================

struct EchoService end
struct MathService end
struct StreamService end
struct ChatService end

# ==============================================================================
# Service Handlers: Echo Service
# ==============================================================================

function echo_unary_handler(ctx::ServerContext, request::EchoRequest)::EchoReply
    @info "Echo request" message=request.message request_id=ctx.request_id
    
    if request.delay_ms > 0
        sleep(request.delay_ms / 1000.0)
    end
    
    return EchoReply(
        "Echo: $(request.message)",
        string(now()),
        ctx.request_id
    )
end

# ==============================================================================
# Service Handlers: Math Service
# ==============================================================================

function add_handler(ctx::ServerContext, request::MathUnaryRequest)::MathUnaryReply
    @debug "Add operation" a=request.operand_a b=request.operand_b request_id=ctx.request_id
    return MathUnaryReply(request.operand_a + request.operand_b, "ADD")
end

function subtract_handler(ctx::ServerContext, request::MathUnaryRequest)::MathUnaryReply
    @debug "Subtract operation" a=request.operand_a b=request.operand_b request_id=ctx.request_id
    return MathUnaryReply(request.operand_a - request.operand_b, "SUBTRACT")
end

function multiply_handler(ctx::ServerContext, request::MathUnaryRequest)::MathUnaryReply
    @debug "Multiply operation" a=request.operand_a b=request.operand_b request_id=ctx.request_id
    return MathUnaryReply(request.operand_a * request.operand_b, "MULTIPLY")
end

function divide_handler(ctx::ServerContext, request::MathUnaryRequest)::MathUnaryReply
    @debug "Divide operation" a=request.operand_a b=request.operand_b request_id=ctx.request_id
    if request.operand_b == 0
        @warn "Division by zero" request_id=ctx.request_id
        return MathUnaryReply(0.0, "ERROR")
    end
    return MathUnaryReply(request.operand_a / request.operand_b, "DIVIDE")
end

# ==============================================================================
# Service Handlers: Stream Service
# ==============================================================================

function count_stream_handler(ctx::ServerContext, request::StreamRequest, stream::ServerStream{StreamReply})::Nothing
    @info "Count stream started" count=request.count request_id=ctx.request_id
    
    for i in 1:request.count
        if ctx.cancelled
            @warn "Stream cancelled" request_id=ctx.request_id
            break
        end
        
        if request.delay_ms > 0
            sleep(request.delay_ms / 1000.0)
        end
        
        reply = StreamReply(
            i,
            string(now()),
            "Data packet $i"
        )
        send!(stream, reply)
    end
    close!(stream)
    return nothing
end

# ==============================================================================
# Service Handlers: Chat Service (Bidirectional Streaming)
# ==============================================================================

function chat_bidi_handler(ctx::ServerContext, stream::BidiStream{ChatMessage, ChatMessage})
    @info "Chat session started" request_id=ctx.request_id
    
    for message in stream
        if ctx.cancelled
            @warn "Chat cancelled" request_id=ctx.request_id
            break
        end
        
        @info "Chat message" user=message.user text=message.text request_id=ctx.request_id
        
        # Echo back with server prefix
        response = ChatMessage(
            "Server",
            "You said: $(message.text)",
            string(now())
        )
        send!(stream, response)
    end
    
    close!(stream)
    @info "Chat session ended" request_id=ctx.request_id
    return nothing
end

# ==============================================================================
# Service Descriptors
# ==============================================================================

function gRPCServer.service_descriptor(::EchoService)
    ServiceDescriptor(
        "showcase.Echo",
        Dict(
            "Echo" => MethodDescriptor(
                "Echo", MethodType.UNARY,
                EchoRequest, EchoReply,
                echo_unary_handler
            )
        ),
        nothing
    )
end

function gRPCServer.service_descriptor(::MathService)
    ServiceDescriptor(
        "showcase.Math",
        Dict(
            "Add" => MethodDescriptor(
                "Add", MethodType.UNARY,
                MathUnaryRequest, MathUnaryReply,
                add_handler
            ),
            "Subtract" => MethodDescriptor(
                "Subtract", MethodType.UNARY,
                MathUnaryRequest, MathUnaryReply,
                subtract_handler
            ),
            "Multiply" => MethodDescriptor(
                "Multiply", MethodType.UNARY,
                MathUnaryRequest, MathUnaryReply,
                multiply_handler
            ),
            "Divide" => MethodDescriptor(
                "Divide", MethodType.UNARY,
                MathUnaryRequest, MathUnaryReply,
                divide_handler
            )
        ),
        nothing
    )
end

function gRPCServer.service_descriptor(::StreamService)
    ServiceDescriptor(
        "showcase.Stream",
        Dict(
            "CountStream" => MethodDescriptor(
                "CountStream", MethodType.SERVER_STREAMING,
                StreamRequest, StreamReply,
                count_stream_handler
            )
        ),
        nothing
    )
end

function gRPCServer.service_descriptor(::ChatService)
    ServiceDescriptor(
        "showcase.Chat",
        Dict(
            "ChatBidi" => MethodDescriptor(
                "ChatBidi", MethodType.BIDI_STREAMING,
                ChatMessage, ChatMessage,
                chat_bidi_handler
            )
        ),
        nothing
    )
end
