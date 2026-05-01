# WASM HTTP Client

## Introduction
This is an example WASM binary that uses the `FetchHTTPClient` (built on Javascript `fetch()` API) to make HTTP requests
from Swift.

## How to use
1. Install the latest WASM SDK from swift.org
1. Build the WASMClient using the WASM SDK
   ```bash
   $ swift sdk list
   $ swift package --swift-sdk <WASM SDK ID> js --product WASMClient --use-cdn
   ```
1. Serve the *root of this repository* using Python
    ```bash
    $ python -m http.server
    ```
1. In your browser, visit `http://localhost:8000/Examples/WASMClient`
1. The page will prompt you for a URL, HTTP method and (optional) request body.
1. The page will then make the HTTP request and collect the response.

Note: You can validate the network activity using your browser's DevTools Network Inspector.

Note: To test the client extensively, you may want to temporarily disable CORS validation on the browser, allowing you to
make requests to domains other than localhost.
