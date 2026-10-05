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

/// An error raised while applying TLS handler options to a request.
@available(anyAppleOS 26.0, *)
enum TLSHandlerError: Error {
    /// The certificates presented by the peer could not be decoded.
    case couldNotParseCertificateChain
    /// A client certificate or private key could not be encoded for the TLS stack.
    case couldNotSerializeClientCertificate
}
