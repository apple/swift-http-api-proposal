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
public struct HTTPClientClosureResponseHandler<ResponseConcludingReader, Return: ~Copyable>: HTTPClientResponseHandler, ~Copyable
where
    ResponseConcludingReader: ConcludingAsyncReader & ~Copyable & SendableMetatype,
    ResponseConcludingReader.Underlying: ~Copyable,
    ResponseConcludingReader.Underlying.ReadElement == UInt8,
    ResponseConcludingReader.FinalElement == HTTPFields?
{
    private let handler: (HTTPResponse, consuming ResponseConcludingReader) async throws -> Return

    public init(handler: @escaping (HTTPResponse, consuming ResponseConcludingReader) async throws -> Return) {
        self.handler = handler
    }

    public func handleInformational(response: HTTPResponse) async throws {
    }

    public func handle(response: HTTPResponse, responseBodyAndTrailers: consuming ResponseConcludingReader) async throws -> Return {
        try await self.handler(response, responseBodyAndTrailers)
    }
}
