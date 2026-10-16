# Security boundary

The untrusted executable type is WebAssembly. Downloaded Dart, JavaScript, native libraries, WASI, and guest imports are not supported. Native execution uses Wasmi with 5 million fuel, a 32 MiB linear-memory limit, one memory, one table with at most 4,096 entries, enforced compiler limits, and four concurrent execution/compilation slots per process. Browser invocations use a disposable worker, a two-second deadline including compilation/start, bounded module declarations, and memory/table caps.

Module bytes are limited to 16 MiB, request/result JSON to 1 MiB, and effects to 32 per round. The host limits chained rounds. Signed packages are installed disabled. Grants and activation revisions are host-owned. A caller-provided confirmation flag grants no authority. Guests never receive direct host handles, vault secrets, or arbitrary file access.

Signed code remains untrusted: a signature identifies a publisher; it does not certify safety. Wasm isolates guest memory and instructions. The exposed API handler is a separate, trusted boundary: review it for authorization, exact input validation, resource scope, cancellation, and response leakage. Network and terminal handlers need their own controls. Trusted native providers and host-internal Dart callbacks are not Wasm sandboxes.

The package store retains LeapTerm's legacy byte-masking format for compatibility. Masking is not encryption with a secret key and does not protect code from the machine owner. Signature verification, interpreter limits, and host authorization provide the relevant boundaries.

This is an experimental proof of concept. It has focused regression tests, not a security audit or a production hardening guarantee. Report vulnerabilities privately through GitHub's security advisory reporting for this repository; do not include credentials or production exploit payloads in public issues.
