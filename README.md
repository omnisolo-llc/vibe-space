# Vibe Space & VibeProtocol

An open protocol and framework for user-vibed UI mods and temporary agent-generated views across opt-in host applications. **MIT licensed.**

Vibe Space lets users describe what they want in plain language and run small, sandboxed programs (**vibes**) inside dedicated host panels or inline inside AI agent replies. Host applications remain strictly in control: vibes never get ambient network, filesystem, storage, or DOM access, and sensitive identifiers can be **sealed** so a vibe can group, sort, and compare records without ever seeing the underlying values.

```text
User wish or agent prompt
         ↓ manifest + synthetic sample data (never live data)
Sandboxed vibe (Wasm guest / isolated Worker)
         ↓ pure JSON { state, view } + sealed handles
Host permission label (Reads / Shows / Cannot)
         ↓ host-owned rendering + lifecycle store
Vibe Space panel (⋯ management) & inline Temporary agent embeds
```

## Trust Boundaries & Key Capabilities

- **Opt-in host manifest**: Each host explicitly declares offered capabilities (`public` or `sealed` fields, synthetic `sample` rows, optional `status()` health checks) and a plain-language `notOffered` list.
- **Generated permission labels**: Before running on live data, the host deterministically builds a **Reads / Shows / Cannot** label from `vibe.needs` and the host manifest. Same-capability edits show `"No new permissions."`; expanded capabilities display a permission diff; `#vibe=...` share tokens carry no grants.
- **Sealed values ("show without seeing")**: Fields marked `'sealed'` cross the sandbox boundary as random opaque handles (`{ "sealed": "h_..." }`). The vibe never sees the real string; the host resolves handles at draw time with a lock indicator, and forged handles render empty.
- **Dedicated panel & inline agent embeds**: Hosts mount `VibeSpacePanel` for wish authoring, sample previews, gallery vibes, and link imports, plus `VibeEmbedCard` inside agent replies (`Temporary` badge, `Inspect` ledger, and **Pin to Vibe Space**).
- **Host-isolated `⋯` lifecycle management**: Every installed vibe has an `⋯` dropdown menu (`Edit…` via wish remix or live code with sandbox preview, `Rename`, `Inspect`, `Share…`, `Pause`/`Resume`, `Pin to top`/`Unpin`, `Move up`/`Move down`, `Revert`, and `Delete` with inline **Undo**). Custom titles and notes stay solely on the host record and never enter sandbox input or share links.
- **Graceful source degradation (`live | offline | revoked | missing`)**: When a host data source disconnects or access is revoked, bound cards preserve their last known view in a stale state (or display a calm unavailable notice when no prior view exists), offer **Retry**, **Preview sample**, or **Edit**, and recover automatically when the source returns.
- **Import-free Wasm & browser Worker isolation**: Native packages run as import-free `wasm32` guests verified with Ed25519 signatures and capability/revision checks (`runtime`), while browser hosts execute vibes inside an isolated Worker (`web/worker.js` / sandboxed frame).

## Packages & Repository Layout

| Path | Purpose |
| --- | --- |
| `runtime` | Rust Wasm interpreter, Ed25519 signature verification, `PackageStore`, activation revisions, resource limits |
| `dart` | `package:vibe_space`: `VibeProtocolHost`, `VibeSealedHandle`, `VibePermissionLabel`, `VibeSpaceStore`, `VibeReadLedger`, `VibeHostRegistry`, schemas, and effect snapshots |
| `flutter` | `package:vibe_space_flutter`: `VibeView`, `VibeCanvasView`, `VibeSpacePanel` (`⋯` lifecycle menu, edit/history, source banners), `VibeEmbedCard`, and generated browser worker source |
| `demo` | Zero-dependency interactive browser demo of VibeProtocol across two unrelated hosts (**LeapTerm** and **Moments**) |
| `sdk/rust`, `sdk/c` | Guest ABI helpers and compiling examples (`examples/hello-rust`, `examples/hello-c`) |
| `sdk/typescript` | JSON protocol types (`index.d.ts`), `SealedHandle` / `ViewTone`, and package verification helpers (`index.mjs`) |
| `web/worker.js` | Disposable browser worker with no Wasm imports |
| `tools` | `vibe.mjs` CLI (`init`, `build`, `keygen`, `pack`, `inspect`) and `sync-worker.mjs` |
| `skills/vibe-space` | Instructions for AI-assisted vibe and mini-app authoring |

