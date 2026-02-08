//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift HTTP API Proposal open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift HTTP API Proposal project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift HTTP API Proposal project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

/// The namespace for all protocols defining HTTP client capabilities.
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public enum HTTPClientCapability {
    /// The request options protocol.
    ///
    /// Additional options supported by a subset of clients are defined in child
    /// protocols to allow libraries to depend on a specific capabilities.
    public protocol RequestOptions {
        init()
    }

}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension HTTPClientCapability.RequestOptions {
    /// Creates and configures request options using a convenience closure that
    /// can be used in a `perform` call.
    ///
    /// - Parameter configure: A closure that configures the request options.
    /// - Returns: The configured request options instance.
    /// ```
    public static func build(configure: (inout Self) -> Void) -> Self {
        var options = Self()
        configure(&options)
        return options
    }
}
