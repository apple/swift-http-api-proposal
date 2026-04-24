# HTTP Client Features

| Feature | URLSession | AHC | fetch |
|---------|------------|-----|-------|
| HTTP1 | ✅ | ✅ | ✅ |
| HTTP2 | ✅ | ✅ | ✅ |
| HTTP3 | ✅ | ❌ | ✅ |
| HTTP version selection | ❌ | ✅ | ❌ |
| h2c | ❌ | ✅ | ❌ |
| Sending CONNECT requests, :protocol | ❌ | ❌ | ❌ |
| Field compression indexing strategy | ❌ | ❌ | ❌ |
| Trailers (sending, receiving) | ❌ | ✅ | ❌ |
| Request body streaming | ✅ | ✅ | ✅ |
| Bidirectional streaming | ✅ | ✅ | ❌ |
| Resumable upload | ✅ | ❌ | ❌ |
| Auto cookie storing and attaching | ✅ | ❌ | ✅ |
| Manual cookie | ✅ | ✅ | ❌ |
| Picking cookie storage | ✅ | ❌ | ❌ |
| Cookie configuration (mainDocumentURL, partition, disable cookie) | ✅ | ❌ | ❌ |
| Reading 1xx response | ✅ | ❌ | ❌ |
| Redirection | ✅ | ✅ | ✅ |
| Redirection configuration | ✅ | ✅ | ✅ |
| Custom redirection callback | ✅ | ❌ | ❌ |
| HTTP auth callback | ✅ | ❌ | ❌ |
| Custom auth scheme | ❌ | ❌ | ❌ |
| Basic auth | ✅ | ✅ | ✅ |
| Kerberos auth | ✅ | ❌ | ✅ |
| AppSSO auth | ✅ | ❌ | Safari |
| Private access token | ✅ | ❌ | Safari |
| Cleartext HTTP proxy | ✅ | ❌ | ✅ |
| HTTP CONNECT proxy | ✅ | ✅ | ✅ |
| MASQUE proxy | ✅ | ❌ | Safari |
| Oblivious HTTP relay | ✅ | ❌ | Safari |
| Proxy configuration | ✅ | ✅ | ❌ |
| Auto caching | ✅ | ❌ | ✅ |
| Picking cache storage | ✅ | ❌ | ❌ |
| Cache policy | ✅ | ❌ | ✅ |
| TLS version selection | ✅ | ✅ | ❌ |
