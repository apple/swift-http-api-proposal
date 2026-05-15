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

public import Middleware

/// A simple middleware that fowrards the input to the next middleware.
public struct ForwardingMiddleware<Input: ~Copyable & ~Escapable>: Middleware {
    public init() {}

    public func intercept<Return: ~Copyable>(
        input: consuming Input,
        next: (consuming Input) async throws -> Return
    ) async throws -> Return {
        try await next(input)
    }
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension Middleware where Input: ~Copyable & ~Escapable, NextInput: ~Copyable & ~Escapable {
    public func forwarding() -> ForwardingMiddleware<Input> {
        ForwardingMiddleware()
    }
}
