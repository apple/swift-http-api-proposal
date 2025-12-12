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

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
struct TestConcludingReader: ConcludingAsyncReader {
    struct UnderlyingReader: AsyncReader {
        typealias ReadElement = Int
        typealias ReadFailure = Never

        var data: [Int]
        var position: Int = 0

        mutating func read<Return, Failure: Error>(
            maximumCount: Int?,
            body: (consuming Span<Int>) async throws(Failure) -> Return
        ) async throws(EitherError<Never, Failure>) -> Return {
            do {
                guard position < data.count else {
                    return try await body([Int]().span)
                }

                let count: Int
                if let maximumCount {
                    count = min(maximumCount, data.count - position)
                } else {
                    count = data.count - position
                }

                let endIndex = position + count
                defer { position = endIndex }
                return try await body(data[position..<endIndex].span)
            } catch {
                throw .second(error)
            }
        }
    }

    typealias Underlying = UnderlyingReader
    typealias FinalElement = Int

    let data: [Int]

    consuming func consumeAndConclude<Return, Failure: Error>(
        body: (consuming sending Underlying) async throws(Failure) -> Return
    ) async throws(Failure) -> (Return, Int) {
        let reader = UnderlyingReader(data: data)
        let result = try await body(reader)
        return (result, data.count)
    }
}
