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
import BasicContainers
import Testing

@Suite
struct AsyncReaderTests {
    @Test
    @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
    func readWithMaximumCount() async {
        var reader = SimpleReader(data: [1, 2, 3, 4, 5])

        let result = try! await reader.read(maximumCount: 3) { span in
            return Array(span)
        }

        #expect(result == [1, 2, 3])
    }

    @Test
    @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
    func readWithoutMaximumCount() async {
        var reader = SimpleReader(data: [1, 2, 3, 4, 5])

        let result = try! await reader.read(maximumCount: nil) { span in
            return Array(span)
        }

        #expect(result == [1, 2, 3, 4, 5])
    }

    @Test
    @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
    func readEmptySpanAtEnd() async {
        var reader = SimpleReader(data: [1, 2, 3])

        // Read all data
        _ = try! await reader.read(maximumCount: nil) { span in
            return Array(span)
        }

        // Next read should return empty span
        let result = try! await reader.read(maximumCount: nil) { span in
            return span.count
        }

        #expect(result == 0)
    }

    @Test
    @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
    func readMultipleChunks() async {
        var reader = SimpleReader(data: [1, 2, 3, 4, 5, 6])
        var chunks: [[Int]] = []

        while true {
            let chunk = try! await reader.read(maximumCount: 2) { span in
                return Array(span)
            }
            if chunk.isEmpty {
                break
            }
            chunks.append(chunk)
        }

        #expect(chunks == [[1, 2], [3, 4], [5, 6]])
    }

    @Test
    @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
    func readIntoCopyableElements() async {
        var reader = SimpleReader(data: [1, 2, 3, 4, 5])
        var buffer = RigidArray<Int>()
        buffer.reserveCapacity(5)

        await buffer.append(count: 5) { outputSpan in
            await reader.read(into: &outputSpan)
        }

        #expect(buffer.count == 5)
    }
}
