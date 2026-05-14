//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift HTTP API Proposal open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift HTTP API Proposal project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

public import AsyncAlgorithms
public import AsyncStreaming
public import BasicContainers
public import ContainersPreview

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension MultiProducerSingleConsumerAsyncChannel: AsyncReader {
    public typealias ReadElement = Element
    public typealias ReadFailure = Failure
    public typealias Buffer = UniqueArray<Element>

    public mutating func read<Return: ~Copyable, F: Error>(
        body: nonisolated(nonsending) (inout UniqueArray<Element>) async throws(F) -> Return
    ) async throws(EitherError<Failure, F>) -> Return {
        let element: Element?
        do {
            element = try await self.next()
        } catch {
            throw .first(error)
        }

        var buffer = UniqueArray<Element>()
        if let element {
            buffer.append(element)
        }

        do {
            return try await body(&buffer)
        } catch {
            throw .second(error)
        }
    }
}

@available(macOS 26.2, iOS 26.2, watchOS 26.2, tvOS 26.2, visionOS 26.2, *)
extension MultiProducerSingleConsumerAsyncChannel.Source: AsyncWriter where Element == UInt8 {
    public typealias WriteElement = Element
    public typealias WriteFailure = any Error
    public typealias Buffer = UniqueArray<Element>

    public mutating func write<Return: ~Copyable, F: Error>(
        _ body: nonisolated(nonsending) (inout UniqueArray<Element>) async throws(F) -> Return
    ) async throws(EitherError<any Error, F>) -> Return {
        var buffer = UniqueArray<Element>()
        let result: Return
        do {
            result = try await body(&buffer)
        } catch {
            throw .second(error)
        }

        var consumer = buffer.consumeAll()
        while let element = consumer.next() {
            do {
                try await self.send(element)
            } catch {
                throw .first(error)
            }
        }
        return result
    }
}
