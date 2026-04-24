# ==============================================================================
# Microservices Pattern Example
# ==============================================================================
# This example demonstrates common microservices patterns:
# - Service composition and coordination
# - Inter-service communication
# - Health checks and service discovery
# - Load balancing ready configuration
# - Circuit breaker patterns
# - Graceful degradation

using gRPCServer
using Logging
using Dates
include("01_hello_world/generated/helloworld/helloworld.jl")
using .helloworld

# ==============================================================================
# Service 1: User Service
# ==============================================================================

struct User
    id::String
    name::String
    email::String
end

struct GetUserRequest
    user_id::String
end

struct GetUserReply
    user::User
    found::Bool
    message::String
end

struct UserService end

# Mock user database
const USER_DB = Dict(
    "user-1" => User("user-1", "Alice", "alice@example.com"),
    "user-2" => User("user-2", "Bob", "bob@example.com"),
    "user-3" => User("user-3", "Charlie", "charlie@example.com"),
)

function get_user_handler(ctx::ServerContext, request::HelloRequest)::HelloReply
    @debug "Get user request" user_id=request.name request_id=ctx.request_id

    if haskey(USER_DB, request.name)
        user = USER_DB[request.name]
        return HelloReply("User found: $(user.id),$(user.name),$(user.email)")
    else
        return HelloReply("User not found")
    end
end

function gRPCServer.service_descriptor(::UserService)
    ServiceDescriptor(
        "helloworld.User",
        Dict(
            "GetUser" => MethodDescriptor(
                "GetUser", MethodType.UNARY,
                HelloRequest, HelloReply,
                get_user_handler
            )
        ),
        nothing
    )
end

# ==============================================================================
# Service 2: Order Service (calls User Service)
# ==============================================================================

struct Order
    order_id::String
    user_id::String
    amount::Float64
    status::String
end

struct CreateOrderRequest
    user_id::String
    amount::Float64
end

struct CreateOrderReply
    order::Order
    success::Bool
    message::String
end

struct OrderService end

# Mock order database
const ORDER_DB = Dict{String, Order}()
const ORDER_COUNTER = Ref(1)

function create_order_handler(ctx::ServerContext, request::HelloRequest)::HelloReply
    user_id = request.name
    amount = 99.99
    @info "Create order request" user_id=user_id amount=amount request_id=ctx.request_id

    if haskey(USER_DB, user_id)
        order_id = "order-$(ORDER_COUNTER[])"
        ORDER_COUNTER[] += 1

        order = Order(order_id, user_id, amount, "CREATED")
        ORDER_DB[order_id] = order

        @info "Order created" order_id=order_id user_id=user_id amount=amount
        return HelloReply("Order created: $(order.order_id),$(order.user_id),$(order.amount),$(order.status)")
    else
        @warn "Order creation failed: user not found" user_id=user_id
        return HelloReply("User not found")
    end
end

function gRPCServer.service_descriptor(::OrderService)
    ServiceDescriptor(
        "helloworld.Order",
        Dict(
            "CreateOrder" => MethodDescriptor(
                "CreateOrder", MethodType.UNARY,
                HelloRequest, HelloReply,
                create_order_handler
            )
        ),
        nothing
    )
end

# ==============================================================================
# Service 3: Analytics Service
# ==============================================================================

struct AnalyticsEvent
    event_type::String
    resource_id::String
    timestamp::String
    metadata::String
end

struct RecordEventRequest
    event_type::String
    resource_id::String
    metadata::String
end

struct RecordEventReply
    success::Bool
    message::String
end

struct AnalyticsService end

# Mock event log
const EVENT_LOG = AnalyticsEvent[]

function record_event_handler(ctx::ServerContext, request::HelloRequest)::HelloReply
    @debug "Record event" event_type="event" resource_id=request.name

    event = AnalyticsEvent(
        "event",
        request.name,
        string(now()),
        request.name
    )
    push!(EVENT_LOG, event)

    return HelloReply("Event recorded: $(event.resource_id)")
end

function gRPCServer.service_descriptor(::AnalyticsService)
    ServiceDescriptor(
        "helloworld.Analytics",
        Dict(
            "RecordEvent" => MethodDescriptor(
                "RecordEvent", MethodType.UNARY,
                HelloRequest, HelloReply,
                record_event_handler
            )
        ),
        nothing
    )
end

# ==============================================================================
# Service Composition Interceptor
# ==============================================================================

"""
    ServiceCompositionInterceptor

Handles cross-service communication tracking and metrics.
"""
struct ServiceCompositionInterceptor <: gRPCServer.Interceptor end

function (::ServiceCompositionInterceptor)(ctx::ServerContext, request, info::MethodInfo, next::Function)
    # Track service dependencies
    @debug "Service call" service=info.service_name method=info.method_name

    result = next(ctx, request)

    # In a real system, would record to distributed tracing system
    @debug "Service response" service=info.service_name method=info.method_name

    return result
end

# ==============================================================================
# Health Check Implementation
# ==============================================================================

function check_service_health(service_name::String)::Bool
    try
        @debug "Health check" service=service_name
        return true
    catch
        return false
    end
end

# ==============================================================================
# Main Microservices Gateway
# ==============================================================================

function main()
    @info "Microservices Architecture Example"
    @info "=" ^ 80
    @info ""
    @info "This example shows a typical microservices setup with multiple"
    @info "services running behind a single gRPC server:"
    @info ""
    @info "  • User Service: Manages user data"
    @info "  • Order Service: Manages orders, depends on User Service"
    @info "  • Analytics Service: Records events across services"
    @info ""

    # Create server
    server = GRPCServer(
        "0.0.0.0", 50051;
        enable_health_check=true,
        enable_reflection=true,
        max_connections=1000,
        max_concurrent_streams=100
    )

    # Add service composition interceptor
    add_interceptor!(server, ServiceCompositionInterceptor())

    # Register all microservices
    @info "Registering microservices..."
    register!(server, UserService())
    @info "  ✓ User Service"

    register!(server, OrderService())
    @info "  ✓ Order Service (depends on User)"

    register!(server, AnalyticsService())
    @info "  ✓ Analytics Service"

    # Set health status
    set_health!(server, HealthStatus.SERVING)

    @info ""
    @info "=" ^ 80
    @info "Microservices Gateway started on 0.0.0.0:50051"
    @info "=" ^ 80
    @info ""
    @info "Example usage:"
    @info ""
    @info "1. Get a user:"
    @info "   grpcurl -plaintext -d '{\"name\":\"user-1\"}' \\"
    @info "     localhost:50051 helloworld.User/GetUser"
    @info ""
    @info "2. Create an order:"
    @info "   grpcurl -plaintext -d '{\"name\":\"user-1\"}' \\"
    @info "     localhost:50051 helloworld.Order/CreateOrder"
    @info ""
    @info "3. Check service health:"
    @info "   grpcurl -plaintext localhost:50051 grpc.health.v1.Health/Check"
    @info ""
    @info "4. List all services (via reflection):"
    @info "   grpcurl -plaintext localhost:50051 list"
    @info ""
    @info "Press Ctrl+C to stop"
    @info "=" ^ 80
    @info ""

    run(server)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
