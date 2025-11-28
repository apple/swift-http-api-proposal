# AsyncReader and AsyncWriter protocols

## Introduction

This target introduces new `AsyncReader` and `AsyncWriter` protocols that
provide a pull/push-based interface for asynchronous streaming such as file I/O,
networking and more. It builds on the learnings of `AsyncSequence` with support
for `~Copyable` and `~Escapable` types, typed throws, lifetimes and more.

## Motivation

While `AsyncSequence` has seen widespread adoption for consuming asynchronous
streams, several limitations have emerged over the past years:

### No support for `~Copyable` and `~Escapable` types

`AsyncSequence` was introduced before `~Copyable` and `~Escapable` types were
introduced, hence, the current `AsyncSequence` protocol's does not support types
with those constraints. Furthermore, it doesn't allow elements with those
constraints either.

### Iterator pattern isn't fitting

`AsyncSequence` followed the design principles of its synchronous counter part
`Sequence`. While iterators are a good abstraction for those it became obvious
that for asynchronous sequences they aren't a good fit. This is due to two
reasons. First, most asynchronous sequences do not support multiple iterators.
Secondly, most asynchronous sequences are not replayable.

### Final elements

Some asynchronous sequences can finish with a special last element. A common
example are HTTP trailers that are an optional part at the end of an HTTP
request or response. The current `AsyncSequence` protocol only allows to express
this by making the `Element` an `Either` like type.

### Bulk iteration

The current `AsyncIterator.next()` method only allows iteration element by
element. This limits performance by requiring multiple calls to retrieve
elements from the iterator even if those elements are already available. 

### Bi-directional streaming and Structured Concurrency

`AsyncSequence`s are used to express a series of asynchronous elements such as
the requests or response body parts of an HTTP request. Various APIs around the
ecosystem have adopted `AsyncSequence`s such as `NIOFileSystem`,
`AsyncHTTPClient` or `grpc-swift`. During the design and implementation of APIs
that support bi-directional streaming such as HTTP or gRPC it became apparent
that pull-based `AsyncSequence`s model is only working for one side of the
bi-directional streaming. Trying to express both side as an `AsyncSequence`
forced the introduction of unstructured tasks breaking Structured Concurrency
guarantees.

```swift
func bidirectionalStreaming(input: some AsyncSequence<UInt8, Never>) async throws -> some AsyncSequence<UInt8, Never> {
  // The output async sequence can start producing values before the input has been fully streamed
  // this forces us to create an unstructured task to continue iterating the input after the return of this method
  Task {
    for await byte in input {
        // Send byte
    }
  }
  return ConcreteAsyncSequence()
}
```

