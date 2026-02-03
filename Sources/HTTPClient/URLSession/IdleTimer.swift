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

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
protocol IdleTimerEntry: ~Copyable {
    var idleDuration: Duration? { get }
    func idleTimeoutFired()
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
protocol IdleTimerEntryProvider: AnyObject, Sendable {
    associatedtype Entry: IdleTimerEntry
    associatedtype Entries: Sequence<Entry>
    var idleTimerEntries: Entries { get }
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
struct IdleTimer<Provider: IdleTimerEntryProvider>: ~Copyable {
    private let task: Task<Void, any Error>

    init(timeout: Duration, provider: Provider) {
        self.task = Task { [weak provider] in
            while true {
                try await Task.sleep(for: timeout)
                guard let provider else {
                    break
                }
                Self.cleanup(timeout: timeout * 0.8, provider: provider)
            }
        }
    }

    private static func cleanup(timeout: Duration, provider: Provider) {
        for entry in provider.idleTimerEntries {
            if let duration = entry.idleDuration, duration > timeout {
                entry.idleTimeoutFired()
            }
        }
    }

    deinit {
        self.task.cancel()
    }
}
