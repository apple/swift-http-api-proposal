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

#if canImport(Foundation)
public import Foundation

/// Formats and parses RFC 9110 HTTP-date values.
@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
public struct HTTPDateFormatter: Sendable {
    public init() {}

    /// Formats a date using the preferred IMF-fixdate form.
    public func string(from date: Date) -> String {
        DateFormatter.httpImfFixdate.string(from: date)
    }

    /// Parses an HTTP-date, accepting the preferred IMF-fixdate form and the two obsolete forms
    /// that recipients are still required to accept.
    public func date(from value: String) -> Date? {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        for formatter in [
            DateFormatter.httpImfFixdate,
            DateFormatter.httpRfc850Date,
            DateFormatter.httpAsctimeDate,
        ] {
            if let date = formatter.date(from: trimmedValue) {
                return date
            }
        }
        return nil
    }
}

private extension DateFormatter {
    // RFC 9110 Section 5.6.7 preferred IMF-fixdate form:
    // Sun, 06 Nov 1994 08:49:37 GMT
    static let httpImfFixdate = DateFormatter.makeHTTPDateFormatter(
        dateFormat: "EEE',' dd MMM yyyy HH':'mm':'ss zzz"
    )

    // RFC 9110 Section 5.6.7 obsolete RFC 850 form that recipients must still accept:
    // Sunday, 06-Nov-94 08:49:37 GMT
    static let httpRfc850Date = DateFormatter.makeHTTPDateFormatter(
        dateFormat: "EEEE',' dd-MMM-yy HH':'mm':'ss zzz"
    )

    // RFC 9110 Section 5.6.7 obsolete ANSI C `asctime()` form:
    // Sun Nov 6 08:49:37 1994
    static let httpAsctimeDate = DateFormatter.makeHTTPDateFormatter(
        dateFormat: "EEE MMM d HH':'mm':'ss yyyy"
    )

    private static func makeHTTPDateFormatter(dateFormat: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = dateFormat
        return formatter
    }
}
#endif
