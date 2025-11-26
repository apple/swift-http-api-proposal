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
struct ConcludingAsyncReaderTests {
    @Test
    @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
    func consumeAndConcludeReturnsResult() async throws {
        let reader = TestConcludingReader(data: [1, 2, 3, 4, 5])

        let (result, finalElement) = await reader.consumeAndConclude { reader in
            let reader = reader
            var sum = 0
            await reader.forEach { span in
                for i in span.indices {
                    sum += span[i]
                }
            }
            return sum
        }

        #expect(result == 15)
        #expect(finalElement == 5)
    }

    @Test
    @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
    func consumeAndConcludeWithEmptyReader() async throws {
        let reader = TestConcludingReader(data: [])

        let (result, finalElement) = await reader.consumeAndConclude { reader in
            let reader = reader
            var count = 0
            await reader.forEach { span in
                count += span.count
            }
            return count
        }

        #expect(result == 0)
        #expect(finalElement == 0)
    }

    @Test
    @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
    func collectReturnsResultAndFinal() async {
        let reader = TestConcludingReader(data: [10, 20, 30])

        let (collected, finalElement) = try! await reader.collect(upTo: 10) { span in
            return Array(span)
        }

        #expect(collected == [10, 20, 30])
        #expect(finalElement == 3)
    }

    @Test
    @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
    func collectEmptyConcludingReader() async {
        let reader = TestConcludingReader(data: [])

        let (collected, finalElement) = try! await reader.collect(upTo: 10) { span in
            return Array(span)
        }

        #expect(collected == [])
        #expect(finalElement == 0)
    }

    @Test
    @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
    func collectProcessesAllElements() async {
        let reader = TestConcludingReader(data: [1, 2, 3, 4])

        let (sum, finalElement) = try! await reader.collect(upTo: 10) { span in
            var total = 0
            for i in span.indices {
                total += span[i]
            }
            return total
        }

        #expect(sum == 10)
        #expect(finalElement == 4)
    }
}
