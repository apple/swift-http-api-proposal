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

import AsyncStreaming
import Testing

@Suite
struct ConcludingAsyncWriterTests {
    @Test
    @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
    func produceAndConcludeReturnsResult() async throws {
        let writer = TestConcludingWriter()

        let result = try await writer.produceAndConclude { writer in
            var writer = writer
            await writer.write(1)
            await writer.write(2)
            await writer.write(3)
            return (writer.storage, "completed")
        }

        #expect(result == [1, 2, 3])
    }

    @Test
    @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
    func produceAndConcludeWithFinalElementOnly() async throws {
        let writer = TestConcludingWriter()

        try await writer.produceAndConclude { writer in
            var writer = writer
            await writer.write(10)
            await writer.write(20)
            return "finished"
        }

        // Test passes if no error is thrown
    }

    @Test
    @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
    func writeAndConcludeWithSingleElement() async throws {
        let writer = TestConcludingWriter()

        try await writer.writeAndConclude(42, finalElement: "done")

        // Test passes if no error is thrown
    }

    @Test
    @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
    func writeAndConcludeWithSpan() async throws {
        let writer = TestConcludingWriter()
        let data = [1, 2, 3, 4, 5]

        try await writer.writeAndConclude(data.span, finalElement: "completed")

        // Test passes if no error is thrown
    }

    @Test
    @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
    func writeAndConcludeWithEmptySpan() async throws {
        let writer = TestConcludingWriter()
        let data: [Int] = []

        try await writer.writeAndConclude(data.span, finalElement: "empty")

        // Test passes if no error is thrown
    }

    @Test
    @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
    func multipleWritesBeforeConclude() async throws {
        let writer = TestConcludingWriter()

        let result = try await writer.produceAndConclude { writer in
            var writer = writer

            try await writer.write { outputSpan in
                outputSpan.append(1)
                outputSpan.append(2)
            }

            try await writer.write { outputSpan in
                outputSpan.append(3)
                outputSpan.append(4)
            }

            return (writer.storage, "done")
        }

        #expect(result == [1, 2, 3, 4])
    }

    @Test
    @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
    func produceAndConcludeWithNoWrites() async throws {
        let writer = TestConcludingWriter()

        let result = try await writer.produceAndConclude { writer in
            return (writer.storage, "no writes")
        }

        #expect(result == [])
    }
}
