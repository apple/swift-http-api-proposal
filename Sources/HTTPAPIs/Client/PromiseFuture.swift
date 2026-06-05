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

import Synchronization

@available(anyAppleOS 26.0, *)
private protocol FutureProtocol<Value>: AnyObject, Sendable {
    associatedtype Value: ~Copyable
    func value() async throws -> sending Value
}

@available(anyAppleOS 26.0, *)
private final class FulfillableFuture<Value: ~Copyable>: FutureProtocol {
    private enum State: ~Copyable {
        case none
        case continuation(Continuation<Value, any Error>)
        case value(Disconnected<Value>)
        case error(any Error)

        mutating func fulfill(_ value: consuming sending Value) {
            switch consume self {
            case .none:
                self = .value(Disconnected(value: value))
            case .continuation(let continuation):
                self = .none
                continuation.resume(returning: value)
            case .value:
                fatalError()
            case .error:
                fatalError()
            }
        }

        mutating func fulfill(error: any Error) {
            switch consume self {
            case .none:
                self = .error(error)
            case .continuation(let continuation):
                self = .none
                continuation.resume(throwing: error)
            case .value:
                fatalError()
            case .error:
                fatalError()
            }
        }

        mutating func take(continuation: consuming Continuation<Value, any Error>) {
            switch consume self {
            case .none:
                self = .continuation(continuation)
            case .continuation:
                fatalError()
            case .value(let value):
                self = .none
                continuation.resume(returning: value.take())
            case .error(let error):
                self = .none
                continuation.resume(throwing: error)
            }
        }
    }
    private let state: Mutex<State> = .init(.none)

    func fulfill(_ value: consuming sending Value) {
        var value = Optional(Disconnected(value: value))
        self.state.withLock {
            $0.fulfill(value.take()!.take())
        }
    }

    func fulfill(error: any Error) {
        self.state.withLock {
            $0.fulfill(error: error)
        }
    }

    func value() async throws -> sending Value {
        try await withContinuation(throwing: (any Error).self) {
            var continuation = Optional($0)
            self.state.withLock {
                $0.take(continuation: continuation.take()!)
            }
        }
    }
}

@available(anyAppleOS 26.0, *)
private final class MappedFuture<Value: ~Copyable, OriginalValue: ~Copyable>: FutureProtocol {
    private let originalPromise: any FutureProtocol<OriginalValue>
    private let transform: @Sendable (consuming sending OriginalValue) -> sending Value

    init(originalPromise: any FutureProtocol<OriginalValue>, transform: @Sendable @escaping (consuming sending OriginalValue) -> sending Value) {
        self.originalPromise = originalPromise
        self.transform = transform
    }

    func value() async throws -> sending Value {
        let value = try await self.originalPromise.value()
        return self.transform(value)
    }
}

@available(anyAppleOS 26.0, *)
private final class ImmediateFuture<Value: ~Copyable>: FutureProtocol {
    private let value: Mutex<Disconnected<Value>?>

    init(_ value: consuming sending Value) {
        self.value = .init(.init(value: value))
    }

    func value() async throws -> sending Value {
        self.value.withLock {
            $0.take()!.take()
        }
    }
}

@frozen
public struct Pair<A: ~Copyable, B: ~Copyable>: ~Copyable {
    public let a: A
    public let b: B

    public init(_ a: consuming A, _ b: consuming B) {
        self.a = a
        self.b = b
    }
}

@available(anyAppleOS 26.0, *)
public struct Promise<Value: ~Copyable>: ~Copyable, Sendable {
    private let state: FulfillableFuture<Value>

    public static func makePromise(of type: Value.Type) -> Pair<Promise<Value>, Future<Value>> {
        let state = FulfillableFuture<Value>()
        let promise = Promise(state: state)
        let future = Future(state: state)
        return Pair(promise, future)
    }

    public consuming func fulfill(_ value: consuming sending Value) {
        self.state.fulfill(value)
    }

    public consuming func fulfill(error: any Error) {
        self.state.fulfill(error: error)
    }
}

@available(anyAppleOS 26.0, *)
public struct Future<Value: ~Copyable>: ~Copyable, Sendable {
    private let state: any FutureProtocol<Value>

    fileprivate init(state: any FutureProtocol<Value>) {
        self.state = state
    }

    public init(immediateValue value: consuming sending Value) {
        self.state = ImmediateFuture(value)
    }

    public consuming func value() async throws -> Value {
        try await self.state.value()
    }

    public consuming func map<NewValue: ~Copyable>(_ transform: @Sendable @escaping (consuming sending Value) -> sending NewValue) -> Future<NewValue>
    {
        let state: any FutureProtocol<NewValue> = MappedFuture(originalPromise: self.state, transform: transform)
        return Future<NewValue>(state: state)
    }
}

@usableFromInline
struct Disconnected<Value: ~Copyable>: ~Copyable, Sendable {
    // This is safe since we take the value as sending and take consumes it
    // and returns it as sending.
    private nonisolated(unsafe) var value: Value?

    @usableFromInline
    init(value: consuming sending Value) {
        unsafe self.value = .some(value)
    }

    @usableFromInline
    consuming func take() -> sending Value {
        nonisolated(unsafe) let value = unsafe self.value.take()!
        return unsafe value
    }

    @usableFromInline
    mutating func swap(newValue: consuming sending Value) -> sending Value {
        nonisolated(unsafe) let value = unsafe self.value.take()!
        unsafe self.value = consume newValue
        return unsafe value
    }
}
