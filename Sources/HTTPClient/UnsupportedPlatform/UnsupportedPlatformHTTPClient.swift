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

import HTTPAPIs

/// This struct implements an HTTP client that is used on unsupported platforms and will result in a runtime
/// fatal error.
@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
struct UnsupportedPlatformHTTPClient: HTTPClient {
    struct ConcludingWriter: ConcludingAsyncWriter {
        struct Writer: AsyncWriter {
            func write<Result, Failure>(
                _ body: (inout OutputSpan<UInt8>) async throws(Failure) -> Result
            ) async throws(EitherError<Never, Failure>) -> Result {
                fatalError("Unspported platform")
            }
        }

        func produceAndConclude<Return>(
            body: (consuming sending Writer) async throws -> (Return, HTTPFields?)
        ) async throws -> Return {
            fatalError("Unspported platform")
        }
    }
    struct ConcludingReader: ConcludingAsyncReader {
        struct Reader: AsyncReader {
            func read<Return, Failure>(
                maximumCount: Int?,
                body: (consuming Span<UInt8>) async throws(Failure) -> Return
            ) async throws(EitherError<Never, Failure>) -> Return {
                fatalError("Unspported platform")
            }
        }

        func consumeAndConclude<Return, Failure>(
            body: (consuming sending Reader) async throws(Failure) -> Return
        ) async throws(Failure) -> (Return, HTTPFields?) where Failure: Error {
            fatalError("Unspported platform")
        }
    }

    func perform<Return>(
        request: HTTPRequest,
        body: consuming HTTPClientRequestBody<ConcludingWriter>?,
        configuration: HTTPClientConfiguration,
        eventHandler: borrowing some HTTPClientEventHandler & ~Copyable & ~Escapable,
        responseHandler: (HTTPResponse, consuming ConcludingReader) async throws -> Return
    ) async throws -> Return {
        fatalError("Unspported platform")
    }
}
