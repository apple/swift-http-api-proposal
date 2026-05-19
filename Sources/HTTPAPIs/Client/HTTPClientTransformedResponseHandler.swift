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

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
package struct HTTPClientTransformedResponseHandler<OtherHandler: HTTPClientResponseHandler & ~Copyable, ResponseConcludingReader>:
    HTTPClientResponseHandler, ~Copyable
where
    OtherHandler.ResponseConcludingReader: ~Copyable,
    OtherHandler.ResponseConcludingReader.Underlying: ~Copyable,
    OtherHandler.Return: ~Copyable,
    ResponseConcludingReader: ConcludingAsyncReader & ~Copyable & SendableMetatype,
    ResponseConcludingReader.Underlying: ~Copyable,
    ResponseConcludingReader.Underlying.ReadElement == UInt8,
    ResponseConcludingReader.FinalElement == HTTPFields?
{
    package typealias Return = OtherHandler.Return

    private let other: OtherHandler
    private let transform: @Sendable (consuming ResponseConcludingReader) -> OtherHandler.ResponseConcludingReader

    package init(
        other: consuming OtherHandler,
        transform: @escaping @Sendable (consuming ResponseConcludingReader) -> OtherHandler.ResponseConcludingReader
    ) {
        self.other = other
        self.transform = transform
    }

    package func handleInformational(response: HTTPResponse) async throws {
        try await self.other.handleInformational(response: response)
    }

    package func handle(response: HTTPResponse, responseBodyAndTrailers: consuming ResponseConcludingReader) async throws -> Return {
        try await self.other.handle(response: response, responseBodyAndTrailers: self.transform(responseBodyAndTrailers))
    }
}
