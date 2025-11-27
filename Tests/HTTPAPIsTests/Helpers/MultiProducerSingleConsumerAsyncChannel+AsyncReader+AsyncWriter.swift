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

public import AsyncAlgorithms
public import AsyncStreaming
import BasicContainers

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension MultiProducerSingleConsumerAsyncChannel: AsyncReader {
    public typealias ReadElement = Element
    public typealias ReadFailure = Failure

    public mutating func read<Return, F: Error>(
        maximumCount: Int?,
        body: nonisolated(nonsending) (consuming Span<Element>) async throws(F) -> Return
    ) async throws(EitherError<Failure, F>) -> Return {
        let element: Element?
        do {
            element = try await self.next()
        } catch {
            throw .first(error)
        }

        do {
            guard let element else {
                return try await body(InlineArray<0, Element>.zero().span)
            }

            return try await body(
                InlineArray<
                    1,
                    Element
                >.one(value: element).span
            )
        } catch {
            throw .second(error)
        }
    }
}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension MultiProducerSingleConsumerAsyncChannel.Source: AsyncWriter where Element == UInt8 {
    public typealias WriteElement = Element
    public typealias WriteFailure = any Error

    public mutating func write<Result, F: Error>(
        _ body: nonisolated(nonsending) (inout OutputSpan<Element>) async throws(F) -> Result
    ) async throws(EitherError<any Error, F>) -> Result {
        var buffer = RigidArray<Element>(capacity: 1)
        let result: Result
        do {
            result = try await buffer.append(count: 1) { outputSpan async throws(F) -> Result in
                try await body(&outputSpan)
            }
        } catch {
            throw .second(error)
        }

        if buffer.count == 1 {
            do {
                try await self.send(buffer.removeLast())
            } catch {
                throw .first(error)
            }
        }
        return result
    }

}
