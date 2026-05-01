import HTTPAPIs
import HTTPTypes
import JavaScriptKit
import JavaScriptEventLoop
import Foundation

public enum FetchError: Error {
    case BadURL
    case MalformedJS
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, *)
public final class FetchHTTPClient: HTTPAPIs.HTTPClient {
    public typealias RequestWriter = RequestBodyWriter
    public typealias ResponseConcludingReader = ResponseReader

    public struct RequestOptions: HTTPClientCapability.RequestOptions, Sendable {
        public init() {}
    }

    public let defaultRequestOptions: RequestOptions = RequestOptions()

    public init() {}

    public func perform<Return>(request: HTTPTypes.HTTPRequest, body: consuming HTTPAPIs.HTTPClientRequestBody<RequestBodyWriter>?, options: RequestOptions, responseHandler: nonisolated(nonsending) (HTTPTypes.HTTPResponse, consuming ResponseReader) async throws -> Return) async throws -> Return where Return : ~Copyable {
        guard let url = request.url else {
            throw FetchError.BadURL
        }

        // Collect request body in advance, because some browsers (Safari, Firefox) don't support streaming bytes in request body.
        var bodyBytes: [UInt8]? = nil
        if let body = body {
            let bufferArray = BufferArray()
            let writer = RequestBodyWriter(bufferArray: bufferArray)
            // Trailers are unsupported in browsers
            let _ = try await body.produce(into: writer)
            bodyBytes = bufferArray.toBytes()
        }

        // Collect request headers
        let requestHeaders = try Headers()
        for field in request.headerFields {
            try requestHeaders.append(field.name.rawName, field.value)
        }

        // Perform the request
        let requestInit = RequestInit(body: bodyBytes, method: request.method.rawValue, headers: requestHeaders)
        let response = try await fetch(url.absoluteString, requestInit);
        let responseStatus = try response.status
        let responseStatusText = try response.statusText
        let stream = try response.body
        let reader = try stream.getReader()

        // Collect response headers
        var responseHeaders = HTTPFields()
        let iterator = try response.headers.entries()
        while true {
            let result = try iterator.next()
            if let done = result.done, done {
                break
            }
            guard let entry = result.value else {
                throw FetchError.MalformedJS
            }

            guard entry.count == 2 else {
                throw FetchError.MalformedJS
            }

            guard let name = HTTPField.Name(entry[0]) else {
                throw FetchError.MalformedJS
            }

            responseHeaders.append(.init(name: name, value: entry[1]))
        }

        return try await responseHandler(HTTPResponse(status: .init(code: responseStatus, reasonPhrase: responseStatusText), headerFields: responseHeaders), ResponseReader(reader: reader))
    }

    public struct RequestBodyWriter: AsyncWriter, ~Copyable {
        var bufferArray: BufferArray

        public mutating func write<Result, Failure>(_ body: nonisolated(nonsending) (inout OutputSpan<UInt8>) async throws(Failure) -> Result) async throws(AsyncStreaming.EitherError<any Error, Failure>) -> Result where Failure : Error {
            do {
                let buffer: Buffer
                if let last = bufferArray.buffers.last, last.hasSpace() {
                    buffer = last
                } else {
                    // Make a new buffer and use that span
                    buffer = Buffer()
                    bufferArray.buffers.append(buffer);
                }
                var span = OutputSpan(buffer: buffer.storage, initializedCount: buffer.numElements)
                let result = try await body(&span)
                buffer.numElements = span.count
                return result;
            } catch {
               throw .second(error)
            }
        }
    }

    public struct ResponseReader: ConcludingAsyncReader, ~Copyable {
        let reader: ReadableStreamDefaultReader

        public consuming func consumeAndConclude<Return, Failure>(body: nonisolated(nonsending) (consuming sending FetchHTTPClient.ResponseBodyReader) async throws(Failure) -> Return) async throws(Failure) -> (Return, HTTPTypes.HTTPFields?) where Failure : Error {
            return (try await body(ResponseBodyReader(reader: reader)), nil)
        }
    }

    public struct ResponseBodyReader: AsyncReader, ~Copyable {
        let reader: ReadableStreamDefaultReader

        public mutating func read<Return, Failure>(maximumCount: Int?, body: nonisolated(nonsending) (consuming Span<UInt8>) async throws(Failure) -> Return) async throws(AsyncStreaming.EitherError<any Error, Failure>) -> Return where Failure : Error {
            let chunk: Chunk
            do {
                chunk = try await reader.read()
            } catch {
                throw .first(error)
            }
            if (chunk.done) {
                do {
                    return try await body(Span())
                } catch {
                    throw .second(error)
                }
            }

            guard let bytes = chunk.value else {
                throw .first(FetchError.MalformedJS)
            }

            if let count = maximumCount, bytes.count >= count {
                // TODO: we may have read more than the maximum count, we should temporarily store the rest
                // and only deliver up what the user asked for.
            }

            do {
                return try await body(bytes.span)
            } catch {
                throw .second(error)
            }
        }
    }
}
