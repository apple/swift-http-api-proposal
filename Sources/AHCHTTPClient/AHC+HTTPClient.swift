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

@_spi(ExperimentalHTTPAPIsSupport) public import AsyncHTTPClient
public import BasicContainers
import Foundation
@_exported public import HTTPAPIs
import HTTPTypes
import NIOCore
import NIOHTTP1
import Synchronization

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, *)
extension AsyncHTTPClient.HTTPClient: HTTPAPIs.HTTPClient {
    public typealias Writer = RequestBodyWriter
    public typealias Reader = ResponseBodyReader

    public struct RequestOptions: HTTPClientCapability.RequestOptions {

    }

    public struct RequestBodyWriter: HTTPBodyWriter, ~Copyable {
        public typealias WriteElement = UInt8
        public typealias WriteFailure = any Error
        // TODO: This should become InputSpan most likely once spans conform to the container protocols
        public typealias Buffer = UniqueArray<UInt8>

        let requestWriter: HTTPClientRequest.Body.RequestWriter
        var byteBuffer: ByteBuffer
        var buffer: UniqueArray<UInt8>?

        init(_ requestWriter: HTTPClientRequest.Body.RequestWriter) {
            self.requestWriter = requestWriter
            self.byteBuffer = ByteBuffer()
            self.byteBuffer.reserveCapacity(2 << 16)
            self.buffer = UniqueArray(minimumCapacity: 2 << 16)
        }

        public mutating func write<Return: ~Copyable, Failure>(
            _ body: (inout UniqueArray<UInt8>) async throws(Failure) -> Return
        ) async throws(AsyncStreaming.EitherError<WriteFailure, Failure>) -> Return where Failure: Error {
            let result: Return
            // This force-unwrap is safe since there can only be one concurrent write
            var buffer = self.buffer.take()!
            do {
                result = try await body(&buffer)
            } catch {
                buffer.removeAll()
                self.buffer = consume buffer
                throw .second(error)
            }
            if buffer.count == 0 {
                self.buffer = consume buffer
                return result
            }

            do {
                self.byteBuffer.clear()
                unsafe self.byteBuffer.writeBytes(buffer.span.bytes)
                buffer.removeAll()
                self.buffer = consume buffer
                try await self.requestWriter.writeRequestBodyPart(self.byteBuffer)
            } catch {
                throw .first(error)
            }

            return result
        }

        public consuming func finish<Failure: Error>(
            body: (inout UniqueArray<UInt8>) async throws(Failure) -> HTTPFields?
        ) async throws(AsyncStreaming.EitherError<any Error, Failure>) {
            var buffer = self.buffer.take()!
            let trailers: HTTPFields?
            do {
                trailers = try await body(&buffer)
            } catch {
                throw .second(error)
            }
            if buffer.count > 0 {
                do {
                    self.byteBuffer.clear()
                    unsafe self.byteBuffer.writeBytes(buffer.span.bytes)
                    try await self.requestWriter.writeRequestBodyPart(self.byteBuffer)
                } catch {
                    throw .first(error)
                }
            }
            let ahcTrailers: HTTPHeaders? =
                if let trailers {
                    HTTPHeaders(.init(trailers.lazy.map({ ($0.name.rawName, $0.value) })))
                } else {
                    nil
                }
            self.requestWriter.requestBodyStreamFinished(trailers: ahcTrailers)
        }
    }

    public struct ResponseBodyReader: HTTPBodyReader, ~Copyable {
        public typealias ReadElement = UInt8
        public typealias ReadFailure = any Error
        public typealias Buffer = UniqueArray<UInt8>

        var underlying: HTTPClientResponse.Body.AsyncIterator
        var body: HTTPClientResponse.Body
        var buffer = UniqueArray<UInt8>()
        var trailersDelivered: Bool = false

        init(body: HTTPClientResponse.Body) {
            self.body = body
            self.underlying = body.makeAsyncIterator()
        }

        public mutating func read<Return: ~Copyable, Failure>(
            body: (inout UniqueArray<UInt8>, HTTPFields?) async throws(Failure) -> Return
        ) async throws(AsyncStreaming.EitherError<ReadFailure, Failure>) -> Return where Failure: Error {
            var trailers: HTTPFields? = nil

            if !self.trailersDelivered {
                let byteBuffer: ByteBuffer?
                do {
                    byteBuffer = try await self.underlying.next(isolation: #isolation)
                } catch {
                    throw .first(error)
                }

                if let byteBuffer, byteBuffer.readableBytes > 0 {
                    self.buffer.reserveCapacity(byteBuffer.readableBytes)
                    unsafe byteBuffer.withUnsafeReadableBytes { rawBufferPtr in
                        let usbptr = unsafe rawBufferPtr.assumingMemoryBound(to: UInt8.self)
                        unsafe self.buffer.append(copying: usbptr)
                    }
                }

                if byteBuffer == nil {
                    self.trailersDelivered = true
                    let collected = self.body.trailers?.compactMap {
                        if let name = HTTPField.Name($0.name) {
                            HTTPField(name: name, value: $0.value)
                        } else {
                            nil
                        }
                    }
                    trailers = collected.flatMap { HTTPFields($0) } ?? HTTPFields()
                }
            }

            do {
                return try await body(&self.buffer, trailers)
            } catch {
                throw .second(error)
            }
        }
    }

    public var defaultRequestOptions: RequestOptions {
        RequestOptions()
    }

    public func perform<Return: ~Copyable>(
        request: HTTPRequest,
        body: consuming HTTPClientRequestBody<RequestBodyWriter>?,
        options: RequestOptions,
        responseHandler: (HTTPResponse, consuming ResponseBodyReader) async throws -> Return
    ) async throws -> Return {
        guard let url = request.url else {
            fatalError()
        }

        var result: Result<Return, any Error>?
        await withTaskGroup(of: Void.self) { taskGroup in

            var ahcRequest = HTTPClientRequest(url: url.absoluteString)
            ahcRequest.method = .init(rawValue: request.method.rawValue)
            if !request.headerFields.isEmpty {
                let sequence = request.headerFields.lazy.map({ ($0.name.rawName, $0.value) })
                ahcRequest.headers.add(contentsOf: sequence)
            }

            if let body, body.knownLength != 0 {
                let (asyncStream, startUploadContinuation) = AsyncStream.makeStream(of: HTTPClientRequest.Body.RequestWriter.self)

                taskGroup.addTask {
                    // TODO: We might want to allow multiple body restarts here.

                    for await ahcWriter in asyncStream {
                        do {
                            let writer = RequestBodyWriter(ahcWriter)
                            try await body.produce(into: writer)
                            // writer.finish already calls requestBodyStreamFinished
                            break  // the loop
                        } catch let error {
                            // if we fail because the user throws in upload, we have to cancel the
                            // upload and fail the request I guess.
                            ahcWriter.fail(error)
                        }
                    }
                }

                ahcRequest.body = .init(length: body.knownLength, startUpload: startUploadContinuation)
            }

            do {
                let ahcResponse = try await self.execute(ahcRequest, timeout: .seconds(30))

                var responseFields = HTTPFields()
                for (name, value) in ahcResponse.headers {
                    if let name = HTTPField.Name(name) {
                        // Add a new header field
                        responseFields.append(.init(name: name, value: value))
                    }
                }

                let response = HTTPResponse(
                    status: .init(code: Int(ahcResponse.status.code)),
                    headerFields: responseFields
                )

                result = .success(try await responseHandler(response, ResponseBodyReader(body: ahcResponse.body)))
            } catch {
                result = .failure(error)
            }
        }

        return try result!.get()
    }
}
