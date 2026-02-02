import HTTPAPIs
import Middleware


@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
final class ExampleMiddlewareClient<Client: HTTPClient & ~Copyable, ClientMiddleware: Middleware<HTTPRequest, HTTPRequest>>: HTTPClient{
    typealias RequestConcludingWriter = Client.RequestConcludingWriter
    typealias ResponseConcludingReader = Client.ResponseConcludingReader
    
    private let client: Client
    private let middleware: ClientMiddleware
    
    init(
        client: consuming Client,
        @MiddlewareBuilder
        middlewareBuilder: (RequestMiddleware<Client>) -> ClientMiddleware
    ) {
        self.client = client
        self.middleware = middlewareBuilder(RequestMiddleware<Client>())
    }

    func perform<Return>(
        request: HTTPRequest,
        body: consuming HTTPClientRequestBody<RequestConcludingWriter>?,
        configuration: HTTPClientConfiguration,
        eventHandler: borrowing some HTTPClientEventHandler & ~Copyable & ~Escapable,
        responseHandler: (HTTPResponse, consuming ResponseConcludingReader) async throws -> Return
    ) async throws -> Return {
        var body = Optional(body)
        return try await self.middleware.intercept(
            input: request
        ) { request in
            try await self.client.perform(
                request: request,
                body: body.take()!,
                configuration: configuration,
                eventHandler: eventHandler,
                responseHandler: responseHandler
            )
        }
    }
}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
struct RequestMiddleware<Client: HTTPClient & ~Copyable>: Middleware {
    typealias Input = HTTPRequest
    typealias NextInput = Input
    
    func intercept<Return: ~Copyable>(
        input: consuming Input,
        next: (consuming NextInput) async throws -> Return
    ) async throws -> Return {
        try await next(input)
    }
}
