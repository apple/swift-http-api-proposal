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

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
struct SimpleReader: AsyncReader {
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
