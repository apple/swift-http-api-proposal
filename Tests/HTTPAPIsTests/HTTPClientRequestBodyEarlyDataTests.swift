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
import Synchronization
import Testing

/// What a body wrote: the offsets it was produced from and the byte count.
@available(anyAppleOS 27.0, *)
final class BodyLog: Sendable {
    private let state = Mutex<(offsets: [Int64], byteCount: Int)>(([], 0))

    var offsets: [Int64] { self.state.withLock { $0.offsets } }
    var byteCount: Int { self.state.withLock { $0.byteCount } }

    func produced(from offset: Int64) {
        self.state.withLock { $0.offsets.append(offset) }
    }

    func wrote(_ count: Int) {
        self.state.withLock { $0.byteCount += count }
    }
}

/// A writer that counts the bytes written to it.
@available(anyAppleOS 27.0, *)
struct CountingBodyWriter: CallerAsyncWriter, ~Copyable {
    typealias WriteElement = UInt8
    typealias WriteFailure = Never
    typealias FinalElement = HTTPFields?

    let log: BodyLog

    mutating func write<Buffer: RangeReplaceableContainer<UInt8> & ~Copyable>(
        buffer: inout Buffer
    ) async where Buffer.Element: ~Copyable {
        self.log.wrote(buffer.count)
        buffer.removeAll()
    }

    consuming func finish<Buffer: RangeReplaceableContainer<UInt8> & ~Copyable>(
        buffer: inout Buffer,
        finalElement: consuming HTTPFields?
    ) async where Buffer.Element: ~Copyable {
        self.log.wrote(buffer.count)
        buffer.removeAll()
    }
}

/// A writer of another type over ``CountingBodyWriter``, for mapped bodies.
@available(anyAppleOS 27.0, *)
struct WrappingBodyWriter: CallerAsyncWriter, ~Copyable {
    typealias WriteElement = UInt8
    typealias WriteFailure = Never
    typealias FinalElement = HTTPFields?

    var base: CountingBodyWriter

    mutating func write<Buffer: RangeReplaceableContainer<UInt8> & ~Copyable>(
        buffer: inout Buffer
    ) async where Buffer.Element: ~Copyable {
        await self.base.write(buffer: &buffer)
    }

    consuming func finish<Buffer: RangeReplaceableContainer<UInt8> & ~Copyable>(
        buffer: inout Buffer,
        finalElement: consuming HTTPFields?
    ) async where Buffer.Element: ~Copyable {
        await self.base.finish(buffer: &buffer, finalElement: finalElement)
    }
}

/// A seekable body of `length` bytes whose early data is its first
/// `earlyLength` bytes (nil: none).
@available(anyAppleOS 27.0, *)
func makeSeekableBody(length: Int, earlyLength: Int?, log: BodyLog) -> HTTPClientRequestBody<CountingBodyWriter> {
    var earlyData: (@Sendable () async -> HTTPEarlyData?)? = nil
    if let earlyLength {
        earlyData = { HTTPEarlyData(bytes: Array(repeating: 0, count: earlyLength), isComplete: earlyLength == length) }
    }
    return .seekable(knownLength: Int64(length), earlyData: earlyData) { offset, writer in
        log.produced(from: offset)
        var writer = writer
        var buffer = UniqueArray<UInt8>(capacity: length - Int(offset))
        for _ in offset..<Int64(length) {
            buffer.append(0)
        }
        try await writer.finish(buffer: &buffer, finalElement: nil)
    }
}

/// Sends `body` the way a client that supports early data does.
///
/// The early data goes first, then the rest of the body from its end, unless
/// the early data was the whole body. Returns the early data's byte count.
@available(anyAppleOS 27.0, *)
func send(_ body: HTTPClientRequestBody<CountingBodyWriter>, log: BodyLog) async throws -> Int {
    guard let earlyData = await body.earlyData?() else {
        try await body.produce(into: CountingBodyWriter(log: log))
        return 0
    }
    if !earlyData.isComplete {
        try await body.produce(offset: Int64(earlyData.bytes.count), into: CountingBodyWriter(log: log))
    }
    return earlyData.bytes.count
}

@Suite
struct HTTPClientRequestBodyEarlyDataTests {
    @available(anyAppleOS 27.0, *)
    @Test func noEarlyDataByDefault() {
        let restartable = HTTPClientRequestBody<CountingBodyWriter>.restartable { _ in }
        let seekable = HTTPClientRequestBody<CountingBodyWriter>.seekable { _, _ in }
        #expect(restartable.earlyData == nil)
        #expect(seekable.earlyData == nil)
    }

    /// Early data that's the start of the body: the rest is produced from
    /// its end.
    @available(anyAppleOS 27.0, *)
    @Test func partialEarlyData() async throws {
        let log = BodyLog()
        let earlyCount = try await send(makeSeekableBody(length: 10, earlyLength: 4, log: log), log: log)
        #expect(earlyCount == 4)
        #expect(log.offsets == [4])
        #expect(log.byteCount == 6)
    }

    /// Early data that's the whole body: nothing else is produced.
    @available(anyAppleOS 27.0, *)
    @Test func completeEarlyData() async throws {
        let log = BodyLog()
        let earlyCount = try await send(makeSeekableBody(length: 10, earlyLength: 10, log: log), log: log)
        #expect(earlyCount == 10)
        #expect(log.offsets.isEmpty)
        #expect(log.byteCount == 0)
    }

    /// A body without early data available is produced from the start.
    @available(anyAppleOS 27.0, *)
    @Test func earlyDataUnavailable() async throws {
        let log = BodyLog()
        let body = HTTPClientRequestBody<CountingBodyWriter>.seekable(
            knownLength: 3,
            earlyData: { nil },
            { offset, writer in
                log.produced(from: offset)
                var writer = writer
                var buffer = UniqueArray<UInt8>(capacity: 3)
                for _ in 0..<3 {
                    buffer.append(0)
                }
                try await writer.finish(buffer: &buffer, finalElement: nil)
            }
        )
        let earlyCount = try await send(body, log: log)
        #expect(earlyCount == 0)
        #expect(log.offsets == [0])
        #expect(log.byteCount == 3)
    }

    /// A body mapped to another writer keeps its early data.
    @available(anyAppleOS 27.0, *)
    @Test func mappedBodyKeepsEarlyData() async throws {
        let log = BodyLog()
        let body = makeSeekableBody(length: 10, earlyLength: 4, log: log)
        let mapped = HTTPClientRequestBody<WrappingBodyWriter>(other: body) { $0.base }
        let earlyData = await mapped.earlyData?()
        #expect(earlyData == HTTPEarlyData(bytes: [0, 0, 0, 0], isComplete: false))
        try await mapped.produce(offset: 4, into: WrappingBodyWriter(base: CountingBodyWriter(log: log)))
        #expect(log.offsets == [4])
        #expect(log.byteCount == 6)
    }
}
