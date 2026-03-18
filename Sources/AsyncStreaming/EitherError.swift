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

/// An enumeration that represents one of two possible error types.
///
/// ``EitherError`` provides a type-safe way to represent errors that can be one of two distinct
/// error types.
public enum EitherError<First: Error, Second: Error>: Error {
    /// An error of the first type.
    ///
    /// The associated value contains the specific error instance of type `First`.
    case first(First)

    /// An error of the second type.
    ///
    /// The associated value contains the specific error instance of type `Second`.
    case second(Second)

    /// Throws the underlying error by unwrapping this either error.
    ///
    /// This method extracts and throws the actual error contained within the either error,
    /// whether it's the first or second type. This is useful when you need to propagate
    /// the original error without the either error wrapper.
    ///
    /// - Throws: The underlying error, either of type `First` or `Second`.
    ///
    /// ## Example
    ///
    /// ```swift
    /// do {
    ///     // Some operation that returns EitherError
    ///     let result = try await operation()
    /// } catch let eitherError as EitherError<NetworkError, ParseError> {
    ///     try eitherError.unwrap() // Throws the original error
    /// }
    /// ```
    public func unwrap() throws -> Never {
        switch self {
        case .first(let first):
            throw first
        case .second(let second):
            throw second
        }
    }
}
