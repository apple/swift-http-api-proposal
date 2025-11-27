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

/// A concrete implementation of ``Middleware`` that is backed by a closure.
struct ClosureMiddleware<Input: ~Copyable, NextInput: ~Copyable>: Middleware {
    private let middlewareFunc:
        @Sendable (
            consuming Input,
            (consuming NextInput) async throws -> Void
        ) async throws -> Void

    /// Creates a middleware using a closure.es.
    ///
    /// - Parameter middlewareFunc: A closure that implements the middleware's behavior.
    init(
        middlewareFunc:
            @Sendable @escaping (
                consuming Input,
                (consuming NextInput) async throws -> Void
            ) async throws -> Void
    ) {
        self.middlewareFunc = middlewareFunc
    }

    /// Intercepts and processes the input, then calls the next middleware or handler.
    ///
    /// This method defines the core behavior of a middleware. It receives the current input,
    /// performs its operation, and then passes control to the next middleware or handler.
    ///
    /// - Parameters:
    ///   - input: The input data to be processed by this middleware.
    ///   - next: A closure representing the next step in the middleware chain.
    ///           It accepts a parameter of type `NextInput`.
    ///
    /// - Throws: Any error that occurs during processing.
    func intercept(
        input: consuming Input,
        next: (consuming NextInput) async throws -> Void
    ) async throws {
        try await middlewareFunc(input, next)
    }
}
