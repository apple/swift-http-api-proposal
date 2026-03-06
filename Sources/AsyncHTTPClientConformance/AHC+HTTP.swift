//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift HTTP API Proposal open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift HTTP API Proposal project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift HTTP API Proposal project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

@_spi(ExperimentalHTTPAPIsSupport) public import AsyncHTTPClient
import BasicContainers
import Foundation
public import HTTPAPIs
import HTTPTypes
import NIOCore
import NIOHTTP1
import Synchronization

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, *)
extension AsyncHTTPClient.HTTPClient: HTTPAPIs.HTTPClient {
    public typealias RequestWriter = RequestBodyWriter
    public typealias ResponseConcludingReader = ResponseReader

    public struct RequestOptions: HTTPClientCapability.RequestOptions {

    }

    public struct RequestBodyWriter: AsyncWriter, ~Copyable {
        public typealias WriteElement = UInt8
        public typealias WriteFailure = any Error

        let requestWriter: HTTPClientRequest.Body.RequestWriter
        var byteBuffer: ByteBuffer
        var rigidArray: RigidArray<UInt8>

        init(_ requestWriter: HTTPClientRequest.Body.RequestWriter) {
            self.requestWriter = requestWriter
            self.byteBuffer = ByteBuffer()
            self.byteBuffer.reserveCapacity(2 ^ 16)
            self.rigidArray = RigidArray(capacity: 2 ^ 16)  // ~ 65k bytes
        }

        public mutating func write<Result, Failure>(
            _ body: (inout OutputSpan<UInt8>) async throws(Failure) -> Result
        ) async throws(AsyncStreaming.EitherError<WriteFailure, Failure>) -> Result where Failure: Error {
            let result: Result
            do {
                // TODO: rigidArray needs a clear all
                self.rigidArray.removeAll()
                self.rigidArray.reserveCapacity(1024)
                result = try await self.rigidArray.append(count: 1024) { (span) async throws(Failure) -> Result in
                    try await body(&span)
                }

                if self.rigidArray.isEmpty {
                    return result
                }
            } catch {
                throw .second(error)
            }

            do {
                self.byteBuffer.clear()

                // we need to use an uninitilized helper rigidarray here to make the compiler happy
                // with regards overlapping memory access.
                var localArray = RigidArray<UInt8>(capacity: 0)
                swap(&localArray, &self.rigidArray)
                unsafe self.byteBuffer.writeBytes(localArray.span.bytes)
                swap(&localArray, &self.rigidArray)
                try await self.requestWriter.writeRequestBodyPart(self.byteBuffer)
            } catch {
                throw .first(error)
            }

            return result
        }
    }

    public struct ResponseReader: ConcludingAsyncReader {
        public typealias Underlying = ResponseBodyReader

        let underlying: HTTPClientResponse.Body

        public typealias FinalElement = HTTPFields?

        init(underlying: HTTPClientResponse.Body) {
            self.underlying = underlying
        }

        public consuming func consumeAndConclude<Return, Failure>(
            body: (consuming sending ResponseBodyReader) async throws(Failure) -> Return
        ) async throws(Failure) -> (Return, HTTPFields?) where Failure: Error {
            let iterator = self.underlying.makeAsyncIterator()
            let reader = ResponseBodyReader(underlying: iterator)
            let returnValue = try await body(reader)

            let t = self.underlying.trailers?.compactMap {
                if let name = HTTPField.Name($0.name) {
                    HTTPField(name: name, value: $0.value)
                } else {
                    nil
                }
            }
            return (returnValue, t.flatMap({ HTTPFields($0) }))
        }
    }

    public struct ResponseBodyReader: AsyncReader, ~Copyable {
        public typealias ReadElement = UInt8
        public typealias ReadFailure = any Error

        var underlying: HTTPClientResponse.Body.AsyncIterator
        var out = RigidArray<UInt8>()
        var readerIndex = 0

        public mutating func read<Return, Failure>(
            maximumCount: Int?,
            body: (consuming Span<UInt8>) async throws(Failure) -> Return
        ) async throws(AsyncStreaming.EitherError<ReadFailure, Failure>) -> Return where Failure: Error {
            do {
                // if have enough data for the read request available, hand it to the user right away
                if let maximumCount, maximumCount <= self.out.count - self.readerIndex {
                    defer {
                        self.readerIndex += maximumCount
                        self.reallocateIfNeeded()
                    }
                    return try await body(self.out.span.extracting(self.readerIndex..<(self.readerIndex + maximumCount)))
                }

                // we have data remaining in the local buffer. hand that to the user next.
                if self.readerIndex < self.out.count {
                    defer {
                        self.readerIndex = self.out.count
                        self.reallocateIfNeeded()
                    }
                    return try await body(self.out.span.extracting(self.readerIndex..<self.out.count))
                }

                // we don't have enough data
                let buffer = try await self.underlying.next(isolation: #isolation)
                guard let buffer else {  // eof received
                    let array = InlineArray<0, UInt8> { _ in }
                    return try await body(array.span)
                }

                let readLength = maximumCount != nil ? min(maximumCount!, buffer.readableBytes) : buffer.readableBytes
                self.out.reserveCapacity(self.out.count + buffer.readableBytes)
                let alreadyRead = self.out.count
                unsafe buffer.withUnsafeReadableBytes { rawBufferPtr in
                    let usbptr = unsafe rawBufferPtr.assumingMemoryBound(to: UInt8.self)
                    unsafe self.out.append(copying: usbptr)
                }
                defer {
                    self.readerIndex = alreadyRead + readLength
                    self.reallocateIfNeeded()
                }
                return try await body(self.out.span.extracting(alreadyRead..<(alreadyRead + readLength)))
            } catch let error as Failure {
                throw .second(error)
            } catch {
                throw .first(error)
            }
        }

        private mutating func reallocateIfNeeded() {
            guard self.readerIndex > 2 ^ 16 else {
                return
            }

            let newCapacity = max(self.out.count - self.readerIndex, 2 ^ 16)

            self.out = RigidArray<UInt8>(capacity: newCapacity) {
                // this is probably super slow.
                for i in self.readerIndex..<self.out.count {
                    $0.append(self.out[i])
                }
            }
            self.readerIndex = 0
        }
    }

    public var defaultRequestOptions: RequestOptions {
        RequestOptions()
    }

    public func perform<Return: ~Copyable>(
        request: HTTPRequest,
        body: consuming HTTPClientRequestBody<RequestBodyWriter>?,
        options: RequestOptions,
        responseHandler: (HTTPResponse, consuming ResponseReader) async throws -> Return
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
                            let writer = RequestWriter(ahcWriter)
                            let maybeTrailers = try await body.produce(into: writer)
                            let trailers: HTTPHeaders? =
                                if let trailers = maybeTrailers {
                                    HTTPHeaders(.init(trailers.lazy.map({ ($0.name.rawName, $0.value) })))
                                } else {
                                    nil
                                }
                            ahcWriter.requestBodyStreamFinished(trailers: trailers)
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

                result = .success(try await responseHandler(response, .init(underlying: ahcResponse.body)))
            } catch {
                result = .failure(error)
            }
        }

        return try result!.get()
    }
}
