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
import Synchronization

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
final class URLSessionRequestStreamBridge: NSObject, StreamDelegate, Sendable {
    private weak let task: URLSessionTask?

    private struct LockedState {
        let inputStream: InputStream
        let outputStream: OutputStream
        var spaceContinuation: CheckedContinuation<Void, any Error>?
        var outputStreamOpened: Bool = false
        var writeFailed: Bool = false
    }

    private let lockedState: Mutex<LockedState>

    private static let streamQueue: DispatchQueue = .init(label: "HTTPClientRequestBody")

    init(task: URLSessionTask) {
        self.task = task
        var inputStream: InputStream? = nil
        var outputStream: OutputStream? = nil
        unsafe Stream.getBoundStreams(
            withBufferSize: 128 * 1024,
            inputStream: &inputStream,
            outputStream: &outputStream
        )
        self.lockedState = .init(.init(inputStream: inputStream!, outputStream: outputStream!))

        super.init()
    }

    var inputStream: InputStream {
        self.lockedState.withLock(\.inputStream)
    }

    var writeFailed: Bool {
        self.lockedState.withLock(\.writeFailed)
    }

    func write(_ span: Span<UInt8>) async throws {
        self.lockedState.withLock { state in
            if !state.outputStreamOpened {
                state.outputStreamOpened = true
                unsafe state.outputStream.delegate = self
                CFWriteStreamSetDispatchQueue(
                    state.outputStream as CFWriteStream,
                    Self.streamQueue
                )
                state.outputStream.open()
            }
        }
        var remaining = span
        while !remaining.isEmpty {
            try Task.checkCancellation()
            try await self.waitForSpace()
            let written = try self.lockedState.withLock { state in
                let written = unsafe remaining.withUnsafeBufferPointer { buffer in
                    unsafe state.outputStream.write(buffer.baseAddress!, maxLength: buffer.count)
                }
                if written < 0 {
                    state.writeFailed = true
                    throw state.outputStream.streamError ?? CancellationError()
                }
                return written
            }
            remaining = remaining.extracting(droppingFirst: written)
        }
    }

    private func waitForSpace() async throws {
        while !self.lockedState.withLock({ $0.outputStream.hasSpaceAvailable }) {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    self.lockedState.withLock {
                        $0.spaceContinuation = continuation
                    }
                }
            } onCancel: {
                self.task?.cancel()
                let continuation = self.lockedState.withLock { state in
                    defer { state.spaceContinuation = nil }
                    return state.spaceContinuation
                }
                continuation?.resume(throwing: CancellationError())
            }
        }
    }

    func close() {
        self.lockedState.withLock { state in
            state.outputStream.close()
        }
    }

    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        if eventCode.contains(.hasSpaceAvailable) {
            let continuation = self.lockedState.withLock { state in
                defer { state.spaceContinuation = nil }
                return state.spaceContinuation
            }
            continuation?.resume()
        }
        if eventCode.contains(.errorOccurred) || eventCode.contains(.endEncountered) {
            let continuation = self.lockedState.withLock { state in
                defer { state.spaceContinuation = nil }
                return state.spaceContinuation
            }
            continuation?.resume(throwing: aStream.streamError ?? CancellationError())
        }
    }
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
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
        self.close()
        return try result.get()
    }
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
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
