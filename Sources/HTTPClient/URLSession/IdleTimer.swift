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
protocol IdleTimerEntryProvider: ~Copyable {
    associatedtype Entry: IdleTimerEntry
    associatedtype Entries: Sequence<Entry>
    var idleTimerEntries: Entries { get }
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
enum IdleTimer {
    static func run(timeout: Duration, provider: some IdleTimerEntryProvider) async {
        do {
            let entryTimeout = timeout * 0.8
            while true {
                try await Task.sleep(for: timeout)
                for entry in provider.idleTimerEntries {
                    if let duration = entry.idleDuration, duration > entryTimeout {
                        entry.idleTimeoutFired()
                    }
                }
            }
        } catch {
            // Catch the cancellation error outside the loop and ignore it.
        }
    }
}
