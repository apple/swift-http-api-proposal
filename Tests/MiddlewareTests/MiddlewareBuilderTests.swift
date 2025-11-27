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

import Middleware
import Testing

private struct ForwardingMiddleware<Input>: Middleware {
    func intercept(
        input: consuming Input,
        next: (consuming Input) async throws -> Void
    ) async throws {
        try await next(input)
    }
}

private struct TransformingMiddleware<Input, NextInput>: Middleware {
    private let transformation: @Sendable (Input) async throws -> NextInput

    init(transformation: @escaping @Sendable (Input) async throws -> NextInput) {
        self.transformation = transformation
    }

    func intercept(
        input: consuming Input,
        next: (consuming NextInput) async throws -> Void
    ) async throws {
        try await next(self.transformation(input))
    }
}

@Suite
struct MiddlewareBuilderTests {
    @Test
    func forwarding() async throws {
        let middleware = buildMiddleware {
            ForwardingMiddleware<Int>()
        }

        try await middleware.intercept(input: 1) { result in
            #expect(result == 1)
        }
    }

    @Test
    func forwardingAndTransforming() async throws {
        let middleware = buildMiddleware {
            ForwardingMiddleware<Int>()
            TransformingMiddleware<Int, String> { "\($0 * 2)" }
            TransformingMiddleware<String, Int> { Int($0)! }
        }

        try await middleware.intercept(input: 1) { result in
            #expect(result == 2)
        }
    }

    private func buildMiddleware(
        @MiddlewareBuilder
        middlewareBuilder: () -> some Middleware<Int, Int>
    ) -> some Middleware<Int, Int> {
        middlewareBuilder()
    }
}
