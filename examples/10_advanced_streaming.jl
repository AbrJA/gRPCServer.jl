# ==============================================================================
# Advanced Streaming Patterns Example
# ==============================================================================
# This example demonstrates advanced streaming scenarios:
# - Streaming with backpressure handling
# - Large file transfer via streaming
# - Event streaming
# - Cancellation handling
# - Error handling in streams

using gRPCServer
using Logging
using Random
using Dates

# ==============================================================================
# Message Types
# ==============================================================================

# File transfer
struct FileChunk
    filename::String
    sequence::Int
    data::Vector{UInt8}
    is_last::Bool
end

struct FileUploadStatus
    filename::String
    bytes_received::Int
    success::Bool
    message::String
end

# Event streaming
struct EventFilter
    event_type::String
    min_priority::Int
end

struct Event
    event_id::String
    event_type::String
    priority::Int
    timestamp::String
    message::String
end

# ==============================================================================
# Service Containers
# ==============================================================================

struct FileService end
struct EventService end

# ==============================================================================
# File Upload Handler (Client Streaming)
# ==============================================================================

function file_upload_handler(ctx::ServerContext, stream::ClientStream{FileChunk})
    @info "File upload started" request_id=ctx.request_id

    total_bytes = 0
    filename = ""

    try
        for chunk in stream
            if ctx.cancelled
                @warn "File upload cancelled" request_id=ctx.request_id
                return FileUploadStatus(filename, total_bytes, false, "Upload cancelled")
            end

            total_bytes += length(chunk.data)
            filename = chunk.filename

            if mod(chunk.sequence, 10) == 0
                @debug "File upload progress" filename=filename bytes=total_bytes sequence=chunk.sequence
            end

            if chunk.is_last
                @info "File upload complete" filename=filename total_bytes=total_bytes
                break
            end
        end

        return FileUploadStatus(filename, total_bytes, true, "File uploaded successfully")

    catch e
        @error "File upload error" filename=filename total_bytes=total_bytes exception=e
        return FileUploadStatus(filename, total_bytes, false, "Upload failed")
    end
end

# ==============================================================================
# Event Streaming Handler (Server Streaming)
# ==============================================================================

function event_stream_handler(ctx::ServerContext, request::EventFilter, stream::ServerStream{Event})::Nothing
    @info "Event stream requested" event_type=request.event_type min_priority=request.min_priority request_id=ctx.request_id

    try
        # Simulate event generation
        for i in 1:100
            if ctx.cancelled
                @warn "Event stream cancelled" request_id=ctx.request_id
                break
            end

            # Generate event matching filter
            event_type = ["login", "logout", "error", "warning", "info"][rand(1:5)]
            if event_type != request.event_type
                continue
            end

            priority = rand(1:5)
            if priority < request.min_priority
                continue
            end

            event = Event(
                "event-$i",
                event_type,
                priority,
                string(now()),
                "Event $i occurred"
            )

            send!(stream, event)
            sleep(0.1)  # Simulate processing
        end

        close!(stream)
        @info "Event stream ended" request_id=ctx.request_id
    catch e
        @error "Event stream error" exception=e request_id=ctx.request_id
    end
    return nothing
end

# ==============================================================================
# Bidirectional Streaming: Incremental Search
# ==============================================================================

struct SearchQuery
    query::String
    max_results::Int
end

struct SearchResult
    id::String
    title::String
    score::Float64
end

function search_handler(ctx::ServerContext, stream::BidiStream{SearchQuery, SearchResult})
    @info "Search stream started" request_id=ctx.request_id

    try
        for query in stream
            if ctx.cancelled
                @warn "Search cancelled" request_id=ctx.request_id
                break
            end

            @info "Processing search" query=query.query max_results=query.max_results

            # Simulate search results
            for i in 1:min(query.max_results, 5)
                result = SearchResult(
                    "result-$i",
                    "Title: $(query.query) - Result $i",
                    100.0 - i * 10.0
                )
                send!(stream, result)
                sleep(0.05)
            end
        end

        close!(stream)
        @info "Search stream ended" request_id=ctx.request_id
    catch e
        @error "Search error" exception=e request_id=ctx.request_id
    end

    return nothing
end

struct SearchService end

# ==============================================================================
# Service Descriptors
# ==============================================================================

function gRPCServer.service_descriptor(::FileService)
    ServiceDescriptor(
        "streaming.File",
        Dict(
            "Upload" => MethodDescriptor(
                "Upload", MethodType.CLIENT_STREAMING,
                FileChunk, FileUploadStatus,
                file_upload_handler
            ),
            "EventStream" => MethodDescriptor(
                "EventStream", MethodType.SERVER_STREAMING,
                EventFilter, Event,
                event_stream_handler
            )
        ),
        nothing
    )
end

function gRPCServer.service_descriptor(::SearchService)
    ServiceDescriptor(
        "streaming.Search",
        Dict(
            "Search" => MethodDescriptor(
                "Search", MethodType.BIDI_STREAMING,
                SearchQuery, SearchResult,
                search_handler
            )
        ),
        nothing
    )
end

# ==============================================================================
# Main Server
# ==============================================================================

function main()
    @info "Advanced Streaming Patterns Example"
    @info "=" ^ 80

    server = GRPCServer(
        "0.0.0.0", 50051;
        enable_health_check=true,
        enable_reflection=true,
        max_message_size=32 * 1024 * 1024  # 32MB for large file transfers
    )

    register!(server, FileService())
    register!(server, SearchService())

    @info "Server started on 0.0.0.0:50051"
    @info ""
    @info "Streaming examples:"
    @info ""
    @info "1. File Upload (client streaming):"
    @info "   grpcurl -plaintext ... streaming.File/Upload"
    @info ""
    @info "2. Event Stream (server streaming):"
    @info "   grpcurl -plaintext -d '{\"event_type\":\"error\",\"min_priority\":2}' \\"
    @info "     localhost:50051 streaming.File/EventStream"
    @info ""
    @info "3. Search (bidirectional streaming):"
    @info "   grpcurl -plaintext -d @ localhost:50051 streaming.Search/Search"
    @info ""
    @info "Press Ctrl+C to stop"
    @info "=" ^ 80

    run(server)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
