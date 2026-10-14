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

import AsyncStreaming
import BasicContainers
import HTTPAPIs
import HTTPTypes
import Testing

/// A body reader that delivers `chunks`, one per read, and then `trailers`
/// with an empty chunk.
@available(anyAppleOS 27.0, *)
struct ChunkedBodyReader: AsyncReader, ~Copyable {
    typealias ReadElement = UInt8
    typealias Buffer = UniqueArray<UInt8>
    typealias ReadFailure = Never
    typealias FinalElement = HTTPFields?

    var chunks: [[UInt8]]
    var trailers: HTTPFields?

    mutating func read<Return: ~Copyable, Failure: Error>(
        body: (inout UniqueArray<UInt8>, consuming HTTPFields??) async throws(Failure) -> Return
    ) async throws(EitherError<Never, Failure>) -> Return {
        let chunk = self.chunks.isEmpty ? [] : self.chunks.removeFirst()
        var buffer = UniqueArray<UInt8>(capacity: chunk.count)
        for byte in chunk {
            buffer.append(byte)
        }
        let finalElement: HTTPFields?? = self.chunks.isEmpty && chunk.isEmpty ? .some(self.trailers) : nil
        do {
            return try await body(&buffer, finalElement)
        } catch {
            throw .second(error)
        }
    }
}

@Suite
struct CollectIntoTests {
    @available(anyAppleOS 27.0, *)
    @Test func bodyShorterThanTheBuffer() async throws {
        let reader = ChunkedBodyReader(chunks: [[1, 2], [3]], trailers: [.init("x-trailer")!: "1"])
        var buffer = UniqueArray<UInt8>(capacity: 4)
        let trailers = try await reader.collect(into: &buffer)
        #expect(Array(buffer.span) == [1, 2, 3])
        #expect(trailers == [.init("x-trailer")!: "1"])
    }

    /// A body that fills the buffer exactly is complete: its trailers are
    /// returned.
    @available(anyAppleOS 27.0, *)
    @Test func bodyAsLongAsTheBuffer() async throws {
        let reader = ChunkedBodyReader(chunks: [[1, 2], [3]], trailers: [.init("x-trailer")!: "1"])
        var buffer = UniqueArray<UInt8>(capacity: 3)
        let trailers = try await reader.collect(into: &buffer)
        #expect(Array(buffer.span) == [1, 2, 3])
        #expect(trailers == [.init("x-trailer")!: "1"])
    }

    /// A body longer than the buffer throws, after the bytes that fit.
    @available(anyAppleOS 27.0, *)
    @Test(arguments: [[[1], [2, 3]], [[1, 2], [3]], [[1, 2, 3]]] as [[[UInt8]]])
    func bodyLongerThanTheBuffer(chunks: [[UInt8]]) async throws {
        let reader = ChunkedBodyReader(chunks: chunks, trailers: nil)
        var buffer = UniqueArray<UInt8>(capacity: 2)
        do {
            _ = try await reader.collect(into: &buffer)
            Issue.record("a body longer than the buffer was collected")
        } catch let error as EitherError<Never, AsyncReaderLeftOverElementsError> {
            guard case .second = error else {
                Issue.record("unexpected \(error)")
                return
            }
        }
        #expect(Array(buffer.span) == [1, 2])
    }
}
