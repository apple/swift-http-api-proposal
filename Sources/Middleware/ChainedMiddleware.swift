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

/// A middleware implementation that links two middleware chains together.
///
/// ``ChainedMiddleware`` is responsible for properly composing two middleware chains
/// so that the output from the first middleware becomes the input to the second.
/// This allows for building complex processing pipelines through composition.
///
/// This type is primarily used internally by the ``MiddlewareChainBuilder`` to combine
/// middleware components in a type-safe way.
struct ChainedMiddleware<First: Middleware, Second: Middleware>: Middleware where First.NextInput == Second.Input {
    /// The first middleware in the chain.
    private let first: First

    /// The second middleware in the chain, which receives output from the first middleware.
    private let second: Second

    init(
        first: First,
        second: Second
    ) {
        self.first = first
        self.second = second
    }

    /// Processes input through both middlewares in sequence.
    ///
    /// This method implements the core chaining behavior by passing the input through
    /// the first middleware, then using the output of that operation as the input to
    /// the second middleware.
    ///
    /// - Parameters:
    ///   - input: The initial input value to pass to the first middleware.
    ///   - next: The next handler function to call after both middlewares have processed the input.
    ///
    /// - Throws: Any error that occurs during processing in either middleware.
    func intercept(
        input: consuming First.Input,
        next: (consuming Second.NextInput) async throws -> Void
    ) async throws {
        try await first.intercept(input: input) { middleInput in
            try await second.intercept(input: middleInput, next: next)
        }
    }
}
