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

public import AsyncStreaming
public import HTTPAPIs

/// The input passed through client-side middleware: the request head plus the
/// request body the user wants to send.
///
/// Mirrors ``HTTPServerMiddlewareInput`` on the server side. Wrapping
/// middlewares can substitute a different `Writer` type for `NextInput` so
/// the inner stage sees a wrapped body that intercepts the bytes the user
/// wrote.
@available(anyAppleOS 26.0, *)
public struct HTTPClientMiddlewareInput<Writer: CallerAsyncWriter & ~Copyable & SendableMetatype>: ~Copyable
where Writer.WriteElement == UInt8, Writer.FinalElement == HTTPFields? {
    public var request: HTTPRequest
    public var body: HTTPClientRequestBody<Writer>?

    public init(request: HTTPRequest, body: consuming HTTPClientRequestBody<Writer>?) {
        self.request = request
        self.body = body
    }
}

@available(*, unavailable)
extension HTTPClientMiddlewareInput: Sendable {}
