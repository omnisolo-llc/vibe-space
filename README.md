# Vibe Space

An experimental framework for Wasm mini-apps and UI mods. LeapTerm is the first host. MIT licensed.

This is a proof of concept: install a signed Wasm package, explicitly grant an exposed API, review a proposed action, and apply a reversible accent change in LeapTerm. It uses LeapTerm's existing Extensions and Quick Jump flow. Installing the framework adds no navigation or layout changes to the application.

Guests run without WASI or host imports. They receive JSON and return declarative views and API requests. Application developers register versioned APIs with input/output schemas, permission names, and trusted handlers. A mod changes host UI through an approved API such as `leapterm.ui`; it cannot inject JavaScript, arbitrary CSS, or replace Flutter widgets.

```text
Rust / C / another import-free Wasm language
             ↓ signed .wasm + manifest
       isolated Wasm invocation
             ↓ JSON proposals
     host grants + exact action review
             ↓ explicit API
     application data / allowed UI tokens
```

## Build an example

Build and verify a signed Wasm guest with the included tools:

```sh
rustup target add wasm32-unknown-unknown
node tools/vibe.mjs build examples/hello-rust rust
mkdir -p /tmp/vibe-space-demo
node tools/vibe.mjs keygen /tmp/vibe-space-demo/publisher
node tools/vibe.mjs pack examples/hello-rust/manifest.json \
  examples/hello-rust/build/module.wasm /tmp/vibe-space-demo/publisher.pem \
  /tmp/vibe-space-demo/hello-rust.json
node tools/vibe.mjs inspect /tmp/vibe-space-demo/hello-rust.json /tmp/vibe-space-demo/publisher.pub
cargo run -p vibe-space-runtime --example run -- \
  /tmp/vibe-space-demo/hello-rust.json /tmp/vibe-space-demo/publisher.pub open
```

The native example runner prints proposals; application effects are executed by the host after its own checks. Keep the `.pem` key private. The `.pub` file is the publisher key the installer must verify separately from the package.

For C, use `node tools/vibe.mjs build examples/hello-c c` with Clang and wasm-ld installed. For a new project, use `node tools/vibe.mjs init /path/to/new-project rust` (or `c`). The template references the local SDK checkout.

## What is here

| Path | Purpose |
| --- | --- |
| `runtime` | Rust interpreter, signature verification, package store, activation revisions, resource limits |
| `dart` | Explicit API registry, schema validation, immutable effect snapshots |
| `flutter` | Host-rendered declarative UI and generated browser worker source |
| `web/worker.js` | Disposable browser worker with no Wasm imports |
| `sdk/rust`, `sdk/c` | Guest ABI helpers and compiling examples |
| `sdk/typescript` | JSON protocol types and package verification helpers |
| `skills/vibe-space` | Instructions for AI-assisted mini-app authoring |

See [the protocol](docs/protocol.md), [host integration](docs/hosts.md), and [security boundary](docs/security.md).

## Scope and portability

The ABI is language independent. Rust and C examples are implemented; other languages need an import-free `wasm32` build exporting this ABI. Dart/Flutter hosts cover browser, desktop, and mobile code paths. This initial PoC validates Linux native execution and Chromium with LeapTerm. Other OS targets are design targets, not a tested support promise.

LeapTerm's PoC exposes only its existing Quick Jump placement. Other placement names are reserved in the protocol for future hosts; adding them must not change LeapTerm's release UI. `leapterm.ui` supports a small allowlist of accent tokens, with no persistence or automatic startup. Filesystem, vault, storage, and arbitrary DOM access are unavailable.

## Focused checks

```sh
cargo test --workspace
node --test tests/*.test.mjs
node tools/sync-worker.mjs --check
(cd dart && dart test)
(cd flutter && flutter test)
```

Changes to `web/worker.js` require `node tools/sync-worker.mjs`. SDKs and APIs are experimental and may change before a stable release. Contributions should keep the example small and protect the host's existing release behavior.
