public import Middleware

public struct ForwardingMiddleware<Input: ~Copyable & ~Escapable>: Middleware {
    public init() {}
    
    public func intercept<Return: ~Copyable>(
        input: consuming Input,
        next: (consuming Input) async throws -> Return
    ) async throws -> Return {
        try await next(input)
    }
}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension Middleware {
    public func forwarding() -> ForwardingMiddleware<Input> {
        ForwardingMiddleware()
    }
}
