# Fetch HTTP Client

## Introduction
The `FetchHTTPClient` is an implementation of the Swift HTTP API and is used to make HTTP requests from Swift WASM.
It is built on top of Javascript `fetch()` API using JavascriptKit and BridgeJS.

## How to use
1. Install the latest WASM SDK from swift.org
1. Create an executable WASM target that depends on `FetchHTTPClient`
1. Build the executable target using the WASM SDK
   ```bash
   $ export HTTP_API_ENABLE_WASM=1
   $ swift sdk list
   $ swift package --swift-sdk <WASM SDK ID> js --product <executable target> --use-cdn
   ```
