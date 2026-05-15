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
    var trailers: HTTPFields? = nil
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
    public typealias Writer = RequestBodyWriter
    public typealias Reader = ResponseBodyReader

    public struct RequestOptions: HTTPClientCapability.RequestOptions, Sendable {
        public init() {}
    }

    public let defaultRequestOptions: RequestOptions = RequestOptions()

    public init() {}

    public func perform<Return>(
        request: HTTPTypes.HTTPRequest,
        body: consuming HTTPAPIs.HTTPClientRequestBody<RequestBodyWriter>?,
        options: RequestOptions,
        responseHandler: nonisolated(nonsending) (HTTPTypes.HTTPResponse, consuming ResponseBodyReader) async throws -> Return
    ) async throws -> Return where Return: ~Copyable {
        guard let url = request.url else {
            throw FetchError.BadURL
        }

        var jsBody: JSObject? = nil

        if let body = body {
            let buffer = RequestBodyBuffer()
            let writer = RequestBodyWriter(buffer: buffer)
            try await body.produce(into: writer)
            if buffer.trailers != nil {
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
            ResponseBodyReader(reader: reader)
        )
    }

    public struct RequestBodyWriter: HTTPBodyWriter, ~Copyable {
        public typealias WriteElement = UInt8
        public typealias WriteFailure = any Error
        public typealias Buffer = UniqueArray<UInt8>

        let buffer: RequestBodyBuffer

        public mutating func write<Return: ~Copyable, Failure>(
            _ body: nonisolated(nonsending) (inout UniqueArray<UInt8>) async throws(Failure) -> Return
        ) async throws(AsyncStreaming.EitherError<any Error, Failure>) -> Return where Failure: Error {
            let result: Return
            do {
                result = try await body(&self.buffer.array)
            } catch {
                throw .second(error)
            }
            return result
        }

        public consuming func finish<Failure: Error>(
            body: nonisolated(nonsending) (inout UniqueArray<UInt8>) async throws(Failure) -> HTTPFields?
        ) async throws(AsyncStreaming.EitherError<any Error, Failure>) {
            let trailer: HTTPFields?
            do {
                trailers = try await body(&self.buffer.array)
            } catch {
                throw .second(error)
            }
            self.buffer.trailers = trailers
        }
    }

    public struct ResponseBodyReader: HTTPBodyReader, ~Copyable {
        public typealias ReadElement = UInt8
        public typealias ReadFailure = any Error
        public typealias Buffer = UniqueArray<UInt8>

        let reader: ReadableStreamDefaultReader
        var buffer = UniqueArray<UInt8>()
        var trailersDelivered: Bool = false

        public mutating func read<Return: ~Copyable, Failure>(
            body: nonisolated(nonsending) (inout UniqueArray<UInt8>, HTTPFields?) async throws(Failure) -> Return
        ) async throws(AsyncStreaming.EitherError<any Error, Failure>) -> Return where Failure: Error {
            var trailers: HTTPFields? = nil

            if !self.trailersDelivered {
                let chunk: Chunk
                do {
                    chunk = try await self.reader.read()
                } catch {
                    throw .first(error)
                }
                if !chunk.done {
                    guard let bytes = chunk.value, !bytes.isEmpty else {
                        throw .first(FetchError.BadAssumptionJS)
                    }
                    self.buffer.reserveCapacity(bytes.count)
                    for b in bytes {
                        self.buffer.append(b)
                    }
                } else {
                    // The fetch API does not surface trailers, so signal end of body
                    // with empty trailers.
                    self.trailersDelivered = true
                    trailers = HTTPFields()
                }
            }

            do {
                return try await body(&self.buffer, trailers)
            } catch {
                throw .second(error)
            }
        }
    }
}
