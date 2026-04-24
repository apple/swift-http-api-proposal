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

/// A result builder that enables a declarative syntax for constructing middleware chains.
///
/// ``MiddlewareBuilder`` leverages Swift's result builder feature to allow developers
/// to create complex middleware pipelines using a clean, DSL-like syntax. It handles
/// the type checking and composition of middleware components automatically.
///
/// This makes it easier to construct middleware chains that might involve multiple
/// transformations and conditional processing logic without having to manually manage
/// the type relationships between different middleware components.
///
/// Example usage:
/// ```swift
/// @MiddlewareBuilder
/// func buildMiddlewareChain() -> some Middleware<Request, Response> {
///     LoggingMiddleware()
///     AuthenticationMiddleware()
///     if shouldCompress {
///         CompressionMiddleware()
///     }
///     RoutingMiddleware()
/// }
/// ```
@resultBuilder
public struct MiddlewareBuilder {
    /// Builds a middleware chain from a single middleware component.
    ///
    /// This is the base case for the result builder pattern, handling a single middleware.
    ///
    /// - Parameter middleware: The single middleware component to wrap in a chain.
    /// - Returns: A middleware chain containing the single component.
    public static func buildPartialBlock<M: Middleware>(
        first middleware: M
    ) -> M {
        middleware
    }

    /// Chains together two middleware components, ensuring their input and output types match.
    ///
    /// This method composes two middlewares where the output of the first matches the input of the second,
    /// creating a unified processing pipeline.
    ///
    /// - Parameters:
    ///   - accumulated: The first middleware in the chain.
    ///   - next: The second middleware in the chain, which accepts the output of the first.
    /// - Returns: A new middleware chain that represents the composition of both middlewares.
    public static func buildPartialBlock<
        First: Middleware,
        Second: Middleware
    >(
        accumulated: First,
        next: Second
    ) -> ChainedMiddleware<First, Second>
    where First.Input: ~Copyable, First.NextInput: ~Copyable, Second.NextInput: ~Copyable, First.NextInput == Second.Input {
        return ChainedMiddleware(first: accumulated, second: next)
    }

    /// Converts a middleware expression to a middleware chain.
    ///
    /// This method allows middleware components to be used directly in result builder expressions.
    ///
    /// - Parameter middleware: The middleware component to convert.
    /// - Returns: A middleware chain wrapping the input middleware.
    public static func buildExpression<M: Middleware>(
        _ middleware: M
    ) -> M {
        middleware
    }
}
