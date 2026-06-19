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

@available(anyAppleOS 26.0, *)
extension AsyncHTTPClient.HTTPClient: HTTPAPIs.HTTPClient {
    public struct RequestOptions: HTTPClientCapability.RequestOptions {

    }

    public struct Writer: CallerAsyncWriter, ~Copyable {
        public typealias WriteElement = UInt8
        public typealias WriteFailure = any Error
        public typealias FinalElement = HTTPFields?

        let requestWriter: HTTPClientRequest.Body.RequestWriter
        var byteBuffer: ByteBuffer

        init(_ requestWriter: HTTPClientRequest.Body.RequestWriter) {
            self.requestWriter = requestWriter
            self.byteBuffer = ByteBuffer()
            self.byteBuffer.reserveCapacity(1 << 16)
        }

        public mutating func write<Buffer: RangeReplaceableContainer<UInt8> & ~Copyable>(
            buffer: inout Buffer
        ) async throws(WriteFailure) where Buffer.Element: ~Copyable {
            guard buffer.count > 0 else { return }
            self.byteBuffer.clear()
            var consumer = buffer.consumeAll()
            // `while !done { ... }` instead of `while true { ... break }` to
            // dodge a SIL ownership-verifier crash on the nightly main
            // toolchain (https://github.com/swiftlang/swift/issues/89639).
            var done = false
            while !done {
                let span = consumer.drainNext()
                if span.isEmpty {
                    done = true
                } else {
                    self.byteBuffer.writeBytes(span.span.bytes)
                }
            }
            try await self.requestWriter.writeRequestBodyPart(self.byteBuffer)
        }

        public consuming func finish<Buffer: RangeReplaceableContainer<UInt8> & ~Copyable>(
            buffer: inout Buffer,
            finalElement: consuming HTTPFields?
        ) async throws(WriteFailure) where Buffer.Element: ~Copyable {
            if buffer.count > 0 {
                self.byteBuffer.clear()
                var consumer = buffer.consumeAll()
                // See note in `write(buffer:)`.
                var done = false
                while !done {
                    let span = consumer.drainNext()
                    if span.isEmpty {
                        done = true
                    } else {
                        self.byteBuffer.writeBytes(span.span.bytes)
                    }
                }
                try await self.requestWriter.writeRequestBodyPart(self.byteBuffer)
            }
            let ahcTrailers: HTTPHeaders? =
                if let finalElement {
                    HTTPHeaders(.init(finalElement.lazy.map({ ($0.name.rawName, $0.value) })))
                } else {
                    nil
                }
            self.requestWriter.requestBodyStreamFinished(trailers: ahcTrailers)
        }
    }

    public struct Reader: AsyncReader, ~Copyable {
        public typealias ReadElement = UInt8
        public typealias ReadFailure = any Error
        public typealias Buffer = UniqueArray<UInt8>
        public typealias FinalElement = HTTPFields?

        var underlying: HTTPClientResponse.Body.AsyncIterator
        var body: HTTPClientResponse.Body
        var buffer = UniqueArray<UInt8>()
        var trailersDelivered: Bool = false

        public init(body: HTTPClientResponse.Body) {
            self.body = body
            self.underlying = body.makeAsyncIterator()
        }

        public mutating func read<Return: ~Copyable, Failure>(
            body: (inout UniqueArray<UInt8>, consuming HTTPFields??) async throws(Failure) -> Return
        ) async throws(AsyncStreaming.EitherError<ReadFailure, Failure>) -> Return where Failure: Error {
            var finalElement: HTTPFields?? = nil

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
                    finalElement = .some(collected.flatMap { HTTPFields($0) })
                }
            }

            do {
                return try await body(&self.buffer, finalElement)
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
        body: consuming HTTPClientRequestBody<Writer>?,
        options: RequestOptions,
        responseHandler: (HTTPResponse, consuming Reader) async throws -> Return
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
                            let writer = Writer(ahcWriter)
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

                result = .success(try await responseHandler(response, Reader(body: ahcResponse.body)))
            } catch {
                result = .failure(error)
            }
        }

        return try result!.get()
    }
}
