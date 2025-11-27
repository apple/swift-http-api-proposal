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

#if canImport(Darwin)
import HTTPAPIs
import Foundation

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension URLSessionTaskDelegateBridge: ConcludingAsyncReader {
    func consumeAndConclude<Return, Failure: Error>(
        body: nonisolated(nonsending) (consuming sending URLSessionTaskDelegateBridge) async throws(Failure) -> Return
    ) async throws(Failure) -> (Return, HTTPFields?) {
        try await (body(self), nil)
    }
}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension URLSessionTaskDelegateBridge: AsyncReader {
    func read<Return, Failure: Error>(
        maximumCount: Int?,
        body: nonisolated(nonsending) (consuming Span<UInt8>) async throws(Failure) -> Return
    ) async throws(EitherError<any Error, Failure>) -> Return {
        let data: Data?
        do {
            data = try await self.data(maximumCount: maximumCount)
        } catch {
            throw .first(error)
        }
        guard let data else {
            do {
                return try await body(InlineArray<0, UInt8>.zero().span)
            } catch {
                throw .second(error)
            }
        }
        do {
            return try await body(data.span)
        } catch {
            throw .second(error)
        }
    }
}
#endif
