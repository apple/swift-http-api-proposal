//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift HTTP API Proposal open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift HTTP API Proposal project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import AsyncStreaming
import BasicContainers

// Helper: A test concluding writer that accumulates elements and tracks if finalized
struct TestConcludingWriter: ConcludingAsyncWriter {
    struct UnderlyingWriter: AsyncWriter {
        typealias WriteElement = Int
        typealias WriteFailure = Never

        var storage: [Int]

        mutating func write<Result, Failure: Error>(
            _ body: (inout OutputSpan<Int>) async throws(Failure) -> Result
        ) async throws(EitherError<Never, Failure>) -> Result {
            do {
                var buffer = RigidArray<Int>(capacity: 10)

                return try await buffer.append(count: 10) { outputSpan async throws(Failure) -> Result in
                    let result = try await body(&outputSpan)
                    storage.append(span: outputSpan.span)
                    return result
                }
            } catch {
                throw .second(error)
            }
        }

        mutating func write(
            _ span: Span<Int>
        ) async throws(EitherError<Never, AsyncWriterWroteShortError>) {
            storage.append(span: span)
        }
    }

    typealias Underlying = UnderlyingWriter
    typealias FinalElement = String

    consuming func produceAndConclude<Return>(
        body: (consuming sending Underlying) async throws -> (Return, String)
    ) async throws -> Return {
        let writer = UnderlyingWriter(storage: [])
        let (result, _) = try await body(writer)
        return result
    }
}
