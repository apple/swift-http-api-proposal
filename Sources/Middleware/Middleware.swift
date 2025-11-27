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

/// A protocol that defines middleware components for processing inputs and passing them to the next stage.
///
/// The `Middleware` protocol provides a way to intercept inputs of type `Input`,
/// process them, and then optionally transform them into `NextInput` before passing
/// to the next middleware.
///
/// Middlewares can be composed to form processing pipelines where each middleware
/// performs a specific operation like authentication, logging, caching, etc.
///
/// - Note: Middleware components are designed to be composable. You can use the
///   `MiddlewareChainBuilder` to easily construct middleware chains.
public protocol Middleware<Input, NextInput>: Sendable {
    /// The input type that this middleware accepts.
    associatedtype Input: ~Copyable, ~Escapable

    /// The type passed to the next middleware in the chain.
    /// Defaults to the same type as `Input` if not specified.
    associatedtype NextInput: ~Copyable, ~Escapable = Input

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
    ) async throws
}
