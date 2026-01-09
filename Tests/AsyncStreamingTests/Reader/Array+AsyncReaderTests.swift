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
struct ArrayAsyncReaderTests {
    @Test
    @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
    func oneSpan() async throws {
        let array = [1, 2, 3].asyncReader()
        var counter = 0
        await array.forEach { span in
            counter += 1
            #expect(span.count == 3)
        }
        #expect(counter == 1)
    }

    @Test
    @available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
    func multipleSpans() async throws {
        var array = [1, 2, 3].asyncReader()
        var counter = 0
        var continueReading = true
        while continueReading {
            try await array.read(maximumCount: 1) { span in
                guard span.count > 0 else {
                    continueReading = false
                    return
                }
                counter += 1
                #expect(span.count == 1)
            }
        }
        #expect(counter == 3)
    }
}