See [VibeProtocol Contract](docs/vibeprotocol.md), [Compatibility Adapters](docs/compatibility-adapters.md), [Protocol v1 (Wasm ABI)](docs/protocol.md), [Host Integration](docs/hosts.md), and [Security Boundary](docs/security.md).

## Multi-Language & Universal UI Compatibility Adapters

Vibe Space supports every major guest language, UI toolkit, and human language behind the same capability and sealed-handle trust boundary:

- **All guest & host languages**: Primary `vibe_alloc` / `vibe_invoke` Wasm exports (alongside `omni_` / `leap_` / `leapterm_` aliases) work from Rust, C/C++, TinyGo, Zig, AssemblyScript, and other import-free `wasm32` toolchains; host kits and adapters ship in **Rust** (`runtime`), **TypeScript / JavaScript** (`sdk/typescript/adapters.mjs`, `demo/kit`), and **Dart / Flutter** (`dart`, `flutter`).
- **Inbound UI dialect adapters**: `adaptExternalUi` / `VibeUiCompatibilityAdapter.adapt` / `adapt_external_ui` convert **A2UI** (`surfaceUpdate` adjacency lists & nested components), **Adaptive Cards**, and **Markdown** into validated canonical `VibeView` trees while preserving `{ "sealed": "h_..." }` handles.
- **Outbound UI toolkit adapters**:
  - **React, Preact, Vue 3, Solid, SSR**: `renderWithH(h, view, opts)` (zero `document` dependency).
  - **Angular, Svelte, Lit, HTMX, Plain HTML**: Web Components `<vibe-view>`, `<vibe-embed>`, and `<vibe-space>` via `defineVibeWebComponents`.
  - **Flutter**: `VibeWidgetAdapter.material()`, `.cupertino()`, and `.custom(...)` per-node builders.
  - **SwiftUI, Jetpack Compose, Qt, GTK, WinUI, React Native**: `resolveViewTree` / `resolveVibeViewTree` / `resolve_view_tree` headless handle-resolved IR (forged handles render empty).
  - **Terminal / TUI, Markdown & Escaped HTML**: `renderToTerminal`, `renderToMarkdown`, and `renderToHtmlString`.
- **All human languages (i18n, UTF-8 & RTL)**: Built-in locale packs (`en`, `zh`, `ja`, `ko`, `es`, `fr`, `de`, `ar` with `rtl: true`), automatic RTL layout direction, and full UTF-8 CJK/Arabic/emoji safety in share tokens and host metadata.

## Quickstart

### 1. Run the interactive browser demo

No build step, `npm install`, or external network access is needed:

```sh
cd demo
python3 -m http.server 8765
```

Open `http://localhost:8765/` (or open `demo/index.html` directly from disk via `file://`).

### 2. Integrate in a Dart / Flutter host

Add `vibe_space` (pure Dart) or `vibe_space_flutter` (Flutter widgets), wrap your app data in a `VibeProtocolHost` with declared `VibeCapability` definitions, and render `VibeSpacePanel` and `VibeEmbedCard`:

```dart
final host = VibeProtocolHost(
  id: 'my-host',
  name: 'MyApp',
  capabilities: [
    VibeCapability(
      name: 'metrics.cpu',
      title: 'CPU usage of your servers',
      fields: {'server': 'sealed', 'cpu': 'public'},
      sealedNote: 'server names stay sealed',
      sealedCannot: 'See server names or addresses',
      status: () => feedConnected
          ? const VibeSourceStatus.live()
          : const VibeSourceStatus.offline('Telemetry feed disconnected'),
      read: () => liveRows,
      sample: sampleRows,
    ),
  ],
  notOffered: const ['Run commands', 'Use the internet'],
);
```

### 3. Build and verify a signed Wasm guest

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

For C guests, run `node tools/vibe.mjs build examples/hello-c c` with Clang and `wasm-ld` installed. To scaffold a new guest project, run `node tools/vibe.mjs init /path/to/new-project rust` (or `c`).

## Verification Suites

```sh
cargo test --workspace
node --test tests/*.test.mjs
node tools/sync-worker.mjs --check
(cd dart && dart test)
(cd flutter && flutter test)
```

Browser demo hostile and end-to-end checks live in `demo/checks/hostile.mjs` and `demo/checks/story.mjs`. Changes to `web/worker.js` require running `node tools/sync-worker.mjs`.

## License

MIT License — see [LICENSE](LICENSE).
