//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift HTTP API Proposal open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift HTTP API Proposal project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift HTTP API Proposal project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

#if canImport(Darwin)
import HTTPAPIs
import BasicContainers
import Foundation

// TODO: Can we get rid of this actor
@globalActor actor RequestBodyActor: GlobalActor {
    static let shared = RequestBodyActor()
}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
@RequestBodyActor
final class URLSessionRequestStreamBridge: NSObject, StreamDelegate, @unchecked Sendable {
    let inputStream: InputStream
    private let outputStream: OutputStream
    private var spaceContinuation: CheckedContinuation<Void, Never>?
    private var outputStreamOpened: Bool = false
    var writeFailed: Bool = false

    override init() {
        var inputStream: InputStream? = nil
        var outputStream: OutputStream? = nil
        unsafe Stream.getBoundStreams(
            withBufferSize: 128 * 1024,
            inputStream: &inputStream,
            outputStream: &outputStream
        )
        self.inputStream = inputStream!
        self.outputStream = outputStream!

        super.init()
    }

    func write(_ span: Span<UInt8>) async throws {
        if !self.outputStreamOpened {
            self.outputStreamOpened = true
            unsafe self.outputStream.delegate = self
            CFWriteStreamSetDispatchQueue(
                self.outputStream as CFWriteStream,
                DispatchQueue(label: "HTTPClientRequestBody")
            )
            self.outputStream.open()
        }
        var remaining = span
        while !remaining.isEmpty {
            try Task.checkCancellation()
            await self.waitForSpace()
            let written = unsafe remaining.withUnsafeBufferPointer { buffer in
                unsafe self.outputStream.write(buffer.baseAddress!, maxLength: buffer.count)
            }
            if written < 0 {
                self.writeFailed = true
                throw self.outputStream.streamError ?? CancellationError()
            }
            remaining = remaining.extracting(droppingFirst: written)
        }
    }

    private func waitForSpace() async {
        if self.outputStream.hasSpaceAvailable {
            return
        }
        while !self.outputStream.hasSpaceAvailable {
            // TODO: This is not handling cancellation appropriately
            await withCheckedContinuation { continuation in
                self.spaceContinuation = continuation
            }
        }
    }

    func close() {
        self.outputStream.close()
    }

    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        if eventCode.contains(.hasSpaceAvailable) {
            // TODO: Can we get rid of this task and instead use one task group
            // for the entire client
            Task.immediate {
                let continuation = self.spaceContinuation
                self.spaceContinuation = nil
                continuation?.resume()
            }
        }
    }
}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension URLSessionRequestStreamBridge: ConcludingAsyncWriter {
    func produceAndConclude<Return>(
        body:
            (consuming sending URLSessionRequestStreamBridge) async throws -> (Return, HTTPFields?)
    ) async throws -> Return {
        let result: Result<Return, any Error>
        do {
            result = .success(try await body(self).0)
        } catch {
            result = .failure(error)
        }
        await self.close()
        return try result.get()
    }
}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension URLSessionRequestStreamBridge: AsyncWriter {
    func write<Result, Failure: Error>(
        _ body: (inout OutputSpan<UInt8>) async throws(Failure) -> Result
    ) async throws(EitherError<any Error, Failure>) -> Result {
        // TODO: Either this needs to be inline or configurable
        var array = RigidArray<UInt8>(capacity: 1024)
        do {
            let result = try await array.append(count: 1024) { outputSpan in
                try await body(&outputSpan)
            }
            try await self.write(array.span)
            return result
        } catch let error as Failure {
            throw .second(error)
        } catch {
            throw .first(error)
        }
    }
}
#endif
