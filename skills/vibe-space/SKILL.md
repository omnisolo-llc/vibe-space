---
name: vibe-space
description: Generate, edit, or audit a Vibe Space mini program (vibe-snippet alias), conditional view, or Wasm guest using a host's sanitized VibeProtocol manifest and WeChat Mini Program security boundaries.
---

# Vibe Space Authoring & Generation Guide

Use this skill whenever generating, remixing, or auditing a **Vibe Mini Program** (`defineMiniProgram`, `defineVibeSnippet` alias, `function invoke(input)`, declarative `VXML`/`VibeView`, or `wasm32` guest) for an embedding host application.

Read [VibeProtocol Contract](../../docs/vibeprotocol.md), [Security Boundary](../../docs/security.md), [Protocol v1 (Wasm ABI)](../../docs/protocol.md), and [Host Integration](../../docs/hosts.md) for wire contracts.

## 1. Build the Guidance System Prompt First

When prompting an LLM to generate or remix a Vibe Mini Program for a user wish, **always** construct the system prompt via the host's built-in prompt builder so live user data and live sealed values never enter the LLM context:

- **Dart / Flutter**: `host.buildGenerationSystemPrompt(userWish: wish, existingVibe: current, target: VibeGenerationTarget.auto)` (or `buildVibeGenerationSystemPrompt(manifest, options: ...)`).
- **TypeScript / Node**: `buildVibeGenerationSystemPrompt(hostOrManifest, { userWish, existingVibe, target })` from `sdk/typescript/index.mjs`.
- **Browser Host Kit**: `host.buildSystemPrompt({ userWish, existingVibe, target })` or `VibeKit.buildSystemPrompt(manifest, options)`.
- **Rust**: `vibe_space_runtime::prompt::build_generation_system_prompt(&manifest_json, &options)`.

Prompt-builder guarantees:
1. Serializes **only** sanitized `host.manifest()` (`sample` metadata with `'sealed'` sample fields replaced by synthetic `{ "sealed": "h_sample_01" }` handles — `read()` is never called).
2. Strips any non-manifest properties (internal state, handle tables, user titles/notes).
3. Isolates `userWish` and `existingVibe` inside untrusted XML fences with explicit prompt-injection neutralization.

## 2. WeChat Mini Program Dual-Layer Security Standard (Mandatory)

Generated Vibe-Snippets MUST obey the dual-layer `AppService` + `Skyline` architecture:

- **Layer 1 (`AppService` Air-Gapped Logic Sandbox)**:
  - Preferred format: `defineMiniProgram({ data, template, onLoad, onShow, onHide, onDataUpdate, methods })` (or `defineVibeSnippet(...)` alias) using incremental `this.setData(patch)` (`<= 64 KiB` per patch, `<= 30/s` rate limit).
  - Pure stateless/stateful worker format: `function invoke(input) { return { state, view }; }`.
  - Binary format: import-free `wasm32-unknown-unknown` exporting `memory`, `vibe_alloc`, and `vibe_invoke` (`sdk/rust` or `sdk/c`, built via `node tools/vibe.mjs build PATH rust|c`, `<= 16 MiB` module, `<= 32 MiB` memory, fuel-metered).
  - **Zero ambient globals**: NEVER reference `window`, `document`, `globalThis`, `self`, `top`, `parent`, `fetch`, `XMLHttpRequest`, `WebSocket`, `EventSource`, `WebTransport`, `RTCPeerConnection`, `Worker`, `SharedWorker`, `ServiceWorker`, `BroadcastChannel`, `navigator`, `location`, `localStorage`, `sessionStorage`, `indexedDB`, `caches`, `cookieStore`, `importScripts`, `postMessage`, `open`, `alert`, `confirm`, `prompt`, `eval`, `Function`, `WebAssembly`, `Proxy`, `Reflect`, dynamic `import()`, or `__proto__` / `constructor` / `prototype`.
- **Layer 2 (`Skyline` Declarative Native View Engine)**:
  - Emit only canonical `VibeView` / `VXML` JSON nodes: `column`, `row`, `card`, `heading`, `text`, `badge`, `stat`, `bar`, `sparkline`, `canvas`, `table`, `divider`, `progress`, `button`, `action`, `input`, `checkbox`, `option_group` (`<= 16` depth, `<= 1,024` nodes).
  - Scoped `WXSS` `style` tokens allow only bounded numeric layout properties (`padding`, `gap`, `borderRadius`, `borderWidth`, `fontSize`, `width`, `height`, `flex`, `opacity`) and safe `#RGB`/`#RRGGBB`/`#RRGGBBAA` or semantic palette colors (`accent`, `ok`, `warn`, `danger`, `surface`, `card`, `border`, `text`, `muted`, `transparent`). Never use CSS `url(...)`, `position: fixed`, or external assets.
  - `canvas` 2D vector draw lists (`clear`, `rect`, `rrect`, `circle`, `arc`, `line`, `path`, `polygon`, `bars`, `text`) are capped at `<= 2,000` commands per frame and accept only hex or semantic palette colors (never SVG `url(...)` paint servers).

## 3. Capabilities, Sealed Handles & Conditional `when` Triggers

- **Least privilege (`needs`)**: Request only capability names declared in `host.manifest().capabilities` (or `[]` for portable Vibe-Snippets). Never request items listed in `notOffered`.
- **Sealed values (`{ "sealed": "h_..." }`)**: Fields marked `"sealed"` arrive as opaque handle objects. Pass handle objects directly into view text/label/cell slots so the host resolves them at draw time with a lock indicator. Never coerce handles to strings (`handle + ""`), slice handle IDs, or invent forged handles (`{ "sealed": "h_..." }` not issued by the host renders blank).
- **Safe `when` triggers**: Keep `when` combinators `<= 16` depth; regex matchers must be `<= 256` chars with zero nested quantifiers (such as `(a+)+`) or backreferences.

## 4. Verification Checklist

Before shipping changes to a Vibe-Snippet or host integration, verify:
1. Permission label (`Reads / Shows / Cannot`), sample preview, and live/offline/revoked source states work cleanly.
2. Malicious inputs (prototype pollution, `constructor` event handlers, sandbox global escapes, CSS/SVG `url(...)` exfiltration, forged sealed handles, ReDoS trigger regexes, and terminal ANSI/OSC escapes) fail closed.
