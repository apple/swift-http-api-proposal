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

extension Array {
    init(_ span: Span<Element>) {
        self.init()
        for index in span.indices {
            self.append(span[index])
        }
    }

    mutating func append(span: Span<Element>) {
        for index in span.indices {
            self.append(span[index])
        }
    }
}
