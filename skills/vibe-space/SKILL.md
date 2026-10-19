---
name: vibe-space
description: Build or edit a Vibe Space Wasm mini-app or UI mod using an embedding app's explicit API catalog. Use for plugin authoring, not changes to the host application's shipped layout.
---

Build a small import-free Wasm guest. Read the host's exposed API catalog and requested behavior before selecting capabilities. For LeapTerm, start from `examples/hello-rust`; the PoC uses the existing Quick Jump slot and `leapterm.ui` v1 for reversible accent tokens.

Read [the protocol](../../docs/protocol.md) for the ABI and JSON shapes. Read [host integration](../../docs/hosts.md) when a host API must be added; exposing an API is a host code change, never a guest privilege.

- Use `sdk/rust` or `sdk/c`; export only the documented memory/allocator/invoke ABI and build without WASI or imports.
- Discover APIs from `host.apis`. Request the exact `api:<name>` capability and API version. Treat missing APIs or grants as unavailable. Do not invent APIs or use network/terminal access as a permission bypass.
- Return declarative views and `host.call` proposals. Persist transient state in `state`. Consume `host.results` without replaying the same effect. Give effects stable unique IDs within the batch.
- UI mods use allowed host tokens and callbacks. Do not inject scripts, HTML, CSS, native libraries, or downloaded Flutter code. Keep the host's navigation and review controls intact.
- Use `vibe.canvas` v1 (`api:vibe.canvas`) when a mini-app or AI agent needs to open an interactive Vibe Canvas (`title`, `format`, `content`, optional `canvasId`, `taskId`, `wasmBase64`, `jsGlue`, `layout`). Supported `format` values are `markdown` (Markdown & Mermaid), `vibe_ui` (declarative `VibeView` JSON), `html` (sandboxed HTML), and `wasm` (sandboxed WebAssembly mini-app).
- Build with `node tools/vibe.mjs build PATH rust|c`. Use `keygen`, `pack`, and `inspect` from that tool for a signed package. Store signing keys outside source control and obtain the trusted publisher key separately from the package.
- Exercise install-disabled, grant, open, deny, approve, disable, and restoration in the actual first host. A standalone guest execution proves ABI behavior only. Run focused tests for new authorization or effect behavior.

Keep this PoC small. Do not redesign the host UI, add automatic activation, or expand the release scope to ship a mini-app demonstration.
