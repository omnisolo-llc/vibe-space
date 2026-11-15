# Security Boundary & WeChat Mini Program Parity

Vibe Space enforces a defense-in-depth security model modeled on the **WeChat Mini Program Dual-Layer Architecture** (`AppService` isolated logic sandbox + `Skyline` native declarative view engine) for **Vibe Mini Programs** (and `vibe-snippet` aliases), extended with **VibeProtocol Sealed Handles** ("show without seeing") and **Ed25519-verified WebAssembly guests**.

## 1. WeChat Mini Program Security Standard Parity Matrix

| Security Pillar | WeChat Mini Program Standard | Vibe Space Enforcement |
| --- | --- | --- |
| **Dual-Thread / Dual-Layer Isolation** | Logic (`AppService` JSCore/V8) is separated from View (`WebView` / `Skyline`); logic has zero DOM access | Layer 1 (`AppService` Worker / pure-Dart interpreter / Wasmi `wasm32`) is air-gapped from Layer 2 (`Skyline` native `VibeView` / `CustomPaint` / DOM renderer); only JSON `setData` & `{ state, view }` cross the bridge |
| **Zero Ambient DOM, Network, or Storage** | No `window`, `document`, arbitrary `eval`, or undeclared `wx.request` origins | `window`, `document`, `fetch`, `XMLHttpRequest`, `WebSocket`, `WebTransport`, `EventSource`, `RTCPeerConnection`, `Worker`, `ServiceWorker`, `BroadcastChannel`, `localStorage`, `indexedDB`, `caches`, `cookieStore`, `importScripts`, `postMessage`, `eval`, `Function`, `Function.prototype.constructor`, and dynamic `import()` are statically rejected and dynamically locked (`writable: false, configurable: false`) |
| **Scoped Declarative Templates (`WXML` / `VXML`)** | Side-effect-free `{{binding}}`, `wx:if`, `wx:for`, `data-*` `dataset`, and named event handlers | `compileTemplate` / `compileVibeTemplate` cap depth (`<= 16`), expression length (`<= 2,048`), loop count (`<= 200`), and block `__proto__`, `constructor`, `prototype`, `toString`, `valueOf` in scope paths, loop variables, and `bindtap` / `dispatchEvent` (`Object.hasOwn`) |
| **Scoped Style Sandbox (`WXSS`)** | No external CSS exfiltration or host-overlay hijacking | `normalizeStyleTokens` / `normalizeVibeStyleTokens` allow only bounded numeric layout props (`0..2048`) and hex/semantic palette colors; CSS `url(...)`, `expression(...)`, `position: fixed`, and high `z-index` are stripped |
| **Bounded `setData` & Frame Budgets** | Incremental path patches with size & frequency limits | `applySetData` / `applyVibeSetData` enforce `<= 64 KiB` per patch, `<= 30/s` sliding-window rate limit, array index bounds, prototype-pollution rejection, `<= 1,024` view nodes, and `<= 2,000` `canvas` draw commands per frame |
| **2D Canvas & Render Exfiltration Defense** | Scoped `<canvas>` context without cross-origin tainting | `canvas` commands validate `#RGB`/`#RRGGBB`/`#RRGGBBAA` and semantic palette colors plus strict SVG `path` syntax (`SAFE_SVG_PATH_RE`), blocking `fill="url(https://...)"` paint-server exfiltration; `renderToTerminal` / `render_terminal` strip ANSI/CSI/OSC 52 control escapes |
| **Explicit Capability Manifest & Review** | Declared `app.json` permissions + user consent prompt | Declared `needs` checked against `host.manifest()`; deterministic **Reads / Shows / Cannot** permission label + diff approval on capability expansion; `#vibe=...` share links carry zero grants |
| **Package Signing & Quota Isolation** | Signed `.wxapkg` packages + per-mini-program storage quota | Ed25519 manifest + SHA-256 Wasm module verification (`verify` / `verifyPackage`), host-owned activation revisions, `<= 4,096` sealed handles, and `<= 2 MiB` per-host installed Vibe-Snippet quota |
| **Privacy-Preserving Identifiers** | OpenID / UnionID opaque per-app tokens | **Sealed Handles (`{ "sealed": "h_..." }`)**: sensitive fields never enter guest memory or LLM guidance prompts; resolved only by the host at draw time, while forged handles render empty |

## 2. WebAssembly & Browser Worker Resource Limits

- **Native Wasm (`runtime`)**: Wasmi interpreter with no WASI and zero guest imports; `5,000,000` fuel per call, `16 MiB` max module bytes, `32 MiB` linear memory limit, 1 memory, 1 table (`<= 4,096` entries), `1 MiB` request/result JSON cap, `<= 32` effects per round, and 4 concurrent execution/compilation slots per process.
- **Browser Worker (`web/worker.js` & `demo/kit/vibekit.js`)**: Disposable Worker inside `sandbox="allow-scripts"` (never `allow-same-origin`, `allow-popups`, `allow-top-navigation`, or `allow-modals`) with `default-src 'none'; connect-src 'none'` CSP, locked `Function`/`AsyncFunction`/`GeneratorFunction` constructors post-compile, locked `self.postMessage` channel, and strict boot/call timeouts (`1s`–`4s`).
- **Trigger ReDoS Protection**: Conditional `when` triggers cap combinator depth at `16`, regex pattern length at `256` characters, and reject nested quantifiers (such as `(a+)+`) and backreferences (`\1`..`\9`).
- **LLM Guidance System Prompt**: `buildVibeGenerationSystemPrompt` / `build_generation_system_prompt` serializes only sanitized `host.manifest()` sample schemas (replacing `'sealed'` sample values with `{ "sealed": "h_sample_01" }` and never invoking `read()`) and isolates `userWish` / `existingVibe` inside prompt-injection defense fences.

## 3. Responsible Disclosure

Signed or validated code remains untrusted: signatures identify a publisher rather than certifying business-logic safety, and host API handlers must independently enforce authorization, input validation, and resource scope. Report vulnerabilities privately through GitHub's security advisory reporting for this repository; do not include credentials or exploit payloads against live services in public issues.