This is due to that fact that `AsyncSequence` is a pull-based model, if the
input and output in a bi-directional streaming setup are related then using a
pull-based model into both directions can work; however, when the two are
unrelated then a push-based model for the output is a better fit. Hence, we see
a proliferation of asynchronous writer protocols and types throughout the
ecosystem such as:
- [NIOAsyncWriter](https://github.com/apple/swift-nio/blob/main/Sources/NIOCore/AsyncSequences/NIOAsyncWriter.swift)
- [WritableFileHandleProtocol](https://github.com/apple/swift-nio/blob/767ea9ee09c4227d32f230c7e24bb9f5a6a5cfd9/Sources/NIOFS/FileHandleProtocol.swift#L448)
- [RPCWriterProtocol](https://github.com/grpc/grpc-swift-2/blob/5c04d83ba35f4343dcf691a000bcb89f68755587/Sources/GRPCCore/Streaming/RPCWriterProtocol.swift#L19)

### Some algorithms break Structured Concurrency

During the implementation of various algorithms inside `swift-async-algorithms`,
we learned that whenever the production of values needs to outlive a single call
to the iterator's `next()` method it forced us to use unstructured tasks.
Examples of this are:
- [merge](https://github.com/apple/swift-async-algorithms/blob/26111a6fb73ce448a41579bbdb12bdebd66672f1/Sources/AsyncAlgorithms/Merge/AsyncMerge2Sequence.swift#L16)
  where a single call to `next` races multiple base asynchronous sequences. We
  return the first value produced by any of the bases but the calls to the other
  bases still need to continue.
- [zip](https://github.com/apple/swift-async-algorithms/blob/26111a6fb73ce448a41579bbdb12bdebd66672f1/Sources/AsyncAlgorithms/Zip/AsyncZip2Sequence.swift#L15)
  same problem as `merge`.
- [buffer](https://github.com/apple/swift-async-algorithms/blob/26111a6fb73ce448a41579bbdb12bdebd66672f1/Sources/AsyncAlgorithms/Buffer/AsyncBufferSequence.swift#L25)
  where the base needs to produce elements until the buffer is full

While the implementations try their best to make the usage of unstructured tasks
as _structured_ as possible, there are multiple problems with their usage:
1. Cancellation needs to be propagated manually
2. Priority escalation needs to be propagated manually
3. Task executor preference needs to be propagated manually
4. Task locals are only copied on the first call to `next`

## Proposed solution

### `AsyncReader`

`AsyncReader` is a replacement to `AsyncSequence` that addresses the above
limitations. It allows `~Copyable` elements and offers bulk
iteration by providing a `Span<Element>`.

```swift
try await fileReader.read { span in
  print(span.count)
}
```

### `ConcludingAsyncReader`

The `ConcludingAsyncReader` is a new type that provides scoped access to an
`AsyncReader`. Once, the user is done with the `AsyncReader` the concluding
final element is returned.

```swift
let trailers = try await httpRequestConcludingReader.consumeAndConclude { bodyReader in
  // Use the bodyReader to read the HTTP request body
  try await bodyReader.read { chunk in
    print(chunk)
  }
}

// The trailers are returned once we are done with the body reader
print(trailers)
```

### `AsyncWriter`

`AsyncWriter` is the push-based counter part to `AsyncReader` that models an
asynchronous writable type. Similar to `AsyncReader` it allows `~Copyable` elements
 and offers bulk writing by offering  an `OutputSpan<Element>` to write into.

```swift
var values = [1, 2, 3, 4]
try await fileWriter.write { outputSpan in
    for value in values {
        outputSpan.append(value)
    }
}
```

### `ConcludingAsyncWriter`

`ConcludingAsyncWriter` is the counter part to the `ConcludingAsyncReader`. It
provides access to a scoped writer. Once the user is done with the writer they
can return a final element. 

```swift
try await httpRequestConcludingWriter.consumeAndConclude { bodyWriter in
  // Use the bodyWriter to write the HTTP request body
    try await bodyWriter.write(values.span.bytes)

    // Return the trailers as the final element
    return HTTPFields(...)
}
```

## Detailed design

### `AsyncReader`

```swift
/// A protocol that represents an asynchronous reader capable of reading elements from some source.
///
/// ``AsyncReader`` defines an interface for types that can asynchronously read elements
/// of a specified type from a source.
public protocol AsyncReader<ReadElement, ReadFailure>: ~Copyable, ~Escapable {
    /// The type of elements that can be read by this reader.
    associatedtype ReadElement: ~Copyable

    /// The type of error that can be thrown during reading operations.
    associatedtype ReadFailure: Error

    /// Reads elements from the underlying source and processes them with the provided body closure.
    ///
    /// This method asynchronously reads a span of elements from whatever source the reader
    /// represents, then passes them to the provided body closure. The operation may complete immediately
    /// or may await resources or processing time.
    ///
    /// - Parameter maximumCount: The maximum count of items the caller is ready
    ///   to process, or nil if the caller is prepared to accept an arbitrarily
    ///   large span. If non-nil, the maximum must be greater than zero.
    ///
    /// - Parameter body: A closure that consumes a span of read elements and performs some operation
    ///   on them, returning a value of type `Return`. When the span is empty, it indicates
    ///   the end of the reading operation or stream.
    ///
    /// - Returns: The value returned by the body closure after processing the read elements.
    ///
    /// - Throws: An `EitherError` containing either a `ReadFailure` from the read operation
    ///   or a `Failure` from the body closure.
    ///
    /// ```swift
    /// var fileReader: FileAsyncReader = ...
    ///
    /// // Read data from a file asynchronously and process it
    /// let result = try await fileReader.read { data in
    ///     guard data.count > 0 else {
    ///         // Handle end of stream/terminal value
    ///         return finalProcessedValue
    ///     }
    ///     // Process the data
    ///     return data
    /// }
    /// ```
    mutating func read<Return, Failure: Error>(
        maximumCount: Int?,
        body: (consuming Span<ReadElement>) async throws(Failure) -> Return
    ) async throws(EitherError<ReadFailure, Failure>) -> Return

}
```

### `ConcludingAsyncReader`

```swift
/// A protocol that represents an asynchronous reader that produces elements and concludes with a final value.
///
/// ``ConcludingAsyncReader`` adds functionality to asynchronous readers that need to
/// provide a conclusive element after all reads are completed. This is particularly useful
/// for streams that have meaningful completion states beyond just terminating, such as
/// HTTP responses that include headers after the body is fully read.
public protocol ConcludingAsyncReader<Underlying, FinalElement>: ~Copyable, ~Escapable {
    /// The underlying asynchronous reader type that produces elements.
    associatedtype Underlying: AsyncReader, ~Copyable, ~Escapable

    /// The type of the final element produced after all reads are completed.
    associatedtype FinalElement

    /// Processes the underlying async reader until completion and returns both the result of processing
    /// and a final element.
    ///
    /// - Parameter body: A closure that takes the underlying `AsyncReader` and returns a value.
    /// - Returns: A tuple containing the value returned by the body closure and the final element.
    /// - Throws: Any error thrown by the body closure or encountered while processing the reader.
    ///
    /// - Note: This method consumes the concluding async reader, meaning it can only be called once on a value type.
    ///
    /// ```swift
    /// let responseReader: HTTPResponseReader = ...
    ///
    /// // Process the body while capturing the final response status
    /// let (bodyData, statusCode) = try await responseReader.consumeAndConclude { reader in
    ///     var collectedData = Data()
    ///     while let chunk = try await reader.read(body: { $0 }) {
    ///         collectedData.append(chunk)
    ///     }
    ///     return collectedData
    /// }
    /// ```
    consuming func consumeAndConclude<Return, Failure: Error>(
        body: (consuming sending Underlying) async throws(Failure) -> Return
    ) async throws(Failure) -> (Return, FinalElement)
}

```

### `AsyncWriter`

```swift
/// A protocol that represents an asynchronous writer capable of providing a buffer to write into.
///
/// ``AsyncWriter`` defines an interface for types that can asynchronously write elements
/// to a destination by providing an output span buffer for efficient batch writing operations.
public protocol AsyncWriter<WriteElement, WriteFailure>: ~Copyable, ~Escapable {
    /// The type of elements that can be written by this writer.
    associatedtype WriteElement: ~Copyable

    /// The type of error that can be thrown during writing operations.
    associatedtype WriteFailure: Error

    /// Provides a buffer to write elements into.
    ///
    /// This method supplies an output span that the body closure can use to append elements
    /// for writing. The writer manages the buffer allocation and handles the actual writing
    /// operation once the body closure completes.
    ///
    /// - Parameter body: A closure that receives an `OutputSpan` for appending elements
    ///   to write. The closure can return a result of type `Result`.
    ///
    /// - Returns: The value returned by the body closure.
    ///
    /// - Throws: An `EitherError` containing either a `WriteFailure` from the write operation
    ///   or a `Failure` from the body closure.
    ///
    /// ## Example
    ///
    /// ```swift
    /// var writer: SomeAsyncWriter = ...
    ///
    /// try await writer.write { outputSpan in
    ///     for item in items {
    ///         outputSpan.append(item)
    ///     }
    ///     return outputSpan.count
    /// }
    /// ```
    mutating func write<Result, Failure: Error>(
        _ body: (inout OutputSpan<WriteElement>) async throws(Failure) -> Result
    ) async throws(EitherError<WriteFailure, Failure>) -> Result

    /// Writes a span of elements to the underlying destination.
    ///
    /// This method asynchronously writes all elements from the provided span to whatever destination
    /// the writer represents. The operation may require multiple write calls to complete if the
    /// writer cannot accept all elements at once.
    ///
    /// - Parameter span: The span of elements to write.
    ///
    /// - Throws: An `EitherError` containing either a `WriteFailure` from the write operation
    ///   or an `AsyncWriterWroteShortError` if the writer cannot accept any more data before
    ///   all elements are written.
    ///
    /// ## Example
    ///
    /// ```swift
    /// var fileWriter: FileAsyncWriter = ...
    /// let dataBuffer: [UInt8] = [1, 2, 3, 4, 5]
    ///
    /// // Write the entire span to a file asynchronously
    /// try await fileWriter.write(dataBuffer.span)
    /// ```
    mutating func write(
        _ span: Span<WriteElement>
    ) async throws(EitherError<WriteFailure, AsyncWriterWroteShortError>)
}
```

### `ConcludingAsyncWriter`

```swift
/// A protocol that represents an asynchronous writer that produces a final value upon completion.
///
/// ``ConcludingAsyncWriter`` adds functionality to asynchronous writers that need to
/// provide a conclusive element after writing is complete. This is particularly useful
/// for streams that have meaningful completion states, such as HTTP response that need
/// to finalize with optional trailers.
public protocol ConcludingAsyncWriter<Underlying, FinalElement>: ~Copyable, ~Escapable {
    /// The underlying asynchronous writer type.
    associatedtype Underlying: AsyncWriter, ~Copyable, ~Escapable

    /// The type of the final element produced after writing is complete.
    associatedtype FinalElement

    /// Allows writing to the underlying async writer and produces a final element upon completion.
    ///
    /// - Parameter body: A closure that takes the underlying writer and returns both a value and a final element.
    /// - Returns: The value returned by the body closure.
    /// - Throws: Any error thrown by the body closure or encountered while writing.
    ///
    /// - Note: This method consumes the concluding async writer, meaning it can only be called once on a value type.
    ///
    /// ```swift
    /// let responseWriter: HTTPResponseWriter = ...
    ///
    /// // Write the response body and produce a final status
    /// let result = try await responseWriter.produceAndConclude { writer in
    ///     try await writer.write(data)
    ///     return (true, trailers)
    /// }
    /// ```
    consuming func produceAndConclude<Return>(
        body: (consuming sending Underlying) async throws -> (Return, FinalElement)
    ) async throws -> Return
}
```

## Alternatives considered

### Naming

We considered various other names for these types such as:

- `AsyncReader` and `AsyncWriter` alternatives:
  - `AsyncReadable` and `AsyncWritable`
- `ConcludingAsyncReader` and `ConcludingAsyncWriter` alternatives:
  - `FinalElementAsyncReader` and `FinalElementAsyncWriter`

### Async generators

Asynchronous generators might provide an alternative to the current
`AsyncSequence` and the `AsyncReader` here. However, they would require
significant compiler features and potentially only replace the _read_ side.
