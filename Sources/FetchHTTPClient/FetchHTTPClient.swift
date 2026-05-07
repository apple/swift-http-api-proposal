//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift HTTP API Proposal open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift HTTP API Proposal project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import BasicContainers
import Foundation
import HTTPAPIs
import HTTPTypes
import JavaScriptEventLoop
import JavaScriptKit

// This class is needed to allow passing references to the UniqueArray
// between FetchHTTPClient and RequestBodyWriter.
class RequestBodyBuffer {
    var array = UniqueArray<UInt8>()
}

enum FetchError: Error {
    case BadURL

    // An expected invariant of a JS API was broken.
    // This usually indicates a faulty assumption about said JS API.
    case BadAssumptionJS

    // Browsers don't support trailers, so providing them
    // in request bodies is not allowed.
    case TrailersUnsupported
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

    public func perform<Return>(
        request: HTTPTypes.HTTPRequest,
        body: consuming HTTPAPIs.HTTPClientRequestBody<RequestBodyWriter>?,
        options: RequestOptions,
        responseHandler: nonisolated(nonsending) (HTTPTypes.HTTPResponse, consuming ResponseReader) async throws -> Return
    ) async throws -> Return where Return: ~Copyable {
        guard let url = request.url else {
            throw FetchError.BadURL
        }

        var jsBody: JSObject? = nil

        if let body = body {
            let buffer = RequestBodyBuffer()

            let writer = RequestBodyWriter(buffer: buffer)
            let trailers = try await body.produce(into: writer)

            if let trailers {
                throw FetchError.TrailersUnsupported
            }

            jsBody = buffer.array.span.withUnsafeBufferPointer { bufferPtr in
                JSTypedArray<UInt8>(buffer: bufferPtr).jsObject
            }
        }

        // Collect request headers
        let requestHeaders = try Headers()
        for field in request.headerFields {
            try requestHeaders.append(field.name.rawName, field.isoLatin1Value)
        }

        // Perform the request
        let requestInit = RequestInit(body: jsBody, method: request.method.rawValue, headers: requestHeaders)
        let response = try await fetch(url.absoluteString, requestInit)
        let responseStatus = try response.status
        let responseStatusText = try response.statusText
        let stream = try response.body
        let reader = try stream.getReader()

        // Collect response headers.
        // Note that `Set-Cookie` headers can never be accessed because
        // they are filtered out by the `fetch` API.
        var responseHeaders = HTTPFields()
        let iterator = try response.headers.entries()
        while true {
            let result = try iterator.next()
            if let done = result.done, done {
                break
            }
            guard let entry = result.value else {
                // If iterator is not done, there must be a header
                throw FetchError.BadAssumptionJS
            }

            guard entry.count == 2 else {
                // There have to be exactly 2 in the array (name and value)
                throw FetchError.BadAssumptionJS
            }

            guard let name = HTTPField.Name(entry[0]) else {
                // The name must be a valid HTTP header name
                throw FetchError.BadAssumptionJS
            }

            responseHeaders.append(.init(name: name, isoLatin1Value: entry[1]))
        }

        return try await responseHandler(
            HTTPResponse(status: .init(code: responseStatus, reasonPhrase: responseStatusText), headerFields: responseHeaders),
            ResponseReader(reader: reader)
        )
    }

    public struct RequestBodyWriter: AsyncWriter, ~Copyable {
        let buffer: RequestBodyBuffer

        public mutating func write<Result, Failure>(
            _ body: nonisolated(nonsending) (inout OutputSpan<UInt8>) async throws(Failure) -> Result
        ) async throws(AsyncStreaming.EitherError<any Error, Failure>) -> Result where Failure: Error {
            do {
                // Each write attempt gets approximately a page of memory to populate with data.
                return try await buffer.array.append(count: 4 * 1024) { span in
                    return try await body(&span)
                }
            } catch {
                throw .first(error)
            }
        }
    }

    public struct ResponseReader: ConcludingAsyncReader, ~Copyable {
        let reader: ReadableStreamDefaultReader

        public consuming func consumeAndConclude<Return, Failure>(
            body: nonisolated(nonsending) (consuming sending FetchHTTPClient.ResponseBodyReader) async throws(Failure) -> Return
        ) async throws(Failure) -> (Return, HTTPTypes.HTTPFields?) where Failure: Error {
            return (try await body(ResponseBodyReader(reader: reader)), nil)
        }
    }

    public struct ResponseBodyReader: AsyncReader, ~Copyable {
        let reader: ReadableStreamDefaultReader
        var buffer = [UInt8]()
        var curIndex = 0

        public mutating func read<Return, Failure>(
            maximumCount: Int?,
            body: nonisolated(nonsending) (consuming Span<UInt8>) async throws(Failure) -> Return
        ) async throws(AsyncStreaming.EitherError<any Error, Failure>) -> Return where Failure: Error {
            if buffer.isEmpty {
                // Read more data in from JS
                let chunk: Chunk
                do {
                    chunk = try await reader.read()
                } catch {
                    throw .first(error)
                }
                if chunk.done {
                    do {
                        return try await body(Span())
                    } catch {
                        throw .second(error)
                    }
                }
                guard let bytes = chunk.value, !bytes.isEmpty else {
                    // If not done, there must be bytes that can be read
                    throw .first(FetchError.BadAssumptionJS)
                }

                buffer = bytes
            }

            let range: Range<Int>
            let numRemainingElements = buffer.count - curIndex
            if let maximumCount, numRemainingElements > maximumCount {
                // There is more data in this buffer than the user wants.
                // Give them a smaller span, update the index
                let endIndex = curIndex + maximumCount
                range = curIndex..<endIndex
                curIndex = endIndex
            } else {
                // Return the rest of the buffer, reset the index
                range = curIndex..<buffer.count
                curIndex = 0
            }

            let result: Return
            do {
                result = try await body(buffer[range].span)
            } catch {
                throw .second(error)
            }

            if range.endIndex == buffer.count {
                // We've read the entire buffer. Clear it out
                buffer.removeAll()
            }

            return result
        }
    }
}
