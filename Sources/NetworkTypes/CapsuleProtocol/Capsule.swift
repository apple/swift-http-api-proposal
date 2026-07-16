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

/// A single capsule containing a type code and its opaque value, per RFC 9297, Section 3.2.
///
/// ``value`` is a borrowed view into the bytes the capsule was decoded from.
/// The value's internal structure is defined by ``type``.
public struct Capsule {
    /// The capsule type.
    public var type: CapsuleType

    /// The value is an opaque byte sequence.
    public var value: Array<UInt8>

    /// Creates a capsule from a type and a borrowed value.
    public init(type: CapsuleType, value: Array<UInt8>) {
        self.type = type
        self.value = value
    }

    /// Header information for a Capsule.
    public struct HeaderInformation {
        /// The capsule type.
        public let type: CapsuleType

        /// Length of the capsule's value following the header.
        public let valueByteCount: Int

        /// Number of bytes used to encode the capsule type and value length.
        public let headerByteCount: Int
    }

    /// Decodes a capsule's header (type and length) from the front of
    /// `input`.
    ///
    /// This does not require the value bytes to be present. Mutates
    /// the span to start with the value. This lets a caller inspect the
    /// header (e.g., to reject an oversized value) before consuming
    /// the value.
    ///
    /// - Returns: The `HeaderInformation` for capsule type or
    ///   `nil` if `input` does not yet contain a complete type and
    ///   length.
    public static func decodeHeader(from input: inout Span<UInt8>) -> HeaderInformation? {
        guard let header = Self.peekHeader(from: input) else {
            return nil
        }
        input = input.extracting(header.headerByteCount...)
        return header
    }

    /// Decodes a capsule's header (type and length) from the front of
    /// `input`.
    ///
    /// This does not require the value bytes to be present. This
    /// does not mutate the span. This lets a caller inspect the header
    /// (e.g., to reject an oversized value) before consuming the value.
    ///
    /// - Returns: The `HeaderInformation` for capsule type or
    ///   `nil` if `input` does not yet contain a complete type and
    ///   length.
    public static func peekHeader(from input: Span<UInt8>) -> HeaderInformation? {
        guard let decodedType = VariableLengthInteger.decode(from: input) else {
            return nil
        }
        let remainingBytes = input.extracting(droppingFirst: decodedType.byteCount)
        guard let decodedLength = VariableLengthInteger.decode(from: remainingBytes) else {
            return nil
        }
        return HeaderInformation(
            type: .init(decodedType.value),
            valueByteCount: Int(decodedLength.value),
            headerByteCount: decodedType.byteCount + decodedLength.byteCount
        )
    }

    /// Decodes one capsule from the front of `input`, advancing `input` past the
    /// bytes it consumed.
    ///
    /// - Returns: The decoded capsule, or `nil` if `input` does not yet contain a
    ///   complete capsule. When `nil` is returned, `input` is left unchanged.
    public static func decode(from input: inout Span<UInt8>) -> Capsule? {
        guard let header = Self.peekHeader(from: input) else {
            return nil
        }
        let capsuleByteCount = header.headerByteCount + header.valueByteCount
        guard capsuleByteCount <= input.count else {
            return nil
        }

        // Copy the value.
        let valueSpan = input.extracting(droppingFirst: header.headerByteCount)
        let value = Array<UInt8>(capacity: valueSpan.count) { outputSpan in
            for index in 0..<valueSpan.count {
                outputSpan.append(valueSpan[index])
            }
        }

        // Create the capulse.
        let capsule = Capsule(type: header.type, value: value)

        // Drop consumed bytes from span.
        input = input.extracting(capsuleByteCount...)
        return capsule
    }
}

@available(anyAppleOS 26.0, *)
extension Capsule {
    /// The number of bytes ``encode(into:)`` writes for this capsule: the encoded
    /// type, the encoded length, and the value.
    ///
    /// - throws: ``NetworkTypeError`` if the capsule type of count surpass the
    ///   maximum length of ``VariableLengthInteger``.
    public var encodedByteCount: Int {
        get throws(NetworkTypeError) {
            try VariableLengthInteger.encodedByteCount(self.type.rawValue)
                + VariableLengthInteger.encodedByteCount(UInt64(self.value.count))
                + self.value.count
        }
    }

    /// Encodes the capsule (type, then length, then value) into `output`.
    ///
    /// - throws: ``NetworkTypeError`` if `output` has does not
    ///   have at least ``encodedByteCount`` bytes of remaining capacity.
    public func encode(into output: inout OutputSpan<UInt8>) throws(NetworkTypeError) {
        if try output.capacity < self.encodedByteCount {
            throw .insufficientCapacity
        }

        // First the type and value length ...
        try VariableLengthInteger.encode(self.type.rawValue, into: &output)
        try VariableLengthInteger.encode(UInt64(self.value.count), into: &output)

        // ... followed by the value itself.
        for index in 0..<self.value.count {
            output.append(self.value[index])
        }
    }

    /// Encodes only a capsule's header (type and length) into `output`.
    ///
    /// After calling this, write exactly `valueByteCount` value bytes to the same
    /// stream. This lets a caller stream a large value without buffering it whole.
    ///
    /// - throws: ``NetworkTypeError`` if `output` has does not
    ///   have at least ``encodedByteCount`` bytes of remaining capacity
    public static func encodeHeader(type: CapsuleType, valueByteCount: Int, into output: inout OutputSpan<UInt8>) throws(NetworkTypeError) {
        try VariableLengthInteger.encode(type.rawValue, into: &output)
        try VariableLengthInteger.encode(UInt64(valueByteCount), into: &output)
    }
}
