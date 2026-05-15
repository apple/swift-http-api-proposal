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
public protocol HTTPClientResponseHandler: ~Copyable {
    associatedtype ResponseConcludingReader: ConcludingAsyncReader, ~Copyable, SendableMetatype
    where
        ResponseConcludingReader.Underlying: ~Copyable,
        ResponseConcludingReader.Underlying.ReadElement == UInt8,
        ResponseConcludingReader.FinalElement == HTTPFields?
    associatedtype Return: ~Copyable

    func handleInformational(response: HTTPResponse) async throws

    func handle(response: HTTPResponse, responseBodyAndTrailers: consuming ResponseConcludingReader) async throws -> Return
}
