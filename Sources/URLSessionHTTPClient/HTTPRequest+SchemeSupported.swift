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

import HTTPTypes

extension HTTPRequest {
    var schemeSupported: Bool {
        guard let scheme = self.scheme?.lowercased() else {
            return false
        }
        return scheme == "https" || scheme == "http" || scheme == "https+unix" || scheme == "http+unix"
    }
}
