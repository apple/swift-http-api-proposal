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

// https://developer.mozilla.org/en-US/docs/Web/API/URL
@JSClass(jsName: "URL", from: .global) struct JSURL {
    @JSFunction init(_ url: String) throws(JSException)
    @JSGetter var `protocol`: String
    @JSGetter var host: String
    @JSGetter var pathname: String
    @JSGetter var search: String
}
